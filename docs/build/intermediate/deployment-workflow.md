# Deployment Workflow

## Overview

This guide covers the complete workflow for deploying custom tokens across multiple chains in the Rayls network. You'll learn how to deploy tokens, register them with the Private Network Hub, synchronize addresses across chains, and verify successful deployment.

## What You'll Learn

- Pre-deployment validation and environment setup
- Multi-chain deployment strategies (manual vs factory deployment)
- Token registration process with the Private Network Hub
- Contract address synchronization across chains
- Post-deployment verification and validation
- Common deployment issues and solutions

## Prerequisites

Before following this guide, you should have:

- Completed [Building Custom Tokens](building-custom-tokens.md) - Know how to create custom tokens
- Understanding of [Token Standards](token-standards.md) - Familiar with token handlers
- Development environment set up (see [Beginner: Docker Setup](../beginner/docker-setup.md))
- Access to Privacy Node Ledgers and Private Network Hub
- Appropriate private keys and RPC endpoints configured

## 1. Pre-Deployment Checklist

Before deploying your token, validate your environment and configuration to avoid common issues.

### Environment Setup Validation

**Check RPC connectivity for all chains:**

```bash
# Test Privacy Node Ledger A
curl -X POST $RPC_URL_NODE_A \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Test Private Network Hub
curl -X POST $RPC_URL_NODE_CC \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Verify required environment variables:**

Your `.env` file must contain:

```bash
# RPC endpoints
RPC_URL_NODE_A=https://...  # Privacy Node Ledger A
RPC_URL_NODE_B=https://...  # Privacy Node Ledger B
RPC_URL_NODE_CC=https://...  # Private Network Hub (legacy variable name)

# Private keys
PRIVATE_KEY_SYSTEM=0x...  # System operator account
PRIVATE_KEY_USER=0x...    # Token deployer account

# Contract addresses
NODE_A_DEPLOYMENTPROXYREGISTRY=0x...  # Privacy Node Ledger A
NODE_B_DEPLOYMENTPROXYREGISTRY=0x...  # Privacy Node Ledger B
NODE_CC_DEPLOYMENTPROXYREGISTRY=0x...  # Private Network Hub (legacy variable name)
NODE_A_RAYLS_NODE_ENDPOINT_ADDRESS=0x...
NODE_A_RAYLS_NODE_USER_GOVERNANCE=0x...
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Deploy.ts:27-46`

### Token Uniqueness Check

**CRITICAL:** Always check for duplicate token names or symbols before deployment. The deployment script automatically performs this check:

```typescript
// Automatic uniqueness validation (reads the Hub TokenRegistry)
const existingTokens = await TokenRegistry.getAllTokens({ gasLimit: 5000000 });

// Check for duplicate name (case-insensitive)
const duplicateName = existingTokens.find(
  (token: any) => token.name.toLowerCase() === taskArgs.name.toLowerCase()
);

// Check for duplicate symbol (case-insensitive)
const duplicateSymbol = existingTokens.find(
  (token: any) => token.symbol.toLowerCase() === taskArgs.symbol.toLowerCase()
);
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Deploy.ts:59-85`

**If a duplicate is found:**

```bash
❌ A token with the symbol "MTK" already exists!
   ResourceId: 0xabc123...
   Name: MyToken
   Status: ACTIVE
```

**Solution:** Choose a different name or symbol before deployment.

### Account Verification

**System operator account** (PRIVATE_KEY_SYSTEM) must have:

- Gas balance on all chains (for authorization and approval transactions)
- Authorization to approve tokens in TokenRegistry
- Permission to add authorized addresses to Endpoint

**User account** (PRIVATE_KEY_USER) must have:

- Gas balance for token deployment
- Proper permissions if custom access control is implemented

**Check balances:**

```bash
# Check deployer balance
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL_NODE_A

# Check system operator balance
cast balance $OPERATOR_ADDRESS --rpc-url $RPC_URL_NODE_CC
```

### Contract Registry Verification

Ensure DeploymentProxyRegistry addresses are configured for all chains:

```bash
# Verify registry on Chain A
cast call $NODE_A_DEPLOYMENTPROXYREGISTRY \
  "getContract(string)(address)" "Endpoint" \
  --rpc-url $RPC_URL_NODE_A

# Should return non-zero address
```

## 2. Multi-Chain Deployment Strategy

There are two approaches to deploying tokens across multiple chains: manual deployment and factory-based automatic deployment.

### Deployment Order

The standard deployment flow is:

1. **Deploy on Chain A** (origin/source chain)
2. **Authorize with EndpointV1** on Chain A
3. **Register on the PN Token Registry** (`registerToken` → `privacyNodeStatus = WAITING_APPROVAL`)
4. **Authorize on the Privacy Node** (`updatePrivacyNodeStatus(AUTHORIZED)`) — token is now operational locally
5. **Submit to the Private Network Hub** (`submitToHub`), then the Hub operator approves (`updateStatus(resourceId, ACTIVE)`)
6. **Receive the `activateToken` callback** — the PN sets the resource ID and `hubStatus = AUTHORIZED`
7. **Deploy on Chain B** (automatic via factory or manual)

See the [PN Token Registry](../../learn/components/smart-contracts/pn-token-registry.md) page for the full lifecycle and the three-status model.

### Method 1: Manual Deployment

Use this approach when you want explicit control over deployment on each chain.

**Deploy token on Chain A:**

```bash
npx hardhat tokens:erc20:deploy \
  --pl A \
  --name "My Institutional Token" \
  --symbol "INST"
```

**What happens behind the scenes:**

```typescript
// 1. Validates token name/symbol uniqueness
// 2. Deploys token contract
const tokenPL = await token.connect(signer).deploy(
  taskArgs.name,
  taskArgs.symbol,
  endpointAddress,
  raylsNodeEndpointAddress,
  governanceAddress,
  { gasLimit: 5000000 }
);

// 3. Authorizes token with endpoint (as system operator)
const endpointContract = await hre.ethers.getContractAt('EndpointV1', contracts[0], operatorSigner);
const authTx = await endpointContract.addAuthorizedAddresses([tokenAddress]);
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Deploy.ts`

!!! note "Deploy no longer registers"
    `tokens:erc20:deploy` now **only deploys and authorizes** the token. Registration is a separate step on the PN Token Registry (`tokens:register`) — see [Token Registration Process](#3-token-registration-process) below. There is no storage-slot argument anywhere in the new flow.

**Expected output:**

```
Token Deployed At Address 0x123abc...
Token authorized successfully for endpoint access
Next, register the token on the PN Token Registry:
  npx hardhat tokens:register --pl A --token-address 0x123abc...
```

### Method 2: Factory Deployment

Factory deployment automatically deploys your token on destination chains during the first cross-chain transfer.

**How it works:**

```solidity
// From RaylsContractFactoryV1.sol
function deployProxyContractForResource(
    bytes32 resourceId,
    bytes memory initializerFunctionParams
) external override onlyFromCommitChain returns (address) {
    // 1. Get token info from hub
    // 2. Create proxy using CREATE2 for deterministic address
    address proxy = address(new TransparentProxy{ salt: salt }(
        implementationAddress,
        address(proxyAdmin),
        initializerFunctionParams
    ));

    // 3. Authorize with local endpoint
    EndpointV1(endpoint).addAuthorizedAddresses(addressesToAuthorize);

    return proxy;
}
```

Reference: `/rayls-sovereign-contracts/src/rayls-protocol/RaylsContractFactory/RaylsContractFactoryV1.sol:39-60`

**Advantages:**

- Automatic deployment on first use
- Deterministic addresses (CREATE2)
- Automatic endpoint authorization
- No manual deployment needed on each chain

**Disadvantages:**

- Less control over deployment timing
- Requires proper `_generateInitializerParams()` implementation

## 3. Token Registration Process

After deployment on the origin chain, register your token on the **PN Token Registry** (`PNTokenRegistryV1`). Registration always originates on the Privacy Node; submitting to the Hub for cross-chain functionality is a subsequent step that requires the token to be PN `AUTHORIZED` first.

For the complete architecture and the three independent status state machines, see the [PN Token Registry](../../learn/components/smart-contracts/pn-token-registry.md) page.

### Step-by-Step Registration

#### Step 1: Register on the PN Token Registry

```bash
npx hardhat tokens:register --pl A --token-address 0x123abc...
```

Under the hood this calls the registry facade with a **single argument — no storage slot**:

```solidity
// PNTokenRegistryV1
PNTokenRegistryV1.registerToken(tokenAddress);
```

**What this does:**

- Reads `name` / `symbol` / `totalSupply` on-chain from the token
- Enforces symbol uniqueness on this Privacy Node
- Sets `privacyNodeStatus = WAITING_APPROVAL`

#### Step 2: Authorize on the Privacy Node

The PN operator reviews the token off-chain and authorizes it locally:

```bash
npx hardhat tokens:approve-pn --symbol INST
```

Under the hood (`AUTHORIZED` = numeric `2`):

```solidity
// PNTokenRegistryV1 — PN operator / local admin
PNTokenRegistryV1.updatePrivacyNodeStatus(tokenAddress, AUTHORIZED); // AUTHORIZED = 2
```

Once `privacyNodeStatus = AUTHORIZED`, the token is operational locally (mint / transfer / handler ops).

Batch variants exist for convenience: `tokens:approve-all-pn`, `tokens:approve-last-pn`, `tokens:approve-last-batch-pn`.

#### Step 3: Submit to the Private Network Hub (optional, for cross-chain)

To make the token usable cross-chain, submit it to the Hub. This preflight **requires PN `AUTHORIZED`**:

```bash
npx hardhat submitTokenToHub --symbol INST
```

Under the hood:

```solidity
// PNTokenRegistryV1 — sets hubStatus = WAITING_APPROVAL and sends addToken() to the Hub registry
PNTokenRegistryV1.submitToHub(tokenAddress);
```

#### Step 4: Hub Approval

The Private Network Hub operator approves the token on the **Hub-side** `TokenRegistryV1` (`ACTIVE` = `1`):

```bash
npx hardhat tokens:approve-hub --symbol INST
```

Under the hood:

```typescript
// Hub-side TokenRegistryV1 — value 1 = ACTIVE
const STATUS_ACTIVE = 1n;
await tokenRegistry.updateStatus(resourceId, STATUS_ACTIVE, { gasLimit: GAS_LIMIT });
```

The `tokens:approve-hub` task resolves the resource ID from the `TOKEN_<SYM>_RESOURCE_ID` environment variable.

#### Step 5: `activateToken` Callback

After Hub approval, the relayer delivers the Hub → PN callback that replaces the old resource-ID callback:

```solidity
// Delivered to the PN Token Registry (token.pnRegistryAddress)
function activateToken(bytes32 resourceId, address tokenAddress, uint8 standard) external;
```

**This callback:**

- Registers the resource ID in the local Endpoint (via `setResourceId` on the `RaylsApp` base)
- Sets `hubStatus = AUTHORIZED`
- Enables cross-chain message routing

### Verification Command

Check if your token successfully received its resourceId:

```bash
npx hardhat tokens:check-resource-id \
  --pl A \
  --token-address 0x123abc...
```

**Expected output (success):**

```
The token got successfully registered with the resourceId 0xabc123def456...

👉 Add the variable below in .env to interact with this token.
Always mention by symbol with flag --token INST

TOKEN_INST_RESOURCE_ID=0xabc123def456...
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/checkTokenResourceId.ts`

**Expected output (not registered yet):**

```
No resource id generated! Wait until the PNH Operator approves the token.
If so, check if relayer is working properly
```

### Registration Statuses (three independent state machines)

The PN Token Registry tracks **three independent statuses** per token, each owned by a different actor. A token can be authorized locally without ever being submitted to the Hub or a public chain.

| Status enum | Values | Owner | Governs |
|-------------|--------|-------|---------|
| `PrivacyNodeStatus` | `UNDEFINED`, `WAITING_APPROVAL`, `AUTHORIZED`, `UNAUTHORIZED`, `FROZEN` | PN operator / local admin | Local operability (mint / transfer / handler ops). `FROZEN` blocks **all** operations. |
| `HubStatus` | `UNDEFINED`, `WAITING_APPROVAL`, `AUTHORIZED`, `UNAUTHORIZED`, `FROZEN` | Private Network Hub (cross-chain callbacks) | Hub cross-chain operability for this token. |
| `PublicChainStatus` | `UNDEFINED`, `PENDING_DEPLOYMENT`, `DEPLOYED`, `FROZEN`, `DEPRECATED` | Relayer / bridge | The public-chain mirror. |

!!! info "Two distinct approvals"
    - **PN approval** — `updatePrivacyNodeStatus(tokenAddress, AUTHORIZED)` (`AUTHORIZED` = `2`) enables local operability.
    - **Hub approval** — the Hub operator calls `updateStatus(resourceId, ACTIVE)` (`ACTIVE` = `1`) on the **Hub-side** registry; the relayer then delivers the `activateToken` callback that sets `hubStatus = AUTHORIZED` on the PN side. Never conflate the two status models.

## 4. Address Synchronization Across Chains

Understanding how token addresses are tracked across multiple chains is crucial for cross-chain operations.

### Resource ID Concept

**Key principle:** Same resourceId on ALL chains, different contract addresses per chain.

```
Chain A: Token at 0x111... → resourceId 0xabc...
Chain B: Token at 0x222... → resourceId 0xabc... (same!)
Chain C: Token at 0x333... → resourceId 0xabc... (same!)
```

The ResourceRegistry on each chain maintains the mapping:

```solidity
mapping(bytes32 resourceId => address contractAddress)
```

### Tracking Pattern

**Query token address by resourceId on any chain:**

```typescript
// Get token address on Chain B using resourceId
const endpoint = await ethers.getContractAt('EndpointV1', ENDPOINT_ADDRESS_B);
const tokenAddress = await endpoint.getAddressByResourceId(resourceId);
```

Reference: e2e test pattern from `/rayls-sovereign-contracts/hardhat/test/e2e/Erc20.ts:86-100`

**In smart contracts:**

```solidity
// Send message to token on another chain
bytes32 destinationResourceId = TOKEN_RESOURCE_ID;
endpoint.dispatchMessage(
    destinationChainId,
    destinationResourceId, // Router finds address automatically
    payload
);
```

### Environment Variable Pattern

For development and testing, track token addresses in your `.env`:

```bash
# Resource ID (same across all chains)
TOKEN_INST_RESOURCE_ID=0xabc123def456...

# Contract addresses (different per chain)
TOKEN_INST_ADDRESS_A=0x111...
TOKEN_INST_ADDRESS_B=0x222...
TOKEN_INST_ADDRESS_C=0x333...
```

**Query addresses:**

```bash
# Get address on Chain A
cast call $ENDPOINT_ADDRESS_A \
  "getAddressByResourceId(bytes32)(address)" \
  $TOKEN_INST_RESOURCE_ID \
  --rpc-url $RPC_URL_NODE_A

# Get address on Chain B
cast call $ENDPOINT_ADDRESS_B \
  "getAddressByResourceId(bytes32)(address)" \
  $TOKEN_INST_RESOURCE_ID \
  --rpc-url $RPC_URL_NODE_B
```

### Synchronization Timing

**When does synchronization happen?**

1. **Origin chain (A):** Immediately after the `activateToken` callback registers the resource ID
2. **Destination chains (B, C...):** During factory deployment OR manual registration

**Wait for synchronization:**

```typescript
// Poll until address is available
let tokenAddress = '0x0000000000000000000000000000000000000000';
while (tokenAddress === '0x0000000000000000000000000000000000000000') {
  tokenAddress = await endpoint.getAddressByResourceId(resourceId);
  await new Promise(resolve => setTimeout(resolve, 5000)); // Wait 5s
}
```

## 5. Verification and Validation Checklist

After deployment, verify everything is configured correctly before using your token.

### Post-Deployment Checklist

Use this checklist to validate successful deployment:

#### ✓ Token Deployed Successfully

```bash
# Verify contract exists
cast code $TOKEN_ADDRESS --rpc-url $RPC_URL_NODE_A | grep -q "0x" && echo "Contract deployed" || echo "No contract"

# Check token symbol
cast call $TOKEN_ADDRESS "symbol()(string)" --rpc-url $RPC_URL_NODE_A
```

#### ✓ Token Authorized with Endpoint

```bash
# Check authorization
cast call $ENDPOINT_ADDRESS \
  "isAuthorizedAddress(address)(bool)" \
  $TOKEN_ADDRESS \
  --rpc-url $RPC_URL_NODE_A

# Expected: true
```

#### ✓ Registered on the PN Token Registry

Query the PN Token Registry (`tokens:statuses`) and confirm the token has `privacyNodeStatus = WAITING_APPROVAL` or `AUTHORIZED`.

#### ✓ Authorized on the Privacy Node

```bash
# privacyNodeStatus should be AUTHORIZED (2)
# Query via tokens:statuses (PN registry: getPrivacyNodeStatus / getAllTokens)
```

#### ✓ Hub Approved Token

```bash
# After submitToHub, the Hub operator sets Hub status ACTIVE (1)
# The activateToken callback then sets hubStatus = AUTHORIZED on the PN side
```

#### ✓ Token Received Resource ID

```bash
# Check resourceId is not zero
cast call $TOKEN_ADDRESS \
  "resourceId()(bytes32)" \
  --rpc-url $RPC_URL_NODE_A

# Expected: 0xabc123... (not 0x0000...0000)
```

#### ✓ Resource ID Registered with Local Endpoint

```bash
# Verify mapping exists
cast call $ENDPOINT_ADDRESS \
  "getAddressByResourceId(bytes32)(address)" \
  $RESOURCE_ID \
  --rpc-url $RPC_URL_NODE_A

# Expected: $TOKEN_ADDRESS
```

#### ✓ Token Callable by Owner

```bash
# Test basic owner function
cast call $TOKEN_ADDRESS \
  "owner()(address)" \
  --rpc-url $RPC_URL_NODE_A

# Should return deployer address
```

#### ✓ Basic Operations Work

```bash
# Test balance query
cast call $TOKEN_ADDRESS \
  "balanceOf(address)(uint256)" \
  $OWNER_ADDRESS \
  --rpc-url $RPC_URL_NODE_A

# Test decimals
cast call $TOKEN_ADDRESS \
  "decimals()(uint8)" \
  --rpc-url $RPC_URL_NODE_A
```

### Common Validation Failures

**Issue: resourceId returns 0x0000...0000**

- **Cause:** Token not approved yet OR relayer not delivering messages
- **Solution:** Run approval command, verify relayer is operational
- **Reference:** [Troubleshooting](troubleshooting.md#issue-4-no-resource-id-received)

**Issue: "Token not authorized" error**

- **Cause:** Missing endpoint authorization
- **Solution:** Add token to authorized addresses in endpoint
- **Command:** See Section 6 below

**Issue: "Token frozen" error**

- **Cause:** The token is not `AUTHORIZED` on the PN Token Registry, or a `FROZEN` status blocks the operation
- **Solution:** PN operator authorizes locally with `tokens:approve-pn`; for cross-chain, submit to the Hub and have the Hub operator approve (`tokens:approve-hub`)

## 6. Common Deployment Issues

### Issue 1: Duplicate Token Name/Symbol

**Error message:**

```
❌ A token with the symbol "MTK" already exists!
   ResourceId: 0xabc123...
   Name: MyToken
   Status: ACTIVE
Error: Duplicate token symbol detected: "MTK". Please choose a different symbol.
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Deploy.ts:78-84`

**Solution:**

- Choose a different name or symbol
- Check existing tokens before deployment:

```bash
# Query all tokens (on Private Network Hub)
cast call $TOKEN_REGISTRY_ADDRESS \
  "getAllTokens()(tuple[])" \
  --rpc-url $RPC_URL_NODE_CC
```

**Prevention:**

The deployment script automatically checks for duplicates (lines 24-86 in erc20Deploy.ts).

### Issue 2: Missing Environment Variables

**Error message:**

```
Error: RPC_URL_NODE_CC is not set in the .env file. Cannot verify token uniqueness.
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Deploy.ts:28-30`

**Required variables:**

```bash
RPC_URL_NODE_A=...
RPC_URL_NODE_CC=...
PRIVATE_KEY_SYSTEM=...
PRIVATE_KEY_USER=...
NODE_A_DEPLOYMENTPROXYREGISTRY=...
NODE_CC_DEPLOYMENTPROXYREGISTRY=...
```

**Solution:**

Copy from `.env.example` and fill in values for your environment.

### Issue 3: Authorization Failure

**Error message:**

```
Error: Endpoint__NotAuthorizedAddress()
```

**Cause:** Token not added to endpoint's authorized addresses list.

**Solution:**

```bash
# Authorize token manually (as system operator)
cast send $ENDPOINT_ADDRESS \
  "addAuthorizedAddresses(address[])" \
  "[$TOKEN_ADDRESS]" \
  --private-key $PRIVATE_KEY_SYSTEM \
  --rpc-url $RPC_URL_NODE_A
```

**Note:** The deployment script does this automatically (lines 111-122 in erc20Deploy.ts), but manual authorization may be needed if deployment was interrupted.

### Issue 4: Resource ID Not Received

**Symptom:** resourceId remains `0x0000000000000000000000000000000000000000` after approval.

**Possible causes:**

1. **Token not submitted to the Hub or not yet approved there**
   - Confirm the token was submitted: `npx hardhat submitTokenToHub --symbol MTK` (requires PN `AUTHORIZED`)
   - Run Hub approval: `npx hardhat tokens:approve-hub --symbol MTK`

2. **Relayer not running or not delivering messages**
   - Check relayer logs for errors
   - Verify relayer has gas on all chains
   - Check MessageDispatched events on Private Network Hub

3. **`hubStatus` still `WAITING_APPROVAL`**
   - Query the PN registry: `npx hardhat tokens:statuses`
   - Filter by symbol and check the Hub status field
   - `hubStatus` should be `AUTHORIZED` after the `activateToken` callback

**Diagnostic:**

```bash
# Check resourceId
npx hardhat tokens:check-resource-id --pl A --token-address $TOKEN_ADDRESS

# If returns "No resource id generated", check above causes
```

### Issue 5: Factory Deployment Initialization Failed

**Error message:**

```
Error: Failed on contract initialization while deploying a resource locally
```

Reference: `/rayls-sovereign-contracts/src/rayls-protocol/RaylsContractFactory/RaylsContractFactoryV1.sol:48`

**Cause:** Incorrect `initialize()` parameters from `_generateInitializerParams()`.

**Solution:**

Verify your `_generateInitializerParams()` implementation returns the correct function signature:

```solidity
function _generateInitializerParams()
    internal
    view
    virtual
    override
    returns (bytes memory)
{
    return abi.encodeWithSignature(
        "initialize(string,string,address,address,address)",
        name(),
        symbol(),
        address(endpoint),
        _getOwnerAddressOnInitialize(),
        _getGovernanceAddressOnInitialize()
    );
}
```

**Common mistakes:**

- Wrong function signature (parameter types don't match)
- Missing custom parameters (e.g., for CustomTokenExample with attestation)
- Incorrect parameter order

Reference: Complete example in `/rayls-sovereign-contracts/src/rayls-protocol/test-contracts/CustomTokenExample.sol:98-109`

### Issue 6: Insufficient Gas

**Error message:**

```
Error: Transaction ran out of gas
```

**Solution:**

Increase gas limit in deployment:

```typescript
const tokenPL = await token.deploy(..., { gasLimit: 5000000 });
```

**Note:** Default gas limit is 5,000,000 in the deployment script (line 104 in erc20Deploy.ts).

## Best Practices

### Pre-Deployment

1. **Always check for duplicate names/symbols** before deployment
2. **Validate all environment variables** are set correctly
3. **Test on development environment** before production
4. **Document your token specifications** (decimals, roles, special features)

### During Deployment

1. **Use descriptive names and symbols** that won't conflict
2. **Save all transaction hashes** for audit trail
3. **Wait for confirmations** before proceeding to next step
4. **Verify each step** before moving to the next

### After Deployment

1. **Save resourceId immediately** to `.env` file
2. **Document all contract addresses** per chain
3. **Test basic operations** (balance, transfer) before cross-chain
4. **Set up monitoring** for deployment events
5. **Back up private keys** and configuration files

### Production Deployment

1. **Use hardware wallets** for system operator keys
2. **Multi-sig approval** for token registration
3. **Audit custom token logic** before deployment
4. **Plan rollback strategy** in case of issues
5. **Monitor relayer health** continuously

## Summary

This workflow ensures your token is deployed correctly across multiple chains:

1. ✓ Validate environment and check uniqueness
2. ✓ Deploy on origin chain (Chain A)
3. ✓ Authorize with endpoint
4. ✓ Register on the PN Token Registry (`tokens:register`)
5. ✓ Authorize on the Privacy Node (`tokens:approve-pn`)
6. ✓ Submit to the Hub (`submitTokenToHub`) and Hub operator approves (`tokens:approve-hub`)
7. ✓ Token receives resourceId via the `activateToken` callback
8. ✓ Deploy on destination chains (automatic or manual)
9. ✓ Verify all addresses and resourceId mappings
10. ✓ Test basic operations before production use

**Next Steps:**

- [End-to-End Tutorial](end-to-end-tutorial.md) - Complete example with all steps
- [Transaction Lifecycle](transaction-lifecycle.md) - Understand cross-chain message flow
- [Troubleshooting](troubleshooting.md) - Fix common deployment issues

## Related Documentation

- [Building Custom Tokens](building-custom-tokens.md) - How to create custom tokens
- [Token Standards](token-standards.md) - Understanding token handlers
- [Security](security.md) - Security best practices
- [Testing](testing.md) - Testing deployed contracts
- [Troubleshooting](troubleshooting.md) - Debugging deployment issues
