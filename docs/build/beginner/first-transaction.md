# First Transaction

This guide walks you through performing your first atomic teleport transfer - sending tokens from Privacy Node A to Privacy Node B using Rayls's cross-chain protocol.

## Prerequisites

Before starting, ensure you have:

- ✓ Docker environment running ([Docker Setup](docker-setup.md))
- ✓ Accounts configured ([Account Setup](account-setup.md))
- ✓ Understanding of the system architecture ([Architecture Overview](architecture-overview.md))

**What you'll accomplish:**

Transfer 100 tokens from Institution A to Institution B using an atomic teleport transaction that guarantees either both sides succeed or both revert.

## Overview: What transaction types are supported by Rayls?

Rayls supports four types of cross-chain token transfers:

**Vanilla Teleport (`teleport`)**

- Tokens burned on source immediately
- No automatic revert if destination fails
- Faster but less safe

**Atomic Teleport (`teleportAtomic`)** ← We'll use this

- Tokens burned on source
- Tokens initially locked on destination
- Automatically reverts if destination fails
- Provides transaction atomicity guarantee

**Enygma Privacy Transfers (`enygma`)**

- Privacy-preserving token transfers using zero-knowledge proofs
- Transaction amounts and sender/recipient identities are hidden
- Requires zero-knowledge proof generation
- See [Enygma Privacy](../advanced/enygma-privacy.md) for details

**DVP Atomic Swaps (`dvp`)**

- Zero-knowledge Delivery vs Payment for trustless multi-party exchanges
- Private atomic swaps with encrypted amounts
- All parties exchange assets simultaneously or all transactions revert
- See [DVP Atomic Swaps](../advanced/dvp-atomic-swaps.md) for details

**When to use Atomic Teleport:**

- Production transfers requiring safety
- High-value transactions
- When you need guaranteed atomicity across chains

**When Vanilla might be appropriate:**

- Testing and development
- Non-critical transfers where speed is prioritized

For this first transaction, we'll use **Atomic Teleport** for maximum safety.

## Understanding the Endpoint Contract

The **Endpoint** is the central messaging gateway that enables all cross-chain communication in Rayls. Every Privacy Node has its own Endpoint contract that acts as the entry and exit point for cross-chain messages. When a token wants to teleport to another chain, it doesn't communicate directly with the destination - instead, it sends a message through its local Endpoint, which coordinates with the Private Network Hub and the destination Endpoint to deliver the message securely.

**Security and Authorization:** Before any token contract can send cross-chain messages, it must be **authorized** by the Endpoint's operator (the account that deployed the Endpoint, typically using `PRIVATE_KEY_SYSTEM`). This authorization system prevents unauthorized contracts from flooding the network with messages. Similarly, only authorized relayers can deliver incoming messages to the Endpoint, ensuring that cross-chain messages come from trusted sources.

**Role in Atomic Teleport:** During an atomic teleport, the Endpoint handles all the complexity of message routing and coordination. It resolves resource IDs (logical token identifiers) to actual contract addresses on different chains, manages message nonces to prevent replay attacks, and coordinates the execute/unlock/revert payloads that make atomic operations possible. When you call `teleportAtomic()` on a token, the Endpoint ensures your message reaches the Private Network Hub for coordination, then gets delivered to the destination chain, and finally handles confirmation or revert messages based on the outcome.

For more details on Endpoint architecture, see [Architecture Overview](architecture-overview.md).

## Quick Start

If you want to get started immediately, here are the commands (detailed explanations follow):

```bash
# Step 1: Deploy ERC20 token on Privacy Node A (token deployment + Endpoint authorisation)
# Source code is here: rayls-sovereign-contracts/hardhat/tasks/tokens/erc20/erc20Deploy.ts
npx hardhat tokens:erc20:deploy --pl A --name "MyToken" --symbol "MTK"

# Step 2: Register the token on the PN Token Registry
npx hardhat tokens:register --pl A --token-address {YOUR-TOKEN-ADDRESS-FROM-DEPLOYMENT-HERE}

# Step 3: PN operator authorizes the token locally
npx hardhat tokens:approve-pn --symbol MTK

# Step 4: Submit the token to the Private Network Hub, then the Hub operator approves it
npx hardhat submitTokenToHub --symbol MTK
npx hardhat tokens:approve-hub --symbol MTK

# Step 5: After Hub approval the activateToken callback assigns a unique
# cross-chain identifier (resourceId). Retrieve it and put it into your .env file
npx hardhat tokens:check-resource-id --pl A --token-address {YOUR-TOKEN-ADDRESS-FROM-DEPLOYMENT-HERE}

# Step 6: Execute atomic teleport from A to B
npx hardhat tokens:erc20:send \
    --symbol MTK \
    --pl-origin A \
    --pl-dest B \
    --destination-address 0x1234567890123456789012345678901234567890 \
    --amount 1000

# Step 7: Check balance of the receiver address on B
npx hardhat tokens:erc20:get-balance --symbol MTK --pl B --address 0x1234567890123456789012345678901234567890
```


!!! note "Conceptual Commands"
    The commands above show the logical flow. In practice, you'll use TypeScript code or actual available Hardhat tasks (see Step-by-Step Guide below). The exact task names may differ from your installation.

## Step-by-Step Guide

### Step 1: Deploy an ERC20 Token

First, we need to deploy a token contract that supports cross-chain transfers. Rayls uses `RaylsErc20Handler`, a special ERC20 extension that adds teleport functionality. You need to inherit from this contract to enable your token to be transfered cross-chain

**Understanding RaylsErc20Handler:**

- Standard ERC20 token (mint, burn, transfer, balanceOf, etc.)
- Additional teleport methods for cross-chain transfers
- Automatic integration with the Endpoint contract
- Built-in support for atomic transactions

**Constructor Parameters:**

- `name`: Token name (e.g., "MyToken")
- `symbol`: Token symbol (e.g., "MTK")
- `endpoint`: Address of the Privacy Node's Endpoint contract
- `raylsNodeEndpoint`: Address for RaylsNode integration (use `ZeroAddress` if not needed)
- `userGovernance`: Address for governance (use `ZeroAddress` if not needed)

!!! info "Private Key Usage Pattern"
    Rayls uses two separate private keys for different types of operations:

    **PRIVATE_KEY_USER** - For token operations:

    - Deploy TokenExample contracts (becomes the token owner)
    - Execute transfers (teleportAtomic, teleport)
    - Mint/burn own tokens
    - Check balances

    **PRIVATE_KEY_SYSTEM** - For operator/admin operations:

    - Authorize tokens with Endpoint (as Endpoint owner)
    - Authorize tokens on the Privacy Node (as PN operator) and on the Hub (as PNH operator)
    - Deploy system contracts (Endpoint, TokenRegistry)
    - Administrative functions

    **Pattern Summary:** Users deploy and operate their tokens with PRIVATE_KEY_USER. System operators authorize and approve using PRIVATE_KEY_SYSTEM.

!!! tip "Token Uniqueness Validation"
    Before deploying a token, the `tokens:erc20:deploy` task automatically checks the TokenRegistry on the Private Network Hub to ensure your token name and symbol are unique (case-insensitive comparison).

    If a duplicate is found, deployment will fail with a clear error message showing:

    - The existing token's name and symbol
    - When it was registered
    - Its current status

    This validation prevents confusion between tokens and saves gas by failing early before deployment.

**TypeScript Code:**

```typescript
import hre from 'hardhat';
import { ethers } from 'ethers';

// Get signer for Privacy Node A
const signerA = await hre.ethers.getSigner();

// Get Endpoint address from environment
const endpointAddressA = process.env.NODE_A_ENDPOINT;

// Deploy TokenExample contract
const TokenFactory = await hre.ethers.getContractFactory('TokenExample', signerA);
const token = await TokenFactory.deploy(
  'MyToken',                                          // Token name
  'MTK',                                              // Token symbol
  endpointAddressA,                                   // Endpoint address
  process.env.NODE_A_RAYLS_NODE_ENDPOINT_ADDRESS,    // RaylsNode endpoint address
  process.env.NODE_A_RAYLS_NODE_USER_GOVERNANCE      // User governance address
);

// Wait for deployment
await token.waitForDeployment();
const tokenAddress = await token.getAddress();

console.log(`✓ Token deployed at: ${tokenAddress}`);
console.log(`✓ Initial supply: 2,000,000 MTK minted to deployer`);
```

**What Happens:**

1. TokenExample contract is deployed to Privacy Node A
2. Deployer receives 2,000,000 MTK (initial supply)
3. Token is registered with the local Endpoint
4. Token is ready for local transfers (but not yet cross-chain)

### Step 2: Authorize Token as Operator

!!! note "Automatic Authorization"
    If you used the `tokens:erc20:deploy` task from the Quick Start, **this step is already completed automatically**. The deploy task handles endpoint authorization for you (using PRIVATE_KEY_SYSTEM). This section explains what happens under the hood for educational purposes.

Before a token can initiate cross-chain transfers, it must be authorized by the Insitution's Endpoint's operator. This is a security measure that prevents unauthorized contracts from sending cross-chain messages.

**Who is the Operator?**

The operator is the account that deployed the Endpoint contract (typically the system deployer using `PRIVATE_KEY_SYSTEM`).

**Why Authorization is Required:**

- Security: Only approved contracts can send cross-chain messages
- Spam prevention: Prevents malicious contracts from flooding the network
- Control: Operator maintains oversight of cross-chain operations

**TypeScript Code:**

```typescript
// Get operator wallet
const operatorWallet = new ethers.Wallet(process.env.PRIVATE_KEY_SYSTEM);

// Connect to Privacy Node A provider
const providerA = new ethers.JsonRpcProvider(process.env.RPC_URL_NODE_A);
const operatorSigner = operatorWallet.connect(providerA);

// Connect to Endpoint contract as operator
const endpoint = await hre.ethers.getContractAt(
  'EndpointV1',
  endpointAddressA,
  operatorSigner
);

// Authorize the token
console.log(`Authorizing token ${tokenAddress} with Endpoint...`);
const authTx = await endpoint.addAuthorizedAddresses([tokenAddress]);
await authTx.wait();

console.log(`✓ Token authorized for cross-chain transfers`);
```

**What Happens:**

1. Operator calls `addAuthorizedAddresses()` on the Endpoint
2. Token address is added to the Endpoint's authorized list
3. Token can now call Endpoint's send functions

**Verification:**

```typescript
// Check if token is authorized
const isAuthorized = await endpoint.isAddressAuthorized(tokenAddress);
console.log(`Token authorized: ${isAuthorized}`); // Should be: true
```

### Step 3: Register and Approve Token

!!! note "Registration is a separate step"
    The `tokens:erc20:deploy` task now **only deploys and authorizes** the token. Registration on the Privacy Node's own `PNTokenRegistryV1` is a separate step (`tokens:register`), described below.

A token is first registered and authorized on the Privacy Node's own `PNTokenRegistryV1`, then submitted to the Private Network Hub for cross-chain use. See the [PN Token Registry](../../learn/components/smart-contracts/pn-token-registry.md) page for the full three-status model.

**Why Registration is Needed:**

- The Privacy Node needs an authoritative record of the token before it can be used
- Submitting to the Hub lets the network route cross-chain messages and store metadata for deployment on other chains
- Each token gets a unique `resourceId` for cross-chain identification

**Step 3a: Register on the PN Token Registry**

```typescript
// Register the token on the Privacy Node's PNTokenRegistryV1
const pnRegistry = await hre.ethers.getContractAt(
  'PNTokenRegistryV1',
  process.env.NODE_A_PN_TOKEN_REGISTRY,
  signerA
);

console.log('Registering token on the PN Token Registry...');
await pnRegistry.registerToken(tokenAddress); // single argument, no storage slot

console.log('✓ Token registered (privacyNodeStatus = WAITING_APPROVAL)');
```

**What happens internally:**

- The registry reads name / symbol / totalSupply on-chain from the token
- Symbol uniqueness is enforced on this Privacy Node
- The token's `privacyNodeStatus` becomes `WAITING_APPROVAL`

**Step 3b: Authorize on the Privacy Node**

```typescript
// Helper function to poll until condition is true
async function pollUntil(checkFn, interval = 1000, maxAttempts = 180) {
  for (let i = 0; i < maxAttempts; i++) {
    if (await checkFn()) return true;
    await new Promise(resolve => setTimeout(resolve, interval));
  }
  return false;
}

// PN operator authorizes the token locally (using the system wallet)
const pnRegistryAsOperator = pnRegistry.connect(operatorSigner);

console.log('Authorizing token on the Privacy Node...');
const authPnTx = await pnRegistryAsOperator.updatePrivacyNodeStatus(
  tokenAddress,
  2, // 2 = AUTHORIZED
  { gasLimit: 5000000 }
);
await authPnTx.wait();

console.log('✓ privacyNodeStatus = AUTHORIZED (token is operational locally)');
```

**Step 3c: Submit to the Hub and Approve**

```typescript
// Submit to the Hub (requires PN AUTHORIZED) → hubStatus = WAITING_APPROVAL
console.log('Submitting token to the Private Network Hub...');
await (await pnRegistryAsOperator.submitToHub(tokenAddress)).wait();

// The Hub operator approves on the Hub-side TokenRegistryV1
const tokenRegistryAddress = process.env.NODE_CC_TOKENREGISTRY;
const providerCC = new ethers.JsonRpcProvider(process.env.RPC_URL_NODE_CC);
const operatorSignerCC = operatorWallet.connect(providerCC);
const tokenRegistry = await hre.ethers.getContractAt(
  'TokenRegistryV1',
  tokenRegistryAddress,
  operatorSignerCC
);

// Resolve the resourceId from the Hub-side registry
let resourceId;
const registered = await pollUntil(async () => {
  const allTokens = await tokenRegistry.getAllTokens();
  const myToken = allTokens.find(t => t.name === 'MyToken');
  if (myToken) {
    resourceId = myToken.resourceId;
    console.log(`✓ Token found on the Hub with resourceId: ${resourceId}`);
    return true;
  }
  return false;
});

if (!registered) {
  throw new Error('Hub registration timed out');
}

console.log('Approving token on the Hub...');
const approveTx = await tokenRegistry.updateStatus(
  resourceId,
  1,  // 1 = ACTIVE
  { gasLimit: 5000000 }
);
await approveTx.wait();

console.log('✓ Token approved on the Private Network Hub');
```

**Typical wait time:** 10-30 seconds

**Step 3d: Wait for the activateToken Callback**

```typescript
// The relayer delivers the activateToken callback to the PN Token Registry,
// which registers the resourceId locally and sets hubStatus = AUTHORIZED
console.log('Waiting for the activateToken callback...');
const propagated = await pollUntil(async () => {
  const rid = await token.resourceId();
  if (rid !== ethers.ZeroHash) {
    console.log(`✓ ResourceId propagated: ${rid}`);
    return true;
  }
  return false;
});

if (!propagated) {
  throw new Error('ResourceId propagation timed out');
}

console.log('✓ Token is now ready for cross-chain transfers!');
```

**Typical wait time:** 10-30 seconds

**What Happens:**
1. The token is registered and authorized on the Privacy Node (`PNTokenRegistryV1`)
2. The token is submitted to the Private Network Hub and the Hub operator approves it
3. The Hub assigns a unique `resourceId`
4. The `activateToken` callback registers the resourceId on the source Privacy Node
5. Token can now be teleported cross-chain

### Step 4: Execute Atomic Teleport Transfer

Now that the token is deployed, authorized, registered, and approved, we can perform the cross-chain transfer!

**Parameters:**

- `to`: Recipient address on the destination chain
- `value`: Amount to transfer (in token's smallest unit)
- `destinationChainId`: Chain ID of the destination Privacy Node

**TypeScript Code:**

```typescript
// Configure transfer
const AMOUNT = 100;
const recipientAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
const destinationChainId = process.env.NODE_B_CHAIN_ID; // e.g., 12346

// Check sender balance before transfer
const senderBalance = await token.balanceOf(signerA.address);
console.log(`Sender balance before: ${senderBalance}`);

// Execute atomic teleport
console.log(`\nInitiating atomic teleport of ${AMOUNT} tokens...`);
console.log(`From: Privacy Node A (${process.env.NODE_A_CHAIN_ID})`);
console.log(`To: Privacy Node B (${destinationChainId})`);
console.log(`Recipient: ${recipientAddress}`);

const tx = await token.teleportAtomic(
  recipientAddress,
  AMOUNT,
  destinationChainId,
  { gasLimit: 5000000 }  // Important: Set high gas limit for cross-chain ops
);

console.log(`Transaction hash: ${tx.hash}`);
await tx.wait();

console.log(`✓ Teleport transaction confirmed!`);
console.log(`Waiting for cross-chain transfer to complete...`);
```

**What Happens:**

1. **On Privacy Node A (Source):**

   - Tokens burned from sender's balance
   - `MessageDispatched` event emitted with transfer details
   - Message encrypted and sent to Private Network Hub

2. **On Private Network Hub:**

   - Receives encrypted message
   - Validates sender, token registration, and approval
   - Routes message to destination Privacy Node B
   - Emits `AtomicMessageTeleportStartedBatch` event

3. **On Privacy Node B (Destination):**

   - If token doesn't exist: automatically deploys token contract using bytecode from registry
   - Calls `receiveTeleportAtomic()` on the token
   - Mints tokens to contract owner
   - Locks tokens for recipient (`_lock(to, value)`)
   - Waits for confirmation

4. **Automatic Unlock:**

   - Once confirmed, tokens are unlocked
   - Transferred from owner to recipient
   - Recipient can now use the tokens

**Typical completion time:** 30-60 seconds end-to-end

### Step 5: Verify the Transfer

Let's verify that the tokens arrived on Privacy Node B.

**TypeScript Code:**

```typescript
// Connect to Privacy Node B
const providerB = new ethers.JsonRpcProvider(process.env.RPC_URL_NODE_B);
const signerB = await hre.ethers.getSigner(); // or create specific signer
const endpointAddressB = process.env.NODE_B_ENDPOINT;

// Get Endpoint on Privacy Node B
const endpointB = await hre.ethers.getContractAt(
  'EndpointV1',
  endpointAddressB,
  signerB
);

// Get token address by resourceId
console.log(`\nLooking up token on Privacy Node B...`);
const tokenAddressB = await endpointB.getAddressByResourceId(resourceId);

if (tokenAddressB === ethers.ZeroAddress) {
  console.log('Waiting for token deployment on destination...');
  // Poll until token is deployed
  await pollUntil(async () => {
    const addr = await endpointB.getAddressByResourceId(resourceId);
    return addr !== ethers.ZeroAddress;
  });
  tokenAddressB = await endpointB.getAddressByResourceId(resourceId);
}

console.log(`✓ Token found on Privacy Node B: ${tokenAddressB}`);

// Get token contract on Privacy Node B
const tokenB = await hre.ethers.getContractAt(
  'TokenExample',
  tokenAddressB,
  signerB
);

// Wait for balance to update (tokens to be unlocked)
console.log('Waiting for tokens to be unlocked...');
await pollUntil(async () => {
  const balance = await tokenB.balanceOf(recipientAddress);
  return balance >= BigInt(AMOUNT);
}, 1000, 300); // Wait up to 5 minutes

// Check final balance
const recipientBalance = await tokenB.balanceOf(recipientAddress);
console.log(`\n✓✓✓ TRANSFER SUCCESSFUL! ✓✓✓`);
console.log(`Recipient balance on Privacy Node B: ${recipientBalance}`);
console.log(`Expected: ${AMOUNT}`);
```

**Success Criteria:**

- Token deployed on Privacy Node B (if it's the first transfer)
- Recipient balance on Privacy Node B equals the transferred amount
- Sender balance on Privacy Node A decreased by the transferred amount

## Complete Runnable Script

Here's the complete script combining all steps:

```typescript
// save as: scripts/first-teleport.ts
import hre from 'hardhat';
import { ethers } from 'ethers';

// Helper function for polling
async function pollUntil(
  checkFn: () => Promise<boolean>,
  interval = 1000,
  maxAttempts = 180
): Promise<boolean> {
  for (let i = 0; i < maxAttempts; i++) {
    if (await checkFn()) return true;
    await new Promise(resolve => setTimeout(resolve, interval));
  }
  return false;
}

async function main() {
  console.log('='.repeat(60));
  console.log('RAYLS FIRST ATOMIC TELEPORT TRANSACTION');
  console.log('='.repeat(60));

  // Configuration
  const TOKEN_NAME = 'MyToken';
  const TOKEN_SYMBOL = 'MTK';
  const AMOUNT = 100;
  const recipientAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';

  // Environment variables
  const endpointAddressA = process.env.NODE_A_ENDPOINT!;
  const endpointAddressB = process.env.NODE_B_ENDPOINT!;
  const tokenRegistryAddress = process.env.NODE_CC_TOKENREGISTRY!;
  const chainIdB = process.env.NODE_B_CHAIN_ID!;

  // Providers
  const providerA = new ethers.JsonRpcProvider(process.env.RPC_URL_NODE_A);
  const providerB = new ethers.JsonRpcProvider(process.env.RPC_URL_NODE_B);
  const providerCC = new ethers.JsonRpcProvider(process.env.RPC_URL_NODE_CC);

  // Wallets
  const userWallet = new ethers.Wallet(process.env.PRIVATE_KEY_USER!);
  const systemWallet = new ethers.Wallet(process.env.PRIVATE_KEY_SYSTEM!);

  // Signers for token operations (user wallet)
  const userSignerA = userWallet.connect(providerA);
  const userSignerB = userWallet.connect(providerB);

  // Signers for operator/system operations (system wallet)
  const systemSignerA = systemWallet.connect(providerA);
  const systemSignerCC = systemWallet.connect(providerCC);

  // ===========================================
  // STEP 1: DEPLOY TOKEN
  // ===========================================
  console.log('\n[1/5] Deploying ERC20 token...');

  const TokenFactory = await hre.ethers.getContractFactory('TokenExample', userSignerA);
  const token = await TokenFactory.deploy(
    TOKEN_NAME,
    TOKEN_SYMBOL,
    endpointAddressA,
    process.env.NODE_A_RAYLS_NODE_ENDPOINT_ADDRESS,
    process.env.NODE_A_RAYLS_NODE_USER_GOVERNANCE
  );
  await token.waitForDeployment();
  const tokenAddress = await token.getAddress();

  console.log(`✓ Token deployed: ${tokenAddress}`);

  // ===========================================
  // STEP 2: AUTHORIZE TOKEN
  // ===========================================
  console.log('\n[2/5] Authorizing token with Endpoint...');

  const endpoint = await hre.ethers.getContractAt(
    'EndpointV1',
    endpointAddressA,
    systemSignerA
  );

  const authTx = await endpoint.addAuthorizedAddresses([tokenAddress]);
  await authTx.wait();

  console.log('✓ Token authorized');

  // ===========================================
  // STEP 3: REGISTER & APPROVE TOKEN
  // ===========================================
  console.log('\n[3/5] Registering and approving token...');

  // 3a. Register on the PN Token Registry (single arg, no storage slot)
  const pnRegistry = await hre.ethers.getContractAt(
    'PNTokenRegistryV1',
    process.env.NODE_A_PN_TOKEN_REGISTRY!,
    userSignerA
  );
  await (await pnRegistry.registerToken(tokenAddress)).wait();
  console.log('✓ Registered on the PN Token Registry');

  // 3b. PN operator authorizes the token locally (AUTHORIZED = 2)
  const pnRegistryAsOperator = pnRegistry.connect(systemSignerA);
  await (await pnRegistryAsOperator.updatePrivacyNodeStatus(tokenAddress, 2)).wait();
  console.log('✓ privacyNodeStatus = AUTHORIZED');

  // 3c. Submit to the Hub (requires PN AUTHORIZED)
  await (await pnRegistryAsOperator.submitToHub(tokenAddress)).wait();
  console.log('✓ Submitted to the Private Network Hub');

  // Resolve the resourceId from the Hub-side registry
  const tokenRegistry = await hre.ethers.getContractAt(
    'TokenRegistryV1',
    tokenRegistryAddress,
    providerCC
  );

  let resourceId: string;
  await pollUntil(async () => {
    const tokens = await tokenRegistry.getAllTokens();
    const myToken = tokens.find((t: any) => t.name === TOKEN_NAME);
    if (myToken) {
      resourceId = myToken.resourceId;
      return true;
    }
    return false;
  });

  // 3d. Hub operator approves (ACTIVE = 1)
  const tokenRegistryAsOperator = tokenRegistry.connect(systemSignerCC);
  const approveTx = await tokenRegistryAsOperator.updateStatus(resourceId!, 1);
  await approveTx.wait();
  console.log('✓ Token approved on the Hub');

  // Wait for the activateToken callback to propagate the resourceId
  await pollUntil(async () => {
    const rid = await token.resourceId();
    return rid !== ethers.ZeroHash;
  });

  console.log('✓ ResourceId propagated');

  // ===========================================
  // STEP 4: EXECUTE ATOMIC TELEPORT
  // ===========================================
  console.log('\n[4/5] Executing atomic teleport...');
  console.log(`Amount: ${AMOUNT} ${TOKEN_SYMBOL}`);
  console.log(`To: ${recipientAddress}`);
  console.log(`Destination: Chain ${chainIdB}`);

  const tx = await token.teleportAtomic(
    recipientAddress,
    AMOUNT,
    chainIdB,
    { gasLimit: 5000000 }
  );

  await tx.wait();
  console.log(`✓ Teleport transaction confirmed: ${tx.hash}`);

  // ===========================================
  // STEP 5: VERIFY TRANSFER
  // ===========================================
  console.log('\n[5/5] Verifying transfer on destination...');

  const endpointB = await hre.ethers.getContractAt(
    'EndpointV1',
    endpointAddressB,
    userSignerB
  );

  // Wait for token deployment
  let tokenAddressB: string;
  await pollUntil(async () => {
    const addr = await endpointB.getAddressByResourceId(resourceId!);
    if (addr !== ethers.ZeroAddress) {
      tokenAddressB = addr;
      return true;
    }
    return false;
  }, 1000, 180);

  console.log(`✓ Token deployed on destination: ${tokenAddressB!}`);

  // Wait for balance update
  const tokenB = await hre.ethers.getContractAt(
    'TokenExample',
    tokenAddressB!,
    userSignerB
  );

  await pollUntil(async () => {
    const balance = await tokenB.balanceOf(recipientAddress);
    return balance >= BigInt(AMOUNT);
  }, 1000, 300);

  const finalBalance = await tokenB.balanceOf(recipientAddress);

  console.log('\n' + '='.repeat(60));
  console.log('✓✓✓ FIRST TRANSACTION SUCCESSFUL! ✓✓✓');
  console.log('='.repeat(60));
  console.log(`Token: ${TOKEN_SYMBOL}`);
  console.log(`Recipient: ${recipientAddress}`);
  console.log(`Final Balance: ${finalBalance} ${TOKEN_SYMBOL}`);
  console.log('='.repeat(60));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('\n❌ ERROR:', error.message);
    process.exit(1);
  });
```

**To run:**

```bash
# Make sure you're in the rayls-sovereign-contracts directory
cd ~/work/parfin/rayls-sovereign-contracts

# Run the script
npx hardhat run scripts/first-teleport.ts --network localA
```

## Understanding the Transaction Flow

Here's a visual timeline of what happens during an atomic teleport:

```
PRIVACY NODE A (Source)
│
├─ 1. User calls teleportAtomic()
├─ 2. Burn 100 tokens from sender
├─ 3. Emit MessageDispatched event
└─ 4. Send encrypted message to Private Network Hub
       │
       ▼
PRIVATE NETWORK HUB
│
├─ 5. Receive encrypted message from Relayer A
├─ 6. Validate token is registered & approved
├─ 7. Route message to destination
├─ 8. Emit AtomicMessageTeleportStartedBatch event
└─ 9. Forward to Relayer B
       │
       ▼
PRIVACY NODE B (Destination)
│
├─ 10. Receive message from Relayer B
├─ 11. Deploy token contract (if first time)
├─ 12. Call receiveTeleportAtomic()
├─ 13. Mint 100 tokens to contract owner
├─ 14. Lock tokens for recipient
├─ 15. Wait for confirmation
└─ 16. Unlock and transfer to recipient

Timeline: 30-60 seconds end-to-end
```

**Key Events:**

- `MessageDispatched`: Emitted on Privacy Node A when message is sent
- `AtomicMessageTeleportStartedBatch`: Emitted on Private Network Hub when routing begins
- `MessageReceived`: Emitted on Privacy Node B when message arrives
- `Transfer`: Emitted on Privacy Node B when tokens are unlocked

## Troubleshooting

### Common Issues

**Issue: "Token deployment hangs"**

**Symptoms:**

- Script runs but never completes Step 1
- No error messages

**Cause:**

- Docker environment not running
- Privacy Node A not accessible

**Solution:**
```bash
# Check Docker services
docker compose ps

# Verify Privacy Node A is running
docker compose logs pl-a

# Restart if needed
docker compose restart pl-a
```

---

**Issue: "Token not authorized"**

**Symptoms:**
```
Error: Token 0x... is not authorized to use endpoint send functions
```

**Cause:**

- Step 2 (authorization) was skipped
- Authorization transaction failed
- Wrong operator account used

**Solution:**
```typescript
// Verify operator has permissions
const owner = await endpoint.owner();
console.log(`Endpoint owner: ${owner}`);
console.log(`Operator address: ${operatorSigner.address}`);
// These should match!

// Re-run authorization
await endpoint.addAuthorizedAddresses([tokenAddress]);
```

**Verification:**
```typescript
const isAuthorized = await endpoint.isAddressAuthorized(tokenAddress);
console.log(`Is authorized: ${isAuthorized}`); // Should be true
```

---

**Issue: "ResourceId is zero"**

**Symptoms:**
```
Error: Token resourceId is still zero after timeout
```

**Cause:**

- Token not registered on Private Network Hub
- Approval not completed
- ResourceId didn't propagate back

**Solution:**
```bash
# Check if token is registered
npx hardhat getAllTokens --network localCC

# Check relayer logs
docker compose logs -f relayer-a

# Verify Private Network Hub is healthy
docker compose ps commit-chain
```

**Manual check:**
```typescript
// Check token on Private Network Hub
const tokens = await tokenRegistry.getAllTokens();
const myToken = tokens.find(t => t.name === 'MyToken');
console.log('Token on Private Network Hub:', myToken);

// Check status (should be 1 = Approved)
console.log('Status:', myToken.status);

// Check resourceId on Privacy Node A
const rid = await token.resourceId();
console.log('ResourceId on PL-A:', rid);
```

---

**Issue: "Transfer hangs / doesn't complete"**

**Symptoms:**

- Teleport transaction confirms
- Balance on destination never updates
- Script hangs at Step 5

**Cause:**

- Relayer B not running
- Message stuck in queue
- Privacy Node B not processing messages

**Solution:**
```bash
# Check all relayers
docker compose ps | grep relayer

# View relayer B logs
docker compose logs -f relayer-b

# Check for errors
docker compose logs relayer-b | grep -i error

# Restart relayer B
docker compose restart relayer-b
```

**Check message status:**
```bash
# View Private Network Hub logs
docker compose logs -f commit-chain

# View Privacy Node B logs
docker compose logs -f pl-b
```

---

**Issue: "Token not found on destination"**

**Symptoms:**
```
Error: Token address is ZeroAddress on destination
```

**Cause:**

- Automatic token deployment failed
- Bytecode not stored in TokenRegistry
- Deployment transaction reverted

**Solution:**

```bash
# Check Privacy Node B logs for deployment errors
docker compose logs pl-b | grep -i "deploy\|error\|revert"

# Check token bytecode in registry
npx hardhat console --network localCC
> const registry = await ethers.getContractAt('TokenRegistryV1', 'REGISTRY_ADDRESS');
> const tokens = await registry.getAllTokens();
> const myToken = tokens.find(t => t.name === 'MyToken');
> console.log('Bytecode length:', myToken.bytecode.length);
```

**Workaround:**

- Resend tokens (will retry deployment)
- Or manually deploy token on destination using the same parameters

---

**Issue: "Insufficient gas"**

**Symptoms:**
```
Error: Transaction reverted: out of gas
```

**Cause:**

- Gas limit too low for cross-chain operation
- Complex contract execution

**Solution:**

```typescript
// Always set high gas limit for teleport operations
const tx = await token.teleportAtomic(
  recipientAddress,
  AMOUNT,
  destinationChainId,
  { gasLimit: 5000000 }  // ← Important!
);
```

---

**Issue: "Tokens received but balance is zero"**

**Symptoms:**

- Transfer appears successful
- Recipient balance is still 0
- No errors in logs

**Cause:**

- Tokens are locked, waiting for unlock confirmation
- Unlock transaction not yet processed

**Check locked balance:**

```typescript
const tokenB = await hre.ethers.getContractAt('TokenExample', tokenAddressB);

// Check locked tokens
const lockedAmount = await tokenB.lockedBalances(recipientAddress);
console.log(`Locked tokens: ${lockedAmount}`);

// Check actual balance
const balance = await tokenB.balanceOf(recipientAddress);
console.log(`Unlocked balance: ${balance}`);
```

**Solution:**

- Wait longer (unlock can take 30-60 seconds)
- Check relayer logs for unlock transactions
- Verify Private Network Hub is confirming messages

**Manual unlock (if needed):**

```typescript
// As contract owner
const owner = new ethers.Wallet(process.env.PRIVATE_KEY_SYSTEM);
const tokenBAsOwner = tokenB.connect(owner.connect(providerB));

await tokenBAsOwner.unlock(recipientAddress, AMOUNT);
```

---

### Debugging Commands

**View Docker service status:**
```bash
# All services
docker compose ps

# Specific services
docker compose ps relayer-a relayer-b pl-a pl-b commit-chain
```

**View real-time logs:**
```bash
# Relayers (message routing)
docker compose logs -f relayer-a relayer-b

# Privacy Nodes (transaction execution)
docker compose logs -f pl-a pl-b

# Private Network Hub (coordination)
docker compose logs -f commit-chain

# All together
docker compose logs -f relayer-a relayer-b pl-a pl-b commit-chain
```

**Check account balances:**
```typescript
// ETH balance (for gas)
const ethBalance = await providerA.getBalance(signerA.address);
console.log(`ETH balance: ${ethers.formatEther(ethBalance)}`);

// Token balance
const tokenBalance = await token.balanceOf(signerA.address);
console.log(`Token balance: ${tokenBalance}`);
```

**Verify environment setup:**
```bash
cd ~/work/parfin/rayls-sovereign-contracts

# Check if .env is loaded
node -e "require('dotenv').config(); console.log('RPC_URL_NODE_A:', process.env.RPC_URL_NODE_A);"
```

---

### Getting Help

If you encounter issues not covered here:

1. **Check Prerequisites**: Verify Docker is running and accounts are configured
2. **Review Logs**: Always check Docker logs for the services involved
3. **Consult Documentation**:
   - [Docker Setup](docker-setup.md) - Environment troubleshooting
   - [Account Setup](account-setup.md) - Account configuration issues
   - [Architecture Overview](architecture-overview.md) - Understanding the system
4. **Community Support**: Reach out with specific error messages and logs

## Next Steps

🎉 Congratulations! You've successfully performed your first atomic teleport transfer.

**What's Next:**

**Explore More Token Operations:**

- **Batch Transfers**: Send tokens to multiple recipients in one transaction
- **Third-Party Transfers**: Use allowances for delegated transfers
- **NFTs**: Try ERC721 and ERC1155 cross-chain transfers

**Dive into Privacy Features:**

- **Enygma Tokens**: Privacy-preserving token transfers with zero-knowledge proofs
- **DVP**: Atomic swaps with hidden amounts and parties
- **Private Balances**: Hide transaction amounts from observers

**Build Applications:**

- [API Reference](../intermediate/api-reference.md) - Complete contract documentation
- [Endpoint Integration](../intermediate/endpoint-integration.md) - Integrate with your apps
- [Testing Guide](../reference/testing-guide.md) - Write comprehensive tests

**Advanced Topics:**

- [Enygma Privacy](../advanced/enygma-privacy.md) - Zero-knowledge protocols
- [DVP Atomic Swaps](../advanced/dvp-atomic-swaps.md) - Private atomic swaps
- [Public Chain Bridge](../advanced/public-chain-bridge.md) - Public chain integration
