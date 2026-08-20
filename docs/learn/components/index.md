# Components Overview

Deep dive into each system component - what it does, how it works, and why it exists.

## Architecture

- **[Transaction Lifecycle](architecture/transaction-lifecycle.md)** - End-to-end transaction flow
- **[Privacy Node Components](architecture/privacy-node-components.md)** - Hub-and-spoke architecture design
- **[Hub Components](architecture/hub-components.md)** - Private Network Hub architecture
- **[Enygma Batching](architecture/enygma.md)** - Privacy-preserving transfer batching

## Infrastructure Components

Core components required for all Rayls deployments.

- **[Rayls Privacy Nodes](privacy-nodes/index.md)** - Private Ethereum-based chains per institution
- **[Private Network Hub](private-network-hub/index.md)** - Central coordination layer (Hub)
- **[Smart Contracts](smart-contracts/index.md)** - All contracts in the Rayls ecosystem
- **[Relayer](relayer/index.md)** - Orchestration service bridging Privacy Nodes to Hub

## Service Components

Supporting services for cryptography, compliance, and operations.

- **[Key Management Module (KMM)](kos/index.md)** - Cryptographic key management and encryption
- **[Gnark API](gnark-api/index.md)** - Zero-knowledge proof generation
- **[Governance](../governance/index.md)** - Regulatory oversight and compliance

## Optional Components

Components required only for public chain integration.

- **[Public Chain](public-chain/index.md)** *(Optional)* - Integration with public blockchains (Ethereum, etc.)
- **[Backend](backend/index.md)** *(Optional)* - Transaction construction and custody integration for public chains

---

**Navigate:**
- [Back to Learn Overview](../index.md)
