#!/usr/bin/env bash
# Show where each pinned ESP-Matter commit sits relative to its upstream branch,
# and optionally advance the pins.
#
# Usage:
#   ./scripts/update-matter-ref.sh          # report only
#   ./scripts/update-matter-ref.sh --write  # advance every pin to its branch HEAD
#
# Why this exists: ESP-Matter publishes no git tags, only moving release/*
# branches, so "the v1.5 release" is not a thing you can fetch - release/v1.5
# carried specification v1.5 at one commit and v1.5.1 at another. images/
# versions.json therefore pins a commit, and picking up upstream changes has to be
# a deliberate edit with a diff rather than a side effect of the next rebuild.
#
# After --write, check what the new commit actually contains before committing:
# the branch's own README carries a "Supported Matter specification versions"
# table, and the tag in versions.json has to keep matching it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"
VERSIONS="images/versions.json"
UPSTREAM="https://github.com/espressif/esp-matter.git"

WRITE=0
case "${1:-}" in
--write) WRITE=1 ;;
"") ;;
*)
    echo "Usage: $0 [--write]" >&2
    exit 2
    ;;
esac

changed=0
while IFS='|' read -r tag branch pinned; do
    [ -n "${tag}" ] || continue
    if [ -z "${branch}" ] || [ "${branch}" = "null" ]; then
        echo "  ${tag}: no upstream_branch recorded - skipping" >&2
        continue
    fi

    head=$(git ls-remote "${UPSTREAM}" "refs/heads/${branch}" | cut -f1)
    if [ -z "${head}" ]; then
        echo "  ${tag}: branch ${branch} not found upstream" >&2
        exit 1
    fi

    if [ "${head}" = "${pinned}" ]; then
        printf '  %-28s %s up to date\n' "${tag}" "${branch}"
        continue
    fi

    printf '  %-28s %s moved\n      pinned: %s\n      head:   %s\n' \
        "${tag}" "${branch}" "${pinned}" "${head}"
    changed=1

    if [ "${WRITE}" -eq 1 ]; then
        tmp=$(mktemp)
        jq --arg t "${tag}" --arg h "${head}" \
            '(.images[].builds[] | select(.tag == $t) | .pin.ESP_MATTER_REF) = $h' \
            "${VERSIONS}" >"${tmp}"
        mv "${tmp}" "${VERSIONS}"
    fi
done < <(jq -r '.images[].builds[] | select(.pin.ESP_MATTER_REF) | "\(.tag)|\(.upstream_branch // "")|\(.pin.ESP_MATTER_REF)"' "${VERSIONS}")

if [ "${changed}" -eq 0 ]; then
    echo "==> every pin matches its branch head"
    exit 0
fi

if [ "${WRITE}" -eq 1 ]; then
    echo "==> pins advanced in ${VERSIONS}"
    echo "    Now check each branch's README for the specification it carries, and"
    echo "    update the image tag if the specification changed. Then run"
    echo "    ./scripts/check-versions.sh - the Dockerfile ARG default for the"
    echo "    primary variant has to move with it."
else
    echo "==> pins are behind; re-run with --write to advance them"
fi
