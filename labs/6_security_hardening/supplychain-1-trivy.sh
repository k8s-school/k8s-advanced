#!/bin/bash

# Supply Chain Security Lab - Phase 1: Trivy Installation and Scanning
# Installs Trivy and performs security analysis

set -euxo pipefail

echo "=== 🏗️ Phase 1: Trivy Installation and Security Analysis ==="

# Check if trivy is already installed
if command -v trivy &> /dev/null; then
    echo "Trivy is already installed: $(trivy --version)"
else
    echo "Installing Trivy..."

    # Detect OS and install accordingly
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux installation
        if command -v apt-get &> /dev/null; then
            # Debian/Ubuntu
            sudo apt-get update
            sudo apt-get install -y wget apt-transport-https gnupg lsb-release
            wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
            echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
            sudo apt-get update
            sudo apt-get install -y trivy
        elif command -v yum &> /dev/null; then
            # RedHat/CentOS/Fedora
            sudo rpm --import https://aquasecurity.github.io/trivy-repo/rpm/public.key
            sudo tee /etc/yum.repos.d/trivy.repo << 'EOF'
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/rpm/public.key
EOF
            sudo yum -y update
            sudo yum -y install trivy
        else
            # Generic Linux - use binary download
            TRIVY_VERSION=$(curl -s "https://api.github.com/repos/aquasecurity/trivy/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
            wget -O /tmp/trivy.tar.gz "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
            tar zxvf /tmp/trivy.tar.gz -C /tmp/
            sudo mv /tmp/trivy /usr/local/bin/
            sudo chmod +x /usr/local/bin/trivy
        fi
    else
        echo "Unsupported OS: $OSTYPE"
        exit 1
    fi

    echo "Trivy installation completed: $(trivy --version)"
fi

echo "=== 🔍 Security Analysis with Trivy ==="

echo "1. Scanning vulnerable image (nginx:1.19) for CRITICAL vulnerabilities..."
trivy image --severity CRITICAL nginx:1.19

echo ""
echo "2. Scanning vulnerable image (nginx:1.19) for HIGH,CRITICAL vulnerabilities..."
trivy image --severity HIGH,CRITICAL nginx:1.19

echo ""
echo "3. Generating SBOM (Software Bill of Materials) for nginx:1.19..."
trivy image --format cyclonedx --output nginx-1.19-sbom.json nginx:1.19

echo "SBOM file created: nginx-1.19-sbom.json"

echo ""
echo "4. Comparing with a more recent image (nginx:alpine)..."
trivy image --severity HIGH,CRITICAL nginx:alpine

echo ""
echo "5. Generating SBOM for the secure image..."
trivy image --format cyclonedx --output nginx-alpine-sbom.json nginx:alpine

echo "SBOM file created: nginx-alpine-sbom.json"

echo ""
echo "=== 📊 Analysis Summary ==="

echo "Vulnerability count comparison:"
VULN_OLD=$(trivy image --format json --quiet nginx:1.19 2>/dev/null | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL" or .Severity == "HIGH")] | length' 2>/dev/null || echo "0")
VULN_NEW=$(trivy image --format json --quiet nginx:alpine 2>/dev/null | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL" or .Severity == "HIGH")] | length' 2>/dev/null || echo "0")

echo "- nginx:1.19: $VULN_OLD HIGH/CRITICAL vulnerabilities"
echo "- nginx:alpine: $VULN_NEW HIGH/CRITICAL vulnerabilities"

if [ "$VULN_OLD" -gt "$VULN_NEW" ]; then
    echo "✅ nginx:alpine is significantly more secure"
else
    echo "⚠️  Both images have similar vulnerability counts"
fi

echo ""
echo "=== 📋 Analysis SBOM file with trivy
trivy sbom nginx-1.19-sbom.json

echo ""
echo "✅ Trivy analysis completed!"
echo ""
echo "Key findings:"
echo "- nginx:1.19 contains multiple critical vulnerabilities"
echo "- nginx:alpine is a more secure alternative"
echo "- SBOM files generated for compliance and security team review"