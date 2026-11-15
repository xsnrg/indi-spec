#!/usr/bin/bash
# check-deps.sh — dependency churn canary for the INDI COPR projects.
#
# Fedora renames and retires packages between releases (e.g. libfli-devel
# was replaced by indi-3rdparty-libfli-devel, which itself was later
# retired). A dead BuildRequires kills every COPR build for that release,
# so check them all *before* submitting a batch of builds.
#
# Usage:
#   ./check-deps.sh [spec ...]        # default: *.spec in this directory
#   RELEASES="44 rawhide" ./check-deps.sh ../indi-3rdparty-spec/*.spec
#
# Environment:
#   RELEASES  space-separated Fedora releases to check (default: active
#             stable releases + rawhide)
#
# Exit status: 0 = all deps resolve everywhere; 1 = at least one problem.

set -u

RELEASES="${RELEASES:-43 44 45 rawhide}"
specs=("$@")
if [ ${#specs[@]} -eq 0 ]; then
    mapfile -t specs < <(printf '%s\n' ./*.spec)
fi

fail=0

# Expand BuildRequires with rpmspec (handles macros and shell expansions
# without building anything).  A scratch topdir keeps the stamp file written
# by the dynamic Release line out of ~/rpmbuild.
collect_deps() {
    local tmpdir spec
    tmpdir=$(mktemp -d)
    for spec in "${specs[@]}"; do
        rpmspec -q --buildrequires \
            --define "_topdir $tmpdir" \
            --undefine=source_date_epoch_from_changelog \
            "$spec" 2>/dev/null
    done
    rm -rf "$tmpdir"
}

mapfile -t raw_deps < <(collect_deps | sort -u)

if [ ${#raw_deps[@]} -eq 0 ]; then
    echo "no BuildRequires found in: ${specs[*]}" >&2
    exit 2
fi

# Strip version constraints, e.g. "cfitsio-devel >= 4", and skip anything
# still containing an unexpanded macro or shell substitution.
declare -A deps=()
for dep in "${raw_deps[@]}"; do
    case "$dep" in
        *'%{'*|*'$('*)
            echo "SKIP (unexpanded): $dep"
            continue ;;
        rpmlib*)
            continue ;;
    esac
    if [ "${dep:0:1}" = "(" ]; then
        # module-style / boolean dependency expression, e.g. "( nginx or httpd )"
        continue
    fi
    dep="${dep%% >= *}"
    dep="${dep%% <= *}"
    dep="${dep%% > *}"
    dep="${dep%% < *}"
    dep="${dep%% = *}"
    deps["$dep"]=1
done

echo "Checking ${#deps[@]} distinct BuildRequires in:"
printf '  %s\n' "${specs[@]}"
echo "against Fedora: $RELEASES"
echo

for rv in $RELEASES; do
    echo "== Fedora $rv =="
    for dep in "${!deps[@]}"; do
        found=$(dnf repoquery -q \
            --disablerepo='*' --enablerepo='fedora' --enablerepo='updates' \
            --releasever="$rv" --whatprovides "$dep" 2>/dev/null |
            grep -v -iE 'cursor|grok|anysphere|fingerprint|importing|loading|https' |
            head -1)
        if [ -n "$found" ]; then
            printf '  ok   %s\n' "$dep"
        else
            printf '  MISS %s\n' "$dep"
            fail=1
        fi
    done
done

if [ $fail -eq 0 ]; then
    echo
    echo "All BuildRequires resolve in every checked release."
else
    echo
    echo "Unresolved BuildRequires above will abort COPR builds for the"
    echo "affected release(s). Replace, drop, or provide them before building."
fi
exit $fail
