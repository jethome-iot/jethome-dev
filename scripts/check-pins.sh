#!/usr/bin/env bash
# Enforce that every package an image installs by name is installed at a version
# this repository chose.
#
# Usage: ./scripts/check-pins.sh [--strict-apt]
#
# images/versions.json pins what CI *builds*. Nothing pinned what a build
# *installs*: `pip install pytest` resolved to whatever PyPI served that morning,
# so one tag carried two different test harnesses across two rebuilds, and the
# `<prefix>-<version>-sha-<short-commit>` tag - which the READMEs document as the
# thing to roll back to - stopped naming a tree. Worse, the drift reached past the
# harness: pytest-embedded 2.x requires esptool>=5.2 and pip overwrote the copy
# ESP-IDF ships, so an unpinned test dependency silently decided what `idf.py
# flash` runs. See issue #18.
#
# The rule is per package manager, because the cost of pinning is:
#
#   pip - a gate. Every package named on a `pip install` line carries `==` and an
#         exact version after it (`==9.*` is a PEP 440 prefix match, so it is a
#         range wearing a pin's clothes), a VCS reference names a full commit, and
#         a URL carries a `#sha256=`. PyPI never deletes a release, so a pin costs
#         nothing and holds. A `-r` file is followed into the build context and
#         held to the same rule; a `-c` file is *not* a pin - constraints bound
#         only the names they list - and neither excuses the packages named
#         alongside them on the same command line.
#   pio - a gate. `pio platform install` and `pio pkg install` take `name@version`,
#         and `@^version` is a *range*: `Unity@^2.6.0` shipped 2.6.1 under an ARG
#         that says 2.6.0. Specs are compared after ARG expansion, so a range
#         cannot hide one level down in a Dockerfile default.
#   apt - advisory, and a gate only under --strict-apt. Deliberate, and not for
#         the reason the workflow used to give: Debian rewrites its pool at every
#         point release (a pinned `curl=7.88.1-10+deb12u14` is a 404 for whoever
#         rebuilds a quarter later), and in Ubuntu the only version that never
#         disappears is the release-pocket one - pinning `jq=1.7.1-3build1` rolls
#         back six CVE fixes. Do not flip this default without rewriting that
#         paragraph in CLAUDE.md first.
#
# An intentional exception is written next to the thing it excuses, names one
# package rather than muting a rule, and carries a reason:
#
#   # pin-allow: <package> - <reason>
#
# anywhere in the Dockerfile it applies to - above or below the install, since
# allowances are collected in a pass of their own. An allowance that matches
# nothing is itself a failure - that is what stops a stale exception from silently
# covering a package added under it years later, which is the failure mode of
# hadolint's `# hadolint ignore=DL3013`: it mutes the whole instruction, keeps
# muting it as packages are added, and survives even a rule raised to `error`.
#
# What this check does NOT see: packages a script the Dockerfile runs installs for
# itself (esp-matter's `./install.sh`), and everything the base image already
# carries. Both are reported as `·` lines rather than passed over in silence.
set -euo pipefail

# Associative arrays and `[[ =~ ]]`, same bash-4 floor scripts/check-versions.sh
# already stands on with `mapfile`. Named here because the failure is otherwise a
# bare `declare: -A: invalid option` from macOS's system bash 3.2.
if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "This script needs bash 4 or newer; you are on ${BASH_VERSION:-a non-bash shell}." >&2
    echo "On macOS: brew install bash, or run it as \`\$(brew --prefix)/bin/bash $0\`." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

strict_apt=0
if [ "${1:-}" = "--strict-apt" ]; then
    strict_apt=1
elif [ -n "${1:-}" ]; then
    echo "Usage: $0 [--strict-apt]" >&2
    exit 2
fi

fail=0
problem() {
    echo "  ✗ $*" >&2
    fail=1
}

# Join a Dockerfile into logical instructions the way the builder does, and emit
# `<first-line-number><TAB><kind><TAB><text>`, where kind is `#` for a comment line
# and `.` for an instruction. Reimplemented rather than shelled out to, because
# this check must run without pulling an image - but the rules below are
# buildkit's, and the output was diffed against `conftest parse --parser
# dockerfile` on every Dockerfile here:
#
#   1. A line ending in `\` continues onto the next one.
#   2. A line whose first non-blank character is `#` is a comment. It is removed
#      *without* ending a continuation - which is the whole difficulty, since
#      images/esp-idf/Dockerfile comments its package list from the inside - and a
#      `\` at the end of a comment continues nothing.
#   3. A blank line inside a continuation is removed the same way.
#
# A `#` anywhere other than the start of a line belongs to the shell, not to the
# Dockerfile, and is left alone.
join_instructions() {
    awk '
        BEGIN { acc = ""; cont = 0; start = 0 }
        {
            stripped = $0
            sub(/^[ \t]+/, "", stripped)
            if (stripped ~ /^#/) { print NR "\t#\t" stripped; next }
            if (stripped == "") next
            if (cont) { acc = acc " " stripped } else { acc = stripped; start = NR }
            if (acc ~ /\\$/) { sub(/[ \t]*\\$/, "", acc); cont = 1; next }
            cont = 0
            print start "\t.\t" acc
            acc = ""
        }
        END { if (acc != "") print start "\t.\t" acc }
    ' "$1"
}

# Flags that swallow the next word. Without this list `-r /tmp/requirements.txt`
# reads as an unpinned package called `/tmp/requirements.txt` - the most likely
# false positive, and the reason a regex over the raw line is not enough. A flag
# missing from this list fails *loudly and wrongly*, naming a package that does
# not exist (`--trusted-host pypi.org` reported `pypi.org` as unpinned), so the
# list covers every value-taking pip flag rather than the ones in use today.
pip_flag_takes_value() {
    case "$1" in
    -r | --requirement | -c | --constraint | -e | --editable | -i | --index-url \
        | --extra-index-url | -f | --find-links | -t | --target | --prefix \
        | --root | --python-version | --platform | --abi | --implementation \
        | --trusted-host | --no-binary | --only-binary | --upgrade-strategy \
        | --proxy | --retries | --timeout | --exists-action | --cert \
        | --client-cert | --cache-dir | --log | --src | --report \
        | --config-settings | -C | --global-option | --install-option \
        | --build-option | --progress-bar | --root-user-action)
        return 0
        ;;
    esac
    return 1
}

# Is this token pinned? The rule is per manager, and sharing it is silent in the
# direction that matters: `owner/library` is a *path* to pip and a *name* to pio,
# so one "a slash means pinned" rule would accept `pio pkg install
# throwtheswitch/Unity` - the unpinned form this check exists to catch.
is_pinned_spec() {
    local manager=$1 spec=$2 version rev
    case "${manager}" in
    pip)
        case "${spec}" in
        # A VCS install names an exact tree only when it carries a commit. A bare
        # `git+https://host/repo.git`, or one ending in `@main`, clones whatever
        # that branch points at on build day - the most unpinned form pip has, and
        # the one that used to pass here because it "looked like a URL".
        git+*)
            case "${spec}" in
            *@*) rev=${spec##*@} ;;
            *) return 1 ;;
            esac
            rev=${rev%%#*}
            [ "${#rev}" -eq 40 ] || return 1
            case "${rev}" in
            *[!0-9a-f]*) return 1 ;;
            *) return 0 ;;
            esac
            ;;
        # A plain URL is a moving target unless it carries a hash: pip accepts
        # `#sha256=...` and verifies it, and `…/pkg-latest.tar.gz` is exactly the
        # nightly this check exists to reject.
        http://* | https://*)
            case "${spec}" in
            *'#sha256='*) return 0 ;;
            *) return 1 ;;
            esac
            ;;
        # A local path is fixed by this repository's own tree.
        . | .. | ./* | ../* | /*) return 0 ;;
        esac
        # `==` and an exact version after it. A range is a decision deferred to
        # build day, which is the whole defect: `pytest>=8` re-resolves on every
        # rebuild exactly like a bare name, and so does the PEP 440 prefix match
        # `pytest==9.*`. `pkg==${VAR}` counts - the value lives in an ARG default
        # that check-versions.sh compares against images/versions.json, so the
        # number is pinned there and the shape is what matters here.
        case "${spec}" in
        *==*)
            version=${spec#*==}
            [ -n "${version}" ] || return 1
            case "${version}" in
            *[*,\ \<\>!~]*) return 1 ;;
            *) return 0 ;;
            esac
            ;;
        esac
        ;;
    pio)
        # `espressif32@6.11.0` - the version always follows an `@`, and it has to
        # be a version rather than a range: `@^2.6.0` and `@~2.6.0` are semver
        # ranges, and `@>=2.6.0` is one too.
        case "${spec}" in
        *@*)
            version=${spec##*@}
            [ -n "${version}" ] || return 1
            # `^` deliberately not first in the class: leading it would negate.
            case "${version}" in
            *[~^\<\>*,\ ]*) return 1 ;;
            *) return 0 ;;
            esac
            ;;
        esac
        ;;
    apt)
        # apt spells it with a single `=`: `jq=1.7.1-3build1`.
        case "${spec}" in
        *=*) return 0 ;;
        esac
        ;;
    esac
    return 1
}

echo "==> package pins"
for dockerfile in images/*/Dockerfile; do
    image=$(basename "$(dirname "${dockerfile}")")
    echo "==> ${image}"

    # ARG defaults, so a spec assembled from one is checked by its value and not
    # by its shape. Without this `espressif32@${ESP32_PLATFORM_VERSION}` passes
    # whatever the default holds, including a range - and those ARGs are exactly
    # the ones CI never passes, so the Dockerfile default is their only source of
    # truth (see images/versions.json's _readme).
    declare -A argval=()
    while IFS= read -r line; do
        key=${line%%=*}
        argval["${key}"]=${line#*=}
    done < <(sed -n 's/^ARG \([A-Za-z_][A-Za-z0-9_]*\)=\(.*\)$/\1=\2/p' "${dockerfile}")

    expand_args() {
        local text=$1 key
        for key in "${!argval[@]}"; do
            text=${text//\$\{${key}\}/${argval[${key}]}}
            text=${text//\$${key}/${argval[${key}]}}
        done
        printf '%s' "${text}"
    }

    # Allowances, and the set actually used, so one that covers nothing is
    # reported at the end.
    declare -A allowed=()
    declare -A allow_line=()
    declare -A allow_used=()

    # Collected in a pass of their own, so an allowance holds wherever it is
    # written. Registering them while checking would silently make one cover only
    # the installs *below* it, and an allowance written under its install would
    # then produce two contradictory errors at once - the package reported
    # unpinned, and the exception naming it reported stale.
    while IFS=$'\t' read -r lineno kind text; do
        [ "${kind}" = "#" ] || continue
        # Anchored to the start of the comment. An unanchored match reads any
        # prose that merely mentions `pin-allow:` - documenting this very
        # mechanism, which is exactly the commenting style this repository uses -
        # as an allowance for whatever word follows, and then fails the build
        # because that word covers nothing.
        [[ ${text} =~ ^#[[:space:]]*pin-allow:[[:space:]]*(.*)$ ]] || continue
        spec=${BASH_REMATCH[1]}
        # The package is the first word, the reason is the rest. Split on
        # whitespace, never on the `-`: `pytest-embedded` would become `pytest`,
        # and the allowance would then cover a package nobody wrote down.
        # shellcheck disable=SC2086
        set -- ${spec}
        pkg=${1:-}
        shift || true
        reason="$*"
        reason=${reason#- }
        reason=${reason#-}
        if [ -z "${pkg}" ] || [ -z "${reason}" ]; then
            problem "${dockerfile}:${lineno}: 'pin-allow' needs '<package> - <reason>'; an exception with no reason cannot be reviewed"
            continue
        fi
        allowed["${pkg}"]=1
        allow_line["${pkg}"]=${lineno}
    done < <(join_instructions "${dockerfile}")

    while IFS=$'\t' read -r lineno kind text; do
        [ "${kind}" = "." ] || continue

        # Only RUN carries package installs. Its own flags are dropped first:
        # `${text#* }` alone leaves `--mount=type=cache,…` as the sub-command's
        # first word, and the dispatch below then matches nothing - turning the
        # check off for that layer with no diagnostic.
        case "${text}" in
        [Rr][Uu][Nn][[:space:]]*) body=${text#* } ;;
        *) continue ;;
        esac
        while :; do
            case "${body}" in
            --*[[:space:]]*) body=${body#* } ;;
            *) break ;;
            esac
        done
        body=$(expand_args "${body}")

        # Split into sub-commands: `pip install` after `source export.sh &&` has to
        # be found, and `pip install a && pip install b` has to be found twice. awk
        # rather than `sed 's/&&/\n/g'`, whose newline in the replacement is a GNU
        # extension this repository cannot rely on (scripts run on macOS too).
        while IFS= read -r sub; do
            # Word splitting without globbing: unguarded, `pip install *` expands
            # against the repository's own working directory and the check then
            # reports whatever files happen to sit there.
            set -f
            # shellcheck disable=SC2086
            set -- ${sub}
            set +f
            [ "$#" -gt 0 ] || continue

            # An installer script resolves and installs packages this check cannot
            # see - esp-matter's `./install.sh --no-host-tool` populates the very
            # venv esp-idf pins. Saying so is the honest half of the guarantee: the
            # gate covers what a Dockerfile names, not what a script it runs does.
            case "$1" in
            ./*.sh | /*.sh | *install.sh | bash | sh)
                echo "  · ${dockerfile}:${lineno}: '$1' installs through a script - its packages are outside this check"
                ;;
            esac

            manager=""
            case "$1" in
            pip | pip3)
                [ "${2:-}" = "install" ] && manager=pip && shift 2
                ;;
            python | python3)
                if [ "${2:-}" = "-m" ] && { [ "${3:-}" = "pip" ] || [ "${3:-}" = "pip3" ]; } && [ "${4:-}" = "install" ]; then
                    manager=pip
                    shift 4
                fi
                ;;
            pio)
                if [ "${2:-}" = "platform" ] || [ "${2:-}" = "pkg" ]; then
                    [ "${3:-}" = "install" ] && manager=pio && shift 3
                fi
                ;;
            apt-get | apt)
                [ "${2:-}" = "install" ] && manager=apt && shift 2
                ;;
            esac
            [ -n "${manager}" ] || continue

            # A requirements file carries pins of its own, so it is followed into
            # the build context and its lines are held to the same rule. A
            # *constraints* file is not the same thing and never was: it bounds
            # only the names it happens to list, so `pip install -c c.txt pytest`
            # leaves pytest free to re-resolve. Neither one excuses the rest of the
            # command line - the packages named alongside the file are checked
            # below like any other, which is what a `continue` here used to skip.
            want_file=""
            req_kind=""
            for arg in "$@"; do
                if [ -n "${want_file}" ] && [ "${want_file}" = "pending" ]; then
                    want_file=${arg}
                    # The path is the one *inside* the image, so it cannot be looked
                    # up on disk. What is checkable is that a file of that name
                    # reaches the image at all: the build context is images/<name>
                    # (CLAUDE.md), so it is either COPYed from there or it does not
                    # exist and pip resolves nothing.
                    case "${want_file}" in
                    *'$'*) ;; # assembled from a variable - unresolvable here
                    *)
                        base=${want_file##*/}
                        if ! grep -qiF "${base}" "${dockerfile}" && [ ! -e "images/${image}/${base}" ]; then
                            problem "${dockerfile}:${lineno}: pip reads '${want_file}', but nothing in images/${image}/ provides '${base}' - the pins it is supposed to carry do not exist"
                        elif [ -f "images/${image}/${base}" ] && [ "${req_kind}" = "requirement" ]; then
                            while IFS= read -r req; do
                                req=${req%%#*}
                                req=${req%"${req##*[![:space:]]}"}
                                req=${req#"${req%%[![:space:]]*}"}
                                [ -n "${req}" ] || continue
                                case "${req}" in -*) continue ;; esac
                                is_pinned_spec pip "${req%% *}" && continue
                                problem "images/${image}/${base}: '${req%% *}' has no exact version - a file of ranges pins nothing"
                            done < "images/${image}/${base}"
                        fi
                        ;;
                    esac
                    want_file=""
                    continue
                fi
                case "${arg}" in
                -r | --requirement)
                    want_file="pending"
                    req_kind="requirement"
                    ;;
                -c | --constraint)
                    want_file="pending"
                    req_kind="constraint"
                    ;;
                esac
            done

            skip_next=0
            for arg in "$@"; do
                if [ "${skip_next}" -eq 1 ]; then
                    skip_next=0
                    continue
                fi
                case "${arg}" in
                --*=*) continue ;;
                -*)
                    if [ "${manager}" = "pip" ] && pip_flag_takes_value "${arg}"; then
                        skip_next=1
                    fi
                    continue
                    ;;
                esac
                # `pio pkg install -g --library "throwtheswitch/Unity@2.6.1"` puts
                # the spec in quotes, and they survive the split above.
                spec=${arg%\"}
                spec=${spec#\"}
                spec=${spec%\'}
                spec=${spec#\'}
                [ -n "${spec}" ] || continue

                is_pinned_spec "${manager}" "${spec}" && continue

                name=${spec%%[<>=~!@^]*}
                name=${name##*/}
                if [ -n "${allowed[${name}]:-}" ]; then
                    allow_used["${name}"]=1
                    continue
                fi

                if [ "${manager}" = "apt" ] && [ "${strict_apt}" -eq 0 ]; then
                    echo "  · ${dockerfile}:${lineno}: apt installs '${spec}' unpinned (advisory - see the header of this script)"
                    continue
                fi
                problem "${dockerfile}:${lineno}: ${manager} installs '${spec}' with no exact version - a rebuild resolves it again"
            done
        done < <(printf '%s\n' "${body}" | awk '{ gsub(/&&|\|\||;|\|/, "\n"); print }')
    done < <(join_instructions "${dockerfile}")

    for pkg in "${!allowed[@]}"; do
        [ -n "${allow_used[${pkg}]:-}" ] \
            || problem "${dockerfile}:${allow_line[${pkg}]}: 'pin-allow: ${pkg}' covers nothing - a stale exception silently covers whatever is added under it"
    done
    unset argval allowed allow_line allow_used
done

if [ "${fail}" -ne 0 ]; then
    echo "==> packages are not pinned" >&2
    exit 1
fi
# Deliberately narrower than "everything is pinned": what a script an image runs
# installs for itself is outside this check (the `·` lines above say where), and
# so is the base image's own environment.
echo "==> every package these Dockerfiles name is pinned"
