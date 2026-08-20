# End-to-End Tutorial: Building MyInstitutionalToken

## Overview

This comprehensive tutorial walks you through building, deploying, and testing a complete cross-chain institutional token from start to finish. You'll create a production-ready ERC20 token with role-based access control, compliance attestation requirements, and full cross-chain capabilities.

## What You'll Build

**MyInstitutionalToken** - A custom ERC20 token with:

- Role-based access control (MINTER_ROLE, BURNER_ROLE, ADMIN_ROLE)
- Compliance attestation requirement for minting
- 6 decimal places (institutional/stablecoin pattern)
- Cross-chain teleport capabilities
- Atomic swap support with automatic revert protection
- Fund manager integration
- Complete test coverage
- Production monitoring setup

**Base Pattern:** This tutorial is based on CustomTokenExample.sol from the rayls-sovereign-contracts repository.

## Prerequisites

Before starting this tutorial, ensure you have completed:

- [Overview](overview.md) - Understanding Rayls architecture
- [Token Standards](token-standards.md) - Token handler basics
- [Building Custom Tokens](building-custom-tokens.md) - Custom token patterns
- [Beginner: Docker Setup](../beginner/docker-setup.md) - Development environment setup
- [Deployment Workflow](deployment-workflow.md) - Deployment process understanding

**Required setup:**

- Hardhat development environment configured
- Access to Privacy Node Ledgers A and B
- Access to Private Network Hub
- Private keys configured in `.env`
- System operator access for approvals

## Tutorial Steps

### Step 1: Design Your Token

Before writing code, define your token's requirements and design decisions.

#### Requirements Gathering

**Business Requirements:**

- Institutional-grade token for fund management
- Must comply with regulatory requirements (attestation-based)
- Support for multiple fund managers across chains
- Controlled minting (not open to public)
- Cross-chain transfer capabilities
- Atomic safety (no token loss on failed transfers)

**Technical Requirements:**

- 6 decimal places (standard for institutional tokens)
- Role-based permissions (admins, minters, burners)
- Attestation check before minting
- Integration with fund manager on specific chain
- Cross-chain teleport support
- Resource ID-based routing

#### Design Decisions

**1. Inheritance Structure:**

```
MyInstitutionalToken
├── AccessControl (OpenZeppelin) - For role-based permissions
└── RaylsErc20Handler - For cross-chain functionality
```

**2. Custom Features:**

- **decimals()**: Override to return 6 (instead of 18)
- **mint()**: Override to require attestation + MINTER_ROLE
- **initialize()**: Custom parameters for proxy deployment
- **_generateInitializerParams()**: Support factory deployment

**3. Roles Design:**

| Role | Purpose | Who Gets It |
|------|---------|-------------|
| DEFAULT_ADMIN_ROLE | Manage roles and attestation | Deployer, governance |
| MINTER_ROLE | Mint new tokens | Deployer, fund manager |
| BURNER_ROLE | Burn tokens | Deployer |

**4. State Variables:**

```solidity
bytes32 public attestationUid;      // Compliance attestation identifier
uint256 public fundManagerFeeChainId; // Chain where fund manager operates
address public fundManagerAddr;      // Fund manager address
```

### Step 2: Implement Custom Token

Create the complete token implementation based on our design.

#### File: `src/MyInstitutionalToken.sol`

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../../rayls-protocol-sdk/tokens/RaylsErc20Handler.sol";
import "../../rayls-protocol-sdk/interfaces/IRaylsEndpoint.sol";
import "../../rayls-protocol/Endpoint/EndpointV1.sol";

/**
 * @title MyInstitutionalToken
 * @notice Institutional-grade ERC20 token with attestation-based minting and cross-chain support
 * @dev Combines AccessControl for permissions with RaylsErc20Handler for cross-chain functionality
 */
contract MyInstitutionalToken is AccessControl, RaylsErc20Handler {
    // Endpoint reference for resource ID lookups
    EndpointV1 private epoint;

    // Compliance attestation UID (required for minting)
    bytes32 public attestationUid;

    // Fund manager configuration
    uint256 public fundManagerFeeChainId;
    address public fundManagerAddr;

    // Role definitions
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /**
     * @notice Constructor for initial deployment on origin chain
     * @param name Token name
     * @param symbol Token symbol
     * @param _fundManagerChainId Chain ID where fund manager operates
     * @param _fundManagerAddr Address of fund manager
     * @param _endpointAddr Local endpoint address
     * @param _raylsNodeEndpoint Rayls Node endpoint address
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 _fundManagerChainId,
        address _fundManagerAddr,
        address _endpointAddr,
        address _raylsNodeEndpoint
    ) RaylsErc20Handler(
        name,
        symbol,
        _endpointAddr,
        _raylsNodeEndpoint,
        address(0), // governance
        msg.sender, // owner
        true        // enable proxy
    ) {
        epoint = EndpointV1(_endpointAddr);

        fundManagerFeeChainId = _fundManagerChainId;
        fundManagerAddr = _fundManagerAddr;

        // Grant roles to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, _fundManagerAddr); // Fund manager can mint
        _grantRole(BURNER_ROLE, msg.sender);
    }

    /**
     * @notice Get endpoint version (for verification)
     */
    function getVersion() public view returns (uint256) {
        return epoint.contractVersion();
    }

    /**
     * @notice Override decimals to use 6 (institutional standard)
     * @dev This is common for stablecoins and institutional tokens
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Initialize function for proxy deployments on destination chains
     * @dev Called by factory when deploying to new chain
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _fundManagerChainId Chain ID where fund manager operates
     * @param _fundManagerAddr Address of fund manager
     * @param _attestationUuid Initial attestation UID
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _fundManagerChainId,
        address _fundManagerAddr,
        bytes32 _attestationUuid
    ) public initializer {
        address _owner = _getOwnerAddressOnInitialize();
        address _endpoint = _getEndpointAddressOnInitialize();
        resourceId = _getResourceIdOnInitialize();

        tokenName = _name;
        tokenSymbol = _symbol;
        attestationUid = _attestationUuid;
        fundManagerFeeChainId = _fundManagerChainId;
        fundManagerAddr = _fundManagerAddr;

        _transferOwnership(_owner);
        endpoint = IRaylsEndpoint(_endpoint);

        // Grant roles on initialized chain
        _grantRole(MINTER_ROLE, _owner);
        _grantRole(BURNER_ROLE, _owner);
    }

    /**
     * @notice Generate initialization parameters for factory deployment
     * @dev Factory calls this to get the correct initialize() signature
     */
    function _generateInitializerParams()
        internal
        view
        override
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "initialize(string,string,uint256,address,bytes32)",
            tokenName,
            tokenSymbol,
            fundManagerFeeChainId,
            fundManagerAddr,
            attestationUid
        );
    }

    /**
     * @notice Set or update attestation UID
     * @dev Only admin can update attestation requirement
     */
    function setAttestationUuid(bytes32 _uuid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        attestationUid = _uuid;
    }

    /**
     * @notice Mint new tokens (REQUIRES ATTESTATION)
     * @dev Overrides parent to add attestation check
     * @param to Recipient address
     * @param amount Amount to mint (in token's decimals)
     */
    function mint(address to, uint256 amount) public override onlyRole(MINTER_ROLE) {
        require(attestationUid != bytes32(0), "No risk analysis attestation emitted yet");
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from caller's balance
     */
    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    /**
     * @notice Burn tokens from another account (requires allowance)
     */
    function burnFrom(address account, uint256 amount) public {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    /**
     * @notice Receive atomic teleport to resource ID
     * @dev Custom receive handler that uses resource ID for lookup
     */
    function receiveTeleportAtomicToResourceId(
        bytes32 resourceId,
        uint256 value
    ) public virtual receiveMethod {
        address to = epoint.getAddressByResourceId(resourceId);
        _mint(owner(), value);
        if (to != owner()) {
            _lock(to, value);
        }
    }

    /**
     * @notice Revert a failed atomic teleport
     * @dev Burns tokens that were minted for failed transfer
     */
    function revertTeleportBurnToResourceId(
        bytes32 resourceId,
        uint256 value
    ) public virtual receiveMethod {
        address to = epoint.getAddressByResourceId(resourceId);
        _burn(to, value);
    }

    /**
     * @notice Unlock tokens after successful atomic teleport
     * @dev Transfers from owner to recipient after confirmation
     */
    function unlockToResourceId(
        bytes32 resourceId,
        uint256 amount
    ) external virtual returns (bool) {
        address to = epoint.getAddressByResourceId(resourceId);
        if (to != owner()) {
            bool success = _unlock(to, amount);
            require(success, "cannot unlock the assets");
            _transfer(owner(), to, amount);
            return true;
        }
        return true;
    }
}
```

Reference: Based on `/rayls-sovereign-contracts/src/rayls-protocol/test-contracts/CustomTokenExample.sol`

#### Key Implementation Details

**Why 6 decimals?**

```solidity
function decimals() public pure override returns (uint8) {
    return 6;
}
```

- Standard for institutional tokens and stablecoins
- Reduces gas costs (smaller numbers)
- Matches traditional finance precision (e.g., 100.000000 = $100.00)

**Why attestation check?**

```solidity
function mint(address to, uint256 amount) public override onlyRole(MINTER_ROLE) {
    require(attestationUid != bytes32(0), "No risk analysis attestation emitted yet");
    _mint(to, amount);
}
```

- Ensures compliance before minting
- Attestation from external risk analysis system
- Prevents unauthorized token creation

**Why _generateInitializerParams()?**

```solidity
function _generateInitializerParams() internal view override returns (bytes memory) {
    return abi.encodeWithSignature(
        "initialize(string,string,uint256,address,bytes32)",
        tokenName, tokenSymbol, fundManagerFeeChainId, fundManagerAddr, attestationUid
    );
}
```

- Enables factory deployment on destination chains
- Factory reads this to call initialize() with correct parameters
- Must match initialize() signature exactly

### Step 3: Deploy to Chain A

Deploy your token to the origin chain (Privacy Node Ledger A).

#### Deployment Command

```bash
npx hardhat tokens:erc20:deploy \
  --pl A \
  --name "Institutional Token" \
  --symbol "INST"
```

**What happens:**

1. Checks for duplicate name/symbol
2. Deploys token contract with your parameters
3. Authorizes token with EndpointV1
4. Returns deployment address

Registration on the PN Token Registry is a separate step (`tokens:register`) — see Step 4.

#### Expected Output

```
✅ Token name and symbol are unique. Proceeding with deployment...
Token Deployed At Address 0x1234567890abcdef1234567890abcdef12345678
Token Deployer Address: 0xabcdef1234567890abcdef1234567890abcdef12
Token authorized successfully for endpoint access
Next, register the token on the PN Token Registry:
  npx hardhat tokens:register --pl A --token-address 0x123...
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Deploy.ts`

#### Verify Deployment

```bash
# Check token exists
cast code 0x1234567890abcdef1234567890abcdef12345678 --rpc-url $RPC_URL_NODE_A

# Verify token name and symbol
cast call 0x123... "name()(string)" --rpc-url $RPC_URL_NODE_A
cast call 0x123... "symbol()(string)" --rpc-url $RPC_URL_NODE_A

# Check decimals (should be 6)
cast call 0x123... "decimals()(uint8)" --rpc-url $RPC_URL_NODE_A

# Verify owner
cast call 0x123... "owner()(address)" --rpc-url $RPC_URL_NODE_A
```

#### Post-Deployment: Set Attestation

After deployment, set the initial attestation UID:

```bash
# As admin/owner
cast send 0x123... \
  "setAttestationUuid(bytes32)" \
  "0xabc123def456..." \
  --private-key $PRIVATE_KEY_USER \
  --rpc-url $RPC_URL_NODE_A
```

**Why?** Without an attestation UID, minting will fail with: `"No risk analysis attestation emitted yet"`

### Step 4: Register and Activate the Token

Register the token on the Privacy Node, authorize it locally, then submit it to the Private Network Hub to enable cross-chain functionality. See the [PN Token Registry](../../learn/components/smart-contracts/pn-token-registry.md) page for the full three-status model.

#### Register on the PN Token Registry

```bash
npx hardhat tokens:register --pl A --token-address 0x123...
```

This calls `PNTokenRegistryV1.registerToken(tokenAddress)` (single argument, no storage slot) and sets `privacyNodeStatus = WAITING_APPROVAL`.

#### Authorize on the Privacy Node

```bash
npx hardhat tokens:approve-pn --symbol INST
```

Calls `updatePrivacyNodeStatus(tokenAddress, AUTHORIZED)` (`AUTHORIZED` = 2). The token is now operational locally.

#### Submit to the Hub and Approve

```bash
# Submit to the Hub (requires PN AUTHORIZED)
npx hardhat submitTokenToHub --symbol INST

# The Hub operator approves on the Hub-side TokenRegistryV1
npx hardhat tokens:approve-hub --symbol INST
```

**What happens on Hub approval:**

```typescript
// Hub-side TokenRegistryV1 — value 1 = ACTIVE
const STATUS_ACTIVE = 1n;
await tokenRegistry.updateStatus(resourceId, STATUS_ACTIVE);
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/`

**What happens next:**

- The Hub emits its token status event
- The relayer delivers the `activateToken(bytes32,address,uint8)` callback to the PN Token Registry, which registers the resource ID locally and sets `hubStatus = AUTHORIZED`

#### Verify Resource ID Reception

```bash
npx hardhat tokens:check-resource-id \
  --pl A \
  --token-address 0x123...
```

**Expected output (success):**

```
The token got successfully registered with the resourceId 0xabc123def456789...

👉 Add the variable below in .env to interact with this token.
Always mention by symbol with flag --token INST

TOKEN_INST_RESOURCE_ID=0xabc123def456789...
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/checkTokenResourceId.ts:39-46`

**If you see "No resource id generated":**

- Wait 30-60 seconds for relayer to deliver message
- Check relayer is running
- Verify operator actually approved the token
- See [Troubleshooting: Missing Environment Variables](troubleshooting.md#issue-2-missing-environment-variables)

#### Update .env File

Add the resourceId to your `.env`:

```bash
# Add to .env
TOKEN_INST_RESOURCE_ID=0xabc123def456789...
TOKEN_INST_ADDRESS_A=0x1234567890abcdef1234567890abcdef12345678
```

### Step 5: Deploy to Chain B

Your token will be automatically deployed to Chain B during the first cross-chain transfer, or you can deploy manually.

#### Option A: Automatic Deployment (Recommended)

The factory will automatically deploy your token on Chain B when you send the first teleport.

**How it works:**

1. You call `teleport()` from Chain A to Chain B
2. Relayer delivers message to Chain B
3. Chain B checks: Does this resourceId have a local address?
4. If NO → Factory deploys proxy automatically
5. Factory calls `initialize()` with parameters from `_generateInitializerParams()`
6. Token is ready on Chain B

**Advantages:**

- No manual deployment needed
- Automatic endpoint authorization
- Same resourceId across all chains

#### Option B: Manual Deployment

Deploy explicitly before first transfer:

```bash
npx hardhat tokens:erc20:deploy \
  --pl B \
  --name "Institutional Token" \
  --symbol "INST"
```

**Note:** Manual deployment will receive the same resourceId from the Private Network Hub.

#### Verify Deployment on Chain B

After first transfer (or manual deployment):

```bash
# Get token address on Chain B using resourceId
cast call $ENDPOINT_ADDRESS_B \
  "getAddressByResourceId(bytes32)(address)" \
  $TOKEN_INST_RESOURCE_ID \
  --rpc-url $RPC_URL_NODE_B

# Verify decimals match (should be 6)
cast call $TOKEN_ADDRESS_B "decimals()(uint8)" --rpc-url $RPC_URL_NODE_B

# Check attestation UID matches
cast call $TOKEN_ADDRESS_B "attestationUid()(bytes32)" --rpc-url $RPC_URL_NODE_B
```

### Step 6: Execute Cross-Chain Transfer

Execute your first cross-chain transfer using atomic teleport for safety.

#### Mint Tokens on Chain A

First, mint some tokens to test with:

```bash
# Mint 1000 INST (with 6 decimals = 1000.000000)
cast send $TOKEN_ADDRESS_A \
  "mint(address,uint256)" \
  $USER_ADDRESS \
  1000000000 \
  --private-key $PRIVATE_KEY_USER \
  --rpc-url $RPC_URL_NODE_A
```

**Verify mint:**

```bash
cast call $TOKEN_ADDRESS_A \
  "balanceOf(address)(uint256)" \
  $USER_ADDRESS \
  --rpc-url $RPC_URL_NODE_A
# Should return: 1000000000 (1000.000000 INST)
```

#### Execute Atomic Teleport

Send tokens from Chain A to Chain B:

```bash
npx hardhat tokens:erc20:send \
  --symbol INST \
  --pl-origin A \
  --pl-dest B \
  --destination-address 0xBobAddress \
  --amount 100000000  # 100 INST with 6 decimals
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Send.ts:17-27`

**What happens under the hood:**

```typescript
// The send task calls teleportAtomic() on your token
const tx = await token.teleportAtomic(
  destinationAddress,
  amount,
  destinationChainId
);
```

#### Complete Transaction Flow

**Phase 1: Source Chain (A)**

```solidity
// teleportAtomic() on Chain A
1. Validate: to != 0x0, amount != 0, chainId != current
2. Burn tokens from sender: _burn(msg.sender, 100000000)
3. Send message via endpoint with atomic flag
4. Emit Transfer(sender, 0x0, 100000000)
```

**Phase 2: Relayer Transport**

- Relayer picks up MessageDispatched event
- Posts to Private Network Hub
- Hub routes to destination chain

**Phase 3: Destination Chain (B)**

```solidity
// If factory deployment needed
1. Factory deploys proxy on Chain B
2. Calls initialize() with parameters

// receiveTeleportAtomic() on Chain B
3. Mint 100 INST to owner: _mint(owner(), 100000000)
4. Lock for Bob: _lock(bob, 100000000)
5. Send confirmation back to Chain A

// After confirmation received
6. unlock() transfers from owner to Bob
```

Reference: Complete flow from `/rayls-sovereign-contracts/hardhat/test/e2e/Erc20.ts:112-134`

#### Monitor Transfer Progress

**Check balances before:**

```bash
# Balance on Chain A
cast call $TOKEN_ADDRESS_A "balanceOf(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL_NODE_A

# Balance on Chain B (should be 0 before first transfer)
cast call $TOKEN_ADDRESS_B "balanceOf(address)(uint256)" $BOB_ADDRESS --rpc-url $RPC_URL_NODE_B
```

**Wait 30-60 seconds for completion**

**Check balances after:**

```bash
# User balance on Chain A should decrease by 100 INST
cast call $TOKEN_ADDRESS_A "balanceOf(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL_NODE_A

# Bob balance on Chain B should increase by 100 INST
cast call $TOKEN_ADDRESS_B "balanceOf(address)(uint256)" $BOB_ADDRESS --rpc-url $RPC_URL_NODE_B
```

#### Expected Timeline

| Time | Event |
|------|-------|
| 0s | teleportAtomic() called on Chain A |
| 0-5s | Tokens burned on Chain A |
| 5-15s | Relayer picks up and posts to hub |
| 15-30s | Hub routes to Chain B |
| 30-45s | Chain B receives and executes |
| 45-60s | Confirmation sent back to Chain A |
| **60s** | **Transfer complete** |

Reference: Timing from [Transaction Lifecycle](transaction-lifecycle.md#timing)

### Step 7: Test Atomic Revert Scenario

Test the atomic revert protection by sending to an address that will fail on receive.

#### Understanding Atomic Reverts

Atomic teleport has a 4-payload system:

1. **Forward payload**: Regular receive on destination
2. **Forward revert payload**: Called if forward fails
3. **Backward payload**: Confirmation to source
4. **Backward revert payload**: Revert mint on source if backward fails

#### Setup: Use Test Address That Fails

TokenExample.sol has a special address that always reverts:

```solidity
address public constant addressToFail = address(0x0000000000000000000555000000000000001123);

function receiveTeleportAtomic(address to, uint256 value) public override receiveMethod {
    if (to == addressToFail) {
        revert("Destination address is the one that revert messages.");
    }
    super.receiveTeleportAtomic(to, value);
}
```

Reference: `/rayls-sovereign-contracts/src/rayls-protocol/test-contracts/TokenExample.sol:13-22`

#### Execute Failing Transfer

```bash
npx hardhat tokens:erc20:send \
  --symbol INST \
  --pl-origin A \
  --pl-dest B \
  --destination-address 0x0000000000000000000555000000000000001123 \
  --amount 50000000  # 50 INST
```

#### What Happens

**Initial balances:**

- Alice on Chain A: 900 INST (after previous transfer of 100)
- addressToFail on Chain B: 0 INST

**Transaction flow:**

```
1. Chain A: Burn 50 INST from Alice → Alice has 850 INST
2. Relayer: Message to Chain B
3. Chain B: receiveTeleportAtomic(addressToFail, 50) → REVERTS
4. Chain B: Execute forward revert payload
5. Chain B: Send revert message back to Chain A
6. Chain A: revertTeleportMint(alice, 50) → Mint 50 INST back
7. Alice back to 900 INST (tokens restored!)
```

Reference: Test pattern from `/rayls-sovereign-contracts/hardhat/test/e2e/Erc20.ts:136-160`

#### Verify Revert Protection

```bash
# Check Alice balance on Chain A (should be unchanged)
cast call $TOKEN_ADDRESS_A "balanceOf(address)(uint256)" $ALICE_ADDRESS --rpc-url $RPC_URL_NODE_A
# Returns: 900000000 (900 INST - same as before)

# Check addressToFail balance on Chain B (should be 0)
cast call $TOKEN_ADDRESS_B "balanceOf(address)(uint256)" 0x0000000000000000000555000000000000001123 --rpc-url $RPC_URL_NODE_B
# Returns: 0 (no tokens received)
```

**Key takeaway:** Atomic teleport prevents token loss. Even if the destination fails, tokens are automatically refunded.

### Step 8: Implement Monitoring

Set up monitoring to track token operations and cross-chain transfers in production.

#### Events to Monitor

**Token Transfer Events:**

```solidity
event Transfer(address indexed from, address indexed to, uint256 value);
```

Monitor on both chains:

```typescript
// Chain A token transfers
tokenA.on("Transfer", (from, to, amount, event) => {
  console.log(`Chain A Transfer: ${from} → ${to}: ${formatUnits(amount, 6)} INST`);
  // Log to database or monitoring system
});

// Chain B token transfers
tokenB.on("Transfer", (from, to, amount, event) => {
  console.log(`Chain B Transfer: ${from} → ${to}: ${formatUnits(amount, 6)} INST`);
});
```

**Endpoint Message Events:**

```solidity
event MessageDispatched(
    bytes32 indexed messageId,
    address indexed from,
    uint256 indexed toChainId,
    bytes32 to,
    bytes message
);
```

Monitor for cross-chain message initiation:

```typescript
endpointA.on("MessageDispatched", (messageId, from, toChainId, to, message) => {
  console.log(`Message dispatched: ${messageId}`);
  console.log(`  From: ${from} → Chain ${toChainId}`);
  // Track message lifecycle
});
```

**Message Execution Events:**

```solidity
event MessageIdExecuted(bytes32 indexed messageId, bool status);
```

Track execution on destination:

```typescript
messageExecutorB.on("MessageIdExecuted", (messageId, status) => {
  console.log(`Message ${messageId} executed: ${status ? 'SUCCESS' : 'FAILED'}`);
});
```

#### Complete Monitoring Script

```typescript
// monitoring.ts
import { ethers } from 'ethers';

// Setup providers
const providerA = new ethers.JsonRpcProvider(process.env.RPC_URL_NODE_A);
const providerB = new ethers.JsonRpcProvider(process.env.RPC_URL_NODE_B);

// Setup contracts
const tokenA = await ethers.getContractAt('MyInstitutionalToken', TOKEN_ADDRESS_A, providerA);
const tokenB = await ethers.getContractAt('MyInstitutionalToken', TOKEN_ADDRESS_B, providerB);
const endpointA = await ethers.getContractAt('EndpointV1', ENDPOINT_A, providerA);
const endpointB = await ethers.getContractAt('EndpointV1', ENDPOINT_B, providerB);

// Track cross-chain transfers
const pendingTransfers = new Map<string, {
  from: string,
  to: string,
  amount: bigint,
  timestamp: number,
  sourceChain: number,
  destChain: number
}>();

// Monitor dispatches from Chain A
endpointA.on("MessageDispatched", (messageId, from, toChainId, to, message) => {
  pendingTransfers.set(messageId, {
    from,
    to: to.toString(),
    amount: parseMessageAmount(message),
    timestamp: Date.now(),
    sourceChain: await endpointA.getChainId(),
    destChain: Number(toChainId)
  });

  console.log(`📤 Transfer initiated: ${messageId}`);
});

// Monitor executions on Chain B
const executorB = await ethers.getContractAt('MessageExecutor', EXECUTOR_B, providerB);
executorB.on("MessageIdExecuted", (messageId, status) => {
  const transfer = pendingTransfers.get(messageId);
  if (transfer) {
    const duration = Date.now() - transfer.timestamp;
    console.log(`✅ Transfer completed: ${messageId}`);
    console.log(`   Duration: ${duration}ms`);
    console.log(`   Status: ${status ? 'SUCCESS' : 'FAILED'}`);

    // Alert if took too long
    if (duration > 90000) { // 90 seconds
      console.warn(`⚠️  Slow transfer detected: ${duration}ms`);
    }

    pendingTransfers.delete(messageId);
  }
});

// Check for stuck transfers every 2 minutes
setInterval(() => {
  const now = Date.now();
  for (const [messageId, transfer] of pendingTransfers.entries()) {
    const age = now - transfer.timestamp;
    if (age > 120000) { // 2 minutes
      console.error(`🚨 STUCK TRANSFER: ${messageId}`);
      console.error(`   Age: ${Math.floor(age / 1000)}s`);
      console.error(`   From: ${transfer.from}`);
      console.error(`   To: ${transfer.to}`);
      // Alert operations team
    }
  }
}, 120000);

console.log("📊 Monitoring started for MyInstitutionalToken");
```

#### Metrics to Track

**Operational Metrics:**

- Total supply per chain
- Cross-chain transfer count
- Average transfer completion time
- Success rate (successful / total transfers)
- Revert rate (reverted / total transfers)

**Health Metrics:**

- Relayer availability
- RPC endpoint latency
- Message queue depth
- Stuck message count

**Business Metrics:**

- Daily volume per chain
- Unique users per chain
- Minting events (with attestation verification)
- Burning events

#### Dashboard Example

```typescript
// metrics.ts
interface Metrics {
  totalSupplyA: bigint;
  totalSupplyB: bigint;
  transfersToday: number;
  avgTransferTime: number;
  successRate: number;
  activeUsers: Set<string>;
}

async function collectMetrics(): Promise<Metrics> {
  return {
    totalSupplyA: await tokenA.totalSupply(),
    totalSupplyB: await tokenB.totalSupply(),
    transfersToday: await getTransfersToday(),
    avgTransferTime: await getAvgTransferTime(),
    successRate: await getSuccessRate(),
    activeUsers: await getActiveUsers()
  };
}

// Export metrics every 5 minutes
setInterval(async () => {
  const metrics = await collectMetrics();
  console.log('Metrics:', {
    totalSupply: formatUnits(metrics.totalSupplyA + metrics.totalSupplyB, 6),
    transfersToday: metrics.transfersToday,
    avgTime: `${metrics.avgTransferTime}ms`,
    successRate: `${(metrics.successRate * 100).toFixed(2)}%`,
    activeUsers: metrics.activeUsers.size
  });
}, 300000);
```

### Step 9: Security Review

Perform a comprehensive security review before production deployment.

#### Security Checklist

**✓ Access Control Review**

```bash
# Verify roles are correctly assigned
cast call $TOKEN_ADDRESS_A "hasRole(bytes32,address)(bool)" \
  $(cast keccak "MINTER_ROLE") \
  $ADMIN_ADDRESS \
  --rpc-url $RPC_URL_NODE_A

# Check DEFAULT_ADMIN_ROLE
cast call $TOKEN_ADDRESS_A "hasRole(bytes32,address)(bool)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $ADMIN_ADDRESS \
  --rpc-url $RPC_URL_NODE_A
```

**✓ receiveMethod Modifier on All Receive Functions**

Verify all receive functions have the `receiveMethod` modifier:

```solidity
// ✓ CORRECT - Has receiveMethod
function receiveTeleportAtomic(address to, uint256 value) public receiveMethod {
    // ...
}

// ✗ WRONG - Missing receiveMethod (vulnerability!)
function receiveTeleportAtomic(address to, uint256 value) public {
    // Anyone could call this and mint tokens!
}
```

Reference: [Security: Authorization](security.md#authorization-access-control)

**✓ Attestation Requirement**

```bash
# Verify attestation is set
cast call $TOKEN_ADDRESS_A "attestationUid()(bytes32)" --rpc-url $RPC_URL_NODE_A
# Should return non-zero value

# Try minting without attestation (should fail)
cast send $TOKEN_ADDRESS_TEST \
  "setAttestationUuid(bytes32)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  --private-key $PRIVATE_KEY_USER \
  --rpc-url $RPC_URL_NODE_A

cast send $TOKEN_ADDRESS_TEST \
  "mint(address,uint256)" \
  $USER_ADDRESS \
  1000 \
  --private-key $PRIVATE_KEY_USER \
  --rpc-url $RPC_URL_NODE_A
# Should revert with: "No risk analysis attestation emitted yet"
```

**✓ Input Validation**

All teleport functions validate inputs:

```solidity
// From RaylsErc20Handler
if (to == address(0) || value == 0 || chainId == 0) {
    revert RaylsErc20Handler__ZeroValueArg(to, value, chainId);
}
if (chainId == endpoint.getChainId()) {
    revert RaylsErc20Handler__WrongFunctionForSameChainId(chainId);
}
```

Test these validations:

```bash
# Should fail: zero address
cast send $TOKEN_ADDRESS_A "teleportAtomic(address,uint256,uint256)" \
  0x0000000000000000000000000000000000000000 100 $CHAIN_B_ID \
  --private-key $PRIVATE_KEY_USER --rpc-url $RPC_URL_NODE_A
# Reverts: RaylsErc20Handler__ZeroValueArg

# Should fail: same chain
cast send $TOKEN_ADDRESS_A "teleportAtomic(address,uint256,uint256)" \
  $USER_ADDRESS 100 $CHAIN_A_ID \
  --private-key $PRIVATE_KEY_USER --rpc-url $RPC_URL_NODE_A
# Reverts: RaylsErc20Handler__WrongFunctionForSameChainId
```

**✓ Atomic Operations**

Always use `teleportAtomic()` in production:

```typescript
// ✓ CORRECT - Atomic with revert protection
await token.teleportAtomic(to, amount, chainId);

// ✗ WRONG - No revert protection (use only for testing)
await token.teleport(to, amount, chainId);
```

**✓ Lock Mechanism**

Verify locked amounts are tracked correctly:

```bash
# Check locked amount for address
cast call $TOKEN_ADDRESS_B \
  "lockedAmount(address)(uint256)" \
  $USER_ADDRESS \
  --rpc-url $RPC_URL_NODE_B
```

**✓ Owner and Governance**

```bash
# Verify owner is correct
cast call $TOKEN_ADDRESS_A "owner()(address)" --rpc-url $RPC_URL_NODE_A

# If governance is set, verify it's correct
cast call $TOKEN_ADDRESS_A "governance()(address)" --rpc-url $RPC_URL_NODE_A
```

**✓ Test Unauthorized Access**

Try calling protected functions without permission:

```bash
# Try minting without MINTER_ROLE (should fail)
cast send $TOKEN_ADDRESS_A \
  "mint(address,uint256)" \
  $USER_ADDRESS \
  1000 \
  --private-key $UNAUTHORIZED_KEY \
  --rpc-url $RPC_URL_NODE_A
# Should revert: AccessControlUnauthorizedAccount
```

#### Audit Steps

1. **Review all custom overrides** for security issues
2. **Test revert scenarios** (destination fails, invalid inputs)
3. **Verify role assignments** on all chains
4. **Test unauthorized access attempts**
5. **Validate business logic** (attestation checks, fund manager integration)
6. **Check for reentrancy** (RaylsErc20Handler has guards)
7. **Verify proxy initialization** on destination chains
8. **Test edge cases** (zero amounts, same-chain transfers, double-spend)

Reference: Complete security guide in [Security](security.md)

### Step 10: Production Deployment

Deploy to production with proper safeguards and monitoring.

#### Pre-Production Checklist

**Code:**

- [ ] All tests passing
- [ ] Security audit complete
- [ ] Code review by 2+ developers
- [ ] No hardcoded values or test addresses
- [ ] Proper error handling

**Infrastructure:**

- [ ] Monitoring infrastructure ready
- [ ] Relayer operational and funded
- [ ] RPC endpoints configured and tested
- [ ] Backup RPC endpoints available
- [ ] Alert system configured

**Operations:**

- [ ] Deployment runbook prepared
- [ ] Rollback plan documented
- [ ] Incident response plan ready
- [ ] On-call engineer assigned
- [ ] Stakeholders notified

#### Deployment Sequence

**Step 1: Deploy to Production Chain A**

```bash
# Use production environment variables
export RPC_URL_NODE_A=https://prod-pl-a.example.com
export PRIVATE_KEY_SYSTEM=0x... # From secure key management
export PRIVATE_KEY_USER=0x...   # From secure key management

# Deploy
npx hardhat tokens:erc20:deploy \
  --pl A \
  --name "Institutional Token" \
  --symbol "INST" \
  --network production
```

**Step 2: Set Attestation**

```bash
# Set production attestation UID from compliance system
cast send $TOKEN_ADDRESS_A \
  "setAttestationUuid(bytes32)" \
  $PRODUCTION_ATTESTATION_UID \
  --private-key $PRIVATE_KEY_SYSTEM \
  --rpc-url $RPC_URL_NODE_A
```

**Step 3: Grant Roles**

```bash
# Grant MINTER_ROLE to fund manager
cast send $TOKEN_ADDRESS_A \
  "grantRole(bytes32,address)" \
  $(cast keccak "MINTER_ROLE") \
  $FUND_MANAGER_ADDRESS \
  --private-key $PRIVATE_KEY_SYSTEM \
  --rpc-url $RPC_URL_NODE_A

# Grant BURNER_ROLE to operations account
cast send $TOKEN_ADDRESS_A \
  "grantRole(bytes32,address)" \
  $(cast keccak "BURNER_ROLE") \
  $OPERATIONS_ADDRESS \
  --private-key $PRIVATE_KEY_SYSTEM \
  --rpc-url $RPC_URL_NODE_A
```

**Step 4: Register and Activate**

```bash
# Register on the PN Token Registry
npx hardhat tokens:register --pl A --token-address $TOKEN_ADDRESS_A --network production

# PN operator authorizes locally
npx hardhat tokens:approve-pn --symbol INST --network production

# Submit to the Hub and have the Hub operator approve
npx hardhat submitTokenToHub --symbol INST --network production
npx hardhat tokens:approve-hub --symbol INST --network production

# Verify resourceId received (via the activateToken callback)
npx hardhat tokens:check-resource-id \
  --pl A \
  --token-address $TOKEN_ADDRESS_A \
  --network production
```

**Step 5: Test with Small Amounts**

```bash
# Mint small test amount (10 INST)
cast send $TOKEN_ADDRESS_A \
  "mint(address,uint256)" \
  $TEST_USER_ADDRESS \
  10000000 \
  --private-key $PRIVATE_KEY_SYSTEM \
  --rpc-url $RPC_URL_NODE_A

# Test cross-chain transfer (1 INST)
npx hardhat tokens:erc20:send \
  --symbol INST \
  --pl-origin A \
  --pl-dest B \
  --destination-address $TEST_USER_ADDRESS \
  --amount 1000000 \
  --network production
```

**Step 6: Verify on Chain B**

```bash
# Wait for factory deployment (60-90 seconds)
sleep 90

# Verify token deployed on Chain B
cast call $ENDPOINT_ADDRESS_B \
  "getAddressByResourceId(bytes32)(address)" \
  $TOKEN_INST_RESOURCE_ID \
  --rpc-url $RPC_URL_NODE_B

# Verify balance received
cast call $TOKEN_ADDRESS_B \
  "balanceOf(address)(uint256)" \
  $TEST_USER_ADDRESS \
  --rpc-url $RPC_URL_NODE_B
```

**Step 7: Enable Monitoring**

```bash
# Start monitoring service
pm2 start monitoring.ts --name inst-monitor

# Verify metrics collection
curl http://localhost:3000/metrics
```

**Step 8: Gradual Rollout**

- Week 1: Test users only (< 1000 INST total)
- Week 2: Limited production (< 10,000 INST)
- Week 3: Increased limits (< 100,000 INST)
- Week 4+: Full production

#### Post-Deployment

**Documentation:**

- Document all contract addresses
- Update `.env` files with production values
- Create operations runbook
- Document monitoring dashboards

**Update Configuration:**

```bash
# Production .env
TOKEN_INST_RESOURCE_ID=0xabc123...
TOKEN_INST_ADDRESS_A=0x123...
TOKEN_INST_ADDRESS_B=0x456...
FUND_MANAGER_ADDRESS=0x789...
ATTESTATION_UID=0xdef...
```

**Ongoing Maintenance:**

- Monitor for frozen tokens
- Track balance updates
- Review attestation renewals
- Update roles as needed
- Monitor relayer health
- Track gas costs
- Review security alerts

#### Emergency Procedures

**If issues detected:**

1. **Pause operations** (if pause functionality implemented)
2. **Alert stakeholders** immediately
3. **Investigate root cause** with monitoring data
4. **Execute rollback** if necessary
5. **Document incident** for post-mortem

**Rollback procedure:**

- Cannot delete deployed contracts
- Can freeze the token on the PN Token Registry (`freezeOnPrivacyNode`)
- Can revoke roles to stop minting
- Can pause transfers (if Pausable implemented)

## Summary

Congratulations! You've completed a full end-to-end implementation of a production-ready cross-chain institutional token.

### What You Accomplished

✅ **Designed** a custom institutional token with compliance requirements
✅ **Implemented** role-based access control and attestation checks
✅ **Deployed** to multiple chains with proper registration
✅ **Executed** cross-chain transfers with atomic safety
✅ **Tested** revert protection and failure scenarios
✅ **Implemented** production monitoring and alerting
✅ **Performed** security review and validation
✅ **Deployed** to production with proper safeguards

### Key Takeaways

1. **Always use atomic teleport** for production transfers
2. **attestation checks** provide compliance guarantees
3. **Role-based access** prevents unauthorized operations
4. **Factory deployment** simplifies multi-chain setup
5. **Monitoring is critical** for production operations
6. **Security review** must cover all custom logic
7. **Gradual rollout** reduces production risk

### Next Steps

- [Transaction Lifecycle](transaction-lifecycle.md) - Deep dive into message flow
- [Security](security.md) - Advanced security patterns
- [Testing](testing.md) - Comprehensive testing strategies
- [Troubleshooting](troubleshooting.md) - Debug production issues

## Related Documentation

- [Deployment Workflow](deployment-workflow.md) - Detailed deployment guide
- [Building Custom Tokens](building-custom-tokens.md) - More customization patterns
- [Token Standards](token-standards.md) - Understanding handlers
- [Endpoint Integration](endpoint-integration.md) - Advanced cross-chain patterns
- [EIP-5164 Explained](eip-5164-explained.md) - Protocol deep dive
