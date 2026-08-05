#!/usr/bin/env bash
# Run the same four checks as .github/workflows/lint.yml, locally.
#
# The workflow is a hard gate on all but the last, so without this script every
# actionlint, shellcheck or pinning mistake costs a push and a CI round-trip to
# discover. Both files pin the same tool versions on purpose - bump them together,
# or the local run stops predicting the remote one.
#
# Usage: ./scripts/lint.sh
set -euo pipefail

ACTIONLINT_IMAGE="rhysd/actionlint:1.7.12"
HADOLINT_IMAGE="hadolint/hadolint:v2.15.1-alpine"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if ! docker version >/dev/null 2>&1; then
    echo "Error: the Docker daemon is not responding - both linters run as containers." >&2
    exit 1
fi

status=0

echo "==> Workflow files (actionlint)"
if ! docker run --rm -v "${REPO_ROOT}:/repo" -w /repo "${ACTIONLINT_IMAGE}" -color; then
    status=1
fi

echo "==> Shell scripts (shellcheck, errors only)"
if ! git ls-files '*.sh' | xargs -r \
    docker run --rm -i -v "${REPO_ROOT}:/repo" -w /repo \
        --entrypoint shellcheck "${ACTIONLINT_IMAGE}" --severity=error; then
    status=1
fi

echo "==> Package pins (pip and pio are gates, apt is advisory)"
if ! ./scripts/check-pins.sh; then
    status=1
fi

# Advisory, exactly as in CI: these Dockerfiles break some hadolint rules by
# design, so its output is read, not obeyed, and never changes the exit code.
echo "==> Dockerfiles (hadolint, advisory)"
for dockerfile in images/*/Dockerfile; do
    echo "--- ${dockerfile}"
    docker run --rm -i "${HADOLINT_IMAGE}" hadolint --no-fail - < "${dockerfile}" || true
done

if [ "${status}" -eq 0 ]; then
    echo "==> All gates passed"
else
    echo "==> Gates failed" >&2
fi
exit "${status}"
