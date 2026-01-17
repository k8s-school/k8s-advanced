#!/bin/bash

set -euxo pipefail

# Default options
ENABLE_KEYLESS_DEMO=false

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -k, --keyless    Enable keyless signing demonstration with Sigstore
  -h, --help       Show this help message

EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--keyless)
            ENABLE_KEYLESS_DEMO=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

echo "=== Cosign Container Signing Lab ==="
echo "This lab demonstrates how to sign container images with cosign and verify signatures"
echo

# Variables
IMAGE_NAME="nginx:1.19"
SIGNED_IMAGE="localhost:5000/nginx:1.19-signed"
REGISTRY_PORT="5000"
LAB_DIR="$HOME/cosign-lab"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if cosign is installed
check_cosign() {
    log_info "Checking cosign installation..."
    if ! command -v cosign &> /dev/null; then
        log_error "cosign is not installed. Installing..."

        # Install cosign
        COSIGN_VERSION="v2.2.3"
        curl -O -L "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"
        sudo mv cosign-linux-amd64 /usr/local/bin/cosign
        sudo chmod +x /usr/local/bin/cosign

        log_success "cosign installed successfully"
    else
        log_success "cosign is already installed: $(cosign version --short)"
    fi
}

# Start local registry if not running
start_local_registry() {
    log_info "Setting up local container registry..."

    if ! docker ps | grep -q "registry:2"; then
        log_info "Starting local registry on port ${REGISTRY_PORT}..."
        docker run -d -p ${REGISTRY_PORT}:5000 --name registry registry:2
        sleep 3
        log_success "Local registry started"
    else
        log_success "Local registry is already running"
    fi
}

# Generate cosign key pair
generate_keys() {
    log_info "Generating cosign key pair..."

    if [[ ! -f "cosign.key" || ! -f "cosign.pub" ]]; then
        log_info "Creating new cosign key pair..."
        echo "test123" | cosign generate-key-pair
        log_success "Key pair generated: cosign.key (private) and cosign.pub (public)"
    else
        log_warning "Key pair already exists, using existing keys"
    fi

    log_info "Public key content:"
    cat cosign.pub
    echo
}

# Pull and tag image for local registry
prepare_image() {
    log_info "Preparing container image..."

    # Pull the base image
    log_info "Pulling ${IMAGE_NAME}..."
    docker pull ${IMAGE_NAME}

    # Tag for local registry
    log_info "Tagging image for local registry..."
    docker tag ${IMAGE_NAME} ${SIGNED_IMAGE}

    # Push to local registry
    log_info "Pushing image to local registry..."
    docker push ${SIGNED_IMAGE}

    log_success "Image ${SIGNED_IMAGE} is ready in local registry"
}

# Sign the container image
sign_image() {
    log_info "Signing container image with cosign..."

    echo "test123" | cosign sign --key cosign.key ${SIGNED_IMAGE} --yes

    log_success "Image ${SIGNED_IMAGE} signed successfully!"
}

# Verify the signature
verify_signature() {
    log_info "Verifying container image signature..."

    if cosign verify --key cosign.pub ${SIGNED_IMAGE}; then
        log_success "Signature verification PASSED! ✓"
    else
        log_error "Signature verification FAILED! ✗"
        return 1
    fi
}

# Show signature information
show_signature_info() {
    log_info "Retrieving signature information..."

    echo "Signature details:"
    cosign tree ${SIGNED_IMAGE} || true
    echo

    echo "Signature metadata:"
    cosign verify --key cosign.pub ${SIGNED_IMAGE} --output json | jq '.[0].optional' || cosign verify --key cosign.pub ${SIGNED_IMAGE}
}

# Demonstrate keyless signing (optional)
demo_keyless_signing() {
    if [[ "$ENABLE_KEYLESS_DEMO" == "true" ]]; then
        log_info "Demonstrating keyless signing with Sigstore..."
        log_warning "This requires internet connectivity and GitHub/Google authentication"

        KEYLESS_IMAGE="localhost:5000/nginx:1.19-keyless"
        docker tag ${IMAGE_NAME} ${KEYLESS_IMAGE}
        docker push ${KEYLESS_IMAGE}

        log_info "Signing with keyless method (follow browser prompts)..."
        cosign sign ${KEYLESS_IMAGE}  --identity-token --yes

        log_info "Verifying keyless signature..."
        cosign verify ${KEYLESS_IMAGE} --certificate-identity-regexp=".*" --certificate-oidc-issuer-regexp=".*"

        log_success "Keyless signing demo completed!"
    else
        log_info "Keyless signing demo skipped (use -k/--keyless to enable)"
    fi
}

# Demonstrate signature verification failure
demo_verification_failure() {
    log_info "Demonstrating signature verification failure..."

    # Create a different key pair
    TEMP_DIR=$(mktemp -d)
    cd ${TEMP_DIR}
    echo "wrong123" | cosign generate-key-pair

    cd - > /dev/null

    log_info "Trying to verify with wrong public key..."
    if cosign verify --key ${TEMP_DIR}/cosign.pub ${SIGNED_IMAGE} 2>/dev/null; then
        log_error "Unexpected: verification passed with wrong key!"
    else
        log_success "Verification correctly failed with wrong key ✓"
    fi

    # Cleanup
    rm -rf ${TEMP_DIR}
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."

    log_info "Keeping generated keys for future use (cosign.key, cosign.pub)"
    log_info "Local registry will continue running for potential future use"
    log_info "To manually clean up:"
    log_info "  - Remove keys: rm -f cosign.key cosign.pub"
    log_info "  - Stop registry: docker stop registry && docker rm registry"
}


# Handle script interruption
trap cleanup EXIT

# Check for required tools
for tool in docker jq curl; do
    if ! command -v $tool &> /dev/null; then
        log_error "$tool is required but not installed"
        exit 1
    fi
done

echo "Starting cosign container signing lab..."
echo "========================================"

# Setup
check_cosign
start_local_registry
generate_keys

echo
echo "========================================"
echo "Step 1: Image Preparation and Signing"
echo "========================================"

prepare_image
sign_image

echo
echo "========================================"
echo "Step 2: Signature Verification"
echo "========================================"

verify_signature
show_signature_info

echo
echo "========================================"
echo "Step 3: Security Demonstrations"
echo "========================================"

demo_verification_failure
demo_keyless_signing

echo
echo "========================================"
echo "Lab Summary"
echo "========================================"

log_success "✓ Generated cosign key pair"
log_success "✓ Signed container image with cosign"
log_success "✓ Verified image signature"
log_success "✓ Demonstrated verification failure with wrong key"

echo
echo "Key takeaways:"
echo "- cosign provides cryptographic signatures for container images"
echo "- Signatures are stored as OCI artifacts alongside the image"
echo "- Verification requires the correct public key"
echo "- Keyless signing uses Sigstore for identity-based verification"
echo "- Always verify signatures before deploying containers in production"

echo
cleanup

log_success "Cosign lab completed successfully!"


