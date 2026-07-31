#!/usr/bin/env bash
#
# Test GitHub Actions workflows locally with act
# Supports both interactive and argument-based usage
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Available images and the workflow file holding their <image>-build job.
# ESP-Matter has no workflow of its own - its jobs live in esp-idf.yml.
declare -A WORKFLOWS=(
    ["esp-idf"]=".github/workflows/esp-idf.yml"
    ["esp-matter"]=".github/workflows/esp-idf.yml"
    ["platformio"]=".github/workflows/platformio.yml"
)

# Print colored message
print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Print usage
usage() {
    cat << EOF
Usage: $0 [WORKFLOW_NAME|all] [--no-dryrun]

Test GitHub Actions workflows locally using act.

Runs the image's <image>-build job as a workflow_dispatch event with the ref
overridden, so the job always runs (also on a fork) and never pushes to GHCR.
The manifest jobs are not run: they only push.

Arguments:
    IMAGE_NAME       Image whose build job to test (esp-idf, esp-matter, platformio)
    all              Test all images
    --no-dryrun      Run actual workflow (default is dry-run)

Without arguments, runs in interactive mode.

Examples:
    $0 esp-idf           # Dry-run ESP-IDF build job
    $0 platformio        # Dry-run PlatformIO build job
    $0 all               # Dry-run every build job
    $0 esp-idf --no-dryrun    # Actually run the build job
    $0                   # Interactive mode

Note: esp-matter builds the connectedhomeip submodule tree and needs ~50GB of
disk plus several hours - it is why that job runs on a self-hosted runner in CI.

Requirements:
    act - https://github.com/nektos/act

EOF
}

# Check if act is installed
check_act() {
    if ! command -v act &> /dev/null; then
        print_color "$RED" "Error: 'act' is not installed."
        echo
        print_color "$YELLOW" "Install act:"
        echo
        echo "  macOS:   brew install act"
        echo "  Linux:   curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash"
        echo "  Windows: choco install act-cli"
        echo
        echo "More info: https://github.com/nektos/act"
        exit 1
    fi
}

# Test a specific workflow
test_workflow() {
    local name=$1
    local dryrun=$2
    local workflow=${WORKFLOWS[$name]}
    
    if [ -z "$workflow" ]; then
        print_color "$RED" "Error: Unknown image '$name'"
        echo "Available images: ${!WORKFLOWS[@]}"
        exit 1
    fi
    
    local dryrun_flag=""
    if [ "$dryrun" == "true" ]; then
        dryrun_flag="--dryrun"
    fi
    
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$BLUE" "Testing workflow: ${name}"
    print_color "$BLUE" "File:             ${workflow}"
    print_color "$BLUE" "Mode:             $([ "$dryrun" == "true" ] && echo "dry-run" || echo "actual run")"
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    # Only the build job: the manifest jobs push to GHCR.
    #
    # workflow_dispatch  - the build jobs are guarded by
    #                      `if: owner == 'jethome-iot' || event_name == 'workflow_dispatch'`.
    #                      act derives the owner from the git remote, so on a fork
    #                      a push event would skip the job and still exit 0 - a
    #                      green result for a workflow that never ran.
    # GITHUB_REF_NAME    - the login step and `push:` are gated on
    #                      `ref_name == 'master'`. Overriding the ref keeps both
    #                      false, so --no-dryrun can never publish a locally built
    #                      image to GHCR. act takes ref_name from this variable but
    #                      always reads the owner from the remote, so this is the
    #                      half that can be forced.
    # --matrix           - one platform is enough locally; .actrc pins the runner
    #                      container to linux/amd64 anyway.
    if act workflow_dispatch -j "${name}-build" -W "$workflow" \
        --env GITHUB_REF_NAME=act-local \
        --matrix platform:linux/amd64 \
        $dryrun_flag; then
        echo
        print_color "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_color "$GREEN" "✓ Workflow test passed: ${name}"
        print_color "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo
        return 0
    else
        echo
        print_color "$RED" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_color "$RED" "✗ Workflow test failed: ${name}"
        print_color "$RED" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo
        return 1
    fi
}

# Interactive mode
interactive_mode() {
    local dryrun=$1
    
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$BLUE" "JetHome Dev - Workflow Tester (act)"
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    print_color "$YELLOW" "Mode: $([ "$dryrun" == "true" ] && echo "dry-run (syntax check)" || echo "actual run")"
    echo
    echo "Select image to test:"
    echo
    
    local idx=1
    local -a workflow_names=()
    
    for name in "${!WORKFLOWS[@]}"; do
        echo "  ${idx}) ${name}"
        workflow_names+=("$name")
        ((idx++))
    done
    
    echo "  ${idx}) all"
    echo "  0) exit"
    echo
    
    read -p "Enter your choice [0-${idx}]: " choice
    echo
    
    if [ "$choice" == "0" ]; then
        print_color "$YELLOW" "Cancelled."
        exit 0
    elif [ "$choice" == "$idx" ]; then
        # Test all
        local failed=0
        for name in "${workflow_names[@]}"; do
            test_workflow "$name" "$dryrun" || failed=1
        done
        exit $failed
    elif [ "$choice" -ge 1 ] && [ "$choice" -lt "$idx" ]; then
        # Test selected
        local selected="${workflow_names[$((choice-1))]}"
        test_workflow "$selected" "$dryrun"
    else
        print_color "$RED" "Invalid choice."
        exit 1
    fi
}

# Main
main() {
    # Change to repository root
    cd "$(dirname "$0")/.."
    
    # Check if act is installed
    check_act
    
    # Parse arguments
    local dryrun="true"
    local target=""
    
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --no-dryrun)
                dryrun="false"
                shift
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done
    
    if [ -z "$target" ]; then
        # Interactive mode
        interactive_mode "$dryrun"
    elif [ "$target" == "all" ]; then
        # Test all workflows
        local failed=0
        for name in "${!WORKFLOWS[@]}"; do
            test_workflow "$name" "$dryrun" || failed=1
        done
        exit $failed
    else
        # Test specific workflow
        test_workflow "$target" "$dryrun"
    fi
}

main "$@"

