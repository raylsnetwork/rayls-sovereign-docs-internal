# Batch Processing

Learn how to optimize multiple atomic teleports using batch operations for improved gas efficiency and coordinated state changes.

## Overview

Batch processing allows multiple atomic teleports to be submitted, processed, and finalized together in a single transaction, providing significant gas savings and ensuring coordinated execution.

**Benefits:**
- **Gas Savings**: 30-40% reduction vs individual transfers
- **Coordinated Execution**: Multiple messages processed atomically
- **Simplified Operations**: Single transaction for multiple transfers
- **Consistent State**: All operations succeed or all revert together

## Batch Architecture

### Message Batching on Private Network Hub

**TeleportV1 Contract:**

```solidity
contract TeleportV1 {
    // Batch message storage
    function storeAtomicMessageBatch(string[] calldata msgIds) external {
        for (uint256 i = 0; i < msgIds.length; i++) {
            AtomicTeleportMessage storage msg = atomicTeleportMessages[msgIds[i]];

            msg.startTime = block.timestamp;
            msg.expiration = block.timestamp + LOCK_TIME; // 240 seconds
            msg.status = MessageStatus.Pending;

            emit AtomicMessageTeleportStarted(
                msgIds[i],
                msg.startTime,
                msg.expiration
            );
        }

        emit AtomicMessageTeleportStartedBatch(msgIds, block.timestamp + LOCK_TIME);
    }

    // Batch execution
    function executeAtomicMessageBatch(
        string[] calldata msgIds,
        string calldata encryptedData
    ) external {
        for (uint256 i = 0; i < msgIds.length; i++) {
            AtomicTeleportMessage storage msg = atomicTeleportMessages[msgIds[i]];

            require(msg.status == MessageStatus.Pending, "Invalid status");
            require(block.timestamp <= msg.expiration, "Expired");

            msg.status = MessageStatus.Executed;
        }

        emit AtomicMessageStatusChangedBatch(msgIds, MessageStatus.Executed);
        emit EncryptedAtomicDataBatch(encryptedData);
    }

    // Batch revert
    function revertAtomicMessageBatch(
        string[] calldata msgIds,
        string calldata encryptedData
    ) external {
        for (uint256 i = 0; i < msgIds.length; i++) {
            AtomicTeleportMessage storage msg = atomicTeleportMessages[msgIds[i]];

            require(msg.status == MessageStatus.Pending, "Invalid status");

            msg.status = MessageStatus.Reverted;
        }

        emit AtomicMessageStatusChangedBatch(msgIds, MessageStatus.Reverted);
        emit EncryptedAtomicDataBatch(encryptedData);
    }
}
```

## ERC-20 Batch Teleports

### Contract Implementation

```solidity
struct BatchTeleportPayloadRequest {
    address to;
    uint256 value;
    uint256 chainId;
}

function batchTeleportAtomic(
    BatchTeleportPayloadRequest[] calldata requests
) external {
    require(requests.length > 0, "Empty batch");
    require(requests.length <= 50, "Batch too large"); // Limit batch size

    ResourceIdCompletePayloadRequest[] memory payloadRequests =
        new ResourceIdCompletePayloadRequest[](requests.length);

    for (uint256 i = 0; i < requests.length; i++) {
        BatchTeleportPayloadRequest calldata request = requests[i];

        // 1. Burn each asset
        _burn(msg.sender, request.value);

        // 2. Build payloads for each transfer
        payloadRequests[i] = ResourceIdCompletePayloadRequest({
            _dstChainId: request.chainId,
            _resourceId: resourceId,
            _payload: abi.encodeWithSignature(
                "receiveTeleportAtomic(address,uint256)",
                request.to,
                request.value
            ),
            _lockData: abi.encodeWithSignature(
                "unlock(address,uint256)",
                request.to,
                request.value
            ),
            _revertDataSender: abi.encodeWithSignature(
                "revertTeleportMint(address,uint256)",
                msg.sender,
                request.value
            ),
            _revertDataReceiver: abi.encodeWithSignature(
                "revertTeleportBurn(uint256)",
                request.value
            ),
            transferMetadata: transferMetadata
        });
    }

    // 3. Send batch to endpoint
    endpoint.sendBatchTeleport(payloadRequests);

    emit BatchTeleportInitiated(msg.sender, requests.length, block.timestamp);
}
```

### Usage Example

**Scenario**: Transfer tokens to 10 different recipients on another chain

```javascript
// Prepare batch requests
const requests = [
    { to: "0xAlice...", value: ethers.parseEther("100"), chainId: chainIdB },
    { to: "0xBob...", value: ethers.parseEther("200"), chainId: chainIdB },
    { to: "0xCarol...", value: ethers.parseEther("150"), chainId: chainIdB },
    { to: "0xDave...", value: ethers.parseEther("300"), chainId: chainIdB },
    { to: "0xEve...", value: ethers.parseEther("250"), chainId: chainIdB },
    { to: "0xFrank...", value: ethers.parseEther("175"), chainId: chainIdB },
    { to: "0xGrace...", value: ethers.parseEther("225"), chainId: chainIdB },
    { to: "0xHeidi...", value: ethers.parseEther("125"), chainId: chainIdB },
    { to: "0xIvan...", value: ethers.parseEther("275"), chainId: chainIdB },
    { to: "0xJudy...", value: ethers.parseEther("325"), chainId: chainIdB }
];

// Execute batch teleport
const tx = await token.batchTeleportAtomic(requests);
console.log("Batch teleport initiated:", tx.hash);

// Wait for confirmation
const receipt = await tx.wait();
console.log(`Batch of ${requests.length} transfers submitted`);
```

### Gas Cost Analysis

**Individual Transfers:**
```
Transfer 1: ~200k gas
Transfer 2: ~200k gas
Transfer 3: ~200k gas
...
Transfer 10: ~200k gas
Total: ~2,000k gas (2M gas)
```

**Batch Transfer:**
```
Batch of 10: ~1,200k gas (1.2M gas)
Savings: ~800k gas (40% reduction)
Per-transfer cost: ~120k gas
```

**Why Cheaper?**
- Single transaction overhead (not 10)
- Shared calldata costs
- Optimized loop processing
- Batch event emission

## ERC-721 Batch Teleports

### Contract Implementation

```solidity
struct BatchNFTTeleportRequest {
    address to;
    uint256 tokenId;
    uint256 chainId;
}

function batchTeleportAtomic(
    BatchNFTTeleportRequest[] calldata requests
) external {
    require(requests.length > 0, "Empty batch");
    require(requests.length <= 50, "Batch too large");

    ResourceIdCompletePayloadRequest[] memory payloadRequests =
        new ResourceIdCompletePayloadRequest[](requests.length);

    for (uint256 i = 0; i < requests.length; i++) {
        BatchNFTTeleportRequest calldata request = requests[i];

        // Verify ownership
        require(ownerOf(request.tokenId) == msg.sender, "Not token owner");

        // Burn NFT
        _burn(request.tokenId);

        // Build payloads
        payloadRequests[i] = ResourceIdCompletePayloadRequest({
            _dstChainId: request.chainId,
            _resourceId: resourceId,
            _payload: abi.encodeWithSignature(
                "receiveTeleportAtomic(address,uint256)",
                request.to,
                request.tokenId
            ),
            _lockData: abi.encodeWithSignature(
                "unlock(address,uint256)",
                request.to,
                request.tokenId
            ),
            _revertDataSender: abi.encodeWithSignature(
                "revertTeleportMint(address,uint256)",
                msg.sender,
                request.tokenId
            ),
            _revertDataReceiver: abi.encodeWithSignature(
                "revertTeleportBurn(uint256)",
                request.tokenId
            ),
            transferMetadata: transferMetadata
        });
    }

    endpoint.sendBatchTeleport(payloadRequests);

    emit BatchNFTTeleportInitiated(msg.sender, requests.length, block.timestamp);
}
```

### Usage Example

**Scenario**: Migrate NFT collection between chains

```javascript
// Get all NFTs owned by user
const balance = await nft.balanceOf(myAddress);
const tokenIds = [];

for (let i = 0; i < balance; i++) {
    const tokenId = await nft.tokenOfOwnerByIndex(myAddress, i);
    tokenIds.push(tokenId);
}

// Prepare batch requests
const requests = tokenIds.map(tokenId => ({
    to: myAddress,
    tokenId: tokenId,
    chainId: destinationChain
}));

// Execute batch migration
const tx = await nft.batchTeleportAtomic(requests);
console.log(`Migrating ${requests.length} NFTs to chain ${destinationChain}`);

await tx.wait();
console.log("NFT collection migration initiated");
```

## ERC-1155 Native Batch Support

### Why ERC-1155 is Ideal for Batching

ERC-1155 has built-in batch support, making it the most efficient for multi-token operations:

```solidity
function batchTeleportAtomic(
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    uint256 chainId
) external {
    require(ids.length == amounts.length, "Length mismatch");
    require(ids.length > 0, "Empty batch");

    // Single burn for all token IDs
    _burnBatch(msg.sender, ids, amounts);

    // Build batch payloads
    bytes memory executePayload = abi.encodeWithSignature(
        "receiveBatchTeleportAtomic(address,uint256[],uint256[])",
        to,
        ids,
        amounts
    );

    bytes memory unlockPayload = abi.encodeWithSignature(
        "batchUnlock(address,uint256[],uint256[])",
        to,
        ids,
        amounts
    );

    bytes memory revertSender = abi.encodeWithSignature(
        "revertBatchTeleportMint(address,uint256[],uint256[])",
        msg.sender,
        ids,
        amounts
    );

    bytes memory revertReceiver = abi.encodeWithSignature(
        "revertBatchTeleportBurn(uint256[],uint256[])",
        ids,
        amounts
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

### Usage Example

**Scenario**: Transfer gaming inventory (multiple item types)

```javascript
// User's inventory: 50 swords, 25 shields, 10 potions
const tx = await gameItems.batchTeleportAtomic(
    playerAddress,
    [1, 2, 3],              // Token IDs: sword, shield, potion
    [50, 25, 10],           // Amounts
    gameServerChainId       // Destination
);

console.log("Inventory transfer initiated");
```

**Gas Comparison:**
```
Individual transfers (3): ~600k gas
Batch transfer (3): ~250k gas
Savings: 58%
```

## Relayer Batch Processing

### Relayer Aggregation Strategy

Relayers collect multiple messages before submitting to Private Network Hub:

```javascript
class BatchRelayer {
    private pendingMessages: Message[] = [];
    private batchSize = 20;
    private batchTimeout = 30000; // 30 seconds

    async collectMessage(message: Message) {
        this.pendingMessages.push(message);

        // Submit when batch is full OR timeout reached
        if (this.pendingMessages.length >= this.batchSize) {
            await this.submitBatch();
        } else if (this.pendingMessages.length === 1) {
            // Start timer on first message
            setTimeout(() => this.submitBatch(), this.batchTimeout);
        }
    }

    async submitBatch() {
        if (this.pendingMessages.length === 0) return;

        const batch = this.pendingMessages.splice(0, this.batchSize);
        const msgIds = batch.map(m => m.id);

        console.log(`Submitting batch of ${batch.length} messages`);

        // Submit to TeleportV1
        const tx = await teleportV1.storeAtomicMessageBatch(msgIds);
        await tx.wait();

        console.log(`Batch ${tx.hash} confirmed`);
    }
}
```

### Batch Execution on Destination

```javascript
class DestinationBatchProcessor {
    private successfulMessages: string[] = [];
    private failedMessages: string[] = [];

    async processMessages(messages: Message[]) {
        // Try to execute all messages
        for (const msg of messages) {
            try {
                await this.executeMessage(msg);
                this.successfulMessages.push(msg.id);
            } catch (error) {
                console.error(`Message ${msg.id} failed:`, error);
                this.failedMessages.push(msg.id);
            }
        }

        // Submit results in batches
        if (this.successfulMessages.length > 0) {
            await teleportV1.executeAtomicMessageBatch(
                this.successfulMessages,
                encryptedData
            );
        }

        if (this.failedMessages.length > 0) {
            await teleportV1.revertAtomicMessageBatch(
                this.failedMessages,
                encryptedData
            );
        }

        // Clear batches
        this.successfulMessages = [];
        this.failedMessages = [];
    }
}
```

## Batch Size Optimization

### Finding Optimal Batch Size

**Factors to Consider:**
1. **Gas Limit**: Block gas limit (~30M on most chains)
2. **Transaction Cost**: Marginal cost per additional item
3. **Timeout Risk**: Larger batches take longer to process
4. **Finality**: Confirmation time increases with batch size

**Recommended Batch Sizes:**

```javascript
const OPTIMAL_BATCH_SIZES = {
    ERC20: 50,      // ~1.2M gas for 50 transfers
    ERC721: 30,     // ~800k gas for 30 NFTs
    ERC1155: 20,    // ~600k gas for 20 multi-token transfers
};

function getOptimalBatchSize(tokenType: string): number {
    return OPTIMAL_BATCH_SIZES[tokenType] || 20;
}
```

### Dynamic Batch Sizing

Adjust batch size based on gas prices:

```javascript
async function calculateDynamicBatchSize(
    tokenType: string,
    gasPrice: bigint
): Promise<number> {
    const baseSize = OPTIMAL_BATCH_SIZES[tokenType];
    const maxGasPrice = ethers.parseUnits("100", "gwei");

    if (gasPrice > maxGasPrice) {
        // High gas: use larger batches for better amortization
        return Math.floor(baseSize * 1.5);
    } else {
        // Low gas: use standard batch size
        return baseSize;
    }
}
```

## Monitoring Batch Operations

### Batch Event Tracking

```javascript
// Monitor batch initiation
teleportV1.on("AtomicMessageTeleportStartedBatch", (msgIds, expiration) => {
    console.log(`Batch started: ${msgIds.length} messages`);
    console.log(`Expires at: ${new Date(expiration * 1000)}`);

    // Track each message ID
    msgIds.forEach(id => {
        batchTracker.set(id, {
            status: 'pending',
            expiration: expiration,
            batchSize: msgIds.length
        });
    });
});

// Monitor batch status changes
teleportV1.on("AtomicMessageStatusChangedBatch", (msgIds, newStatus) => {
    const statusName = ['Pending', 'Executed', 'Rejected', 'Reverted'][newStatus];
    console.log(`Batch status changed: ${msgIds.length} messages → ${statusName}`);

    // Update tracking
    msgIds.forEach(id => {
        const info = batchTracker.get(id);
        if (info) {
            info.status = statusName.toLowerCase();
            batchTracker.set(id, info);
        }
    });
});
```

### Batch Performance Metrics

```javascript
class BatchMetrics {
    private metrics = {
        totalBatches: 0,
        totalMessages: 0,
        successfulBatches: 0,
        failedBatches: 0,
        averageBatchSize: 0,
        averageGasCost: 0n,
        totalGasSaved: 0n
    };

    recordBatch(batchSize: number, gasUsed: bigint, success: boolean) {
        this.metrics.totalBatches++;
        this.metrics.totalMessages += batchSize;

        if (success) {
            this.metrics.successfulBatches++;
        } else {
            this.metrics.failedBatches++;
        }

        // Calculate averages
        this.metrics.averageBatchSize =
            this.metrics.totalMessages / this.metrics.totalBatches;

        this.metrics.averageGasCost =
            (this.metrics.averageGasCost * BigInt(this.metrics.totalBatches - 1) + gasUsed) /
            BigInt(this.metrics.totalBatches);

        // Calculate savings (assuming 200k gas per individual transfer)
        const individualCost = BigInt(batchSize) * 200000n;
        const savings = individualCost - gasUsed;
        this.metrics.totalGasSaved += savings;
    }

    getReport() {
        return {
            ...this.metrics,
            successRate: (this.metrics.successfulBatches / this.metrics.totalBatches * 100).toFixed(2) + '%',
            averageGasCost: this.metrics.averageGasCost.toString(),
            totalGasSaved: this.metrics.totalGasSaved.toString(),
            averageSavingsPerBatch: (this.metrics.totalGasSaved / BigInt(this.metrics.totalBatches)).toString()
        };
    }
}
```

## Error Handling in Batches

### Partial Failure Handling

**Problem**: What if 1 message in a batch of 50 fails?

**Solution**: Process successful and failed messages separately

```javascript
async function processBatchWithPartialFailure(messages: Message[]) {
    const successful: string[] = [];
    const failed: string[] = [];

    // Try each message individually
    for (const msg of messages) {
        try {
            await executeMessage(msg);
            successful.push(msg.id);
        } catch (error) {
            console.error(`Message ${msg.id} failed:`, error.message);
            failed.push(msg.id);
        }
    }

    // Submit results as separate batches
    if (successful.length > 0) {
        console.log(`Executing ${successful.length} successful messages`);
        await teleportV1.executeAtomicMessageBatch(successful, encryptedData);
    }

    if (failed.length > 0) {
        console.log(`Reverting ${failed.length} failed messages`);
        await teleportV1.revertAtomicMessageBatch(failed, encryptedData);
    }

    return {
        successful: successful.length,
        failed: failed.length,
        total: messages.length
    };
}
```

### Retry Logic for Failed Batches

```javascript
async function submitBatchWithRetry(
    msgIds: string[],
    maxRetries: number = 3
): Promise<boolean> {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            const tx = await teleportV1.storeAtomicMessageBatch(msgIds);
            await tx.wait();
            console.log(`Batch submitted successfully on attempt ${attempt}`);
            return true;
        } catch (error) {
            console.error(`Batch submission failed (attempt ${attempt}):`, error);

            if (attempt < maxRetries) {
                // Exponential backoff
                const delay = 1000 * Math.pow(2, attempt - 1);
                console.log(`Retrying in ${delay}ms...`);
                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
    }

    console.error(`Batch submission failed after ${maxRetries} attempts`);
    return false;
}
```

## Best Practices

### 1. Batch Size Management

```javascript
// ✅ Good: Reasonable batch size
await token.batchTeleportAtomic(requests.slice(0, 50));

// ❌ Bad: Batch too large, may exceed gas limit
await token.batchTeleportAtomic(requests.slice(0, 500));
```

### 2. Homogeneous Batches

```javascript
// ✅ Good: All messages to same destination chain
const batchToChainB = messages.filter(m => m.destChain === chainIdB);
await submitBatch(batchToChainB);

// ❌ Bad: Mixed destination chains in one batch
await submitBatch(allMessages); // Contains different chains
```

### 3. Timeout Awareness

```javascript
// ✅ Good: Process batch well before timeout
const PROCESSING_BUFFER = 60; // 60 seconds buffer
const deadline = message.expiration - PROCESSING_BUFFER;

if (Date.now() / 1000 < deadline) {
    await processBatch(messages);
}

// ❌ Bad: Process batch close to timeout
// Risk of expiration during processing
```

### 4. Gas Estimation

```javascript
// ✅ Good: Estimate gas before submission
const estimatedGas = await token.estimateGas.batchTeleportAtomic(requests);
console.log(`Estimated gas: ${estimatedGas.toString()}`);

if (estimatedGas < 5000000n) { // 5M gas limit
    await token.batchTeleportAtomic(requests);
}

// ❌ Bad: Submit without estimation
// May fail due to insufficient gas
```

## Next Steps

- **[Atomic Reverts](atomic-reverts.md)** - Deep dive on rollback mechanisms
- **[Cross-Chain Messaging](crosschain-messaging.md)** - Message lifecycle details
- **[Token Transfers](token-transfers.md)** - Standard-specific implementations
- **[Smart Contracts Integration](../../../build/intermediate/endpoint-integration.md)** - Building with batches

## Additional Resources

- [Atomic Teleport Overview](overview.md)
- [Ethereum Gas Optimization](https://ethereum.org/en/developers/docs/gas/)
- [Batch Processing Patterns](https://docs.soliditylang.org/en/latest/common-patterns.html)
