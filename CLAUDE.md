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
  whether the pool is reachable — `runner-smoke.yml` is what answers that, and it
  reads the same list, so a pool is probed and linted from one source. It runs on
  `workflow_dispatch` **or** a push to `runner-probe/**`, never on a pull request;
  the branch trigger is the only way to exercise a change to the probe itself,
  since `workflow_dispatch` is offered only for workflows already on `master`.
- Two jobs per image: `<image>-build` (matrix axis `platform`, one leg per
  `linux/amd64` / `linux/arm64`) then `<image>-manifest`
  (`docker buildx imagetools create` → `latest`, `sha-<7 chars>`,
  `<prefix>-<version>`). No job is named `build`. Every job that touches GHCR
  needs its own `permissions: contents: read` + `packages: write`; `lint.yml` and
  `runner-smoke.yml` touch nothing and declare the minimum they need instead.
- **Nothing is handed between those jobs by tag.** A build leg pushes by digest and
  carries no tag of its own (`outputs: type=image,…,push-by-digest=true`); the
  digests travel to the manifest job as one empty file per leg, named after the
  digest, through an artifact — matrix legs cannot each set a job output, they
  overwrite one another. The manifest is then assembled from
  `<image>@sha256:<digest>` references. A tag in between would be a mutable name
  resolved at a later moment, and between those moments another run can overwrite
  it: that is how a `sha-<commit>` tag ends up holding a different commit's image.
  There are no `-linux-<arch>` tags in GHCR any more.
- The version tag is listed **last** in `imagetools create` on purpose: GHCR shows
  the last tag as the package's primary tag.
- `esp-idf-manifest` publishes the manifest's own digest as an artifact named
  `manifest-digest-<image>-<version>`, and `esp-matter-build` downloads the one
  matching the ESP-IDF version in its own tag, then builds `FROM` it via a single
  `BASE_IMAGE` build-arg. An artifact rather than a job output because that job has
  a matrix: a scalar output would be overwritten by whichever leg finished last.
  One argument rather than repo + tag because a digest needs `@`, not `:` — and it
  makes the base repository overridable, so a fork or a local build can point at
  its own esp-idf instead of this one.
- **`images/versions.json` is the single source of truth for what CI builds.** A
  `prepare` job runs `scripts/check-versions.sh`, then `scripts/versions-matrix.sh
  <image> build|manifest`, and every other job takes its matrix from
  `fromJSON(needs.prepare.outputs.…)`. Matrices are not written in the workflow at
  all. Bumping a version is one edit here plus the matching `ARG` default in that
  image's Dockerfile — the checker fails the build if you do only one, because
  `scripts/build.sh` passes no `--build-arg` and those defaults are what every
  local build uses.
- What the checker enforces, each because getting it wrong used to be silent:
  every image has a Dockerfile and every Dockerfile an image; exactly one variant
  per image is `primary` (it alone gets `latest` and `sha-<commit>`); tags are
  unique **and none is a prefix of another**, since digests are downloaded with a
  `digest-<image>-<tag>-*` glob; every variant names in its own tag every version
  it is built with, so a bumped `args` with a forgotten `tag` cannot publish a name
  that contradicts its contents; every variant passes the same set of arg *names*
  as the primary one, because an absent or misspelled arg silently falls back to
  the Dockerfile default; the primary variant's arg *values* match the Dockerfile's
  `ARG` defaults; every runner is a pool listed in `.github/actionlint.yaml` (a
  runtime `runs-on` is invisible to actionlint); every `base_tag` exists among the
  base image's tags; and the base image's `ARG` default names the primary variant's
  base tag. Run it locally with `./scripts/check-versions.sh`.
- The checker validates the whole file and both workflows gate on it, so a version
  file broken for one image blocks publishing for all of them. That is deliberate —
  the data is shared — but it is also why `images/versions.json` sits in every
  `paths:` filter: a bump to one image rebuilds the others. The alternative, a file
  per image, trades that for losing the cross-image checks.
- Adding a *variant* (a second ESP-IDF or Matter version) is an entry in `builds`.
  Only one of them may be `primary`; the rest publish their version tag alone, so
  `latest` is a decision in the data rather than a race between manifest jobs.
- An `ARG` with no matrix entry is a pin CI never passes, so its Dockerfile
  default is the sole source of truth and is bumped there — today
  `ESP32_PLATFORM_VERSION`, `NATIVE_PLATFORM_VERSION` and `UNITY_VERSION` in
  `images/platformio/Dockerfile`.
- Every matrix carries `fail-fast: false`, so one platform leg failing does not
  cancel the other and truncate its log.
- `concurrency` cancels superseded **pull-request** runs and groups nothing else:
  the key carries `github.sha` on a push, giving every commit its own group. Note
  that `cancel-in-progress: false` does **not** produce a queue — GitHub cancels a
  *pending* run in a group whenever a newer one arrives, whatever that flag says.
  Grouping master pushes by ref would therefore drop the middle commit of any three
  landing inside one build window, along with its `sha-<commit>` image, which the
  READMEs document as the way to pin an exact commit.
- Each manifest job asserts it received one digest per platform before publishing.
  With `fail-fast: false` a failed leg would otherwise leave a single file in the
  directory and quietly publish a single-platform image under the multi-arch tags.
  The digest capture runs under `set -o pipefail`, because `jq` exits 0 on empty
  input: without it a failed `imagetools inspect` yields an empty digest and a
  green step.
- Publishing is gated on two questions, asked at different levels. **Who**: the
  build job's `if: github.repository_owner == 'jethome-iot'` — nothing runs
  anywhere else, so no step below needs to re-ask. **Where**: the login step's
  `if: github.ref_name == 'master'` and the `push=` field inside the build step's
  `outputs:` CSV, carrying the same expression — on a PR or on `dev` the image is
  built and thrown away, never uploaded. Manifest jobs
  ask both in their own job `if`, since they have no build step to gate. The org
  literal is hardcoded.
- **`esp-matter-build` runs on pull requests too**, and the base it uses differs by
  context. On `master` it downloads the digest artifact `esp-idf-manifest` just
  published and builds on that exact image. Elsewhere no such artifact exists — the
  manifest job is master-only — so it falls back to the last published
  `idf-<version>` tag. That validates this image's own layers, which is what a
  change to it touches; the *combination* of an edited esp-idf and an edited
  esp-matter is only exercised once both land on master.
- If that tag is not published either — a coordinated bump raises the ESP-IDF
  version and Matter's `base_tag` together, and the new esp-idf image only exists
  once it lands — the build falls back to `:latest` with a warning. Insisting on
  the unpublished tag would fail every version-bump PR at `FROM`.
- That is why the job's `if` is an expression rather than a plain `needs:`. A
  `needs` on a skipped job skips this one as well, which is exactly how ESP-Matter
  went unvalidated while a green "🐳 ESP-IDF Docker Image" check implied otherwise.
  On `master` it requires the manifest to have **succeeded**, not merely
  "not failed": a failed `esp-idf-build` leaves the manifest job `skipped`, and
  accepting that would start two 180-minute builds that die looking for digest
  artifacts nobody created, burying the original failure. Note the `${{ }}`
  wrapper — YAML reserves `!` at the start of a scalar.
- **Every build job also checks the PR's head repository**, not just the owner. On
  a pull request *from* a fork `github.repository_owner` is still `jethome-iot`, so
  the owner check alone would let a fork-controlled Dockerfile run on this org's
  paid pools. The condition is
  `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`.
- Both workflows exclude `!images/**/*.md` from their `paths:`. Negations come last
  and are order-sensitive, and `paths:` cannot be mixed with `paths-ignore:` for one
  event. Without this a documentation-only commit rebuilds and republishes every
  image.
- Every build job runs on a larger-runner pool, chosen by platform through a
  `runner` key in the matrix `include:` and read as `runs-on: ${{ matrix.runner }}`
  — `ubuntu-latest-8core` for `linux/amd64`, `ubuntu-latest-8core-arm` for
  `linux/arm64`. **Each platform builds on its own architecture**: there is no
  QEMU anywhere, and adding a platform means adding the pool for it, not emulating
  it. That coupling is unchecked and fails quietly: a `platform:` value with no
  matching `include:` entry leaves `matrix.runner` empty, `runs-on` evaluates to
  the empty string, and the leg never starts — actionlint passes it (verified
  against the image `lint.yml` runs, which catches a *wrong* label but not a
  missing key). The mapping is also copied into each build job, so a platform
  change touches every one of them. **Manifest jobs stay on `ubuntu-latest`** —
  they are seconds of GHCR calls, so a pool would buy nothing, and they are the
  only jobs that publish a multi-arch tag: pointing them at a pool would make tag
  publication hostage to that pool still existing and still being granted to this
  repository, and an unreachable pool queues for 24 hours rather than failing.
- Timeouts are 60 min for a build, 180 for `esp-matter-build`, 10 for a manifest.
  The esp-matter figure is a ceiling on a wedged job, not a target, and it stays
  generous until the native arm64 leg has been measured: the only native number
  that exists is 24 min on amd64 (the QEMU leg it replaced took 337). Lowering it
  too early fails in an unobvious way — the arm64 leg is killed, the manifest job
  is skipped with it, and the amd64 image is already in GHCR as an untagged blob
  that nothing references — so the published tags stay on the previous build while
  a run reports failure.
- **Nothing runs in a fork.** Those pools belong to `jethome-iot`, a fork cannot
  resolve their labels, and an unresolvable `runs-on` queues for 24 hours rather
  than failing — so the build jobs are gated on `github.repository_owner ==
  'jethome-iot'` with no `workflow_dispatch` escape hatch. A fork builds with
  `./scripts/build.sh`. Do not re-add a dispatch exception without giving the job
  a runner a fork can actually reach.
- The pool choice for `esp-matter-build` is about disk, not cores: the
  connectedhomeip tree needs ~50 GB, and the 8-core pools measured 372 GB (amd64)
  and 393 GB (arm64) free under Docker against 88 GB on 4-core. Re-measure with
  `runner-smoke.yml` before moving that job to a smaller pool.
- **No build cache.** `cache-from`/`cache-to` were removed after measurement: zero
  cache hits across every master run, against 21.6 minutes per run spent writing
  the cache — for esp-idf, 390 s of export on a 72 s build. `mode=max` wrote about
  3.9 GiB per leg into a 10 GB repository-wide quota, so LRU evicted entries
  during the very run that created them, leaving index entries whose blobs were
  already gone. Re-introduce it only against a measured, repeating hit.
- `workflow_dispatch` is declared with no inputs anywhere, so
  `gh workflow run … -f version=… -f force_rebuild=…` is rejected. Builds are cold
  by construction now that there is no layer cache.
- Actions are pinned to a floating major (`@v<N>`, not a SHA), and Dependabot
  (`.github/dependabot.yml`, `github-actions` only) raises the major when one
  ships. Resolve the number from the registry rather than from memory —
  `gh release view -R <owner>/<repo> --json tagName` — and read what the major
  breaks before taking it: these actions sit on the publishing path, and the last
  bump crossed changes to fork-PR checkout, removed deprecated inputs, a Node
  runtime requirement, and a new default that uploaded every build record as a
  public artifact (turned off via `DOCKER_BUILD_RECORD_UPLOAD`).
- The same rule covers the `uses:` lines in the image READMEs' CI examples, and
  nothing enforces it there: Dependabot reads workflow files, not Markdown, and
  `lint.yml` lints workflows, not documentation. They were three majors stale
  before anyone looked. Bump them in the same change as the workflows.
- Workflow and step names carry emoji by convention (`🐳 ESP-IDF Docker Image`,
  `📥 Checkout repository`, `🏷️ Generate tags`), and tooling matches the display
  name verbatim: `gh run list --workflow="🐳 ESP-IDF Docker Image"`.

## Dockerfiles

- Every image sets `WORKDIR /workspace` and ends with a version-printing
  verification `RUN` as its last build layer. It is the only thing standing between
  a silently failed install and a published image: a tool that never installed
  still leaves a green build until something asks it for its version. Emulation
  used to be the loudest source of those (CI no longer emulates), but it was never
  the only one — a mirror serving a stale package or an installer that exits 0 on
  a partial install produce the same image. Keep the layer. Both platforms must
  build.
- Docker's default `SHELL` is `/bin/sh`, so an image that sets none must keep its
  `RUN` layers POSIX — check the image's own Dockerfile before reaching for a
  bash-ism. esp-idf and esp-matter set `SHELL ["/bin/bash", "-c"]` because their
  layers call the bash builtin `source`; platformio does not. A trailing
  `CMD ["/bin/bash"]` sets the interactive shell, not the build shell.
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
