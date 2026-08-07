<div align="center">

# Kubernetes Cluster Metrics & Cost Explorer


![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326CE5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)


</div>

## Overview
A dashboard that tracks per-namespace resource usage and estimated cost across a Kubernetes cluster in real time. It snapshots pod resource requests on an interval, prices them against real AWS EC2 on-demand rates for whichever node they're running on, stores the history in Postgres, and exports hourly cost reports to S3.

![Application](docs/application.png)

## Architecture
### AWS infrastructure
- VPC spanning 2 AZs (eu-central-1a/b), each with a public + private subnet
- EKS cluster and node group in the private subnets; RDS Postgres alongside them, Multi-AZ (primary + synchronous standby)
- One NAT Gateway + EIP per AZ in the public subnets, for private subnet egress
- Frontend reachable via a Network Load Balancer in the public subnets, TLS-terminated with an ACM certificate issued for a Route53-hosted domain
- IAM OIDC provider for IRSA, plus roles scoping S3 writes, RDS IAM connect, and Pricing API reads to the backend pod only
- ECR repos for the backend/frontend images, S3 bucket for the hourly cost reports

![Infrastructure diagram](docs/infrastructure.svg)

### Kubernetes cluster
- Frontend and backend each in their own namespace, as a Deployment + Service + HPA (frontend: avg CPU 20%, backend: avg CPU 50%)
- Frontend Service is type LoadBalancer (the entry point from the internet); backend Service is ClusterIP, only reachable from inside the cluster
- Backend pods run under a dedicated ServiceAccount, IAM-role-annotated for IRSA, with a read-only ClusterRole to read node/pod metrics for the cost calculations
- `metrics-server` in kube-system backs both the HPA and that metrics API
- A one-shot `rds-iam-bootstrap` Job grants the backend's IAM-mapped DB role `rds_iam`, since RDS Postgres doesn't allow IAM auth for the master user

![Cluster diagram](docs/cluster.svg)


## Key Design Decisions

| Section | Explanation |
|---|---|
| **High Availability** | RDS Multi-AZ standby replica for automatic failover<br>One NAT gateway + EIP per AZ, so private subnet egress survives an AZ outage<br>EKS node group spans both AZs (2-4 nodes), so losing one AZ doesn't take down the cluster |
| **Security** | No static AWS credentials — IRSA for S3, RDS, and Pricing API<br>Dedicated ServiceAccount + read-only ClusterRole<br>Private subnets, no public IPs<br>TLS via a Route53-hosted domain + DNS-validated ACM certificate on the frontend NLB |
| **Elasticity** | HPA on frontend + backend: 3–30 pods, CPU-based<br>EKS node group scales 2-4 nodes on CPU via target tracking |
| **Cost-Efficiency** | RDS on db.t4g.micro — cheapest general-purpose Graviton class<br>gp3 storage instead of gp2<br>No RDS backups (acceptable trade-off for a demo project)<br>Node and pod autoscaling avoid paying for idle capacity |

## How to Run

**Prerequisites:** Docker, kubectl, [skaffold](https://skaffold.dev/), Terraform, AWS CLI (configured with credentials).

### Local (k3d)
1. Point kubectl at a local k3d cluster.
2. Copy `.env.example` to `.env` and fill in Postgres credentials.
3. `skaffold dev`

### AWS (EKS)
1. Fill in `.env` with Postgres credentials, `TF_VAR_domain_name`, and `TF_VAR_app_hostname` (a domain you own, registered in Route53).
2. `./scripts/deploy-all.sh` — provisions the infra with Terraform, then builds/pushes images to ECR and deploys via Skaffold.
3. `./scripts/update-dns.sh` — points the domain at the frontend's load balancer once it's up.
4. Visit `https://<app_hostname>`.

To tear everything down: `./scripts/destroy-all.sh`.
