#!/usr/bin/env bash
#
# Build Docker images locally
# Supports both interactive and argument-based usage
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Available images
declare -A IMAGES=(
    ["esp-idf"]="images/esp-idf"
    ["platformio"]="images/platformio"
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
Usage: $0 [IMAGE_NAME|all]

Build Docker images locally.

Arguments:
    IMAGE_NAME    Name of the image to build (esp-idf, platformio)
    all           Build all images

Without arguments, runs in interactive mode.

Examples:
    $0 esp-idf        # Build ESP-IDF image
    $0 platformio     # Build PlatformIO image
    $0 all            # Build all images
    $0                # Interactive mode

EOF
}

# Build a specific image
build_image() {
    local name=$1
    local context=${IMAGES[$name]}
    
    if [ -z "$context" ]; then
        print_color "$RED" "Error: Unknown image '$name'"
        echo "Available images: ${!IMAGES[@]}"
        exit 1
    fi
    
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$BLUE" "Building: jethome-dev-${name}"
    print_color "$BLUE" "Context:  ${context}"
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    if ! docker build -t "jethome-dev-${name}:latest" "$context"; then
        print_color "$RED" "✗ Build failed for ${name}"
        return 1
    fi
    
    echo
    print_color "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$GREEN" "✓ Successfully built: jethome-dev-${name}:latest"
    print_color "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    print_color "$YELLOW" "To enter the image in interactive mode:"
    echo
    print_color "$BLUE" "  docker run -it --rm -v \$(pwd):/workspace jethome-dev-${name}:latest"
    echo
    print_color "$YELLOW" "To build your project:"
    echo
    
    if [ "$name" == "esp-idf" ]; then
        print_color "$BLUE" "  docker run --rm -v \$(pwd):/workspace jethome-dev-${name}:latest idf.py build"
    elif [ "$name" == "platformio" ]; then
        print_color "$BLUE" "  docker run --rm -v \$(pwd):/workspace jethome-dev-${name}:latest pio run"
    fi
    
    echo
    print_color "$YELLOW" "See ${context}/README.md for more usage examples."
    echo
}

# Interactive mode
interactive_mode() {
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$BLUE" "JetHome Dev - Docker Image Builder"
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Select image to build:"
    echo
    
    local idx=1
    local -a image_names=()
    
    for name in "${!IMAGES[@]}"; do
        echo "  ${idx}) ${name}"
        image_names+=("$name")
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
        # Build all
        for name in "${image_names[@]}"; do
            build_image "$name"
        done
    elif [ "$choice" -ge 1 ] && [ "$choice" -lt "$idx" ]; then
        # Build selected
        local selected="${image_names[$((choice-1))]}"
        build_image "$selected"
    else
        print_color "$RED" "Invalid choice."
        exit 1
    fi
}

# Main
main() {
    # Change to repository root
    cd "$(dirname "$0")/.."
    
    if [ $# -eq 0 ]; then
        # Interactive mode
        interactive_mode
    elif [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        usage
        exit 0
    elif [ "$1" == "all" ]; then
        # Build all images
        for name in "${!IMAGES[@]}"; do
            build_image "$name"
        done
    else
        # Build specific image
        build_image "$1"
    fi
}

main "$@"

