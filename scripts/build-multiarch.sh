#!/bin/bash
set -euo pipefail

# Multi-architecture Docker build script for kube-powertools
# Supports: linux/amd64, linux/arm64
#
# Usage:
#   ./scripts/build-multiarch.sh [OPTIONS]
#
# Options:
#   -t, --tag TAG           Image tag (default: dev)
#   -p, --platforms LIST    Comma-separated platform list (default: linux/amd64,linux/arm64)
#   -r, --registry REGISTRY Registry prefix (default: ghcr.io/chgl)
#   --push                  Push images to registry
#   --load                  Load images into local Docker daemon (single platform only)
#   -h, --help              Show this help message
#
# Examples:
#   # Build locally with default settings
#   ./scripts/build-multiarch.sh
#
#   # Build and push to registry
#   ./scripts/build-multiarch.sh --tag v2.5.30 --push
#
#   # Build specific platforms only
#   ./scripts/build-multiarch.sh --platforms linux/arm64 --tag latest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
TAG="dev"
PLATFORMS="linux/amd64,linux/arm64"
REGISTRY="ghcr.io/chgl"
PUSH=""
LOAD=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    sed -n '/^# /,/^#$/p' "$0" | sed 's/^# //' | sed 's/^#$//'
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--tag)
                TAG="$2"
                shift 2
                ;;
            -p|--platforms)
                PLATFORMS="$2"
                shift 2
                ;;
            -r|--registry)
                REGISTRY="$2"
                shift 2
                ;;
            --push)
                PUSH="true"
                shift
                ;;
            --load)
                LOAD="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi

    # Check Docker buildx
    if ! docker buildx version &> /dev/null; then
        log_error "Docker buildx is not available. Please enable experimental features or upgrade Docker."
        exit 1
    fi

    # Check if we can use buildx
    if ! docker buildx ls &> /dev/null; then
        log_error "Cannot use Docker buildx. Please ensure Docker experimental features are enabled."
        exit 1
    fi

    log_info "Prerequisites check passed"
}

setup_buildx() {
    log_info "Setting up Docker buildx builder..."

    BUILDER_NAME="multiarch-builder"

    # Check if builder already exists
    if docker buildx ls | grep -q "${BUILDER_NAME}"; then
        log_info "Using existing buildx builder: ${BUILDER_NAME}"
        docker buildx use "${BUILDER_NAME}"
    else
        log_info "Creating new buildx builder: ${BUILDER_NAME}"
        docker buildx create --name "${BUILDER_NAME}" --driver docker-container --bootstrap
        docker buildx use "${BUILDER_NAME}"
    fi

    # Inspect builder
    docker buildx inspect --bootstrap
}

build_images() {
    local image_name="${REGISTRY}/kube-powertools"
    local full_tag="${image_name}:${TAG}"

    log_info "Building multi-architecture images..."
    log_info "  Platforms: ${PLATFORMS}"
    log_info "  Tag: ${full_tag}"
    log_info "  Push: ${PUSH:-false}"
    log_info "  Load: ${LOAD:-false}"

    # Build arguments
    local dockerfile="${PROJECT_ROOT}/Dockerfile.multiarch"
    local build_args=(
        "--platform" "${PLATFORMS}"
        "--tag" "${full_tag}"
        "--file" "${dockerfile}"
        "--progress" "auto"
    )

    # Add push flag if requested
    if [[ -n "${PUSH}" ]]; then
        build_args+=("--push")
    fi

    # Add load flag if requested (only works for single platform)
    if [[ -n "${LOAD}" ]]; then
        if [[ "${PLATFORMS}" == *","* ]]; then
            log_warn "--load only works with single platform. Skipping load for multi-platform build."
        else
            build_args+=("--load")
        fi
    fi

    # Add build context
    build_args+=("${PROJECT_ROOT}")

    # Build
    log_info "Running: docker buildx build ${build_args[*]}"
    docker buildx build "${build_args[@]}"

    log_info "Build completed successfully!"

    # Show image info if pushed
    if [[ -n "${PUSH}" ]]; then
        log_info "Image pushed to: ${full_tag}"
        log_info "Platforms: ${PLATFORMS}"
    fi
}

verify_images() {
    log_info "Verifying multi-architecture images..."

    local image_name="${REGISTRY}/kube-powertools"
    local full_tag="${image_name}:${TAG}"

    # Check if we can inspect the manifest
    if command -v crane &> /dev/null; then
        log_info "Using crane to verify image platforms..."
        crane manifest "${full_tag}" | jq '.manifests[].platform'
    elif [[ -n "${PUSH}" ]]; then
        log_warn "Install crane (github.com/google/go-containerregistry) to verify multi-arch manifests"
        log_info "Or check the registry directly for platform support"
    fi

    # If loaded locally, test it
    if [[ -n "${LOAD}" && "${PLATFORMS}" != *","* ]]; then
        log_info "Testing locally loaded image..."
        docker run --rm "${full_tag}" bash -c "uname -m && echo 'Architecture verified'"
    fi
}

main() {
    parse_args "$@"
    check_prerequisites
    setup_buildx
    build_images
    verify_images

    log_info "Multi-architecture build process completed!"
    log_info "Image: ${REGISTRY}/kube-powertools:${TAG}"
    log_info "Platforms: ${PLATFORMS}"
}

main "$@"
