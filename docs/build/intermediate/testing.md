# Testing

## Introduction

Testing is critical in cross-chain systems where assets move across multiple chains and failures can result in lost funds. Rayls provides a comprehensive end-to-end (e2e) test suite covering token operations, privacy features, atomic swaps, and infrastructure components.

**Why e2e testing matters:**

- **Cross-chain complexity**: Multiple chains, relayers, and asynchronous message delivery
- **Asset safety**: Failed transfers must not result in token loss
- **Privacy guarantees**: Enygma tests verify cryptographic commitments
- **Atomic operations**: DVP tests ensure all-or-nothing execution
- **Real-world scenarios**: Tests run against actual blockchain nodes, not mocks

**Test pyramid for Rayls:**

```
         /\
        /  \  E2E Tests (67 files, ~41K lines)
       /----\  ↑ Cross-chain flows, full system integration
      /      \
     /--------\ Integration Tests
    /          \ ↑ Contract interactions
   /------------\
  /--------------\ Unit Tests
 /________________\ ↑ Individual functions
```

This guide focuses on the **e2e test layer** - running existing tests and writing new ones for cross-chain features.

!!! info "Prerequisites"
    - Understand [Transaction Lifecycle](transaction-lifecycle.md) for test timing expectations
    - Read [Token Standards](token-standards.md) for teleport mechanisms being tested
    - Know [Security](security.md) for security test scenarios

**What this guide covers:**

- Running existing e2e tests
- Understanding test output
- Test organization and categories
- Writing your own cross-chain tests
- Debugging common issues

---

## Test Organization Overview

### Directory Structure

```
rayls-sovereign-contracts/
└── hardhat/
    └── test/
        ├── e2e/                          # E2E tests (67 files)
        │   ├── Erc20.ts                  # ERC20 token tests
        │   ├── Erc721.ts                 # ERC721 NFT tests
        │   ├── Erc1155.ts                # ERC1155 multi-token tests
        │   ├── ArbitraryMessages.ts      # Cross-chain messaging
        │   ├── BatchTransfer.ts          # Batch operations
        │   ├── FreezeTokens.ts           # Token freeze tests
        │   ├── Erc20-public-chain.ts     # Public chain bridge
        │   ├── Erc20-private-to-public.ts # Private→Public flow
        │   ├── enygma/                   # Privacy tests (34 files)
        │   │   ├── Enygma_1-1.ts         # One-to-one private transfer
        │   │   ├── Enygma_1-2_batch.ts   # Batched private transfers
        │   │   ├── Enygma_1-1_conc.ts    # Concurrent transfers
        │   │   └── Enygma_1-1_stressTest.ts # Performance tests
        │   ├── dvp/                    # Atomic swap tests (21 files)
        │   │   ├── ZkDvp_Swap_NFT_Enygma_OneDeposit.ts
        │   │   ├── Enygma_ZkDvp-OneDeposit-Withdraw-BalanceCheck.ts
        │   │   └── ZkDvp_ERC721_Security.ts
        │   └── backend/                  # Backend API tests (3 files)
        │       ├── Test_ERC20.ts
        │       ├── Test_ERC721.ts
        │       └── Test_ERC1155.ts
        └── utils/                        # Test utilities
            ├── Constants.ts              # Test configuration
            ├── Utils.ts                  # Helper functions
            └── UtilsBackend.ts           # Backend helpers
```

---

### Test Categories

**Core Token Tests (8 files):**

- ERC20, ERC721, ERC1155 cross-chain teleports
- Vanilla and atomic transfers
- Public chain bridging
- Private-to-public flows

**Enygma Privacy Tests (34 files, ~37K lines):**

- Private transfers with hidden balances
- 1-to-N transfer patterns
- Batch and concurrent operations
- Stress and performance tests

**DVP Atomic Swap Tests (21 files, ~4.7K lines):**

- NFT-for-token atomic swaps
- Zero-knowledge deposit/withdraw
- Consolidation and security tests

**Infrastructure Tests (3 files):**

- Arbitrary cross-chain messages
- Batch transfer operations
- Token freeze functionality

**Backend Integration Tests (3 files):**

- User onboarding API
- Token registration API
- Public chain transfer API

---

### Test Statistics

- **Total e2e test files:** 67
- **Total lines of test code:** ~41,654
- **Test categories:** 5 main categories
- **Test commands:** 15+ npm scripts
- **Coverage:** Token operations, privacy, atomic swaps, security, infrastructure

---

## Running Tests

### Environment Setup

Before running tests, ensure the following are running:

**Required nodes:**

```bash
# Privacy Node Ledger nodes
- Node A (RPC_URL_NODE_A)
- Node B (RPC_URL_NODE_B)
- Node C (RPC_URL_NODE_C) # For multi-ledger tests
- Node D, E, F # For advanced tests

# Coordination layer
- Private Network Hub (RPC_URL_NODE_CC) # Legacy variable name

# Public chain bridge (optional)
- Public Chain (RPC_URL_NODE_PC)
```

**Required services:**

```bash
# MongoDB instances (for Enygma tests)
- MongoDB for Node A (NODE_A_MONGO_CS)
- MongoDB for Node B (NODE_B_MONGO_CS)

# Backend API (for backend tests)
- Backend service (BACKEND_URL)
```

**Environment variables:**

Create `.env` file in `rayls-sovereign-contracts/` directory:

```bash
# Node RPC URLs
RPC_URL_NODE_A=http://localhost:8545  # Privacy Node Ledger A
RPC_URL_NODE_B=http://localhost:8546  # Privacy Node Ledger B
RPC_URL_NODE_CC=http://localhost:8547  # Private Network Hub (legacy variable name)

# Chain IDs
NODE_A_CHAIN_ID=1001  # Privacy Node Ledger A
NODE_B_CHAIN_ID=1002  # Privacy Node Ledger B
NODE_CC_CHAIN_ID=1000  # Private Network Hub

# Operator key
PRIVATE_KEY_SYSTEM=0x...

# Contract addresses (auto-populated after deployment)
NODE_A_DEPLOYMENTPROXYREGISTRY=0x...
NODE_B_DEPLOYMENTPROXYREGISTRY=0x...

# MongoDB (for Enygma tests)
NODE_A_MONGO_CS=mongodb://localhost:27017/nodeA
NODE_B_MONGO_CS=mongodb://localhost:27018/nodeB

# Backend (for backend tests)
BACKEND_URL=http://localhost:3000
BACKEND_USER_AUTH_KEY=user-api-key
BACKEND_OPERATOR_AUTH_KEY=operator-api-key
```

---

### Basic Test Commands

**Run all e2e tests:**

```bash
cd rayls-sovereign-contracts
npm run test:e2e
```

**Run specific test categories:**

```bash
# Token tests
npm run test:e2e-erc20              # ERC20 teleports
npm run test:e2e-erc721             # ERC721 NFTs
npm run test:e2e-erc1155            # ERC1155 multi-tokens

# Public chain tests
npm run test:e2e-erc20-public       # ERC20 public chain bridge
npm run test:e2e-erc20-private-to-public  # Private→Public flow
npm run test:e2e-public             # All public chain tests

# Infrastructure tests
npm run test:e2e-am                 # Arbitrary messages
npm run test:e2e-batch              # Batch transfers

# Privacy tests
npm run test:e2e-enygma             # All Enygma privacy tests

# Atomic swap tests
npm run test:e2e-zkdvp              # All DVP swap tests
```

---

### Running Specific Test Files

**Run individual test file:**

```bash
# Token test
npx hardhat test hardhat/test/e2e/Erc20.ts

# Enygma privacy test
npx hardhat test hardhat/test/e2e/enygma/Enygma_1-1.ts

# DVP atomic swap
npx hardhat test hardhat/test/e2e/dvp/ZkDvp_Swap_NFT_Enygma_OneDeposit.ts

# Backend integration
npx hardhat test hardhat/test/e2e/backend/Test_ERC20.ts
```

**Run specific test within file:**

```bash
# Run only tests matching pattern
npx hardhat test hardhat/test/e2e/Erc20.ts --grep "vanilla"

# Run only tests matching "atomic"
npx hardhat test hardhat/test/e2e/Erc20.ts --grep "atomic"
```

---

### Understanding Test Output

**Successful test output:**

```
E2E Tests: Erc20 (erc20)
  Token: MyToken (MTK)
  Resource ID: 0x4d544b0000000000000000000000000000000000000000000000000000000000

  ✓ Should register and approve token (15432ms)
  ✓ Should teleport Vanilla from A to B (automatic contract deploy on B) (32145ms)
  ✓ Should teleport atomic from B to A (28756ms)
  ✓ Should teleport atomic from A to B, fail when reaching B and revert (45231ms)
  ✓ Should teleport vanilla and atomic as a 3rd Party from A to B (31987ms)

  5 passing (2m 34s)
```

**What to look for:**

- ✓ Green checkmarks = tests passed
- Timing in parentheses (should be < 60s for simple operations)
- No red ✗ or errors
- Final summary shows all passing

**Failed test output:**

```
1) E2E Tests: Erc20 (erc20)
     Should teleport atomic from B to A:
   Error: Timeout: Balance did not update within expected time
   Expected: 30n
   Received: 0n
```

**Common failure reasons:**

- **Timeout**: Relayer not running or network congestion
- **Balance mismatch**: Transaction failed on destination
- **Connection error**: Node not running or wrong RPC URL
- **Revert**: Contract logic rejected transaction

---

### Troubleshooting Common Issues

**Issue: "Error: could not detect network"**

**Solution:** Check node is running and RPC URL is correct:

```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545
```

**Issue: "Timeout waiting for balance update"**

**Solution:**

1. Check relayer logs: `docker logs rayls-relayer-1`
2. Verify relayer is running: `docker ps | grep relayer`
3. Increase test timeout if network is slow

**Issue: "TypeError: Cannot read property 'address' of undefined"**

**Solution:** Ensure contract deployment completed in `before()` hook. Check previous test didn't fail.

**Issue: "MongoError: connect ECONNREFUSED"**

**Solution:** Start MongoDB for Enygma tests:

```bash
docker start mongodb-nodeA
docker start mongodb-nodeB
```

---

## Token Tests

Token tests verify ERC20, ERC721, and ERC1155 cross-chain teleport functionality.

### What Token Tests Cover

- ✅ Token deployment on source Privacy Node Ledger
- ✅ Token registration on Private Network Hub
- ✅ Vanilla teleport (one-way transfer)
- ✅ Atomic teleport (with auto-revert)
- ✅ Failed atomic teleport (reverts correctly)
- ✅ Third-party teleport with approval
- ✅ Automatic contract deployment on destination
- ✅ Balance consistency across chains
- ✅ Frozen participant handling

---

### Running Token Tests

**All token tests:**

```bash
npm run test:e2e-erc20
npm run test:e2e-erc721
npm run test:e2e-erc1155
```

**Individual test files:**

```bash
npx hardhat test hardhat/test/e2e/Erc20.ts
npx hardhat test hardhat/test/e2e/Erc721.ts
npx hardhat test hardhat/test/e2e/Erc1155.ts
```

**Expected duration:**

- ERC20 tests: ~2-3 minutes
- ERC721 tests: ~2-3 minutes
- ERC1155 tests: ~2-3 minutes

---

### Test Code Example: ERC20 Teleport

**File:** `hardhat/test/e2e/Erc20.ts`

**Test structure:**

```typescript
describe('E2E Tests: Erc20 (erc20)', function () {
  const AMOUNT = 30;
  const privacyLedger: { [NODE: string]: RaylsNode } = {};

  // Initialize Privacy Node Ledgers A, B, C, D
  for (const pl of PRIVACY_LEDGERS.filter(pl => pl == 'A' || pl == 'B')) {
    privacyLedger[pl] = new RaylsNode(pl, hre);
  }

  const commitChain = new CommitChain(hre); // Legacy class name - refers to Private Network Hub
  const token = new Token();

  // Setup: Deploy contracts before tests
  before(async function () {
    this.timeout(DEFAULT_TIMEOUT);
    await commitChain.initialize(); // Initialize Private Network Hub
    await privacyLedger.A.initialize();
    await privacyLedger.B.initialize();

    // Deploy token on Privacy Node Ledger A
    const erc20ContractFactory = await privacyLedger.A.getContractFactory('TokenExample');
    await privacyLedger.A.deploy(
      erc20ContractFactory,
      token.symbol,
      token.name,
      token.symbol,
      privacyLedger.A.endpointAddress,
      privacyLedger.A.raylsNodeEndpointAddress,
      privacyLedger.A.raylsNodeUserGovernance
    );

    // Authorize token to use endpoint
    const tokenAddress = await tokenContract.getAddress();
    const endpointA = await ethers.getContractAt('EndpointV1', privacyLedger.A.endpointAddress);
    await endpointA.addAuthorizedAddresses([tokenAddress]);
  });

  // Test 1: Register token on Private Network Hub
  it('Should register and approve token',
    shouldRegisterAndApproveToken(commitChain, privacyLedger.A, token)
  ).timeout(DEFAULT_TIMEOUT);

  // Test 2: Vanilla teleport A → B
  it('Should teleport Vanilla from A to B', async function () {
    // Execute teleport
    await commitChain.wait(
      privacyLedger.A.getContract('TokenExample').teleport(
        privacyLedger.B.signer.address,  // recipient
        AMOUNT,                           // amount
        privacyLedger.B.chainId,          // destination chain
        { gasLimit: GAS_LIMIT }
      ),
      `Teleporting ${AMOUNT} to ${privacyLedger.B.chainId}...`
    );

    // Wait for automatic contract deployment on B
    await commitChain.waitUntil(
      async () => {
        const tokenAddress = await privacyLedger.B.getContract('EndpointV1')
          .getAddressByResourceId(token.resourceId);

        if (tokenAddress === ZERO_ADDRESS) return false;

        await privacyLedger.B.getContractAt('TokenExample', tokenAddress, token.symbol);
        return true;
      },
      `Checking contract deploy on ${privacyLedger.B.chainId}`
    );

    // Verify balance on destination
    await commitChain.waitUntil(
      async () => {
        const balance = await privacyLedger.B.getContract('TokenExample')
          .balanceOf(privacyLedger.B.signer.address);

        return balance === BigInt(AMOUNT);
      },
      `Checking balance...`
    );
  }).timeout(DEFAULT_TIMEOUT);

  // Test 3: Atomic teleport B → A
  it('Should teleport atomic from B to A', async function () {
    const balanceBefore = {
      A: await privacyLedger.A.getContract('TokenExample').balanceOf(privacyLedger.A.signer.address),
      B: await privacyLedger.B.getContract('TokenExample').balanceOf(privacyLedger.B.signer.address)
    };

    // Execute atomic teleport
    await commitChain.wait(
      privacyLedger.B.getContract('TokenExample').teleportAtomic(
        privacyLedger.A.signer.address,  // recipient
        AMOUNT,                           // amount
        privacyLedger.A.chainId,          // destination chain
        { gasLimit: GAS_LIMIT }
      ),
      `Teleporting ${AMOUNT} to ${privacyLedger.A.chainId}`
    );

    // Verify balances updated on both chains
    await commitChain.waitUntil(
      async () => {
        const balanceA = await privacyLedger.A.getContract('TokenExample')
          .balanceOf(privacyLedger.A.signer.address);
        const balanceB = await privacyLedger.B.getContract('TokenExample')
          .balanceOf(privacyLedger.B.signer.address);

        return balanceB === balanceBefore.B - BigInt(AMOUNT) &&
               balanceA === balanceBefore.A + BigInt(AMOUNT);
      },
      `Checking balances...`
    );
  }).timeout(DEFAULT_TIMEOUT);

  // Test 4: Failed atomic teleport with automatic revert
  it('Should teleport atomic from A to B, fail and revert', async function () {
    // Get address that causes failure (addressToFail)
    const addressToFail = await privacyLedger.A.getContract('TokenExample').addressToFail();

    const balanceBefore = {
      A: await privacyLedger.A.getContract('TokenExample').balanceOf(privacyLedger.A.signer.address),
      B: await privacyLedger.B.getContract('TokenExample').balanceOf(addressToFail)
    };

    // Execute atomic teleport to fail address
    await commitChain.wait(
      privacyLedger.A.getContract('TokenExample').teleportAtomic(
        addressToFail,               // recipient (will fail)
        AMOUNT,
        privacyLedger.B.chainId,
        { gasLimit: GAS_LIMIT }
      ),
      `Teleporting from A to fail address on B...`
    );

    // Verify balances unchanged (automatic revert occurred)
    await commitChain.waitUntil(
      async () => {
        const balanceA = await privacyLedger.A.getContract('TokenExample')
          .balanceOf(privacyLedger.A.signer.address);
        const balanceB = await privacyLedger.B.getContract('TokenExample')
          .balanceOf(addressToFail);

        // Balances should be unchanged (tokens refunded to sender)
        return balanceA === balanceBefore.A && balanceB === balanceBefore.B;
      },
      `Checking balances...`
    );
  }).timeout(DEFAULT_TIMEOUT);
});
```

---

### What Token Tests Guarantee

**Vanilla teleport guarantees:**

- ✅ Tokens burned on source chain
- ✅ Tokens minted on destination chain
- ✅ Contract automatically deployed if not exists
- ✅ Balance consistency (source decreases, destination increases)
- ⚠️ No automatic revert on failure

**Atomic teleport guarantees:**

- ✅ All-or-nothing execution
- ✅ Automatic revert if destination fails
- ✅ Balance preservation on failure (tokens refunded)
- ✅ Lock/unlock mechanism prevents partial state
- ✅ Safe for production use

**Third-party teleport guarantees:**

- ✅ Approval-based transfers (like ERC20 transferFrom)
- ✅ Third party can initiate on behalf of token owner
- ✅ Same balance consistency as regular teleport

---

## Cross-Chain Transfer Tests

Cross-chain transfers are the core functionality tested across all token types.

### Vanilla vs Atomic Teleport

!!! info "Complete Atomic Teleport Documentation"
    This section covers the **testing** perspective of atomic teleport. For comprehensive coverage:

    - **Complete mechanism**: [Token Standards: Atomic Teleport 4-Payload System](token-standards.md#how-it-works-four-payloads) - Canonical reference
    - **Transaction flow**: [Transaction Lifecycle: Phase 5 Atomic Confirmation](transaction-lifecycle.md#phase-5-atomic-confirmation) - Step-by-step flow and timing
    - **Security analysis**: [Security: Atomic Transaction Security](security.md#atomic-transaction-security) - Lock/unlock security and attack prevention

**Vanilla teleport (`teleport`):**

```typescript
// Simple one-way transfer
await token.teleport(
  recipient,          // destination address
  amount,             // amount to send
  destinationChainId  // target chain ID
);
```

**What happens:**

1. Tokens burned on source chain (~2-4s)
2. Cross-chain message dispatched
3. Tokens minted on destination (~30-60s total)
4. **If destination fails**: Tokens lost (burned but not minted)

**Use case:** Development, testing, scenarios with manual recovery

---

**Atomic teleport (`teleportAtomic`):**

```typescript
// Transfer with automatic revert
await token.teleportAtomic(
  recipient,          // destination address
  amount,             // amount to send
  destinationChainId  // target chain ID
);
```

**What happens:**

1. Tokens burned on source chain (~2-4s)
2. Cross-chain message with 4 payloads dispatched
3. Tokens minted to escrow and locked (~30-60s)
4. **If success**: Unlock executes, recipient receives tokens (~60-80s total)
5. **If failure**: Revert executes, sender refunded (~60-90s total)

**Use case:** Production, user-facing applications, safety-critical scenarios

---

### Balance Verification Pattern

All tests follow this pattern for verifying cross-chain transfers:

```typescript
// 1. Capture balances before transfer
const balanceBefore = {
  source: await sourceToken.balanceOf(sender),
  dest: await destToken.balanceOf(recipient)
};

// 2. Execute cross-chain transfer
await commitChain.wait(
  sourceToken.teleportAtomic(recipient, amount, destChainId),
  'Teleporting...'
);

// 3. Poll until balances update
await commitChain.waitUntil(
  async () => {
    const balanceSource = await sourceToken.balanceOf(sender);
    const balanceDest = await destToken.balanceOf(recipient);

    // Verify both sides updated correctly
    return balanceSource === balanceBefore.source - BigInt(amount) &&
           balanceDest === balanceBefore.dest + BigInt(amount);
  },
  'Checking balances...'
);
```

**Key points:**

- **Before snapshot**: Capture balances before operation
- **Non-blocking wait**: `commitChain.wait()` submits transaction
- **Polling**: `commitChain.waitUntil()` polls until condition true
- **Both sides**: Verify source decreased AND destination increased
- **BigInt**: Use BigInt for token amounts (Solidity uint256)

---

### What to Check in Test Results

**Successful transfer indicators:**

```
✓ Should teleport atomic from B to A (28756ms)
```

- ✓ Green checkmark
- Reasonable timing (< 60s for simple operations)
- No errors or warnings

**Look for in logs:**

```
Token: MyToken (MTK)
Teleporting 30 to 1002...
Checking balances...
```

- Clear operation description
- Chain ID matches expected destination
- Balance checks complete

**Failed transfer indicators:**

```
1) Should teleport atomic from B to A:
   Error: Timeout: Balance did not update within expected time
```

- Red ✗ or error message
- Timeout errors (> 2 minutes)
- Balance mismatches

---

## Enygma Privacy Tests

Enygma tests verify privacy-preserving transfers using Pedersen commitments to hide balances.

### What Enygma Tests Cover

- ✅ **Privacy**: Balances hidden using cryptographic commitments
- ✅ **Multi-destination**: One sender to N recipients (1-to-5 patterns)
- ✅ **Atomicity**: All-or-nothing multi-party transfers
- ✅ **Batch operations**: Multiple transfers in single transaction
- ✅ **Concurrent safety**: Pending transfers handled correctly
- ✅ **Revert safety**: Failed transfers automatically revert
- ✅ **Database consistency**: Off-chain DB matches on-chain commitments
- ✅ **Payload execution**: Smart contract calls on destination

---

### Running Enygma Tests

**All Enygma tests (takes ~30-60 minutes):**

```bash
npm run test:e2e-enygma
```

**Individual Enygma test files:**

```bash
# Basic 1-to-1 private transfer
npx hardhat test hardhat/test/e2e/enygma/Enygma_1-1.ts

# Batch private transfers
npx hardhat test hardhat/test/e2e/enygma/Enygma_1-2_batch.ts

# Concurrent transfers
npx hardhat test hardhat/test/e2e/enygma/Enygma_1-1_conc.ts

# Edge cases (reverts, wrong payload, recovery)
npx hardhat test hardhat/test/e2e/enygma/EnygmaEdgeCases.ts
```

---

### Enygma Test Patterns

**Transfer patterns:**

- **1-to-1**: One sender → one recipient
- **1-to-2**: One sender → two recipients
- **1-to-3**: One sender → three recipients
- **1-to-4**: One sender → four recipients
- **1-to-5**: One sender → five recipients

**Variations:**

- **Regular**: Sequential transfers
- **Batch** (`_batch`): Multiple transfers batched
- **Concurrent** (`_conc`): Mint/burn during pending flow
- **Concurrent + Batch** (`_conc-batch`): Both optimizations

**Stress tests:**

- **Duplex**: Bidirectional transfers (A↔B)
- **Triplex**: Three-way transfers (A→B, B→C, C→A)
- **Single Token**: All operations on one token

---

### What Enygma Tests Guarantee

**Privacy guarantees:**

- Actual token amounts hidden in commitments
- Only sender and recipient know transfer amounts
- Observers see only encrypted data

**Atomicity guarantees:**

- All destinations receive OR no one receives
- Failed multi-destination transfer reverts all
- Partial deliveries impossible

**Database consistency:**

- MongoDB balances match on-chain commitments
- Balance queries return correct values
- Concurrent updates handled safely

**Revert safety:**

- Failed transfers automatically refund sender
- System continues working after failures
- Reference IDs track transaction status

---

## DVP Atomic Swap Tests

DVP (Zero-Knowledge Delivery vs Payment) tests verify atomic swaps between NFTs and tokens using zero-knowledge proofs.

### What DVP Tests Cover

- ✅ **Atomicity**: Swap succeeds completely or fails completely
- ✅ **Privacy**: Zero-knowledge proofs hide transaction details
- ✅ **Deposit/Withdraw**: Enygma tokens to DVP pool
- ✅ **NFT swaps**: ERC721 and ERC1155 atomic exchanges
- ✅ **Consolidation**: Multiple deposits properly merged (>10 deposits)
- ✅ **Change handling**: Excess funds returned correctly
- ✅ **Security**: Only token owners can deposit
- ✅ **Cross-chain**: Swaps across different Privacy Node Ledgers

---

### Running DVP Tests

**All DVP tests:**

```bash
npm run test:e2e-zkdvp
```

**Specific swap tests:**

```bash
# Single deposit NFT swap
npm run test:e2e-zkdvp:swap:nft_enygma_one_deposits

# Ten deposit NFT swap
npm run test:e2e-zkdvp:swap:nft_enygma_ten_deposits

# Consolidation test (11 deposits)
npm run test:e2e-zkdvp:swap:enygma_nft_eleven_deposits
```

**Individual test files:**

```bash
# Basic deposit/withdraw
npx hardhat test hardhat/test/e2e/dvp/Enygma_ZkDvp-OneDeposit-Withdraw-BalanceCheck.ts

# NFT for Enygma swap
npx hardhat test hardhat/test/e2e/dvp/ZkDvp_Swap_NFT_Enygma_OneDeposit.ts

# Security tests
npx hardhat test hardhat/test/e2e/dvp/ZkDvp_ERC721_Security.ts
```

---

### DVP Test Scenarios

**Deposit/Withdraw flow:**

1. User deposits Enygma tokens to DVP pool
2. DVP locks tokens and generates proof
3. User can withdraw anytime with change
4. Balance consistency maintained

**Atomic swap flow:**

1. User A deposits Enygma tokens (PN-A)
2. User B deposits NFT (PN-B)
3. Atomic swap executes
4. User A receives NFT on PN-A
5. User B receives Enygma tokens on PN-B
6. Change returned to User A if applicable

**Consolidation (>10 deposits):**

- Tests efficient handling of many small deposits
- Verifies proof generation doesn't fail
- Ensures withdraw works with consolidated balance

---

### What DVP Tests Guarantee

**Atomicity:**

- Swap succeeds for both parties OR fails for both
- No partial swaps (one party receives, other doesn't)
- Automatic rollback on any failure

**Security:**

- Only token owner can deposit their tokens
- Unauthorized deposits rejected
- Lock status prevents double-spend

**Privacy:**

- Zero-knowledge proofs hide amounts
- Observers can't determine swap values
- Commitment-based balance tracking

**Correctness:**

- Change calculated and returned accurately
- Multiple deposits consolidated correctly
- Cross-chain transfers maintain consistency

---

## Infrastructure Tests

Infrastructure tests verify core protocol features beyond token transfers.

### Arbitrary Messages

**File:** `hardhat/test/e2e/ArbitraryMessages.ts`

**What it tests:**

- Send 1 message to single destination
- Send 3 messages to single destination
- Send multiple messages to different participants
- Send same message to multiple participants
- Send message to all participants
- Send message with metadata
- Performance: 60 sequential messages

**Running:**

```bash
npm run test:e2e-am
```

**Guarantees:**

- Messages reliably delivered across chains
- Multiple messages can be batched
- Broadcast to multiple participants works
- Message metadata preserved

---

### Batch Transfers

**File:** `hardhat/test/e2e/BatchTransfer.ts`

**What it tests:**

- Two messages (5 different encoding methods)
- Many messages (50 messages in single batch)
- Different payload encoding compatibility

**Running:**

```bash
npm run test:e2e-batch
```

**Guarantees:**

- Multiple operations atomic within transaction
- Different encoding methods compatible
- Batch size limits enforced

---

### Token Freeze

**File:** `hardhat/test/e2e/FreezeTokens.ts`

**What it tests:**

- Freeze ERC20/721/1155 for specific participants
- Unfreeze tokens
- Revert teleport when frozen
- Success after unfreezing

**Guarantees:**

- Only operators can freeze/unfreeze
- Frozen tokens cannot be transferred
- Freeze syncs to Privacy Node Ledger replicas
- Unfreeze restores normal operations

---

## Public Chain Bridge Tests

Public chain tests verify bidirectional token transfers between Privacy Node Ledgers and public blockchains.

### What Public Chain Tests Cover

- ✅ User onboarding with public/private address pairs
- ✅ Token registration for public bridging
- ✅ Private → Public transfers (lock and mint)
- ✅ Public → Private transfers (burn and unlock)
- ✅ Automatic public token deployment by relayer
- ✅ Balance consistency across chains
- ✅ Revert handling for invalid operations

---

### Running Public Chain Tests

```bash
# All public chain tests
npm run test:e2e-public

# Individual test categories
npm run test:e2e-erc20-public
npm run test:e2e-erc721-public
npm run test:e2e-erc1155-public
npm run test:e2e-erc20-private-to-public
```

---

### Public Chain Flow

**User setup:**

1. Create user with public/private address pair
2. Approve user in governance
3. Fund private address

**Token setup:**

1. Deploy token on Privacy Node Ledger
2. Register in RaylsNode governance
3. Approve for public bridging
4. Wait for relayer to deploy public token

**Private → Public transfer:**

1. Lock tokens on Privacy Node Ledger
2. Wait for relayer processing
3. Verify mint on public chain

**Public → Private transfer:**

1. Burn tokens on public chain
2. Wait for relayer processing
3. Verify unlock on Privacy Node Ledger

---

## Writing Your Own Tests

### Test Structure Pattern

All e2e tests follow this structure:

```typescript
import hre from 'hardhat';
import { ethers } from 'ethers';
import { expect } from 'chai';
import {
  RaylsNode,
  CommitChain, // Legacy class name - refers to Private Network Hub
  Token,
  DEFAULT_TIMEOUT,
  GAS_LIMIT,
  PRIVACY_LEDGERS
} from '../utils/Constants';
import { shouldRegisterAndApproveToken } from '../utils/Utils';

describe('E2E Tests: My Feature', function () {
  // Setup nodes
  const privacyLedger: { [NODE: string]: RaylsNode } = {};

  for (const pl of PRIVACY_LEDGERS.filter(pl => pl == 'A' || pl == 'B')) {
    privacyLedger[pl] = new RaylsNode(pl, hre);
  }

  const commitChain = new CommitChain(hre);
  const token = new Token();

  // Initialize before tests
  before(async function () {
    this.timeout(DEFAULT_TIMEOUT);

    await commitChain.initialize();
    await privacyLedger.A.initialize();
    await privacyLedger.B.initialize();

    // Deploy contracts, authorize, etc.
  });

  // Test registration
  it('Should register and approve token',
    shouldRegisterAndApproveToken(commitChain, privacyLedger.A, token)
  ).timeout(DEFAULT_TIMEOUT);

  // Your test cases
  it('Should perform my operation', async function () {
    // 1. Setup: Capture state before
    const balanceBefore = await token.balanceOf(user);

    // 2. Execute: Perform operation
    await commitChain.wait(
      myContract.myOperation(params),
      'Performing my operation...'
    );

    // 3. Verify: Check state after
    await commitChain.waitUntil(
      async () => {
        const balanceAfter = await token.balanceOf(user);
        return balanceAfter === balanceBefore + expectedChange;
      },
      'Checking results...'
    );
  }).timeout(DEFAULT_TIMEOUT);
});
```

---

### Best Practices

**1. Always use timeouts:**

```typescript
// ✅ Good - specify timeout
it('Should complete operation', async function () {
  // test code
}).timeout(DEFAULT_TIMEOUT);

// ❌ Bad - no timeout (may hang forever)
it('Should complete operation', async function () {
  // test code
});
```

**2. Wait for cross-chain confirmations:**

```typescript
// ✅ Good - wait for cross-chain completion
await commitChain.waitUntil(
  async () => {
    const balance = await destToken.balanceOf(recipient);
    return balance === expectedAmount;
  },
  'Waiting for destination balance...'
);

// ❌ Bad - immediate check (cross-chain not complete)
const balance = await destToken.balanceOf(recipient);
expect(balance).to.equal(expectedAmount);  // Will fail!
```

**3. Verify balances on all chains:**

```typescript
// ✅ Good - check both source and destination
return balanceSource === before.source - amount &&
       balanceDest === before.dest + amount;

// ❌ Bad - only check one side
return balanceDest === before.dest + amount;
```

**4. Test both success and failure paths:**

```typescript
// ✅ Good - test both paths
it('Should succeed for valid input', async () => { /* ... */ });
it('Should revert for invalid input', async () => { /* ... */ });

// ❌ Bad - only test happy path
it('Should succeed for valid input', async () => { /* ... */ });
```

**5. Use proper gas limits:**

```typescript
// ✅ Good - specify gas limit
await token.teleport(recipient, amount, chainId, { gasLimit: GAS_LIMIT });

// ⚠️ Risky - auto gas estimation may fail
await token.teleport(recipient, amount, chainId);
```

---

### Common Test Patterns

**Pattern 1: Token deployment**

```typescript
const erc20Factory = await privacyLedger.A.getContractFactory('TokenExample');
await privacyLedger.A.deploy(
  erc20Factory,
  symbol,
  name,
  symbol,
  endpointAddress,
  raylsNodeEndpointAddress,
  userGovernanceAddress
);
```

**Pattern 2: Cross-chain transfer**

```typescript
await commitChain.wait(
  sourceToken.teleportAtomic(recipient, amount, destChainId),
  'Teleporting...'
);

await commitChain.waitUntil(
  async () => {
    const balance = await destToken.balanceOf(recipient);
    return balance === expectedAmount;
  },
  'Checking balance...'
);
```

**Pattern 3: Balance verification**

```typescript
const balanceBefore = {
  A: await tokenA.balanceOf(address),
  B: await tokenB.balanceOf(address)
};

// ... perform operation ...

await commitChain.waitUntil(
  async () => {
    const balanceA = await tokenA.balanceOf(address);
    const balanceB = await tokenB.balanceOf(address);

    return balanceA === balanceBefore.A - amount &&
           balanceB === balanceBefore.B + amount;
  },
  'Verifying balances...'
);
```

**Pattern 4: Revert testing**

```typescript
const balanceBefore = await token.balanceOf(sender);

// Execute operation that should fail
await commitChain.wait(
  token.teleportAtomic(invalidAddress, amount, chainId),
  'Teleporting to fail address...'
);

// Verify balance unchanged (automatic revert)
await commitChain.waitUntil(
  async () => {
    const balanceAfter = await token.balanceOf(sender);
    return balanceAfter === balanceBefore;  // No change
  },
  'Checking revert...'
);
```

---

## Test Utilities Reference

The test suite provides helper utilities in `hardhat/test/utils/`.

### Constants.ts

**Core classes:**

```typescript
import {
  RaylsNode,        // Privacy Node Ledger node abstraction
  CommitChain,      // Private Network Hub interaction (legacy class name)
  Token,            // Token configuration
  ERC721,           // NFT configuration
  ERC1155,          // Multi-token configuration
  DEFAULT_TIMEOUT,  // Test timeout (usually 120000ms)
  GAS_LIMIT,        // Transaction gas limit
  ZERO_ADDRESS,     // 0x0000...0000
  PRIVACY_LEDGERS   // ['A', 'B', 'C', 'D', 'E', 'F']
} from '../utils/Constants';
```

**Usage:**

```typescript
const privacyLedger = new RaylsNode('A', hre);
await privacyLedger.initialize();

const token = await privacyLedger.getContract('TokenExample');
```

---

### Utils.ts

**Helper functions:**

```typescript
import {
  shouldRegisterAndApproveToken,  // Register token on Private Network Hub
  shouldMintEnygma,                // Mint Enygma tokens
  shouldTransferEnygma,            // Transfer Enygma tokens
  shouldDepositEnygmaToZkdvp,     // Deposit to DVP pool
  shouldSwapNftForEnygma,          // Execute atomic swap
  pollCondition,                   // Poll until condition true
  encodeFunctionCall               // Encode contract call
} from '../utils/Utils';
```

**Example usage:**

```typescript
// Use helper for token registration
it('Should register token',
  shouldRegisterAndApproveToken(commitChain, privacyLedger.A, token)
).timeout(DEFAULT_TIMEOUT);

// Poll for condition
await pollCondition(
  async () => {
    const balance = await token.balanceOf(address);
    return balance > 0;
  },
  60000,  // timeout (ms)
  1000    // poll interval (ms)
);
```

---

### UtilsBackend.ts

**Backend integration helpers:**

```typescript
import {
  shouldOnboardAndApproveUser,              // Onboard user via API
  shouldRegisterAndApproveTokenInBackend,   // Register token via API
  shouldSendToPublicChainERC20,             // Send to public chain
  transferPrivateFundsAndAssert             // Private transfer helper
} from '../utils/UtilsBackend';
```

**Example usage:**

```typescript
// Onboard user through backend
it('Should onboard user',
  shouldOnboardAndApproveUser(userAddress, publicAddress)
).timeout(DEFAULT_TIMEOUT);
```

---

## Debugging Tests

### Common Test Failures

**1. Timeout errors:**

```
Error: Timeout of 120000ms exceeded
```

**Causes:**

- Relayer not running
- Node not responding
- Network congestion

**Solutions:**

- Check relayer: `docker ps | grep relayer`
- Check node: `curl http://localhost:8545`
- Increase timeout: `.timeout(240000)` // 4 minutes

---

**2. Balance mismatches:**

```
AssertionError: expected 0n to equal 30n
```

**Causes:**

- Transaction failed on destination
- Relayer didn't process message
- Wrong chain ID

**Solutions:**

- Check destination transaction logs
- Verify relayer processed event
- Confirm chain IDs match

---

**3. Connection errors:**

```
Error: could not detect network
```

**Causes:**

- Node not running
- Wrong RPC URL in .env
- Network unreachable

**Solutions:**

- Start nodes: `docker-compose up -d`
- Verify RPC URLs in `.env`
- Test connection: `curl -X POST http://localhost:8545`

---

**4. MongoDB errors (Enygma tests):**

```
MongoError: connect ECONNREFUSED
```

**Causes:**

- MongoDB not running
- Wrong connection string

**Solutions:**

- Start MongoDB: `docker start mongodb-nodeA`
- Verify `NODE_A_MONGO_CS` in `.env`
- Test connection: `mongo $NODE_A_MONGO_CS`

---

### Verbose Output

**Enable debug logging:**

```bash
# Full debug output
DEBUG=* npm run test:e2e-erc20

# Specific module debug
DEBUG=hardhat:* npm run test:e2e-erc20
```

---

### Checking Node Logs

**View Privacy Node Ledger logs:**

```bash
docker logs privacy-ledger-a --tail 100
docker logs privacy-ledger-b --tail 100
```

**View relayer logs:**

```bash
docker logs rayls-relayer-1 --tail 100 -f
```

**Look for:**

- Transaction confirmations
- Message processing
- Error messages
- Gas usage

---

## Summary

### Test Coverage Recap

**What's tested:**

- ✅ **Token operations**: ERC20, ERC721, ERC1155 cross-chain teleports
- ✅ **Privacy transfers**: Enygma with hidden balances and multi-destination
- ✅ **Atomic swaps**: DVP NFT-for-token exchanges with zero-knowledge proofs
- ✅ **Public bridging**: Private ↔ Public chain bidirectional flows
- ✅ **Infrastructure**: Messages, batches, freeze functionality
- ✅ **Security**: Revert handling, authorization, freeze controls
- ✅ **Performance**: Stress tests, concurrent operations, large batches

**What's guaranteed:**

- Cross-chain balance consistency
- Atomic teleport auto-revert on failure
- Privacy with Enygma commitments
- DVP atomic swap all-or-nothing
- Token freeze security
- Concurrent transfer safety
- Public/private bridge correctness

---

### Quick Reference Commands

```bash
# Run all e2e tests
npm run test:e2e

# Token tests
npm run test:e2e-erc20
npm run test:e2e-erc721
npm run test:e2e-erc1155

# Privacy tests
npm run test:e2e-enygma

# Atomic swap tests
npm run test:e2e-zkdvp

# Public chain tests
npm run test:e2e-public

# Run specific file
npx hardhat test hardhat/test/e2e/Erc20.ts

# Run tests matching pattern
npx hardhat test hardhat/test/e2e/Erc20.ts --grep "atomic"
```

---

### Testing Checklist for New Features

When adding new cross-chain features, ensure tests cover:

- [ ] Happy path (successful operation)
- [ ] Failure path (operation fails and reverts)
- [ ] Balance verification on all chains involved
- [ ] Timeout handling (reasonable timeout values)
- [ ] Edge cases (zero amounts, invalid addresses, etc.)
- [ ] Security (unauthorized access, frozen participants)
- [ ] Concurrent operations (if applicable)
- [ ] Backend integration (if API exposed)

---

### Related Documentation

**For protocol understanding:**

- [Transaction Lifecycle](transaction-lifecycle.md) - Timing expectations for tests
- [Token Standards](token-standards.md) - Teleport mechanisms being tested
- [Security](security.md) - Security scenarios to test

**For development:**

- [Endpoint Integration](endpoint-integration.md) - Custom contract testing
- [Best Practices](../reference/best-practices.md) - Production guidelines

---

### Testing under failure — resilience and chaos tests

Functional e2e tests cover what the system does when everything works. They cannot
cover what happens when the relayer crashes between a database write and a NATS ack,
or when a downstream call times out mid-flow — the timing windows are too small and
the failure paths are asynchronous.

Rayls has a runtime fault-injection facility that lets a test force a specific
internal failure (`crash`, `panic`, `sleep`, or typed `error`) at a named cutpoint
and assert the post-recovery state. See **[Fault Injection](../advanced/fault-injection.md)**
for the conceptual guide; the "Reference tests" section there links to three real
test files you can read in order to learn the patterns.

---

You now understand how to run, write, and debug e2e tests for Rayls cross-chain features. Use this knowledge to ensure your contracts work correctly across multiple chains with comprehensive test coverage.

Ready to see code examples? Check [Code Examples](code-examples.md) next.
