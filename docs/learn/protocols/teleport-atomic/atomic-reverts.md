# Atomic Reverts

Learn how Atomic Teleport's automatic rollback mechanism ensures assets are never lost, with detailed revert scenarios and recovery procedures.

## Overview

The atomic revert mechanism is the core safety feature of Atomic Teleport. It guarantees that if a cross-chain transfer cannot be completed, the asset is automatically restored to its original owner on the origin chain.

**Key Principles:**
- **Automatic**: No manual intervention required
- **Guaranteed**: All failed transfers trigger revert
- **Time-Bounded**: Reverts occur within 240 seconds (LOCK_TIME)
- **Asset-Safe**: No intermediate "lost" state possible

## Revert Triggers

### 1. Destination Execution Failure

**Scenario**: Destination chain rejects the transfer

**Common Causes:**
- Recipient address blacklisted
- Insufficient contract balance
- Custom validation fails
- Contract execution error

**Example:**

```solidity
// Destination chain token contract
function receiveTeleportAtomic(address to, uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint");

    // Custom validation that might fail
    require(!isBlacklisted(to), "Recipient is blacklisted");
    require(to != address(0), "Invalid recipient");

    // If any require fails → transaction reverts
    // → Relayer detects failure
    // → Triggers automatic revert on Private Network Hub
    _mint(owner(), value);
    _lock(to, value);
}
```

**Revert Flow:**

```
1. Destination execution fails
2. Relayer B detects failure
3. Relayer B calls revertAtomicMessageBatch([msgId])
4. TeleportV1 marks message as Reverted
5. Relayer A executes revert payload on origin chain
6. Asset restored to original sender
```

### 2. Timeout Expiration

**Scenario**: Message not processed within 240 seconds

**Causes:**
- Destination chain offline
- Relayer B offline or slow
- Network congestion
- Gas price too low

**Timeout Detection:**

```javascript
// Relayer monitoring for expired messages
setInterval(async () => {
    const now = Math.floor(Date.now() / 1000);

    // Query all pending messages
    const pendingMessages = await teleportV1.getPendingMessages();

    // Find expired messages
    const expired = pendingMessages.filter(msg =>
        msg.expiration < now && msg.status === 0 // 0 = Pending
    );

    if (expired.length > 0) {
        console.log(`Found ${expired.length} expired messages`);
        const msgIds = expired.map(m => m.id);

        // Trigger automatic revert
        await teleportV1.revertAtomicMessageBatch(msgIds, encryptedData);
        console.log(`Reverted ${msgIds.length} expired messages`);
    }
}, 10000); // Check every 10 seconds
```

**Timeline:**

```
T=0:     Message created
T=0-240: Normal processing window
T=240:   Expiration reached
T=240+:  Relayer detects and triggers revert
T=250:   Asset restored to sender
```

### 3. Manual Revert (Post-Expiration)

**Scenario**: User manually triggers revert after timeout

**When to Use:**
- Relayer failed to auto-revert
- Manual recovery needed
- Testing/debugging

**Implementation:**

```javascript
// User checks if message expired
async function checkAndRevertExpired(messageId) {
    const message = await teleportV1.atomicTeleportMessages(messageId);
    const now = Math.floor(Date.now() / 1000);

    if (message.status === 0 && message.expiration < now) {
        console.log("Message expired and still pending");

        // User can trigger manual revert
        const tx = await teleportV1.revertAtomicMessageBatch(
            [messageId],
            encryptedData
        );

        await tx.wait();
        console.log("Manual revert completed:", tx.hash);
    }
}
```

### 4. Batch Partial Failure

**Scenario**: Some messages in batch fail, others succeed

**Handling:**

```javascript
async function processBatchWithPartialFailure(messages) {
    const successful = [];
    const failed = [];

    // Try each message
    for (const msg of messages) {
        try {
            await destinationEndpoint.executeMessage(msg.id, msg.payload);
            successful.push(msg.id);
        } catch (error) {
            console.error(`Message ${msg.id} failed:`, error);
            failed.push(msg.id);
        }
    }

    // Execute successful messages
    if (successful.length > 0) {
        await teleportV1.executeAtomicMessageBatch(successful, encryptedData);
        console.log(`Executed ${successful.length} successful messages`);
    }

    // Revert failed messages
    if (failed.length > 0) {
        await teleportV1.revertAtomicMessageBatch(failed, encryptedData);
        console.log(`Reverted ${failed.length} failed messages`);
    }
}
```

## Revert Payload System

### Payload Structure

Every atomic teleport includes four payloads:

```solidity
struct TeleportPayloads {
    bytes executePayload;        // Normal execution on destination
    bytes unlockPayload;         // Unlock after confirmation
    bytes revertPayloadSender;   // Revert on origin chain
    bytes revertPayloadReceiver; // Cleanup on destination chain
}
```

### ERC-20 Revert Payloads

**Creation:**

```solidity
function teleportAtomic(address to, uint256 value, uint256 chainId) external {
    // Burn on origin
    _burn(msg.sender, value);

    // Prepare revert payload for sender (origin chain)
    bytes memory revertSender = abi.encodeWithSignature(
        "revertTeleportMint(address,uint256)",
        msg.sender,  // Restore to original sender
        value        // Original amount
    );

    // Prepare revert payload for receiver (destination chain)
    bytes memory revertReceiver = abi.encodeWithSignature(
        "revertTeleportBurn(uint256)",
        value  // Burn temporary mint if any
    );

    // Send to endpoint
    endpoint.sendTeleport(
        chainId,
        executePayload,
        unlockPayload,
        revertSender,
        revertReceiver,
        metadata
    );
}
```

**Execution on Origin Chain:**

```solidity
// Automatically called when revert triggered
function revertTeleportMint(address to, uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint");

    // Restore asset to original sender
    _mint(to, value);

    emit TeleportReverted(to, value, block.timestamp);
}
```

**Execution on Destination Chain (Cleanup):**

```solidity
// Burns any temporary minted tokens
function revertTeleportBurn(uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint");

    // Burn temporary mint (if receiveTeleportAtomic succeeded)
    if (balanceOf(owner()) >= value) {
        _burn(owner(), value);
    }

    emit TeleportRevertedCleanup(value, block.timestamp);
}
```

### ERC-721 Revert Payloads

**Creation:**

```solidity
function teleportAtomic(address to, uint256 tokenId, uint256 chainId) external {
    // Burn NFT on origin
    _burn(tokenId);

    // Revert payload: restore NFT to original owner
    bytes memory revertSender = abi.encodeWithSignature(
        "revertTeleportMint(address,uint256)",
        msg.sender,  // Original owner
        tokenId      // Original token ID
    );

    // Cleanup payload: burn temporary NFT on destination
    bytes memory revertReceiver = abi.encodeWithSignature(
        "revertTeleportBurn(uint256)",
        tokenId
    );

    endpoint.sendTeleport(
        chainId,
        executePayload,
        unlockPayload,
        revertSender,
        revertReceiver,
        metadata
    );
}
```

**Execution:**

```solidity
// Restore NFT to original owner
function revertTeleportMint(address to, uint256 tokenId) external {
    require(msg.sender == address(endpoint), "Only endpoint");

    // Re-mint NFT with same token ID
    _mint(to, tokenId);

    emit NFTTeleportReverted(to, tokenId, block.timestamp);
}

// Cleanup: burn temporary NFT if it was minted
function revertTeleportBurn(uint256 tokenId) external {
    require(msg.sender == address(endpoint), "Only endpoint");

    // Burn if exists
    if (_ownerOf(tokenId) == owner()) {
        _burn(tokenId);
    }

    emit NFTTeleportRevertedCleanup(tokenId, block.timestamp);
}
```

### ERC-1155 Revert Payloads

**Creation:**

```solidity
function teleportAtomic(
    address to,
    uint256 id,
    uint256 amount,
    uint256 chainId
) external {
    // Burn on origin
    _burn(msg.sender, id, amount);

    // Revert payload: restore to sender
    bytes memory revertSender = abi.encodeWithSignature(
        "revertTeleportMint(address,uint256,uint256)",
        msg.sender,
        id,
        amount
    );

    // Cleanup payload: burn on destination
    bytes memory revertReceiver = abi.encodeWithSignature(
        "revertTeleportBurn(uint256,uint256)",
        id,
        amount
    );

    endpoint.sendTeleport(
        chainId,
        executePayload,
        unlockPayload,
        revertSender,
        revertReceiver,
        metadata
    );
}
```

## Revert State Machine

### Message Status Transitions

```
┌─────────┐
│         │
│ Pending │◄──── Initial state after creation
│         │
└────┬────┘
     │
     ├──────────────┐
     │              │
     ▼              ▼
┌─────────┐    ┌──────────┐
│         │    │          │
│Executed │    │ Reverted │
│         │    │          │
└─────────┘    └──────────┘

ALLOWED TRANSITIONS:
Pending → Executed   (success path)
Pending → Reverted   (failure path)

FORBIDDEN TRANSITIONS:
Executed → Reverted  (cannot revert after execution)
Reverted → Executed  (cannot execute after revert)
```

**State Validation:**

```solidity
function executeAtomicMessageBatch(string[] calldata msgIds, ...) external {
    for (uint i = 0; i < msgIds.length; i++) {
        AtomicTeleportMessage storage msg = atomicTeleportMessages[msgIds[i]];

        // Can only execute if Pending
        require(msg.status == MessageStatus.Pending, "Invalid status");

        // Must not be expired
        require(block.timestamp <= msg.expiration, "Message expired");

        msg.status = MessageStatus.Executed;
    }

    emit AtomicMessageStatusChangedBatch(msgIds, MessageStatus.Executed);
}

function revertAtomicMessageBatch(string[] calldata msgIds, ...) external {
    for (uint i = 0; i < msgIds.length; i++) {
        AtomicTeleportMessage storage msg = atomicTeleportMessages[msgIds[i]];

        // Can only revert if Pending
        require(msg.status == MessageStatus.Pending, "Invalid status");

        // No expiration check for revert (can revert anytime if pending)
        msg.status = MessageStatus.Reverted;
    }

    emit AtomicMessageStatusChangedBatch(msgIds, MessageStatus.Reverted);
}
```

## Complete Revert Examples

### Example 1: Blacklisted Recipient

**Scenario**: Alice tries to send 100 USDC to Bob, but Bob is blacklisted on destination chain

**Step 1: Alice Initiates Transfer**

```javascript
// Privacy Node A (origin)
const tx = await usdc.teleportAtomic(
    "0xBob...",                    // Bob's address
    ethers.parseUnits("100", 6),  // 100 USDC
    chainIdB                       // Privacy Node B
);

console.log("Transfer initiated:", tx.hash);
```

**Step 2: Asset Burned on Origin**

```solidity
// Alice's balance: 1000 USDC → 900 USDC
_burn(alice, 100 * 10**6);
```

**Step 3: Relayer A Submits to Private Network Hub**

```javascript
// Relayer detects TeleportInitiated event
const messageId = await endpoint.getMessage(tx.hash);
await teleportV1.storeAtomicMessageBatch([messageId]);

// Message status: Pending
// Expiration: now + 240 seconds
```

**Step 4: Relayer B Tries to Execute on Destination**

```solidity
// Privacy Node B (destination)
function receiveTeleportAtomic(address to, uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint");

    // Bob is blacklisted!
    require(!isBlacklisted(to), "Recipient is blacklisted");
    // ↑ Transaction reverts here
}
```

**Step 5: Relayer B Triggers Revert**

```javascript
// Relayer detects execution failure
try {
    await destEndpoint.executeMessage(messageId, payload);
} catch (error) {
    console.log("Execution failed:", error.message);

    // Report failure to Private Network Hub
    await teleportV1.revertAtomicMessageBatch([messageId], encryptedData);
}
```

**Step 6: Private Network Hub Updates Status**

```solidity
// TeleportV1 marks message as Reverted
message.status = MessageStatus.Reverted;
emit AtomicMessageStatusChangedBatch([messageId], MessageStatus.Reverted);
```

**Step 7: Relayer A Executes Revert on Origin**

```javascript
// Relayer A detects AtomicMessageStatusChangedBatch event
teleportV1.on("AtomicMessageStatusChangedBatch", async (msgIds, status) => {
    if (status === MessageStatus.Reverted) {
        // Execute revert payloads on origin chain
        for (const msgId of msgIds) {
            const message = await getMessageDetails(msgId);
            await originEndpoint.executeRevert(msgId, message.revertPayloadSender);
        }
    }
});
```

**Step 8: Asset Restored to Alice**

```solidity
// revertTeleportMint called on origin chain
function revertTeleportMint(address to, uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint");

    // Alice's balance: 900 USDC → 1000 USDC
    _mint(alice, 100 * 10**6);

    emit TeleportReverted(alice, 100 * 10**6, block.timestamp);
}
```

**Final State:**
- Alice: 1000 USDC (back to original)
- Bob: 0 USDC (never received)
- Message status: Reverted

### Example 2: Timeout Due to Offline Chain

**Scenario**: Destination chain goes offline during transfer

**Timeline:**

```
T=0:   Alice initiates transfer (1000 USDC)
T=5:   Message registered on Private Network Hub (expires at T=245)
T=10:  Relayer B tries to execute on destination
T=10:  Destination chain is offline (network error)
T=20:  Relayer B retries → still offline
T=40:  Relayer B retries → still offline
T=60:  Relayer B retries → still offline
...
T=240: Message expires
T=245: Relayer detects expiration
T=246: Relayer triggers automatic revert
T=250: Asset restored to Alice
```

**Relayer Logic:**

```javascript
async function processMessageWithTimeout(messageId) {
    const message = await teleportV1.atomicTeleportMessages(messageId);
    const deadline = message.expiration;

    // Try to execute until deadline
    while (Date.now() / 1000 < deadline) {
        try {
            await destinationEndpoint.executeMessage(messageId, payload);
            console.log("Execution succeeded");
            await teleportV1.executeAtomicMessageBatch([messageId], encryptedData);
            return 'success';
        } catch (error) {
            console.log("Execution failed, retrying in 10s...");
            await delay(10000);
        }
    }

    // Deadline reached, trigger revert
    console.log("Message expired, triggering revert");
    await teleportV1.revertAtomicMessageBatch([messageId], encryptedData);
    return 'reverted';
}
```

## Monitoring Reverts

### Event Tracking

```javascript
// Monitor all revert events
teleportV1.on("AtomicMessageStatusChangedBatch", (msgIds, newStatus) => {
    if (newStatus === MessageStatus.Reverted) {
        console.log(`⚠️  ${msgIds.length} messages reverted`);

        msgIds.forEach(async (msgId) => {
            const message = await teleportV1.atomicTeleportMessages(msgId);
            const reason = await determineRevertReason(message);

            console.log(`Message ${msgId}:`);
            console.log(`  - Reason: ${reason}`);
            console.log(`  - Started: ${new Date(message.startTime * 1000)}`);
            console.log(`  - Expired: ${new Date(message.expiration * 1000)}`);
        });
    }
});

// Determine revert reason
async function determineRevertReason(message) {
    const now = Math.floor(Date.now() / 1000);

    if (message.expiration < now) {
        return 'Timeout';
    } else {
        return 'Execution failure';
    }
}
```

### Revert Metrics

```javascript
class RevertMetrics {
    private metrics = {
        totalReverts: 0,
        timeoutReverts: 0,
        failureReverts: 0,
        revertRate: 0
    };

    recordRevert(reason: 'timeout' | 'failure') {
        this.metrics.totalReverts++;

        if (reason === 'timeout') {
            this.metrics.timeoutReverts++;
        } else {
            this.metrics.failureReverts++;
        }
    }

    calculateRevertRate(totalMessages: number) {
        this.metrics.revertRate =
            (this.metrics.totalReverts / totalMessages * 100);
    }

    getReport() {
        return {
            ...this.metrics,
            revertRate: this.metrics.revertRate.toFixed(2) + '%',
            timeoutRate: (this.metrics.timeoutReverts / this.metrics.totalReverts * 100).toFixed(2) + '%',
            failureRate: (this.metrics.failureReverts / this.metrics.totalReverts * 100).toFixed(2) + '%'
        };
    }
}
```

## Security Guarantees

### 1. Asset Conservation

**Mathematical Invariant:**

```
∀ message ∈ AtomicTeleport:
    (status = Pending ∧ asset ∈ burned_on_origin) ∨
    (status = Executed ∧ asset ∈ unlocked_on_destination) ∨
    (status = Reverted ∧ asset ∈ minted_on_origin)

Total Supply: constant across all states
```

### 2. No Double-Spend

**Proof:**
- Asset burned on origin before message created
- Destination mint is locked until confirmation
- Revert can only occur if status = Pending
- Once Executed, status cannot change to Reverted
- Once Reverted, status cannot change to Executed

### 3. No Asset Loss

**Proof:**
- Every message has timeout (240 seconds)
- After timeout, message can always be reverted
- Revert payload always restores asset to sender
- No intermediate state where asset is "lost"

### 4. Idempotency

Revert operations are idempotent:

```solidity
// Calling revert multiple times has same effect as calling once
function revertAtomicMessageBatch(string[] calldata msgIds, ...) external {
    for (uint i = 0; i < msgIds.length; i++) {
        AtomicTeleportMessage storage msg = atomicTeleportMessages[msgIds[i]];

        // Only change state if Pending
        require(msg.status == MessageStatus.Pending, "Invalid status");

        msg.status = MessageStatus.Reverted; // Idempotent: Reverted → Reverted
    }
}
```

## Best Practices

### 1. Monitor Revert Rates

```javascript
// Alert if revert rate exceeds threshold
if (revertMetrics.revertRate > 5) {
    console.warn(`⚠️  High revert rate: ${revertMetrics.revertRate}%`);
    // Investigate:
    // - Destination chain issues?
    // - Invalid recipient addresses?
    // - Contract bugs?
}
```

### 2. Handle Revert Notifications

```javascript
// Notify user of revert
async function notifyUserOfRevert(messageId, userAddress) {
    const message = await teleportV1.atomicTeleportMessages(messageId);

    if (message.status === MessageStatus.Reverted) {
        await sendNotification(userAddress, {
            type: 'revert',
            message: 'Your transfer was reverted and assets restored',
            messageId: messageId,
            timestamp: message.expiration
        });
    }
}
```

### 3. Test Revert Scenarios

```javascript
// Test suite for revert scenarios
describe("Atomic Revert", () => {
    it("should revert on blacklisted recipient", async () => {
        await token.teleportAtomic(blacklistedAddress, amount, destChain);
        // Wait for revert
        await waitForRevert(messageId);
        // Verify asset restored
        expect(await token.balanceOf(sender)).to.equal(originalBalance);
    });

    it("should revert on timeout", async () => {
        // Pause destination chain
        await destChain.pause();

        await token.teleportAtomic(recipient, amount, destChain);

        // Wait for timeout (240s)
        await time.increase(241);

        // Trigger manual revert
        await teleportV1.revertAtomicMessageBatch([messageId], encryptedData);

        // Verify asset restored
        expect(await token.balanceOf(sender)).to.equal(originalBalance);
    });
});
```

## Next Steps

- **[Cross-Chain Messaging](crosschain-messaging.md)** - Message lifecycle details
- **[Token Transfers](token-transfers.md)** - Standard-specific implementations
- **[Batch Processing](batch-processing.md)** - Optimize multiple transfers
- **[Smart Contracts Integration](../../../build/intermediate/endpoint-integration.md)** - Building with Atomic Teleport

## Additional Resources

- [Atomic Teleport Overview](overview.md)
- [State Machine Patterns](https://en.wikipedia.org/wiki/Finite-state_machine)
- [Atomic Transactions](https://en.wikipedia.org/wiki/Atomicity_(database_systems))
