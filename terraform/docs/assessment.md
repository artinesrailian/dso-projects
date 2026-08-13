# Technical Task

## Automate AWS EKS cluster setup with Karpenter, while utilizing Graviton and Spot instances

### Description

You've joined a new and growing startup.
The company wants to build its initial Kubernetes infrastructure on AWS. The team wants to leverage the latest autoscaling capabilities by Karpenter, as well as utilize Graviton and Spot instances for better price/performance.

**They have asked you if you can help create the following:**

- Terraform code that deploys an EKS cluster (whatever latest version is currently available) into a new dedicated VPC
- The terraform code should also deploy Karpenter with node pool(s) that can deploy both x86 and arm64 instances
- Include a short readme that explains how to use the Terraform repo and that also demonstrates how an end-user (a developer from the company) can run a pod/deployment on x86 or Graviton instance inside the cluster.

### Deliverable

Please place your technical assignment solution under the terraform/ folder in the repository root.
This folder should include all the necessary infrastructure as code needed in order to recreate a working POC of the above architecture.
