#!/usr/bin/env bash
# ==============================================================================
# Helper Script: Setup GitHub Actions Self-Hosted Runner on Kubernetes Master VM
# ==============================================================================
set -euo pipefail

echo "=================================================================="
echo " Setting up GitHub Actions Self-Hosted Runner on Kubernetes Master"
echo "=================================================================="

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <REPO_URL> <RUNNER_REGISTRATION_TOKEN>"
  echo "Example: $0 https://github.com/YOUR_USERNAME/AIOPS-COURSE-1 ABCDEFGHIJKLMNOPQRST"
  echo ""
  echo "To get your token:"
  echo "  1. Go to your GitHub repository -> Settings -> Actions -> Runners"
  echo "  2. Click 'New self-hosted runner'"
  echo "  3. Copy the token provided in the registration step"
  exit 1
fi

REPO_URL="$1"
RUNNER_TOKEN="$2"
RUNNER_DIR="/home/vagrant/actions-runner"
RUNNER_VERSION="2.321.0"

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [[ ! -f "config.sh" ]]; then
  echo "[-] Downloading GitHub Actions runner v${RUNNER_VERSION}..."
  curl -fsSL -o actions-runner.tar.gz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
  tar xzf actions-runner.tar.gz
  rm -f actions-runner.tar.gz
fi

echo "[-] Configuring runner with repository: $REPO_URL..."
./config.sh \
  --url "$REPO_URL" \
  --token "$RUNNER_TOKEN" \
  --name "k8s-master-runner" \
  --labels "self-hosted,k8s,lab" \
  --work "_work" \
  --unattended \
  --replace

echo "[-] Installing runner as a systemd service..."
sudo ./svc.sh install vagrant || true
sudo ./svc.sh start

echo "=================================================================="
echo " Runner successfully configured and started as a background service!"
echo " Check runner status: sudo ./svc.sh status"
echo "=================================================================="
