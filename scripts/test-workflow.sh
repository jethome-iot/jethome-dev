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

# Available workflows
declare -A WORKFLOWS=(
    ["esp-idf"]=".github/workflows/esp-idf.yml"
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

Arguments:
    WORKFLOW_NAME    Name of the workflow to test (esp-idf, platformio)
    all              Test all workflows
    --no-dryrun      Run actual workflow (default is dry-run)

Without arguments, runs in interactive mode.

Examples:
    $0 esp-idf           # Dry-run ESP-IDF workflow
    $0 platformio        # Dry-run PlatformIO workflow
    $0 all               # Dry-run all workflows
    $0 esp-idf --no-dryrun    # Actually run the workflow
    $0                   # Interactive mode

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
        print_color "$RED" "Error: Unknown workflow '$name'"
        echo "Available workflows: ${!WORKFLOWS[@]}"
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
    
    if act -j build -W "$workflow" $dryrun_flag; then
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
    echo "Select workflow to test:"
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

