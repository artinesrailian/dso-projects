# The Assignment (verbatim)

> The original file as supplied is [`../docs/assessment.md`](../docs/assessment.md). It is
> reproduced below verbatim so that agents need only one read. **`docs/assessment.md` is the
> authority** — if the two ever diverge, that file wins, and the divergence is a bug to report in
> `STATE.md`.
>
> This is the **only** source of requirements. If anything in a phase document appears to contradict
> it, it wins — stop and report the contradiction rather than guessing.

---

## Architecture Design for "Innovate Inc."

### Description

One of our clients is a small startup called "Innovate Inc." They are developing a web application
(details below) and are looking to deploy it on one of the two major cloud providers (AWS or GCP).
They have limited experience with cloud infrastructure and are seeking your expertise to design a
robust, scalable, secure, and cost-effective solution. They are particularly interested in
leveraging managed Kubernetes and following best practices.

### Application Details

- **Type:** Web application with a REST API backend and a single-page application (SPA) frontend.
- **Technology Stack:** Backend: Python/Flask, Frontend: React, Database: PostgreSQL.
- **Traffic:** The expected initial load is low (a few hundred users per day), but they anticipate
  rapid growth to potentially millions of users.
- **Data:** Sensitive user data is handled, requiring strong security measures.
- **Deployment Frequency:** Aiming for continuous integration and continuous delivery (CI/CD).

### Assignment

Create an architectural design document for Innovate Inc.'s Cloud infrastructure. The document
should address the following key areas:

1. **Cloud Environment Structure**
   - Recommend the optimal number and purpose of AWS accounts/GCP Projects for Innovate Inc. and
     justify your choice. Consider best practices for isolation, billing, and management.

2. **Network Design**
   - Design the Virtual Private Cloud (VPC) architecture.
   - Describe how you will secure the network.

3. **Compute Platform**
   - Detail how you will leverage Kubernetes Service to deploy and manage the application.
   - Describe your approach to node groups, scaling, and resource allocation within the cluster.
   - Explain your strategy for containerization, including image building, registry, and deployment
     processes.

4. **Database**
   - Recommend the appropriate service for the PostgreSQL database and justify your choice.
   - Outline your approach to database backups, high availability, and disaster recovery.

### Deliverables

> Please place your architecture assignment under the `architecture/` folder in the repository root.
> This folder should include a README architecture document with at least one HDL (High-Level
> Diagram) to illustrate the architecture.

---

## Decoding the deliverable statement

| Phrase in the brief | How this plan satisfies it |
|---|---|
| "under the `architecture/` folder in the repository root" | Everything produced lives directly under `architecture/`. No subfolder between the assignment and the folder named in the brief. |
| "This folder should include a README architecture document" | **`architecture/README.md`** — one self-contained document, assembled in Phase 11. |
| "at least one HDL (High-Level Diagram)" | Phase 10 produces **five** Mermaid diagrams; the primary HLD is embedded near the top of the README, organised by the three tiers. "HDL" is a typo for HLD in the original — write **HLD**. |

`architecture/` is owned entirely by this assignment. The Terraform / EKS + Karpenter assignment
lives under `terraform/` and is off-limits (`AGENT-PROTOCOL.md` §1).

---

## Requirements register

Every phase must be traceable to one of these. Phase 00 seeds this table into the draft and Phase 12
verifies that every row is satisfied by a real section of the final README.

Requirements **R1–R18** come from the assignment's explicit wording. **R19–R25** come from its
description paragraph — they are not numbered in the brief, but a reviewer checks them, and the
client named several of them directly ("robust, scalable, secure, and cost-effective", "best
practices", "limited experience"). **R26–R28** are this engagement's additional standards.

| ID | Requirement | Source | Owning phase(s) |
|---|---|---|---|
| **R1** | Recommend the optimal **number and purpose** of AWS accounts | Area 1 | 01 |
| **R2** | **Justify** the account choice against isolation, billing, and management | Area 1 | 01 |
| **R3** | Design the **VPC architecture** | Area 2 | 02 |
| **R4** | Describe how the **network is secured** | Area 2 | 02, 06 |
| **R5** | Detail how **managed Kubernetes** deploys and manages the application | Area 3 | 03 |
| **R6** | Approach to **node groups** | Area 3 | 03 |
| **R7** | Approach to **scaling** | Area 3 | 03, 07 |
| **R8** | Approach to **resource allocation within the cluster** | Area 3 | 03 |
| **R9** | Containerization strategy — **image building** | Area 3 | 04 |
| **R10** | Containerization strategy — **registry** | Area 3 | 04 |
| **R11** | Containerization strategy — **deployment processes** | Area 3 | 04 |
| **R12** | Recommend the **PostgreSQL service** and **justify** it | Area 4 | 05 |
| **R13** | Database **backups** | Area 4 | 05 |
| **R14** | Database **high availability** | Area 4 | 05 |
| **R15** | Database **disaster recovery** (distinct from HA) | Area 4 | 05 |
| **R16** | Deliverable lives under `architecture/` | Deliverables | 00, 11, 12 |
| **R17** | A README architecture document | Deliverables | 11 |
| **R18** | At least one High-Level Diagram | Deliverables | 10, 11 |
| **R19** | Solution is **robust** | Description | 03, 05, 07 |
| **R20** | Solution is **scalable** — hundreds → millions of users | Description | 03, 05, 09 |
| **R21** | Solution is **secure** — sensitive user data | Description | 02, 04, 06 |
| **R22** | Solution is **cost-effective** | Description | 08 |
| **R23** | **CI/CD** is supported | Description | 04 |
| **R24** | Readable by a client with **limited cloud experience** | Description | 11, 12 |
| **R25** | Follows **best practices** | Description | all, 09 |
| **R26** | **Every decision is justified**, with alternatives and consequences, in language the client can follow | Engagement standard | all, 11 |
| **R27** | Design aligns to the **AWS Well-Architected Framework**, all six pillars | Engagement standard | 09, all |
| **R28** | Design is presented as a **three-tier architecture** (presentation, application, data) | Engagement standard | 00, 02, 03, 10 |
