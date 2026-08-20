# API Reference

Complete API reference for Rayls smart contracts and services.

---

## Overview

This reference documents the APIs available for Rayls development.

!!! info "Coming Soon"
    Detailed content coming soon. This guide will cover:

    - RaylsEndpoint contract API
    - Token handler APIs
    - Relayer service APIs
    - Backend API endpoints
    - Event specifications

---

## Quick Reference

### RaylsEndpoint

| Function | Description |
|----------|-------------|
| `teleport()` | Initiate cross-chain transfer |
| `registerToken()` | Register token for cross-chain use |
| `executeMessage()` | Execute incoming message |

### Token Handlers

| Contract | Purpose |
|----------|---------|
| `RaylsErc20Handler` | ERC-20 token transfers |
| `RaylsErc721Handler` | ERC-721 NFT transfers |
| `RaylsErc1155Handler` | ERC-1155 multi-token transfers |
| `RaylsEnygmaHandler` | Privacy-preserving transfers |

---

## Related Documentation

- [Endpoint Integration](endpoint-integration.md) - Integration patterns
- [Token Standards](token-standards.md) - Handler details
- [EIP-5164 Explained](eip-5164-explained.md) - Protocol reference

---

**Navigate:**

- [Back to Build Overview](../index.md)
