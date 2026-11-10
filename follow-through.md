# Project 2: Containerized Microservice on AWS ECS Fargate
> **Senior DevOps Guide & Engineering Deep Dive**  
> *Target Architecture*: Node.js Microservice -> Amazon ECR -> AWS ECS Fargate (Private Subnets) behind an Application Load Balancer (Public Subnets) provisioned with Terraform, automated via GitHub Actions matrix pipelines, and benchmarked with Bash load-testing.

---

## Architecture Overview

```
                      INTERNET / CLIENTS
                              │
                              ▼
                 ┌─────────────────────────┐
                 │ Application Load Balancer│ (Public Subnets: us-east-1a, 1b)
                 │     (Port 80 / 443)     │
                 └────────────┬────────────┘
                              │ HTTP :3000
                              ▼ Target Group (Health check: /health)
  ════════════════════════════════════════════════════════════════════
  PRIVATE VPC SUBNETS (No direct public IPs)
  
       ┌───────────────────────────────┐   ┌───────────────────────────────┐
       │   ECS Task 1 (Fargate)        │   │   ECS Task 2 (Fargate)        │
       │   - App Container (:3000)     │   │   - App Container (:3000)     │
       │   - awslogs log driver        │   │   - awslogs log driver        │
       └───────────────┬───────────────┘   └───────────────┬───────────────┘
                       │                                   │
                       └───────────────┬───────────────────┘
                                       │ Pull Image
                                       ▼
                          ┌─────────────────────────┐
                          │   Amazon ECR Registry   │
                          │ (microservice-api)      │
                          └─────────────────────────┘
```

---

## Step 0: Architectural Foundations & Mental Models

### What You Must Learn Before Touching Code
1. **The Shared Responsibility Model in Fargate**:
   - In traditional EC2-backed ECS, you patch the Linux OS, configure Docker daemon flags, rotate AMIs, and manage cluster auto-scaling.
   - In AWS Fargate, AWS handles underlying kernel security, hypervisor isolation, and host capacity. You are responsible solely for your container image, IAM permissions, CPU/memory configuration, task definitions, and networking security groups.
2. **Public vs. Private Subnet Partitioning**:
   - Never place backend application containers in public subnets unless there is an insurmountable constraint.
   - ALBs sit in public subnets with Internet Gateway (IGW) routes. ECS Tasks live in private subnets and reach the outside world via NAT Gateways or AWS VPC Endpoints (PrivateLink).
3. **Task Execution Role vs. Task Role**:
   - *ECS Task Execution Role*: Used by the ECS agent / infrastructure itself (pulling images from ECR, streaming container stdout/stderr to CloudWatch Logs, decrypting Secrets Manager/SSM parameters).
   - *ECS Task Role*: Used by the application code running inside the container (e.g. if the Node.js API queries Amazon DynamoDB or S3).

---

## Step 1: Docker Multi-Stage Build & Production Hardening

### The DevOps Objective
Build a lightweight, minimal, and secure container image where vulnerabilities and attack surfaces are eliminated before reaching any registry.

### Repository Layout
```
ecs-fargate-microservice/
├── app/
│   ├── .dockerignore
│   ├── Dockerfile
│   ├── package.json
│   ├── package-lock.json
│   └── server.js
├── terraform/
│   ├── environments/
│   │   ├── dev/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── terraform.tfvars
│   │   └── staging/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── terraform.tfvars
│   └── modules/
│       ├── vpc/
│       ├── alb/
│       └── ecs/
├── .github/
│   └── workflows/
│       └── deploy.yml
└── scripts/
    └── loadtest.sh
```

### Key Engineering Details in `app/Dockerfile`
```dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
# Safe dependency installation; fallback if zero external packages
RUN npm ci --omit=dev && mkdir -p /app/node_modules

FROM node:20-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# Non-root user setup (Principle of Least Privilege)
RUN addgroup -S nodejs && adduser -S nodejs -G nodejs

COPY --from=deps /app/node_modules ./node_modules
COPY --chown=nodejs:nodejs . .

USER nodejs
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD wget -qO- http://127.0.0.1:3000/health || exit 1

CMD ["node", "server.js"]
```

### Critical Teachings for this Step
- **Why Multi-stage Builds?**: Separates build dependencies (compilers, npm cache, dev dependencies) from runtime artifacts. This cuts image size from ~1GB down to ~50MB.
- **Why Non-Root User (`USER nodejs`)?**: By default, containers execute as `root`. If a remote code execution vulnerability occurs in an app running as root, an attacker has full root system calls within that namespace.
- **Why Docker Healthcheck?**: Provides self-healing inside Docker engine, and ECS task definitions can use container-level health checks to kill unready containers before routing traffic.

---

## Step 2: Infrastructure as Code (IaC) with Terraform

### The DevOps Objective
Declare the entire infrastructure deterministically using reusable Terraform modules. No manual clicks in the AWS Console.

### Module Breakdown
1. **Module `vpc`**:
   - 1 VPC (CIDR `10.0.0.0/16`)
   - 2 Public Subnets (across 2 Availability Zones for high availability)
   - 2 Private Subnets (across 2 Availability Zones for Fargate tasks)
   - 1 Internet Gateway (IGW) + Route table for Public Subnets
   - 1 or 2 NAT Gateways (Public subnets) with Elastic IPs + Route tables for Private Subnets (allows private tasks to pull ECR images and send logs).
2. **Module `alb`**:
   - Public Application Load Balancer in public subnets.
   - ALB Security Group: Inbound port 80/443 from `0.0.0.0/0`.
   - Target Group: Target type `ip` (required for Fargate with `awsvpc` network mode), protocol `HTTP`, port `3000`, health check path `/health`.
3. **Module `ecs`**:
   - AWS ECR Repository with image scanning enabled (`scan_on_push = true`) and lifecycle rules (keep last 30 images).
   - ECS Cluster (`aws_ecs_cluster`).
   - IAM Roles: `ecsTaskExecutionRole` with managed policy `service-role/AmazonECSTaskExecutionRolePolicy`.
   - CloudWatch Log Group: `/ecs/microservice-api-<env>` with retention policy (e.g., 14 days).
   - ECS Task Definition:
     - `network_mode = "awsvpc"`
     - `requires_compatibilities = ["FARGATE"]`
     - `cpu = "256"` (0.25 vCPU)
     - `memory = "512"` (512 MB)
     - `container_definitions` JSON with port mappings (`containerPort = 3000`), log configuration (`awslogs`).
   - ECS Service:
     - `launch_type = "FARGATE"`
     - `desired_count = 2` (Zero-downtime rolling updates)
     - `network_configuration`: `subnets = private_subnets`, `assign_public_ip = false`.
     - `load_balancer` block binding target group to container port 3000.
     - Security Group: Allow ingress on port 3000 **strictly** from the ALB Security Group ID.

### Critical Teachings for this Step
- **Security Group Chaining**: Do **not** open port 3000 to `0.0.0.0/0`. Set the ingress source of the ECS Security Group to `security_groups = [aws_security_group.alb.id]`. This enforces that traffic *must* flow through the ALB.
- **Target Type `ip` vs `instance`**: Fargate assigns each task its own Elastic Network Interface (ENI) with a private IP in your VPC (`awsvpc` mode). Therefore, the ALB Target Group must use `target_type = "ip"`.
- **Remote State & Locking**: In a team or production setup, never keep `terraform.tfstate` locally. Use an S3 backend with DynamoDB state locking to prevent race conditions during concurrent applies.

---

## Step 3: CI/CD with GitHub Actions & Matrix Workflows

### The DevOps Objective
Automate build, test, container publishing to ECR, and ECS service deployment across environments (`dev` and `staging`) using a matrix workflow or environment dispatch.

### Pipeline Workflow Architecture (`.github/workflows/deploy.yml`)
1. **Triggering Strategy**:
   - Push to `main` branch or pull requests.
2. **Matrix Strategy for Multi-Environment Promotions**:
   ```yaml
   name: Deploy Microservice

   on:
     push:
       branches: [ main, staging ]

   jobs:
     deploy:
       name: Build & Deploy
       runs-on: ubuntu-latest
       strategy:
         matrix:
           include:
             - branch: staging
               environment: staging
               aws_region: us-east-1
             - branch: main
               environment: dev
               aws_region: us-east-1
       if: github.ref_name == matrix.branch

       steps:
         - name: Checkout Code
           uses: actions/checkout@v4

         - name: Configure AWS Credentials (OIDC)
           uses: aws-actions/configure-aws-credentials@v4
           with:
             role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
             aws-region: ${{ matrix.aws_region }}

         - name: Login to Amazon ECR
           id: login-ecr
           uses: aws-actions/amazon-ecr-login@v2

         - name: Build, tag, and push Docker image
           env:
             REGISTRY: ${{ steps.login-ecr.outputs.registry }}
             REPOSITORY: microservice-api-${{ matrix.environment }}
             IMAGE_TAG: ${{ github.sha }}
           run: |
             docker build -t $REGISTRY/$REPOSITORY:$IMAGE_TAG -t $REGISTRY/$REPOSITORY:latest app/
             docker push $REGISTRY/$REPOSITORY:$IMAGE_TAG
             docker push $REGISTRY/$REPOSITORY:latest

         - name: Update ECS Task Definition & Deploy Service
           run: |
             aws ecs update-service \
               --cluster microservice-cluster-${{ matrix.environment }} \
               --service microservice-svc-${{ matrix.environment }} \
               --force-new-deployment
   ```

### Critical Teachings for this Step
- **OIDC (OpenID Connect) vs. Long-lived IAM Keys**:
  Never store permanent `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in GitHub Secrets. Use AWS IAM OIDC federation (`assume-role-with-web-identity`) so GitHub Actions receives short-lived, rotating temporary credentials.
- **Immutable Container Tags**:
  Always tag images with the Git commit SHA (`${{ github.sha }}`) or semantic version, not just `:latest`. If a deployment breaks, an immutable tag allows instant, deterministic rollbacks to the previous known good commit.
- **Graceful Shutdown**:
  Notice the `SIGTERM` handler in `server.js`:
  ```javascript
  process.on('SIGTERM', () => {
    server.close(() => process.exit(0));
  });
  ```
  When ECS updates a service, it sends `SIGTERM` to the old container, waits `stopTimeout` (default 30s), and allows in-flight HTTP requests to complete before sending `SIGKILL`.

---

## Step 4: Verification, Load Testing & Performance Profiling

### The DevOps Objective
Before opening traffic to users, validate high availability, latency percentiles ($p50$, $p95$, $p99$), and autoscaling thresholds under synthetic load.

### Load Test Script Execution (`scripts/loadtest.sh`)
```bash
chmod +x scripts/loadtest.sh
./scripts/loadtest.sh http://<ALB-DNS-NAME>/ 500 20
```

### Metrics to Observe During Load Test
1. **CloudWatch Metrics for ECS**:
   - `CPUUtilization` & `MemoryUtilization`: Are your resource reservations (256 CPU / 512 MB) adequate, or is the container thrashing?
2. **CloudWatch Metrics for Target Group**:
   - `TargetResponseTime`: Server-side request duration.
   - `HTTPCode_Target_2XX_Count` vs `HTTPCode_Target_5XX_Count`.
   - `RequestCountPerTarget`.
3. **Application Auto Scaling (Target Tracking Policy)**:
   - Configure a target tracking policy to scale out when `ECSServiceAverageCPUUtilization` exceeds 70%.
   - During the load test, watch ECS launch task 3 and 4 automatically, then scale in when load ceases.

---

## Step 5: Day-2 Operations, Observability & Cost Optimization

### Critical Teachings for this Step
1. **Fargate Spot**:
   - In non-production or burstable workloads, use Fargate Spot to achieve up to 70% cost savings compared to standard Fargate on-demand pricing.
2. **Centralized Logging**:
   - Using the `awslogs` log driver, stdout and stderr from Node.js stream automatically into Amazon CloudWatch Logs.
   - In production, set up CloudWatch Metric Filters for `"Error"` or `"UnhandledPromiseRejection"` to trigger SNS alarms to PagerDuty or Slack.
3. **Health Check Grace Period**:
   - When deploying new tasks, set `health_check_grace_period_seconds = 60` on the ECS service. This prevents the ALB from prematurely marking a slowly booting container as unhealthy and killing it in an infinite crash-loop.

---

## Summary Checklist to Reach Completion

- [x] Application code written with `/` and `/health` endpoints.
- [x] Multi-stage, non-root `Dockerfile` created and verified.
- [x] Functional bash load-testing script with $p50$, $p95$, $p99$ calculation.
- [ ] Terraform files for VPC, ALB, and ECS Fargate.
- [ ] GitHub Actions CI/CD matrix pipeline.
- [ ] CloudWatch alarms and Target Tracking Auto-scaling policy configured.

