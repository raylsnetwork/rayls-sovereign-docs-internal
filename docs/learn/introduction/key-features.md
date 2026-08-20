# Key Features

This page provides a catalog of Rayls' core capabilities. For technical implementation details, see [How It Works](how-it-works.md).

## Privacy Features

### End-to-End Encryption

All cross-chain messages are encrypted before leaving your Privacy Node:

- ML-KEM key encapsulation for establishing shared secrets (post-quantum)
- AES-256 encryption for message payloads
- Key Management Module (KMM) handles all cryptographic operations
- Keys can be stored in HSMs or cloud KMS (AWS, GCP, Azure)

### Enygma: Zero-Knowledge Private Transfers

Enygma hides transfer amounts even from the receiving institution:

| Property | Standard Transfer | Enygma Transfer |
|----------|-------------------|-----------------|
| Amount visible to sender | Yes | Yes |
| Amount visible to recipient | Yes | No (only balance change) |
| Amount visible on Hub | Encrypted | Hidden in ZK proof |
| Verifiable correctness | Yes | Yes (via ZK proof) |

**Performance:**

- Proof generation: 2-10 seconds
- k-Anonymity: 2-6 participants per batch
- Latency: 20-60 seconds end-to-end

### DVP: Private Atomic Swaps

Exchange assets between parties without either trusting the other:

- Atomic execution across token types (ERC-20/721/1155)
- Zero-knowledge proofs hide trade details
- Cross-Privacy-Ledger execution
- UTXO-based state for efficient verification

## Cross-Chain Capabilities

### Teleport Protocol

The core token transfer mechanism (burn-and-mint):

| Phase | Action |
|-------|--------|
| 1 | Token burned on source ledger |
| 2 | Merkle proof generated |
| 3 | Encrypted message posted to Hub |
| 4 | Destination Relayer decrypts |
| 5 | Token minted to recipient |

**Supported token standards:**

- **ERC-20** - Fungible tokens
- **ERC-721** - Non-fungible tokens (NFTs)
- **ERC-1155** - Multi-token standard

### Atomic Transactions

For transactions requiring all-or-nothing semantics:

- Funds locked during execution
- If destination fails, source automatically reverts
- If source fails, destination never executes
- Timeout-based fallback for edge cases

### EIP-5164 Implementation

Native cross-chain execution standard with context propagation (84 bytes appended to calldata: messageId, fromChainId, sender).

For code examples, see [How It Works](how-it-works.md#the-eip-5164-protocol).

## Infrastructure Features

### Ethereum Compatibility

Rayls Privacy Nodes are full Ethereum nodes:

| Feature | Support |
|---------|---------|
| Solidity contracts | Full support |
| EVM opcodes | All standard opcodes |
| JSON-RPC API | Standard Ethereum RPC |
| Contract size | Extended to 1MB (vs 24KB default) |
| Gas model | Standard Ethereum gas |
| Block time | 1 second (configurable) |

### Consensus

**Privacy Node (Narwhal + Bullshark BFT):**

- Multi-validator committee (4 by default) with epoch rotation via on-chain ConsensusRegistry
- Sub-second block time
- Deterministic BFT finality once a Bullshark leader gets f+1 support

**Hub (IBFT/QBFT):**

- Byzantine Fault Tolerant consensus
- Multiple validator nodes
- Tolerates up to 1/3 faulty validators

### Resource Registry

Chain-agnostic asset identification using 32-byte Resource IDs:

- Same asset referenced consistently across chains
- Enables automatic token mapping
- Supports multiple token types

## Operational Features

### Key Management Module (KMM)

| Key Type | Purpose |
|----------|---------|
| Rayls Sign Keys (ECDSA) | Blockchain signing |
| Rayls View Keys (ML-KEM) | Message encryption |
| Payment Spend Keys (Baby JubJub) | Enygma ZK proofs and commitments |

**Storage options:** AWS KMS, Google Cloud KMS, Azure Key Vault, HSMs, local (dev only)

### Governance and Audit

Compliance tools for regulated environments:

- Real-time transaction monitoring
- Configurable flagging rules
- Message decryption (with auditor keys)
- REST API for compliance queries
- Participant and token tracking

## Performance Characteristics

| Metric | Value |
|--------|-------|
| Privacy Node TPS | ~1000+ |
| Hub TPS | ~100-500 |
| Standard teleport | 30-60 seconds |
| Atomic transaction | 60-90 seconds |
| Enygma transfer | 20-60 seconds |

## Integration Options

| Interface | Use Case |
|-----------|----------|
| JSON-RPC | Direct blockchain access |
| REST API (Backend) | Application integration |
| Governance API | Compliance queries |
| WebSocket | Real-time events |

**Custody integration:** Self-custody with HSM, Cloud KMS signing, third-party custody (e.g., Fireblocks), multi-signature schemes.

---

**Next:** [How It Works](how-it-works.md) - Technical deep-dive into the architecture.
