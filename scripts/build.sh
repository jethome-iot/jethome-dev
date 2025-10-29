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

# Image tag for local builds
IMAGE_TAG="${IMAGE_TAG:-local}"

# Discover available images from images/ directory
# Each subdirectory with a Dockerfile is considered an image
declare -A IMAGES=()

discover_images() {
    local images_dir="images"
    
    if [ ! -d "$images_dir" ]; then
        echo "Error: $images_dir directory not found"
        exit 1
    fi
    
    for dir in "$images_dir"/*/ ; do
        if [ -d "$dir" ]; then
            local name=$(basename "$dir")
            if [ -f "$dir/Dockerfile" ]; then
                IMAGES["$name"]="$images_dir/$name"
            fi
        fi
    done
    
    if [ ${#IMAGES[@]} -eq 0 ]; then
        echo "Error: No images found in $images_dir directory"
        exit 1
    fi
}

# Discover images on script start
discover_images

# Print colored message
print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [IMAGE_NAME|all]

Build Docker images locally.

Options:
    -r, --run     Run the image interactively after successful build (single image only)
    -h, --help    Show this help message

Arguments:
    IMAGE_NAME    Name of the image to build (auto-discovered from images/ directory)
    all           Build all images

Available images:
EOF
    for name in $(printf '%s\n' "${!IMAGES[@]}" | sort); do
        echo "    - $name"
    done
    cat << EOF

Environment Variables:
    IMAGE_TAG     Docker image tag to use (default: local)

Without arguments, runs in interactive mode.

Examples:
    $0 esp-idf                    # Build ESP-IDF image with 'local' tag
    $0 -r esp-idf                 # Build and run ESP-IDF image interactively
    $0 platformio --run           # Build and run PlatformIO image interactively
    IMAGE_TAG=latest $0 esp-idf   # Build with custom tag
    $0 all                        # Build all images
    $0                            # Interactive mode

EOF
}

# Run an image interactively
run_image() {
    local name=$1
    
    print_color "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$GREEN" "Running: jethome-dev-${name}:${IMAGE_TAG}"
    print_color "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    docker run -it --rm -v "$(pwd):/workspace" "jethome-dev-${name}:${IMAGE_TAG}"
}

# Build a specific image
build_image() {
    local name=$1
    local run_after_build=${2:-false}
    local context=${IMAGES[$name]}
    
    if [ -z "$context" ]; then
        print_color "$RED" "Error: Unknown image '$name'"
        echo "Available images: ${!IMAGES[@]}"
        exit 1
    fi
    
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$BLUE" "Building: jethome-dev-${name}:${IMAGE_TAG}"
    print_color "$BLUE" "Context:  ${context}"
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    if ! docker build -t "jethome-dev-${name}:${IMAGE_TAG}" "$context"; then
        print_color "$RED" "✗ Build failed for ${name}"
        return 1
    fi
    
    echo
    print_color "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$GREEN" "✓ Successfully built: jethome-dev-${name}:${IMAGE_TAG}"
    print_color "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    # Run the image if requested
    if [ "$run_after_build" == "true" ]; then
        echo
        run_image "$name"
        return 0
    fi
    
    print_color "$YELLOW" "To run the image interactively:"
    echo
    print_color "$BLUE" "  docker run -it --rm -v \$(pwd):/workspace jethome-dev-${name}:${IMAGE_TAG}"
    echo
    print_color "$YELLOW" "For usage examples and build commands, see:"
    echo
    print_color "$BLUE" "  ${context}/README.md"
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
            if build_image "$name" "false"; then
                # Prompt to run after successful build
                read -p "Do you want to run this image in interactive mode? (y/n): " run_choice
                if [[ "$run_choice" =~ ^[Yy]$ ]]; then
                    echo
                    run_image "$name"
                fi
                echo
            fi
        done
    elif [ "$choice" -ge 1 ] && [ "$choice" -lt "$idx" ]; then
        # Build selected
        local selected="${image_names[$((choice-1))]}"
        if build_image "$selected" "false"; then
            # Prompt to run after successful build
            read -p "Do you want to run this image in interactive mode? (y/n): " run_choice
            if [[ "$run_choice" =~ ^[Yy]$ ]]; then
                echo
                run_image "$selected"
            fi
        fi
    else
        print_color "$RED" "Invalid choice."
        exit 1
    fi
}

# Main
main() {
    # Change to repository root
    cd "$(dirname "$0")/.."
    
    # Parse command-line flags
    local run_flag=false
    local image_name=""
    
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -r|--run)
                run_flag=true
                shift
                ;;
            -*)
                print_color "$RED" "Error: Unknown option '$1'"
                usage
                exit 1
                ;;
            *)
                if [ -z "$image_name" ]; then
                    image_name="$1"
                else
                    print_color "$RED" "Error: Multiple image names provided"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Handle different modes
    if [ -z "$image_name" ]; then
        # Interactive mode
        if [ "$run_flag" == "true" ]; then
            print_color "$YELLOW" "Warning: -r/--run flag is ignored in interactive mode"
            echo
        fi
        interactive_mode
    elif [ "$image_name" == "all" ]; then
        # Build all images
        if [ "$run_flag" == "true" ]; then
            print_color "$YELLOW" "Warning: -r/--run flag is only supported for single image builds"
            echo
        fi
        for name in "${!IMAGES[@]}"; do
            build_image "$name" "false"
        done
    else
        # Build specific image
        build_image "$image_name" "$run_flag"
    fi
}

main "$@"

