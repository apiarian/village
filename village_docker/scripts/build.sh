#!/bin/bash
# Build the Village Docker image
# This script does NOT require --instance — the image is shared across all instances.
set -e

# Opt out of instance requirement for build
export VILLAGE_SKIP_INSTANCE_PARSE=1
export VILLAGE_SKIP_INSTANCE_REQUIRE=1

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Help text
show_help() {
    cat << EOF
Build the Village Docker image

Usage: $(basename "$0") [OPTIONS]

Note: This script does NOT require --instance. The Docker image is shared
across all instances.

Options:
    --uid UID       Set the UID for the village user in the container
                    (default: auto-detected from host village user, or 10000)
    --no-cache      Build without using Docker cache (full rebuild)
    -h, --help      Show this help message

Examples:
    # Build with auto-detected UID
    $(basename "$0")

    # Build with specific UID
    $(basename "$0") --uid 991

    # Force full rebuild
    $(basename "$0") --no-cache

Environment Variables:
    VILLAGE_UID     Alternative way to set UID (overridden by --uid flag)

Notes:
    - The UID in the container should match the UID of the host user that
      owns the instance data and logs directories
    - Run setup.sh first to create directories with correct ownership
    - Build context is the repository root, not village_docker/
    - Dockerfile is located at village_docker/Dockerfile

EOF
    exit 0
}

# Parse arguments
CUSTOM_UID=""
NO_CACHE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --uid)
            CUSTOM_UID="$2"
            shift 2
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Determine UID to use
if [[ -n "$CUSTOM_UID" ]]; then
    BUILD_UID="$CUSTOM_UID"
    info "Using custom UID: $BUILD_UID"
elif [[ -n "$VILLAGE_UID" ]]; then
    BUILD_UID="$VILLAGE_UID"
    info "Using UID from VILLAGE_UID environment variable: $BUILD_UID"
else
    BUILD_UID=$(get_village_uid)
    info "Auto-detected village user UID: $BUILD_UID"
fi

# Validate UID is numeric
if ! [[ "$BUILD_UID" =~ ^[0-9]+$ ]]; then
    error "UID must be numeric, got: $BUILD_UID"
    exit 1
fi

# Navigate to repository root
cd "$SCRIPT_REPO"

# Check that Dockerfile exists
if [[ ! -f "$SCRIPT_REPO/village_docker/Dockerfile" ]]; then
    error "Dockerfile not found at: $SCRIPT_REPO/village_docker/Dockerfile"
    exit 1
fi

info "Building Village Docker image..."
info "  Image name: $IMAGE_NAME"
info "  Container UID: $BUILD_UID"
info "  Build context: $SCRIPT_REPO"
info "  Dockerfile: $SCRIPT_REPO/village_docker/Dockerfile"

if [[ -n "$NO_CACHE" ]]; then
    warn "Building without cache (full rebuild)"
fi

# Build the image
debug "Running: docker build $NO_CACHE --progress=plain --build-arg VILLAGE_UID=$BUILD_UID -f village_docker/Dockerfile -t $IMAGE_NAME ."

if docker build $NO_CACHE \
    --progress=plain \
    --build-arg VILLAGE_UID="$BUILD_UID" \
    -f village_docker/Dockerfile \
    -t "$IMAGE_NAME" \
    .; then
    
    info "✓ Build successful!"
    info ""
    info "Image details:"
    docker images "$IMAGE_NAME" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    
    info ""
    info "Next steps:"
    info "  1. Ensure setup.sh --instance <name> has been run to create directories"
    info "  2. Edit the instance config (set FLASK_SECRET_KEY, HOST_PORT, etc.)"
    info "  3. Run: $SCRIPT_DIR/run-script.sh --instance <name> initialize-repository"
    info "  4. Run: $SCRIPT_DIR/run-script.sh --instance <name> create-user"
    info "  5. Run: $SCRIPT_DIR/start.sh --instance <name>"
else
    error "Build failed!"
    exit 1
fi
