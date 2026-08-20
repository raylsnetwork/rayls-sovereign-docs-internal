# Transaction Lifecycle

## Introduction

Understanding the complete lifecycle of a cross-chain transaction is essential for building robust applications on Rayls. This guide provides a comprehensive technical walkthrough of what happens when you initiate a cross-chain transaction, from the initial function call to final confirmation.

**What this guide covers:**

- Complete 6-phase transaction flow from source to destination
- Pre-flight validations and security checks
- Off-chain relayer operations
- Private Network Hub coordination
- Timing expectations and finality guarantees
- Failure modes and recovery mechanisms
- Monitoring and debugging strategies

!!! info "Prerequisites"
    - Read [EIP-5164 Explained](eip-5164-explained.md) for protocol foundations
    - Understand [Token Standards](token-standards.md) for teleport mechanisms
    - Know [Endpoint Integration](endpoint-integration.md) for security modifiers

**Key concept:**

A single `teleport()` call triggers a coordinated multi-phase flow across multiple chains. Each phase has specific responsibilities, timing characteristics, and potential failure modes.

---

## Overview: The Six Phases

```
Phase 0: Pre-flight Validations
    ↓
Phase 1: Source Chain Execution
    ↓
Phase 2: Relayer Transport (off-chain)
    ↓
Phase 3: Private Network Hub Coordination
    ↓
Phase 4: Destination Chain Execution
    ↓
Phase 5: Atomic Confirmation (if using teleportAtomic)
```

**Typical timing:**

- **Regular teleport**: 30-60 seconds total
- **Atomic teleport success**: 30-60 seconds
- **Atomic teleport with revert**: 60-90 seconds

Each phase is detailed below with actual contract code, timing expectations, and what can go wrong.

---

## Phase 0: Pre-flight Validations

Before any transaction executes, several validation checks must pass. These happen at contract call time and will cause immediate revert if they fail.

### Endpoint Authorization Check

**File**: `RaylsApp.sol:249-255`

```solidity
modifier receiveMethod() {
    require(
        endpoint.isTrustedExecutor(msg.sender),
        "This is a receive method. Only endpoint's executor can call this method."
    );
    _;
}
```

**What this validates:**

- Only the trusted MessageExecutor can call receive methods
- Prevents unauthorized cross-chain message injection
- Applied to all `receive*()` functions

**When it's checked:**

On destination chain when `receiveTeleport()` or `receiveTeleportAtomic()` is called.

---

### Parameter Validation

**File**: `RaylsErc20Handler.sol:153-175`

```solidity
function teleport(uint256 chainId, address to, uint256 value) public virtual returns (bool) {
    // Validation
    if (to == address(0) || value == 0 || chainId == 0) {
        revert RaylsErc20Handler__ZeroValueArg(to, value, chainId);
    }
    if (chainId == endpoint.getChainId()) {
        revert RaylsErc20Handler__WrongFunctionForSameChainId(chainId);
    }

    // ... execution continues
}
```

**What this validates:**

- Non-zero recipient address
- Non-zero transfer amount
- Non-zero destination chain ID
- Destination chain is different from source chain

**When it fails:**

Immediate revert on source chain before any state changes.

---

### Resource ID Resolution

**File**: `RaylsApp.sol:143-149`

```solidity
function _registerResourceId() internal virtual {
    require(
        resourceId != bytes32(0),
        "Only register resource when it's approved"
    );
    endpoint.registerResourceId(resourceId, address(this));
}
```

**What this enables:**

- Logical addressing across chains
- Contract upgradability without changing calling code
- Routing messages to correct destination contract

**How it's used:**

When sending to a resource ID instead of direct address, the endpoint resolves the current contract address on the destination chain.

For ERC-20 tokens the `resourceId` is not self-assigned: it is delivered by the Privacy Node's `PNTokenRegistryV1` via the `activateToken(bytes32,address,uint8)` callback, which calls `setResourceId(bytes32)` on the token after Hub approval. The generic no-argument `_registerResourceId()` above is used by non-token dApps that manage their own resource id.

See [EIP-5164 Explained - Resource IDs](eip-5164-explained.md) for details.

---

### Timing

**Phase 0 duration**: Instant (< 1 second)

These checks happen during transaction validation. If any fail, the transaction reverts immediately with no gas cost beyond validation.

---

## Phase 1: Source Chain Execution

Once pre-flight validations pass, the source chain executes the teleport logic. This involves burning/locking tokens and dispatching a cross-chain message.

### Step 1.1: Token Burn

**File**: `RaylsErc20Handler.sol:153-175`

```solidity
function teleport(uint256 chainId, address to, uint256 value) public virtual returns (bool) {
    // ... validations from Phase 0

    // Execute teleport logic
    _burn(msg.sender, value);

    // ... message dispatch continues
}
```

**What happens:**

- Tokens are burned from sender's balance on source chain
- Total supply decreases
- `Transfer` event emitted (from sender to `address(0)`)

**Why burn instead of lock:**

For cross-chain transfers, tokens are burned on source and minted on destination to maintain total supply across all chains. Each chain has independent token contracts.

---

### Step 1.2: Message Construction

**File**: `RaylsErc20Handler.sol:153-175`

```solidity
function teleport(uint256 chainId, address to, uint256 value) public virtual returns (bool) {
    // ... burn from Step 1.1

    BridgedTransferMetadata memory transferMetadata = BridgedTransferMetadata({
        assetType: RaylsBridgeableERC.ERC20,
        id: _erc20Identifier,
        from: msg.sender,
        tokenAddress: address(this),
        to: to,
        amount: value
    });

    // Prepare cross-chain transfer
    sendTeleport(
        chainId,
        abi.encodeWithSignature("receiveTeleport(address,uint256)", to, value),
        bytes(""),  // No lock data for regular teleport
        bytes(""),  // No revert data
        bytes(""),  // No revert data
        transferMetadata
    );

    return true;
}
```

**What's constructed:**

- **Payload**: Encoded function call for destination (`receiveTeleport(address,uint256)`)
- **Metadata**: Transfer details (asset type, amounts, addresses)
- **Destination chain ID**: Where message should be routed
- **Lock/revert payloads**: Empty for regular teleport (used in atomic)

---

### Step 1.3: Endpoint Dispatch

**File**: `RaylsApp.sol:51-57`

```solidity
function _raylsSend(
    uint256 _dstChainId,
    address _destination,
    bytes memory _payload
) internal virtual {
    endpoint.send(_dstChainId, _destination, _payload);
}
```

**What happens:**

The application calls the endpoint's `send()` method, which routes to the appropriate dispatcher based on chain type.

**File**: `RNMessageDispatcherV1.sol:85-90`

```solidity
function dispatchMessage(
    uint256 toChainId,
    address to,
    bytes calldata data
) external payable returns (bytes32 messageId) {
    messageId = keccak256(abi.encodePacked(block.chainid, msg.sender, to, toChainId, nonce[msg.sender]++));

    emit MessageDispatched(messageId, msg.sender, toChainId, to, data);
}
```

**What this does:**

- Generates unique `messageId` using hash of (chainId, sender, recipient, toChainId, nonce)
- Increments nonce for sender to prevent replay attacks
- Emits `MessageDispatched` event with all message details

**The messageId:**

```
messageId = keccak256(abi.encodePacked(
    block.chainid,     // Source chain ID
    msg.sender,        // Calling contract (token contract)
    to,                // Destination contract address
    toChainId,         // Destination chain ID
    nonce[msg.sender]  // Sender's current nonce
))
```

This `messageId` is critical - it's used for replay protection, tracking, and monitoring throughout all phases.

---

### Step 1.4: Event Emission

**Event emitted:**

```solidity
event MessageDispatched(
    bytes32 indexed messageId,
    address indexed from,
    uint256 indexed toChainId,
    address to,
    bytes data
);
```

**Why this matters:**

The off-chain relayer listens for this event to detect new cross-chain messages that need to be transported.

**What you can monitor:**

```typescript
// Listen for MessageDispatched events
const filter = dispatcher.filters.MessageDispatched();
dispatcher.on(filter, (messageId, from, toChainId, to, data) => {
    console.log("Message dispatched:", messageId);
    console.log("Destination chain:", toChainId);
    console.log("Destination contract:", to);
});
```

---

### Timing

**Phase 1 duration**: ~2-4 seconds

- Transaction submitted to source chain
- Validated and included in block
- Transaction mined and confirmed
- Events emitted and indexed

**What you see:**

```bash
# Check source chain after Phase 1
npx hardhat console --network privateledgera

> const token = await ethers.getContractAt("MyToken", tokenAddress)
> await token.balanceOf(senderAddress)
900000000000000000000n  # Decreased by 100 tokens ✅
```

At this point, tokens are burned on source but nothing has happened on destination yet.

---

## Phase 2: Relayer Transport (Off-Chain)

The relayer is an off-chain service that bridges on-chain events to cross-chain execution. This phase is entirely off-chain but critical to the flow.

### Step 2.1: Event Detection

**What the relayer does:**

```
1. Polls source chain for MessageDispatched events
2. Reads event data (messageId, destination, payload)
3. Validates message format and destination chain
```

**Polling interval:**

Typically 2-3 seconds, configurable based on relayer setup.

**What happens if relayer is down:**

- Message remains unprocessed
- No destination execution occurs
- Tokens are burned on source but not minted on destination
- **For atomic teleport**: No automatic recovery until relayer resumes
- **For regular teleport**: Manual intervention required

---

### Step 2.2: Message Packaging

**What the relayer prepares:**

```
Message package = {
    messageId: bytes32,
    fromChainId: uint256,
    from: address,
    toChainId: uint256,
    to: address,
    data: bytes
}
```

**Additional data (may include):**

- Merkle proofs for state verification (implementation-specific)
- Signatures for message authentication
- Gas price parameters for hub submission

---

### Step 2.3: Hub Submission

**What the relayer does:**

```
1. Constructs transaction to Private Network Hub
2. Calls RaylsMessageExecutorV1.executeMessage()
3. Pays gas for hub execution
4. Waits for hub confirmation
```

**Relayer gas considerations:**

- Relayer pays gas on hub chain
- Must maintain sufficient balance
- If out of gas, message delivery stalls

**Relayer monitoring:**

```bash
# Check relayer logs
docker logs rayls-relayer-1 --tail 50

# Look for:
[INFO] Detected MessageDispatched: 0x123abc...
[INFO] Submitting to hub: chainId=1001
[INFO] Hub transaction confirmed: 0x456def...
```

---

### Timing

**Phase 2 duration**: ~5-10 seconds

- Event detection: 2-3 seconds (polling interval)
- Message preparation: < 1 second
- Hub submission: 2-4 seconds (hub block time)
- Confirmation: 1-2 seconds

**Total Phase 2**: Typically 5-10 seconds, depends on polling frequency and hub block times.

---

## Phase 3: Private Network Hub Coordination

The Private Network Hub acts as a trusted coordinator, validating and routing messages between Privacy Node Ledgers.

### Step 3.1: Hub Message Validation

**File**: `RaylsMessageExecutorV1.sol:29-36`

```solidity
function executeMessage(
    uint256 fromChainId,
    address from,
    address to,
    bytes calldata data
) external payable returns (bytes32 messageId) {
    messageId = keccak256(abi.encodePacked(fromChainId, from, to, block.chainid, data));

    // Replay protection
    if (executed[messageId]) revert MessageIdAlreadyExecuted(messageId);
    executed[messageId] = true;

    // ... routing to destination
}
```

**What the hub validates:**

- Message has not been executed before (replay protection)
- Message format is correct
- Destination chain ID is valid
- Routing information is present

**Replay protection:**

The `executed` mapping tracks all processed `messageId` values. Attempting to execute the same message twice will revert.

---

### Step 3.2: Message Routing

**What the hub does:**

```
1. Marks message as executed (replay protection)
2. Routes message to destination chain relayer
3. Queues message for destination delivery
```

**Hub responsibilities:**

- Maintain message ordering (if required)
- Ensure exactly-once delivery semantics
- Handle destination chain unavailability (queue messages)

---

### Step 3.3: Destination Relayer Handoff

**What happens:**

The hub emits events or makes messages available for destination chain relayers to pick up. The destination relayer then submits to the destination Privacy Node Ledger.

**Architectural note:**

In some deployments, the same relayer handles both source→hub and hub→destination. In others, separate relayers may be used for each leg.

---

### Timing

**Phase 3 duration**: ~5-10 seconds

- Hub validation: < 1 second
- Replay check: < 1 second
- Routing and event emission: 2-4 seconds
- Destination relayer detection: 2-3 seconds

**Hub monitoring:**

```bash
# Check if hub executed the message
npx hardhat console --network commithub

> const executor = await ethers.getContractAt("RaylsMessageExecutorV1", hubExecutorAddress)
> await executor.executed(messageId)
true  # ✅ Hub processed it
```

If this returns `false` after 20 seconds, the hub hasn't received the message yet. Check relayer Phase 2.

---

## Phase 4: Destination Chain Execution

The destination Privacy Node Ledger executes the cross-chain message, calling the target contract's receive method.

### Step 4.1: Destination Relayer Detection

**What happens:**

Destination relayer monitors hub for messages destined for its chain, then submits execution transaction.

**Timing:**

Similar to Phase 2, typically 2-3 second polling interval plus transaction time.

---

### Step 4.2: MessageExecutor Execution

**File**: `MessageExecutor.sol:40-50`

```solidity
function executeMessage(
    uint256 fromChainId,
    address from,
    address to,
    bytes calldata data
) external payable returns (bytes32 messageId) {
    messageId = keccak256(abi.encodePacked(fromChainId, from, to, block.chainid, data));

    // Replay protection
    if (executed[messageId]) revert MessageIdAlreadyExecuted(messageId);
    executed[messageId] = true;

    // Execute message on destination
    _executeMessage(fromChainId, from, to, data);
}
```

**What this does:**

- Generates `messageId` from message parameters
- Checks replay protection (has this message been executed before?)
- Marks message as executed
- Calls internal `_executeMessage()` with context appending

---

### Step 4.3: Context Appending

**File**: `MessageExecutor.sol:61-80`

```solidity
function _executeMessage(
    uint256 fromChainId,
    address from,
    address to,
    bytes calldata data
) internal virtual {
    // Append context: messageId (32 bytes) + fromChainId (32 bytes) + from (32 bytes)
    bytes memory dataWithContext = abi.encodePacked(data, messageId, fromChainId, from);

    // Execute call to target contract
    (bool success,) = to.call{value: msg.value}(dataWithContext);

    if (!success) {
        // Handle failure based on atomic vs regular
    }
}
```

**The 84-byte context:**

```
Original data || messageId (32 bytes) || fromChainId (32 bytes) || from (32 bytes)
```

**Why context is appended:**

Allows receive methods to extract the original sender, source chain, and message ID without passing them as explicit parameters.

**How contracts extract context:**

**File**: `RaylsApp.sol:279-329`

```solidity
function _getMessageIdOnReceiveMethod() internal pure virtual returns (bytes32 messageId) {
    assembly {
        messageId := calldataload(sub(calldatasize(), 84))
    }
}

function _getFromChainIdOnReceiveMethod() internal pure virtual returns (uint256 fromChainId) {
    assembly {
        fromChainId := calldataload(sub(calldatasize(), 52))
    }
}

function _getMsgSenderOnReceiveMethod() internal pure virtual returns (address sender) {
    assembly {
        sender := shr(96, calldataload(sub(calldatasize(), 20)))
    }
}
```

See [Endpoint Integration - Context Extraction](endpoint-integration.md#cross-chain-context-extraction) for usage examples.

---

### Step 4.4: Target Contract Receive Method

**For regular teleport** (`RaylsErc20Handler.sol:367-369`):

```solidity
function receiveTeleport(address to, uint256 value) public virtual receiveMethod {
    _mint(to, value);
}
```

**What happens:**

- `receiveMethod` modifier validates caller is trusted executor
- Tokens minted directly to recipient
- Transfer complete

**For atomic teleport** (`RaylsErc20Handler.sol:375-380`):

```solidity
function receiveTeleportAtomic(address to, uint256 value) public virtual receiveMethod {
    _mint(owner(), value);  // Minted to owner (escrow)
    if (to != owner()) {
        _lock(to, value);   // Locked for recipient
    }
}
```

**What happens:**

- `receiveMethod` modifier validates caller
- Tokens minted to contract owner (escrow)
- Tokens locked for recipient (not yet transferred)
- Awaits Phase 5 confirmation

---

### Step 4.5: Execution Result

**If execution succeeds:**

- Message marked as executed
- Tokens minted (regular) or locked (atomic)
- Events emitted
- **For regular teleport**: Transfer complete (go to finality)
- **For atomic teleport**: Proceed to Phase 5

**If execution fails:**

- Message still marked as executed (prevents retry)
- Tokens NOT minted
- **For regular teleport**: Tokens lost (burned on source, not minted on destination) - manual recovery needed
- **For atomic teleport**: Automatic revert triggered (Phase 5 revert path)

---

### Timing

**Phase 4 duration**: ~8-12 seconds

- Destination relayer detection: 2-3 seconds
- Transaction submission: 2-4 seconds
- Contract execution: 1-2 seconds
- Confirmation: 2-3 seconds

**Destination monitoring:**

```bash
# Check if destination executed the message
npx hardhat console --network privateledgerb

> const executor = await ethers.getContractAt("MessageExecutor", destExecutorAddress)
> await executor.executed(messageId)
true  # ✅ Destination processed it

# Check if tokens were minted
> const token = await ethers.getContractAt("MyToken", tokenAddress)
> await token.balanceOf(recipientAddress)
100000000000000000000n  # ✅ Tokens received (regular teleport)
```

---

## Phase 5: Atomic Confirmation

This phase only applies when using `teleportAtomic()`. It provides automatic revert on failure or final unlock on success.

!!! info "Complete Atomic Teleport Documentation"
    This section covers the **transaction flow** perspective of atomic teleport. For comprehensive coverage:

    - **Complete mechanism**: [Token Standards: Atomic Teleport 4-Payload System](token-standards.md#how-it-works-four-payloads) - Canonical reference
    - **Security analysis**: [Security: Atomic Transaction Security](security.md#atomic-transaction-security) - Lock/unlock security and attack prevention
    - **Testing scenarios**: [Testing: Vanilla vs Atomic Teleport](testing.md#vanilla-vs-atomic-teleport) - Test coverage and guarantees

### Success Path: Unlock

If Phase 4 succeeds, the confirmation payload unlocks tokens from escrow.

**File**: `RaylsErc20Handler.sol:427-435`

```solidity
function unlock(address to, uint256 value) public virtual receiveMethod {
    _unlock(to, value);
    if (to != owner()) {
        _transfer(owner(), to, value);
    }
}
```

**What happens:**

1. Unlock called via cross-chain message (payload 2 from atomic teleport)
2. Tokens unlocked from escrow
3. Tokens transferred from owner to recipient
4. **Transfer complete**

**Timing:**

Additional ~30-40 seconds for unlock message to route through hub and execute on destination (same flow as Phase 1-4).

**Total atomic success time**: ~60-80 seconds (initial mint + unlock)

---

### Failure Path: Automatic Revert

If Phase 4 fails (e.g., `receiveTeleportAtomic()` reverts), the revert payload refunds the sender.

**File**: `RaylsErc20Handler.sol:382-384`

```solidity
function revertTeleportMint(address to, uint256 value) public virtual receiveMethod {
    _mint(to, value);  // Refund to original sender
}
```

**What happens:**

1. Destination execution fails
2. Hub detects failure
3. Revert payload (payload 3) executed on source chain
4. Tokens minted back to original sender
5. **Sender refunded**

**Timing:**

Revert detection + message routing back to source: ~30-50 seconds

**Total atomic failure time**: ~60-90 seconds (attempt + revert)

**User experience:**

```bash
# After 90 seconds, check sender balance on source chain
npx hardhat console --network privateledgera

> await token.balanceOf(senderAddress)
1000000000000000000000n  # ✅ Refunded (back to original balance)
```

---

### Why Use Atomic

**Comparison:**

| Transaction Type | Success Time | Failure Outcome | Recovery |
|-----------------|--------------|-----------------|----------|
| **Regular teleport** | ~30-40s | Tokens burned, not minted | Manual intervention required |
| **Atomic teleport** | ~60-80s | Automatic refund | No action needed ✅ |

**Recommendation:**

Always use `teleportAtomic()` in production unless you have specific reasons to use regular teleport and a manual recovery process in place.

---

### Timing

**Phase 5 duration**: ~30-50 seconds

- Message routing back through hub: ~15-20 seconds
- Execution on source/destination: ~10-15 seconds
- Confirmation: ~5-10 seconds

**Phase 5 monitoring:**

Check for unlock/revert events on the respective chains to confirm completion.

---

## Timing and Finality Expectations

### Typical Timeline Breakdown

**Regular teleport (success):**

```
Phase 0: Pre-flight validations           < 1s
Phase 1: Source chain execution           2-4s
Phase 2: Relayer transport (off-chain)    5-10s
Phase 3: Hub coordination                 5-10s
Phase 4: Destination execution            8-12s
                                          ────────
TOTAL:                                    30-40 seconds
```

**Atomic teleport (success):**

```
Phase 0-4: Initial transfer               30-40s
Phase 5: Unlock confirmation              30-40s
                                          ────────
TOTAL:                                    60-80 seconds
```

**Atomic teleport (failure + revert):**

```
Phase 0-4: Attempt (fails at Phase 4)     30-40s
Phase 5: Revert execution                 30-50s
                                          ────────
TOTAL:                                    60-90 seconds
```

---

### Finality Guarantees

**Source chain finality:**

After Phase 1 completes (~2-4s), tokens are burned. This is final and cannot be undone (unless atomic revert triggers).

**Destination chain finality:**

- **Regular teleport**: After Phase 4 completes (~30-40s total)
- **Atomic teleport**: After Phase 5 completes (~60-80s total)

**What "finality" means:**

- Tokens minted on destination
- Transaction will not be reverted by chain reorganization
- Recipient can use tokens
- Transfer is considered complete

---

### Factors That Affect Timing

**Faster:**

- Dedicated relayer with fast polling (1s instead of 3s)
- Low network congestion
- Optimized gas prices
- Pre-warmed relayer connections

**Slower:**

- Shared relayer with conservative polling (5s+)
- Network congestion on any chain in the flow
- Low gas price settings causing transaction delays
- Relayer queue backlog

**Realistic expectations:**

- **Best case**: 20-30 seconds (regular teleport)
- **Typical case**: 30-60 seconds (regular), 60-90 seconds (atomic)
- **Slow case**: 90-120 seconds (network congestion or relayer delays)

**When to investigate:**

If a transaction hasn't completed after 2 minutes, start debugging (see Monitoring section below).

---

## Failure Modes and Recovery

Understanding failure modes helps you build resilient applications and handle edge cases.

### Failure Mode 1: Destination Execution Reverts

**What happens:**

Phase 4 fails - the destination contract's receive method reverts (e.g., recipient is blacklisted, contract logic rejects transfer).

**Outcome:**

- **Regular teleport**: Tokens burned on source, NOT minted on destination → **Tokens lost**
- **Atomic teleport**: Automatic revert executes → **Sender refunded**

**How to detect:**

```bash
# Check destination executor
> await executor.executed(messageId)
true  # Message was executed

# But tokens not received
> await token.balanceOf(recipient)
0n  # No tokens ❌
```

**Recovery:**

- **Regular teleport**: Manual intervention required (admin mint, governance vote, or protocol-specific recovery)
- **Atomic teleport**: Wait for automatic revert (~60-90s total)

**Prevention:**

- Use `teleportAtomic()` in production
- Test receive methods thoroughly
- Handle edge cases in contract logic (blacklists, pauses, etc.)

---

### Failure Mode 2: Relayer Offline

**What happens:**

Phase 2 or Phase 3 fails - the relayer is not running or cannot submit transactions.

**Outcome:**

- Source chain execution completes (Phase 1)
- Tokens burned on source
- Message never reaches hub or destination
- Transaction stalled indefinitely

**How to detect:**

```bash
# Source shows message dispatched
> const filter = dispatcher.filters.MessageDispatched(messageId)
> const events = await dispatcher.queryFilter(filter)
> events.length
1  # ✅ Message dispatched

# But hub shows not executed
> await hubExecutor.executed(messageId)
false  # ❌ Hub hasn't received it

# Check relayer
$ docker ps | grep relayer
# No output = relayer not running
```

**Recovery:**

- Start the relayer
- Relayer will catch up and process pending messages
- No manual intervention needed (if using atomic)

**Prevention:**

- Monitor relayer health continuously
- Set up relayer redundancy (multiple relayers)
- Use alerting for relayer downtime

---

### Failure Mode 3: Invalid Destination Address

**What happens:**

Pre-flight validation (Phase 0) or Phase 4 fails - the destination address is invalid or doesn't exist.

**Outcome:**

- **If caught in Phase 0**: Transaction reverts on source chain, no state changes
- **If not caught until Phase 4**: Same as Failure Mode 1 (execution reverts on destination)

**How to detect:**

```typescript
// Phase 0 revert - immediate error
try {
    await token.teleport(chainIdB, INVALID_ADDRESS, amount)
} catch (error) {
    console.error("Pre-flight validation failed:", error)
    // RaylsErc20Handler__ZeroValueArg or similar
}
```

**Recovery:**

- **Phase 0 failure**: No recovery needed, transaction didn't execute
- **Phase 4 failure**: Same as Failure Mode 1

**Prevention:**

- Validate addresses before calling teleport
- Use address whitelisting in your application
- Implement address format checks

---

### Failure Mode 4: Insufficient Gas for Hub/Destination

**What happens:**

Phase 2 or Phase 4 fails - the relayer runs out of gas funds on hub or destination chain.

**Outcome:**

- Message dispatched on source
- Relayer attempts submission but transaction fails due to insufficient gas
- Message remains unprocessed until relayer is funded

**How to detect:**

```bash
# Check relayer logs
$ docker logs rayls-relayer-1 | grep -i "insufficient"
[ERROR] Insufficient funds for gas: required 0.1 ETH, have 0.05 ETH

# Hub shows not executed
> await hubExecutor.executed(messageId)
false  # ❌ Hub hasn't received it
```

**Recovery:**

- Fund the relayer account on the relevant chain
- Relayer will automatically retry pending messages
- No manual message resubmission needed

**Prevention:**

- Monitor relayer gas balances
- Set up auto-funding or alerts when balance drops below threshold
- Use gas price estimation to predict funding needs

---

## Monitoring Your Transaction

Effective monitoring helps you track transaction progress and diagnose issues quickly.

### Method 1: On-Chain Events

**Source chain - MessageDispatched:**

```typescript
// Listen for dispatch
const dispatcher = await ethers.getContractAt("RNMessageDispatcherV1", dispatcherAddress)
const filter = dispatcher.filters.MessageDispatched()

dispatcher.on(filter, (messageId, from, toChainId, to, data) => {
    console.log("✅ Phase 1 complete: Message dispatched")
    console.log("Message ID:", messageId)
    console.log("Destination:", toChainId, to)
})
```

**Destination chain - MessageExecuted:**

```typescript
// Listen for execution (if your contract emits this)
const executor = await ethers.getContractAt("MessageExecutor", executorAddress)
// Note: MessageExecutor may not emit events - check your implementation

// Alternative: listen for token Transfer events
const token = await ethers.getContractAt("MyToken", tokenAddress)
const filter = token.filters.Transfer(null, recipient)

token.on(filter, (from, to, value) => {
    console.log("✅ Phase 4 complete: Tokens minted")
    console.log("Recipient:", to)
    console.log("Amount:", value.toString())
})
```

---

### Method 2: Executor State Queries

**Check hub execution:**

```typescript
const hubExecutor = await ethers.getContractAt("RaylsMessageExecutorV1", hubExecutorAddress)
const isExecuted = await hubExecutor.executed(messageId)

if (isExecuted) {
    console.log("✅ Phase 3 complete: Hub processed message")
} else {
    console.log("⏳ Phase 2-3: Message not yet at hub")
}
```

**Check destination execution:**

```typescript
const destExecutor = await ethers.getContractAt("MessageExecutor", destExecutorAddress)
const isExecuted = await destExecutor.executed(messageId)

if (isExecuted) {
    console.log("✅ Phase 4 complete: Destination processed message")
    // Now check if tokens were actually minted (execution could have reverted)
} else {
    console.log("⏳ Phase 3-4: Message not yet at destination")
}
```

---

### Method 3: Balance Verification

**Source chain:**

```typescript
const sourceToken = await ethers.getContractAt("MyToken", sourceTokenAddress)
const balance = await sourceToken.balanceOf(sender)

if (balance < originalBalance) {
    console.log("✅ Phase 1 complete: Tokens burned on source")
}
```

**Destination chain:**

```typescript
const destToken = await ethers.getContractAt("MyToken", destTokenAddress)
const balance = await destToken.balanceOf(recipient)

if (balance > 0) {
    console.log("✅ Transfer complete: Tokens received on destination")
} else {
    console.log("⏳ Awaiting destination mint")
}
```

---

### Method 4: Relayer Logs

**View logs:**

```bash
# Real-time monitoring
docker logs -f rayls-relayer-1

# Last 100 lines
docker logs rayls-relayer-1 --tail 100

# Filter for specific message
docker logs rayls-relayer-1 | grep "0x123abc..."
```

**What to look for:**

```
[INFO] Detected MessageDispatched: 0x123abc...           ← Phase 2 started
[INFO] Submitting to hub: chainId=1001                   ← Phase 2 in progress
[INFO] Hub transaction confirmed: 0x456def...            ← Phase 3 complete
[INFO] Detected hub message for chain 1002               ← Phase 4 starting
[INFO] Destination transaction confirmed: 0x789ghi...    ← Phase 4 complete
```

**Error patterns:**

```
[ERROR] Insufficient funds for gas                       ← Relayer needs funding
[ERROR] RPC connection failed                            ← Network connectivity issue
[WARN] Transaction pending for 60s                       ← Network congestion
```

---

### Monitoring Best Practices

**1. Track the messageId:**

Always save the `messageId` from the source transaction - it's the key to tracing the entire flow.

```typescript
const tx = await token.teleport(chainIdB, recipient, amount)
const receipt = await tx.wait()
const dispatchEvent = receipt.events?.find(e => e.event === 'MessageDispatched')
const messageId = dispatchEvent?.args?.messageId

// Save this for monitoring
await database.saveMessageId(messageId, { source: chainIdA, dest: chainIdB, sender, recipient, amount })
```

**2. Implement progressive monitoring:**

```typescript
async function monitorTeleport(messageId, timeout = 120000) {
    const start = Date.now()

    // Phase 1: Already complete if we have messageId
    console.log("✅ Phase 1: Source execution complete")

    // Phase 3: Check hub
    while (Date.now() - start < timeout) {
        const hubExecuted = await hubExecutor.executed(messageId)
        if (hubExecuted) {
            console.log("✅ Phase 3: Hub processed message")
            break
        }
        await sleep(5000)  // Check every 5s
    }

    // Phase 4: Check destination
    while (Date.now() - start < timeout) {
        const destExecuted = await destExecutor.executed(messageId)
        if (destExecuted) {
            console.log("✅ Phase 4: Destination processed message")

            // Verify tokens received
            const balance = await destToken.balanceOf(recipient)
            if (balance > 0) {
                console.log("✅ Transfer complete")
                return true
            } else {
                console.log("❌ Execution reverted - tokens not minted")
                return false
            }
        }
        await sleep(5000)
    }

    console.log("❌ Timeout - transaction did not complete")
    return false
}
```

**3. Set up alerts:**

```typescript
// Alert if transaction takes too long
if (Date.now() - start > 90000) {  // 90 seconds
    sendAlert("Transaction exceeding expected time", { messageId })
}

// Alert on relayer issues
if (!await isRelayerHealthy()) {
    sendAlert("Relayer health check failed", { timestamp: Date.now() })
}
```

---

## Can You Now...?

Test your understanding before proceeding:

- [ ] **Trace a cross-chain token transfer** through all six lifecycle phases?
  - *Can you describe what happens in each phase from pre-flight to finality?*

- [ ] **Explain proposal execution** on the destination chain?
  - *What role does the MessageExecutor play? How is context appended?*

- [ ] **Identify where token locking/burning** occurs in the flow?
  - *Which phase handles token state changes on source vs destination?*

- [ ] **Understand relayer responsibilities** in Phase 2?
  - *What happens if the relayer is offline? How does it affect the transaction?*

- [ ] **Recognize atomic vs regular teleport** timing differences?
  - *Why does atomic take longer? What are the trade-offs?*

- [ ] **Debug a stuck transaction** using phase-by-phase monitoring?
  - *How would you check which phase a transaction is stuck in?*

If you answered "no" to any question, review the relevant sections above. Understanding the complete lifecycle is essential for debugging cross-chain issues and setting appropriate expectations.

---

## Summary

### Key Takeaways

**Six phases:**

1. **Phase 0**: Pre-flight validations (instant)
2. **Phase 1**: Source chain execution (2-4s)
3. **Phase 2**: Relayer transport (5-10s)
4. **Phase 3**: Hub coordination (5-10s)
5. **Phase 4**: Destination execution (8-12s)
6. **Phase 5**: Atomic confirmation (30-50s, atomic only)

**Timing expectations:**

- Regular teleport: 30-60 seconds
- Atomic teleport success: 60-80 seconds
- Atomic teleport revert: 60-90 seconds

**Failure resilience:**

- Always use `teleportAtomic()` in production
- Monitor relayer health continuously
- Implement progressive monitoring with messageId tracking
- Set timeouts to 120+ seconds before considering failed

**Monitoring approach:**

- Track `messageId` from source transaction
- Query `executed` mappings on hub and destination
- Verify balances on both chains
- Monitor relayer logs for transport issues

---

### Production Checklist

- [ ] Use `teleportAtomic()` for all cross-chain transfers
- [ ] Implement messageId tracking and storage
- [ ] Set up progressive monitoring (hub → destination → balance)
- [ ] Configure alerting for transactions exceeding 90 seconds
- [ ] Monitor relayer health and gas balances
- [ ] Test failure scenarios (reverts, relayer downtime)
- [ ] Set application timeouts to 120+ seconds
- [ ] Implement graceful error handling and user notifications

---

### Related Documentation

**For protocol details:**

- [EIP-5164 Explained](eip-5164-explained.md) - Message protocol internals
- [Token Standards](token-standards.md) - Atomic mechanism implementation
- [Endpoint Integration](endpoint-integration.md) - Security modifiers and context extraction

**For development:**

- [Testing Guide](../reference/testing-guide.md) - Test cross-chain flows
- [Best Practices](../reference/best-practices.md) - Production guidelines

---

You now have a complete understanding of the cross-chain transaction lifecycle on Rayls. Use this knowledge to build robust monitoring, handle failures gracefully, and set appropriate expectations for transaction finality.

Ready to implement testing? See [Testing Guide](../reference/testing-guide.md) next.
