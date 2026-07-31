# CLAUDE.md

This repo ships no application code. It builds three Docker developer images —
`esp-idf`, `esp-matter`, `platformio` — and publishes them to
`ghcr.io/<owner>/jethome-dev-<image>`. The deliverables are Dockerfiles, GitHub
Actions workflows and READMEs.

## Layout

- One directory per image: `images/<name>/`, holding its `Dockerfile`, `README.md`
  and any support files (`esp-matter/entrypoint.sh`, `platformio/pio_project/`).
- Each workflow sets `context: images/<name>` and `scripts/build.sh` builds the
  same directory, so a Dockerfile can only `COPY` from inside its own directory —
  a shared file at the repo root breaks both CI and local builds.
- `scripts/build.sh` auto-discovers images by scanning `images/*/Dockerfile`; an
  image placed anywhere else is invisible to the tooling. `scripts/test-workflow.sh`
  instead hardcodes a workflow map that must be edited by hand.

## CI

The authoritative files are `.github/workflows/esp-idf.yml` and `platformio.yml` —
read them before changing anything here.

- Only two workflow files exist: `esp-idf.yml` builds **both** esp-idf and
  esp-matter; `platformio.yml` builds platformio. One workflow per image *family*:
  an image whose Dockerfile is `FROM` another image of this repo joins the base
  image's workflow, adds `images/<name>/**` to its push **and** pull_request
  `paths:` filters, and chains via `needs: <base>-manifest`.
- Two jobs per image: `<image>-build` (matrix axis `platform`, one leg per
  `linux/amd64` / `linux/arm64`, pushes platform-suffixed tags) then
  `<image>-manifest` (`docker buildx imagetools create` → `latest`, `sha-<7 chars>`,
  `<prefix>-<version>`). No job is named `build`. Every job needs its own
  `permissions: contents: read` + `packages: write`.
- The version tag is listed **last** in `imagetools create` on purpose: GHCR shows
  the last tag as the package's primary tag.
- The versions CI passes in (`IDF_BASE_TAG`, `BASE_IMAGE_TAG`, `ESP_MATTER_VERSION`,
  `PIO_VERSION`) live in the matrix `version:` + `include:` blocks and reach the
  image as `build-args`; for those the Dockerfile `ARG` default is only a
  local-build fallback. A bump means editing **two** matrix blocks per image — the
  build job's and the manifest job's; updating one alone produces a manifest
  referencing tags that were never built. Bumping ESP-IDF touches **four** blocks,
  because both `esp-matter-*` blocks embed it as `jethome_idf_base_tag` (→
  `BASE_IMAGE_TAG`), plus the `ARG BASE_IMAGE_TAG` default in
  `images/esp-matter/Dockerfile`.
- The other pins — `ESP32_PLATFORM_VERSION`, `NATIVE_PLATFORM_VERSION`,
  `UNITY_VERSION` in `images/platformio/Dockerfile` — are never passed from CI, so
  their `ARG` defaults are the sole source of truth and are bumped there.
- No README may repeat a version number.
- Publishing is gated in three places per build job, all of which must stay in
  sync: job `if: github.repository_owner == 'jethome-iot' || github.event_name ==
  'workflow_dispatch'`, the login step's `if: … owner == 'jethome-iot' &&
  github.ref_name == 'master'`, and `push:` with that same master-only expression.
  Manifest jobs use the master-only form as their job `if`. The org literal is
  hardcoded.
- `esp-matter-build` has `needs: esp-idf-manifest`, which is master-only, so both
  ESP-Matter jobs are skipped entirely on `dev`, on PRs and on non-master dispatch —
  ESP-Matter gets no build validation there. The dependency is real:
  `images/esp-matter/Dockerfile` is `FROM ghcr.io/jethome-iot/jethome-dev-esp-idf:idf-<version>`,
  a multi-arch tag only that manifest job publishes (owner hardcoded, so forks pull
  from `jethome-iot` too).
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

- Common to all three: `WORKDIR /workspace` and a version-printing verification
  `RUN` as the last build layer — that layer is what catches installs which
  silently no-op under emulation. Both platforms must build.
- `SHELL ["/bin/bash", "-c"]` is set only in esp-idf and esp-matter, whose `RUN`
  layers need the bash builtin `source` (their comment: "needed for QEMU emulation
  compatibility"). platformio has no `SHELL` directive, so its `RUN` layers run
  under `/bin/sh` — keep them POSIX. Its trailing `CMD ["/bin/bash"]` sets the
  interactive shell, not the build shell.
- Activate toolchains by sourcing `${IDF_PATH}/export.sh` (esp-idf additionally
  needs `export IDF_PATH_FORCE=1` in the same `RUN`; esp-matter also sources
  `${ESP_MATTER_PATH}/export.sh`), then call tools by name. Python packages live
  inside the ESP-IDF venv — hardcoded interpreter paths like
  `/opt/esp/python_env/idf5.4_py3.12_env/bin/python3` were tried and reverted.
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

## Local workflow

- `./scripts/build.sh <image>|all` runs a plain `docker build` for the host
  architecture with the Dockerfile's own ARG defaults (no `--build-arg`, no
  buildx), tagging `jethome-dev-<image>:local` (`IMAGE_TAG` overrides). `-r` runs
  the image afterwards and only applies to a single named image. Building
  `esp-matter` this way pulls its base from GHCR, so it does not exercise a locally
  built esp-idf.
- `./scripts/test-workflow.sh [<workflow>|all] [--no-dryrun]` runs `act` on the
  workflow's `<name>-build` job only — the manifest jobs push to GHCR, and
  `esp-idf.yml` also carries the long self-hosted `esp-matter-build`. The workflow
  map inside the script is hardcoded. `.actrc` pins the runner image and forces
  `--platform linux/amd64`.

## Git

- Commit messages: English, short imperative subject, optional bullet body. The
  history does **not** use Conventional Commits — no `feat:` / `fix:` prefixes.
- `dev` is for validation, `master` is the only branch that publishes to GHCR.
- Never run `git commit` unless the user explicitly asks for it.
