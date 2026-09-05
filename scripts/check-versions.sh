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
#   7. Every tag is a legal Docker reference and short enough to carry the
#      suffixes the manifest jobs append. A tag with `+` or `/` in it, or one 152
#      characters long, is accepted here today and fails later, inside the push.
#   8. No tag is shaped like a name the manifest jobs publish by themselves -
#      `latest`, a bare `sha-<7hex>`, or `<tag>-sha-<7hex>`. The bare pair is the
#      dangerous one: `sha-1234567` is nobody's prefix, so nothing else here sees
#      it, and it is overwritten the day a commit's short SHA is 1234567.
#   9. The published names of an image are unique across its variants - the
#      backstop behind check 8, for whatever a future derived name adds.
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

    # A tag is a Docker reference: [a-zA-Z0-9_] first, then [a-zA-Z0-9._-], 128 max.
    # The cap here is 100, not 128, so a tag always has room for the suffixes the
    # manifest jobs append - today the longest is `-sha-<7hex>`, 12 characters.
    # Without this check a `+` or a `/` reaches the artifact name and
    # `docker buildx imagetools create`, and fails there instead. A newline cannot
    # be caught in this loop at all - the reader already split on it - which is what
    # the data-level check just above the loop is for.
    # Two things that can only be seen in the data, before any loop reads it.
    #
    # A control character, because `jq -r` emits one line per tag and `read` splits
    # on newlines: a tag containing one arrives as two values that are each legal on
    # their own, and the uniqueness check counts a single tag either way.
    #
    # A tag that is not a string, because `test` refuses one - and under `set -e`
    # that ends the whole run at this line, with no image name and no field name in
    # the log. `"tag": 24.04` written without quotes is the way to get there. The
    # type guard keeps the message a `problem` like any other, so the rest of the
    # file is still checked.
    nonstring=$(jq -r --arg i "${image}" '[.images[$i].builds[] | select((.tag | type) != "string")] | length' "${VERSIONS}")
    [ "${nonstring}" -eq 0 ] || problem "${image}: a variant's tag is not a string - quote it in ${VERSIONS}"
    # Every value that reaches a line-based reader, not just the tag: an `args`
    # value carrying a newline splits into a second `--build-arg` in the matrix
    # (`IDF_BASE_TAG=v5.4.1` plus a fabricated `EXTRA=1`), and the loop below drops
    # that second line through its own emptiness guard, so nothing checks it.
    ctrl=$(jq -r --arg i "${image}" '[.images[$i].builds[] | (.tag, ((.args // {}) | .[]), ((.pin // {}) | .[])) | select(type == "string" and test("[[:cntrl:]]"))] | length' "${VERSIONS}")
    [ "${ctrl}" -eq 0 ] || problem "${image}: a tag, arg or pin value contains a control character - the line-based checks below cannot see it"

    # `IFS= read` rather than plain `read`: the latter strips leading and trailing
    # whitespace, so ` ubuntu-24.04` would satisfy the pattern below while
    # versions-matrix.sh passes the space through to the manifest job, which then
    # fails on an illegal reference after every build has already run.
    # No `[ -n ... ] || continue` here, deliberately: the empty string is the one
    # value guaranteed to be an illegal reference, and skipping it would exempt it
    # from the only check that says so. It reaches `imagetools create -t <image>:`
    # otherwise, after every build in the matrix has run.
    while IFS= read -r variant_tag; do
        if ! printf '%s' "${variant_tag}" | grep -Eq '^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$'; then
            problem "${image}: tag '${variant_tag}' is not a legal Docker reference of at most 100 characters"
        fi
        # The manifest jobs derive `<tag>-sha-<7hex>` from this value, and publish
        # `latest` and a bare `sha-<7hex>` for the primary variant. A hand-written
        # tag of any of those three shapes cannot be told apart from a derived one -
        # and the bare forms are the dangerous pair, since neither the prefix rule
        # nor the derived-suffix check below sees them: `sha-1234567` is nobody's
        # prefix, yet it is overwritten the day a commit's short SHA is 1234567.
        case "${variant_tag}" in
        latest) problem "${image}: tag 'latest' is the name the primary variant publishes - it cannot also be a variant's own tag" ;;
        sha-???????)
            case "${variant_tag#sha-}" in
            *[!0-9a-f]*) ;;
            *) problem "${image}: tag '${variant_tag}' is the shape the primary variant publishes for a commit - it would be overwritten by the build of commit ${variant_tag#sha-}" ;;
            esac
            ;;
        esac
        case "${variant_tag}" in
        *-sha-???????)
            case "${variant_tag##*-sha-}" in
            *[!0-9a-f]*) ;;
            *) problem "${image}: tag '${variant_tag}' looks like the derived name <tag>-sha-<7hex>" ;;
            esac
            ;;
        esac
    done < <(jq -r --arg i "${image}" '.images[$i].builds[].tag' "${VERSIONS}")

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
    # Matched on a token boundary, not as a bare substring: as a substring a value
    # satisfied any tag that merely contained it, so a variant built with `v5.5`
    # passed while its tag claimed `idf-v5.5.5` - the tag naming a version the
    # build never used.
    # The value is escaped first - every version here contains dots, and an
    # unescaped `.` is a regex metacharacter that matches `24X04` as happily as
    # `24.04`. The boundary class is `[-_]` and deliberately excludes `.`: with a
    # dot in it, `idf-v5.5.5` would satisfy a claim of `v5.5`, which is the hole
    # this replaces.
    while IFS='|' read -r variant_tag value; do
        [ -n "${value}" ] || continue
        escaped=$(printf '%s' "${value}" | sed 's/[.[\*^$()+?{}|\\]/\\&/g')
        printf '%s' "${variant_tag}" | grep -Eq "(^v?|[-_]v?)${escaped}($|[-_])" \
            || problem "${image}: variant '${variant_tag}' is built with '${value}' but does not name it in its tag"
    done < <(jq -r --arg i "${image}" '.images[$i].builds[] as $b | (($b.args // {}) | to_entries[] | "\($b.tag)|\(.value)"), (if ($b.base_tag // "") != "" then "\($b.tag)|\($b.base_tag)" else empty end)' "${VERSIONS}")

    # Digests are downloaded with `digest-<image>-<tag>-*`, so one tag being a
    # prefix of another would pull in the other variant's platforms and publish a
    # mixed manifest. Uniqueness alone does not rule that out.
    #
    # Note what this rule is about, because it reads like a constraint on published
    # names and is not one: both this check and that glob read `builds[].tag`, the
    # matrix key. The names the manifest jobs publish are derived from it at build
    # time and never appear in this file, so adding a derived name costs nothing
    # here.
    while read -r a; do
        while read -r b; do
            [ "${a}" != "${b}" ] || continue
            case "${b}" in
            "${a}"*) problem "${image}: tag '${a}' is a prefix of '${b}' - the digest download glob cannot tell them apart" ;;
            esac
        done < <(jq -r --arg i "${image}" '.images[$i].builds[].tag' "${VERSIONS}")
    done < <(jq -r --arg i "${image}" '.images[$i].builds[].tag' "${VERSIONS}")

    # The names actually published must be unique across variants - `tag`
    # uniqueness does not imply it, because every variant publishes more names than
    # its tag. This is the backstop behind the shape rules above rather than a
    # first line of defence: those reject the shapes a collision needs, and this
    # catches whatever a future derived name adds that they do not know about. The
    # placeholders stand in for values only CI knows, and are constant on purpose -
    # a collision must not depend on which commit happens to build.
    published=""
    while IFS='|' read -r variant_tag is_primary; do
        [ -n "${variant_tag}" ] || continue
        published="${published}${variant_tag}
${variant_tag}-sha-0000000
"
        if [ "${is_primary}" = "true" ]; then
            published="${published}latest
sha-0000000
"
        fi
    done < <(jq -r --arg i "${image}" '.images[$i].builds[] | "\(.tag)|\(.primary // false)"' "${VERSIONS}")
    while read -r dupe; do
        [ -n "${dupe}" ] || continue
        problem "${image}: two variants would publish the same name '${dupe}'"
    done < <(printf '%s' "${published}" | sort | uniq -d)

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
    while IFS='|' read -r variant_tag is_primary arg value; do
        [ -n "${arg}" ] || continue
        # Every character, not just the first: `[0-9a-f]*` as a shell pattern only
        # constrains the leading one, so `2c1z…` would have passed here and failed
        # later at `git fetch` instead.
        case "${value}" in
        *[!0-9a-f]*) problem "${image}: variant '${variant_tag}' pins ${arg} to '${value}', which is not hexadecimal" ;;
        *) [ "${#value}" -eq 40 ] || problem "${image}: variant '${variant_tag}' pins ${arg} to a ${#value}-character value; a full commit SHA is 40" ;;
        esac
        pin_default=$(sed -n "s/^ARG ${arg}=//p" "images/${image}/Dockerfile" | head -1)
        if [ -z "${pin_default}" ]; then
            problem "${image}: variant '${variant_tag}' pins ${arg}, which images/${image}/Dockerfile does not declare - Docker would ignore it"
        elif [ "${is_primary}" = "true" ] && [ "${pin_default}" != "${value}" ]; then
            # Same rule as for args: the primary variant is what a local build
            # reproduces. Advancing a pin without moving the ARG default would have
            # CI build the new commit while ./scripts/build.sh checks out the old.
            problem "${image}: ${arg} is '${value}' in ${VERSIONS} but '${pin_default}' in the Dockerfile"
        fi
    done < <(jq -r --arg i "${image}" '.images[$i].builds[] as $b | ($b.pin // {}) | to_entries[] | "\($b.tag)|\($b.primary // false)|\(.key)|\(.value)"' "${VERSIONS}")

    # A variant with no `pin` at all emits no row above, so the loop cannot catch
    # it - and the Dockerfile would fall back to the primary's commit, publishing
    # one variant's tree under another variant's tag. Same key-set rule as `args`.
    primary_pins=$(jq -r --arg i "${image}" '[.images[$i].builds[] | select(.primary == true) | (.pin // {}) | keys[]] | sort | join(",")' "${VERSIONS}")
    while IFS='|' read -r variant_tag keys; do
        [ "${keys}" = "${primary_pins}" ] \
            || problem "${image}: variant '${variant_tag}' pins [${keys}] but the primary variant pins [${primary_pins}]"
    done < <(jq -r --arg i "${image}" '.images[$i].builds[] | "\(.tag)|\([(.pin // {}) | keys[]] | sort | join(","))"' "${VERSIONS}")

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
