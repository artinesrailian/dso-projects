## Account and Organizational Unit Topology

Start at the root and follow the organizational units (OUs), not the account list — that is the
point of this diagram: service control policies (SCPs) attach to the OU, so moving an account between OUs
is how its guardrails change. Dashed edges show identity sessions and log or finding delivery, never
a network path; no account can reach another over the network. Two accounts, marked (future), arrive
as the team and its network topology grow.

```mermaid
flowchart TB
  root["AWS Organization<br/>innovate-inc"]
  mgmt["innovate-management<br/>Control Tower + IAM Identity Center"]

  subgraph sec_ou["OU: Security"]
    direction TB
    log["innovate-log-archive"]
    sectool["innovate-security-tooling"]
  end

  subgraph infra_ou["OU: Infrastructure"]
    direction TB
    shared["innovate-shared-services"]
    network["innovate-network<br/>(future)"]
  end

  subgraph workloads_ou["OU: Workloads"]
    direction TB
    subgraph nonprod_ou["OU: NonProd"]
      direction TB
      dev["innovate-dev"]
      staging["innovate-staging"]
    end
    subgraph prodou["OU: Prod"]
      direction TB
      prod["innovate-prod"]
    end
  end

  subgraph sandbox_ou["OU: Sandbox"]
    direction TB
    sandbox["innovate-sandbox-*<br/>(future)"]
  end

  suspended["OU: Suspended<br/>decommissioned accounts, deny-all"]

  root --> mgmt
  root --> sec_ou
  root --> infra_ou
  root --> workloads_ou
  root --> sandbox_ou
  root --> suspended

  mgmt -.->|"SSO session"| dev
  mgmt -.->|"SSO session"| staging
  mgmt -.->|"SSO session"| prod
  mgmt -.->|"SSO session"| shared

  dev -.->|"logs, findings"| log
  dev -.->|"findings"| sectool
  staging -.->|"logs, findings"| log
  staging -.->|"findings"| sectool
  prod -.->|"logs, findings"| log
  prod -.->|"findings"| sectool
  shared -.->|"logs, findings"| log
  shared -.->|"findings"| sectool

  classDef security fill:#FCE4EC,stroke:#AD1457,stroke-width:1px,color:#111
  classDef ops fill:#EDE7F6,stroke:#4527A0,stroke-width:1px,color:#111
  classDef compute fill:#E3F2FD,stroke:#1565C0,stroke-width:1px,color:#111
  classDef external fill:#ECEFF1,stroke:#455A64,stroke-width:1px,color:#111
  class root,suspended external
  class mgmt,log,sectool security
  class shared,network ops
  class dev,staging,prod,sandbox compute
```

**Legend**

| Element | Meaning |
|---|---|
| Pink (`security`) | Management and security accounts — govern and audit, no workloads |
| Purple (`ops`) | Infrastructure accounts — shared services, later the network account |
| Blue (`compute`) | Workload accounts — dev, staging, prod, future per-engineer sandboxes |
| Grey (`external`) | The organization root and the Suspended OU exit path |
| Dashed edge | An identity session or log/finding delivery, not a network path |

> **Note.** Permission sets and the six SCP guardrail families are omitted; see §1 Cloud Environment
> Structure for the full list.
