# Security

## Introduction

Security is paramount in cross-chain systems where assets move across multiple trust boundaries. Rayls implements enterprise-grade security through defense in depth—multiple independent security layers working together to prevent attacks and protect user assets.

**Why cross-chain security is challenging:**

- Multiple execution environments (source chain, hub, destination)
- Off-chain relayer components
- Asynchronous message delivery
- Irreversible token burns
- Complex state transitions

**Rayls security approach:**

- **Multi-layer authorization**: Independent validation at each protocol boundary
- **Replay protection**: Dual-layer message ID tracking and nonce sequencing
- **Reentrancy guards**: Separate protections for send and receive paths
- **Input validation**: Comprehensive checks at every entry point
- **Context authentication**: Cryptographic message origin verification
- **Atomic safety**: Lock/unlock mechanisms preventing partial state updates

!!! info "Prerequisites"
    - Understand [EIP-5164 Explained](eip-5164-explained.md) for message protocol foundations
    - Read [Endpoint Integration](endpoint-integration.md) for security modifiers in practice
    - Know [Token Standards](token-standards.md) for atomic teleport mechanisms

**What this guide covers:**

This document provides a comprehensive technical reference for Rayls security mechanisms. You'll learn how each security layer works, what attacks are prevented, and how to use security features correctly in your contracts.

---

## Security Architecture Overview

Rayls employs a defense-in-depth architecture with multiple independent security layers. Each layer provides protection against specific attack vectors, and together they create a robust security posture.

### The Five Security Layers

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 5: Governance Validation                             │
│  • Token activation status                                  │
│  • User registration checks                                 │
│  • RaylsAccessManagerV1 role-based authorization            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 4: Chain-Specific Authorization                      │
│  • onlyFromPrivateNetworkHub validation                      │
│  • Source chain verification                                │
│  • Cross-chain context extraction                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: Sender Authorization                              │
│  • restricted modifier (AccessManager canCall check)        │
│  • Function-level role mapping per contract                 │
│  • RELAYER role for cross-chain message delivery            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 2: Relayer Authorization                             │
│  • AccessManager RELAYER role verification                  │
│  • Message package validation                               │
│  • Off-chain component authentication                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Executor Authorization                            │
│  • MESSAGE_EXECUTOR role validation                         │
│  • Context appending (messageId + fromChainId + sender)     │
│  • restricted modifier enforcement                          │
└─────────────────────────────────────────────────────────────┘
```

!!! info "Authorization System"
    For a comprehensive threat model, attack scenarios, and defense-in-depth analysis specific to the authorization system, see the [Authorization Security Model](../../learn/governance/authorization/security-model.md).

**Defense in depth principle:**

If one layer is compromised, others continue providing protection. For example:
- Even if a relayer is compromised, trusted executor validation prevents unauthorized execution
- Even if sender authorization is bypassed, chain-specific checks prevent cross-chain attacks
- Even if all authorization layers are bypassed, replay protection prevents message reuse

**Trust boundaries:**

- **Source chain ↔ Relayer**: Event detection and message packaging
- **Relayer ↔ Private Network Hub**: Message submission and validation
- **Hub ↔ Destination relayer**: Message routing and delivery
- **Destination relayer ↔ Destination chain**: Execution and state updates

Each boundary has specific security mechanisms to prevent unauthorized or malicious activity.

---

## Authorization & Access Control

Rayls uses three authorization mechanisms, each serving a specific purpose in the security model.

### 1. restricted - Unified Role-Based Authorization

**File**: `RaylsAccessManaged.sol:73-76`

```solidity
modifier restricted() {
    _checkCanCall(msg.sender, msg.sig);
    _;
}
```

**What it does:**

Delegates all authorization decisions to the central `RaylsAccessManagerV1` contract via `canCall(caller, target, selector)`. Each function is mapped to one or more roles, and only callers holding the required role can invoke it.

**What it prevents:**

- **Unauthorized access** to any privileged function
- **Over-permission** -- each role has access to only specific functions on specific contracts
- **Unaudited changes** -- all role grants and function mappings emit events

**When to use:**

Apply to ALL privileged functions. This is the primary authorization mechanism for all Rayls contracts:

```solidity
function freezeToken(bytes32 resourceId, uint256[] calldata chainIds) external restricted {
    tokenFreezeManager.freezeToken(resourceId, chainIds);
}

function receiveTeleport(address to, uint256 value) public virtual restricted {
    _mint(to, value);
}
```

Cross-chain receive functions use `restricted` with the `MESSAGE_EXECUTOR` role. Relayer-facing functions use `restricted` with the `RELAYER` role. Administrative functions use `restricted` and default to `ADMIN` when unmapped.

For details on the full authorization system, see [Authorization](../../learn/governance/authorization/index.md).

---

### 2. onlyRegisteredUsers - User Governance

**File**: `RaylsApp.sol:371-377`

```solidity
modifier onlyRegisteredUsers() {
    if (address(raylsNodeUserGovernance) != address(0)) {
        bool isRegistered = raylsNodeUserGovernance.checkUserIsApprovedByPrivateAddress(msg.sender);
        require(isRegistered, "User not registered");
    }
    _;
}
```

**What it does:**

Validates that `msg.sender` is registered through the user governance contract. Supports optional governance -- skips the check if governance is not configured (address is zero).

**What it prevents:**

- **Unauthorized user access** to permissioned functions
- **Sybil attacks** by limiting operations to registered users
- **Compliance violations** by enforcing user registration requirements

**When to use:**

Applied to user-initiated functions that require registration, such as cross-chain teleport operations:

```solidity
function teleportToPublicChain(
    address to, uint256 value, uint256 destinationChainId
) external onlyRegisteredUsers {
    // Only registered users can initiate public chain teleports
}
```

**Governance integration:**

The governance contract determines registration status. This allows dynamic user management without contract upgrades.

---

### 3. onlyAuthorizedTokens - Token Activation

**File**: `RNEndpointV1.sol:58`

```solidity
modifier onlyAuthorizedTokens() {
    if (!tokenGovernance.isTokenAddressActive(msg.sender)) {
        revert RNEndpointV1__TokenUnauthorizedAccount(msg.sender);
    }
    _;
}
```

**What it does:**

Validates that the calling token contract is active in the token governance registry before allowing cross-chain operations.

**What it prevents:**

- **Deactivated tokens** performing cross-chain transfers
- **Malicious token contracts** exploiting cross-chain messaging
- **Unauthorized tokens** using the protocol

**When to use:**

Applied to endpoint send functions on Privacy Nodes. Only active token contracts can dispatch cross-chain messages:

```solidity
function send(
    uint256 _dstChainId, address _destination, bytes calldata _payload
) external virtual override onlyAuthorizedTokens returns (bytes32 messageId) {
    // Only active tokens can send cross-chain messages
}
```

**Token governance integration:**

The token governance contract maintains the registry of active tokens. Administrators can activate/deactivate tokens dynamically without contract upgrades.

---

### Authorization Best Practices

**1. Use `restricted` for all privileged functions:**

```solidity
// ✅ Correct -- role-based access via AccessManager
function freezeToken(bytes32 resourceId, uint256[] calldata chainIds) external restricted {
    tokenFreezeManager.freezeToken(resourceId, chainIds);
}

// ❌ Wrong -- no access control
function freezeToken(bytes32 resourceId, uint256[] calldata chainIds) external {
    tokenFreezeManager.freezeToken(resourceId, chainIds);  // Anyone can call!
}
```

**2. Use `onlyRegisteredUsers` for user-facing operations:**

```solidity
// ✅ User validation for public chain operations
function teleportToPublicChain(address to, uint256 value, uint256 chainId) external onlyRegisteredUsers {
    _executeTeleport(to, value, chainId);
}
```

**3. Understand how `restricted` replaces legacy modifiers:**

| Security Concern | Previous Modifier | Current Mechanism |
|---|---|---|
| Cross-chain message delivery | `receiveMethod` | `restricted` with `MESSAGE_EXECUTOR` role |
| Relayer authorization | `onlyRelayerAuthorized` | `restricted` with `RELAYER` role |
| Send authorization | `onlyAuthorizedAddresses` | `restricted` with `ENDPOINT_SENDER` role |
| PNH origin validation | `onlyFromCommitChain` | Inline calldata checks where needed |

---

## Replay Protection

Replay protection prevents the same cross-chain message from being executed multiple times. Rayls implements dual-layer replay protection: message ID tracking and nonce-based sequencing.

### Message ID Tracking

**The executed Mapping Pattern:**

Every executor contract maintains a mapping of executed message IDs:

**File**: `RaylsMessageExecutorV1.sol:17`

```solidity
mapping(bytes32 => bool) public executed;
```

**Execution flow with replay protection:**

**File**: `RaylsMessageExecutorV1.sol:29-36`

```solidity
function executeMessage(
    uint256 fromChainId,
    address from,
    address to,
    bytes calldata data
) external payable returns (bytes32 messageId) {
    messageId = keccak256(abi.encodePacked(fromChainId, from, to, block.chainid, data));

    bool _executedMessageId = executed[messageId];
    executed[messageId] = true;

    MessageLib.executeMessage(to, data, messageId, fromChainId, from, _executedMessageId);
}
```

**Key security properties:**

1. **Read-before-write**: Reads `executed[messageId]` before setting to true
2. **Set before execution**: Marks message as executed BEFORE calling target contract
3. **Check-effects-interaction**: Follows security best practice to prevent reentrancy

**Modern implementation with custom errors:**

**File**: `RNMessageExecutorV1.sol:94-111`

```solidity
function executeMessage(
    uint256 fromChainId,
    address from,
    address to,
    bytes calldata data
) external payable onlyEndpoint returns (bytes32 messageId) {
    messageId = keccak256(abi.encodePacked(fromChainId, from, to, block.chainid, data));

    bool _executedMessageId = executed[messageId];
    executed[messageId] = true;

    if (_executedMessageId) {
        revert RNMessageExecutorV1__MessageIdAlreadyExecuted(messageId);
    }

    // Execute message
    _executeMessage(to, data, messageId, fromChainId, from);
}
```

**Why set before checking?**

This pattern supports atomic transactions where the check happens internally in `_executeMessage`. Setting the flag first prevents reentrancy during message execution.

---

### Message ID Computation

Message IDs are deterministic hashes of message parameters, ensuring uniqueness:

**File**: `MessageLib.sol:59-65`

```solidity
function computeMessageId(
    uint256 fromChainId,
    address from,
    uint256 toChainId,
    address to,
    bytes memory data
) internal pure returns (bytes32) {
    return keccak256(abi.encode(fromChainId, from, toChainId, to, data));
}
```

**Uniqueness properties:**

- **Chain-specific**: Different chains produce different message IDs
- **Sender-specific**: Different senders produce different IDs
- **Content-specific**: Different payloads produce different IDs
- **Deterministic**: Same inputs always produce the same ID

**Why this prevents replay:**

Even if an attacker captures and replays a message:
1. The `executed[messageId]` check will fail
2. The transaction reverts with `MessageIdAlreadyExecuted` error
3. No state changes occur

---

### Nonce-Based Sequencing

In addition to message ID tracking, Rayls uses nonces for message ordering:

**File**: `MessageReceiver.sol:16`

```solidity
mapping(uint256 => uint256) public inboundNonce;
```

**Nonce validation:**

**File**: `MessageReceiver.sol:96-99`

```solidity
if (!_messageMetadata.ignoresNonce) {
    require(
        _messageMetadata.nonce == ++inboundNonce[_srcChainId],
        'MessageReceiver: wrong nonce'
    );
}
```

**What nonces prevent:**

- **Message reordering**: Messages must be processed in sequence
- **Skipped messages**: Missing nonces are detected
- **Partial replays**: Cannot replay only some messages from a sequence

**Per-chain nonces:**

Each source chain has its own nonce counter (`inboundNonce[_srcChainId]`), allowing independent sequencing per chain.

**Optional nonce checking:**

The `ignoresNonce` flag allows flexibility for messages where ordering doesn't matter. This is useful for:
- Independent operations (e.g., separate user transfers)
- Idempotent operations (e.g., configuration that can be set multiple times)

---

### EIP-5164 Compliance

Rayls implements EIP-5164 compliant replay protection:

**File**: `PublicRNEndpointV1.sol:224-230`

```solidity
// EIP-5164 replay protection: Check if message already executed
if (executed[_messageId]) revert PublicRNEndpointV1__MessageAlreadyExecuted();

// Mark message as executed to prevent replay
executed[_messageId] = true;

// Execute the cross-chain call
_executeCall(_to, _data, _messageId, _fromChainId, _from);
```

**EIP-5164 nonce increment:**

**File**: `PublicRNEndpointV1.sol:331-332`

```solidity
// Increment EIP-5164 compliant nonce
uint256 currentNonce = ++nonce;
```

**Standard compliance benefits:**

- **Interoperability**: Works with other EIP-5164 compliant systems
- **Standard security**: Follows established cross-chain security patterns
- **Ecosystem compatibility**: Can integrate with standard tools and libraries

---

### Dual-Layer Replay Protection

Rayls implements replay protection at TWO levels:

**Level 1: Private Network Hub**

**File**: `RaylsMessageExecutorV1.sol:29-36`

The hub checks `executed[messageId]` before routing to destination. This prevents replays at the coordination layer.

**Level 2: Destination Chain**

**File**: `RNMessageExecutorV1.sol:94-111`

The destination executor also checks `executed[messageId]` before execution. This provides defense in depth.

**Why two layers?**

- **Hub compromise**: If hub is compromised, destination still prevents replay
- **Route bypassing**: If attacker bypasses hub, destination catches replay
- **Independent verification**: Each layer validates independently

**Example scenario:**

1. Message executed successfully on destination
2. Attacker captures the message and tries to replay through hub
3. **Hub layer**: Detects `executed[messageId] == true`, reverts
4. If hub layer is bypassed somehow, **destination layer** still prevents execution

This dual-layer approach is a core example of defense in depth in Rayls security architecture.

---

## Reentrancy Protection

Reentrancy attacks occur when an external call allows the called contract to re-enter the calling contract before the first invocation completes. Rayls implements custom reentrancy guards specifically designed for cross-chain operations.

### Why Separate Send/Receive Guards?

Standard reentrancy guards use a single lock for the entire contract. Rayls uses **separate locks for send and receive paths** to prevent a specific cross-chain attack scenario:

**Attack scenario prevented:**

1. Contract A sends a cross-chain message to Contract B
2. During send execution, Contract B is called for some reason
3. Contract B attempts to send a cross-chain message back
4. Without separate guards, this circular send is possible
5. **With separate guards**: Send lock prevents the circular call

**The dual guard pattern:**

**File**: `RaylsReentrancyGuardV1.sol:7-37`

```solidity
abstract contract RaylsReentrancyGuardV1 is Initializable {
    uint8 internal constant _NOT_ENTERED = 1;
    uint8 internal constant _ENTERED = 2;

    uint8 internal _send_entered_state;
    uint8 internal _receive_entered_state;

    function __RaylsReentrancyGuard_init() internal onlyInitializing {
        __RaylsReentrancyGuard_init_unchained();
    }

    function __RaylsReentrancyGuard_init_unchained() internal onlyInitializing {
        _send_entered_state = _NOT_ENTERED;
        _receive_entered_state = _NOT_ENTERED;
    }

    // Separate modifiers for send and receive paths
}
```

---

### Send Path Protection

**File**: `RaylsReentrancyGuardV1.sol:19-27`

```solidity
modifier sendNonReentrant() {
    require(
        _send_entered_state == _NOT_ENTERED,
        "Rayls: no send reentrancy"
    );
    _send_entered_state = _ENTERED;
    _;
    _send_entered_state = _NOT_ENTERED;
}
```

**How it works:**

1. **Check**: Validates `_send_entered_state == _NOT_ENTERED`
2. **Set**: Changes state to `_ENTERED` before function executes
3. **Execute**: Function body runs
4. **Reset**: State returns to `_NOT_ENTERED` after completion

**Applied to send functions:**

```solidity
function send(uint256 chainId, address to, bytes memory data)
    external
    sendNonReentrant
{
    // Send cross-chain message
    // Any reentrant call to send() will revert
}
```

**What it prevents:**

- Recursive sends during message dispatch
- Send operations during send callbacks
- Circular send patterns in complex integrations

---

### Receive Path Protection

**File**: `RaylsReentrancyGuardV1.sol:28-36`

```solidity
modifier receiveNonReentrant() {
    require(
        _receive_entered_state == _NOT_ENTERED,
        "Rayls: no receive reentrancy"
    );
    _receive_entered_state = _ENTERED;
    _;
    _receive_entered_state = _NOT_ENTERED;
}
```

**Applied to receive functions:**

```solidity
function executeMessage(address to, bytes calldata data)
    external
    receiveNonReentrant
{
    // Execute cross-chain message
    // Any reentrant call to executeMessage() will revert
}
```

**What it prevents:**

- Malicious contracts calling back into receive during execution
- Circular message execution
- State manipulation through reentrant receives

---

### Modern Implementation with Custom Errors

The newer implementation uses gas-efficient custom errors:

**File**: `RNReentrancyGuardV1.sol:1-63`

```solidity
error RNReentrancyGuardV1__SendReentrancy();
error RNReentrancyGuardV1__ReceiveReentrancy();

abstract contract RNReentrancyGuardV1 is Initializable {
    uint8 internal constant _NOT_ENTERED = 1;
    uint8 internal constant _ENTERED = 2;

    uint8 internal _send_entered_state;
    uint8 internal _receive_entered_state;

    modifier sendNonReentrant() {
        if (_send_entered_state == _ENTERED) revert RNReentrancyGuardV1__SendReentrancy();
        _send_entered_state = _ENTERED;
        _;
        _send_entered_state = _NOT_ENTERED;
    }

    modifier receiveNonReentrant() {
        if (_receive_entered_state == _ENTERED) revert RNReentrancyGuardV1__ReceiveReentrancy();
        _receive_entered_state = _ENTERED;
        _;
        _receive_entered_state = _NOT_ENTERED;
    }
}
```

**Benefits of custom errors:**

- **Lower gas cost**: Custom errors are cheaper than string reverts
- **Better debugging**: Error names clearly indicate the issue
- **Type safety**: Errors can include parameters for debugging

---

### Why Independent Send/Receive Locks?

**Scenario demonstrating the need:**

```solidity
contract CrossChainBridge is RaylsReentrancyGuardV1 {
    function bridgeAssets(uint256 amount) external sendNonReentrant {
        // 1. Lock assets locally
        _lockAssets(msg.sender, amount);

        // 2. Send cross-chain message
        endpoint.send(destChain, destContract, data);

        // 3. During send, external call might trigger receive
        // With separate locks, receive can execute without blocking
    }

    function receiveAssets(address to, uint256 amount) external receiveNonReentrant {
        // Receive can execute even if send is in progress
        // Separate lock prevents receive reentrancy
        _unlockAssets(to, amount);
    }
}
```

**With a single lock:**

- Send locks the contract
- Any receive during send would fail
- Legitimate cross-chain interactions would break

**With separate locks:**

- Send locks only send path
- Receive can execute independently
- Only circular calls in the same path are prevented

---

### Reentrancy Protection Best Practices

**1. Always apply appropriate guard:**

```solidity
// ✅ Correct - send protected
function sendMessage() external sendNonReentrant {
    endpoint.send(...);
}

// ✅ Correct - receive protected
function receiveMessage() external receiveNonReentrant {
    _processMessage(...);
}
```

**2. Use with other security modifiers:**

```solidity
// ✅ Multi-layer protection
function receiveTokens(address to, uint256 amount)
    external
    restricted
    receiveNonReentrant
{
    _mint(to, amount);
}
```

**3. Don't mix send/receive guards:**

```solidity
// ❌ Wrong - using send guard on receive function
function receiveData() external sendNonReentrant {
    _processData();  // Should use receiveNonReentrant
}
```

**4. Understand guard scope:**

Guards only prevent reentrancy within the same path (send-to-send or receive-to-receive). They don't prevent send calling receive or vice versa, which is intentional for legitimate cross-chain flows.

!!! tip "See it in practice"
    Learn how to implement reentrancy guards in custom token handlers:

    - [Building Custom Tokens: Security Patterns](building-custom-tokens.md) - Complete implementation with sendNonReentrant and receiveNonReentrant
    - [Building Custom Tokens: Advanced Patterns](building-custom-tokens.md) - Complex scenarios requiring reentrancy protection

---

## Cross-Chain Message Authentication

Cross-chain message authentication ensures that receive methods can verify the original sender, source chain, and message ID. Rayls uses context appending to provide this authentication.

### Context Appending Mechanism

When the MessageExecutor calls a target contract's receive method, it appends 84 bytes of context to the calldata:

**File**: `MessageLib.sol:136`

```solidity
(bool _success, bytes memory _returnData) = to.call(
    abi.encodePacked(data, messageId, fromChainId, from)
);
```

**The 84-byte context structure:**

```
Original calldata || messageId (32 bytes) || fromChainId (32 bytes) || from (32 bytes)
```

**Example:**

```
Function call: receiveTeleport(address to, uint256 value)
Original data: 0x[function selector][to address][value]
Context added: [messageId][fromChainId][sender address]
Final calldata: [original data][messageId][fromChainId][from]
```

**Why append instead of prepend?**

Appending maintains backward compatibility with function selectors and allows the function to execute normally while providing context extraction for contracts that need it.

---

### Extracting Context Securely

RaylsApp provides helper functions to extract context from appended calldata:

**Extracting messageId:**

**File**: `RaylsApp.sol:279-291`

```solidity
function _getMessageIdOnReceiveMethod() internal pure virtual returns (bytes32 messageId) {
    assembly {
        messageId := calldataload(sub(calldatasize(), 84))
    }
}
```

**How it works:**

- `calldatasize()` returns total calldata length
- `sub(calldatasize(), 84)` calculates position of messageId (84 bytes from end)
- `calldataload()` reads 32 bytes starting at that position

**Extracting fromChainId:**

**File**: `RaylsApp.sol:298-310`

```solidity
function _getFromChainIdOnReceiveMethod() internal pure virtual returns (uint256 fromChainId) {
    assembly {
        fromChainId := calldataload(sub(calldatasize(), 52))
    }
}
```

**How it works:**

- 52 bytes from end = 32 bytes (from) + 20 bytes into fromChainId
- Reads the fromChainId value from the appended context

**Extracting original sender:**

**File**: `RaylsApp.sol:317-329`

```solidity
function _getMsgSenderOnReceiveMethod() internal pure virtual returns (address sender) {
    assembly {
        sender := shr(96, calldataload(sub(calldatasize(), 20)))
    }
}
```

**How it works:**

- 20 bytes from end = last 20 bytes (Ethereum address size)
- `shr(96, ...)` right-shifts 96 bits to extract address from 32-byte word

---

### Security Implications

**1. Only trusted executors can append context:**

The context is appended by the MessageExecutor, which is validated by the `restricted` modifier (requiring the `MESSAGE_EXECUTOR` role). An attacker cannot call the receive function directly and provide fake context.

**Attack prevention:**

```solidity
// ❌ Attack attempt: Direct call with fake context
contract Attacker {
    function attack(address target) external {
        // Try to call receiveTeleport directly with fake context
        bytes memory fakeContext = abi.encodePacked(
            fakeMessageId,
            fakeChainId,
            attackerAddress
        );
        target.call(abi.encodePacked(
            abi.encodeWithSignature("receiveTeleport(address,uint256)", attacker, 1000000),
            fakeContext
        ));
        // ❌ FAILS: restricted modifier rejects non-MESSAGE_EXECUTOR caller
    }
}
```

The `restricted` modifier ensures only the authorized MessageExecutor can call the function, and the executor always appends authentic context.

**2. Context extraction must happen in receive functions:**

The context extraction functions only work when called from within a restricted receive function (where the caller is the MessageExecutor):

```solidity
// ✅ Correct usage
function receiveVote(uint256 proposalId, bool support) external restricted {
    address originalSender = _getMsgSenderOnReceiveMethod();
    uint256 sourceChain = _getFromChainIdOnReceiveMethod();

    _recordVote(originalSender, sourceChain, proposalId, support);
}
```

**3. Context provides cross-chain identity:**

The extracted sender address is the original caller on the source chain, not `msg.sender` on the destination:

```
Source Chain A:
  User (0xAlice) calls token.teleport(chainB, recipient, 100)

Destination Chain B:
  msg.sender = MessageExecutor address (0x123...)
  _getMsgSenderOnReceiveMethod() = 0xAlice (original sender)
```

This allows destination contracts to implement sender-based logic:

```solidity
function receiveTokens(address to, uint256 value) external restricted {
    address originalSender = _getMsgSenderOnReceiveMethod();

    // Enforce same-user transfer
    require(to == originalSender, "Can only send to yourself");

    _mint(to, value);
}
```

---

### Using Context for Origin Validation

Contracts that need to validate message origin can extract `fromChainId` from appended context. For example, `ParticipantStorageReplicaV1` uses an inline check to ensure messages originate from the Private Network Hub:

```solidity
uint256 fromChainId = _getFromChainIdOnReceiveMethod();
require(fromChainId == endpoint.getCommitChainId(), "Only from Private Network Hub");
```

**How this works:**

1. Extract `fromChainId` from appended context
2. Compare to expected Private Network Hub chain ID
3. Revert if source is not the Private Network Hub

**Security guarantee:**

An attacker cannot spoof the source chain because:
- Only the authorized MessageExecutor can call the function (`restricted` modifier)
- Only the executor appends the context
- The executor gets `fromChainId` from the validated cross-chain message flow

---

### Context Appending Best Practices

**1. Always use `restricted` on cross-chain receive functions:**

```solidity
// ✅ Correct -- restricted ensures only MESSAGE_EXECUTOR can call
function receiveMessage() external restricted {
    address sender = _getMsgSenderOnReceiveMethod();
    // Use sender safely
}

// ❌ Wrong -- no access control
function receiveMessage() external {
    address sender = _getMsgSenderOnReceiveMethod();
    // Unsafe! No validation that context is authentic
}
```

**2. Extract context early in function:**

```solidity
// ✅ Good practice
function receiveData(bytes calldata data) external restricted {
    address sender = _getMsgSenderOnReceiveMethod();
    uint256 sourceChain = _getFromChainIdOnReceiveMethod();
    bytes32 msgId = _getMessageIdOnReceiveMethod();

    // Use extracted context throughout function
    _processData(sender, sourceChain, msgId, data);
}
```

**3. Don't extract context in non-receive functions:**

```solidity
// ❌ Wrong - context not available in regular functions
function regularFunction() external {
    address sender = _getMsgSenderOnReceiveMethod();
    // Returns garbage data - no context appended
}
```

**4. Use for cross-chain authorization:**

```solidity
// ✅ Cross-chain sender validation
function adminOperation() external restricted {
    address crossChainSender = _getMsgSenderOnReceiveMethod();
    require(isAdmin[crossChainSender], "Not admin");

    // Execute admin operation
}
```

---

## Input Validation Patterns

Comprehensive input validation prevents invalid states and protects against malicious inputs. Rayls implements validation at every entry point.

### Address Validation

**Zero address prevention:**

**File**: `RaylsErc20Handler.sol:146-151`

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

**What this prevents:**

- **Token burning**: Sending to `address(0)` burns tokens unintentionally
- **Invalid transfers**: Zero value transfers waste gas
- **Same-chain teleports**: Using cross-chain function for local transfers

**Third-party validation:**

**File**: `RaylsErc20Handler.sol:192-200`

```solidity
function teleportFrom(
    address from,
    address to,
    uint256 value,
    uint256 chainId
) public virtual returns (bool) {
    if (from == address(0) || from == msg.sender) {
        revert RaylsErc20Handler__WrongAddress(from);
    }

    // ... execution continues
}
```

**What this prevents:**

- Using `teleportFrom` for self-transfers (use `teleport` instead)
- Invalid `from` address specification

**Authorization array validation:**

**File**: `EndpointV1.sol:493-496`

```solidity
for (uint256 i = 0; i < addresses.length; i++) {
    if (addresses[i] == address(0)) {
        revert Endpoint__ZeroAddressNotAllowed();
    }
    isAuthorizedAddress[addresses[i]] = true;
}
```

**What this prevents:**

- Adding `address(0)` to authorization whitelist
- Creating authorization bypasses

---

### Contract Existence Checks

Before executing calls to target contracts, Rayls validates that the target is actually a contract:

**File**: `MessageLib.sol:186-189`

```solidity
function _requireContract(address to) internal view {
    require(to.code.length > 0, "MessageLib/no-contract-at-to");
}
```

**How it works:**

- `to.code.length` returns the bytecode length at address
- For contracts: `code.length > 0`
- For EOAs (externally owned accounts): `code.length == 0`

**Modern implementation:**

**File**: `RNMessageExecutorV1.sol:175-179`

```solidity
function _requireContract(address to) internal view {
    if (to.code.length == 0) {
        revert RNMessageExecutorV1__NoContractAtAddress(to);
    }
}
```

**What this prevents:**

- **Calls to EOAs**: Cross-chain messages to regular user accounts
- **Invalid destinations**: Messages to non-existent contracts
- **Silent failures**: Calls that would succeed but do nothing

**Applied before execution:**

```solidity
function executeMessage(address to, bytes calldata data) external {
    _requireContract(to);  // Validate before execution

    // Execute call
    (bool success,) = to.call(data);
}
```

---

### Batch Size Limits

To prevent DoS attacks through oversized batches, Rayls enforces configurable batch limits:

**File**: `EndpointV1.sol:226-229`

```solidity
require(
    _destinationPayloadRequests.length < getMaxBatchMessages(),
    "EndpointV1: The max number of transactions allowed in a batch has been exceeded"
);
```

**What this prevents:**

- **DoS through gas exhaustion**: Batches too large to execute
- **State bloat**: Excessive message storage
- **Relayer overload**: Unprocessable batch sizes

**Configurable limits:**

The owner can adjust `maxBatchMessages` based on network conditions:

```solidity
function setMaxBatchMessages(uint256 _maxBatchMessages) public restricted {
    maxBatchMessages = _maxBatchMessages;
}
```

---

### Amount and Value Validation

**Positive amount requirements:**

**File**: `RaylsErc20Handler.sol:438-447`

```solidity
function _lock(address to, uint256 amount) internal {
    require(amount > 0, "Amount must be greater than 0");
    require(to != address(0));

    lockedBalances[to] += amount;
}

function _unlock(address to, uint256 amount) internal {
    uint256 amountToUnlock = lockedBalances[to];
    require(amount > 0 && amount <= amountToUnlock, "Not enough funds to unlock");

    lockedBalances[to] -= amount;
}
```

**What this prevents:**

- Zero-value locks (wasting storage)
- Unlocking more than locked (underflow protection)
- Invalid amount specifications

---

### Input Validation Best Practices

**1. Validate early:**

```solidity
// ✅ Validate at function start
function transfer(address to, uint256 amount) external {
    if (to == address(0)) revert InvalidAddress();
    if (amount == 0) revert InvalidAmount();

    // Continue with valid inputs
    _transfer(msg.sender, to, amount);
}
```

**2. Use custom errors for gas efficiency:**

```solidity
// ✅ Gas-efficient custom errors
error ZeroAddress();
error ZeroAmount();

if (to == address(0)) revert ZeroAddress();
if (amount == 0) revert ZeroAmount();
```

**3. Validate arrays before iteration:**

```solidity
// ✅ Check array not empty
function batchProcess(address[] calldata addresses) external {
    if (addresses.length == 0) revert EmptyArray();

    for (uint256 i = 0; i < addresses.length; i++) {
        // Process each address
    }
}
```

**4. Combine related validations:**

```solidity
// ✅ Validate all parameters together
if (to == address(0) || value == 0 || chainId == 0) {
    revert InvalidParameters(to, value, chainId);
}
```

---

## Atomic Transaction Security

Atomic transactions provide automatic revert capabilities if cross-chain operations fail. This prevents partial state updates and protects user assets.

!!! info "Complete Atomic Teleport Documentation"
    This section covers the **security** perspective of atomic teleport. For comprehensive coverage:

    - **Complete mechanism**: [Token Standards: Atomic Teleport 4-Payload System](token-standards.md#how-it-works-four-payloads) - Canonical reference
    - **Transaction flow**: [Transaction Lifecycle: Phase 5 Atomic Confirmation](transaction-lifecycle.md#phase-5-atomic-confirmation) - Step-by-step flow and timing
    - **Testing scenarios**: [Testing: Vanilla vs Atomic Teleport](testing.md#vanilla-vs-atomic-teleport) - Test coverage and guarantees

### Lock/Unlock Mechanism

Atomic teleports use a two-step process: lock on arrival, unlock on confirmation.

**Step 1: Receive and lock:**

**File**: `RaylsErc20Handler.sol:375-380`

```solidity
function receiveTeleportAtomic(address to, uint256 value) public virtual restricted {
    _mint(owner(), value);  // Minted to owner (escrow)
    if (to != owner()) {
        _lock(to, value);   // Locked for recipient
    }
}
```

**What happens:**

1. Tokens minted to contract owner (escrow account)
2. Tokens locked for recipient
3. Recipient cannot access tokens yet
4. Awaits unlock confirmation

**Step 2: Unlock on success:**

**File**: `RaylsErc20Handler.sol:427-435`

```solidity
function unlock(address to, uint256 value) public virtual restricted {
    _unlock(to, value);
    if (to != owner()) {
        _transfer(owner(), to, value);
    }
}
```

**What happens:**

1. Locked amount decremented
2. Tokens transferred from owner to recipient
3. **Transfer complete**

---

### Revert on Failure

If the destination execution fails, atomic teleport automatically refunds the sender:

**File**: `RaylsErc20Handler.sol:382-384`

```solidity
function revertTeleportMint(address to, uint256 value) public virtual restricted {
    _mint(to, value);  // Refund to original sender
}
```

**When this executes:**

- Destination `receiveTeleportAtomic()` reverts
- Hub detects failure
- Revert payload executed on source chain
- Tokens minted back to original sender

**Security properties:**

1. **No token loss**: Failed transfers result in refund, not burned tokens
2. **Automatic**: No manual intervention required
3. **Atomic**: Either completes fully or reverts fully

---

### Four-Payload System

Atomic teleports include four payloads for different execution paths:

**File**: `RaylsErc20Handler.sol:241-272`

```solidity
function teleportAtomic(address to, uint256 value, uint256 destinationChainId) public virtual returns (bool) {
    _burn(msg.sender, value);

    sendTeleport(
        destinationChainId,
        abi.encodeWithSignature("receiveTeleportAtomic(address,uint256)", to, value),        // Payload 1: Main
        abi.encodeWithSignature("unlock(address,uint256)", to, value),                        // Payload 2: Success
        abi.encodeWithSignature("revertTeleportMint(address,uint256)", msg.sender, value),   // Payload 3: Failure
        abi.encodeWithSignature("revertTeleportBurn(uint256)", value),                        // Payload 4: Cleanup
        transferMetadata
    );
    return true;
}
```

**Payload execution logic:**

- **Payload 1 succeeds** → Execute Payload 2 (unlock)
- **Payload 1 fails** → Execute Payload 3 (revert mint on source)
- **Payload 3 used** → Execute Payload 4 (cleanup on destination)

**Security guarantee:**

The four-payload system ensures that regardless of where failure occurs, the system reaches a consistent final state with no lost tokens.

---

### Preventing Partial State Updates

**Problem scenario without atomic:**

```
1. Tokens burned on source chain ✅
2. Cross-chain message dispatched ✅
3. Destination execution fails ❌
   → Tokens burned but not minted = LOST
```

**Solution with atomic:**

```
1. Tokens burned on source chain ✅
2. Cross-chain message dispatched ✅
3. Destination execution fails ❌
4. Revert payload executed ✅
5. Tokens minted back to sender ✅
   → No tokens lost = SAFE
```

**Lock mechanism prevents partial delivery:**

Even if unlock fails:

```
1. Tokens minted to escrow ✅
2. Tokens locked for recipient ✅
3. Unlock payload fails ❌
   → Tokens remain in escrow, can be recovered
   → Recipient doesn't receive partial/incorrect amount
```

---

### Atomic vs Regular Teleport Security

| Aspect | Regular Teleport | Atomic Teleport |
|--------|------------------|-----------------|
| **Failure handling** | Manual recovery required | Automatic refund |
| **Token safety** | Can be lost if destination fails | Always refunded on failure |
| **Complexity** | Single payload | Four payloads |
| **Gas cost** | Lower (one message) | Higher (multiple messages) |
| **Production readiness** | Development/testing only | **Recommended for production** |
| **Partial state risk** | High (burned but not minted) | Low (lock/unlock prevents) |

**Recommendation:**

Always use `teleportAtomic()` in production unless you have:
- Manual recovery procedures in place
- Operational team to handle failures
- Specific use case requiring regular teleport

---

### Atomic Transaction Best Practices

**1. Use teleportAtomic in production:**

```solidity
// ✅ Production code
token.teleportAtomic(recipient, amount, destinationChainId);

// ❌ Risky without recovery plan
token.teleport(destinationChainId, recipient, amount);
```

**2. Understand lock implications:**

```solidity
// User's tokens are locked until unlock executes
// Plan for ~60-80 second total time
const tx = await token.teleportAtomic(recipient, amount, chainB);
// Tokens locked on destination after ~30-40s
// Tokens unlocked to recipient after ~60-80s total
```

**3. Handle errors gracefully:**

```solidity
try {
    await token.teleportAtomic(recipient, amount, chainB);
    // Success path
} catch (error) {
    // Source-side validation failed
    // No tokens burned, safe to retry
}
```

**4. Monitor lock status:**

```solidity
// Check locked balance on destination
const locked = await destToken.lockedBalances(recipient);
if (locked > 0) {
    // Awaiting unlock confirmation
}
```

---

## Resource ID Security

Resource IDs provide logical addressing for contracts across chains, enabling upgradeability and flexible routing.

### Registration Requirement

Contracts must register a resource ID before cross-chain operations:

**File**: `RaylsApp.sol:143-148`

```solidity
function _registerResourceId() internal virtual {
    require(
        resourceId != bytes32(0),
        "Only register resource when it's approved"
    );
    endpoint.registerResourceId(resourceId, address(this));
}
```

**Security properties:**

- **Non-zero check**: Prevents registration without approval
- **Explicit registration**: Opt-in model, not automatic
- **Endpoint validation**: Endpoint verifies and stores mapping

The no-argument `_registerResourceId()` above is used by non-token dApps that
manage their own resource id. **Tokens are registry-driven:** their `resourceId`
is assigned by the Privacy Node's `PNTokenRegistryV1` through the
`activateToken(bytes32,address,uint8)` callback (fired after Hub approval), which
calls `setResourceId(bytes32)` on the token and registers the mapping in the
endpoint. A token cannot obtain a non-zero `resourceId` — and therefore cannot
operate cross-chain — until it has been authorized on the Privacy Node
(`updatePrivacyNodeStatus(token, AUTHORIZED)`) and approved on the Hub.

**Token-specific validation:**

**File**: `RaylsErc20Handler.sol:466`

```solidity
function sendTeleport(...) internal {
    require(resourceId != bytes32(0), "Token not registered.");

    // Continue with teleport
}
```

**What this prevents:**

- Tokens performing cross-chain operations before Privacy Node authorization and Hub approval
- Routing failures due to missing resource ID
- Unauthorized resource ID usage

---

### Resource ID vs Direct Addressing

**Direct addressing:**

```solidity
endpoint.send(chainB, destinationContractAddress, payload);
```

- Routes to specific contract address
- Address must be known at call time
- No upgradeability

**Resource ID addressing:**

```solidity
endpoint.sendToResourceId(chainB, resourceId, payload);
```

- Routes to current address registered for resource ID
- Address can change via re-registration
- Supports contract upgrades

**Security implication:**

Resource IDs enable contract upgrades without changing calling code, but require trust in the entity managing resource ID registration.

---

### Best Practices

**1. Register during initialization:**

```solidity
function initialize(bytes32 _resourceId) external initializer {
    resourceId = _resourceId;
    _registerResourceId();
}
```

**2. Validate before operations:**

```solidity
function crossChainOperation() external {
    require(resourceId != bytes32(0), "Not registered");

    endpoint.sendToResourceId(chainB, resourceId, data);
}
```

**3. Use for upgradeable contracts:**

Resource IDs are ideal for upgradeable proxy patterns where the implementation address may change.

!!! tip "See it in practice"
    Learn how to implement resource ID validation in custom tokens:

    - [Building Custom Tokens: Resource ID Management](building-custom-tokens.md) - Proper registration and validation patterns
    - [Building Custom Tokens: Cross-Chain Addressing](building-custom-tokens.md) - Using resourceId for teleport operations
    - [Deployment Workflow: Resource ID Verification](deployment-workflow.md) - Testing resource ID configuration

---

## Summary

### Security Mechanisms Recap

**Authorization (3 mechanisms):**

- ✅ Unified role-based access control (`restricted` via AccessManager -- covers executor validation, relayer auth, sender auth, and all privileged operations)
- ✅ User governance (`onlyRegisteredUsers`)
- ✅ Token activation (`onlyAuthorizedTokens`)

**Replay Protection (2 mechanisms):**

- ✅ Message ID tracking (executed mappings)
- ✅ Nonce-based sequencing

**Reentrancy Protection:**

- ✅ Dual guards (separate send/receive locks)
- ✅ Check-effects-interaction pattern

**Input Validation:**

- ✅ Address validation (zero address prevention)
- ✅ Contract existence checks
- ✅ Batch size limits
- ✅ Amount validation

**Cross-Chain Authentication:**

- ✅ Context appending (84-byte context)
- ✅ Trusted executor pattern
- ✅ Message origin verification

**Atomic Safety:**

- ✅ Lock/unlock mechanisms
- ✅ Automatic revert payloads
- ✅ Four-payload system

---

### Production Security Checklist

- [ ] Use `restricted` on ALL privileged functions (cross-chain receives, admin operations, relayer endpoints)
- [ ] Use `teleportAtomic()` for production token transfers
- [ ] Validate addresses before cross-chain operations
- [ ] Implement proper error handling for failed messages
- [ ] Monitor relayer authorization status
- [ ] Test failure scenarios (reverts, unauthorized calls)
- [ ] Register resource IDs before operations
- [ ] Use appropriate reentrancy guards
- [ ] Combine multiple modifiers for defense in depth

---

### Attack Prevention Summary

| Attack Vector | Prevention Mechanism | Implementation |
|--------------|---------------------|----------------|
| **Replay attacks** | Message ID tracking | `executed[messageId]` mapping |
| **Reentrancy** | Dual guards | `sendNonReentrant` + `receiveNonReentrant` |
| **Message injection** | Context appending | 84-byte authenticated context |
| **Unauthorized calls** | Multi-layer authorization | 6 security modifiers |
| **Zero address exploits** | Comprehensive validation | Address checks at every entry |
| **DoS batch overflow** | Size limits | Configurable `maxBatchMessages` |
| **Contract call to EOA** | Code length checks | `to.code.length > 0` |
| **Message reordering** | Nonce sequencing | Per-chain nonce validation |
| **Token loss on failure** | Atomic reverts | Four-payload system |
| **Unauthorized upgrades** | UUPS pattern | Owner-only authorization |

---

### Related Documentation

**For protocol foundations:**

- [EIP-5164 Explained](eip-5164-explained.md) - Cross-chain messaging standard
- [Token Standards](token-standards.md) - Atomic teleport implementation
- [Endpoint Integration](endpoint-integration.md) - Security modifiers in practice

**For implementation:**

- [Transaction Lifecycle](transaction-lifecycle.md) - Security at each phase
- [Testing Guide](../reference/testing-guide.md) - Testing security scenarios
- [Best Practices](../reference/best-practices.md) - Secure development patterns

---

You now have a comprehensive understanding of Rayls security architecture. Use this knowledge to build secure cross-chain applications with defense-in-depth protection against attacks.

Ready to test your secure implementation? See [Testing Guide](../reference/testing-guide.md) next.
