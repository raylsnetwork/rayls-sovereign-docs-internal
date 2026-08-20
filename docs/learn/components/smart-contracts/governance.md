# Governance Contracts

Smart contracts that manage permissions, registrations, and authorization within a Privacy Node. These contracts control who can perform operations and how tokens and users are managed.

---

## Overview

Governance contracts operate at the Privacy Node level, managing local permissions and registrations. They work alongside Hub registries to maintain consistent state across the network.

---

## Core Contracts

### RNUserGovernanceV1

Manages address pair mappings between public and private chains.

**What it does:**

- Maps user IDs to public and private addresses
- Enables address lookups in either direction
- Supports compliance and audit requirements
- Maintains user identity across chain boundaries

**Key operations:**

- Add address pairs (public ↔ private mapping)
- Look up addresses by user ID
- Look up user ID by public or private address

### PNTokenRegistryV1

Manages token registration, authorization, and status on a Privacy Node. It is a modular subsystem (a `PNTokenRegistryV1` facade delegating to `PNTokenCoreV1` and `PNTokenFreezeManagerV1`) that centralizes logic that used to be scattered across individual token and handler contracts. See the dedicated [PN Token Registry](pn-token-registry.md) page for the full architecture, status state machines, and flows.

**What it does:**

- Registers tokens locally when created or received via a single `registerToken(tokenAddress)` entry point
- Tracks three independent statuses per token — `PrivacyNodeStatus`, `HubStatus`, and `PublicChainStatus`
- Maps between private and public token addresses
- Coordinates with the Hub `TokenRegistryV1` for cross-chain state
- Centralizes freeze/unfreeze across the Privacy Node, Hub, and public-chain layers

**Key operations:**

- `registerToken(tokenAddress)` — register a token locally (`privacyNodeStatus = WAITING_APPROVAL`)
- `updatePrivacyNodeStatus(addr, AUTHORIZED)` — authorize the token for local operation
- `submitToHub(addr)` / `submitToPublicChain(addr)` — submit an authorized token for cross-chain or public-chain use
- Query token existence and the three statuses
- Map addresses between chains

### RaylsAccessManagerV1

Controls all authorization decisions across the Privacy Node through a unified, function-level permission system.

**What it does:**

- Manages named roles with function-level granularity
- Enforces permissions via the `restricted` modifier on all consumer contracts
- Supports target-scoped grants for per-contract role isolation
- Provides execution delays, guardians, and per-contract emergency pause

**Key operations:**

- Grant and revoke roles
- Map functions to roles
- Pause and unpause contracts
- Schedule and execute delayed operations

See [Authorization](../../governance/authorization/index.md) for full documentation.

---

## Permission Model

!!! info "Authorization System"
    The permission model is managed by `RaylsAccessManagerV1`. Consumer contracts use the `restricted` modifier, which delegates authorization checks to the AccessManager. See [Authorization](../../governance/authorization/index.md) for full documentation.

### Role Hierarchy

```
ADMIN (role 0)
├── Can upgrade contracts (UUPS)
├── Can configure settings
├── Can manage all roles
└── Bypasses all authorization checks

RELAYER (infrastructure role)
├── Can execute incoming messages (receivePayload)
├── Can submit encrypted data and headers
└── Cannot modify governance

MESSAGE_EXECUTOR (infrastructure role)
├── Can deliver cross-chain messages to target contracts
└── Cannot modify permissions

ENDPOINT_SENDER (infrastructure role)
├── Token contracts send cross-chain messages
└── Scoped to EndpointV1

TOKEN_OWNER (built-in role 2)
├── Can mint and burn on their specific token
├── Target-scoped (per-contract)
└── Cannot affect other tokens
```

### Access Control Modifiers

All privileged functions use the unified `restricted` modifier, which delegates authorization checks to `RaylsAccessManagerV1`:

| Modifier | Purpose |
|----------|---------|
| `restricted` | Unified authorization via AccessManager `canCall()` check |
| `onlyFromPrivateHub` | Validates cross-chain message origin (calldata check, not role-based) |

### Message Authorization Flow

When a cross-chain message arrives:

1. **Relayer submits** - Must hold the RELAYER role in the AccessManager
2. **Endpoint validates** - `restricted` modifier checks `canCall()` for RELAYER role
3. **MessageReceiver forwards** - Protocol-level address check (`onlyEndpoint`)
4. **MessageExecutor delivers** - `restricted` modifier checks MESSAGE_RECEIVER role
5. **Target receives** - `restricted` modifier checks MESSAGE_EXECUTOR role
6. **Context verified** - Target can check source chain via `onlyFromPrivateHub` (calldata check)

---

## Registration Flows

### Token Registration

1. Token created on Privacy Node
2. `PNTokenRegistryV1.registerToken(tokenAddress)` records the local registration (`privacyNodeStatus = WAITING_APPROVAL`)
3. PN operator authorizes it via `updatePrivacyNodeStatus(addr, AUTHORIZED)`
4. Operator calls `submitToHub(addr)`; the Hub `TokenRegistryV1` approves with `updateStatus(resourceId, ACTIVE)`
5. The Hub delivers the `activateToken(bytes32,address,uint8)` callback back to the PN registry, which registers the resource ID and sets `hubStatus = AUTHORIZED`; other Privacy Nodes that receive the token auto-register locally

See the [PN Token Registry](pn-token-registry.md) page for the complete flow.

### Participant Registration

1. Institution joins network
2. Registered on Hub ParticipantStorage
3. Public keys stored (Rayls View Keys, Payment Spend Keys)
4. Broadcast to all Privacy Nodes
5. Local replicas updated

---

## Security Considerations

- **Owner privileges** - Owner can upgrade contracts; secure key management is critical
- **Relayer trust** - Only authorized relayers can execute messages
- **Replay protection** - Message IDs prevent duplicate execution
- **Source validation** - Handlers can verify message origin

---

**Navigate:**

- [Back to Smart Contracts Overview](index.md)
