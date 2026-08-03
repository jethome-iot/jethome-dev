# CLAUDE.md

This repo ships no application code. It is a home for Docker developer images:
each image lives in `images/<name>/` and is published as
`ghcr.io/<owner>/jethome-dev-<image>`. The deliverables are Dockerfiles, GitHub
Actions workflows and READMEs. `images/` is the roster — today `esp-idf`,
`esp-matter` and `platformio`, and adding to it is the normal case, not an
exception. Rules below are written per image; where they name one, it is an
example.

## Layout

- One directory per image: `images/<name>/`, holding its `Dockerfile`, `README.md`
  and any support files (`esp-matter/entrypoint.sh`, `platformio/pio_project/`).
- Each workflow sets `context: images/<name>` and `scripts/build.sh` builds the
  same directory, so a Dockerfile can only `COPY` from inside its own directory —
  a shared file at the repo root breaks both CI and local builds.
- `scripts/build.sh` auto-discovers images by scanning `images/*/Dockerfile`; an
  image placed anywhere else is invisible to the tooling.

## CI

The authoritative files are `.github/workflows/esp-idf.yml` and
`.github/workflows/platformio.yml` — read them before changing anything here.

- One workflow file per image *family*; today there are two — `esp-idf.yml` builds
  **both** esp-idf and esp-matter, `platformio.yml` builds platformio. A family is:
  an image whose Dockerfile is `FROM` another image of this repo joins the base
  image's workflow, adds `images/<name>/**` to its push **and** pull_request
  `paths:` filters, and chains via `needs: <base>-manifest`. The rule covers
  image-building workflows only; `lint.yml` and `runner-smoke.yml` build nothing
  and belong to no family.
- A larger-runner label names a pool created in the org, not anything GitHub
  predefines, so a typo cannot be told apart from a pool that does not exist: the
  job just sits queued for up to 24 hours, and `timeout-minutes` does not fire
  because it starts at assignment, not at queueing. Those pools are listed in
  `.github/actionlint.yaml` (GitHub's own labels are known to actionlint and are
  not repeated there); add one there before referencing it, or `lint.yml` fails
  the change. The check compares names against that list and cannot ask GitHub
  whether the pool is still alive — `runner-smoke.yml` (`workflow_dispatch` only)
  is what answers that, and it reads the same list, so a pool is probed and
  linted from one source.
- Two jobs per image: `<image>-build` (matrix axis `platform`, one leg per
  `linux/amd64` / `linux/arm64`, pushes platform-suffixed tags) then
  `<image>-manifest` (`docker buildx imagetools create` → `latest`, `sha-<7 chars>`,
  `<prefix>-<version>`). No job is named `build`. Every job that touches GHCR
  needs its own `permissions: contents: read` + `packages: write`; `lint.yml` and
  `runner-smoke.yml` touch nothing and declare the minimum they need instead.
- The version tag is listed **last** in `imagetools create` on purpose: GHCR shows
  the last tag as the package's primary tag.
- The versions CI passes in (`IDF_BASE_TAG`, `BASE_IMAGE_TAG`, `ESP_MATTER_VERSION`,
  `PIO_VERSION`) live in the matrix `version:` + `include:` blocks and reach the
  image as `build-args`. A bump means editing **two** matrix blocks per image — the
  build job's and the manifest job's; updating one alone produces a manifest
  referencing tags that were never built. Bumping ESP-IDF touches **four** blocks,
  because both `esp-matter-*` blocks embed it as `jethome_idf_base_tag` (→
  `BASE_IMAGE_TAG`).
- **Bump the matching `ARG` default in the Dockerfile too**, in the same change.
  `scripts/build.sh` passes no `--build-arg`, so those defaults are what every
  local build uses: leave one behind and local builds silently stay on the old
  version while CI moves on. The set to check is the `build-args:` block of that
  image's build step — currently `IDF_BASE_TAG` (esp-idf), `BASE_IMAGE_TAG` +
  `ESP_MATTER_VERSION` (esp-matter), `PIO_VERSION` (platformio).
- An `ARG` with no matrix entry is a pin CI never passes, so its Dockerfile
  default is the sole source of truth and is bumped there — today
  `ESP32_PLATFORM_VERSION`, `NATIVE_PLATFORM_VERSION` and `UNITY_VERSION` in
  `images/platformio/Dockerfile`.
- Every matrix carries `fail-fast: false`, so one platform leg failing does not
  cancel the other and truncate its log.
- Publishing is gated in three places per build job, all of which must stay in
  sync: job `if: github.repository_owner == 'jethome-iot' || github.event_name ==
  'workflow_dispatch'`, the login step's `if: … owner == 'jethome-iot' &&
  github.ref_name == 'master'`, and `push:` with that same master-only expression.
  Manifest jobs use the master-only form as their job `if`. The org literal is
  hardcoded.
- `esp-matter-build` has `needs: esp-idf-manifest`, which requires both
  `jethome-iot` **and** `master`, so both ESP-Matter jobs are skipped entirely on
  `dev`, on PRs, on non-master dispatch and in every fork. The dependency is real:
  `images/esp-matter/Dockerfile` is
  `FROM ghcr.io/jethome-iot/jethome-dev-esp-idf:idf-<version>`, a multi-arch tag
  only that manifest job publishes (owner hardcoded, so forks pull from
  `jethome-iot` too).
- Worse than "no validation": a PR touching only `images/esp-matter/**` still
  matches the workflow's `paths:` filter, so `esp-idf-build` runs on its unchanged
  context and the check goes green — a passing "🐳 ESP-IDF Docker Image" on such a
  PR says nothing about ESP-Matter. Validate it with `./scripts/build.sh esp-matter`
  or on `master`.
- `esp-matter-build` is the only self-hosted job (`[self-hosted, ubuntu-latest]`,
  `timeout-minutes: 360`): the connectedhomeip submodule tree needs ~50 GB and
  fails on a GitHub-hosted runner with "No space left on device". Everything else
  is `ubuntu-latest`, 60 min for build / 10 for manifest.
- `workflow_dispatch` is declared with no inputs anywhere, so
  `gh workflow run … -f version=… -f force_rebuild=…` is rejected. To force a cold
  build, clear the GHA cache — scopes are `jethome-dev-<image>-linux-amd64` /
  `-linux-arm64`.
- Workflow and step names carry emoji by convention (`🐳 ESP-IDF Docker Image`,
  `📥 Checkout repository`, `🏷️ Generate tags`), and tooling matches the display
  name verbatim: `gh run list --workflow="🐳 ESP-IDF Docker Image"`.

## Dockerfiles

- Every image sets `WORKDIR /workspace` and ends with a version-printing
  verification `RUN` as its last build layer — that layer is what catches installs
  which silently no-op under emulation. Both platforms must build.
- Docker's default `SHELL` is `/bin/sh`, so an image that sets none must keep its
  `RUN` layers POSIX — check the image's own Dockerfile before reaching for a
  bash-ism. esp-idf and esp-matter set `SHELL ["/bin/bash", "-c"]` because their
  layers need the bash builtin `source` (their comment: "needed for QEMU emulation
  compatibility"); platformio does not. A trailing `CMD ["/bin/bash"]` sets the
  interactive shell, not the build shell.
- Toolchain activation is per-image, not repo-wide. The ESP images source
  `${IDF_PATH}/export.sh` in every `RUN` that needs the toolchain (esp-idf
  additionally needs `export IDF_PATH_FORCE=1` in the same `RUN`; esp-matter also
  sources `${ESP_MATTER_PATH}/export.sh`), while platformio puts `pio` on `PATH`
  at install time and activates nothing. Either way call tools by name, never by
  absolute path: `/opt/esp/python_env/idf5.4_py3.12_env/bin/python3` was tried and
  reverted — it pins a version-stamped directory that a version bump invalidates.
- esp-matter activates both environments at runtime through
  `ENTRYPOINT ["/opt/esp/esp_matter_entrypoint.sh"]`; overriding that entrypoint in
  a derived image silently breaks the "no sourcing needed" promise in its README.
- Thin images are deliberate: esp-matter installs with `--no-host-tool` (no
  chip-tool/chip-cert) and platformio's `pio run`/`pio test` pre-warm block is
  commented out as a "VERY LONG step". Toolchains are meant to download on first
  build. Do not "optimize" these back on.

## Documentation

- Never hardcode a version number in a README. Describe capabilities and use
  placeholders: `idf-v<version>`, `idf-v<idf-ver>-matter-v<matter-ver>`,
  `pio-v<version>`, `sha-<commit>`. The only exceptions are `ARG` defaults inside a
  Dockerfile and build-argument examples.
- The root README indexes the images and covers repo-wide topics (layout, local
  scripts, CI triggers, registry) plus one image-agnostic `docker run` example;
  per-image tags, usage and build args live only in `images/<name>/README.md`. A
  new image needs a row in the root table, not a section of its own.
- Image READMEs document *the image* — tags, invocation, build args, environment —
  not how to develop with the framework inside it.
- An image README links the root index plus its own `FROM` edges — its base image
  and any image built on it. It never enumerates the roster, so adding an image
  touches its own README, the root table, and the README of its base image only.
- An image built `FROM` another image of this repo links to the base image's
  README for what it inherits and lists only its own additions. A copied inventory
  is a second source of truth that goes stale silently — the esp-matter copy had
  already lost `gcovr` before it was replaced by a link.

## Adding an image

Four places, none of them checked automatically:

1. `images/<name>/` with a `Dockerfile` and a `README.md`.
2. A row in the root README's image table.
3. Either a new workflow file, or — if the image is `FROM` another image of this
   repo — two jobs added to that family's workflow, plus `images/<name>/**` in its
   push **and** pull_request `paths:` filters.
4. A `FROM`-edge link in the base image's README, where there is a base image.

## Local workflow

- `./scripts/build.sh <image>|all` runs a plain `docker build` for the host
  architecture with the Dockerfile's own ARG defaults (no `--build-arg`, no
  buildx), tagging `jethome-dev-<image>:local` (`IMAGE_TAG` overrides). `-r` runs
  the image afterwards and only applies to a single named image. Building
  `esp-matter` this way pulls its base from GHCR, so it does not exercise a locally
  built esp-idf.
- There is no local workflow runner. Workflow changes are validated by pushing the
  branch and reading the PR's checks; `act` and its wrapper were removed because
  they only duplicated `build.sh` behind a container.
- **Verify before finishing.** After changing an image or its README, build it
  (`./scripts/build.sh <image>`) and run the README's own examples against the
  built image. Documented paths, env vars and `docker run` lines are exactly what
  drifts, and nothing else in this repo checks them — there are no tests.
