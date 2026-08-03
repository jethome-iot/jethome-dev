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

# GitHub's own labels are known to actionlint and deliberately absent from
# .github/actionlint.yaml, so they are listed here instead.
GITHUB_HOSTED=(ubuntu-latest ubuntu-24.04 ubuntu-22.04 ubuntu-24.04-arm ubuntu-22.04-arm)

# The larger-runner pools, read from the linter's config so the two cannot drift.
mapfile -t POOL_LABELS < <(sed -n 's/^[[:space:]]*-[[:space:]]*//p' .github/actionlint.yaml)
if [ "${#POOL_LABELS[@]}" -eq 0 ]; then
    echo "  ✗ .github/actionlint.yaml lists no runner pools - refusing to accept any label" >&2
    exit 1
fi

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

    # runs-on is now filled at runtime from this file, so actionlint no longer sees
    # the label and cannot compare it against .github/actionlint.yaml. A typo would
    # leave the leg queued for 24 hours with no diagnostic, so the comparison
    # happens here instead.
    while read -r runner; do
        [ -n "${runner}" ] || continue
        # Compared as strings, not as a pattern: every label here contains dots
        # and dashes, and `ubuntu-24.04-arm` used as a regex would also match
        # `ubuntu-24X04-arm` - accepting exactly the typo this check exists for.
        known=0
        for label in "${POOL_LABELS[@]}" "${GITHUB_HOSTED[@]}"; do
            if [ "${label}" = "${runner}" ]; then
                known=1
                break
            fi
        done
        [ "${known}" -eq 1 ] \
            || problem "${image}: runner '${runner}' is neither a pool in .github/actionlint.yaml nor a GitHub-hosted label"
    done < <(jq -r --arg i "${image}" '.images[$i].platforms[]' "${VERSIONS}")

    # Argument *names* are checked for every variant: Docker silently ignores an
    # unconsumed --build-arg, so a typo in a non-primary variant would build the
    # Dockerfile's default version and publish it under the other version's tag.
    # Argument *values* are only compared for the primary variant, since that is
    # the one a local build (which passes no --build-arg) reproduces.
    while IFS='|' read -r variant_tag is_primary arg value; do
        [ -n "${arg}" ] || continue
        default=$(sed -n "s/^ARG ${arg}=//p" "images/${image}/Dockerfile" | head -1)
        if [ -z "${default}" ]; then
            problem "${image}: variant '${variant_tag}' passes ${arg}, which images/${image}/Dockerfile does not declare - Docker would ignore it"
        elif [ "${is_primary}" = "true" ] && [ "${default}" != "${value}" ]; then
            problem "${image}: ${arg} is '${value}' in ${VERSIONS} but '${default}' in the Dockerfile"
        fi
    done < <(jq -r --arg i "${image}" '.images[$i].builds[] as $b | ($b.args // {}) | to_entries[] | "\($b.tag)|\($b.primary // false)|\(.key)|\(.value)"' "${VERSIONS}")

    # `tag` used to be assembled in the workflow from the same fields that fed
    # build-args, so it could not disagree with them. As free text in a data file
    # it can, and the result is a GHCR tag whose name contradicts its contents.
    # Requiring every version that went into the build to appear in the tag is what
    # restores that link.
    while IFS='|' read -r variant_tag value; do
        [ -n "${value}" ] || continue
        case "${variant_tag}" in
        *"${value}"*) ;;
        *) problem "${image}: variant '${variant_tag}' is built with '${value}' but does not name it in its tag" ;;
        esac
    done < <(jq -r --arg i "${image}" '.images[$i].builds[] as $b | (($b.args // {}) | to_entries[] | "\($b.tag)|\(.value)"), (if ($b.base_tag // "") != "" then "\($b.tag)|\($b.base_tag)" else empty end)' "${VERSIONS}")

    # Digests are downloaded with `digest-<image>-<tag>-*`, so one tag being a
    # prefix of another would pull in the other variant's platforms and publish a
    # mixed manifest. Uniqueness alone does not rule that out.
    while read -r a; do
        while read -r b; do
            [ "${a}" != "${b}" ] || continue
            case "${b}" in
            "${a}"*) problem "${image}: tag '${a}' is a prefix of '${b}' - the digest download glob cannot tell them apart" ;;
            esac
        done < <(jq -r --arg i "${image}" '.images[$i].builds[].tag' "${VERSIONS}")
    done < <(jq -r --arg i "${image}" '.images[$i].builds[].tag' "${VERSIONS}")

    # Every variant passes the same set of build args. An empty or partial set
    # would silently fall back to the Dockerfile's defaults and publish that under
    # this variant's tag - the failure the arg-name check below cannot see, since
    # it never runs for keys that are absent.
    primary_keys=$(jq -r --arg i "${image}" '[.images[$i].builds[] | select(.primary == true) | (.args // {}) | keys[]] | sort | join(",")' "${VERSIONS}")
    while IFS='|' read -r variant_tag keys; do
        [ "${keys}" = "${primary_keys}" ] \
            || problem "${image}: variant '${variant_tag}' passes args [${keys}] but the primary variant passes [${primary_keys}]"
    done < <(jq -r --arg i "${image}" '.images[$i].builds[] | "\(.tag)|\([(.args // {}) | keys[]] | sort | join(","))"' "${VERSIONS}")

    # A pin is a full commit SHA: it reaches the build as a --build-arg like any
    # other, but it can never appear in the tag, so the "tag names its versions"
    # rule above must not apply to it. What is checkable offline is the shape, and
    # that the Dockerfile declares the ARG at all - a pin naming an ARG that does
    # not exist would be silently dropped by Docker, and the build would quietly
    # take whatever the Dockerfile defaults to.
    while IFS='|' read -r variant_tag arg value; do
        [ -n "${arg}" ] || continue
        case "${value}" in
        [0-9a-f]*) [ "${#value}" -eq 40 ] || problem "${image}: variant '${variant_tag}' pins ${arg} to '${value}', which is not a full 40-character commit SHA" ;;
        *) problem "${image}: variant '${variant_tag}' pins ${arg} to '${value}', which is not a commit SHA" ;;
        esac
        grep -q "^ARG ${arg}=" "images/${image}/Dockerfile" \
            || problem "${image}: variant '${variant_tag}' pins ${arg}, which images/${image}/Dockerfile does not declare"
    done < <(jq -r --arg i "${image}" '.images[$i].builds[] as $b | ($b.pin // {}) | to_entries[] | "\($b.tag)|\(.key)|\(.value)"' "${VERSIONS}")

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
