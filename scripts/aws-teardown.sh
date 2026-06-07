#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================================"
echo "  Telescope DevOps — AWS Teardown"
echo "  Region: ap-south-1"
echo "========================================================"

cd "$ROOT_DIR"
ansible-playbook ansible/playbooks/destroy-cluster.yml
