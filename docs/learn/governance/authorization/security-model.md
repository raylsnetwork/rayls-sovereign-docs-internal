# Security Model

The authorization system implements defense-in-depth with multiple independent security layers. Each layer provides protection against specific attack vectors, and together they create a robust security posture for the entire Rayls network.

---

## Threat Model

### Threat Landscape

```mermaid
graph TD
    subgraph "Threats"
        T1["T1: Compromised<br/>ADMIN key"]
        T2["T2: Malicious function<br/>remapping"]
        T3["T3: Manager contract<br/>implementation bug"]
        T4["T4: Authority<br/>misconfiguration"]
        T5["T5: Scheduled operation<br/>abuse"]
        T6["T6: Per-target close<br/>bypass"]
        T7["T7: Role confusion<br/>between chains"]
    end

    subgraph "Mitigations"
        M1["Multisig + Grant delays<br/>+ Guardian cancel"]
        M2["Admin delay + Event monitoring<br/>+ Guardian cancel"]
        M3["UUPS upgradeable<br/>+ Comprehensive tests + Audit"]
        M4["Fail-closed defaults<br/>+ Idempotent deploy scripts"]
        M5["Expiration window<br/>+ Caller-bound operationId"]
        M6["Close check is first<br/>in canCall path"]
        M7["Independent manager<br/>per chain"]
    end

    T1 --> M1
    T2 --> M2
    T3 --> M3
    T4 --> M4
    T5 --> M5
    T6 --> M6
    T7 --> M7

    style T1 fill:#e74c3c,color:#fff
    style T2 fill:#e74c3c,color:#fff
    style T3 fill:#e67e22,color:#fff
    style T4 fill:#f1c40f,color:#000
    style T5 fill:#f1c40f,color:#000
    style T6 fill:#f1c40f,color:#000
    style T7 fill:#f1c40f,color:#000
```

### Threat-Mitigation Matrix

| # | Threat | Severity | Likelihood | Mitigations | Residual Risk |
|---|---|---|---|---|---|
| T1 | Compromised ADMIN key grants attacker all roles | Critical | Medium | Multisig for ADMIN, grant delays prevent instant escalation, guardian can cancel pending operations | Low (with multisig) |
| T2 | Malicious function mapping (e.g., map freezeToken to PUBLIC) | Critical | Low | Admin delay on addFunctionAllowedRoles, event monitoring detects remapping, guardian can cancel config changes | Low |
| T3 | Manager implementation bug (canCall bypass, storage corruption) | High | Low | UUPS upgrade path for fix-forward, comprehensive Forge test coverage, professional audit recommended | Low (post-audit) |
| T4 | Authority misconfiguration (target contract points to wrong manager) | High | Medium | Fail-closed default (canCall returns false for unknown targets), deploy script validation | Low |
| T5 | Scheduled operation executed by different caller or replayed | Medium | Low | operationId includes caller address, expiration window (1 week default), schedule deletion after execution prevents replay | Very Low |
| T6 | Per-target close bypassed via alternative code path | High | Very Low | Close check is the first check in canCall, no alternative path exists in the modifier | Very Low |
| T7 | Role confusion between Private Network Hub and Privacy Node roles | Medium | Low | Independent manager instance per chain, no cross-chain role references, role IDs are local | Very Low |
| T8 | Over-permission from role sharing | Low | Low | `addFunctionAllowedRoles()` maps multiple independent roles per function. Each integration gets its own role with minimal blast radius. Two-level bitmap provides O(1) checks. | Very Low |

---

## Defense-in-Depth

### Security Layers

```mermaid
graph TD
    subgraph "Layer 1: Access Control"
        L1A["restricted modifier<br/>on all protected functions"]
        L1B["canCall() check<br/>role to target and selector mapping"]
        L1C["Fail-closed default<br/>unmapped selectors require ADMIN"]
    end

    subgraph "Layer 2: Temporal Controls"
        L2A["Execution delays<br/>for sensitive operations"]
        L2B["Grant delays<br/>prevent instant privilege escalation"]
        L2C["Operation expiration<br/>(1 week default window)"]
    end

    subgraph "Layer 3: Monitoring and Response"
        L3A["16 indexed event types<br/>all permission changes logged"]
        L3B["Guardian role<br/>can cancel scheduled operations"]
        L3C["Per-target close<br/>emergency kill switch"]
    end

    subgraph "Layer 4: Infrastructure"
        L4A["UUPS upgradeable<br/>fix-forward capability"]
        L4B["ERC-7201 namespaced storage<br/>no upgrade collisions"]
        L4C["Independent manager per chain<br/>blast radius isolation"]
    end

    L1A --> L1B --> L1C
    L2A --> L2B --> L2C
    L3A --> L3B --> L3C
    L4A --> L4B --> L4C

    style L1A fill:#e74c3c,color:#fff
    style L1B fill:#e74c3c,color:#fff
    style L1C fill:#e74c3c,color:#fff
    style L2A fill:#e67e22,color:#fff
    style L2B fill:#e67e22,color:#fff
    style L2C fill:#e67e22,color:#fff
    style L3A fill:#f1c40f,color:#000
    style L3B fill:#f1c40f,color:#000
    style L3C fill:#f1c40f,color:#000
    style L4A fill:#3498db,color:#fff
    style L4B fill:#3498db,color:#fff
    style L4C fill:#3498db,color:#fff
```

### Security Properties

| Property | Implementation | Verification |
|---|---|---|
| **Fail-closed** | Unmapped functions default to ADMIN | `canCall()` returns false for unknown selectors |
| **Least privilege** | Each role maps to specific (target, selector) pairs | `addFunctionAllowedRoles()` granularity |
| **Defense in depth** | `restricted` with `MESSAGE_EXECUTOR` for executor paths + origin chain policies | Unified check via AccessManager |
| **Audit trail** | 16 indexed event types | All permission changes logged on-chain |
| **Emergency response** | `setContractPaused()` per-contract kill switch | Instant disable without revoking roles |
| **Upgrade safety** | UUPS with ADMIN + ERC-7201 storage | No storage collisions on upgrade |

---

## Attack Scenarios

### Scenario 1: Compromised Role Key

An attacker steals the key for a role with execution delays configured. The delay provides a detection window, and the guardian can cancel the operation before it executes.

```mermaid
sequenceDiagram
    participant Attacker as Attacker<br/>(stole COMPLIANCE_OFFICER key)
    participant Manager as RaylsAccessManagerV1
    participant Guardian as Guardian<br/>(PRIVACY_NODE_OPERATOR role)
    participant Target as TokenRegistryV1

    Note over Attacker: Attacker has COMPLIANCE_OFFICER<br/>key with 24h execution delay

    Attacker->>Manager: schedule(tokenRegistry,<br/>freezeToken(ALL_TOKENS), 86400)
    Manager-->>Attacker: OperationScheduled event

    Note over Manager: Monitoring alert fires<br/>"Suspicious freeze scheduled"

    Guardian->>Manager: cancel(attacker, tokenRegistry, data)
    Manager-->>Guardian: OperationCanceled event

    Guardian->>Manager: revokeRole(COMPLIANCE_OFFICER, attackerAddr)
    Manager-->>Guardian: RoleRevoked event

    Note over Attacker: Attack neutralized<br/>Blast radius: ZERO<br/>(operation never executed)
```

### Scenario 2: Compromised ADMIN Key (Worst Case)

Even in the worst case of ADMIN key compromise, grant delays provide a detection window for the security team to respond.

```mermaid
sequenceDiagram
    participant Attacker as Attacker<br/>(stole ADMIN key)
    participant Manager as RaylsAccessManagerV1
    participant Security as Security Team

    Note over Attacker: Tries to grant self<br/>all roles immediately

    Attacker->>Manager: grantRole(PRIVACY_NODE_OPERATOR, self, 0)

    alt Grant delay configured (recommended)
        Note over Manager: Grant delay: 48h<br/>Role is INACTIVE until elapsed
        Manager-->>Security: RoleGranted event detected by monitoring
        Security->>Manager: revokeRole(PRIVACY_NODE_OPERATOR, attacker)
        Note over Attacker: Neutralized before<br/>role activated
    else No grant delay configured
        Note over Manager: Role immediately active
        Note over Attacker: Can now call<br/>PRIVACY_NODE_OPERATOR-mapped functions
        Note over Security: Detect via events<br/>Revoke and rotate keys
    end
```

### Scenario 3: Malicious Function Remapping

An attacker remaps a sensitive function to the PUBLIC role, making it callable by anyone. Event monitoring detects the change immediately.

```mermaid
sequenceDiagram
    participant Attacker as Attacker<br/>(compromised admin)
    participant Manager as RaylsAccessManagerV1
    participant Monitor as Monitoring System

    Attacker->>Manager: addFunctionAllowedRoles(<br/>tokenRegistry,<br/>[freezeToken.selector],<br/>[PUBLIC])

    Manager-->>Monitor: FunctionAllowedRoleAdded event<br/>"freezeToken remapped to PUBLIC"

    Note over Monitor: CRITICAL ALERT:<br/>Sensitive function mapped<br/>to PUBLIC!

    Note over Monitor: Response: setContractPaused(<br/>tokenRegistry, true)<br/>until incident remediated
```

---

## Identity Isolation

Each Privacy Node deploys its own `RaylsAccessManagerV1` that manages internal roles locally. The Private Network Hub only sees the Participant address (the relayer's signing key). Internal role assignments are never exposed to the network layer.

```mermaid
graph TB
    subgraph "Privacy Node (Internal)"
        ROLES["Internal Roles<br/>Operator, Bank Employee,<br/>Auditor, Compliance Officer"]
        AM["RaylsAccessManagerV1<br/>(Privacy Node Instance)"]
        ROLES --> AM
    end

    subgraph "Privacy Boundary"
        WALL["Privacy Boundary"]
    end

    subgraph "Private Network (External)"
        PART["PARTICIPANT<br/>(Single Identity Address)"]
        NET["Network sees ONLY<br/>the participant address"]
        PART --> NET
    end

    AM -.->|"Relayer submits transactions<br/>using Participant key"| WALL
    WALL -.-> PART

    style WALL fill:#e74c3c,color:#fff
    style AM fill:#27ae60,color:#fff
    style PART fill:#3498db,color:#fff
```

---

## Upgrade Authorization

Contract upgrades are protected by the authorization system. The `_authorizeUpgrade` hook calls `_checkAdmin(msg.sender)` directly, requiring the caller to hold the ADMIN role. This is a direct storage check -- it does not go through the `canCall` bitmap path.

```mermaid
flowchart TD
    CALLER["Caller calls<br/>proxy.upgradeToAndCall()"] --> AUTH["_authorizeUpgrade() fires"]
    AUTH --> CHECK["_checkAdmin(msg.sender)"]
    CHECK --> VERIFY{"Caller has<br/>ADMIN?"}
    VERIFY -->|Yes| PROCEED["Upgrade proceeds"]
    VERIFY -->|No| REVERT["Revert:<br/>RaylsAccessManagerV1__Unauthorized"]

    style REVERT fill:#e74c3c,color:#fff
    style PROCEED fill:#27ae60,color:#fff
```

---

## Best Practices

- ADMIN should be a Gnosis Safe or equivalent multisig
- Set grant delays for critical roles (ADMIN: 72h, PRIVACY_NODE_OPERATOR: 48h)
- Set execution delays for destructive operations (freeze: 24h, upgrade: 72h)
- Configure guardian roles for all delayed roles
- Monitor all authorization events via the Governance API
- Conduct regular role membership reviews (quarterly)
- Professional audit before production deployment of business roles
- Document delay policy decisions and rationale

---

**Navigate:**

- [Back to Authorization Overview](index.md)
- [Access Manager](access-manager.md) - Core contract architecture and data model
- [Roles and Permissions](roles-and-permissions.md) - Role taxonomy and hierarchies
- [Authorization Flows](authorization-flows.md) - How authorization checks work at runtime
