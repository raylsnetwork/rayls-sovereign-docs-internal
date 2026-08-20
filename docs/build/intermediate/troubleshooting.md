# Troubleshooting Guide

## Overview

This guide helps you diagnose and resolve common issues when building and deploying cross-chain applications on Rayls. Each issue includes symptoms, diagnostic steps, root causes, and solutions with actual commands and code examples.

!!! info "Prerequisites"
    Before troubleshooting, ensure you have completed:

    - [Building Custom Tokens](building-custom-tokens.md) - Implementation of your custom token contract
    - [Deployment Workflow](deployment-workflow.md) - Understanding of deployment and registration process
    - [Testing](testing.md) - Familiarity with testing strategies to isolate issues

    Most troubleshooting assumes you have a deployed token that's exhibiting problems. If you haven't deployed yet, complete the deployment workflow first.

## Quick Diagnostic Checklist

Before diving into specific issues, run these diagnostic commands to gather basic information:

```bash
# 1. Check RPC connectivity
curl -X POST $RPC_URL_NODE_A \  # Privacy Node Ledger A
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

curl -X POST $RPC_URL_NODE_CC \  # Private Network Hub (legacy variable name)
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# 2. Check account balances
cast balance $USER_ADDRESS --rpc-url $RPC_URL_NODE_A
cast balance $SYSTEM_ADDRESS --rpc-url $RPC_URL_NODE_CC

# 3. Check token resourceId
cast call $TOKEN_ADDRESS \
  "resourceId()(bytes32)" \
  --rpc-url $RPC_URL_NODE_A

# 4. Check endpoint authorization
cast call $ENDPOINT_ADDRESS \
  "isAuthorizedAddress(address)(bool)" \
  $TOKEN_ADDRESS \
  --rpc-url $RPC_URL_NODE_A

# 5. Check contract deployment
cast code $TOKEN_ADDRESS --rpc-url $RPC_URL_NODE_A
```

If all checks pass but you still have issues, proceed to the specific issue sections below.

## Common Issues

### Issue 1: Duplicate Token Name/Symbol

**Symptoms:**

- Deployment fails with duplicate error
- Cannot register token with TokenRegistry

**Error message:**

```
❌ A token with the symbol "MTK" already exists!
   ResourceId: 0xabc123...
   Name: MyToken
   Status: ACTIVE
Error: Duplicate token symbol detected: "MTK". Please choose a different symbol.
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Deploy.ts:78-84`

**Diagnostic steps:**

```bash
# Query all existing tokens on Private Network Hub
cast call $TOKEN_REGISTRY_ADDRESS \
  "getAllTokens()(tuple[])" \
  --rpc-url $RPC_URL_NODE_CC \
  --gas-limit 5000000
```

**Root causes:**

1. **Name collision:** Token name already registered (case-insensitive)
2. **Symbol collision:** Token symbol already registered (case-insensitive)
3. **Previous test deployment:** You deployed a test token with same name/symbol

**Solutions:**

**Solution A: Choose different name/symbol**

```bash
# Deploy with unique identifier
npx hardhat tokens:erc20:deploy \
  --pl A \
  --name "My Token V2" \
  --symbol "MTK2"
```

**Solution B: Use deployment prefix**

```bash
# Add environment prefix (DEV, PROD, etc.)
npx hardhat tokens:erc20:deploy \
  --pl A \
  --name "DEV My Token" \
  --symbol "DEV_MTK"
```

**Prevention:**

The deployment script automatically checks for duplicates before deployment (lines 24-86 in erc20Deploy.ts). Always let this check complete.

---

### Issue 2: Missing Environment Variables

**Symptoms:**

- Deployment script fails immediately
- Cannot connect to RPC endpoints
- Missing contract addresses

**Error messages:**

```
Error: RPC_URL_NODE_CC is not set in the .env file. Cannot verify token uniqueness.
Error: PRIVATE_KEY_SYSTEM is not set in the .env file.
Error: NODE_A_DEPLOYMENTPROXYREGISTRY is not set in the .env file.
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Deploy.ts:28-46`

**Required environment variables:**

```bash
# RPC endpoints
RPC_URL_NODE_A=https://...
RPC_URL_NODE_B=https://...
RPC_URL_NODE_CC=https://...  # Private Network Hub

# Private keys
PRIVATE_KEY_SYSTEM=0x...  # System operator (for approvals, authorizations)
PRIVATE_KEY_USER=0x...    # Token deployer

# Contract registries
NODE_A_DEPLOYMENTPROXYREGISTRY=0x...
NODE_B_DEPLOYMENTPROXYREGISTRY=0x...
NODE_CC_DEPLOYMENTPROXYREGISTRY=0x...

# Endpoint addresses
NODE_A_RAYLS_NODE_ENDPOINT_ADDRESS=0x...
NODE_B_RAYLS_NODE_ENDPOINT_ADDRESS=0x...

# Governance addresses
NODE_A_RAYLS_NODE_USER_GOVERNANCE=0x...
NODE_B_RAYLS_NODE_USER_GOVERNANCE=0x...

# Chain IDs
NODE_A_CHAIN_ID=1001
NODE_B_CHAIN_ID=1002
```

**Solution:**

1. Copy `.env.example` to `.env`
2. Fill in all required values for your environment
3. Verify no typos in variable names
4. Ensure no extra spaces around `=`

**Validation script:**

```bash
#!/bin/bash
# validate-env.sh

required_vars=(
  "RPC_URL_NODE_A"
  "RPC_URL_NODE_CC"
  "PRIVATE_KEY_SYSTEM"
  "PRIVATE_KEY_USER"
  "NODE_A_DEPLOYMENTPROXYREGISTRY"
  "NODE_CC_DEPLOYMENTPROXYREGISTRY"
)

for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ Missing: $var"
    exit 1
  else
    echo "✅ Found: $var"
  fi
done

echo "All required environment variables are set!"
```

---

### Issue 3: Authorization Failure

**Symptoms:**

- Token deployed but cannot send messages
- Cross-chain transfers fail immediately
- Registration submission fails

**Error message:**

```
Error: Endpoint__NotAuthorizedAddress()
```

Reference: `/rayls-sovereign-contracts/src/rayls-protocol/Endpoint/EndpointV1.sol:27-28`

**Diagnostic:**

```bash
# Check if token is authorized
cast call $ENDPOINT_ADDRESS \
  "isAuthorizedAddress(address)(bool)" \
  $TOKEN_ADDRESS \
  --rpc-url $RPC_URL_NODE_A
# Should return: true
```

**Root causes:**

1. **Token not added to authorized list:** Deployment script didn't complete authorization step
2. **Deployment interrupted:** Script stopped between deployment and authorization
3. **Wrong operator key:** PRIVATE_KEY_SYSTEM doesn't have permission to authorize

**Solution:**

Manually authorize the token:

```bash
# As system operator
cast send $ENDPOINT_ADDRESS \
  "addAuthorizedAddresses(address[])" \
  "[$TOKEN_ADDRESS]" \
  --private-key $PRIVATE_KEY_SYSTEM \
  --rpc-url $RPC_URL_NODE_A \
  --gas-limit 500000
```

Reference: Automatic authorization in `/rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Deploy.ts:111-122`

**Verify authorization:**

```bash
cast call $ENDPOINT_ADDRESS \
  "isAuthorizedAddress(address)(bool)" \
  $TOKEN_ADDRESS \
  --rpc-url $RPC_URL_NODE_A
# Expected: true
```

**Prevention:**

Always wait for the deployment script to complete fully. Don't interrupt with Ctrl+C.

---

### Issue 4: No Resource ID Received

**Symptoms:**

- Token deployed and approved
- `resourceId()` returns `0x0000...0000`
- Cannot execute cross-chain transfers

**Error when trying to transfer:**

```
ResourceId not registered
```

**Diagnostic:**

```bash
# Check resourceId on token
cast call $TOKEN_ADDRESS \
  "resourceId()(bytes32)" \
  --rpc-url $RPC_URL_NODE_A

# If returns 0x0000...0000, resourceId not received
```

**Root causes:**

**Cause A: Token not approved by operator**

```bash
# Check token status in the PN TokenRegistry
# Query getAllTokens() and find your token
# PrivacyNodeStatus: 0 = UNDEFINED, 1 = WAITING_APPROVAL,
#                    2 = AUTHORIZED, 3 = UNAUTHORIZED, 4 = FROZEN
# The resourceId is delivered from the Hub via the activateToken callback,
# so it stays 0x0 until the token is authorized on the PN AND approved on the Hub.
```

**Solution:**

```bash
# Authorize on the Privacy Node, then approve on the Hub
# (Hub approval triggers the activateToken callback that assigns the resourceId)
npx hardhat tokens:approve-pn --symbol MTK
npx hardhat tokens:approve-hub --symbol MTK
```

**Cause B: Relayer not running or not delivering messages**

**Diagnostic:**

```bash
# Check relayer status
curl http://relayer:8080/health

# Check relayer logs
docker logs -f rayls-relayer | grep "MessageDispatched"

# Check if relayer has gas
cast balance $RELAYER_ADDRESS --rpc-url $RPC_URL_NODE_CC
```

**Solution:**

- Restart relayer service
- Fund relayer wallet if balance is low
- Check relayer configuration

**Cause C: activateToken() callback failed / resource ID not yet received**

**Diagnostic:**

Look for `MessageFailure` events on the source chain. The resource ID is assigned by the Private Network Hub and delivered to the PN `PNTokenRegistryV1` through the `activateToken(bytes32,address,uint8)` callback; the registry then calls `setResourceId(bytes32)` on your token.

**Solution:**

There is nothing to implement on the token itself — `setResourceId(bytes32)` is inherited from the `RaylsApp` base and is callable only by the PN TokenRegistry. If the resource ID is still `0x0`:

- Confirm the token is authorized on the Privacy Node and submitted to the Hub (`submitToHub`).
- Confirm the Hub operator approved the token (`tokens:approve-hub`), which is what fires the `activateToken` callback.
- Check the relayer is delivering the callback (see Cause B).

**Wait time:**

Normal resourceId reception: 30-60 seconds after approval. If longer than 2 minutes, investigate relayer.

---

### Issue 5: Transaction Stuck in Relayer

**Symptoms:**

- Tokens burned on source chain
- No arrival on destination chain after 2+ minutes
- `MessageDispatched` event emitted but nothing happens

**Diagnostic steps:**

**Step 1: Verify message was dispatched**

```bash
# Get recent MessageDispatched events from source endpoint
cast logs \
  --from-block -1000 \
  --address $ENDPOINT_ADDRESS_A \
  --rpc-url $RPC_URL_NODE_A \
  "MessageDispatched(bytes32,address,uint256,bytes32,bytes)"
```

**Step 2: Check relayer status**

```bash
# Health check
curl http://relayer:8080/health

# View recent logs
docker logs --tail 100 rayls-relayer
```

**Step 3: Check if message reached Private Network Hub**

Query Teleport contract on hub for message status.

**Step 4: Check destination chain accessibility**

```bash
# Test RPC connection
curl -X POST $RPC_URL_NODE_B \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Root causes & solutions:**

**Cause A: Relayer offline**

**Solution:**

```bash
# Restart relayer
docker restart rayls-relayer

# OR systemd
systemctl restart rayls-relayer
```

Messages will be picked up automatically when relayer resumes.

**Cause B: Relayer out of gas**

**Diagnostic:**

```bash
cast balance $RELAYER_ADDRESS --rpc-url $RPC_URL_NODE_A
cast balance $RELAYER_ADDRESS --rpc-url $RPC_URL_NODE_B
cast balance $RELAYER_ADDRESS --rpc-url $RPC_URL_NODE_CC
```

**Solution:**

Fund relayer wallets on all chains:

```bash
# Fund with native tokens
cast send $RELAYER_ADDRESS \
  --value 1ether \
  --private-key $FUNDER_KEY \
  --rpc-url $RPC_URL_NODE_A
```

**Cause C: Destination RPC endpoint down**

**Diagnostic:**

```bash
# Test connectivity
curl -I $RPC_URL_NODE_B
```

**Solution:**

- Wait for RPC to come back online
- Use backup RPC endpoint if configured
- Relayer will retry automatically

**Cause D: Message already executed (replay)**

**Diagnostic:**

```bash
# Check if message was executed
cast call $MESSAGE_EXECUTOR_ADDRESS \
  "executed(bytes32)(bool)" \
  $MESSAGE_ID \
  --rpc-url $RPC_URL_NODE_B
```

If returns `true`, message already executed (not stuck).

---

### Issue 6: Destination Chain Not Receiving Messages

**Symptoms:**

- Message dispatched successfully
- Relayer shows no errors
- Token not minted on destination

**Diagnostic:**

```bash
# Check for MessageIdExecuted events
cast logs \
  --from-block -1000 \
  --address $MESSAGE_EXECUTOR_B \
  --rpc-url $RPC_URL_NODE_B \
  "MessageIdExecuted(bytes32,bool)"
```

**Root causes & solutions:**

**Cause A: Relayer not authorized on destination endpoint**

**Error in relayer logs:**

```
Error: RelayerUnauthorizedAccount(0x...)
```

**Solution:**

```bash
# As system operator on destination chain
cast send $ENDPOINT_ADDRESS_B \
  "authorizeRelayer(address)" \
  $RELAYER_ADDRESS \
  --private-key $PRIVATE_KEY_SYSTEM \
  --rpc-url $RPC_URL_NODE_B
```

Reference: `/rayls-sovereign-contracts/src/rayls-protocol/Endpoint/EndpointV1.sol:27`

**Cause B: Message already executed (replay protection)**

**Error:**

```
MessageIdAlreadyExecuted(bytes32)
```

**Diagnostic:**

```bash
cast call $MESSAGE_EXECUTOR_B \
  "executed(bytes32)(bool)" \
  $MESSAGE_ID \
  --rpc-url $RPC_URL_NODE_B
```

**This is normal:** Replay protection working correctly. Not an error.

**Cause C: Target contract doesn't exist on destination**

**Diagnostic:**

```bash
# Check if token deployed on destination
cast call $ENDPOINT_ADDRESS_B \
  "getAddressByResourceId(bytes32)(address)" \
  $RESOURCE_ID \
  --rpc-url $RPC_URL_NODE_B
```

If returns `0x0000...0000`, contract not deployed yet.

**Solution:**

Wait for factory deployment (happens automatically on first message) or deploy manually.

---

### Issue 7: Atomic Teleport Revert Not Working

**Symptoms:**

- Destination rejects tokens
- Tokens NOT returned to sender
- Balance lost

**THIS SHOULD NEVER HAPPEN with teleportAtomic()**, but if it does:

**Diagnostic:**

```bash
# Check transaction on source chain
cast tx $TX_HASH --rpc-url $RPC_URL_NODE_A

# Look for revert payloads in transaction data
```

**Root causes:**

**Cause A: Used teleport() instead of teleportAtomic()**

```solidity
// ✗ WRONG - No revert protection
await token.teleport(to, amount, chainId);

// ✓ CORRECT - Atomic with automatic revert
await token.teleportAtomic(to, amount, chainId);
```

**Prevention:**

ALWAYS use `teleportAtomic()` for production transfers.

**Cause B: revertTeleportMint() function missing**

Verify your token has the revert handler:

```solidity
function revertTeleportMint(address to, uint256 value) public virtual receiveMethod {
    _mint(to, value);
}
```

**Cause C: Backward revert payload failed**

Check if backward message execution failed on source chain.

**Solution:**

If tokens are truly lost:
1. Contact Rayls support immediately
2. Provide transaction hashes for investigation
3. May require operator intervention to recover

**Prevention is key:** Always use `teleportAtomic()`.

---

### Issue 8: Factory Deployment Initialization Failed

**Symptoms:**

- Factory deploys proxy on destination
- Initialization fails
- Contract exists but unusable

**Error message:**

```
Failed on contract initialization while deploying a resource locally
```

Reference: `/rayls-sovereign-contracts/src/rayls-protocol/RaylsContractFactory/RaylsContractFactoryV1.sol:48`

**Root cause:**

Incorrect `_generateInitializerParams()` implementation.

**Diagnostic:**

```bash
# Check if proxy deployed
cast code $TOKEN_ADDRESS_B --rpc-url $RPC_URL_NODE_B

# Try calling owner (will fail if not initialized)
cast call $TOKEN_ADDRESS_B \
  "owner()(address)" \
  --rpc-url $RPC_URL_NODE_B
```

If returns `0x0000...0000`, initialization failed.

**Solution:**

Fix `_generateInitializerParams()` in your token contract:

```solidity
function _generateInitializerParams()
    internal
    view
    override
    returns (bytes memory)
{
    // MUST match initialize() signature exactly
    return abi.encodeWithSignature(
        "initialize(string,string,address,address,address)",  // Correct signature
        tokenName,
        tokenSymbol,
        address(endpoint),
        _getOwnerAddressOnInitialize(),
        _getGovernanceAddressOnInitialize()
    );
}
```

**Common mistakes:**

1. **Wrong parameter types:** `uint256` vs `address`
2. **Wrong parameter order:** Must match `initialize()` exactly
3. **Missing parameters:** Custom tokens with extra parameters
4. **Incorrect function name:** Typo in `"initialize"`

**Example for custom parameters:**

```solidity
// Custom initialize with attestation
function initialize(
    string memory _name,
    string memory _symbol,
    uint256 _fundManagerChainId,
    address _fundManagerAddr,
    bytes32 _attestationUuid
) public initializer { ... }

// Matching _generateInitializerParams()
function _generateInitializerParams() internal view override returns (bytes memory) {
    return abi.encodeWithSignature(
        "initialize(string,string,uint256,address,bytes32)",  // Must match above!
        tokenName,
        tokenSymbol,
        fundManagerFeeChainId,
        fundManagerAddr,
        attestationUid
    );
}
```

Reference: `/rayls-sovereign-contracts/src/rayls-protocol/test-contracts/CustomTokenExample.sol:74-89`

---

### Issue 9: Proxy Initialization Errors

**Symptoms:**

- Proxy deployment succeeds
- Contract calls fail
- Owner returns zero address

**Diagnostic:**

```bash
# Check initialization status
cast call $TOKEN_ADDRESS "owner()(address)" --rpc-url $RPC_URL_NODE_A
# If returns 0x0000...0000, not initialized

# Check if initialize() was called
# (Cannot call twice due to initializer modifier)
```

**Root causes:**

**Cause A: initialize() not marked with initializer modifier**

```solidity
// ✗ WRONG - Missing initializer modifier
function initialize(...) public {
    // Can be called multiple times!
}

// ✓ CORRECT - Has initializer modifier
function initialize(...) public initializer {
    // Can only be called once
}
```

**Cause B: Context extraction functions incorrect**

```solidity
// Must use helper functions in RaylsApp
address _owner = _getOwnerAddressOnInitialize();  // Extracts from context
address _endpoint = _getEndpointAddressOnInitialize();
bytes32 _resourceId = _getResourceIdOnInitialize();
```

**Cause C: Forgot to call parent initialize**

```solidity
function initialize(...) public initializer {
    // Must set these from context
    resourceId = _getResourceIdOnInitialize();
    endpoint = IRaylsEndpoint(_getEndpointAddressOnInitialize());
    _transferOwnership(_getOwnerAddressOnInitialize());

    // Your custom initialization
    // ...
}
```

Reference: Complete example in `/rayls-sovereign-contracts/src/rayls-protocol/test-contracts/CustomTokenExample.sol:53-72`

---

### Issue 10: receiveMethod Rejects Valid Calls

**Symptoms:**

- Cross-chain messages fail on destination
- Error: "Unauthorized executor"
- Receive functions reverting

**Error:**

```
This is a receive method. Only endpoint's executor can call this method.
```

Reference: `/rayls-sovereign-contracts/src/rayls-protocol-sdk/RaylsApp.sol:249-255`

**Root cause:**

`receiveMethod` modifier validation failing.

**How receiveMethod works:**

```solidity
modifier receiveMethod() {
    require(
        endpoint.isTrustedExecutor(msg.sender),
        "Only endpoint's executor can call this method."
    );
    _;
}
```

**Checks:**

1. `msg.sender` must be MessageExecutor
2. Context must include valid messageId, fromChainId, from

**Common mistakes:**

**Mistake A: Calling receive function directly**

```bash
# ✗ WRONG - Cannot call directly (not from executor)
cast send $TOKEN_ADDRESS_B \
  "receiveTeleportAtomic(address,uint256)" \
  $USER 1000 \
  --private-key $PRIVATE_KEY_USER \
  --rpc-url $RPC_URL_NODE_B
# Reverts: "Only endpoint's executor can call this method."
```

**Correct:** Only MessageExecutor calls receive functions (automatic).

**Mistake B: Missing receiveMethod modifier**

```solidity
// ✗ WRONG - Anyone can call and mint tokens!
function receiveTeleportAtomic(address to, uint256 value) public {
    _mint(to, value);  // VULNERABILITY!
}

// ✓ CORRECT - Only executor can call
function receiveTeleportAtomic(address to, uint256 value) public receiveMethod {
    _mint(to, value);  // Safe
}
```

**Mistake C: Wrong executor address**

**Diagnostic:**

```bash
# Check trusted executor
cast call $ENDPOINT_ADDRESS \
  "isTrustedExecutor(address)(bool)" \
  $MESSAGE_EXECUTOR_ADDRESS \
  --rpc-url $RPC_URL_NODE_B
# Should return: true
```

---

### Issue 11: TokenIsFrozenForParticipant

**Symptoms:**

- Transfer fails immediately
- Token appears active in TokenRegistry
- Specific user cannot transfer

**Error:**

```
TokenFreezeManagerV1__TokenFrozenForParticipant(bytes32 resourceId, uint256 chainId)
```

Reference: `/rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Send.ts:30-34`
Reference: `/rayls-sovereign-contracts/src/rayls-protocol/TokenRegistry/modules/TokenFreezeManager/PNTokenFreezeManagerV1.sol`

**Root cause:**

Token is frozen specifically for this participant, enforced by the PN `PNTokenFreezeManagerV1` module of the `PNTokenRegistryV1`.

**Diagnostic:**

```bash
# Check freeze status for the participant chain
# Query the PN TokenRegistry (freeze manager) on the Privacy Node Ledger
cast call $PN_TOKEN_REGISTRY \
  "getFrozenTokenForParticipant(bytes32,uint256)(bool)" \
  $TOKEN_RESOURCE_ID \
  $PARTICIPANT_CHAIN_ID \
  --rpc-url $RPC_URL_NODE_A
```

**Solutions:**

**Solution A: Operator unfreezes token for participant**

Contact Private Network Operator to unfreeze.

**Solution B: Use different account**

If only specific account is frozen, use different wallet.

**Prevention:**

Comply with network policies to avoid freezing.

---

### Issue 12: Input Validation Errors

**Symptoms:**

- teleport() call reverts immediately
- Custom error about zero values

**Error messages:**

```
RaylsErc20Handler__ZeroValueArg(address receiver, uint256 value, uint256 destChainId)
RaylsErc20Handler__WrongFunctionForSameChainId(uint256 chainId)
```

Reference: `/rayls-sovereign-contracts/src/rayls-protocol-sdk/tokens/RaylsErc20Handler.sol:20-22`

**Root causes & solutions:**

**Cause A: Zero address**

```solidity
// Validates receiver != 0x0
teleport(address(0), 100, chainId);  // Reverts!
```

**Solution:** Use valid address.

**Cause B: Zero amount**

```solidity
teleport(receiver, 0, chainId);  // Reverts!
```

**Solution:** Transfer amount > 0.

**Cause C: Zero or same chain ID**

```solidity
// Same chain
uint256 currentChain = endpoint.getChainId();
teleport(receiver, 100, currentChain);  // Reverts!
```

**Solution:** For same-chain transfers, use `transfer()` instead of `teleport()`.

**Diagnostic:**

```bash
# Get current chain ID
cast call $ENDPOINT_ADDRESS \
  "getChainId()(uint256)" \
  --rpc-url $RPC_URL_NODE_A
```

---

### Issue 13: E2E Tests Timeout

**Symptoms:**

- Tests hang waiting for balance change
- Timeout after 2 minutes (DEFAULT_TIMEOUT)

**Error:**

```
Error: Timeout of 120000ms exceeded
```

**Diagnostic:**

```typescript
// From test helper
await commitChain.waitUntil(
  async () => { /* condition */ },
  "Checking balance...",
  { timeout: 120000 }  // 2 minutes
);
```

Reference: `/rayls-sovereign-contracts/hardhat/test/e2e/Erc20.ts:102-109`

**Root causes:**

**Cause A: Relayer not running in test environment**

**Solution:**

```bash
# Check test environment setup
# Ensure mockRelayerEthers is initialized
```

**Cause B: Chain not producing blocks**

**Solution:**

Verify test chains are running:

```bash
# Check if chains are mining
cast block-number --rpc-url $RPC_URL_NODE_A
# Wait 5 seconds
cast block-number --rpc-url $RPC_URL_NODE_A
# Block number should have increased
```

**Cause C: Test condition never satisfied**

**Debug:**

```typescript
await commitChain.waitUntil(
  async () => {
    const balance = await token.balanceOf(user);
    console.log(`Current balance: ${balance}`);  // Debug output
    return balance === expectedBalance;
  },
  "Checking balance..."
);
```

**Solution D: Increase timeout for slow environments**

```typescript
it('Should teleport', async function () {
  // ...
}).timeout(300000);  // 5 minutes for slow CI/CD
```

---

### Issue 14: Access Control Errors

**Symptoms:**

- Function calls revert
- Cannot mint/burn tokens
- Role-based operations fail

**Error messages:**

```
AccessControlUnauthorizedAccount(address account, bytes32 role)
OwnableUnauthorizedAccount(address account)
```

**Root causes:**

**Cause A: Missing role assignment**

**Diagnostic:**

```bash
# Check if account has role
cast call $TOKEN_ADDRESS \
  "hasRole(bytes32,address)(bool)" \
  $(cast keccak "MINTER_ROLE") \
  $USER_ADDRESS \
  --rpc-url $RPC_URL_NODE_A
# Should return: true
```

**Solution:**

Grant role:

```bash
# As admin
cast send $TOKEN_ADDRESS \
  "grantRole(bytes32,address)" \
  $(cast keccak "MINTER_ROLE") \
  $USER_ADDRESS \
  --private-key $ADMIN_KEY \
  --rpc-url $RPC_URL_NODE_A
```

**Cause B: Not owner**

**Diagnostic:**

```bash
cast call $TOKEN_ADDRESS \
  "owner()(address)" \
  --rpc-url $RPC_URL_NODE_A
```

**Solution:**

Either call from owner account or transfer ownership:

```bash
cast send $TOKEN_ADDRESS \
  "transferOwnership(address)" \
  $NEW_OWNER \
  --private-key $CURRENT_OWNER_KEY \
  --rpc-url $RPC_URL_NODE_A
```

---

### Issue 15: Chain ID Mismatches

**Symptoms:**

- Wrong chain receiving messages
- Cannot find destination chain
- Configuration errors

**Error:**

```
RaylsErc20Handler__WrongFunctionForSameChainId(uint256 chainId)
```

**Diagnostic:**

```bash
# Check chain ID
cast call $ENDPOINT_ADDRESS \
  "getChainId()(uint256)" \
  --rpc-url $RPC_URL_NODE_A

# Verify environment variable matches
echo $NODE_A_CHAIN_ID
```

**Solution:**

Ensure chain IDs in `.env` match actual chain configuration.

---

### Issue 16: Network Connectivity Issues

**Symptoms:**

- Cannot connect to RPC
- Timeout errors
- Connection refused

**Diagnostic commands:**

```bash
# Test HTTP connection
curl -I $RPC_URL_NODE_A

# Test JSON-RPC endpoint
curl -X POST $RPC_URL_NODE_A \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Test with verbose output
curl -v $RPC_URL_NODE_A
```

**Solutions:**

1. **Check firewall rules**
2. **Verify VPN connection** if required
3. **Try alternate RPC endpoint**
4. **Check if endpoint is rate-limited**
5. **Verify API keys** if required

---

## Diagnostic Tools

### Checking Transaction Status

```bash
# Get transaction receipt
cast receipt $TX_HASH --rpc-url $RPC_URL_NODE_A

# Get transaction details
cast tx $TX_HASH --rpc-url $RPC_URL_NODE_A

# Decode revert reason (if failed)
cast run $TX_HASH --rpc-url $RPC_URL_NODE_A
```

### Verifying Contract Deployment

```bash
# Check if contract exists
cast code $CONTRACT_ADDRESS --rpc-url $RPC_URL_NODE_A

# Get contract size
cast code $CONTRACT_ADDRESS --rpc-url $RPC_URL_NODE_A | wc -c

# Verify implementation (for proxies)
cast call $PROXY_ADDRESS \
  "implementation()(address)" \
  --rpc-url $RPC_URL_NODE_A

# Check contract owner
cast call $CONTRACT_ADDRESS \
  "owner()(address)" \
  --rpc-url $RPC_URL_NODE_A
```

### Monitoring Relayer Health

```bash
# Health check endpoint
curl http://relayer:8080/health

# Check relayer balance on all chains
for chain in A B CC; do
  echo "Chain $chain:"
  cast balance $RELAYER_ADDRESS --rpc-url $(eval echo \$RPC_URL_NODE_$chain)
done

# View recent relayer logs
docker logs --tail 100 --follow rayls-relayer

# Search for specific message
docker logs rayls-relayer 2>&1 | grep $MESSAGE_ID
```

### Debugging Message Execution

**Monitor message dispatch:**

```bash
# Watch for MessageDispatched events
cast logs \
  --from-block latest \
  --follow \
  --address $ENDPOINT_ADDRESS \
  --rpc-url $RPC_URL_NODE_A \
  "MessageDispatched(bytes32,address,uint256,bytes32,bytes)"
```

**Monitor message execution:**

```bash
# Watch for MessageIdExecuted events
cast logs \
  --from-block latest \
  --follow \
  --address $MESSAGE_EXECUTOR_ADDRESS \
  --rpc-url $RPC_URL_NODE_B \
  "MessageIdExecuted(bytes32,bool)"
```

**Check if message executed:**

```bash
cast call $MESSAGE_EXECUTOR_ADDRESS \
  "executed(bytes32)(bool)" \
  $MESSAGE_ID \
  --rpc-url $RPC_URL_NODE_B
```

### Query Token Information

```bash
# Complete token status check
echo "=== Token Status ==="
echo "Name: $(cast call $TOKEN_ADDRESS 'name()(string)' --rpc-url $RPC_URL_NODE_A)"
echo "Symbol: $(cast call $TOKEN_ADDRESS 'symbol()(string)' --rpc-url $RPC_URL_NODE_A)"
echo "Decimals: $(cast call $TOKEN_ADDRESS 'decimals()(uint8)' --rpc-url $RPC_URL_NODE_A)"
echo "Total Supply: $(cast call $TOKEN_ADDRESS 'totalSupply()(uint256)' --rpc-url $RPC_URL_NODE_A)"
echo "Owner: $(cast call $TOKEN_ADDRESS 'owner()(address)' --rpc-url $RPC_URL_NODE_A)"
echo "ResourceId: $(cast call $TOKEN_ADDRESS 'resourceId()(bytes32)' --rpc-url $RPC_URL_NODE_A)"
```

## Getting Help

If you've tried all troubleshooting steps and still have issues:

1. **Gather diagnostic information:**
   - Transaction hashes
   - Error messages (full text)
   - Contract addresses
   - Relevant logs

2. **Check existing documentation:**
   - [Deployment Workflow](deployment-workflow.md)
   - [End-to-End Tutorial](end-to-end-tutorial.md)
   - [Security](security.md)
   - [Testing](testing.md)

3. **Contact support:**
   - Provide all diagnostic information
   - Include steps to reproduce
   - Specify environment (dev/staging/prod)

## Related Documentation

- [Deployment Workflow](deployment-workflow.md) - Proper deployment procedures
- [Transaction Lifecycle](transaction-lifecycle.md) - Understanding message flow
- [Security](security.md) - Security considerations
- [Testing](testing.md) - Testing strategies to prevent issues
- [End-to-End Tutorial](end-to-end-tutorial.md) - Complete working example
- [Building Custom Tokens](building-custom-tokens.md) - Token customization patterns
