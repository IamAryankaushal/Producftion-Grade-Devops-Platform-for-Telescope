#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BOOTSTRAP_DIR="$ROOT_DIR/terraform/bootstrap"
TF_DIR="$ROOT_DIR/terraform/environments/dev"

echo "========================================================"
echo "  Telescope DevOps — AWS Deploy"
echo "  Region: ap-south-1"
echo "========================================================"

# ── Step 1: Bootstrap state backend (only if not already done) ────────────
echo ""
echo "==> Step 1/3: Bootstrap Terraform state backend..."
cd "$BOOTSTRAP_DIR"
terraform init

# Check if state bucket already exists
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="telescope-tfstate-${ACCOUNT_ID}"

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "    [✓] State bucket already exists: $BUCKET_NAME"
else
  echo "    Creating state backend resources..."
  terraform apply -auto-approve
  echo "    [✓] State backend created"
fi

# ── Step 2: Provision all AWS infrastructure ──────────────────────────────
echo ""
echo "==> Step 2/3: Provisioning AWS infrastructure with Terraform..."
cd "$TF_DIR"
terraform init -upgrade
terraform apply -auto-approve

echo ""
echo "==> Terraform outputs:"
terraform output

# ── Step 3: Configure cluster with Ansible ───────────────────────────────
echo ""
echo "==> Step 3/3: Configuring EKS cluster with Ansible..."
cd "$ROOT_DIR"
ansible-playbook ansible/playbooks/bootstrap-cluster.yml

echo ""
echo "========================================================"
echo "  Deployment complete!"
echo "========================================================"
