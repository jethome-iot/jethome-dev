#!/usr/bin/env bash
# Enforce the invariants images/versions.json cannot express on its own.
#
# Usage: ./scripts/check-versions.sh
#
# Each check below exists because getting it wrong used to be silent - a green
# build publishing the wrong thing - rather than a failure anyone would notice:
#
#   1. Every image in versions.json has images/<name>/Dockerfile, and every
#      Dockerfile is in versions.json. An image missing here is never built; an
#      entry with no Dockerfile fails only once CI reaches it.
#   2. Exactly one variant per image is primary. Zero means nothing publishes
#      `latest`; two means `latest` and `sha-<commit>` are decided by whichever
#      manifest job finished last.
#   3. Tags are unique within an image - two variants sharing one tag would
#      overwrite each other in GHCR.
#   4. Every platform has a runner pool. A platform without one leaves `runs-on`
#      empty and that leg silently never starts.
#   5. The primary variant's args match the Dockerfile's ARG defaults. scripts/
#      build.sh passes no --build-arg, so a mismatch means local builds and CI
#      build different images from the same commit.
#   6. Every base_tag exists among the base image's tags, and an image with a base
#      declares base_arg. This is what stops a half-done bump from publishing an
#      idf-v<old> tag built on v<new>.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"
VERSIONS="images/versions.json"

fail=0
problem() {
    echo "  ✗ $*" >&2
    fail=1
}

echo "==> ${VERSIONS} is valid JSON"
jq -e . "${VERSIONS}" >/dev/null || exit 1

images=$(jq -r '.images | keys[]' "${VERSIONS}")

echo "==> every image has a Dockerfile, and every Dockerfile an image"
for image in ${images}; do
    [ -f "images/${image}/Dockerfile" ] || problem "images/${image}/Dockerfile is missing"
done
for dockerfile in images/*/Dockerfile; do
    name=$(basename "$(dirname "${dockerfile}")")
    jq -e --arg n "${name}" '.images[$n]' "${VERSIONS}" >/dev/null \
        || problem "images/${name}/Dockerfile has no entry in ${VERSIONS} - it will never be built"
done

for image in ${images}; do
    echo "==> ${image}"

    primaries=$(jq -r --arg i "${image}" '[.images[$i].builds[] | select(.primary == true)] | length' "${VERSIONS}")
    [ "${primaries}" -eq 1 ] || problem "${image}: expected exactly one primary variant, found ${primaries}"

    total=$(jq -r --arg i "${image}" '.images[$i].builds | length' "${VERSIONS}")
    unique=$(jq -r --arg i "${image}" '[.images[$i].builds[].tag] | unique | length' "${VERSIONS}")
    [ "${total}" -eq "${unique}" ] || problem "${image}: duplicate tags among its variants"

    platforms=$(jq -r --arg i "${image}" '.images[$i].platforms | length' "${VERSIONS}")
    [ "${platforms}" -gt 0 ] || problem "${image}: no platforms declared"
    empty_runners=$(jq -r --arg i "${image}" '[.images[$i].platforms[] | select(. == "" or . == null)] | length' "${VERSIONS}")
    [ "${empty_runners}" -eq 0 ] || problem "${image}: a platform has no runner pool"

    # The primary variant is what a local build reproduces, so its args are the
    # ones that must match the Dockerfile.
    while IFS='=' read -r arg value; do
        [ -n "${arg}" ] || continue
        default=$(sed -n "s/^ARG ${arg}=//p" "images/${image}/Dockerfile" | head -1)
        if [ -z "${default}" ]; then
            problem "${image}: Dockerfile has no 'ARG ${arg}=' default, but versions.json passes it"
        elif [ "${default}" != "${value}" ]; then
            problem "${image}: ${arg} is '${value}' in ${VERSIONS} but '${default}' in the Dockerfile"
        fi
    done < <(jq -r --arg i "${image}" '.images[$i].builds[] | select(.primary == true) | .args | to_entries[] | "\(.key)=\(.value)"' "${VERSIONS}")

    base=$(jq -r --arg i "${image}" '.images[$i].base // ""' "${VERSIONS}")
    if [ -n "${base}" ]; then
        jq -e --arg b "${base}" '.images[$b]' "${VERSIONS}" >/dev/null \
            || problem "${image}: base image '${base}' is not in ${VERSIONS}"
        base_arg=$(jq -r --arg i "${image}" '.images[$i].base_arg // ""' "${VERSIONS}")
        [ -n "${base_arg}" ] || problem "${image}: declares a base but no base_arg to pass it through"

        while read -r variant_tag base_tag; do
            if [ -z "${base_tag}" ] || [ "${base_tag}" = "null" ]; then
                problem "${image}: variant '${variant_tag}' has no base_tag"
                continue
            fi
            jq -e --arg b "${base}" --arg t "${base_tag}" \
                '.images[$b].builds | map(.tag) | index($t)' "${VERSIONS}" >/dev/null \
                || problem "${image}: variant '${variant_tag}' wants base tag '${base_tag}', which ${base} does not publish"
        done < <(jq -r --arg i "${image}" '.images[$i].builds[] | "\(.tag) \(.base_tag // "")"' "${VERSIONS}")

        # CI overrides base_arg with a digest, so the Dockerfile default is only
        # ever used by a local build - which is exactly why it drifts unnoticed.
        # It has to name the primary variant's base tag, or ./scripts/build.sh
        # builds on a different ESP-IDF than CI does.
        primary_base_tag=$(jq -r --arg i "${image}" '.images[$i].builds[] | select(.primary == true) | .base_tag // ""' "${VERSIONS}")
        base_default=$(sed -n "s/^ARG ${base_arg}=//p" "images/${image}/Dockerfile" | head -1)
        if [ -z "${base_default}" ]; then
            problem "${image}: Dockerfile has no 'ARG ${base_arg}=' default for a local build to use"
        elif [ "${base_default##*:}" != "${primary_base_tag}" ]; then
            problem "${image}: Dockerfile's ${base_arg} default ends in ':${base_default##*:}' but the primary variant is built on '${primary_base_tag}'"
        fi
    fi

    # The generator must produce something for both matrices, or the workflow gets
    # an empty matrix and quietly builds nothing.
    for kind in build manifest; do
        count=$(./scripts/versions-matrix.sh "${image}" "${kind}" | jq 'length')
        [ "${count}" -gt 0 ] || problem "${image}: the ${kind} matrix is empty"
    done
done

if [ "${fail}" -ne 0 ]; then
    echo "==> versions are inconsistent" >&2
    exit 1
fi
echo "==> versions are consistent"
