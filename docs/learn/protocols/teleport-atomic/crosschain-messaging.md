# Cross-Chain Messaging

Learn how messages flow through the Atomic Teleport system, from initiation to final settlement or rollback.

## Message Lifecycle

Every atomic teleport goes through a well-defined lifecycle with three possible terminal states:

```
[Origin Chain]
      ↓ teleportAtomic()
[Private Network Hub: PENDING]
      ↓
   Decision Point
      ↓
   Success? ──Yes→ [EXECUTED] → Unlock on destination
      ↓
     No
      ↓
[REVERTED] → Restore on origin
```

## Complete Message Flow

### Step 1: Initiation (Origin Chain)

**User Action:**

```javascript
// Privacy Node A (origin)
const tx = await token.teleportAtomic(
    recipientAddress,    // 0xBob...
    amount,              // 100 * 10^18
    destinationChainId   // Chain ID of Privacy Node B
);
```

**Contract Processing:**

```solidity
function teleportAtomic(address to, uint256 value, uint256 chainId) {
    // 1. Burn asset
    _burn(msg.sender, value);

    // 2. Build payloads
    bytes memory executePayload = abi.encodeWithSignature(
        "receiveTeleportAtomic(address,uint256)",
        to,
        value
    );

    bytes memory unlockPayload = abi.encodeWithSignature(
        "unlock(address,uint256)",
        to,
        value
    );

    bytes memory revertSender = abi.encodeWithSignature(
        "revertTeleportMint(address,uint256)",
        msg.sender,
        value
    );

    bytes memory revertReceiver = abi.encodeWithSignature(
        "revertTeleportBurn(uint256)",
        value
    );

    // 3. Send via endpoint
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

**Event Emitted:**

```solidity
event TeleportInitiated(
    string indexed messageId,
    address indexed sender,
    uint256 amount,
    uint256 destinationChain,
    address recipient,
    uint256 timestamp
);
```

### Step 2: Relayer Detection (Origin Chain → Private Network Hub)

**Relayer A Monitors:**

```javascript
// Relayer service running on Origin Chain
endpoint.on("TeleportInitiated", async (messageId, sender, amount, destChain, recipient) => {
    console.log("Detected teleport:", messageId);

    // 1. Fetch message details
    const message = await endpoint.getMessage(messageId);

    // 2. Fetch recipient's public key from ParticipantStorage
    const recipientKey = await participantStorage.getPublicKey(destChain);

    // 3. Encrypt message payloads
    const encrypted = encryptPayloads(message, recipientKey);

    // 4. Submit to Private Network Hub
    await hubEndpoint.submitAtomicMessage(encrypted);
});
```

**Encryption Process:**

```javascript
function encryptPayloads(message, publicKey) {
    const plaintext = {
        messageId: message.id,
        executePayload: message.executePayload,
        unlockPayload: message.unlockPayload,
        revertSender: message.revertSender,
        revertReceiver: message.revertReceiver,
        metadata: message.metadata
    };

    // ML-KEM + AES-GCM encryption
    return encrypt(JSON.stringify(plaintext), sharedSecret);
}
```

### Step 3: Registration (Private Network Hub)

**TeleportV1 Receives Message:**

```solidity
function storeAtomicMessageBatch(string[] calldata msgIds) {
    for (uint256 i = 0; i < msgIds.length; i++) {
        AtomicTeleportMessage storage msg = atomicTeleportMessages[msgIds[i]];

        msg.startTime = block.timestamp;
        msg.expiration = block.timestamp + LOCK_TIME; // +240 seconds
        msg.status = MessageStatus.Pending;

        emit AtomicMessageTeleportStarted(
            msgIds[i],
            msg.startTime,
            msg.expiration
        );
    }
}
```

**Message State:**

```javascript
{
    messageId: "0x1a2b3c...",
    startTime: 1699564800,      // Unix timestamp
    expiration: 1699565040,     // startTime + 240 seconds
    status: "Pending",
    encryptedPayload: "0x...",  // Only destination can decrypt
    sourceChain: 12345,
    destinationChain: 12346
}
```

### Step 4: Destination Detection (Private Network Hub → Destination Chain)

**Relayer B Monitors:**

```javascript
// Relayer service for Destination Chain
teleportV1.on("AtomicMessageTeleportStarted", async (msgId, startTime, expiration) => {
    // 1. Fetch encrypted message
    const encrypted = await teleportV1.getMessage(msgId);

    // 2. Decrypt with private key
    const decrypted = decrypt(encrypted, privateKey);

    // 3. Parse payloads
    const message = JSON.parse(decrypted);

    // 4. Execute on destination chain
    try {
        await destinationEndpoint.executeMessage(
            message.messageId,
            message.executePayload
        );
        // If successful → report success to Private Network Hub
        successfulMessages.push(msgId);
    } catch (error) {
        // If failed → report failure to Private Network Hub
        failedMessages.push(msgId);
    }
});
```

### Step 5A: Success Path - Execution

**Destination Chain Execution:**

```solidity
// receiveTeleportAtomic called on destination token
function receiveTeleportAtomic(address to, uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint");

    // Mint to contract owner (temporary)
    _mint(owner(), value);

    // Lock for recipient
    if (to != owner()) {
        _lock(to, value);
    }

    emit TeleportReceived(to, value, block.timestamp);
}
```

**Relayer B Reports Success:**

```javascript
// Submit batch of successful messages
await teleportV1.executeAtomicMessageBatch(successfulMessages, encryptedData);
```

**TeleportV1 Updates Status:**

```solidity
function executeAtomicMessageBatch(string[] calldata msgIds, string calldata encryptedData) {
    for (uint i = 0; i < msgIds.length; i++) {
        AtomicTeleportMessage storage msg = atomicTeleportMessages[msgIds[i]];

        require(msg.status == MessageStatus.Pending, "Invalid status");
        require(block.timestamp <= msg.expiration, "Expired");

        msg.status = MessageStatus.Executed;
    }

    emit AtomicMessageStatusChangedBatch(msgIds, MessageStatus.Executed);
}
```

**Unlock on Destination:**

```solidity
// Endpoint calls unlock on destination token
function unlock(address to, uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint");

    bool success = _unlock(to, value);
    require(success, "Unlock failed");

    // Transfer from owner to recipient
    _transfer(owner(), to, value);

    emit TeleportCompleted(to, value, block.timestamp);
}
```

### Step 5B: Failure Path - Revert

**Destination Chain Fails:**

```solidity
// receiveTeleportAtomic reverts
function receiveTeleportAtomic(address to, uint256 value) external {
    require(to != blacklistedAddress, "Recipient not allowed");
    // ↑ Transaction reverts here
}
```

**Relayer B Reports Failure:**

```javascript
// Submit batch of failed messages
await teleportV1.revertAtomicMessageBatch(failedMessages, encryptedData);
```

**TeleportV1 Updates Status:**

```solidity
function revertAtomicMessageBatch(string[] calldata msgIds, string calldata encryptedData) {
    for (uint i = 0; i < msgIds.length; i++) {
        AtomicTeleportMessage storage msg = atomicTeleportMessages[msgIds[i]];

        require(msg.status == MessageStatus.Pending, "Invalid status");

        msg.status = MessageStatus.Reverted;
    }

    emit AtomicMessageStatusChangedBatch(msgIds, MessageStatus.Reverted);
}
```

**Revert on Origin:**

```solidity
// Endpoint calls revertTeleportMint on origin token
function revertTeleportMint(address to, uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint");

    // Restore asset to original sender
    _mint(to, value);

    emit TeleportReverted(to, value, block.timestamp);
}
```

## Message Tracking

### Query Message Status

**On Private Network Hub:**

```javascript
// Check message status
const message = await teleportV1.atomicTeleportMessages(messageId);

console.log("Status:", message.status);
// 0 = Pending
// 1 = Executed
// 2 = Rejected (not used)
// 3 = Reverted

console.log("Start Time:", new Date(message.startTime * 1000));
console.log("Expiration:", new Date(message.expiration * 1000));
```

**Calculate Remaining Time:**

```javascript
function getRemainingTime(messageId) {
    const message = await teleportV1.atomicTeleportMessages(messageId);
    const now = Math.floor(Date.now() / 1000);

    if (message.status !== 0) { // Not pending
        return 0;
    }

    const remaining = message.expiration - now;
    return Math.max(0, remaining);
}

// Usage
const timeLeft = await getRemainingTime(messageId);
console.log(`${timeLeft} seconds remaining`);
```

## Timeout Handling

### Automatic Timeout Detection

**Relayer Monitoring:**

```javascript
// Check for expired messages every 10 seconds
setInterval(async () => {
    const now = Math.floor(Date.now() / 1000);

    // Query all pending messages
    const pendingMessages = await teleportV1.getPendingMessages();

    const expired = pendingMessages.filter(msg =>
        msg.expiration < now && msg.status === 0
    );

    if (expired.length > 0) {
        console.log(`Found ${expired.length} expired messages`);
        const msgIds = expired.map(m => m.id);

        // Trigger automatic revert
        await teleportV1.revertAtomicMessageBatch(msgIds, encryptedData);
    }
}, 10000);
```

### Timeout Workflow

```
Message created at T=0
    ↓
T=0 to T=240: Normal processing window
    ↓
T=240: Expiration reached
    ↓
Relayer detects expiration
    ↓
Automatic revert triggered
    ↓
Asset restored to origin
```

## Encryption and Privacy

### ML-KEM Key Agreement

**Key Agreement Setup:**

```javascript
// Each participant generates ML-KEM key pair
const viewKeyPair = crypto.generateMLKEMKeyPair768();

// Encapsulation key (public) stored on-chain (ParticipantStorage)
await participantStorage.setRaylsViewPublicKey(
    chainId,
    viewKeyPair.encapsulationKey
);

// Decapsulation key (private) kept secure off-chain
secureStore.save('rayls-view-secret-key', viewKeyPair.decapsulationKey);
```

### Message Encryption

**Encryption (Relayer A):**

```javascript
function encryptMessage(plaintext, sharedSecret) {
    // 1. Derive symmetric key from ML-KEM shared secret
    const encKey = hkdf(sha3_256, sharedSecret, 'Rayls');

    // 2. Encrypt plaintext
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', encKey, iv);

    let encrypted = cipher.update(plaintext, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    const authTag = cipher.getAuthTag();

    return {
        ciphertext: encrypted,
        iv: iv.toString('hex'),
        authTag: authTag.toString('hex')
    };
}
```

**Decryption (Relayer B):**

```javascript
function decryptMessage(encrypted, sharedSecret) {
    // 1. Derive symmetric key from ML-KEM shared secret
    const decKey = hkdf(sha3_256, sharedSecret, 'Rayls');

    // 2. Decrypt ciphertext
    const decipher = crypto.createDecipheriv(
        'aes-256-gcm',
        decKey,
        Buffer.from(encrypted.iv, 'hex')
    );

    decipher.setAuthTag(Buffer.from(encrypted.authTag, 'hex'));

    let plaintext = decipher.update(encrypted.ciphertext, 'hex', 'utf8');
    plaintext += decipher.final('utf8');

    return plaintext;
}
```

### Privacy Guarantees

**What's Encrypted:**
- Message payloads (execute, unlock, revert)
- Recipient address
- Amount being transferred
- Token contract address

**What's Public:**
- Message ID (hash)
- Source chain ID
- Destination chain ID
- Timestamp
- Status (Pending/Executed/Reverted)

## Error Handling

### Common Failure Scenarios

**1. Destination Chain Offline:**

```javascript
// Relayer cannot connect to destination
try {
    await destinationEndpoint.executeMessage(msgId, payload);
} catch (error) {
    if (error.code === 'NETWORK_ERROR') {
        // Retry later, will timeout if not resolved
        retryQueue.add(msgId, { delay: 30000 });
    }
}
```

**2. Insufficient Gas:**

```javascript
// Execution runs out of gas
try {
    await destinationEndpoint.executeMessage(msgId, payload, {
        gasLimit: 500000
    });
} catch (error) {
    if (error.code === 'OUT_OF_GAS') {
        // Report as failed, trigger revert
        await teleportV1.revertAtomicMessageBatch([msgId], encryptedData);
    }
}
```

**3. Invalid Recipient:**

```javascript
// Destination contract rejects recipient
function receiveTeleportAtomic(address to, uint256 value) {
    require(to != address(0), "Invalid recipient");
    require(!isBlacklisted(to), "Blacklisted");
    // If reverts → automatic revert flow
}
```

### Retry Logic

```javascript
class RelayerMessageProcessor {
    async processMessage(msgId) {
        const maxRetries = 3;
        let attempt = 0;

        while (attempt < maxRetries) {
            try {
                await this.executeOnDestination(msgId);
                return 'success';
            } catch (error) {
                attempt++;

                if (this.isRetryable(error) && attempt < maxRetries) {
                    await this.delay(5000 * attempt); // Exponential backoff
                    continue;
                }

                // Non-retryable or max retries reached
                return 'failed';
            }
        }
    }

    isRetryable(error) {
        const retryableCodes = [
            'NETWORK_ERROR',
            'TIMEOUT',
            'NONCE_TOO_LOW'
        ];
        return retryableCodes.includes(error.code);
    }
}
```

## Monitoring and Debugging

### Event Monitoring

```javascript
// Monitor all atomic teleport events
const teleportV1 = new ethers.Contract(address, abi, provider);

// Message started
teleportV1.on("AtomicMessageTeleportStarted", (msgId, startTime, expiration) => {
    console.log(`Message ${msgId} started`);
    console.log(`Expires at: ${new Date(expiration * 1000)}`);
});

// Status changed
teleportV1.on("AtomicMessageStatusChangedBatch", (msgIds, newStatus) => {
    const statusNames = ['Pending', 'Executed', 'Rejected', 'Reverted'];
    console.log(`Messages ${msgIds} → ${statusNames[newStatus]}`);
});
```

### Message Tracing

```javascript
async function traceMessage(messageId) {
    // 1. Origin chain
    const originTx = await originEndpoint.getInitiationTx(messageId);
    console.log("Initiated:", originTx.hash, "at block", originTx.blockNumber);

    // 2. Private Network Hub
    const commitMsg = await teleportV1.atomicTeleportMessages(messageId);
    console.log("Status:", commitMsg.status);
    console.log("Expires:", new Date(commitMsg.expiration * 1000));

    // 3. Destination chain (if executed)
    if (commitMsg.status === 1) {
        const destTx = await destEndpoint.getExecutionTx(messageId);
        console.log("Executed:", destTx.hash, "at block", destTx.blockNumber);
    }

    // 4. Calculate timeline
    const timeline = {
        initiated: originTx.timestamp,
        registered: commitMsg.startTime,
        completed: destTx?.timestamp || commitMsg.expiration,
        duration: (destTx?.timestamp || commitMsg.expiration) - originTx.timestamp
    };

    return timeline;
}
```

## Next Steps

- **[Token Transfers](token-transfers.md)** - Specific flows for ERC-20/721/1155
- **[Batch Processing](batch-processing.md)** - Optimizing multiple transfers
- **[Atomic Reverts](atomic-reverts.md)** - Deep dive on rollback mechanisms
- **[Smart Contracts Integration](../../../build/intermediate/endpoint-integration.md)** - Building with Atomic Teleport

## Additional Resources

- [Atomic Teleport Overview](overview.md)
- [ML-KEM (NIST FIPS 203)](https://csrc.nist.gov/pubs/fips/203/final)
- [Cross-Chain Communication Patterns](https://ethereum.org/en/developers/docs/bridges/)
