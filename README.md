# Strapi CMS Deployment on AWS ECS with Blue–Green Strategy

## Overview

This project demonstrates the end-to-end deployment of **Strapi CMS** on AWS using modern DevOps practices. The application is containerized with Docker, deployed on **Amazon ECS (Fargate)**, and released using a **Blue–Green deployment strategy** powered by **AWS CodeDeploy** and an **Application Load Balancer**. Infrastructure provisioning and configuration are fully managed using **Terraform**, while CI/CD automation is handled through **GitHub Actions**.

The project was implemented as part of a **DevOps internship**, focusing on real-world deployment patterns, zero-downtime releases, and infrastructure automation.

---

## Architecture

**High-level flow:**

1. Strapi CMS is developed and tested locally.
2. The application is containerized using Docker.
3. Docker images are pushed to Amazon ECR.
4. Infrastructure is provisioned using Terraform:

   * ECS Cluster (Fargate)
   * Application Load Balancer
   * CodeDeploy (Blue–Green)
   * RDS PostgreSQL
   * IAM roles and security groups
5. GitHub Actions triggers:

   * Terraform apply
   * ECS task definition revision
   * CodeDeploy Blue–Green deployment
6. Traffic is shifted gradually using a canary strategy.
7. Old tasks are terminated after successful deployment.

---

## Tech Stack

**Application**

* Strapi CMS
* Node.js

**Containerization**

* Docker
* Docker Compose (local development)

**AWS Services**

* Amazon ECS (Fargate)
* Amazon ECR
* AWS CodeDeploy (ECS Blue–Green)
* Application Load Balancer
* Amazon RDS (PostgreSQL)
* IAM
* CloudWatch

**Infrastructure as Code**

* Terraform

**CI/CD**

* GitHub Actions

---

## Deployment Strategy

### Blue–Green Deployment (ECS)

* Two target groups are configured: **Blue** and **Green**
* Production traffic is routed via an **Application Load Balancer**
* Each deployment:

  * Registers a new ECS task definition
  * Deploys the new version to the inactive target group
  * Gradually shifts traffic using **canary deployment (10% for 5 minutes)**
  * Automatically rolls back on failure
  * Terminates the old version after success

This approach ensures **zero downtime** and safe application releases.

---

## Database Configuration

* Amazon RDS (PostgreSQL) is used as the backend database
* The database is external to ECS tasks to ensure:

  * Data persistence across deployments
  * Safe Blue–Green releases
* Database credentials and secrets are injected via ECS environment variables

---

## Repository Structure

```
.
├── .github/workflows/
│   └── deploy.yml              # GitHub Actions CI/CD pipeline
├── terraform/
│   ├── main.tf                 # Infrastructure definition
│   ├── variables.tf            # Input variables
│   └── outputs.tf              # Outputs (if any)
├── appspec.yaml                # CodeDeploy AppSpec for ECS
├── Dockerfile                  # Strapi CMS Docker image
├── docker-compose.yml          # Local development setup
└── README.md
```

---

## CI/CD Pipeline (GitHub Actions)

The pipeline performs the following steps:

1. Checkout source code
2. Configure AWS credentials
3. Initialize and apply Terraform
4. Register a new ECS task definition with updated image tag
5. Trigger AWS CodeDeploy Blue–Green deployment using AppSpec
6. Monitor deployment status

Deployments are triggered manually using `workflow_dispatch`.

---

## Monitoring & Observability

* CloudWatch Logs for ECS task logs
* CloudWatch Dashboard tracking:

  * ECS CPU utilization
  * ECS Memory utilization

This provides visibility into application health and resource usage.

---

## Security Considerations

* IAM roles follow least-privilege principles
* ECS tasks use a dedicated execution role
* Database access is restricted via security groups
* Secrets are injected via GitHub Secrets and Terraform variables

---

## How to Deploy (High Level)

1. Push application changes to GitHub
2. Build and tag Docker image
3. Push image to Amazon ECR
4. Trigger GitHub Actions workflow
5. CodeDeploy handles Blue–Green deployment automatically

---

## Key Learnings

* Implementing real-world Blue–Green deployments on ECS
* Managing containerized workloads using Fargate
* Automating infrastructure with Terraform
* Integrating CI/CD pipelines with AWS services
* Handling stateful services (RDS) with stateless containers

---

## Future Improvements

* Move RDS to private subnets
* Add HTTPS using ACM
* Implement auto-scaling policies for ECS
* Add Prometheus/Grafana for advanced monitoring
* Introduce approval-based deployment stages

---

