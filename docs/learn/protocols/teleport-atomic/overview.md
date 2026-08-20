# Atomic Teleport Protocol

Learn about the Atomic Teleport protocol, Rayls' guaranteed cross-chain asset transfer system with automatic rollback mechanisms.

## What is Atomic Teleport?

**Atomic Teleport** is a protocol that guarantees **"all or nothing"** cross-chain asset transfers:

- ✅ **Success**: Asset appears on destination chain AND disappears from origin chain
- ❌ **Failure**: Asset automatically returns to origin chain (rollback)
- 🚫 **Impossible**: Asset lost or duplicated between chains

### The Problem with Traditional Cross-Chain Transfers

**Traditional Teleport** (non-atomic):

```solidity
function teleport(address to, uint256 value, uint256 chainId) {
    _burn(msg.sender, value);  // Asset destroyed immediately
    // Sends cross-chain message
    // If destination fails → ASSET LOST FOREVER
}
```

**Risk**: If the destination chain rejects the transfer (invalid address, blacklisted recipient, contract error), the asset is permanently lost because it was already burned on the origin chain.

**Atomic Teleport** (guaranteed):

```solidity
function teleportAtomic(address to, uint256 value, uint256 chainId) {
    _burn(msg.sender, value);  // Asset destroyed temporarily
    // Sends with automatic revert capability
    // Destination: asset stays "locked" until confirmed
    // If fails → automatic revert restores asset on origin
}
```

**Guarantee**: The asset either completes the full journey (origin → destination) or automatically returns to the origin. No intermediate "lost" state exists.

## System Architecture

### Core Components

**1. TeleportV1 Contract (Private Network Hub)**
- Central controller for all atomic transfers
- Tracks message status: Pending → Executed/Reverted
- Enforces 240-second timeout (LOCK_TIME)
- Coordinates execution and revert payloads

**2. Token Handlers (Privacy Nodes)**
- ERC-20, ERC-721, ERC-1155 implementations
- Lock/unlock mechanisms
- Temporary mint/burn operations
- Revert execution

**3. Relayers**
- Monitor origin chains for teleport initiations
- Submit messages to TeleportV1 on Private Network Hub
- Execute confirmations or reverts on destination chains
- Handle timeout scenarios

### Message States

```
┌──────────┐    Success    ┌──────────┐
│          │─────────────→│          │
│ Pending  │              │ Executed │
│          │←────────────┤          │
└──────────┘    Timeout    └──────────┘
     │             or
     │          Failure
     ↓
┌──────────┐
│          │
│ Reverted │
│          │
└──────────┘
```

## How Atomic Teleport Works

### Phase 1: Initiation (Origin Chain)

User initiates atomic teleport:

```solidity
// User calls on origin chain (e.g., Privacy Node A)
token.teleportAtomic(
    recipientAddress,  // Destination address
    100 * 10**18,      // Amount (100 tokens)
    chainIdB           // Destination chain ID
);
```

**What Happens:**
1. **Burn**: Asset temporarily destroyed on origin chain
2. **Prepare Payloads**:
   - **Execute payload**: Mint and lock on destination
   - **Unlock payload**: Final transfer to recipient
   - **Revert-sender payload**: Restore asset if failure
   - **Revert-receiver payload**: Cleanup on destination
3. **Send Message**: Submit to Private Network Hub via Relayer

### Phase 2: Message Registration (Private Network Hub)

TeleportV1 receives and tracks the message:

```solidity
// TeleportV1 on Private Network Hub
AtomicTeleportMessage {
    startTime: block.timestamp,           // e.g., 1699564800
    expiration: block.timestamp + 240,    // +4 minutes
    status: MessageStatus.Pending
}
```

**Key Properties:**
- **LOCK_TIME**: 240 seconds (4 minutes) to complete transfer
- **Status Tracking**: Pending until execution or timeout
- **Batch Processing**: Multiple messages handled together for efficiency

### Phase 3: Reception (Destination Chain)

Destination chain receives execute payload:

```solidity
// On destination chain (e.g., Privacy Node B)
function receiveTeleportAtomic(address to, uint256 value) {
    _mint(owner(), value);  // Temporary mint to contract
    if (to != owner()) {
        _lock(to, value);   // Lock for recipient
    }
}
```

**State**:
- Asset exists on destination but is **locked**
- Cannot be transferred or spent yet
- Awaiting confirmation from Private Network Hub

### Phase 4A: Success Path - Confirmation

If destination reception succeeds:

```solidity
// TeleportV1 on Private Network Hub
function executeAtomicMessageBatch(string[] msgIds) {
    for (uint i = 0; i < msgIds.length; i++) {
        message.status = MessageStatus.Executed;
    }
    emit AtomicMessageStatusChangedBatch(msgIds, Executed);
}

// Destination chain receives unlock payload
function unlock(address to, uint256 value) {
    _unlock(to, value);           // Remove lock
    _transfer(owner(), to, value); // Transfer to recipient
}
```

**Result**: Asset permanently transferred to destination.

### Phase 4B: Failure Path - Automatic Revert

If destination fails OR timeout occurs:

```solidity
// TeleportV1 on Private Network Hub
function revertAtomicMessageBatch(string[] msgIds) {
    for (uint i = 0; i < msgIds.length; i++) {
        message.status = MessageStatus.Reverted;
    }
    emit AtomicMessageStatusChangedBatch(msgIds, Reverted);
}

// Origin chain receives revert payload
function revertTeleportMint(address to, uint256 value) {
    _mint(to, value);  // Restore asset to original sender
}
```

**Result**: Asset returned to sender on origin chain.

## Key Features

### 1. Automatic Rollback

No manual intervention needed:

```javascript
// If timeout (240 seconds passed):
if (block.timestamp > message.expiration &&
    message.status == Pending) {
    // Automatically reverted by Relayer
    revertAtomicMessageBatch(msgIds);
}
```

### 2. Lock/Unlock Mechanism

**ERC-20 Example:**

```solidity
// Internal tracking of locked amounts
mapping(address => uint256) private lockedAmount;

function _lock(address to, uint256 amount) internal {
    lockedAmount[to] += amount;
}

function _unlock(address to, uint256 amount) internal {
    require(amount <= lockedAmount[to]);
    lockedAmount[to] -= amount;
    return true;
}
```

**Purpose**: Prevents spending of assets until transfer is confirmed.

### 3. Batch Processing

Multiple teleports processed together:

```solidity
// Process 50 messages in one transaction
executeAtomicMessageBatch([msgId1, msgId2, ..., msgId50]);
```

**Benefits:**
- Reduced gas costs
- Improved throughput
- Coordinated state changes

### 4. Timeout Protection

Automatic expiration prevents stuck transfers:

- **Default**: 240 seconds (4 minutes)
- **Configurable**: Via `COMMITCHAIN_EXPIRATIONREVERTTIMEINMINUTES`
- **Monitoring**: Relayers watch for expired messages

## Token Standard Support

### ERC-20 (Fungible Tokens)

```solidity
// Lock specific amount
lockedAmount[recipient] += 100 * 10**18;

// Unlock specific amount
lockedAmount[recipient] -= 100 * 10**18;
```

### ERC-721 (NFTs)

```solidity
// Lock specific token ID
lockedTokens[recipient][tokenId] = true;

// Unlock specific token ID
lockedTokens[recipient][tokenId] = false;
```

### ERC-1155 (Multi-Tokens)

```solidity
// Lock specific token ID and amount
lockedAmount[recipient][tokenId] += 50;

// Unlock specific token ID and amount
lockedAmount[recipient][tokenId] -= 50;
```

## Use Cases

### 1. High-Value Asset Transfers

**Scenario**: Transfer $1M USDC between Privacy Nodes

**Why Atomic**:
- Too valuable to risk loss
- Automatic rollback if destination unavailable
- Guaranteed delivery or refund

### 2. NFT Marketplace Operations

**Scenario**: Selling rare NFT across chains

**Why Atomic**:
- NFT uniqueness requires atomicity
- Prevents NFT duplication or loss
- Buyer and seller protected

### 3. Cross-Chain DeFi

**Scenario**: Move collateral between lending protocols

**Why Atomic**:
- Liquidation protection during transfer
- No intermediate "stuck" state
- Predictable settlement time (240s max)

### 4. Regulatory Compliance

**Scenario**: Transfer between regulated entities

**Why Atomic**:
- Audit trail with definitive outcomes
- No "lost funds" to explain
- Compliance-friendly rollback mechanism

## Advantages Over Other Solutions

### vs Traditional Bridge Protocols

| Feature | Traditional Bridge | Atomic Teleport |
|---------|-------------------|-----------------|
| Asset Loss Risk | Medium-High (if dest fails) | Zero (auto-rollback) |
| Settlement Time | Variable (hours-days) | Predictable (≤240s) |
| Stuck Transactions | Common | Impossible |
| Manual Recovery | Often required | Automatic |
| Gas Efficiency | Lower | Higher (batching) |

### vs Lock-and-Mint Bridges

| Feature | Lock-and-Mint | Atomic Teleport |
|---------|---------------|-----------------|
| Atomicity | No | Yes |
| Timeout Handling | Manual | Automatic |
| Failed Transfer | Assets stuck | Auto-returned |
| Trust Model | Trusted validator set | Protocol-enforced |

### vs HTLCs (Hash Time-Locked Contracts)

| Feature | HTLC | Atomic Teleport |
|---------|------|-----------------|
| User Experience | Complex (hashlock/timelock) | Simple |
| Coordination | Manual secret reveal | Automatic |
| Timeout Recovery | User-initiated | Auto-revert |
| Privacy | Limited (hash reveals) | Better (encrypted messages) |

## Limitations and Considerations

### 1. Timeout Window

**240-second window** for completion:

- Fast enough for most use cases
- May be tight for complex destination operations
- Configurable via governance

### 2. Gas Costs

Atomic operations cost more than non-atomic:

- Additional lock/unlock operations
- Revert payload storage
- Batch processing mitigates this

### 3. Destination Requirements

Destination chain must:

- Be online and accepting transactions
- Have Atomic Teleport support
- Complete reception within timeout

### 4. Finality Considerations

- Assumes block finality on all chains
- Reorgs could complicate state
- axyl's Bullshark BFT provides deterministic finality in Rayls once a leader gets f+1 support

## Security Guarantees

### 1. Asset Conservation

**Mathematical Proof**:

```
Let S = total supply across all chains

At any time:
S = Σ(unlocked_i) + Σ(locked_i) + Σ(burned_pending_revert_i)

After atomic operation completes:
S_before = S_after (conservation maintained)
```

### 2. No Double-Spend

**Mechanism**:
- Asset burned on origin before destination mint
- Destination mint is locked until confirmation
- Revert only possible if destination mint reversed

### 3. No Asset Loss

**State Machine**:

```
Burned(origin) ∧ Pending(commit) →
    [Success: Unlocked(dest)] ∨
    [Failure: Minted(origin)]
```

All paths lead to asset existing exactly once.

### 4. Timeout Safety

**Invariant**:

```
if (block.timestamp > expiration) {
    status ≠ Pending
}
```

No message stuck indefinitely.

## Integration Examples

### For Developers

See detailed guides:
- **[Cross-Chain Messaging](crosschain-messaging.md)** - Message lifecycle
- **[Token Transfers](token-transfers.md)** - ERC-20/721/1155 specific flows
- **[Batch Processing](batch-processing.md)** - Optimizing multiple transfers
- **[Atomic Reverts](atomic-reverts.md)** - Handling failures

### For Application Builders

See implementation guides:
- **[Smart Contracts](../../../build/intermediate/endpoint-integration.md)** - Integrating Atomic Teleport
- **[Token Standards](../../../build/intermediate/token-standards.md)** - Token implementations
- **[Testing](../../../build/intermediate/testing.md)** - Testing atomic transfers

## Additional Resources

- [Atomic Teleport Technical Specification](https://github.com/rayls/rayls-sovereign-contracts/docs/ATOMIC_TELEPORT_TECHNICAL_GUIDE.md)
- [Cross-Chain Communication Patterns](https://ethereum.org/en/developers/docs/bridges/)
- [Atomic Swap Research](https://arxiv.org/abs/1801.09515)
