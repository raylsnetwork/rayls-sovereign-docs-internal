# Governance API - CI/CD Pipeline (Go PR Standard)

This document describes the CI/CD pipeline for the rayls-sovereign-pnh-governance repository, which serves as the standard for Go pull requests in the Rayls ecosystem.

## Pipeline Flow Diagram

```mermaid
flowchart TB
    subgraph trigger["PR Trigger"]
        PR["Pull Request to version-* branch"]
    end

    PR --> stage1
    PR --> stage2
    PR --> stage3

    subgraph stage1["Stage 1: Unit Tests"]
        direction TB
        S1_setup["Go Setup (v1.24.11)"]
        S1_tools["Install go-junit-report"]
        S1_test["Run Unit Tests<br/>• Coverage profiling<br/>• Race detection"]
        S1_report["Generate Coverage<br/>Summary & HTML"]
        S1_publish["Publish Artifacts<br/>• test-results.xml<br/>• coverage.html<br/>• coverage.out"]

        S1_setup --> S1_tools --> S1_test --> S1_report --> S1_publish
    end

    subgraph stage2["Stage 2: Formatters & Linters"]
        direction TB
        S2_setup["Go Setup (v1.24.11)"]
        S2_lint_install["Install golangci-lint v2.7.1"]
        S2_cache["Restore Lint Cache"]
        S2_fmt["Run Formatters<br/>(golangci-lint fmt)"]
        S2_check["Check for<br/>Formatting Issues"]
        S2_lint["Run Linters<br/>(golangci-lint run)"]

        S2_setup --> S2_lint_install --> S2_cache --> S2_fmt --> S2_check --> S2_lint
    end

    subgraph stage3["Stage 3: Docker Build & Security Scan"]
        direction TB
        subgraph jobs["Parallel Jobs"]
            direction LR
            S3_api["Build & Scan<br/>API<br/>(Trivy)"]
            S3_flagger["Build & Scan<br/>Flagger<br/>(Trivy)"]
            S3_listener["Build & Scan<br/>Listener<br/>(Trivy)"]
        end
    end

    subgraph stage4["Stage 4: SonarCloud Analysis"]
        direction TB
        S4_checkout["Checkout<br/>(full history)"]
        S4_download["Download<br/>coverage.out"]
        S4_prepare["Prepare SonarCloud"]
        S4_run["Run SonarCloud<br/>• Code Quality<br/>• Coverage Report<br/>• PR Decoration"]

        S4_checkout --> S4_download --> S4_prepare --> S4_run
    end

    stage1 -->|"sonar-coverage<br/>artifact"| stage4

    stage1 --> gate
    stage2 --> gate
    stage3 --> gate
    stage4 --> gate

    subgraph gate["PR Gate"]
        direction TB
        G1["✓ All Tests Pass"]
        G2["✓ No Lint/Format Errors"]
        G3["✓ No Critical Vulnerabilities"]
        G4["✓ SonarCloud Quality Gate"]
    end

    gate --> merge["Ready to Merge"]
```

## Stage Dependencies

```mermaid
flowchart LR
    subgraph parallel["Parallel Execution"]
        S1["Stage 1<br/>Unit Tests"]
        S2["Stage 2<br/>Formatters & Linters"]
        S3["Stage 3<br/>Docker Build"]
    end

    S1 -->|depends on| S4["Stage 4<br/>SonarCloud"]
```

## Stage Details

### Stage 1: Unit Tests
**Runs in parallel with Stages 2 & 3**

| Step | Description |
|------|-------------|
| Go Setup | Installs Go 1.24.11 with module caching |
| Install Tools | go-junit-report v2.1.0 |
| Run Tests | `go test -v -race -coverprofile=coverage.out -covermode=atomic` |
| Coverage Report | Generates summary and HTML report |
| Publish | JUnit results, HTML report, coverage.out for SonarCloud |

**Packages Tested:**

- `./cmd/listener/core/...`
- `./cmd/flagger/core/...`

**Artifacts Produced:**

| Artifact | Format | Purpose |
|----------|--------|---------|
| `test-results.xml` | JUnit | Azure DevOps test reporting |
| `coverage.html` | HTML | Human-readable coverage report |
| `coverage.out` | Go Cover | SonarCloud analysis input |

### Stage 2: Formatters & Linters
**Runs in parallel with Stages 1 & 3**

| Step | Description |
|------|-------------|
| Go Setup | Installs Go 1.24.11 with module caching |
| Install Lint | golangci-lint v2.7.1 |
| Cache | Restores lint cache for faster analysis |
| Formatters | `golangci-lint fmt ./...` |
| Check Changes | Fails if formatting changes detected |
| Linters | `golangci-lint run ./...` |

### Stage 3: Docker Build & Security Scan
**Runs in parallel with Stages 1 & 2**

Three parallel jobs build and scan Docker images:

| Job | Dockerfile | Security Scanner |
|-----|------------|------------------|
| API | `Dockerfile.api` | Trivy v0.68.2 |
| Flagger | `Dockerfile.flagger` | Trivy v0.68.2 |
| Listener | `Dockerfile.listener` | Trivy v0.68.2 |

### Stage 4: SonarCloud Analysis
**Depends on Stage 1 (Unit Tests)**

| Step | Description |
|------|-------------|
| Checkout | Full git history (`fetchDepth: 0`) for blame info |
| Download Artifact | Gets `coverage.out` from Stage 1 |
| Prepare | Configures SonarCloud scanner |
| Analyze | Runs Go-specific SonarCloud analysis |

**SonarCloud Features:**

- Code quality analysis (bugs, vulnerabilities, code smells)
- Code coverage visualization
- PR decoration with inline comments
- Quality gate enforcement

## Tool Versions

```yaml
GO_VERSION: '1.24.11'
GO_JUNIT_REPORT_VERSION: 'v2.1.0'
GOLANGCI_LINT_VERSION: 'v2.7.1'
TRIVY_VERSION: '0.68.2'
VM_IMAGE: 'ubuntu-22.04'
```

## Pipeline Triggers

| Trigger Type | Configuration |
|--------------|---------------|
| PR Trigger | `version-*` branches |
| CI Trigger | Disabled |
