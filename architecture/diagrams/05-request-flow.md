## Authenticated Request Flow

Start at the top and follow one authenticated request across all three tiers, past the AWS Web
Application Firewall (WAF) evaluation, then compare it to the second, shorter path below for a
cached static asset — proof the presentation tier answers without ever waking the application tier.
Every hop after CloudFront is still separately encrypted, with its own TLS termination point named
in a note.

```mermaid
sequenceDiagram
  participant browser as "Browser"
  participant cf as "Amazon CloudFront"
  participant waf as "AWS WAF"
  participant s3 as "Amazon S3 origin"
  participant alb as "Application Load Balancer"
  participant pod as "Flask API pod"
  participant proxy as "Amazon RDS Proxy"
  participant aurora as "Aurora PostgreSQL writer"

  browser->>cf: GET /api/orders, TLS 1.2+
  Note over browser,cf: TLS terminates at the CloudFront edge
  cf->>waf: evaluate against managed rule groups
  alt request blocked
    waf-->>browser: 403 Forbidden
  else request allowed
    waf-->>cf: allow
    cf->>alb: forward /api/*, re-encrypted
    Note over cf,alb: TLS re-terminated at the ALB with an ACM certificate
    alb->>pod: HTTPS to pod ENI, IP target mode
    Note over alb,pod: TLS terminated at the pod via a cert-manager certificate
    pod->>proxy: query, sslmode=verify-full
    proxy->>aurora: hold connection, forward query
    aurora-->>proxy: result set
    proxy-->>pod: result set
    pod-->>alb: 200 OK JSON
    alb-->>cf: 200 OK
    cf-->>browser: 200 OK JSON
  end

  Note over browser,s3: Static asset — cache-hit alternative path
  browser->>cf: GET /static/app.js
  alt cached at the edge
    cf-->>browser: 200 OK, served from edge cache
  else cache miss
    cf->>s3: fetch via origin access control
    s3-->>cf: asset
    cf-->>browser: 200 OK, now cached at the edge
  end
```

**Legend**

| Element | Meaning |
|---|---|
| Solid arrow | A request — a synchronous call to the next hop |
| Dashed arrow | A response — the answer flowing back |
| `alt` / `else` block | A branch — the WAF verdict, or a cache hit versus a cache miss |
| `Note` | Where TLS terminates or re-terminates along the path |

> **Note.** Aurora's failover to the reader, and RDS Proxy's connection retention during it, are
> described in §4 Database and not repeated here.
