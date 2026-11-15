# AGENTS.md — INDI/StellarSolver/EkosDebugger COPR operations

Handoff knowledge from the Nov-2026 COPR fix campaign (all four upstream PRs merged,
everything green, all sources on upstream master). Read this before touching these
projects.

## The four COPR projects

| COPR project (xsnrg/) | COPR package(s) | Spec source (upstream) | Chroots |
|---|---|---|---|
| `libindi-bleeding` | `indi` | `indilib/indi:master` → `spec/libindi.spec` | f43/44/45/rawhide × x86_64+aarch64 (8) |
| `indi-3rdparty-bleeding` | 68 pkgs (43 `indi-*` drivers, 25 `lib*`) | `indilib/indi-3rdparty:master` → `<pkg>/<pkg>.spec` | same 8 |
| `stellarsolver-bleeding` | `stellarsolver` | `rlancaste/stellarsolver:master` → `spec/stellarsolver.spec` | f43/44/45/rawhide ×2 + epel-8 ×2 (10) |
| `ekosdebugger` | `ekosdebugger` | `knro/ekosdebugger:master` → `ekosdebugger.spec` | f43/44/45/rawhide/epel-8 x86_64 (5) |

Upstream PRs that carried the fixes: indilib/indi#2534, indilib/indi-3rdparty#1424,
rlancaste/stellarsolver#186, knro/ekosdebugger#7. knro merges PRs personally, often
within hours.

**COPR pulls specs straight from the upstream repos.** The old `xsnrg/*-spec`
dist-git repos are dead — nothing builds from them; local clones were removed
Nov 15 2026 (bundles in `~/indi-fix/archive/`). GitHub-side spec repos and the
xsnrg forks can be archived too.

## Manual rebuild rules (the workflow that works)

1. Fix root causes **upstream via PR**, not by pointing COPR at forks. If a fork
   branch must be used temporarily, snapshot each package's `source_dict` first
   (see `~/indi-fix/copr-source-snapshot.json` for the format) and revert promptly.
2. Build `lib*` packages first, **wait for terminal states AND repo publication**,
   then submit drivers. `~/indi-fix/revert_to_upstream.py --rebuild` implements the
   whole phased sequence (core → libs blocking → drivers) and can be reused any time
   the whole stack needs a clean rebuild.
3. Only ONE true build-time lib→driver dependency exists in indi-3rdparty:
   **indi-apogee ← libapogee-devel**. All other drivers compile the vendor SDK
   sources from the monorepo tarball directly; the `lib*` packages exist only to
   ship runtime `.so`s. So normally drivers can go in any order — except apogee.
4. COPR repo publication lags chroot completion by ~5 minutes. Resubmitting a
   driver too soon after its lib finishes fails with `No match for argument:
   lib<foo>-devel` — that is a race, just resubmit.
5. Keep the queue lean: cancel queued-but-unstarted builds before submitting a
   new wave (`build_proxy.cancel(id)`, one at a time).
6. Canary first: `./check-deps.sh [specs...]` in this repo checks every
   `BuildRequires` still resolves on each target Fedora release
   (`RELEASES="44 rawhide" ./check-deps.sh ../indi-3rdparty/*.spec`).

## Fix classes (what upstream specs now contain — preserve these in future edits)

1. **Stamp-file Release** instead of `%(date)`: `%(test -f .release-stamp || date -u +%Y%m%d%H%M%S > .release-stamp; cat .release-stamp)`.
   `%(date)` re-evaluates on every rpm parse, which breaks mock's SRPM re-parse loop.
2. **No dead BuildRequires** (libfli-devel was dropped; it's gone from f44+).
3. **Modern cmake macros**: `%cmake` / `%cmake_build` / `%cmake_install`. f44's
   cmake-rpm-macros 4.3 is Ninja/out-of-source and **ignores the
   `__cmake_in_source_build` hatch** — in-source builds cannot be salvaged,
   they must be modernized.
4. **Explicit `BuildRequires: gcc` + `gcc-c++`** — Fedora 44+ removed implicit
   toolchains (symptom: `CMAKE_CXX_COMPILER not set`).
5. **Platform gates via conditional `ExcludeArch`** (reports as COPR `skipped`, not
   `failed`): `indi-ahp-xc` builds fedora≤43 only (libahp-xc retired from f44+);
   `indi-libcamera` skips fedora<44/rhel<9 (no rpicam-apps) and fedora≥46/rawhide
   (`properties::PixelArraySize` removed from libcamera API, driver not ready);
   non-aarch64 gets `-DDISABLE_RPI_FEATURES` through a cmake `-C` **cache-init
   script** (not a flag list).
6. **libapogee has a real `%package devel`** (runtime/devel split). It was the only
   lib missing one — f43 only worked because the retired distro
   `indi-3rdparty-libapogee-devel` provided the name.
7. **StellarSolver builds Qt5** (`-DUSE_QT5=ON` + qt5-qtbase-devel) on purpose —
   keeps kstars-bleeding compatibility. Don't "modernize" it to Qt6 silently.

## rpm / Fedora facts worth remembering

- rpm 4.14 (el8) **rejects non-standard `%changelog` month spellings**
  (`June` invalid, `Jun` valid); f43+ rpm tolerates anything.
- `%{?fedora}` is also set on EPEL — gate EPEL with `%{?rhel}` awareness.
- `Exit: 0` inside `%build` does not work; use conditional ExcludeArch instead.
- Bare containers need `rpm-build redhat-rpm-config` before `rpmspec`/`rpmbuild -bs`
  smoke tests work.
- Fedora f44/45/rawhide lack: libfli, all distro INDI/ahp driver packages incl.
  `indi-3rdparty-libapogee*`. f43 still has them (that masked the libapogee gap for
  years). f43's COPR repo accumulates old builds — absence there ≠ never built;
  grep `primary.xml` `<name>` elements, not substrings (requires are `rpm:entry`).

## COPR API / CLI gotchas

- **Use the API/CLI, not the web UI** (Anobis bot-protection breaks scraping).
  Token: `~/.config/copr`, section `[copr-cli]`. python-copr:
  `Client.create_from_config_file(os.path.expanduser('~/.config/copr'))`.
- Re-point a package: `package_proxy.edit(owner, proj, pkg, source_type='scm',
  source_dict={...})`. **Always print the resulting `committish`/URL and verify it
  points where you think before theorizing about spec causes** (this burned a whole
  debugging cycle on ekosdebugger once).
- `package_proxy.delete` fails while builds run — cancel first.
- `build_proxy.get_list(owner, project)` needs both args.
- Submit one package across chroots:
  `copr-cli build-package <proj> --name <pkg> --nowait` (one build, all enabled chroots).
- Build logs: `https://download.copr.fedorainfracloud.org/results/xsnrg/<proj>/<chroot>/<id>-<pkg>/builder-live.log.gz`
  — log dir is `<id>-<pkg>` with **no zero-padding**.

## Where things live

- `~/indi-fix/STATUS.md` — final campaign record (scoreboard: 71 pkgs, 549 builds,
  0 failures; merge timestamps; cleanup log).
- `~/indi-fix/` — kept: PR/comment bodies, `copr-source-snapshot.json`,
  `revert_to_upstream.py`, build-id lists, `wave-plan.json` (lib/driver dep map).
- `~/indi-fix/archive/` — git bundles of every deleted repo (all refs) + patches of
  unpushed local commits (rtl-sdr/usbfs spec edits from the 1.8.8 era in
  `patches/`) + snapshots of dirty working files. `git bundle unbundle` or
  `git fetch <bundle> refs/...` to recover.
- `check-deps.sh` (this repo) — BuildRequires canary described above.
- Historical PR/issue archaeology: the four PRs listed at the top contain the full
  root-cause writeups in their descriptions and comments.
