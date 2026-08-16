## Production Network Topology

Start with one Availability Zone (AZ) column, then see it repeat three times — that repetition is
the design. The four subnet tiers map one-to-one to the three application tiers: public for the edge
of the virtual private cloud (VPC), private-app for EKS nodes, private-data for Aurora,
private-endpoints for AWS service traffic kept off the NAT Gateway. Every Classless Inter-Domain
Routing (CIDR) block shown here matches the network design section exactly.

```mermaid
flowchart TB
  internet["Internet"]
  igw["Internet Gateway"]
  alb["Application Load Balancer<br/>spans all 3 public subnets"]

  subgraph vpc_prod["VPC innovate-prod-vpc-use1 10.30.0.0/16"]
    direction TB

    subgraph az_a["Availability Zone us-east-1a"]
      direction TB
      pub_a["Public 10.30.0.0/24<br/>ALB ENI + NAT Gateway"]
      app_a["Private App 10.30.16.0/20<br/>EKS worker nodes"]
      data_a["Private Data 10.30.64.0/24<br/>Aurora writer"]
      endpoint_a["Private Endpoints 10.30.68.0/24<br/>Interface VPC endpoints"]
    end

    subgraph az_b["Availability Zone us-east-1b"]
      direction TB
      pub_b["Public 10.30.1.0/24<br/>ALB ENI + NAT Gateway"]
      app_b["Private App 10.30.32.0/20<br/>EKS worker nodes"]
      data_b["Private Data 10.30.65.0/24<br/>Aurora reader"]
      endpoint_b["Private Endpoints 10.30.69.0/24<br/>Interface VPC endpoints"]
    end

    subgraph az_c["Availability Zone us-east-1c"]
      direction TB
      pub_c["Public 10.30.2.0/24<br/>ALB ENI + NAT Gateway"]
      app_c["Private App 10.30.48.0/20<br/>EKS worker nodes"]
      data_c["Private Data 10.30.66.0/24<br/>storage copy, no reader"]
      endpoint_c["Private Endpoints 10.30.70.0/24<br/>Interface VPC endpoints"]
    end
  end

  internet --> igw
  igw --> pub_a
  igw --> pub_b
  igw --> pub_c
  pub_a --> alb
  pub_b --> alb
  pub_c --> alb
  alb --> app_a
  alb --> app_b
  alb --> app_c
  app_a -->|"per-AZ route, 0.0.0.0/0"| pub_a
  app_b -->|"per-AZ route, 0.0.0.0/0"| pub_b
  app_c -->|"per-AZ route, 0.0.0.0/0"| pub_c
  app_a -->|"5432"| data_a
  app_b -->|"5432"| data_b
  app_c -->|"5432"| data_c
  data_a -.->|"sync replication"| data_b
  app_a -.-> endpoint_a
  app_b -.-> endpoint_b
  app_c -.-> endpoint_c

  classDef edge fill:#FFF3E0,stroke:#E65100,stroke-width:1px,color:#111
  classDef compute fill:#E3F2FD,stroke:#1565C0,stroke-width:1px,color:#111
  classDef data fill:#E8F5E9,stroke:#2E7D32,stroke-width:1px,color:#111
  classDef external fill:#ECEFF1,stroke:#455A64,stroke-width:1px,color:#111
  class internet,igw external
  class pub_a,pub_b,pub_c,alb edge
  class app_a,app_b,app_c,endpoint_a,endpoint_b,endpoint_c compute
  class data_a,data_b,data_c data
```

**Legend**

| Element | Meaning |
|---|---|
| Orange (`edge`) | Public subnet — the Application Load Balancer (ALB) and each AZ's NAT Gateway |
| Blue (`compute`) | Private App subnet — EKS worker nodes; also the interface VPC endpoints |
| Green (`data`) | Private Data subnet — Aurora writer, reader, and the third storage copy |
| Grey (`external`) | Outside the VPC — the internet and the Internet Gateway |

> **Note.** The pod CIDR (`100.66.0.0/16`), the reserved `/17` block, and security-group rules are
> omitted; see §2 Network Design for the full model.
