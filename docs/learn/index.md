# Learn Rayls

Welcome to the Rayls learning center. This section provides comprehensive documentation on how Rayls works, from high-level concepts to deep technical implementation details.

## What You'll Learn

Rayls is a **privacy-preserving institutional blockchain network** that enables secure, confidential cross-chain token transfers between financial institutions. The Learn section is structured to take you from understanding the business case to mastering the technical architecture.

---

## Documentation Structure

### [Introduction](introduction/index.md)

Start here to understand what Rayls is, what problems it solves, and why it exists.

- **[What is Rayls?](introduction/what-is-rayls.md)** - The vision, value proposition, and challenges Rayls addresses
- **[Key Features](introduction/key-features.md)** - Core strengths and capabilities
- **[How It Works](introduction/how-it-works.md)** - High-level system walkthrough

**Best for:** Business stakeholders, solution architects, anyone new to Rayls

---

### [Components](components/index.md)

Deep dive into each system component - what it does, how it works, and why it exists.

#### Architecture
- **[Transaction Lifecycle](components/architecture/transaction-lifecycle.md)** - End-to-end transaction flow
- **[Privacy Node Components](components/architecture/privacy-node-components.md)** - Hub-and-spoke architecture
- **[Hub Components](components/architecture/hub-components.md)** - Private Network Hub architecture

#### Infrastructure
- **[Rayls Privacy Nodes](components/privacy-nodes/index.md)** - Private Ethereum-based chains per institution
- **[Private Network Hub](components/private-network-hub/index.md)** - Central coordination layer (Hub)
- **[Smart Contracts](components/smart-contracts/index.md)** - All contracts in the Rayls ecosystem
- **[Relayer](components/relayer/index.md)** - Orchestration service bridging Privacy Nodes to Hub

#### Services
- **[Key Management Module (KMM)](components/kos/index.md)** - Cryptographic key management and encryption
- **[Gnark API](components/gnark-api/index.md)** - Zero-knowledge proof generation
- **[Governance](governance/index.md)** - Regulatory oversight and compliance

#### Optional Components
- **[Public Chain](components/public-chain/index.md)** *(Optional)* - Integration with public blockchains (Ethereum, etc.)
- **[Backend](components/backend/index.md)** *(Optional)* - Transaction construction and custody integration for public chains

**Best for:** Developers, system integrators, operators, solution architects

---

### [Protocols](protocols/teleport-atomic/overview.md)

Learn the cryptographic protocols and message passing systems that power Rayls.

#### Core Protocols
- **[Teleport Atomic](protocols/teleport-atomic/overview.md)** - Atomic cross-chain token transfers with EIP-5164

#### Privacy Protocols
- **[Enygma](protocols/enygma/index.md)** - Confidential token transfers with zero-knowledge proofs
- **[DVP](protocols/dvp/index.md)** - Zero-Knowledge Delivery versus Payment (atomic swaps)

**Best for:** Cryptographers, protocol developers, security researchers

---

## Learning Paths

### For Business Stakeholders
1. [What is Rayls?](introduction/what-is-rayls.md)
2. [Key Features](introduction/key-features.md)
3. [Transaction Lifecycle](components/architecture/transaction-lifecycle.md)

### For Developers
1. [How It Works](introduction/how-it-works.md)
2. [Components](components/index.md)
3. [Teleport Atomic](protocols/teleport-atomic/overview.md)
4. Then explore [Build](../build/index.md) section for hands-on development

### For Protocol Researchers
1. [Enygma Protocol](protocols/enygma/index.md)
2. [DVP Protocol](protocols/dvp/index.md)
3. [Cryptographic Foundations](protocols/enygma/cryptographic-foundations.md)
4. [The Proof System](protocols/enygma/the-proof-system.md)

### For Operators
1. [Components](components/index.md) - all subsections
2. [Governance](governance/index.md)
3. Then explore [Deploy](../deploy/index.md) section for production setup

---

## Quick Reference

| Topic | Key Pages |
|-------|-----------|
| **Business Case** | [What is Rayls](introduction/what-is-rayls.md), [Key Features](introduction/key-features.md) |
| **Technical Design** | [Transaction Lifecycle](components/architecture/transaction-lifecycle.md), [Hub Components](components/architecture/hub-components.md) |
| **Privacy Features** | [Enygma](protocols/enygma/index.md), [DVP](protocols/dvp/index.md) |
| **Operations** | [Governance](governance/index.md), [Relayer](components/relayer/index.md) |
| **Integration** | [Build Section](../build/index.md), [Deploy Section](../deploy/index.md) |

---

## Next Steps

- **New to Rayls?** Start with [Introduction](introduction/index.md)
- **Ready to build?** Head to [Build Section](../build/index.md)
- **Deploying to production?** See [Deploy Section](../deploy/index.md)

---

**Need help?** Check the [Glossary](../resources/glossary.md) for term definitions.
