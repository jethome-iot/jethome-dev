# CLAUDE.md

This repo ships no application code. It is a home for Docker developer images:
each image lives in `images/<name>/` and is published as
`ghcr.io/<owner>/jethome-dev-<image>`. The deliverables are Dockerfiles, GitHub
Actions workflows and READMEs. `images/` is the roster — today `esp-idf`,
`esp-matter`, `host` and `platformio`, and adding to it is the normal case, not an
exception. Rules below are written per image; where they name one, it is an
example.

## Layout

- One directory per image: `images/<name>/`, holding its `Dockerfile`, `README.md`
  and any support files (`esp-matter/entrypoint.sh`, `platformio/pio_project/`,
  `host/smoke/`).
- Each workflow sets `context: images/<name>` and `scripts/build.sh` builds the
  same directory, so a Dockerfile can only `COPY` from inside its own directory —
  a shared file at the repo root breaks both CI and local builds.
- `scripts/build.sh` auto-discovers images by scanning `images/*/Dockerfile`; an
  image placed anywhere else is invisible to the tooling.

## CI

The authoritative files are `.github/workflows/esp-idf.yml`,
`.github/workflows/platformio.yml` and `.github/workflows/host.yml` — read them
before changing anything here.

- One workflow file per image *family*; today there are three — `esp-idf.yml`
  builds **both** esp-idf and esp-matter, `platformio.yml` builds platformio,
  `host.yml` builds host. A family is:
  an image whose Dockerfile is `FROM` another image of this repo joins the base
  image's workflow, adds `images/<name>/**` to its push **and** pull_request
  `paths:` filters, and chains via `needs: <base>-build` — the *build* job, not the
  manifest one, because what it needs is the base image itself and that is pushed
  by digest on every run, while tags are master-only. The rule covers
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
- Two jobs per image: `<image>-build` (one leg per variant × platform) then
  `<image>-manifest`. Tags per variant: `<prefix>-<version>` (moves on every
  rebuild) and `<prefix>-<version>-sha-<short-commit>` (immutable, the only thing to
  roll back to). The **primary** variant additionally gets `latest` and the bare
  `sha-<short-commit>`.
- **Any job downstream of a multi-variant build runs under `!cancelled()`** with an
  explicit `prepare` check, never the implicit `success()` over `needs`. One build
  job covers every variant of an image, so a legacy variant failing marks the whole
  job failed — which would otherwise withhold the tags of variants that built fine
  (`latest` stays on the previous release while their images sit untagged), and
  skip `esp-matter-build` entirely even for a base that succeeded. Each leg resolves
  its own artifact and fails by itself when it is missing, which is the right blast
  radius. No job is named `build`. Every job that touches GHCR
  needs its own `permissions: contents: read` + `packages: write`; `lint.yml` and
  `runner-smoke.yml` touch nothing and declare the minimum they need instead.
- **Nothing is handed between those jobs by tag.** A build leg pushes by digest and
  carries no tag of its own (`outputs: type=image,…,push-by-digest=true`); the
  digests travel to the manifest job as one empty file per leg, named after the
  digest, through an artifact — matrix legs cannot each set a job output, they
  overwrite one another. The manifest is then assembled from
  `<image>@sha256:<digest>` references. A tag in between would be a mutable name
  resolved at a later moment, and between those moments another run can overwrite
  it: that is how a `sha-<short-commit>` tag ends up holding a different commit's image.
- The version tag is listed **last** in `imagetools create` on purpose: GHCR shows
  the last tag as the package's primary tag.
- `esp-matter-build` depends on `esp-idf-build`, **not** on the manifest job, and
  takes the per-platform digest for its own architecture from that build's
  artifact. The artifact is named after the ESP-IDF version this image declares in
  its own tag, so base and advertised version cannot drift apart. It reaches the
  Dockerfile through a single `BASE_IMAGE` build-arg — one argument rather than
  repo + tag, because a digest needs `@` where a tag needs `:`, and because it makes
  the base repository overridable for a fork or a local build. A digest names no
  version, so the ESP-IDF version travels separately as `IDF_VERSION` in `args`,
  taken from the same `base_tag`; both ESP images label it as
  `dev.jethome.idf.version` and both assert it against `idf.py --version`, which is
  what keeps a label a consumer reads from the registry from outliving the base it
  describes.
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
  per image is `primary` (it alone gets `latest` and `sha-<short-commit>`); tags are
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
- The checker validates the whole file and every build workflow gates on it, so a version
  file broken for one image blocks publishing for all of them. That is deliberate —
  the data is shared — but it is also why `images/versions.json` sits in every
  `paths:` filter: a bump to one image rebuilds the others. The alternative, a file
  per image, trades that for losing the cross-image checks.
- **ESP-Matter is pinned by commit, not by branch.** Upstream publishes no git
  tags, only moving `release/*` branches, so a branch names a line rather than a
  release — `release/v1.5` carried specification v1.5 at one commit and v1.5.1 at
  another. Each variant carries `pin.ESP_MATTER_REF` (a full SHA) and
  `upstream_branch` (where it came from); the Dockerfile fetches that commit
  shallowly rather than cloning the branch, and records it as an OCI label. `pin`
  reaches the build as a build-arg like `args`, but the checker validates it
  differently — a SHA can never appear in the tag. Advance pins with
  `./scripts/update-matter-ref.sh --write`, then check the branch's own README for
  the specification it now carries and move the image tag if it changed.
- Adding a *variant* (a second ESP-IDF or Matter version) is an entry in `builds`.
  Only one of them may be `primary`; the rest publish their version tag alone, so
  `latest` is a decision in the data rather than a race between manifest jobs.
- An `ARG` with no matrix entry is a pin CI never passes, so its Dockerfile
  default is the sole source of truth and is bumped there — today
  `ESP32_PLATFORM_VERSION`, `NATIVE_PLATFORM_VERSION` and `UNITY_VERSION` in
  `images/platformio/Dockerfile`, and every tool pin in `images/host/Dockerfile`
  (the QA versions, `PAHO_VERSION`/`PAHO_REF`, and `LYCHEE_VERSION` and
  `DOCKER_VERSION` with their per-architecture checksums). host passes one arg and
  one only, `UBUNTU_BASE_TAG`, because that is the single value its tag can name.
- Every matrix carries `fail-fast: false`, so one platform leg failing does not
  cancel the other and truncate its log.
- `concurrency` cancels superseded **pull-request** runs and groups nothing else:
  the key carries `github.sha` on a push, giving every commit its own group. Note
  that `cancel-in-progress: false` does **not** produce a queue — GitHub cancels a
  *pending* run in a group whenever a newer one arrives, whatever that flag says.
  Grouping master pushes by ref would therefore drop the middle commit of any three
  landing inside one build window, along with its `sha-<short-commit>` image, which the
  READMEs document as the way to pin an exact commit.
- Each manifest job asserts it received one digest per platform before publishing.
  With `fail-fast: false` a failed leg would otherwise leave a single file in the
  directory and quietly publish a single-platform image under the multi-arch tags.
  The digest capture runs under `set -o pipefail`, because `jq` exits 0 on empty
  input: without it a failed `imagetools inspect` yields an empty digest and a
  green step.
- **Publishing a *tag* is master-only; pushing an *image* is not.** Keep the two
  apart when reading these workflows:
  - **Who** runs at all: the build job's `if: github.repository_owner ==
    'jethome-iot'`, so no step below re-asks.
  - **Which tags** get written: only the manifest jobs write tags, and their job
    `if` requires `master`. Nothing outside master ever moves `latest` or a version
    tag.
  - **Whether the image is uploaded** differs per image. `esp-idf-build` pushes by
    digest on *every* run — its GHCR login is unconditional to match — because
    `esp-matter-build` consumes that digest and that is what makes ESP-Matter
    validatable on a pull request. `platformio-build`, `host-build` and
    `esp-matter-build` keep `push=${{ github.ref_name == 'master' }}`: nothing
    consumes them, so a PR builds and throws away.

  The org literal is hardcoded throughout.
- **Every image is build-validated on pull requests**, ESP-Matter included, and on
  the ESP-IDF this very run produced — so a branch bumping both versions at once is
  checked as the pair it will become, not against whatever is published today. What
  a pull request pushes is reachable by digest alone and never by name, so it leaves
  untagged blobs in GHCR and moves no tag. They accumulate; clean them up
  periodically.
- **Dependabot is the exception.** GitHub gives its runs a read-only
  `GITHUB_TOKEN` regardless of the job's `permissions:`, so the digest push would
  be rejected. Its pull requests skip the push and the digest upload, and
  `esp-matter-build` sits them out — the action bump they carry is still exercised
  by esp-idf-build compiling the image.
- **Every build job also checks the PR's head repository**, not just the owner. On
  a pull request *from* a fork `github.repository_owner` is still `jethome-iot`, so
  the owner check alone would let a fork-controlled Dockerfile run on this org's
  paid pools. The condition is
  `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`.
- Every build workflow excludes `!images/**/*.md` from its `paths:`. Negations come last
  and are order-sensitive, and `paths:` cannot be mixed with `paths-ignore:` for one
  event. Without this a documentation-only commit rebuilds and republishes every
  image.
- Every build job runs on a larger-runner pool, chosen by platform through a
  `runner` key in the matrix `include:` and read as `runs-on: ${{ matrix.runner }}`
  — `ubuntu-latest-8core` for `linux/amd64`, `ubuntu-latest-8core-arm` for
  `linux/arm64`. **Each platform builds on its own architecture**: there is no
  QEMU anywhere, and adding a platform means adding the pool for it, not emulating
  it. The mapping lives once in `images/versions.json` and is generated into every
  matrix, so a platform is added in one place; `check-versions.sh` rejects a
  platform with no pool, which would otherwise leave `runs-on` empty and the leg
  silently never starting. **Manifest jobs stay on `ubuntu-latest`** —
  they are seconds of GHCR calls, so a pool would buy nothing, and they are the
  only jobs that publish a multi-arch tag: pointing them at a pool would make tag
  publication hostage to that pool still existing and still being granted to this
  repository, and an unreachable pool queues for 24 hours rather than failing.
- **Build** timeouts live in `images/versions.json` (`timeout_minutes` per image),
  60 for every image today. The other jobs hardcode theirs in the workflow — 10 for
  a manifest, 5 for `prepare` — because the manifest matrix carries no such field;
  changing `timeout_minutes` will not move them. All of them are a ceiling on a
  wedged job, not a target.
- The slowest image is esp-matter, whose legs land at **8–11 minutes on both
  architectures**, so 60 is a five- to sevenfold margin. Do not tighten it towards
  the observed number: the failure is quiet, not loud — the leg is killed, its
  manifest is skipped with it, and the other platform's image sits in GHCR
  unreferenced while the published tags stay on the previous build. Re-measure
  before changing it; `runner-smoke.yml` reports what the pools are.
- **Nothing runs in a fork.** Those pools belong to `jethome-iot`, a fork cannot
  resolve their labels, and an unresolvable `runs-on` queues for 24 hours rather
  than failing — so the build jobs are gated on `github.repository_owner ==
  'jethome-iot'` with no `workflow_dispatch` escape hatch. A fork builds with
  `./scripts/build.sh`. Do not re-add a dispatch exception without giving the job
  a runner a fork can actually reach.
- The pool choice for `esp-matter-build` is about disk, not cores: the
  connectedhomeip tree needs ~50 GB, and the 8-core pools measured 372 GB (amd64)
  and 393 GB (arm64) free under Docker against 88 GB on 4-core. Re-measure with
  `runner-smoke.yml` before moving that job to a smaller pool. The thinning below
  shrinks the *published* image, not this requirement: what it deletes is still
  downloaded and unpacked first, inside the same layer.
- **No build cache**, by measurement: zero `cache-from`/`cache-to` hits across every
  master run, against 21.6 minutes per run spent writing the cache — for esp-idf,
  390 s of export on a 72 s build. `mode=max` wrote about 3.9 GiB per leg into a
  10 GB repository-wide quota, so LRU evicted entries during the very run that
  created them, leaving index entries whose blobs were already gone. Re-introduce it
  only against a measured, repeating hit. Builds are cold by construction.
- `workflow_dispatch` is declared with no inputs anywhere, so
  `gh workflow run … -f version=… -f force_rebuild=…` is rejected.
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
  still leaves a green build until something asks it for its version. A mirror
  serving a stale package, or an installer that exits 0 on a partial install,
  produces exactly that. Keep the layer. Both platforms must build. **What a layer
  pins, the verification prints — and for the one that changed silently, asserts.**
  `esptool` is in the esp-idf list precisely because nothing there installs it
  directly, so its layer greps for the exact
  `esptool==<version>` rather than for the name: any version passing is the bug
  itself, since ESP-IDF's own environment ships a different one. That repeats the
  number, deliberately — the two disagreeing fails the build instead of publishing
  an image contradicting its Dockerfile. The `pip freeze` beside it goes to
  `/opt/esp/python-packages.txt`, a file rather than a pipe so nothing swallows a
  failure, and **an image that installs on top regenerates it**: esp-matter's
  `install.sh` populates the same venv, so inheriting the base's snapshot would
  leave the file describing an environment that no longer exists. host takes the
  same rule one step further, because a version print cannot reach what it
  promises: its layer asserts that `clang-format` and `clang-tidy` *report* the
  numbers pip was told to install (the wrapper and the wheel are two different
  things), and then configures, builds and `ctest`s `images/host/smoke/` — two
  files that prove `find_package(GTest)` resolves, that GMock links, and that the
  paho which loads reports the version pinned beside its commit. Its own freeze
  goes to `/opt/qa-packages.txt`.
- **A version an image installs by name is a version this repository chose**, and
  `./scripts/check-pins.sh` enforces that per package manager, because the price of
  a pin differs per manager. `pip` takes `==` on every name — pip here runs with no
  constraints whatsoever (the ESP base sets `IDF_PYTHON_CHECK_CONSTRAINTS=no` and
  nothing exports `PIP_CONSTRAINT`), so a bare name resolves to whatever PyPI
  served that morning, and one tag has already carried two different harnesses.
  `pio` takes `name@version`; `@^version` is a semver range, not a pin, and it
  shipped Unity 2.6.1 under an `ARG` saying 2.6.0. `apt` is deliberately *not*
  pinned: Debian rewrites its pool at every point release so a pinned version 404s
  a quarter later, in Ubuntu the only version that never disappears is the
  release-pocket one whose pin rolls back CVE fixes, and the base image below us is
  unpinned anyway. Specs are checked after `ARG` expansion, so a range cannot hide
  in a Dockerfile default. A deliberate exception is `# pin-allow: <package> -
  <reason>` in that Dockerfile, it names a package rather than muting a rule, and
  an exception covering nothing fails the check. The gate lives in `lint.yml`, not
  in `prepare`: a Dockerfile belongs to one image, so an unpinned package in one
  must not withhold another image's tags — the cross-image blast radius is
  justified for `images/versions.json` alone, where the data really is shared.
- **Pinning the test harness pins the flasher.** `pytest-embedded` 2.x requires
  `esptool>=5.2`, nothing holds esptool back, and pip overwrites the copy ESP-IDF
  ships — while `$IDF_PATH/components/esptool_py/esptool/esptool.py` is a shim
  around `python -m esptool`, so the harness decides what `idf.py flash` runs. The
  esp-idf image therefore pins `esptool` explicitly and runs 5.3.1 against ESP-IDF
  5.5's own `esptool~=4.12`. That divergence is deliberate, measured, and resolves
  itself at ESP-IDF 6.0, whose constraints already pair esptool 5.x with
  pytest-embedded 2.x. Three ways to "fix" it that do not work, all verified:
  editing `espidf.constraints.*.txt` inside the image (it is a cache with a one-day
  TTL, restored the moment constraints are armed), re-pointing `PIP_CONSTRAINT` at
  Espressif's copy (mutable under a stable URL — the pytest pins were deleted from
  it mid-2026, and there is no per-patch file to bind instead), and arming
  `IDF_PYTHON_CHECK_CONSTRAINTS` (every `idf.py` call, `--version` included, then
  exits non-zero, and `export.sh` fails with it).
- Docker's default `SHELL` is `/bin/sh`, so an image that sets none must keep its
  `RUN` layers POSIX — check the image's own Dockerfile before reaching for a
  bash-ism. esp-idf and esp-matter set `SHELL ["/bin/bash", "-c"]` because their
  layers call the bash builtin `source`; platformio and host do not — host's
  multi-line layers are POSIX `sh` on purpose (`set -eu`, `case`, no arrays). A trailing
  `CMD ["/bin/bash"]` sets the interactive shell, not the build shell.
- Toolchain activation is per-image, not repo-wide. The ESP images source
  `${IDF_PATH}/export.sh` in every `RUN` that needs the toolchain (esp-idf
  additionally needs `export IDF_PATH_FORCE=1` in the same `RUN`; esp-matter also
  sources `${ESP_MATTER_PATH}/export.sh`), while platformio puts `pio` on `PATH`
  at install time and activates nothing, and host puts its venv (`/opt/qa-venv`)
  first on `PATH` so `ruff`/`mypy`/`clang-tidy` resolve without activation —
  Ubuntu 24.04 ships PEP 668, so there is no system interpreter to install into. Either way call tools by name, never by
  absolute path: `/opt/esp/python_env/idf5.4_py3.12_env/bin/python3` was tried and
  reverted — it pins a version-stamped directory that a version bump invalidates.
- **A repository the image built is owned by root, and the documented invocation
  runs as the caller's uid**, so git refuses it as "dubious ownership" — in the
  container only. Every image whose git matters marks its own trees:
  `espressif/idf` does `$IDF_PATH`, esp-matter does `/opt/esp-matter`, and host
  does `'*'`. The scope differs on purpose: the ESP images mark directories they
  created, while host exists to run against a checkout mounted at a path it cannot
  know (a job `container:` gets `/__w/<repo>/<repo>`). A path entry is not a
  provenance check either — git matches the path and not the owner — so what the
  narrow form buys is that the ownership check still applies everywhere else.
  Submodules are separate repositories, so esp-matter adds `/opt/esp-matter/*`
  beside the plain path: that suffix covers subdirectories on git 2.47 and is
  ignored by the 2.43 its base ships, so until the base moves a submodule wants a
  per-invocation `-c safe.directory=<path>`. Measure before restating either
  behaviour; both were established by running the two versions.
- esp-matter activates both environments at runtime through
  `ENTRYPOINT ["/opt/esp/esp_matter_entrypoint.sh"]`; overriding that entrypoint in
  a derived image silently breaks the "no sourcing needed" promise in its README.
- Thin images are deliberate: esp-matter installs with `--no-host-tool` (no
  chip-tool/chip-cert) and platformio's `pio run`/`pio test` pre-warm block is
  commented out as a "VERY LONG step". Toolchains are meant to download on first
  build. Do not "optimize" these back on.
- **esp-matter is thinned twice more, and both cuts are measured.** Its checkout
  asks `checkout_submodules.py` for `--platform esp32` alone, not the
  `esp32 linux` upstream documents — `linux` is there for the host tools this image
  does not build, and it costs eleven submodules plus three that connectedhomeip's
  own `.gitmodules` marks `excluded-platforms = esp32` (1.9 GB of tree against
  649 MB). Its install layer then sets `PW_NO_CIPD_CACHE_DIR=1` (pigweed otherwise
  keeps every CIPD package twice — unpacked, and again in `~/.cipd-cache-dir`, both
  written by the same `RUN`, 1.4 GB of duplicate) and deletes what a
  cross-compile never opens: `cipd/packages/arm` (arm-none-eabi-gcc, and a cipd
  cpython3 the venv does not use — `pigweed-venv/pyvenv.cfg` names ESP-IDF's own
  interpreter), pigweed's clang/qemu/bionic-sysroot subtrees, its OpenOCD (which
  cannot reach an ESP32 and is shadowed by ESP-IDF's `openocd-esp32` anyway), and
  `gn_out`. `gn`, `ninja`, `bin/protoc` **with `include/google` beside it**,
  `packages/zap` and `pigweed-venv` stay. Every deleted path is asserted to exist
  before it is removed, because `rm -rf` on a missing path exits 0 and the list is
  literal paths in a tree upstream rearranges; the verification layer then asserts
  the survivors — `gn` and `zap-cli` through PATH, and protoc by *compiling* a
  proto that imports `google/protobuf/descriptor.proto`, since a protoc without its
  well-known protos is a working binary that fails only later, in someone else's
  pw_rpc build. Deleting rather than not installing is the point: `install.sh` runs
  exactly as upstream wrote it, and the environment comes back by removing
  `.environment` and re-running `install.sh --no-host-tool` — the flag included,
  since the default builds chip-tool against a `linux` submodule the checkout no
  longer takes — and not by re-running `bootstrap.sh`, which has to be sourced and
  leaves CIPD reconciling against its own record rather than the files on disk. The
  protoc probe spells its path out of `ESP_MATTER_PATH` and not the tidier
  `_PW_ACTUAL_ENVIRONMENT_ROOT`, which esp-matter's `export.sh` exports only from
  v1.5.1 on: this Dockerfile also builds the pinned v1.4.2 variant, and there the
  tidier form collapses to an absolute path that does not exist — failing one CI
  leg that no local build of the primary tag reaches. The existence assertion covers
  the five paths worth hundreds of MB and not the few-MB ones, because which CIPD
  packages land in that prefix varies by platform manifest and an inventory taken on
  one architecture must not fail the build on the other. Together 17.9 GB → 10.8 GB
  unpacked, the install layer 6.9 GB → ~1.0 GB; verified by building
  `examples/light` for esp32 in the resulting image. Re-measure before restating any
  of it.
- Consequently platformio ships *platform definitions* (`espressif32`, `native`)
  without the ESP32 cross-toolchains — those arrive on the user's first build. The
  host compiler is present (`build-essential`, and the verification layer runs
  `gcc --version`), so `native` unit tests work straight away; it is the xtensa and
  RISC-V toolchains that are deferred. `ARG PIO_ENVS` exists only for the
  commented-out pre-warm block and is otherwise dead. The ESP images need no such
  step at all — `espressif/idf` already carries every toolchain.

## Documentation

- Never hardcode a version number in a README. Describe capabilities and use
  placeholders: `idf-v<version>`, `idf-v<idf-ver>-matter-v<matter-ver>`,
  `pio-v<version>`, `sha-<short-commit>`. The only exceptions are `ARG` defaults inside a
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
  `esp-matter` this way pulls its base from GHCR — to build it on an esp-idf you
  just built, pass the base explicitly:
  `docker build --build-arg BASE_IMAGE=jethome-dev-esp-idf:local --build-arg
  IDF_VERSION=v<idf-version> images/esp-matter` (the leading `v`, as the SDK
  reports it — the assertion compares the two literally) — the second arg because the version is
  asserted against the base, and its default belongs to the *published* base
  rather than to whatever you just built.
  Note that a version-bump branch cannot use the Dockerfile default at all: it
  names a tag that only exists once the branch lands.
- There is no local workflow runner. Workflow changes are validated by pushing the
  branch and reading the PR's checks; `act` and its wrapper were removed because
  they only duplicated `build.sh` behind a container.
- **Verify before finishing.** After changing an image or its README, build it
  (`./scripts/build.sh <image>`) and run the README's own examples against the
  built image. Documented paths, env vars and `docker run` lines are exactly what
  drifts, and nothing else in this repo checks them — there are no tests.
