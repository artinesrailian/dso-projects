## High-Level Diagram (HLD)

This High-Level Diagram (HLD) is the whole system on one page, organised by tier rather than by AWS
service — start with the three coloured tiers, then trace one request left to right. Presentation
(orange) sits entirely at the edge; application (blue) runs on Amazon EKS behind one load balancer;
data (green) is reached only through Amazon RDS Proxy. Delivery (purple) builds and signs images in
a separate account, then reaches the cluster only through Argo CD's pull-based sync.

```mermaid
flowchart LR
  user["End users<br/>browser"]
  dns["Amazon Route 53"]
  cf["Amazon CloudFront<br/>AWS WAF + Shield"]
  spa["Amazon S3<br/>React SPA bundle"]

  subgraph shared["AWS account innovate-shared-services"]
    direction TB
    ci["GitHub Actions CI<br/>OIDC, build, scan, sign"]
    ecr["Amazon ECR<br/>innovate/api, innovate/worker"]
    gitops["GitOps repository<br/>Kustomize overlays"]
  end

  subgraph prod["AWS account innovate-prod"]
    direction TB
    subgraph vpc["VPC innovate-prod-vpc-use1 10.30.0.0/16, 3 AZs"]
      direction TB
      alb["Application Load Balancer<br/>public subnets"]
      subgraph eks["Amazon EKS innovate-prod-eks-use1"]
        direction TB
        argocd["Argo CD"]
        api["Flask API pods<br/>ns innovate-api"]
        worker["Worker pods<br/>ns innovate-jobs"]
      end
      proxy["Amazon RDS Proxy"]
      db[("Aurora PostgreSQL<br/>writer + reader, separate AZs")]
    end
  end

  dr["DR region us-west-2<br/>Aurora Global Database<br/>pilot light"]

  user --> dns
  dns --> cf
  cf -->|"static assets"| spa
  cf -->|"/api/*"| alb
  alb --> api
  api --> proxy
  worker --> proxy
  proxy --> db
  db -.->|"replication under 1s"| dr
  ci -->|"push signed image"| ecr
  ci -->|"commit image digest"| gitops
  gitops -.->|"pull-based sync"| argocd
  ecr -.->|"pull by digest"| api

  classDef edge fill:#FFF3E0,stroke:#E65100,stroke-width:1px,color:#111
  classDef compute fill:#E3F2FD,stroke:#1565C0,stroke-width:1px,color:#111
  classDef data fill:#E8F5E9,stroke:#2E7D32,stroke-width:1px,color:#111
  classDef ops fill:#EDE7F6,stroke:#4527A0,stroke-width:1px,color:#111
  classDef external fill:#ECEFF1,stroke:#455A64,stroke-width:1px,color:#111
  class user,dns external
  class cf,spa edge
  class alb,api,worker,argocd compute
  class proxy,db,dr data
  class ci,ecr,gitops ops
```

**Legend**

| Element | Meaning |
|---|---|
| Orange (`edge`) | Presentation tier — CloudFront, AWS Web Application Firewall (WAF), the S3 origin |
| Blue (`compute`) | Application tier — the load balancer, Argo CD, and the Flask API / worker pods on EKS |
| Green (`data`) | Data tier — RDS Proxy, Aurora PostgreSQL, and the disaster recovery (DR) region |
| Purple (`ops`) | Delivery pipeline — continuous integration (CI), ECR, and the GitOps repository |
| Grey (`external`) | Outside the system — end users and DNS resolution |

> **Note.** Non-production accounts, virtual private cloud (VPC) endpoints, EKS add-ons, and subnet
> detail are omitted here for legibility; see diagrams 2 and 3.
