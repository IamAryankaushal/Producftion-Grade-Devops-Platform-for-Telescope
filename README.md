# Telescope DevOps Platform

> A production-grade, end-to-end DevOps platform built for [Telescope](https://github.com/Seneca-CDOT/telescope) — an actively maintained open-source microservices application developed by Seneca College with 180+ contributors and real production traffic.

This repository contains the complete infrastructure lifecycle for Telescope: local containerization, Kubernetes orchestration, cloud provisioning, configuration management, observability, and automated CI/CD. Every layer is built with industry-standard tooling and documented as a reference for how a real engineering team would operate a microservices platform.

**Source application:** [github.com/Seneca-CDOT/telescope](https://github.com/Seneca-CDOT/telescope)

---

## Table of Contents

- [How Each Tool Was Used](#how-each-tool-was-used)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Microservices](#microservices)
- [Prerequisites](#prerequisites)
- [Phase 1 — Local Docker Compose](#phase-1--local-docker-compose)
- [Phase 2 — Local Kubernetes with Minikube](#phase-2--local-kubernetes-with-minikube)
- [Phase 3 — AWS Production](#phase-3--aws-production)
- [Terraform Modules](#terraform-modules)
- [Ansible Roles and Playbooks](#ansible-roles-and-playbooks)
- [Kubernetes Manifests](#kubernetes-manifests)
- [CI/CD Pipeline](#cicd-pipeline)
- [Scripts Reference](#scripts-reference)
- [Observability](#observability)
- [Environment Variables](#environment-variables)
- [Configuration You Must Set](#configuration-you-must-set)
- [AWS Cost](#aws-cost)

---

## How Each Tool Was Used

This section explains the specific role each tool plays in this platform and why it was chosen for that role.

---

### Docker

Docker is the foundation of the entire platform. Every Telescope microservice is packaged as a Docker image built from a Dockerfile in the upstream source repository. Docker provides the guarantee that a service behaves identically in local development, in a Minikube cluster, and on AWS EKS — the environment is the same in every case because the container is the same.

**How it was used in this project:**

Each of the eight microservices has its own Dockerfile under `telescope/src/api/<service>/`. Docker builds each service independently, installing only its production dependencies and copying only its source files. The resulting images are small, isolated, and independently deployable.

A custom Dockerfile was written for the `image` service at `docker/image.Dockerfile`. The upstream Dockerfile compiles the `sharp` native image processing library for the glibc C library (used by standard Linux), but Minikube and Alpine-based containers use musl libc. The custom Dockerfile rebuilds sharp specifically for the musl platform, which was the root cause of the image service CrashLoopBackOff in Kubernetes.

For local development, Docker Compose orchestrates all services together in a single command. The upstream Telescope repository ships its own `docker/docker-compose.yml` and we extend it with `docker/docker-compose.override.yml` which adds Prometheus and Grafana as a monitoring overlay without modifying the upstream files.

**Key Docker decisions:**
- `imagePullPolicy: Never` in the local Kubernetes overlay — images are built directly inside Minikube's Docker daemon so no registry is needed locally
- `imagePullPolicy: Always` in the production overlay — ensures EKS always pulls the latest ECR image rather than using a cached version
- Multi-stage builds in the upstream Dockerfiles — separate dependency installation from source copying so layer caching is maximally effective

---

### Docker Compose

Docker Compose is the local development environment. It runs all ten services — traefik, posts, search, image, status, sso, parser, feed-discovery, redis, elasticsearch — in a single network with a single command, wiring up all the service-to-service connections automatically.

**How it was used in this project:**

The upstream Telescope repository assembles its development stack from four compose files chained via the `COMPOSE_FILE` environment variable:

```
docker/docker-compose.yml               core service definitions
docker/development.yml                  dev overrides (live reload, volumes)
docker/supabase/docker-compose.yml      supabase stack
docker/supabase/supabase-development.yml  supabase dev config
```

Rather than modifying any upstream files, a fifth file `docker/docker-compose.override.yml` was added. This overlay adds Prometheus and Grafana to the running stack using host networking so they can scrape metrics from the telescope containers without joining their internal Docker network.

The `start-local.sh` script handles the environment preparation — it copies `config/env.development` as `.env`, applies three sed fixes (Linux path separators, container hostnames for Redis and Elasticsearch), and starts the correct subset of services, deliberately excluding the nginx/docs service which fails to build under Node 18 due to a dependency conflict.

---

### Kubernetes

Kubernetes is the container orchestration layer. It takes individual Docker containers and manages them as a distributed system — scheduling them across compute, restarting failed containers, routing traffic, scaling under load, and rolling out new versions without downtime.

**How it was used in this project:**

The platform has two Kubernetes environments:

**Local (Minikube):** A single-node cluster running inside Docker on the developer's machine. All service images are built directly inside Minikube's Docker daemon. The ingress-nginx addon provides L7 routing. The metrics-server addon enables HPA autoscaling. This environment mirrors production as closely as possible without any cloud costs.

**Production (AWS EKS):** A managed Kubernetes 1.28 cluster on AWS with all workloads running on Fargate Spot. Three Fargate profiles cover the `telescope`, `monitoring`, and `kube-system` namespaces. The AWS Load Balancer Controller translates Kubernetes Ingress objects into real AWS Application Load Balancers, handling pod IP changes automatically.

All manifests are written in the `k8s/base/` directory and managed with Kustomize. Kustomize overlays (`k8s/overlays/local/` and `k8s/overlays/production/`) apply environment-specific patches — replica counts, image pull policies, and ECR image URLs — without duplicating any base manifest.

HorizontalPodAutoscalers are configured for the two highest-traffic services. The posts service scales between 1 and 5 replicas targeting 60% CPU and 70% memory utilization. The search service scales between 1 and 4 replicas. Both require the metrics-server to be running in the cluster.

**Key Kubernetes decisions:**
- Kustomize over Helm for the application manifests — gives full control over every field without a templating layer
- Fargate Spot over managed node groups — no EC2 nodes to patch or manage, ~60% cheaper than on-demand, no idle capacity cost
- Single Ingress resource with path-based routing — all `/v1/*` paths handled by one ALB rather than one load balancer per service
- `emptyDir` volumes for Redis and Elasticsearch in dev — avoids PersistentVolume complexity; data is ephemeral which is acceptable for development

---

### AWS

AWS is the cloud provider for the production environment. The platform uses a carefully selected set of services chosen for both capability and cost at the student budget level.

**How each AWS service was used:**

**VPC** — A custom VPC (`10.0.0.0/16`) with two public subnets and two private subnets across two availability zones provides network isolation. All application workloads run in private subnets and cannot be reached directly from the internet. Only the ALB lives in public subnets. A single NAT Gateway in the first public subnet (rather than one per AZ) provides outbound internet access from private subnets while saving ~$32/month.

**EKS** — The managed Kubernetes control plane. AWS manages the API server, etcd, and controller manager. We only manage the workloads running on it. Using Fargate means there are no EC2 worker nodes to manage, patch, or right-size. Fargate Spot provides the same serverless compute at a ~60% discount in exchange for occasional interruptions which Kubernetes handles by rescheduling.

**ECR** — One private repository per microservice stores Docker images. Image scanning on push automatically checks for known CVEs. Lifecycle policies keep only the ten most recent images per repository, preventing unbounded storage costs. Images are tagged with both the short commit SHA (for traceability) and `latest` (for convenience).

**IAM** — Three roles are created. The EKS cluster role allows the Kubernetes control plane to make AWS API calls. The Fargate pod execution role allows pods to pull images from ECR. The ALB controller role, using IRSA (IAM Roles for Service Accounts) via the OIDC provider, gives the AWS Load Balancer Controller pod the permissions it needs to create and manage ALBs without any static credentials in the cluster.

**RDS PostgreSQL** — A `db.t3.micro` PostgreSQL 15.4 instance in private subnets serves as the Supabase database backend. Single-AZ, no multi-AZ standby, 20GB gp2 storage, 1-day backup retention. These choices minimize cost while keeping the database functional for a development/demo environment.

**Application Load Balancer** — Created dynamically by the AWS Load Balancer Controller when the Kubernetes Ingress manifest is applied. Internet-facing, listening on port 80, with path-based routing to each microservice. Target type is `ip` rather than `instance` so traffic goes directly to pod IPs, bypassing kube-proxy entirely for better performance.

**S3 + DynamoDB** — Terraform remote state is stored in a versioned, encrypted S3 bucket. A DynamoDB table with a `LockID` hash key prevents concurrent Terraform operations from corrupting state. Both are created by a separate bootstrap Terraform workspace that uses local state, solving the chicken-and-egg problem.

**CloudWatch + SNS** — A billing alarm monitors `EstimatedCharges` daily and triggers an SNS topic that sends an email if spend exceeds $5. This catches accidental resource leaks immediately.

---

### Terraform

Terraform is the infrastructure-as-code tool. It provisions and manages all AWS resources declaratively — you describe what should exist, Terraform figures out how to create it, and tracks the current state so it knows what to change on subsequent runs.

**How it was used in this project:**

The Terraform codebase is organized into reusable modules and environment-specific root configurations:

**Bootstrap workspace** (`terraform/bootstrap/`) uses local state intentionally. It creates the S3 bucket and DynamoDB table that all other workspaces use as their remote backend. It runs once and is never touched again. `prevent_destroy = true` is set on both resources so they cannot be accidentally deleted.

**Modules** are self-contained units of infrastructure with defined inputs and outputs:
- `modules/vpc` — network layer
- `modules/eks` — cluster and Fargate profiles, OIDC provider
- `modules/iam` — all IAM roles, policies, billing alarm
- `modules/ecr` — repositories and lifecycle policies
- `modules/rds` — PostgreSQL instance and security group
- `modules/security-groups` — ALB and pod security groups
- `modules/route53` — reference only, not executed

**Root environment** (`environments/dev/`) calls all active modules, wires their outputs together as inputs, and defines the S3 backend. A `terraform.tfvars` file holds the environment-specific values that change between deployments.

**Key Terraform decisions:**
- Module-per-concern rather than one large `main.tf` — each module is independently testable and reusable
- `depends_on` between EKS and IAM modules — ensures IAM roles exist before EKS tries to use them
- `sensitive = true` on `db_password` variable — prevents the password from appearing in plan output or logs
- Two AWS provider aliases — the billing alarm CloudWatch metric only exists in `us-east-1` regardless of deployment region, requiring a second provider alias pointing to that region
- Route53/ACM module written but commented out — demonstrates knowledge of the full production architecture without incurring domain registration costs

---

### Ansible

Ansible handles everything that happens after Terraform finishes. Where Terraform owns AWS resource creation, Ansible owns cluster configuration — anything that requires running commands against a live system rather than declaring resource state.

**How it was used in this project:**

Ansible runs locally against `localhost` using the `local` connection plugin. No SSH, no remote inventory. It reads Terraform outputs directly using `terraform output -json` and uses those values to configure the cluster without any hardcoded values.

The codebase is organized into three roles:

**`roles/common`** installs baseline tooling — AWS CLI v2, kubectl, and Helm — on any target host. Uses the `apt` module for system packages, `get_url` for binary downloads, and `copy` for installation. Controlled by boolean variables (`install_aws_cli`, `install_kubectl`, `install_helm`) so individual tools can be skipped if already present.

**`roles/docker`** handles Docker Engine installation, ECR authentication, image builds, and pushes. The build task iterates over the `service_list` variable, checks for a Dockerfile in each service directory, and builds the image. The image service is handled as a special case using the custom musl-compatible Dockerfile. The push task tags and pushes both SHA-tagged and `latest` versions.

**`roles/monitoring`** installs Prometheus and Grafana into the cluster via Helm. Adds the `prometheus-community` and `grafana` Helm repositories, installs both charts into the `monitoring` namespace, waits for rollouts to complete, configures the Grafana Prometheus datasource via the Grafana HTTP API, and outputs the access URLs.

**`bootstrap-cluster.yml`** is the main deployment playbook. It reads Terraform outputs, configures kubectl, creates namespaces, patches CoreDNS for Fargate compatibility, installs the AWS Load Balancer Controller, invokes the monitoring and docker roles, updates the Kustomize production overlay with ECR URLs, applies all Kubernetes manifests, and waits for the ALB to be provisioned before printing the final access URLs.

**`destroy-cluster.yml`** runs an interactive teardown. It prompts for confirmation, removes Kubernetes resources first (which triggers the ALB controller to delete the ALB from AWS), waits for AWS to clean up the load balancers, then runs `terraform destroy`. Finally it verifies that no billable resources remain.

**Key Ansible decisions:**
- `group_vars/all.yml` for shared variables — single source of truth for region, namespace names, service list, and tool flags
- `ignore_errors: true` on the CoreDNS patch — the annotation may not exist on all cluster versions; the task should not fail the entire playbook if the patch is a no-op
- Reading Terraform outputs rather than hardcoding values — the ALB controller role ARN, VPC ID, and cluster name all come from `terraform output -json` so the playbook works correctly across different accounts and regions without modification

---

### Prometheus

Prometheus is the metrics collection system. It scrapes HTTP endpoints on each microservice and infrastructure component every 15 seconds, stores the time-series data locally, and makes it available for querying and alerting.

**How it was used in this project:**

In Phase 1 (Docker Compose), Prometheus runs as a container in the monitoring overlay using host networking. This allows it to reach all Telescope service ports directly on localhost without needing to be on the same Docker network.

In Phase 2 and 3 (Kubernetes), Prometheus is deployed via the `prometheus-community/prometheus` Helm chart into the `monitoring` namespace. The chart deploys the Prometheus server, a node exporter DaemonSet, and a kube-state-metrics deployment which exposes Kubernetes object metrics (replica counts, pod status, HPA state) as Prometheus metrics.

The scrape configuration in `monitoring/prometheus/prometheus.yml` defines nine scrape jobs covering the Prometheus server itself, Traefik, all six microservice APIs, Redis, and Elasticsearch. Each job specifies the target host:port and the metrics path. The satellite framework used by Telescope's Node.js services automatically exposes a `/v1/metrics` endpoint on each service.

**Key metrics collected:**
- HTTP request rate and duration per service and status code
- Active connections and queue depth in Redis
- Elasticsearch indexing rate, search latency, and cluster health
- Traefik upstream response times and error rates
- Kubernetes pod CPU and memory utilization
- HPA current and desired replica counts

---

### Grafana

Grafana is the visualization layer. It connects to Prometheus as a datasource and renders the collected metrics as dashboards and graphs.

**How it was used in this project:**

In Phase 1, Grafana runs as a container in the monitoring overlay on port 3001. In Phase 2 and 3, it is deployed via Helm into the `monitoring` namespace with a LoadBalancer service type so it gets a public URL from AWS.

Grafana is configured through provisioning files rather than manual UI setup. `monitoring/grafana/provisioning/datasources/prometheus.yml` automatically registers the Prometheus instance as the default datasource at startup — no clicking required. `monitoring/grafana/provisioning/dashboards/default.yml` configures the file-based dashboard provider to load JSON dashboard files from a mounted directory.

In the Kubernetes deployment, the Ansible monitoring role additionally configures the datasource via the Grafana HTTP API after the pod starts, ensuring the connection is established even when the provisioning files are not mounted.

**Default credentials:** `admin / telescope123`

**Key dashboards:**
- Service request rate and p99 latency
- HTTP error rate per service
- Pod CPU and memory vs resource limits
- Redis hit rate and connected clients
- Elasticsearch cluster health and query performance
- HPA scaling events over time

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
║              INFRASTRUCTURE AS CODE + CONFIG MANAGEMENT              ║
║                                                                      ║
║  Terraform (ALL AWS resources)       Ansible (ALL configuration)    ║
║  ├── bootstrap/                      ├── roles/common               ║
║  │   └── S3 bucket + DynamoDB        │   └── aws-cli, kubectl, helm ║
║  └── environments/dev/               ├── roles/docker               ║
║      ├── modules/vpc                 │   └── build + push to ECR    ║
║      ├── modules/eks                 ├── roles/monitoring            ║
║      ├── modules/iam                 │   └── prometheus + grafana    ║
║      ├── modules/ecr                 └── playbooks/                 ║
║      ├── modules/rds                     ├── bootstrap-cluster.yml  ║
║      ├── modules/security-groups         └── destroy-cluster.yml    ║
║      └── modules/route53  ← ref only                                ║
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
║   Application Load Balancer                                          ║
║   (created by AWS Load Balancer Controller reacting to Ingress)      ║
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
║   │   │  └── Grafana     (dashboards + alerting)        │  │          ║
║   │   └────────────────────────────────────────────────┘  │          ║
║   │                                                       │          ║
║   │   RDS PostgreSQL 15  (db.t3.micro, private subnet)   │          ║
║   │   ECR  (8 repos, one per service)                    │          ║
║   │   S3 + DynamoDB  (Terraform remote state)            │          ║
║   │   IAM  (EKS role, Fargate role, ALB controller role) │          ║
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
║       └── dashboards: request rate · latency · error rate           ║
║                        pod resources · HPA scaling · redis · ES      ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## Tech Stack

| Layer | Tool | Purpose |
|---|---|---|
| Containerization | Docker | Package each microservice into a portable image |
| Local orchestration | Docker Compose | Run the full multi-service stack locally |
| Kubernetes (local) | Minikube | Single-node k8s cluster for local development |
| Kubernetes (cloud) | AWS EKS Fargate | Managed serverless Kubernetes in production |
| Manifest management | Kustomize | Environment-specific overlays without duplication |
| Infrastructure as Code | Terraform | Provision and manage all AWS resources declaratively |
| Configuration management | Ansible | Bootstrap EKS, install tooling, build and push images |
| CI/CD | GitHub Actions | Automated lint, test, build, push, and deploy |
| Container registry | Amazon ECR | Store and version Docker images per service |
| Reverse proxy (local) | Traefik | API gateway and service routing in Docker Compose |
| Ingress (cloud) | AWS ALB + Controller | Route external traffic into the Kubernetes cluster |
| Database | AWS RDS PostgreSQL | Managed Supabase backend database |
| Metrics | Prometheus | Scrape and store time-series metrics from all services |
| Dashboards | Grafana | Visualize metrics with provisioned datasources |
| Package manager (k8s) | Helm | Install Prometheus and Grafana into Kubernetes |
| Scripting | Bash | Automate startup, teardown, health checks, deployment |

---

## Repository Structure

```
telescope-devops/
│
├── telescope/                              # Upstream source (Seneca-CDOT/telescope)
│
├── docker/
│   ├── .env.local                          # Local env vars for Docker Compose
│   ├── docker-compose.override.yml         # Monitoring overlay (Prometheus + Grafana)
│   └── image.Dockerfile                    # Custom Dockerfile for image service (sharp/musl fix)
│
├── k8s/
│   ├── base/                               # Kustomize base — environment-agnostic manifests
│   │   ├── kustomization.yaml              # Base resource list
│   │   ├── configmaps/
│   │   │   └── app-config.yaml             # All non-sensitive env vars as ConfigMap
│   │   ├── secrets/
│   │   │   └── app-secrets.yaml            # JWT, DB passwords, SAML certs as k8s Secret
│   │   ├── deployments/
│   │   │   ├── redis.yaml                  # Redis deployment
│   │   │   ├── elasticsearch.yaml          # Elasticsearch deployment with sysctl init
│   │   │   ├── posts.yaml                  # Posts microservice
│   │   │   ├── search.yaml                 # Search microservice
│   │   │   ├── image.yaml                  # Image proxy microservice
│   │   │   ├── status.yaml                 # Status API microservice
│   │   │   ├── feed-discovery.yaml         # Feed discovery microservice
│   │   │   ├── sso.yaml                    # SSO/auth microservice
│   │   │   ├── login.yaml                  # Test SAML IdP
│   │   │   └── hpa.yaml                    # HPA for posts and search
│   │   ├── services/
│   │   │   └── all-services.yaml           # ClusterIP services for all deployments
│   │   └── ingress/
│   │       └── telescope-ingress.yaml      # Path-based ingress routing
│   │
│   └── overlays/
│       ├── local/                          # Minikube overrides
│       │   ├── kustomization.yaml          # replicas=1, imagePullPolicy=Never
│       │   └── kind-config.yaml            # Reference kind cluster config
│       └── production/                     # EKS overrides
│           ├── kustomization.yaml          # replicas=2, ECR image refs
│           └── alb-ingress-patch.yaml      # ALB annotations for AWS
│
├── terraform/
│   ├── bootstrap/                          # One-time state backend creation
│   │   ├── main.tf                         # S3 bucket + DynamoDB table (local state)
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── modules/
│   │   ├── vpc/                            # VPC, subnets, IGW, NAT, route tables
│   │   ├── eks/                            # EKS cluster, Fargate profiles, OIDC
│   │   ├── iam/                            # All IAM roles, policies, billing alarm
│   │   ├── ecr/                            # ECR repos + lifecycle policies
│   │   ├── rds/                            # RDS PostgreSQL + security group
│   │   ├── security-groups/                # ALB and pod security groups
│   │   └── route53/                        # DNS + TLS — REFERENCE ONLY, not executed
│   └── environments/
│       └── dev/
│           ├── main.tf                     # Root config — calls all active modules
│           ├── variables.tf                # project_name, environment, region, email, db_password
│           ├── outputs.tf                  # All module outputs
│           └── terraform.tfvars            # Actual values — update before running
│
├── ansible/
│   ├── group_vars/
│   │   └── all.yml                         # Shared variables for all roles and playbooks
│   ├── inventory/
│   │   └── localhost                       # Local connection inventory
│   ├── playbooks/
│   │   ├── bootstrap-cluster.yml           # Main deploy playbook — uses all three roles
│   │   └── destroy-cluster.yml             # Guided teardown
│   └── roles/
│       ├── common/
│       │   └── tasks/main.yml              # AWS CLI, kubectl, Helm installation
│       ├── docker/
│       │   └── tasks/main.yml              # Docker install, ECR login, build, push
│       └── monitoring/
│           └── tasks/main.yml              # Prometheus + Grafana via Helm
│
├── .github/
│   └── workflows/
│       └── ci-cd.yml                       # Full 4-job CI/CD pipeline
│
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus.yml                  # Scrape config for all services
│   └── grafana/
│       └── provisioning/
│           ├── datasources/
│           │   └── prometheus.yml          # Auto-provision Prometheus datasource
│           └── dashboards/
│               └── default.yml             # Dashboard file provider config
│
└── scripts/
    ├── start-local.sh                      # Start full local Docker Compose stack
    ├── stop-local.sh                       # Stop and clean up local stack
    ├── logs.sh                             # Tail logs for a specific service
    ├── health-check.sh                     # Hit all endpoints and report HTTP status
    ├── aws-deploy.sh                       # bootstrap + terraform apply + ansible
    └── aws-teardown.sh                     # Destroy all AWS resources safely
```

---

## Microservices

All services are part of the Telescope monorepo under `src/api/` and built as independent Node.js applications using the `@senecacdot/satellite` framework.

| Service | Role | Port | Path |
|---|---|---|---|
| `posts` | Feed post CRUD — stores and serves parsed blog posts | 5555 | `/v1/posts` |
| `search` | Elasticsearch-backed full-text search | 4445 | `/v1/search` |
| `image` | Unsplash image proxy — header images for posts | 4444 | `/v1/image` |
| `status` | Health and uptime API | 1111 | `/v1/status` |
| `feed-discovery` | Discovers RSS/Atom feed URLs | 9999 | `/v1/feed-discovery` |
| `sso` | SAML 2.0 authentication | 7777 | `/v1/auth` |
| `parser` | Feed parser worker — pulls from RSS Bridge | 10000 | `/v1/parser` |
| `dependency-discovery` | Scans repos for open-source dependencies | 10500 | `/v1/dependency-discovery` |
| `traefik` | Reverse proxy / API gateway | 80, 443 | — |
| `redis` | Bull queue backend + session cache | 6379 | — |
| `elasticsearch` | Full-text search engine | 9200 | — |

---

## Prerequisites

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

Runs the complete Telescope microservices stack locally using Docker Compose with a Prometheus and Grafana monitoring overlay.

```bash
git clone https://github.com/your-username/telescope-devops.git
cd telescope-devops
git clone https://github.com/Seneca-CDOT/telescope.git

./scripts/start-local.sh
```

| Endpoint | URL |
|---|---|
| API Gateway | `http://localhost:80` |
| Traefik Dashboard | `http://localhost:8080` |
| Posts API | `http://localhost/v1/posts` |
| Status API | `http://localhost/v1/status` |
| Prometheus | `http://localhost:9090` |
| Grafana | `http://localhost:3001` — `admin / telescope123` |

```bash
# Verify all services
./scripts/health-check.sh

# Tail logs
./scripts/logs.sh posts

# Stop
./scripts/stop-local.sh
```

---

## Phase 2 — Local Kubernetes with Minikube

```bash
# Start cluster
minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=6144 \
  --kubernetes-version=v1.28.0 \
  --profile=telescope

# Enable addons
minikube addons enable ingress --profile=telescope
minikube addons enable metrics-server --profile=telescope

# Build images inside Minikube
eval $(minikube docker-env --profile=telescope)
cd telescope
docker build -t telescope/posts:local          -f src/api/posts/Dockerfile          src/api/posts/
docker build -t telescope/search:local         -f src/api/search/Dockerfile         src/api/search/
docker build -t telescope/image:local          -f ../docker/image.Dockerfile        src/api/image/
docker build -t telescope/status:local         -f src/api/status/Dockerfile         src/api/status/
docker build -t telescope/feed-discovery:local -f src/api/feed-discovery/Dockerfile src/api/feed-discovery/
docker build -t telescope/sso:local            -f src/api/sso/Dockerfile            src/api/sso/
docker build -t telescope/parser:local         -f src/api/parser/Dockerfile         src/api/parser/
eval $(minikube docker-env --profile=telescope -u)

# Deploy
cd ..
kubectl create namespace telescope
kubectl apply -k k8s/overlays/local/
kubectl get pods -n telescope -w

# Install monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts && helm repo update
kubectl create namespace monitoring
helm install prometheus prometheus-community/prometheus -n monitoring \
  --set server.service.type=NodePort --set alertmanager.enabled=false
helm install grafana grafana/grafana -n monitoring \
  --set service.type=NodePort --set adminPassword=telescope123

# Access
MINIKUBE_IP=$(minikube ip --profile=telescope)
curl http://$MINIKUBE_IP/v1/status
minikube service grafana -n monitoring --url --profile=telescope
```

---

## Phase 3 — AWS Production

### Before you start

```bash
# Configure AWS
aws configure   # region: ap-south-1

# Download the ALB controller IAM policy (required by Terraform)
curl -sL https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json \
  -o terraform/modules/iam/alb-controller-policy.json

# Update these values before running anything
nano terraform/environments/dev/terraform.tfvars
# Set: alert_email, db_password

# Update Kubernetes secrets to match db_password
nano k8s/base/secrets/app-secrets.yaml
# Set: POSTGRES_PASSWORD to same value as db_password
```

### Deploy

```bash
./scripts/aws-deploy.sh
```

The script runs in three stages automatically:
1. Bootstrap — creates S3 state bucket and DynamoDB lock table via Terraform (skipped if already exists)
2. Provision — `terraform apply` creates VPC, EKS, ECR, IAM, RDS, security groups
3. Configure — Ansible bootstraps the cluster, installs ALB controller, deploys monitoring, builds and pushes images, applies manifests

Total time: approximately 20 minutes.

### Verify

```bash
kubectl get nodes
kubectl get pods -n telescope
kubectl get pods -n monitoring
kubectl get ingress -n telescope

ALB=$(kubectl get ingress telescope-ingress -n telescope \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$ALB/v1/status
curl http://$ALB/v1/posts
```

### Teardown

```bash
./scripts/aws-teardown.sh
# Type 'destroy' when prompted
```

---

## Terraform Modules

### Active modules (executed on every `terraform apply`)

**`bootstrap/`** — runs once to create the remote state backend. Uses local state intentionally. Creates the S3 bucket with versioning and AES256 encryption, public access block, and the DynamoDB lock table. `prevent_destroy = true` on both resources.

**`modules/vpc`** — VPC (`10.0.0.0/16`), two public subnets, two private subnets across two AZs, Internet Gateway, single shared NAT Gateway, public and private route tables and associations. Subnet tags applied for EKS and ALB discovery.

**`modules/eks`** — EKS 1.28 control plane, three Fargate profiles (telescope, monitoring, kube-system), OIDC provider for IRSA. Control plane logging disabled to avoid CloudWatch costs.

**`modules/iam`** — EKS cluster role with `AmazonEKSClusterPolicy`, Fargate pod execution role with `AmazonEKSFargatePodExecutionRolePolicy` and ECR pull inline policy, ALB controller role using IRSA trust policy, billing CloudWatch alarm and SNS topic in `us-east-1`.

**`modules/ecr`** — One ECR private repository per service using `for_each`. Image scanning on push enabled. Lifecycle policy retaining the ten most recent images on each repository.

**`modules/rds`** — RDS PostgreSQL 15.4 on `db.t3.micro`, 20GB gp2 storage, private subnets, dedicated security group allowing port 5432 from within the VPC, no multi-AZ, `skip_final_snapshot = true`, `deletion_protection = false` for dev teardown.

**`modules/security-groups`** — ALB security group allowing inbound 80 and 443 from the internet. EKS pods security group allowing all traffic from the ALB security group and pod-to-pod within the VPC CIDR.

### Reference module (not executed)

**`modules/route53`** — Hosted zone, ACM TLS certificate with DNS validation (apex and wildcard), Route 53 validation records, A alias records pointing domain and `*.domain` to the ALB. The module call is commented out in `environments/dev/main.tf`. Activate by providing a registered domain name and uncommenting the block. Cost: ~$0.50/month for the zone. ACM cert is free.

---

## Ansible Roles and Playbooks

### `roles/common`

Installs baseline tooling on any target host. Downloads and installs AWS CLI v2, kubectl, and Helm. Each tool installation is controlled by a boolean variable so tools already present can be skipped. Verifies installations by running version commands and printing output.

### `roles/docker`

Installs Docker Engine from the official apt repository. Adds the current user to the docker group. Logs into Amazon ECR using `aws ecr get-login-password`. Builds all service images iterating over `service_list`, using the custom `image.Dockerfile` for the image service. Pushes both SHA-tagged and `latest` versions to ECR.

### `roles/monitoring`

Adds the `prometheus-community` and `grafana` Helm repositories. Installs Prometheus with persistent volumes disabled, alertmanager disabled, and the configured scrape interval. Installs Grafana with a LoadBalancer service type and the admin password from `group_vars`. Waits for both rollouts. Configures the Grafana Prometheus datasource via the HTTP API. Outputs both service URLs.

### `playbooks/bootstrap-cluster.yml`

Main deployment playbook. Reads all values from Terraform outputs so nothing is hardcoded. Configures kubectl, creates namespaces, patches and restarts CoreDNS for Fargate compatibility, adds Helm repos, installs the AWS Load Balancer Controller with the IRSA role ARN, invokes the monitoring role, invokes the docker role to build and push images, updates the kustomize production overlay with ECR URLs, patches the ConfigMap with the RDS endpoint, applies all Kubernetes manifests, waits for the ALB to be provisioned, and prints the final access URLs.

### `playbooks/destroy-cluster.yml`

Interactive teardown playbook. Prompts for `destroy` confirmation. Removes the Ingress and Grafana service first (triggering the ALB controller to delete the ALB from AWS). Waits 30 seconds for AWS cleanup. Runs `terraform destroy -auto-approve`. Verifies that EKS clusters, NAT gateways, load balancers, and RDS instances are all gone.

---

## Kubernetes Manifests

### `base/configmaps/app-config.yaml`

ConfigMap `telescope-config` containing all non-sensitive environment variables shared across microservices. Service ports, internal cluster service URLs, Elasticsearch configuration, SSO and SAML settings, JWT issuer and audience, feed processing parameters, and Supabase configuration. Mounted into every Deployment via `envFrom.configMapRef`.

### `base/secrets/app-secrets.yaml`

Secret `telescope-secrets` containing `JWT_SECRET`, `POSTGRES_PASSWORD`, `ANON_KEY`, `SERVICE_ROLE_KEY`, and `SSO_IDP_PUBLIC_KEY_CERT`. The `POSTGRES_PASSWORD` here must exactly match `db_password` in `terraform.tfvars`. Mounted alongside the ConfigMap via `envFrom.secretRef`.

### `base/deployments/`

One Deployment per service. All share the pattern: container image, `envFrom` referencing ConfigMap and Secret, resource requests and limits, HTTP readiness and liveness probes against `/` (using root path to avoid false failures when the database is empty). Redis and Elasticsearch use `emptyDir` volumes.

### `base/deployments/hpa.yaml`

Two HPAs. `telescope-posts-hpa` scales 1–5 replicas at 60% CPU / 70% memory. `telescope-search-hpa` scales 1–4 replicas at 60% CPU. Both require the metrics-server.

### `base/services/all-services.yaml`

ClusterIP services for all deployments. Internal cluster DNS only. External access goes through the Ingress exclusively.

### `base/ingress/telescope-ingress.yaml`

Single Ingress with regex path routing. Maps `/v1/posts`, `/v1/search`, `/v1/image`, `/v1/status`, `/v1/feed-discovery`, and `/v1/auth` to their respective services.

### `overlays/local/kustomization.yaml`

Patches replicas to 1 and `imagePullPolicy` to `Never`. For Minikube where images are built inside the cluster's Docker daemon.

### `overlays/production/kustomization.yaml`

Patches replicas to 2 for posts and search. Sets `imagePullPolicy: Always`. Rewrites all image names to full ECR URLs. Applies `alb-ingress-patch.yaml`.

### `overlays/production/alb-ingress-patch.yaml`

Adds ALB annotations to the Ingress: `scheme: internet-facing`, `target-type: ip`, `listen-ports: HTTP:80`, health check configuration. These annotations are what cause the AWS Load Balancer Controller to create a real ALB in AWS.

---

## CI/CD Pipeline

Four jobs defined in `.github/workflows/ci-cd.yml`.

**Job 1 — `test`** runs on every push and pull request. Checks out both repos, installs Node 18 and pnpm with caching, runs `pnpm install --frozen-lockfile`, lint, and unit tests. All downstream jobs depend on this passing.

**Job 2 — `build-push`** runs on push to main after job 1. Authenticates to ECR, sets image tag to 7-char commit SHA, builds all service images (custom Dockerfile for image service), pushes SHA-tagged and `latest` versions. Outputs the tag and registry URL for job 4.

**Job 3 — `terraform-plan`** runs on pull requests only. Initializes Terraform and runs a plan, printing the diff. Does not apply anything. `continue-on-error: true` so a plan warning does not block the PR.

**Job 4 — `deploy`** runs on push to main after job 2. Updates kubeconfig for EKS, uses kustomize to update image tags in the production overlay to the exact SHA from job 2, applies all manifests, waits for each rollout to complete, smoke-tests the ALB endpoint, prints the final pod and ingress status.

### Required GitHub Secrets

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_ACCOUNT_ID` | `aws sts get-caller-identity --query Account --output text` |

---

## Scripts Reference

**`start-local.sh`** — copies `config/env.development` as `.env`, applies Linux path separator fixes and container hostname fixes for Redis and Elasticsearch, runs `pnpm install`, starts core Docker Compose services excluding the nginx/docs service, waits for Elasticsearch, detects the Docker network name, starts the monitoring overlay.

**`stop-local.sh`** — stops the monitoring overlay, then stops all core Docker Compose services. Volumes are preserved.

**`logs.sh`** — wraps `docker compose logs`. No argument streams all services with 50-line tail. Service name argument streams that service with 100-line tail.

**`health-check.sh`** — curls all microservice API endpoints with a 5-second timeout. Reports HTTP status for each. Marks 200, 201, 301, 302, and 404 as healthy (404 means the container is up but has no data). Also checks Traefik, Prometheus, and Grafana.

**`aws-deploy.sh`** — three-stage deploy: (1) bootstrap Terraform state backend if not already done, (2) `terraform init` and `terraform apply -auto-approve`, (3) `ansible-playbook bootstrap-cluster.yml`.

**`aws-teardown.sh`** — prompts for `destroy` confirmation, then runs `ansible-playbook destroy-cluster.yml` which handles Kubernetes cleanup before `terraform destroy`.

---

## Observability

### Prometheus scrape targets

| Job | Target | Metrics path |
|---|---|---|
| `prometheus` | `localhost:9090` | `/metrics` |
| `traefik` | `localhost:8080` | `/metrics` |
| `telescope-posts` | `posts:5555` | `/v1/metrics` |
| `telescope-search` | `search:4445` | `/v1/metrics` |
| `telescope-status` | `status:1111` | `/v1/metrics` |
| `telescope-image` | `image:4444` | `/v1/metrics` |
| `telescope-feed-discovery` | `feed-discovery:9999` | `/v1/metrics` |
| `redis` | `redis:6379` | — |
| `elasticsearch` | `elasticsearch:9200` | `/_prometheus/metrics` |

### Generate load for Grafana screenshots

```bash
ALB="localhost"   # or your ALB hostname
for i in $(seq 1 300); do
  curl -s http://$ALB/v1/status > /dev/null
  curl -s http://$ALB/v1/posts  > /dev/null
done
# Wait 60 seconds then refresh Grafana
```

---

## Configuration You Must Set

### GitHub Secrets

| Secret | How to get it |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS Console → IAM → Users → Security credentials → Create access key |
| `AWS_SECRET_ACCESS_KEY` | Same screen |
| `AWS_ACCOUNT_ID` | `aws sts get-caller-identity --query Account --output text` |

### `terraform/environments/dev/terraform.tfvars`

```hcl
alert_email = "your-actual-email@example.com"   # receives billing alerts
db_password = "YourStrongPassword123!"           # RDS master password
```

### `k8s/base/secrets/app-secrets.yaml`

```yaml
POSTGRES_PASSWORD: "YourStrongPassword123!"   # must match db_password above
```

### Post-deploy

After `terraform apply` runs, AWS sends a subscription confirmation email to `alert_email`. Click the confirmation link or billing alerts will not be delivered.

---

## AWS Cost

### Active modules

| Resource | Configuration | Est. monthly |
|---|---|---|
| EKS control plane | 1 cluster | $73.00 |
| Fargate Spot compute | ~4 vCPU / 8 GB average | ~$15.00 |
| RDS PostgreSQL | `db.t3.micro`, 20GB, single-AZ | ~$15.00 |
| Application Load Balancer | created by k8s controller | ~$5.00 |
| NAT Gateway | 1 shared across both AZs | $5.00 |
| ECR storage | ~3 GB across all repos | $0.30 |
| S3 + DynamoDB | Terraform state backend | ~$0.00 |
| **Total** | | **~$113/mo** |

### Reference modules (not executed)

| Resource | Cost if activated |
|---|---|
| Route 53 hosted zone | +$0.50/mo |
| ACM certificate | free |

### Cost controls

- **Fargate Spot** — ~60% cheaper than on-demand Fargate
- **Single NAT Gateway** — saves ~$32/month vs one-per-AZ
- **ECR lifecycle policies** — max 10 images per repo
- **`aws-teardown.sh`** — EKS control plane costs $2.40/day at idle; destroy and reprovision (~20 min) between sessions
- **Billing alarm** — CloudWatch fires at $5/day spend

---
