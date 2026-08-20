# Building with Enygma Privacy Tokens

Build applications with privacy-preserving token transfers using Enygma on Rayls.

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [First Transaction](../beginner/first-transaction.md) tutorial
- [ ] Rayls development environment running ([Docker Setup](../beginner/docker-setup.md))
- [ ] Basic understanding of [Token Standards](../intermediate/token-standards.md)
- [ ] Familiarity with Enygma concepts ([Learn: Enygma Overview](../../learn/protocols/enygma/index.md))

**Key terms:** This guide uses cryptographic concepts explained in the [Enygma Glossary](../../learn/protocols/enygma/glossary.md).

## Overview

Enygma enables confidential cross-chain token transfers where amounts remain hidden from observers. This guide covers:

- Deploying Enygma tokens using Hardhat tasks
- Creating custom tokens by extending `RaylsEnygmaHandler`
- Executing cross-chain transfers with privacy
- Testing your integration

### Why Privacy Tokens?

Standard token transfers expose amounts publicly on-chain. Anyone can see "Alice sent 1000 tokens to Bob." In regulated financial environments, this transparency creates problems:

- **Competitive intelligence**: Competitors can track your transaction volumes
- **Front-running**: Observers can exploit knowledge of large pending transfers
- **Regulatory requirements**: Some jurisdictions require transaction confidentiality

Enygma solves this using [Pedersen commitments](../../learn/protocols/enygma/glossary.md#pedersen-commitment) - cryptographic structures that hide amounts while still proving transfers are valid. The system mathematically guarantees that balances are correct without revealing what those balances are.

**What's hidden:** Transfer amounts, account balances
**What's visible:** That a transfer occurred, sender/recipient addresses (within the batch)

---

## Quick Start

### 1. Deploy an Enygma Token

```bash
npx hardhat tokens:enygma:deploy \
  --pl A \
  --symbol MPT \
  --name "My Private Token" \
  --network pl-a
```

### 2. Mint Tokens

```bash
npx hardhat tokens:enygma:mint \
  --pl A \
  --symbol MPT \
  --to 0xYourAddress \
  --amount 1000 \
  --network pl-a
```

### 3. Cross-Chain Transfer

```bash
npx hardhat tokens:enygma:send-cross \
  --pl A \
  --symbol MPT \
  --destinations 0xRecipientAddress \
  --amounts 100 \
  --chain-ids 1002 \
  --network pl-a
```

---

## Hardhat Tasks Reference

### Token Management

| Task | Description | Key Parameters |
|------|-------------|----------------|
| `tokens:enygma:deploy` | Deploy new Enygma token | `--pl`, `--symbol`, `--name` |
| `tokens:enygma:mint` | Mint tokens to address | `--pl`, `--symbol`, `--to`, `--amount` |
| `tokens:enygma:burn` | Burn tokens | `--pl`, `--symbol`, `--amount` |
| `tokens:enygma:get-balance` | Get token balance | `--pl`, `--symbol`, `--address` |
| `tokens:enygma:check-resource-id` | Verify token resource ID | `--pl`, `--symbol` |

### Cross-Chain Transfers

| Task | Description | Key Parameters |
|------|-------------|----------------|
| `tokens:enygma:send-cross` | Transfer to other PN | `--pl`, `--symbol`, `--destinations`, `--amounts`, `--chain-ids` |
| `tokens:enygma:send-cross-linear` | Simplified single transfer | Same as above |
| `tokens:enygma:send-cross-from` | Transfer on behalf of user | `--from`, `--to`, `--amount`, `--callables-path` |

### Example: Transfer with Callable

```bash
# Create callables.json
echo '[{
  "resourceId": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "contractAddress": "0xTargetContract",
  "payload": "0xEncodedFunctionCall"
}]' > callables.json

# Execute transfer with callback
npx hardhat tokens:enygma:send-cross-from \
  --pl A \
  --symbol MPT \
  --from 0xSender \
  --to 0xRecipient \
  --amount 100 \
  --callables-path ./callables.json \
  --network pl-a
```

---

## Creating a Custom Token

### Extend RaylsEnygmaHandler

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RaylsEnygmaHandler} from "@rayls/protocol-sdk/tokens/RaylsEnygmaHandler.sol";
import {SharedObjects} from "@rayls/protocol-sdk/libraries/SharedObjects.sol";

contract MyPrivateToken is RaylsEnygmaHandler {
    uint256 public maxTransferAmount = 10000 * 10**18;

    constructor(
        address _endpoint,
        address _owner
    ) RaylsEnygmaHandler(
        "My Private Token",  // name
        "MPT",               // symbol
        _endpoint,           // Rayls endpoint
        _owner,              // owner address
        18,                  // decimals
        false                // isCustom
    ) {}

    // Custom mint with validation
    function mint(address _to, uint256 _value) public override onlyOwner {
        require(_value <= maxTransferAmount, "Exceeds max amount");
        super.mint(_to, _value);
    }

    // Custom receive logic
    function crossMint(
        address _to,
        uint256 _value,
        bytes32 _referenceId,
        SharedObjects.EnygmaCrossTransferCallable[] calldata _callables
    ) public override {
        require(_value <= maxTransferAmount, "Exceeds max amount");
        super.crossMint(_to, _value, _referenceId, _callables);

        emit TokensReceived(_to, _value, _referenceId);
    }

    event TokensReceived(address indexed to, uint256 value, bytes32 referenceId);
}
```

### Deploy Script

```typescript
import { ethers } from "hardhat";

async function main() {
    const [deployer] = await ethers.getSigners();
    const endpointAddress = process.env.ENDPOINT_ADDRESS!;

    const MyPrivateToken = await ethers.getContractFactory("MyPrivateToken");
    const token = await MyPrivateToken.deploy(endpointAddress, deployer.address);
    await token.waitForDeployment();

    console.log("Token deployed:", await token.getAddress());
    console.log("Resource ID:", await token.resourceId());

    // Authorize for endpoint access
    const endpoint = await ethers.getContractAt("EndpointV1", endpointAddress);
    await endpoint.addAuthorizedAddresses([await token.getAddress()]);
    console.log("Token authorized for endpoint");
}

main().catch(console.error);
```

---

## Understanding RaylsEnygmaHandler

Before customizing, understand what the base contract provides.

### Constructor Parameters

```solidity
constructor(
    string memory _name,      // Token name (e.g., "My Private Token")
    string memory _symbol,    // Token symbol (e.g., "MPT")
    address _endpoint,        // Rayls endpoint address
    address _owner,           // Initial owner (can mint/burn)
    uint8 _decimals,          // Decimal places (typically 18)
    bool _isCustom            // Custom implementation flag
)
```

| Parameter | Purpose |
|-----------|---------|
| `_name` | Display name for the token |
| `_symbol` | Ticker symbol |
| `_endpoint` | Rayls endpoint contract for cross-chain messaging |
| `_owner` | Address with mint/burn privileges |
| `_decimals` | Token precision (18 = standard) |
| `_isCustom` | **Important:** Set `false` for standard tokens, `true` for custom logic that differs from protocol defaults. Affects how the Hub registers your token. |

### Inheritance Chain

```
RaylsEnygmaHandler
├── ERC20           → Standard token (transfer, balanceOf, approve, etc.)
├── RaylsApp        → Cross-chain messaging (_raylsSend, receiveMethod)
├── Ownable         → Owner-based access control
└── Initializable   → Proxy/upgradeable pattern support
```

**What you get automatically:**
- Full ERC20 functionality for same-chain transfers
- Cross-chain transfer infrastructure
- Reference ID tracking for transfer status
- DVP integration hooks

### Key Functions to Override

| Function | Default Behavior | Override When |
|----------|------------------|---------------|
| `mint(address, uint256)` | Mints tokens, emits event | Add validation, limits, or custom logic |
| `burn(address, uint256)` | Burns tokens, emits event | Add validation or restrictions |
| `crossMint(address, uint256, bytes32, callables[])` | Receives cross-chain transfer, executes callables | Add receive-side validation or events |
| `crossTransfer(...)` | Burns locally, initiates cross-chain send | Add send-side validation or limits |

**Example: Adding transfer limits**
```solidity
function crossTransfer(
    address[] memory _to,
    uint256[] memory _value,
    uint256[] memory _toChainId,
    SharedObjects.EnygmaCrossTransferCallable[][] memory _callables
) public virtual override {
    for (uint i = 0; i < _value.length; i++) {
        require(_value[i] <= maxTransferAmount, "Exceeds limit");
    }
    super.crossTransfer(_to, _value, _toChainId, _callables);
}
```

### Access Control

| Modifier | Who Can Call | Applied To |
|----------|--------------|------------|
| `onlyOwner` | Contract owner only | `mint()`, `burn()` |
| `receiveMethod` | Rayls endpoint executor only | `crossMint()`, receive handlers |
| `onlyFromCommitChain` | Calls originating from Hub only | `activateToken()` |

**Note:** `receiveMethod` functions are called by the Relayer through the Endpoint - you cannot call them directly.

### Reference ID Status

Track cross-chain transfer lifecycle:

```solidity
enum ReferenceIdStatus {
    NOSTATUS,          // 0 - Not tracked
    SENT,              // 1 - Transfer initiated (tokens burned)
    RECEIVED,          // 2 - Transfer completed (tokens minted)
    DEPOSITED,         // 3 - Deposited to DVP
    WITHDRAW_ASKED,    // 4 - DVP withdrawal requested
    WITHDRAW_RECEIVED  // 5 - DVP withdrawal completed
}

// Check status
mapping(bytes32 => uint256) public referenceIdsStatus;
```

---

## Cross-Chain Transfers

Cross-chain transfers in Enygma work differently from standard tokens. When you call `crossTransfer()`:

1. Tokens are **burned** on the source chain
2. The relayer picks up the event and **batches** it with other transfers
3. A **zero-knowledge proof** is generated proving the transfer is valid
4. The proof is verified on the Hub
5. Tokens are **minted** on the destination chain

This process takes 20-60 seconds depending on batching and proof generation time.

### Simple Transfer

```typescript
// Transfer 100 tokens to recipient on chain 1002
// Tokens are burned locally, then minted on destination after proof verification
const tx = await token.crossTransfer(
    [recipientAddress],           // recipients array
    [ethers.parseEther("100")],   // amounts array (must match recipients length)
    [1002n],                      // destination chain IDs array
    [[]]                          // callables array (empty = no callbacks)
);
await tx.wait();
// Note: tx.wait() only confirms the burn - minting happens async after proof
```

### Linear Transfer (Simplified)

For single-recipient transfers, `linearCrossTransfer` provides a simpler API that doesn't require arrays:

```typescript
// Single recipient, single amount - simpler than crossTransfer for 1-to-1 transfers
const tx = await token.linearCrossTransfer(
    recipientAddress,             // single recipient (not array)
    ethers.parseEther("100"),     // single amount (not array)
    1002n,                        // destination chain
    ethers.ZeroHash,              // callable resourceId (bytes32(0) = none)
    ethers.ZeroAddress,           // callable contract (address(0) = none)
    "0x"                          // callable payload (empty = none)
);
```

**When to use which:**
- `crossTransfer`: Multiple recipients, multiple destinations, or complex callables
- `linearCrossTransfer`: Simple 1-to-1 transfers with optional single callable

### Multi-Destination Transfer (1-to-N)

```typescript
// Send to multiple recipients on different chains
const tx = await token.crossTransfer(
    [recipient1, recipient2, recipient3],
    [ethers.parseEther("50"), ethers.parseEther("30"), ethers.parseEther("20")],
    [1002n, 1003n, 1004n],
    [[], [], []]
);
```

### Transfer with Callback (Callables)

Callables let you execute contract functions on the destination chain when tokens arrive. This enables patterns like:

- Automatic staking after transfer
- Triggering a swap on arrival
- Notifying a contract that payment was received
- Chaining multiple operations atomically

Each transfer supports up to **5 callables**. They execute in order after tokens are minted.

```typescript
// Encode the callback function that will run on destination
const targetInterface = new ethers.Interface([
    "function onTokenReceived(address sender, uint256 amount)"
]);
const payload = targetInterface.encodeFunctionData("onTokenReceived", [
    senderAddress,
    ethers.parseEther("100")
]);

// Create callable - specify EITHER resourceId OR contractAddress, not both
const callable = {
    resourceId: ethers.ZeroHash,        // Use this to resolve address via endpoint
    contractAddress: targetContractAddress,  // Or specify address directly
    payload: payload                    // Encoded function call
};

// Execute transfer - callable runs after mint succeeds
const tx = await token.crossTransfer(
    [recipientAddress],
    [ethers.parseEther("100")],
    [1002n],
    [[callable]]  // Up to 5 callables per transfer
);
```

**Important:** If any callable fails, the entire `crossMint` reverts - tokens are not minted. Design callables to handle edge cases gracefully.

---

## Receiving Transfers

When tokens arrive from another chain, `crossMint` is called:

```solidity
function crossMint(
    address _to,
    uint256 _value,
    bytes32 _referenceId,
    SharedObjects.EnygmaCrossTransferCallable[] calldata _callables
) public virtual {
    // 1. Update reference status
    referenceIdsStatus[_referenceId] = uint256(ReferenceIdStatus.RECEIVED);

    // 2. Mint tokens
    _mint(_to, _value);

    // 3. Execute callables
    for (uint256 i = 0; i < _callables.length; ++i) {
        address contractAddress = _callables[i].contractAddress;
        if (_callables[i].resourceId != bytes32('')) {
            contractAddress = endpoint.getAddressByResourceId(_callables[i].resourceId);
        }

        if (contractAddress != address(0)) {
            (bool success, ) = contractAddress.call(_callables[i].payload);
            require(success, "Callable execution failed");
        }
    }
}
```

### Track Transfer Status

```typescript
// Reference ID statuses
enum ReferenceIdStatus {
    NOSTATUS = 0,
    SENT = 1,
    RECEIVED = 2,
    DEPOSITED = 3,
    WITHDRAW_ASKED = 4,
    WITHDRAW_RECEIVED = 5
}

// Check status
const status = await token.referenceIdsStatus(referenceId);
console.log("Status:", status); // 1 = SENT, 2 = RECEIVED
```

---

## Testing

### Test Pattern: Basic Transfer

```typescript
import { RaylsNode, CommitChain, Token } from "@rayls/test-utils";

describe("Enygma Transfer", function () {
    const privacyLedgerA = new RaylsNode("A", hre);
    const privacyLedgerB = new RaylsNode("B", hre);
    const commitChain = new CommitChain(hre);
    const enygma = new Token();

    it("should transfer between PLs", async function () {
        // 1. Register and approve token
        await shouldRegisterAndApproveToken(commitChain, privacyLedgerA, enygma);

        // 2. Mint on source PL
        await shouldMintEnygma(1000, commitChain, privacyLedgerA, enygma);

        // 3. Transfer to destination PL
        const transfer = {
            destinationAddresses: [recipientAddress],
            amounts: [500],
            destinationChainIds: [privacyLedgerB.chainId],
            callables: [[]]
        };
        await shouldTransferEnygma(transfer, 1, expectedBalances,
            commitChain, privacyLedgerA, [privacyLedgerB], enygma);

        // 4. Verify balance on destination
        const balance = await token.balanceOf(recipientAddress);
        expect(balance).to.equal(ethers.parseEther("500"));
    });
});
```

### Test Utility Functions

```typescript
// From hardhat/test/utils/Utils.ts

// Mint tokens
shouldMintEnygma(amount, commitChain, privacyLedger, token)

// Register token
shouldRegisterAndApproveToken(commitChain, privacyLedger, token)

// Transfer with verification
shouldTransferEnygma(transfer, transferNumber, expectedBalances,
                     commitChain, source, destinations, token)

// Verify MongoDB balance (if enabled)
checkMongoDbBalance(expectedBalance, commitChain, privacyLedger, token)
```

---

## Reference

### Performance

| Operation | Latency | Notes |
|-----------|---------|-------|
| Mint | ~5 sec | Block confirmation |
| Cross-chain transfer | 20-60 sec | Batching + proof generation |
| Batch ([k=2](../../learn/protocols/enygma/glossary.md#k-anonymity)) | ~20 sec | 2 participants |
| Batch ([k=6](../../learn/protocols/enygma/glossary.md#k-anonymity)) | ~40 sec | 6 participants |

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `"Use another function to transfer to same ChainId"` | Targeting same chain | Use regular ERC20 transfer for same-chain |
| `"Array lengths must match"` | Mismatched arrays | Ensure `_to`, `_value`, `_toChainId`, `_callables` have same length |
| `"Protocol doesn't support more than 5 callables"` | Too many callables | Limit to 5 per transfer |
| `"Cannot specify both resourceId and contractAddress"` | Callable config error | Use one or the other, not both |
| `"Callable contract address is not a contract"` | Invalid callable target | Verify contract is deployed at address |

---

## Troubleshooting

### Transfer stuck in SENT status

**Symptoms:** Transfer initiated but never arrives at destination

**Possible causes:**
1. Relayer not running or not connected to your PN
2. Proof generation failing
3. Hub verification failing

**Debug steps:**
```bash
# Check relayer logs
docker compose logs relayer-a | grep -i error

# Verify proof API is healthy
curl http://localhost:3003/health

# Check Hub for pending transactions
npx hardhat enygma:check-pending --network commit-chain
```

### Proof generation timeout

**Symptoms:** Transfer takes >2 minutes, eventually fails

**Cause:** Proof API overloaded or circuit files missing

**Solution:**
```bash
# Restart proof service
docker compose restart proofs-api

# Verify circuits are loaded (should show files)
docker compose exec proofs-api ls -la /app/circuits/
```

### Balance mismatch after transfer

**Symptoms:** Sender shows wrong balance after transfer

**Cause:** Usually a display issue - actual balance is in commitments

**Note:** Enygma balances are stored as cryptographic commitments. The "balance" you see locally may differ from the committed balance on the Hub. Trust the commitment verification, not local state.

### Reference ID Flow

```
crossTransfer() called  →  SENT (1)
         ↓
Proof generated & verified
         ↓
crossMint() called      →  RECEIVED (2)
```

---

## Next Steps

- [DVP Atomic Swaps](dvp-atomic-swaps.md) - Exchange tokens for NFTs
- [Learn: Cross-Chain Transfers](../../learn/protocols/enygma/cross-chain-transfers.md) - Transfer lifecycle details
- [Learn: Enygma Glossary](../../learn/protocols/enygma/glossary.md) - Term definitions
