#!/usr/bin/env bash
# Turn images/versions.json into a GitHub Actions matrix.
#
# Usage: ./scripts/versions-matrix.sh <image> build|manifest
#
# Prints one JSON array, ready for `fromJSON`. The build matrix has one entry per
# (variant × platform); the manifest matrix has one per variant.
#
# Every entry carries `runner`, so a platform without a pool is impossible to
# express here - the generator fails instead of emitting a leg whose `runs-on`
# resolves to the empty string and never starts.
#
# `build_args` is emitted as the newline-joined string the build step wants, rather
# than an object, because a workflow cannot expand an object into that field.
#
# `platform_tag` uses gsub, not sub: a platform like linux/arm/v7 has two
# separators, and a leftover slash is rejected as an artifact name.
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <image> build|manifest" >&2
    exit 2
fi

IMAGE="$1"
KIND="$2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS="${REPO_ROOT}/images/versions.json"

if ! jq -e --arg img "${IMAGE}" '.images[$img]' "${VERSIONS}" >/dev/null; then
    echo "Error: no image '${IMAGE}' in images/versions.json" >&2
    exit 1
fi

case "${KIND}" in
build)
    jq -c --arg img "${IMAGE}" '
        .images[$img] as $i
        | [ $i.builds[] as $b
            | ($i.platforms | to_entries[]) as $p
            | {
                tag: $b.tag,
                primary: ($b.primary // false),
                platform: $p.key,
                runner: $p.value,
                platform_tag: ($p.key | gsub("/"; "-")),
                base_tag: ($b.base_tag // ""),
                base_arg: ($i.base_arg // ""),
                timeout_minutes: ($i.timeout_minutes // 60),
                platform_count: ($i.platforms | length),
                build_args: (($b.args // {}) | to_entries | map("\(.key)=\(.value)") | join("\n"))
              } ]
    ' "${VERSIONS}"
    ;;
manifest)
    jq -c --arg img "${IMAGE}" '
        .images[$img] as $i
        | [ $i.builds[]
            | {
                tag: .tag,
                primary: (.primary // false),
                base_tag: (.base_tag // ""),
                platform_count: ($i.platforms | length)
              } ]
    ' "${VERSIONS}"
    ;;
*)
    echo "Error: kind must be 'build' or 'manifest', got '${KIND}'" >&2
    exit 2
    ;;
esac
