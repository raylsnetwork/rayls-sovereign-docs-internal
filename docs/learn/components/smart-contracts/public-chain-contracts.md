# Public Chain Contracts

Smart contracts for bridging Rayls Privacy Node Ledgers to public blockchains like Ethereum. These contracts enable token transfers between private and public networks.

!!! info "Optional Component"
    Public chain integration is optional. These contracts are only deployed when bridging assets to/from public blockchains.

## Contract Overview

| Contract | Type | Purpose |
|---|---|---|
| **PublicRNEndpointV1** | Infrastructure | Message gateway on the public chain — receives and dispatches cross-chain messages |
| **RaylsPublicApp** | Base | Abstract base for public chain applications — provides `receiveMethod` modifier |
| **RaylsPublicERC20Handler** | Handler | ERC-20 bridge logic — lock, unlock, mint, and revert operations |
| **RaylsPublicERC721Handler** | Handler | ERC-721 bridge logic with original owner tracking |
| **RaylsPublicERC1155Handler** | Handler | ERC-1155 bridge logic with per-token-ID tracking |
| **PublicChainERC20** | Implementation | Auto-deployed ERC-20 mirror contract |
| **PublicChainERC721** | Implementation | Auto-deployed ERC-721 mirror contract |
| **PublicChainERC1155** | Implementation | Auto-deployed ERC-1155 mirror contract |

!!! tip "Detailed Documentation"
    For comprehensive documentation on public chain integration:

    - [Bridge Architecture](../public-chain/architecture.md) — How infrastructure contracts connect, endpoint differences, and contract details
    - [Token Bridging](../public-chain/token-bridging.md) — Transfer flows with sequence diagrams, failure handling, and lock/unlock mechanics
    - [Public Chain Bridge (Build Guide)](../../../build/advanced/public-chain-bridge.md) — Step-by-step developer guide for building bridgeable tokens

---

**Navigate:**

- [Back to Smart Contracts Overview](index.md)
