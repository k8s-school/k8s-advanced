#!/bin/bash

# Trivy Container Image Vulnerability Scanning Lab Automation
# This script automates the Trivy vulnerability scanning lab

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
NAMESPACE="trivy-test"
TEST_TIMEOUT=120

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    for tool in kubectl docker curl; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    log_success "All prerequisites are available"
}

# Function to install Trivy
install_trivy() {
    log_info "Installing Trivy..."

    if command -v trivy &> /dev/null; then
        log_success "Trivy is already installed: $(trivy version --format json | jq -r .Version 2>/dev/null || trivy version)"
        return 0
    fi

    # Install Trivy
    log_info "Downloading and installing Trivy..."
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /tmp/

    # Make it available in PATH for this session
    export PATH="/tmp:$PATH"

    if command -v trivy &> /dev/null; then
        log_success "Trivy installed successfully: $(trivy version --format json | jq -r .Version 2>/dev/null || echo "installed")"
    else
        log_error "Failed to install Trivy"
        exit 1
    fi
}

# Function to verify cluster connectivity
verify_cluster() {
    log_info "Verifying cluster connectivity..."

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    local cluster_context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    log_success "Connected to cluster: $cluster_context"
}

# Function to setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."

    # Create test namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    log_success "Test environment ready"
}

# Function to demonstrate basic image scanning
demo_basic_scanning() {
    log_info "Demonstrating basic image scanning..."

    # Update Trivy database
    log_info "Updating Trivy vulnerability database..."
    trivy image --download-db-only

    # Scan a clean image
    log_info "Scanning secure image (nginx:alpine)..."
    local alpine_vulnerabilities
    alpine_vulnerabilities=$(trivy image --severity HIGH,CRITICAL --quiet --format json nginx:alpine | jq '.Results[].Vulnerabilities // [] | length' 2>/dev/null || echo "0")
    log_info "Found $alpine_vulnerabilities HIGH/CRITICAL vulnerabilities in nginx:alpine"

    # Scan a vulnerable image
    log_info "Scanning vulnerable image (nginx:1.14)..."
    local vulnerable_count
    vulnerable_count=$(trivy image --severity HIGH,CRITICAL --quiet --format json nginx:1.14 | jq '.Results[].Vulnerabilities // [] | length' 2>/dev/null || echo "0")
    log_info "Found $vulnerable_count HIGH/CRITICAL vulnerabilities in nginx:1.14"

    if [ "$vulnerable_count" -gt "$alpine_vulnerabilities" ]; then
        log_success "Demonstrated difference between secure and vulnerable images"
    else
        log_warning "Vulnerability comparison may not show expected difference"
    fi

    # Show detailed scan of vulnerable image
    log_info "Detailed scan results for nginx:1.14:"
    trivy image --severity HIGH,CRITICAL nginx:1.14 | head -20
}

# Function to test policy enforcement
test_policy_enforcement() {
    log_info "Testing policy enforcement..."

    # Create a vulnerable deployment manifest
    cat << 'EOF' > /tmp/vulnerable-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vulnerable-app
  namespace: trivy-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vulnerable-app
  template:
    metadata:
      labels:
        app: vulnerable-app
    spec:
      containers:
      - name: app
        image: nginx:1.14
        ports:
        - containerPort: 80
EOF

    # Test policy enforcement simulation
    log_info "Simulating policy enforcement for nginx:1.14..."
    if trivy image --exit-code 1 --severity CRITICAL nginx:1.14 >/dev/null 2>&1; then
        log_success "Image passed CRITICAL vulnerability check"
        kubectl apply -f /tmp/vulnerable-app.yaml
    else
        log_warning "Image failed CRITICAL vulnerability check - would block deployment"
        log_info "Deploying anyway for demonstration purposes..."
        kubectl apply -f /tmp/vulnerable-app.yaml
    fi

    # Wait for deployment
    kubectl wait --for=condition=available deployment/vulnerable-app -n "$NAMESPACE" --timeout="${TEST_TIMEOUT}s"
    log_success "Vulnerable app deployed for testing"
}

# Function to scan running containers
scan_running_containers() {
    log_info "Scanning running container images..."

    # Get running images in test namespace
    local images
    images=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u)

    for image in $images; do
        log_info "Scanning running image: $image"
        local vuln_count
        vuln_count=$(trivy image --severity HIGH,CRITICAL --quiet --format json "$image" | jq '.Results[].Vulnerabilities // [] | length' 2>/dev/null || echo "0")
        log_info "  Found $vuln_count HIGH/CRITICAL vulnerabilities"
    done

    log_success "Completed scanning of running containers"
}

# Function to generate SBOM
generate_sbom() {
    log_info "Generating Software Bill of Materials (SBOM)..."

    # Generate SBOM for nginx:alpine
    log_info "Generating SBOM for nginx:alpine..."
    trivy image --format spdx-json --output /tmp/nginx-alpine-sbom.spdx.json nginx:alpine

    # Show SBOM summary
    if [ -f /tmp/nginx-alpine-sbom.spdx.json ]; then
        local package_count
        package_count=$(jq '.packages | length' /tmp/nginx-alpine-sbom.spdx.json 2>/dev/null || echo "unknown")
        log_success "Generated SBOM with $package_count packages"

        # Show some packages
        log_info "Sample packages from SBOM:"
        jq -r '.packages[0:5][] | "- \(.name) \(.versionInfo)"' /tmp/nginx-alpine-sbom.spdx.json 2>/dev/null || echo "Could not parse SBOM"
    else
        log_warning "SBOM file not created"
    fi
}

# Function to demonstrate Trivy Operator (simplified)
demo_trivy_operator() {
    log_info "Demonstrating Trivy Operator concepts..."

    # Create a simple VulnerabilityReport-like resource for demonstration
    cat << 'EOF' > /tmp/vulnerability-report.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vulnerability-report-example
  namespace: trivy-test
data:
  report.json: |
    {
      "vulnerabilities": [
        {
          "id": "CVE-2023-1234",
          "severity": "HIGH",
          "title": "Example vulnerability in nginx:1.14",
          "description": "This is an example vulnerability report",
          "fixedVersion": "1.20.0"
        }
      ],
      "summary": {
        "critical": 2,
        "high": 5,
        "medium": 10,
        "low": 3
      }
    }
EOF

    kubectl apply -f /tmp/vulnerability-report.yaml
    log_success "Created example vulnerability report"

    # Show what a real Trivy Operator would do
    log_info "In a real Trivy Operator deployment:"
    log_info "- Automatic scanning of all pod images"
    log_info "- VulnerabilityReport CRDs created for each image"
    log_info "- ConfigAuditReport for Kubernetes configurations"
    log_info "- ExposedSecretReport for secret scanning"
    log_info "- Continuous monitoring and updates"
}

# Function to show CI/CD integration example
demo_cicd_integration() {
    log_info "Demonstrating CI/CD integration patterns..."

    # Create example CI script
    cat << 'EOF' > /tmp/ci-security-scan.sh
#!/bin/bash
# Example CI/CD security scanning script

IMAGE_NAME="$1"
SEVERITY_THRESHOLD="CRITICAL"

echo "Scanning image: $IMAGE_NAME"

# Scan image and exit with error code if vulnerabilities found
if trivy image --exit-code 1 --severity "$SEVERITY_THRESHOLD" "$IMAGE_NAME"; then
    echo "✓ Image passed security scan"
    echo "Proceeding with deployment..."
else
    echo "✗ Image failed security scan - blocking deployment"
    exit 1
fi

# Generate SBOM for compliance
trivy image --format spdx-json --output "sbom-${IMAGE_NAME//\//-}.json" "$IMAGE_NAME"
echo "✓ SBOM generated"

# Additional checks could include:
# - License scanning
# - Secret detection
# - Configuration scanning
EOF

    chmod +x /tmp/ci-security-scan.sh

    log_info "Testing CI/CD integration with nginx:alpine..."
    if bash /tmp/ci-security-scan.sh nginx:alpine; then
        log_success "CI/CD integration test passed"
    else
        log_warning "CI/CD integration test failed (expected for vulnerable images)"
    fi
}

# Function to run quick cluster security overview
cluster_security_overview() {
    log_info "Generating cluster security overview..."

    # Get all unique images in cluster
    log_info "Collecting all container images in cluster..."
    local all_images
    all_images=$(kubectl get pods --all-namespaces -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u | head -5)

    log_info "Sample of cluster images (first 5):"
    echo "$all_images" | while read -r image; do
        if [ -n "$image" ]; then
            local vuln_count
            vuln_count=$(trivy image --severity CRITICAL --quiet --format json "$image" 2>/dev/null | jq '.Results[].Vulnerabilities // [] | length' 2>/dev/null || echo "?")
            echo "  $image: $vuln_count CRITICAL vulnerabilities"
        fi
    done

    log_success "Cluster security overview completed"
}

# Function to cleanup resources
cleanup() {
    log_info "Cleaning up test resources..."

    # Delete test namespace
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true

    # Clean up temporary files
    rm -f /tmp/vulnerable-app.yaml /tmp/vulnerability-report.yaml /tmp/ci-security-scan.sh /tmp/nginx-alpine-sbom.spdx.json

    log_success "Cleanup completed"
}

# Function to show help
show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

This script automates the Trivy vulnerability scanning lab.

OPTIONS:
    -h, --help        Show this help message
    -c, --cleanup     Only run cleanup (remove test resources)
    -i, --install     Only install Trivy
    -s, --scan        Only run basic scanning demo
    -p, --policy      Only test policy enforcement
    -b, --sbom        Only generate SBOM demo
    -o, --overview    Only run cluster overview

EXAMPLES:
    $0                Run the complete lab
    $0 --install      Install Trivy only
    $0 --scan         Run basic vulnerability scanning
    $0 --policy       Test policy enforcement
    $0 --cleanup      Clean up all test resources

EOF
}

# Main function
main() {
    log_info "Starting Trivy Container Image Vulnerability Scanning Lab"
    log_info "========================================================="

    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--cleanup)
            cleanup
            exit 0
            ;;
        -i|--install)
            check_prerequisites
            install_trivy
            exit 0
            ;;
        -s|--scan)
            check_prerequisites
            install_trivy
            demo_basic_scanning
            exit 0
            ;;
        -p|--policy)
            check_prerequisites
            install_trivy
            verify_cluster
            setup_test_environment
            test_policy_enforcement
            exit 0
            ;;
        -b|--sbom)
            check_prerequisites
            install_trivy
            generate_sbom
            exit 0
            ;;
        -o|--overview)
            check_prerequisites
            install_trivy
            verify_cluster
            cluster_security_overview
            exit 0
            ;;
        "")
            # Run complete lab
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac

    # Trap to ensure cleanup on script exit
    trap cleanup EXIT

    # Run complete lab
    check_prerequisites
    install_trivy
    verify_cluster
    setup_test_environment
    demo_basic_scanning
    test_policy_enforcement
    scan_running_containers
    generate_sbom
    demo_trivy_operator
    demo_cicd_integration
    cluster_security_overview

    log_success "=================================================="
    log_success "Trivy Vulnerability Scanning Lab completed!"
    log_success "=================================================="
    log_info "Key achievements:"
    log_info "- Installed and configured Trivy"
    log_info "- Scanned images for vulnerabilities"
    log_info "- Demonstrated policy enforcement"
    log_info "- Generated Software Bill of Materials (SBOM)"
    log_info "- Showed CI/CD integration patterns"
    log_info "- Performed cluster security overview"
    log_info ""
    log_info "Security recommendations:"
    log_info "- Integrate Trivy into your CI/CD pipeline"
    log_info "- Establish vulnerability thresholds and SLAs"
    log_info "- Use SBOM for supply chain transparency"
    log_info "- Consider Trivy Operator for continuous monitoring"
    log_info "- Combine with other security tools (Falco, OPA)"
}

# Check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi