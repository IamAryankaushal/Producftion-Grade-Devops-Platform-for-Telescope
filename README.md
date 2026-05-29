# Telescope DevOps Platform

> Production-grade cloud infrastructure and CI/CD platform for [Telescope](https://github.com/Seneca-CDOT/telescope) — an actively maintained open-source microservices application built by Seneca College with 180+ contributors.

---

## Overview

This repository contains the complete DevOps infrastructure for deploying and operating the Telescope application across local and cloud environments. It covers containerization, container orchestration, infrastructure-as-code, configuration management, observability, and automated CI/CD — built with industry-standard tooling throughout.

Telescope itself is a blog feed aggregator that tracks open-source activity across Seneca College. It is a real production application with live traffic, making it a meaningful target for infrastructure work.

**Source application:** [github.com/Seneca-CDOT/telescope](https://github.com/Seneca-CDOT/telescope)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Developer Workflow                        │
│                                                                  │
│   git push → GitHub Actions → ECR → EKS (rolling deploy)        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      AWS Production Stack                        │
│                                                                  │
│   Internet                                                       │
│      │                                                           │
│   Route 53 (DNS)                                                 │
│      │                                                           │
│   ACM (TLS termination)                                          │
│      │                                                           │
│   Application Load Balancer                                      │
│      │                                                           │
│   ┌──┴──────────────────────────────────────┐                   │
│   │         EKS Cluster (Fargate Spot)       │                   │
│   │                                          │                   │
│   │   namespace: telescope                   │                   │
│   │   ├── posts          (HPA: 1–5 replicas) │                   │
│   │   ├── search         (HPA: 1–4 replicas) │                   │
│   │   ├── image                              │                   │
│   │   ├── status                             │                   │
│   │   ├── feed-discovery                     │                   │
│   │   └── sso                                │                   │
│   │                                          │                   │
│   │   namespace: monitoring                  │                   │
│   │   ├── Prometheus                         │                   │
│   │   └── Grafana                            │                   │
│   └──────────────────────────────────────────┘                   │
│                                                                  │
│   Supporting Services (AWS Managed)                              │
│   ├── ElastiCache Redis   (cache.t3.micro)                       │
│   ├── ECR                 (image registry, per-service repos)    │
│   ├── S3 + DynamoDB       (Terraform remote state + locking)     │
│   └── VPC                 (public/private subnets, 2 AZs)        │
└─────────────────────────────────────────────────────────────────┘
```

### Microservices

| Service | Role | Port |
|---|---|---|
| `posts` | Feed post CRUD API | 5555 |
| `search` | Elasticsearch-backed search | 4445 |
| `image` | Image proxy service | 4444 |
| `status` | Health and status API | 1111 |
| `feed-discovery` | RSS/Atom feed URL discovery | 9999 |
| `sso` | SAML-based authentication | 7777 |
| `parser` | Feed parsing worker | 10000 |
| `traefik` | Reverse proxy / API gateway | 80, 443 |
| `redis` | Queue backend and cache | 6379 |
| `elasticsearch` | Full-text search engine | 9200 |

---

## Tech Stack

| Layer | Tools |
|---|---|
| Containerization | Docker, Docker Compose |
| Orchestration | Kubernetes (Minikube locally, EKS on AWS) |
| Infrastructure as Code | Terraform |
| Configuration Management | Ansible |
| CI/CD | GitHub Actions |
| Observability | Prometheus, Grafana (via Helm) |
| Cloud | AWS (EKS, ECR, ElastiCache, ALB, Route 53, ACM, VPC) |
| Scripting | Bash |

---

## Repository Structure

```
telescope-devops/
├── telescope/                        # upstream source (git submodule)
├── docker/
│   ├── .env.local                    # local environment variables
│   └── docker-compose.override.yml  # monitoring overlay
├── k8s/
│   ├── base/                         # kustomize base manifests
│   │   ├── configmaps/
│   │   ├── secrets/
│   │   ├── deployments/              # one file per service + HPA
│   │   ├── services/
│   │   └── ingress/
│   └── overlays/
│       ├── local/                    # minikube overrides
│       └── production/               # EKS overrides with ECR image refs
├── terraform/
│   ├── modules/
│   │   ├── vpc/                      # VPC, subnets, NAT gateway
│   │   ├── eks/                      # EKS cluster + Fargate profiles
│   │   ├── ecr/                      # ECR repos with lifecycle policies
│   │   ├── elasticache/              # Redis cluster
│   │   └── iam/                      # cluster and pod execution roles
│   └── environments/
│       └── dev/                      # root config, backend, outputs
├── ansible/
│   └── playbooks/
│       ├── bootstrap-cluster.yml     # post-Terraform EKS setup
│       └── destroy-cluster.yml       # teardown with confirmation
├── .github/
│   └── workflows/
│       └── ci-cd.yml                 # full pipeline definition
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus.yml            # scrape config for all services
│   └── grafana/
│       └── provisioning/             # auto-provisioned datasources
└── scripts/
    ├── start-local.sh                # bring up full local stack
    ├── stop-local.sh                 # tear down local stack
    ├── health-check.sh               # verify all service endpoints
    ├── aws-deploy.sh                 # provision and deploy to AWS
    └── aws-teardown.sh               # destroy all AWS resources
```

---

## Getting Started

### Prerequisites

| Tool | Version |
|---|---|
| Docker + Docker Compose | 24.x + |
| Node.js | 18.x |
| pnpm | 9.x |
| kubectl | 1.28+ |
| Minikube | 1.32+ |
| Helm | 3.x |
| Terraform | 1.5+ |
| Ansible | 2.14+ |
| AWS CLI | v2 |

### Phase 1 — Local Docker Compose

Runs all services locally with a Prometheus + Grafana monitoring overlay.

```bash
git clone https://github.com/your-username/telescope-devops.git
cd telescope-devops
git clone https://github.com/Seneca-CDOT/telescope.git

./scripts/start-local.sh
```

| Endpoint | URL |
|---|---|
| API Gateway (Traefik) | http://localhost:80 |
| Traefik Dashboard | http://localhost:8080 |
| Posts API | http://localhost/v1/posts |
| Status API | http://localhost/v1/status |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3001 |

Grafana credentials: `admin / telescope123`

```bash
# Verify all services
./scripts/health-check.sh

# Tail logs for a specific service
./scripts/logs.sh posts

# Stop everything
./scripts/stop-local.sh
```

### Phase 2 — Local Kubernetes (Minikube)

Deploys all services to a local Kubernetes cluster with ingress, autoscaling, and Helm-based monitoring.

```bash
# Start Minikube
minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=6144 \
  --profile=telescope

# Enable addons
minikube addons enable ingress --profile=telescope
minikube addons enable metrics-server --profile=telescope

# Build images inside Minikube
eval $(minikube docker-env --profile=telescope)
cd telescope
docker build -t telescope/posts:local -f src/api/posts/Dockerfile src/api/posts/
# ... repeat for each service

# Deploy
cd ..
kubectl apply -k k8s/overlays/local/

# Install monitoring via Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/prometheus -n monitoring --create-namespace \
  --set server.service.type=NodePort \
  --set alertmanager.enabled=false

helm install grafana grafana/grafana -n monitoring \
  --set service.type=NodePort \
  --set adminPassword=telescope123

# Get service URLs
minikube service grafana -n monitoring --url --profile=telescope

# Verify
kubectl get pods -n telescope
kubectl get hpa -n telescope
```

### Phase 3 — AWS Production

Provisions cloud infrastructure with Terraform and deploys via Ansible + GitHub Actions.

#### 1. Bootstrap Terraform state backend (one-time)

```bash
export TF_STATE_BUCKET="telescope-tfstate-$(aws sts get-caller-identity --query Account --output text)"
export AWS_REGION="us-east-1"

aws s3api create-bucket --bucket $TF_STATE_BUCKET --region $AWS_REGION
aws s3api put-bucket-versioning --bucket $TF_STATE_BUCKET \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name telescope-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION
```

#### 2. Update backend config

```bash
# Set your bucket name in the Terraform backend
sed -i "s/REPLACE_WITH_YOUR_TF_STATE_BUCKET/$TF_STATE_BUCKET/" \
  terraform/environments/dev/main.tf
```

#### 3. Deploy

```bash
./scripts/aws-deploy.sh
```

This runs `terraform apply` to provision all AWS resources, then runs the Ansible playbook to bootstrap the EKS cluster, install the AWS Load Balancer Controller, deploy Prometheus and Grafana via Helm, and apply all Kubernetes manifests.

#### 4. Tear down when not in use

```bash
./scripts/aws-teardown.sh
```

---

## CI/CD Pipeline

Every push to `main` triggers the full pipeline. Pull requests run lint, tests, and a Terraform plan only.

```
Push to main
    │
    ├── [test]            pnpm install → lint → unit tests
    │
    ├── [build-push]      Docker build (all services) → push to ECR
    │        │
    │        └── image tag: first 7 chars of commit SHA
    │
    ├── [terraform-plan]  runs on PRs only — posts plan output
    │
    └── [deploy]          update-kubeconfig → kustomize image tags
                          → kubectl apply → rollout status
                          → smoke test ALB endpoints
```

### Required GitHub Secrets

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_ACCOUNT_ID` | AWS account ID |

---

## Observability

Prometheus scrapes metrics from all running services every 15 seconds. Grafana is pre-provisioned with the Prometheus datasource.

**Metrics collected:**
- Request rate and latency per microservice
- HTTP error rate (4xx/5xx)
- Pod CPU and memory utilization
- Elasticsearch cluster health and query performance
- Redis connection and command stats
- Traefik routing and upstream health

**Access Grafana locally:**
```bash
open http://localhost:3001   # Docker Compose
# or
minikube service grafana -n monitoring --url --profile=telescope   # Kubernetes
```

---

## AWS Cost (Student-Optimised)

| Resource | Configuration | Est. monthly |
|---|---|---|
| EKS control plane | 1 cluster | $73.00 |
| Fargate Spot compute | ~4 vCPU / 8 GB avg | ~$15.00 |
| ElastiCache Redis | `cache.t3.micro`, single node | $12.00 |
| Application Load Balancer | minimal LCUs | $5.00 |
| NAT Gateway | 1 shared across all AZs | $5.00 |
| ECR storage | ~3 GB | $0.30 |
| Route 53 | 1 hosted zone | $0.50 |
| **Total** | | **~$111/mo** |

**Cost controls built in:**
- Fargate Spot for all workloads (~60% cheaper than on-demand)
- Single NAT gateway instead of one per AZ
- ECR lifecycle policies retain only the last 10 images
- `aws-teardown.sh` destroys all resources when not in use — run it at end of day

---

## Environment Variables

All configuration is driven by environment variables. The development defaults live in `telescope/config/env.development`. For Kubernetes deployments, values are split between a `ConfigMap` (non-sensitive) and a `Secret` (credentials, JWT keys, Supabase keys).

Key variables:

| Variable | Purpose |
|---|---|
| `REDIS_URL` | Redis connection string |
| `ELASTIC_URL` | Elasticsearch host |
| `JWT_SECRET` | Token signing key |
| `POSTGRES_PASSWORD` | Supabase database password |
| `SSO_IDP_PUBLIC_KEY_CERT` | SAML identity provider certificate |
| `ANON_KEY` / `SERVICE_ROLE_KEY` | Supabase API keys |

---

## License

Infrastructure code in this repository is MIT licensed.
The Telescope application source code is licensed under [BSD-2-Clause](https://github.com/Seneca-CDOT/telescope/blob/master/LICENSE).
