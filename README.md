# Telescope DevOps Platform

> A production-grade, end-to-end DevOps platform built for [Telescope](https://github.com/Seneca-CDOT/telescope) — an actively maintained open-source microservices application developed by Seneca College with 180+ contributors and real production traffic.

This repository contains the complete infrastructure lifecycle for Telescope: local containerization, Kubernetes orchestration, cloud provisioning, configuration management, observability, and automated CI/CD. Every layer is built with industry-standard tooling and documented as a reference for how a real engineering team would operate a microservices platform.

**Source application:** [github.com/Seneca-CDOT/telescope](https://github.com/Seneca-CDOT/telescope)

---

## Table of Contents

- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Microservices](#microservices)
- [Prerequisites](#prerequisites)
- [Phase 1 — Local Docker Compose](#phase-1--local-docker-compose)
- [Phase 2 — Local Kubernetes with Minikube](#phase-2--local-kubernetes-with-minikube)
- [Phase 3 — AWS Production](#phase-3--aws-production)
- [Terraform Modules](#terraform-modules)
- [Ansible Playbooks](#ansible-playbooks)
- [Kubernetes Manifests](#kubernetes-manifests)
- [CI/CD Pipeline](#cicd-pipeline)
- [Scripts Reference](#scripts-reference)
- [Observability](#observability)
- [Environment Variables](#environment-variables)
- [AWS Cost](#aws-cost)

---

## Architecture

```
╔══════════════════════════════════════════════════════════════════════╗
║                        DEVELOPER WORKFLOW                            ║
║                                                                      ║
║   Developer → git push → GitHub → GitHub Actions CI/CD Pipeline     ║
║                                         │                            ║
║                              ┌──────────┴──────────┐                ║
║                              │   on pull request    │                ║
║                              │   lint → test →      │                ║
║                              │   terraform plan     │                ║
║                              └──────────────────────┘                ║
║                                         │                            ║
║                              ┌──────────┴──────────┐                ║
║                              │   on push to main    │                ║
║                              │   lint → test →      │                ║
║                              │   docker build →     │                ║
║                              │   push to ECR →      │                ║
║                              │   deploy to EKS →    │                ║
║                              │   smoke test         │                ║
║                              └──────────────────────┘                ║
╚══════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════╗
║                     LOCAL ENVIRONMENTS                               ║
║                                                                      ║
║  ┌──────────────────────────┐  ┌──────────────────────────────────┐ ║
║  │   Docker Compose         │  │   Minikube / Kubernetes          │ ║
║  │   (Phase 1)              │  │   (Phase 2)                      │ ║
║  │                          │  │                                  │ ║
║  │  traefik    :80/:8080    │  │  ingress-nginx  (L7 routing)     │ ║
║  │  posts      :5555        │  │  deployments    (all services)   │ ║
║  │  search     :4445        │  │  ConfigMap      (env config)     │ ║
║  │  image      :4444        │  │  Secrets        (credentials)    │ ║
║  │  status     :1111        │  │  HPA            (autoscaling)    │ ║
║  │  sso        :7777        │  │  kustomize      (overlays)       │ ║
║  │  redis      :6379        │  │  prometheus     (Helm)           │ ║
║  │  elasticsearch :9200     │  │  grafana        (Helm)           │ ║
║  │  prometheus :9090        │  │                                  │ ║
║  │  grafana    :3001        │  │                                  │ ║
║  └──────────────────────────┘  └──────────────────────────────────┘ ║
╚══════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════╗
║                  INFRASTRUCTURE AS CODE                              ║
║                                                                      ║
║  Terraform (provision)               Ansible (configure)            ║
║  ├── modules/vpc                     ├── bootstrap-cluster.yml      ║
║  ├── modules/eks                     │   (post-Terraform EKS setup) ║
║  ├── modules/ecr                     └── destroy-cluster.yml        ║
║  ├── modules/iam                         (teardown with confirm)    ║
║  └── modules/route53  ← reference only, not executed               ║
╚══════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════╗
║                    AWS PRODUCTION STACK                              ║
║                                                                      ║
║   Internet                                                           ║
║      │                                                               ║
║   Route 53 (DNS)          ← reference module, not executed          ║
║      │                                                               ║
║   ACM (TLS certificate)   ← reference module, not executed          ║
║      │                                                               ║
║   Application Load Balancer (AWS Load Balancer Controller)          ║
║      │                                                               ║
║   ┌──┴───────────────────────────────────────────────────┐          ║
║   │   AWS VPC  10.0.0.0/16  —  2 availability zones      │          ║
║   │                                                       │          ║
║   │   Public subnets  (10.0.1.0/24, 10.0.2.0/24)         │          ║
║   │   NAT Gateway     (single, shared — cost optimised)   │          ║
║   │   Private subnets (10.0.10.0/24, 10.0.11.0/24)       │          ║
║   │                                                       │          ║
║   │   ┌────────────────────────────────────────────────┐  │          ║
║   │   │  EKS Cluster 1.28  —  Fargate Spot             │  │          ║
║   │   │                                                 │  │          ║
║   │   │  namespace: telescope                           │  │          ║
║   │   │  ├── posts          HPA: 1–5 replicas           │  │          ║
║   │   │  ├── search         HPA: 1–4 replicas           │  │          ║
║   │   │  ├── image                                      │  │          ║
║   │   │  ├── status                                     │  │          ║
║   │   │  ├── feed-discovery                             │  │          ║
║   │   │  └── sso                                        │  │          ║
║   │   │                                                 │  │          ║
║   │   │  namespace: monitoring                          │  │          ║
║   │   │  ├── Prometheus  (scrapes all services)         │  │          ║
║   │   │  └── Grafana     (dashboards)                   │  │          ║
║   │   └────────────────────────────────────────────────┘  │          ║
║   │                                                       │          ║
║   │   Supporting: ECR  ·  S3  ·  DynamoDB  ·  IAM        │          ║
║   └───────────────────────────────────────────────────────┘          ║
╚══════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════╗
║                       OBSERVABILITY                                  ║
║                                                                      ║
║   Prometheus  ──scrapes──►  all microservices (15s interval)        ║
║       │                     traefik · redis · elasticsearch          ║
║       │                                                              ║
║   Grafana  ◄──datasource──  Prometheus                              ║
║       │                                                              ║
║       └── dashboards: latency · error rate · pod resources          ║
║                        redis stats · elasticsearch health            ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## Tech Stack

| Layer | Tool | Purpose |
|---|---|---|
| Containerization | Docker | Package each microservice into a portable image |
| Local orchestration | Docker Compose | Run the full multi-service stack locally |
| Kubernetes (local) | Minikube | Single-node k8s cluster for local development |
| Kubernetes (cloud) | AWS EKS (Fargate) | Managed Kubernetes in production |
| Manifest management | Kustomize | Environment-specific overlays without duplication |
| Infrastructure as Code | Terraform | Provision and manage all AWS resources declaratively |
| Configuration management | Ansible | Bootstrap EKS post-Terraform, install tooling, deploy Helm charts |
| CI/CD | GitHub Actions | Automated lint, test, build, push, and deploy on every commit |
| Container registry | Amazon ECR | Store and version Docker images per service |
| Reverse proxy | Traefik | API gateway and service routing in local Docker Compose |
| Ingress | ingress-nginx / AWS ALB | Route external traffic into the Kubernetes cluster |
| Metrics | Prometheus | Scrape and store time-series metrics from all services |
| Dashboards | Grafana | Visualize metrics with pre-provisioned datasources |
| Package manager | Helm | Install Prometheus and Grafana into Kubernetes |
| Scripting | Bash | Automate startup, teardown, health checks, and deployment |

---

## Repository Structure

```
telescope-devops/
│
├── telescope/                              # Upstream source (Seneca-CDOT/telescope)
│
├── docker/
│   ├── .env.local                          # Local env vars for Docker Compose
│   └── docker-compose.override.yml         # Monitoring overlay (Prometheus + Grafana)
│
├── k8s/
│   ├── base/                               # Kustomize base — environment-agnostic manifests
│   │   ├── kustomization.yaml              # Base resource list
│   │   ├── configmaps/
│   │   │   └── app-config.yaml             # All non-sensitive env vars as ConfigMap
│   │   ├── secrets/
│   │   │   └── app-secrets.yaml            # JWT, DB passwords, SAML certs as k8s Secret
│   │   ├── deployments/
│   │   │   ├── redis.yaml                  # Redis deployment + volume
│   │   │   ├── elasticsearch.yaml          # Elasticsearch deployment + sysctl init
│   │   │   ├── posts.yaml                  # Posts microservice deployment
│   │   │   ├── search.yaml                 # Search microservice deployment
│   │   │   ├── image.yaml                  # Image proxy deployment
│   │   │   ├── status.yaml                 # Status API deployment
│   │   │   ├── feed-discovery.yaml         # Feed discovery deployment
│   │   │   ├── sso.yaml                    # SSO/auth deployment
│   │   │   ├── login.yaml                  # Test SAML IdP deployment
│   │   │   └── hpa.yaml                    # HorizontalPodAutoscalers for posts + search
│   │   ├── services/
│   │   │   └── all-services.yaml           # ClusterIP services for all deployments
│   │   └── ingress/
│   │       └── telescope-ingress.yaml      # Ingress rules mapping /v1/* to services
│   │
│   └── overlays/
│       ├── local/                          # Minikube-specific overrides
│       │   ├── kustomization.yaml          # Patches replicas to 1, imagePullPolicy to Never
│       │   └── kind-config.yaml            # Reference kind cluster config
│       └── production/                     # EKS-specific overrides
│           └── kustomization.yaml          # Patches replicas to 2, rewrites ECR image refs
│
├── terraform/
│   ├── modules/
│   │   ├── vpc/
│   │   │   ├── main.tf                     # VPC, subnets, IGW, NAT gateway, route tables
│   │   │   ├── variables.tf                # CIDR ranges, project name, environment
│   │   │   └── outputs.tf                  # vpc_id, public/private subnet IDs
│   │   ├── eks/
│   │   │   ├── main.tf                     # EKS cluster + Fargate profiles per namespace
│   │   │   ├── variables.tf                # Cluster name, IAM roles, subnet IDs
│   │   │   └── outputs.tf                  # cluster_name, endpoint, CA data
│   │   ├── ecr/
│   │   │   ├── main.tf                     # ECR repos per service + lifecycle policies
│   │   │   ├── variables.tf                # Project name, environment
│   │   │   └── outputs.tf                  # repository_urls map, registry_id
│   │   ├── iam/
│   │   │   ├── main.tf                     # EKS cluster role + Fargate pod execution role
│   │   │   ├── variables.tf                # Project name, environment
│   │   │   └── outputs.tf                  # Role ARNs
│   │   └── route53/                        # REFERENCE ONLY — not executed
│   │       ├── main.tf                     # Hosted zone, ACM cert, DNS validation records
│   │       ├── variables.tf                # domain_name, alb_dns_name, alb_zone_id
│   │       └── outputs.tf                  # certificate_arn, hosted_zone_id, name_servers
│   │
│   └── environments/
│       └── dev/
│           ├── main.tf                     # Root config — calls all active modules
│           ├── variables.tf                # project_name, environment, aws_region
│           └── outputs.tf                  # cluster_name, ecr_urls, vpc_id
│
├── ansible/
│   └── playbooks/
│       ├── bootstrap-cluster.yml           # Post-Terraform EKS setup + Helm installs
│       └── destroy-cluster.yml             # Guided teardown of all AWS resources
│
├── .github/
│   └── workflows/
│       └── ci-cd.yml                       # Full CI/CD pipeline definition
│
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus.yml                  # Scrape config for all services
│   └── grafana/
│       └── provisioning/
│           ├── datasources/
│           │   └── prometheus.yml          # Auto-provision Prometheus as datasource
│           └── dashboards/
│               └── default.yml             # Dashboard file provider config
│
└── scripts/
    ├── start-local.sh                      # Start full local Docker Compose stack
    ├── stop-local.sh                       # Stop and clean up local stack
    ├── logs.sh                             # Tail logs for a specific service
    ├── health-check.sh                     # Hit all service endpoints and report HTTP status
    ├── aws-deploy.sh                       # terraform apply + ansible bootstrap
    └── aws-teardown.sh                     # Destroy all AWS resources with confirmation
```

---

## Microservices

All services are part of the Telescope monorepo under `src/api/` and built as independent Node.js applications using the `@senecacdot/satellite` framework.

| Service | Role | Port | Path prefix |
|---|---|---|---|
| `posts` | Feed post CRUD — stores and serves parsed blog posts | 5555 | `/v1/posts` |
| `search` | Elasticsearch-backed full-text search across all posts | 4445 | `/v1/search` |
| `image` | Unsplash image proxy — serves header images for posts | 4444 | `/v1/image` |
| `status` | Health and uptime API — reports status of all services | 1111 | `/v1/status` |
| `feed-discovery` | Discovers RSS/Atom feed URLs from a given website | 9999 | `/v1/feed-discovery` |
| `sso` | SAML 2.0 authentication — handles login and logout flow | 7777 | `/v1/auth` |
| `parser` | Feed parser worker — pulls from RSS Bridge, posts to posts service | 10000 | `/v1/parser` |
| `dependency-discovery` | Scans repos for open-source dependencies | 10500 | `/v1/dependency-discovery` |
| `traefik` | Reverse proxy — routes all `/v1/*` traffic to the correct service | 80 / 443 | — |
| `redis` | Bull queue backend for the parser worker + session cache | 6379 | — |
| `elasticsearch` | Full-text search engine used by the search service | 9200 | — |

---

## Prerequisites

All commands assume Ubuntu 22.04 / Debian 12 or WSL2.

```bash
# Docker Engine
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker

# Node.js 18 via nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc && nvm install 18 && nvm alias default 18

# pnpm 9 (compatible with Node 18)
npm install -g pnpm@9

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor \
  -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform

# Ansible
sudo apt-get install -y ansible

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install
```

| Tool | Minimum version |
|---|---|
| Docker + Docker Compose plugin | 24.x |
| Node.js | 18.x |
| pnpm | 9.x |
| kubectl | 1.28+ |
| Minikube | 1.32+ |
| Helm | 3.x |
| Terraform | 1.5+ |
| Ansible | 2.14+ |
| AWS CLI | v2 |

---

## Phase 1 — Local Docker Compose

Runs the complete Telescope microservices stack locally using Docker Compose, with a Prometheus and Grafana monitoring overlay added on top of the upstream configuration.

### How it works

The upstream Telescope repository ships its own Docker Compose files under `docker/`. The start script copies `telescope/config/env.development` as `.env`, applies Linux-specific fixes (path separators, container hostnames for Redis and Elasticsearch), and runs `docker compose up` for the core service subset. A separate overlay file adds Prometheus and Grafana using host networking so they can scrape the running containers without joining the internal Docker network.

### Start the stack

```bash
git clone https://github.com/your-username/telescope-devops.git
cd telescope-devops
git clone https://github.com/Seneca-CDOT/telescope.git

./scripts/start-local.sh
```

The script installs Node dependencies (~2 minutes on first run), builds all service Docker images, starts the core services, waits for Elasticsearch to initialize, then starts the monitoring overlay.

### Service endpoints

| Service | URL | Notes |
|---|---|---|
| API Gateway | `http://localhost:80` | Entry point for all `/v1/*` routes |
| Traefik Dashboard | `http://localhost:8080` | Shows all registered routes and upstreams |
| Posts API | `http://localhost/v1/posts` | |
| Search API | `http://localhost/v1/search` | |
| Status API | `http://localhost/v1/status` | |
| Prometheus | `http://localhost:9090` | Metrics explorer |
| Grafana | `http://localhost:3001` | `admin / telescope123` |

### Verify

```bash
# Check all service endpoints
./scripts/health-check.sh

# Check running containers
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Tail logs for a specific service
./scripts/logs.sh posts

# Hit APIs directly
curl http://localhost/v1/status
curl http://localhost/v1/posts
```

### Stop the stack

```bash
./scripts/stop-local.sh
```

---

## Phase 2 — Local Kubernetes with Minikube

Deploys all Telescope services into a local Kubernetes cluster running inside Docker via Minikube. This phase mirrors the production EKS setup using the same manifests via Kustomize overlays.

### Create the cluster

```bash
minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=6144 \
  --disk-size=20g \
  --kubernetes-version=v1.28.0 \
  --profile=telescope
```

### Enable required addons

```bash
minikube addons enable ingress --profile=telescope
minikube addons enable metrics-server --profile=telescope
minikube addons enable dashboard --profile=telescope

# Wait for ingress controller
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### Build images inside Minikube

Images must be built inside Minikube's Docker daemon so the cluster can access them without a registry.

```bash
eval $(minikube docker-env --profile=telescope)

cd telescope
docker build -t telescope/posts:local          -f src/api/posts/Dockerfile          src/api/posts/
docker build -t telescope/search:local         -f src/api/search/Dockerfile         src/api/search/
docker build -t telescope/image:local          -f src/api/image/Dockerfile          src/api/image/
docker build -t telescope/status:local         -f src/api/status/Dockerfile         src/api/status/
docker build -t telescope/feed-discovery:local -f src/api/feed-discovery/Dockerfile src/api/feed-discovery/
docker build -t telescope/sso:local            -f src/api/sso/Dockerfile            src/api/sso/
docker build -t telescope/parser:local         -f src/api/parser/Dockerfile         src/api/parser/

eval $(minikube docker-env --profile=telescope -u)
```

### Deploy

```bash
cd ..
kubectl create namespace telescope
kubectl config set-context --current --namespace=telescope

kubectl apply -k k8s/overlays/local/

# Watch pods come up (Elasticsearch takes 60-90s)
kubectl get pods -n telescope -w
```

### Install monitoring via Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --set server.service.type=NodePort \
  --set server.service.nodePort=30090 \
  --set alertmanager.enabled=false \
  --set pushgateway.enabled=false

helm install grafana grafana/grafana \
  --namespace monitoring \
  --set service.type=NodePort \
  --set service.nodePort=30030 \
  --set adminPassword=telescope123 \
  --set persistence.enabled=false
```

### Access services

```bash
MINIKUBE_IP=$(minikube ip --profile=telescope)

curl http://$MINIKUBE_IP/v1/status
curl http://$MINIKUBE_IP/v1/posts

minikube service prometheus-server -n monitoring --url --profile=telescope
minikube service grafana -n monitoring --url --profile=telescope
minikube dashboard --profile=telescope
```

### Verify autoscaling

```bash
kubectl get hpa -n telescope
kubectl get pods -n telescope
kubectl top pods -n telescope
```

### Tear down

```bash
minikube delete --profile=telescope
```

---

## Phase 3 — AWS Production

Provisions a full production-grade AWS environment using Terraform, configures it using Ansible, and deploys all services to EKS via GitHub Actions or manually.

### One-time setup — Terraform state backend

```bash
export TF_STATE_BUCKET="telescope-tfstate-$(aws sts get-caller-identity \
  --query Account --output text)"
export AWS_REGION="us-east-1"

aws s3api create-bucket \
  --bucket $TF_STATE_BUCKET \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION

aws s3api put-bucket-versioning \
  --bucket $TF_STATE_BUCKET \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket $TF_STATE_BUCKET \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name telescope-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION

sed -i "s/REPLACE_WITH_YOUR_TF_STATE_BUCKET/$TF_STATE_BUCKET/" \
  terraform/environments/dev/main.tf
```

### Configure AWS credentials

```bash
aws configure
aws sts get-caller-identity
```

### Set a billing alarm

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "telescope-spend-alert" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD \
  --evaluation-periods 1
```

### Deploy

```bash
./scripts/aws-deploy.sh
```

Runs `terraform init` and `terraform apply`, then runs the Ansible bootstrap playbook to configure the cluster, install the AWS Load Balancer Controller, deploy Prometheus and Grafana via Helm, and apply all Kubernetes manifests.

### Verify

```bash
kubectl get nodes
kubectl get pods -n telescope
kubectl get pods -n monitoring
kubectl get ingress -n telescope

ALB=$(kubectl get ingress telescope-ingress -n telescope \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: $ALB"

curl http://$ALB/v1/status
curl http://$ALB/v1/posts
```

### Tear down

```bash
./scripts/aws-teardown.sh
```

Destroys all AWS resources. Prompts for confirmation. Run this at the end of every session — the EKS control plane charges $0.10/hour at idle.

---

## Terraform Modules

### `modules/vpc`

Provisions the foundational network layer. Creates a VPC with a `/16` CIDR block, two public and two private subnets across two availability zones, an Internet Gateway, and a single shared NAT Gateway in the first public subnet for outbound internet access from private subnets. Using one NAT Gateway instead of two saves ~$32/month at the cost of cross-AZ resilience — an accepted trade-off for a development environment. Subnet tags are applied for EKS and ALB auto-discovery.

| File | Contents |
|---|---|
| `main.tf` | VPC, subnets, IGW, NAT Gateway, EIP, route tables, associations |
| `variables.tf` | `project_name`, `environment`, `vpc_cidr`, `public_subnet_cidrs`, `private_subnet_cidrs` |
| `outputs.tf` | `vpc_id`, `public_subnet_ids`, `private_subnet_ids` |

### `modules/eks`

Creates the EKS 1.28 control plane and three Fargate profiles — one each for the `telescope`, `monitoring`, and `kube-system` namespaces. All workloads run on Fargate Spot, which is serverless with no EC2 node management and significantly lower cost than on-demand. Control plane logging is disabled to avoid CloudWatch charges during development.

| File | Contents |
|---|---|
| `main.tf` | EKS cluster resource, three `aws_eks_fargate_profile` resources |
| `variables.tf` | `project_name`, `environment`, role ARNs, subnet IDs, `vpc_id` |
| `outputs.tf` | `cluster_name`, `cluster_endpoint`, `cluster_ca` |

### `modules/ecr`

Creates one Amazon ECR private repository per microservice. Image scanning on push is enabled to automatically flag known CVEs. A lifecycle policy is attached to each repository retaining only the most recent 10 images, keeping storage costs near zero.

| File | Contents |
|---|---|
| `main.tf` | `aws_ecr_repository` and `aws_ecr_lifecycle_policy` for each service using `for_each` |
| `variables.tf` | `project_name`, `environment` |
| `outputs.tf` | `repository_urls` (map of service → ECR URL), `registry_id` |

### `modules/iam`

Creates the two IAM roles required for EKS on Fargate: the EKS cluster role with `AmazonEKSClusterPolicy` and the Fargate pod execution role with `AmazonEKSFargatePodExecutionRolePolicy` plus an inline policy granting ECR image pull access. These are the minimum permissions required to run authenticated workloads on EKS Fargate with ECR-hosted images.

| File | Contents |
|---|---|
| `main.tf` | Two IAM roles, three policy attachments, one inline policy |
| `variables.tf` | `project_name`, `environment` |
| `outputs.tf` | `eks_cluster_role_arn`, `fargate_pod_execution_role_arn` |

### `modules/route53` — Reference only, not executed

> **This module is intentionally not called from any environment and will not be executed by `terraform apply`.** It is included as a complete reference implementation demonstrating how production DNS and TLS would be wired into this architecture. The module call is commented out in `terraform/environments/dev/main.tf` with inline instructions for activation.

Provisions a Route 53 hosted zone, an ACM TLS certificate with DNS validation covering both the apex domain and the `*` wildcard, Route 53 DNS records for certificate validation and ALB aliasing, and waits for the certificate to be fully issued before returning its ARN.

| File | Contents |
|---|---|
| `main.tf` | `aws_route53_zone`, `aws_acm_certificate`, `aws_route53_record` (validation + A records), `aws_acm_certificate_validation` |
| `variables.tf` | `project_name`, `environment`, `domain_name`, `alb_dns_name`, `alb_zone_id` |
| `outputs.tf` | `certificate_arn`, `hosted_zone_id`, `name_servers`, `domain_url` |

**To activate if you have a registered domain:**
1. Uncomment the `module "route53"` block in `terraform/environments/dev/main.tf`
2. Set `domain_name` to your domain
3. Wire `alb_dns_name` and `alb_zone_id` from your ALB outputs
4. Add the certificate ARN to your Ingress annotations:
   ```yaml
   alb.ingress.kubernetes.io/certificate-arn: <certificate_arn output>
   alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
   ```

**Cost if activated:** ~$0.50/month for the hosted zone. ACM certificates are free. Domain registration is ~$3–12/year depending on TLD.

---

## Ansible Playbooks

### `bootstrap-cluster.yml`

Runs after `terraform apply` to configure the EKS cluster. Executed locally against `localhost` using the `local` connection plugin — no SSH required.

**Tasks in order:**
1. Runs `aws eks update-kubeconfig` to configure kubectl access to the new cluster
2. Creates the `telescope` and `monitoring` namespaces idempotently
3. Patches the CoreDNS deployment to remove the Fargate compute-type annotation (required for CoreDNS to schedule correctly on Fargate)
4. Adds Helm repositories: `prometheus-community`, `grafana`, `eks`
5. Installs the AWS Load Balancer Controller via Helm into `kube-system`
6. Installs Prometheus via Helm into `monitoring`
7. Installs Grafana via Helm into `monitoring` with a LoadBalancer service type
8. Applies all Kubernetes manifests via `kubectl apply -k k8s/overlays/production/`
9. Prints the Grafana LoadBalancer hostname

### `destroy-cluster.yml`

Runs an interactive teardown of all AWS resources. Prompts the operator to type `yes` before proceeding, then runs `terraform destroy -auto-approve` in the dev environment directory. Includes a skip path so cancellation exits cleanly without error.

---

## Kubernetes Manifests

### Base manifests (`k8s/base/`)

**`configmaps/app-config.yaml`**
A single ConfigMap named `telescope-config` containing all non-sensitive environment variables used across microservices — service ports, internal cluster URLs, Elasticsearch and Redis config, SSO/SAML settings, JWT issuer and audience, feed processing parameters, and Supabase configuration. Mounted into every Deployment via `envFrom.configMapRef`.

**`secrets/app-secrets.yaml`**
A Kubernetes Secret named `telescope-secrets` holding sensitive values: `JWT_SECRET`, `POSTGRES_PASSWORD`, `ANON_KEY`, `SERVICE_ROLE_KEY`, and `SSO_IDP_PUBLIC_KEY_CERT`. Stored as `stringData` and base64-encoded automatically by Kubernetes. Mounted via `envFrom.secretRef` alongside the ConfigMap in every Deployment. In a production hardening scenario this would be replaced with the External Secrets Operator pulling from AWS Secrets Manager.

**`deployments/redis.yaml`**
Single-replica Redis 7 Alpine Deployment with readiness and liveness probes using `redis-cli ping`. Resource limits are set conservatively (200m CPU, 256Mi memory). Uses an `emptyDir` volume — acceptable for a development environment where Redis queue persistence is not required.

**`deployments/elasticsearch.yaml`**
Single-replica Elasticsearch 8.4.0 Deployment. Includes a privileged init container that runs `sysctl -w vm.max_map_count=262144`, which Elasticsearch requires on Linux. Security is disabled (`xpack.security.enabled: false`) for development use. JVM heap is capped at 512MB. Readiness probe polls `/_cluster/health` with a 45-second initial delay to account for slow startup time.

**`deployments/posts.yaml`**, **`search.yaml`**, **`image.yaml`**, **`status.yaml`**, **`feed-discovery.yaml`**, **`sso.yaml`**, **`login.yaml`**
One Deployment per microservice. All follow the same structure: container image tagged `:local` for Minikube (rewritten to ECR URL by the production overlay), `envFrom` referencing both the ConfigMap and Secret, resource requests and limits tuned per service, and HTTP readiness and liveness probes against each service's own health endpoint.

**`deployments/hpa.yaml`**
Two HorizontalPodAutoscaler resources. `telescope-posts-hpa` scales between 1 and 5 replicas targeting 60% CPU and 70% memory utilization. `telescope-search-hpa` scales between 1 and 4 replicas on the same CPU threshold. Both require the metrics-server addon to be running in the cluster.

**`services/all-services.yaml`**
ClusterIP Services for every Deployment — Redis, Elasticsearch, posts, search, image, status, feed-discovery, sso, and login. Each Service selects pods by the `app` label set in the corresponding Deployment and exposes the correct internal port. ClusterIP means services are only reachable within the cluster; all external access goes through the Ingress.

**`ingress/telescope-ingress.yaml`**
A single Ingress resource routing external traffic to the correct Service based on path prefix. Uses regex path matching (`/v1/posts(/|$)(.*)`) with the nginx rewrite annotation to strip the path prefix before forwarding to the upstream. Configured with `ingressClassName: nginx` for both local Minikube and, via the production overlay annotation, AWS ALB.

**`base/kustomization.yaml`**
The Kustomize base resource list. Declares all manifests above as resources. Contains no patches — this is the clean base that both local and production overlays extend without modifying.

### Local overlay (`k8s/overlays/local/`)

**`kustomization.yaml`**
Extends the base and applies two strategic merge patches: reduces `telescope-posts` and `telescope-search` replicas to 1 to conserve Minikube resources, and sets `imagePullPolicy: Never` on all microservice Deployments so Kubernetes uses images built directly in Minikube's Docker daemon rather than attempting to pull from a registry.

### Production overlay (`k8s/overlays/production/`)

**`kustomization.yaml`**
Extends the base and applies: replica count of 2 for posts and search, `imagePullPolicy: Always` for all microservice Deployments, and image name rewrites replacing `telescope/<service>:local` with the full ECR URL `<account>.dkr.ecr.us-east-1.amazonaws.com/telescope/<service>:latest`. The `ACCOUNT_ID` placeholder and image tags are updated to the current commit SHA by the GitHub Actions deploy job immediately before `kubectl apply` runs.

---

## CI/CD Pipeline

**File:** `.github/workflows/ci-cd.yml`

The pipeline has four jobs. Pull requests trigger jobs 1 and 3. Pushes to `main` trigger jobs 1, 2, and 4.

### Job 1 — `test`

Runs on every push and pull request. Checks out the Telescope source, sets up Node 18 and pnpm with dependency caching enabled, runs `pnpm install --frozen-lockfile`, then runs lint and unit tests. A failure here blocks all downstream jobs.

### Job 2 — `build-push`

Runs on push to `main` only, after `test` passes. Authenticates to AWS using repository secrets and logs into ECR. Sets the image tag to the first 7 characters of the commit SHA (e.g. `a3f8c12`). Iterates over all service directories, checks for the presence of a `Dockerfile`, builds the image, and pushes both a SHA-tagged version and `latest` to ECR. Outputs the image tag for downstream use.

### Job 3 — `terraform-plan`

Runs on pull requests only. Initializes Terraform and runs `terraform plan` against the dev environment, printing the full resource diff as job output. Gives reviewers visibility into infrastructure changes before they are merged and applied.

### Job 4 — `deploy`

Runs on push to `main` only, after `build-push` completes. Updates the local kubeconfig for the EKS cluster. Replaces the `ACCOUNT_ID` placeholder in the production kustomization with the real AWS account ID, then uses `kustomize edit set image` to point each service image to its ECR URL with the new SHA tag. Runs `kubectl apply -k k8s/overlays/production/`, then waits for each Deployment's rollout to complete via `kubectl rollout status`. Performs a smoke test by curling the ALB hostname on `/v1/status` and `/v1/posts`.

### Required GitHub Secrets

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_ACCOUNT_ID` | Output of `aws sts get-caller-identity --query Account --output text` |

---

## Scripts Reference

### `scripts/start-local.sh`

Primary entrypoint for local development. Copies `telescope/config/env.development` to `telescope/.env`, applies three `sed` fixes (Linux path separator in `COMPOSE_FILE`, Redis URL pointing to the `redis` container name, Elasticsearch URL pointing to the `elasticsearch` container name), runs `pnpm install`, starts the core Docker Compose services excluding the nginx/docs service (which has an incompatible Node 18 dependency), waits 30 seconds for Elasticsearch to initialize, detects the Docker network name created by Compose, updates the monitoring overlay's network reference, and starts Prometheus and Grafana.

### `scripts/stop-local.sh`

Stops the monitoring overlay containers first, then runs `docker compose down` in the telescope directory to stop and remove all core service containers. Volumes are preserved by default so data survives restarts.

### `scripts/logs.sh`

Wrapper around `docker compose logs`. Accepts an optional service name as the first argument. With no argument, streams logs from all services with a 50-line tail. With a service name (e.g. `./scripts/logs.sh posts`), streams only that service's logs with a 100-line tail.

### `scripts/health-check.sh`

Iterates over all microservice API endpoints and reports their HTTP status codes using `curl` with a 5-second timeout per request. Marks each service as healthy (✓) if the response code is 200, 201, 301, 302, or 404. A 404 indicates the service is responding but the specific path doesn't exist — the container is healthy. Also reports status for the Traefik dashboard, Prometheus, and Grafana. Useful for confirming the full stack is up without opening a browser.

### `scripts/aws-deploy.sh`

Runs `terraform init` and `terraform apply -auto-approve` in the dev environment directory, then immediately runs the Ansible `bootstrap-cluster.yml` playbook. Used for both initial provisioning and re-provisioning after a teardown. Assumes AWS credentials are configured and the S3 state bucket already exists.

### `scripts/aws-teardown.sh`

Prompts the operator to type `destroy` before proceeding. On confirmation, runs `terraform destroy -auto-approve` to remove all provisioned AWS resources. Run this at the end of every working session — the EKS control plane costs $0.10/hour regardless of whether anything is scheduled on it.

---

## Observability

### Prometheus

**Config file:** `monitoring/prometheus/prometheus.yml`

Prometheus scrapes the following targets every 15 seconds:

| Job | Target (Docker Compose) | Target (Kubernetes) | Metrics path |
|---|---|---|---|
| `prometheus` | `localhost:9090` | `localhost:9090` | `/metrics` |
| `traefik` | `localhost:8080` | `localhost:8080` | `/metrics` |
| `telescope-posts` | `localhost:5555` | `posts:5555` | `/v1/metrics` |
| `telescope-search` | `localhost:4445` | `search:4445` | `/v1/metrics` |
| `telescope-status` | `localhost:1111` | `status:1111` | `/v1/metrics` |
| `telescope-image` | `localhost:4444` | `image:4444` | `/v1/metrics` |
| `telescope-feed-discovery` | `localhost:9999` | `feed-discovery:9999` | `/v1/metrics` |
| `redis` | `localhost:6379` | `redis:6379` | — |
| `elasticsearch` | `localhost:9200` | `elasticsearch:9200` | `/_prometheus/metrics` |

### Grafana

**Provisioning:** `monitoring/grafana/provisioning/`

`datasources/prometheus.yml` automatically registers the Prometheus instance as the default datasource on first startup — no manual configuration required. `dashboards/default.yml` configures Grafana's file-based dashboard provider to load JSON dashboard files from `/var/lib/grafana/dashboards/`.

**Default credentials:** `admin / telescope123`

To generate meaningful graph data before screenshotting:

```bash
ALB="localhost"  # or your ALB hostname
for i in $(seq 1 300); do
  curl -s http://$ALB/v1/status > /dev/null
  curl -s http://$ALB/v1/posts  > /dev/null
done
# Wait 60 seconds, then refresh Grafana
```

---

## Environment Variables

All configuration is environment-variable driven. Development defaults live in `telescope/config/env.development`. For Kubernetes deployments, variables are split between a ConfigMap (non-sensitive) and a Secret (credentials).

| Variable | Used by | Purpose |
|---|---|---|
| `REDIS_URL` | posts, parser, sso | Redis connection string |
| `ELASTIC_URL` | search, posts | Elasticsearch base URL |
| `JWT_SECRET` | all services | Token signing key for express-jwt |
| `JWT_ISSUER` | sso | JWT issuer claim (`iss`) |
| `JWT_AUDIENCE` | all services | JWT audience claim (`aud`) |
| `POSTGRES_PASSWORD` | supabase stack | Database password |
| `ANON_KEY` | supabase clients | Public Supabase API key |
| `SERVICE_ROLE_KEY` | supabase admin | Privileged Supabase API key |
| `SSO_IDP_PUBLIC_KEY_CERT` | sso | SAML IdP certificate for signature validation |
| `SSO_LOGIN_CALLBACK_URL` | sso | SAML assertion consumer service URL |
| `SAML_ENTITY_ID` | sso | Service provider entity ID |
| `FEED_URL` | parser | URL of the Planet CDOT RSS feed list |
| `ELASTIC_MAX_RESULTS_PER_PAGE` | search | Search result page size |
| `POSTS_PORT`, `SEARCH_PORT`, etc. | docker compose | Explicit port bindings for Traefik routing |

---

## AWS Cost

### Active modules

| Resource | Configuration | Est. monthly |
|---|---|---|
| EKS control plane | 1 cluster | $73.00 |
| Fargate Spot compute | ~4 vCPU / 8 GB average | ~$15.00 |
| Application Load Balancer | minimal LCUs | $5.00 |
| NAT Gateway | 1 shared across both AZs | $5.00 |
| ECR storage | ~3 GB across all repos | $0.30 |
| S3 + DynamoDB | Terraform state backend | ~$0.00 (free tier) |
| **Total** | | **~$98/mo** |

### Reference modules (not executed)

| Resource | Notes | Cost if activated |
|---|---|---|
| Route 53 hosted zone | Requires registered domain | +$0.50/mo |
| ACM certificate | DNS-validated, auto-renewed | Free |

### Cost controls built into this setup

- **Fargate Spot** — approximately 60% cheaper than on-demand Fargate for the same compute
- **Single NAT Gateway** — one instead of one-per-AZ saves ~$32/month, accepted trade-off for dev
- **ECR lifecycle policies** — each repo retains only the last 10 images, capping storage costs
- **`aws-teardown.sh`** — the most impactful control; the EKS control plane charges $2.40/day at idle regardless of workload, so destroying and reprovisioning (~15 minutes) between sessions keeps total spend minimal
- **Billing alarm** — CloudWatch alarm fires if daily spend exceeds $5, catching accidental resource leaks immediately

---