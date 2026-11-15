# indi-spec

Hub repo for xsnrg's INDI-family COPR projects — documentation and tooling only.
**No specs live here anymore**: COPR builds all four projects straight from
upstream repos (indilib/indi, indilib/indi-3rdparty, rlancaste/stellarsolver,
knro/ekosdebugger).

- `AGENTS.md` — full operations handoff: project map, rebuild workflow, spec
  fix-classes to preserve, rpm/Fedora/COPR gotchas. Read it first.
- `check-deps.sh` — BuildRequires canary; checks every BR in given specs still
  resolves on each target Fedora release before submitting a COPR wave.

Historical: this repo used to host `libindi.spec` for the libindi-bleeding COPR
package (the `CMakeLists.txt.patch` dated that effort). Upstream's own
`spec/libindi.spec` has been the build source since the Nov 2026 fix campaign
(indilib/indi#2534); the local copies were removed as dead weight.
