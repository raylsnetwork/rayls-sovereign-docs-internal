# Token Transfers

Learn how Atomic Teleport handles different token standards (ERC-20, ERC-721, ERC-1155) with standard-specific lock/unlock mechanisms.

## Overview

Atomic Teleport supports all major Ethereum token standards, each with tailored implementations that preserve the standard's semantics while providing atomicity guarantees.

**Supported Standards:**
- **ERC-20**: Fungible tokens (USDC, DAI, custom tokens)
- **ERC-721**: Non-fungible tokens (NFTs, unique assets)
- **ERC-1155**: Multi-tokens (semi-fungible, batch operations)

**Common Flow for All Standards:**

```
Origin Chain:
1. Burn token(s)
2. Create execute/unlock/revert payloads
3. Send to Private Network Hub

Destination Chain:
4. Mint to contract owner (temporary)
5. Lock for recipient
6. Wait for confirmation

Finalization:
7. Unlock and transfer to recipient (success)
   OR
8. Revert and restore to sender (failure)
```

## ERC-20 Fungible Tokens

### Lock/Unlock Implementation

**Internal State:**

```solidity
// Track locked amounts per address
mapping(address => uint256) private lockedAmount;

function _lock(address to, uint256 amount) internal {
    require(to != address(0), "Invalid recipient");
    require(amount > 0, "Amount must be greater than 0");

    lockedAmount[to] += amount;
}

function _unlock(address to, uint256 amount) internal returns (bool) {
    require(to != address(0), "Invalid recipient");
    uint256 amountToUnlock = lockedAmount[to];
    require(amount > 0 && amount <= amountToUnlock, "Not enough funds to unlock");

    lockedAmount[to] -= amount;
    return true;
}
```

### Complete ERC-20 Atomic Transfer

**Step 1: User Initiates Transfer**

```javascript
// Origin Chain: Privacy Node A
const token = new ethers.Contract(tokenAddress, erc20Abi, signer);

// Transfer 100 USDC to Bob on Privacy Node B
const tx = await token.teleportAtomic(
    "0xBob...",           // Recipient address
    ethers.parseUnits("100", 6),  // 100 USDC (6 decimals)
    chainIdB             // Destination chain ID
);

console.log("Teleport initiated:", tx.hash);
```

**Step 2: Contract Burns and Prepares Payloads**

```solidity
function teleportAtomic(address to, uint256 value, uint256 chainId) external {
    // 1. Burn from sender
    _burn(msg.sender, value);

    // 2. Prepare execute payload (destination receives)
    bytes memory executePayload = abi.encodeWithSignature(
        "receiveTeleportAtomic(address,uint256)",
        to,
        value
    );

    // 3. Prepare unlock payload (final transfer on destination)
    bytes memory unlockPayload = abi.encodeWithSignature(
        "unlock(address,uint256)",
        to,
        value
    );

    // 4. Prepare revert payloads (if failure)
    bytes memory revertSender = abi.encodeWithSignature(
        "revertTeleportMint(address,uint256)",
        msg.sender,
        value
    );

    bytes memory revertReceiver = abi.encodeWithSignature(
        "revertTeleportBurn(uint256)",
        value
    );

    // 5. Send via endpoint
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

**Step 3: Destination Chain Receives**

```solidity
function receiveTeleportAtomic(address to, uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint can call");

    // 1. Mint to contract owner (temporary custody)
    _mint(owner(), value);

    // 2. Lock for recipient (prevents spending until confirmed)
    if (to != owner()) {
        _lock(to, value);
    }

    emit TeleportReceived(to, value, block.timestamp);
}
```

**Step 4A: Success - Unlock**

```solidity
function unlock(address to, uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint can call");

    // 1. Unlock the amount
    bool success = _unlock(to, value);
    require(success, "Unlock failed");

    // 2. Transfer from owner to recipient
    _transfer(owner(), to, value);

    emit TeleportCompleted(to, value, block.timestamp);
}
```

**Result**: Bob receives 100 USDC on Privacy Node B.

**Step 4B: Failure - Revert**

```solidity
function revertTeleportMint(address to, uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint can call");

    // Restore asset to original sender on origin chain
    _mint(to, value);

    emit TeleportReverted(to, value, block.timestamp);
}
```

**Result**: Original sender gets 100 USDC back on Privacy Node A.

### Balance Checking

**User Balance vs Locked Amount:**

```javascript
// Check user's total balance
const totalBalance = await token.balanceOf(userAddress);
console.log("Total balance:", ethers.formatUnits(totalBalance, 6));

// Check locked amount (not spendable yet)
const locked = await token.lockedAmount(userAddress);
console.log("Locked amount:", ethers.formatUnits(locked, 6));

// Available balance = total - locked
const available = totalBalance - locked;
console.log("Available balance:", ethers.formatUnits(available, 6));
```

### Transfer Restrictions During Lock

```solidity
// Override transfer to prevent moving locked tokens
function _update(address from, address to, uint256 value) internal override {
    if (from != address(0)) {
        // Check if sender has enough unlocked balance
        uint256 balance = balanceOf(from);
        uint256 locked = lockedAmount[from];
        require(balance - locked >= value, "Insufficient unlocked balance");
    }

    super._update(from, to, value);
}
```

## ERC-721 Non-Fungible Tokens

### Lock/Unlock Implementation

**Internal State:**

```solidity
// Track locked tokens per owner
mapping(address => mapping(uint256 => bool)) private lockedTokens;

function _lock(address to, uint256 id) internal {
    require(to != address(0), "Invalid recipient");
    lockedTokens[to][id] = true;
}

function _unlock(address to, uint256 id) internal returns (bool) {
    require(to != address(0), "Invalid recipient");
    require(lockedTokens[to][id], "Token not locked");

    lockedTokens[to][id] = false;
    return true;
}
```

### Complete ERC-721 Atomic Transfer

**Step 1: User Initiates NFT Transfer**

```javascript
// Origin Chain: Privacy Node A
const nft = new ethers.Contract(nftAddress, erc721Abi, signer);

// Transfer NFT #42 to Bob on Privacy Node B
const tx = await nft.teleportAtomic(
    "0xBob...",           // Recipient address
    42,                  // Token ID
    chainIdB             // Destination chain ID
);

console.log("NFT teleport initiated:", tx.hash);
```

**Step 2: Contract Burns NFT and Prepares Payloads**

```solidity
function teleportAtomic(address to, uint256 tokenId, uint256 chainId) external {
    require(ownerOf(tokenId) == msg.sender, "Not token owner");

    // 1. Burn NFT from sender
    _burn(tokenId);

    // 2. Prepare execute payload
    bytes memory executePayload = abi.encodeWithSignature(
        "receiveTeleportAtomic(address,uint256)",
        to,
        tokenId
    );

    // 3. Prepare unlock payload
    bytes memory unlockPayload = abi.encodeWithSignature(
        "unlock(address,uint256)",
        to,
        tokenId
    );

    // 4. Prepare revert payloads
    bytes memory revertSender = abi.encodeWithSignature(
        "revertTeleportMint(address,uint256)",
        msg.sender,
        tokenId
    );

    bytes memory revertReceiver = abi.encodeWithSignature(
        "revertTeleportBurn(uint256)",
        tokenId
    );

    // 5. Send via endpoint
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

**Step 3: Destination Chain Receives NFT**

```solidity
function receiveTeleportAtomic(address to, uint256 tokenId) external {
    require(msg.sender == address(endpoint), "Only endpoint can call");

    // 1. Mint to contract owner (temporary custody)
    _mint(owner(), tokenId);

    // 2. Lock NFT for recipient
    if (to != owner()) {
        _lock(to, tokenId);
    }

    emit TeleportReceived(to, tokenId, block.timestamp);
}
```

**Step 4A: Success - Unlock NFT**

```solidity
function unlock(address to, uint256 tokenId) external {
    require(msg.sender == address(endpoint), "Only endpoint can call");

    // 1. Unlock the NFT
    bool success = _unlock(to, tokenId);
    require(success, "Unlock failed");

    // 2. Transfer from owner to recipient
    _transfer(owner(), to, tokenId);

    emit TeleportCompleted(to, tokenId, block.timestamp);
}
```

**Result**: Bob owns NFT #42 on Privacy Node B.

**Step 4B: Failure - Revert NFT**

```solidity
function revertTeleportMint(address to, uint256 tokenId) external {
    require(msg.sender == address(endpoint), "Only endpoint can call");

    // Restore NFT to original owner on origin chain
    _mint(to, tokenId);

    emit TeleportReverted(to, tokenId, block.timestamp);
}
```

**Result**: Original owner gets NFT #42 back on Privacy Node A.

### Transfer Restrictions for Locked NFTs

```solidity
// Override transfer to prevent moving locked NFTs
function _update(address to, uint256 tokenId, address auth)
    internal
    override
    returns (address)
{
    address from = _ownerOf(tokenId);

    if (from != address(0)) {
        // Prevent transfer of locked NFTs
        require(!lockedTokens[from][tokenId], "Token is locked");
    }

    return super._update(to, tokenId, auth);
}
```

### Checking NFT Lock Status

```javascript
// Check if specific NFT is locked
const isLocked = await nft.lockedTokens(ownerAddress, tokenId);
console.log(`NFT #${tokenId} locked:`, isLocked);

// Check ownership
const owner = await nft.ownerOf(tokenId);
console.log(`NFT #${tokenId} owner:`, owner);
```

## ERC-1155 Multi-Tokens

### Lock/Unlock Implementation

**Internal State:**

```solidity
// Track locked amounts per address per token ID
mapping(address => mapping(uint256 => uint256)) private lockedAmount;

function _lock(address to, uint256 id, uint256 amount) internal {
    require(to != address(0), "Invalid recipient");
    require(amount > 0, "Amount must be greater than 0");

    lockedAmount[to][id] += amount;
}

function _unlock(address to, uint256 id, uint256 amount) internal returns (bool) {
    require(to != address(0), "Invalid recipient");
    uint256 amountToUnlock = lockedAmount[to][id];
    require(amount > 0 && amount <= amountToUnlock, "Not enough funds to unlock");

    lockedAmount[to][id] -= amount;
    return true;
}
```

### Complete ERC-1155 Atomic Transfer

**Step 1: User Initiates Multi-Token Transfer**

```javascript
// Origin Chain: Privacy Node A
const multiToken = new ethers.Contract(tokenAddress, erc1155Abi, signer);

// Transfer 50 units of token ID 100 to Bob on Privacy Node B
const tx = await multiToken.teleportAtomic(
    "0xBob...",           // Recipient address
    100,                 // Token ID
    50,                  // Amount
    chainIdB             // Destination chain ID
);

console.log("Multi-token teleport initiated:", tx.hash);
```

**Step 2: Contract Burns and Prepares Payloads**

```solidity
function teleportAtomic(
    address to,
    uint256 id,
    uint256 amount,
    uint256 chainId
) external {
    // 1. Burn from sender
    _burn(msg.sender, id, amount);

    // 2. Prepare execute payload
    bytes memory executePayload = abi.encodeWithSignature(
        "receiveTeleportAtomic(address,uint256,uint256)",
        to,
        id,
        amount
    );

    // 3. Prepare unlock payload
    bytes memory unlockPayload = abi.encodeWithSignature(
        "unlock(address,uint256,uint256)",
        to,
        id,
        amount
    );

    // 4. Prepare revert payloads
    bytes memory revertSender = abi.encodeWithSignature(
        "revertTeleportMint(address,uint256,uint256)",
        msg.sender,
        id,
        amount
    );

    bytes memory revertReceiver = abi.encodeWithSignature(
        "revertTeleportBurn(uint256,uint256)",
        id,
        amount
    );

    // 5. Send via endpoint
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

**Step 3: Destination Chain Receives**

```solidity
function receiveTeleportAtomic(address to, uint256 id, uint256 amount) external {
    require(msg.sender == address(endpoint), "Only endpoint can call");

    // 1. Mint to contract owner (temporary custody)
    _mint(owner(), id, amount, "");

    // 2. Lock for recipient
    if (to != owner()) {
        _lock(to, id, amount);
    }

    emit TeleportReceived(to, id, amount, block.timestamp);
}
```

**Step 4A: Success - Unlock**

```solidity
function unlock(address to, uint256 id, uint256 amount) external {
    require(msg.sender == address(endpoint), "Only endpoint can call");

    // 1. Unlock the amount
    bool success = _unlock(to, id, amount);
    require(success, "Unlock failed");

    // 2. Transfer from owner to recipient
    _safeTransferFrom(owner(), to, id, amount, "");

    emit TeleportCompleted(to, id, amount, block.timestamp);
}
```

**Result**: Bob receives 50 units of token ID 100 on Privacy Node B.

**Step 4B: Failure - Revert**

```solidity
function revertTeleportMint(address to, uint256 id, uint256 amount) external {
    require(msg.sender == address(endpoint), "Only endpoint can call");

    // Restore asset to original sender on origin chain
    _mint(to, id, amount, "");

    emit TeleportReverted(to, id, amount, block.timestamp);
}
```

**Result**: Original sender gets 50 units of token ID 100 back on Privacy Node A.

### Batch Transfers (ERC-1155 Specific)

**Batch Teleport Multiple Token IDs:**

```javascript
// Transfer multiple token types in one atomic operation
const tx = await multiToken.batchTeleportAtomic(
    "0xBob...",           // Recipient
    [100, 200, 300],     // Token IDs
    [50, 25, 10],        // Amounts
    chainIdB             // Destination chain ID
);
```

**Contract Implementation:**

```solidity
function batchTeleportAtomic(
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    uint256 chainId
) external {
    require(ids.length == amounts.length, "Length mismatch");

    // 1. Burn all tokens
    _burnBatch(msg.sender, ids, amounts);

    // 2. Prepare batch execute payload
    bytes memory executePayload = abi.encodeWithSignature(
        "receiveBatchTeleportAtomic(address,uint256[],uint256[])",
        to,
        ids,
        amounts
    );

    // 3. Prepare batch unlock payload
    bytes memory unlockPayload = abi.encodeWithSignature(
        "batchUnlock(address,uint256[],uint256[])",
        to,
        ids,
        amounts
    );

    // 4. Prepare revert payloads
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

    // 5. Send via endpoint
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

### Checking Multi-Token Lock Status

```javascript
// Check locked amount for specific token ID
const locked = await multiToken.lockedAmount(ownerAddress, tokenId);
console.log(`Token ID ${tokenId} locked:`, locked.toString());

// Check total balance
const balance = await multiToken.balanceOf(ownerAddress, tokenId);
console.log(`Token ID ${tokenId} total:`, balance.toString());

// Available = total - locked
const available = balance - locked;
console.log(`Token ID ${tokenId} available:`, available.toString());
```

## Gas Cost Comparison

### Estimated Gas Costs

**Single Transfers:**

```
ERC-20 Atomic Teleport:     ~180-220k gas
ERC-721 Atomic Teleport:    ~160-200k gas
ERC-1155 Atomic Teleport:   ~200-250k gas
```

**Why Different?**
- ERC-20: Simple amount tracking
- ERC-721: Token ID validation, ownership checks
- ERC-1155: Token ID + amount tracking, more complex state

### Optimization Tips

**1. Use Batch Operations (ERC-1155)**

```javascript
// ❌ Inefficient: 3 separate transactions
await multiToken.teleportAtomic(bob, 100, 50, chainIdB);  // ~220k gas
await multiToken.teleportAtomic(bob, 200, 25, chainIdB);  // ~220k gas
await multiToken.teleportAtomic(bob, 300, 10, chainIdB);  // ~220k gas
// Total: ~660k gas

// ✅ Efficient: 1 batch transaction
await multiToken.batchTeleportAtomic(
    bob,
    [100, 200, 300],
    [50, 25, 10],
    chainIdB
);
// Total: ~350k gas (47% savings)
```

**2. Approve Once, Transfer Many**

```javascript
// Set approval for contract to manage your tokens
await token.setApprovalForAll(endpoint.address, true);

// Now you can teleport without additional approvals
await token.teleportAtomic(bob, amount, chainIdB);
```

**3. Monitor Gas Prices**

```javascript
// Wait for low gas prices before initiating
const gasPrice = await provider.getFeeData();
console.log("Current gas price:", gasPrice.gasPrice);

if (gasPrice.gasPrice < ethers.parseUnits("20", "gwei")) {
    // Good time to teleport
    await token.teleportAtomic(bob, amount, chainIdB);
}
```

## Common Patterns

### Pattern 1: Cross-Chain Marketplace Sale

**Scenario**: Sell NFT on one chain, receive payment on another

```javascript
async function crossChainNFTSale(
    nftContract,
    tokenId,
    paymentToken,
    price,
    buyer,
    buyerChain,
    sellerChain
) {
    // 1. Seller: Teleport NFT to buyer's chain
    await nftContract.teleportAtomic(buyer, tokenId, buyerChain);

    // 2. Buyer: Teleport payment to seller's chain
    await paymentToken.teleportAtomic(seller, price, sellerChain);

    // Both operations are atomic - either both succeed or both revert
}
```

### Pattern 2: Multi-Asset Migration

**Scenario**: Move entire portfolio between chains

```javascript
async function migratePortfolio(assets, destChain) {
    for (const asset of assets) {
        if (asset.standard === 'ERC20') {
            await asset.contract.teleportAtomic(
                myAddress,
                asset.amount,
                destChain
            );
        } else if (asset.standard === 'ERC721') {
            await asset.contract.teleportAtomic(
                myAddress,
                asset.tokenId,
                destChain
            );
        } else if (asset.standard === 'ERC1155') {
            await asset.contract.teleportAtomic(
                myAddress,
                asset.tokenId,
                asset.amount,
                destChain
            );
        }
    }
}
```

### Pattern 3: Conditional Transfer

**Scenario**: Transfer only if destination conditions are met

```javascript
// Custom validation on destination chain
function receiveTeleportAtomic(address to, uint256 value) external {
    require(msg.sender == address(endpoint), "Only endpoint");

    // Custom validation: only accept if recipient is whitelisted
    require(isWhitelisted(to), "Recipient not whitelisted");

    // If this fails, automatic revert triggers on origin chain
    _mint(owner(), value);
    if (to != owner()) {
        _lock(to, value);
    }
}
```

## Security Considerations

### 1. Reentrancy Protection

```solidity
bool private processing;

modifier nonReentrant() {
    require(!processing, "Reentrant call");
    processing = true;
    _;
    processing = false;
}

function teleportAtomic(...) external nonReentrant {
    // Protected from reentrancy
}
```

### 2. Amount Validation

```solidity
function teleportAtomic(address to, uint256 value, uint256 chainId) external {
    require(value > 0, "Amount must be greater than 0");
    require(to != address(0), "Invalid recipient");
    require(balanceOf(msg.sender) >= value, "Insufficient balance");

    // Proceed with teleport
}
```

### 3. Resource ID Registration

```solidity
function sendTeleport(...) internal {
    bytes32 resourceId = endpoint.getResourceId(address(this));
    require(resourceId != bytes32(0), "Token not registered");

    // Only registered tokens can teleport
}
```

### 4. Chain ID Validation

```solidity
function teleportAtomic(address to, uint256 value, uint256 chainId) external {
    uint256 currentChain = endpoint.getChainId();
    require(chainId != currentChain, "Cannot send to same chain");

    // Proceed with teleport
}
```

## Troubleshooting

### Issue 1: Transfer Fails with "Insufficient unlocked balance"

**Cause**: Trying to transfer locked tokens

**Solution**:
```javascript
// Check locked amount before transfer
const locked = await token.lockedAmount(myAddress);
const balance = await token.balanceOf(myAddress);
const available = balance - locked;

console.log(`Available: ${available}, Trying to send: ${amount}`);

if (available >= amount) {
    await token.transfer(recipient, amount);
}
```

### Issue 2: NFT Transfer Fails with "Token is locked"

**Cause**: Trying to transfer NFT that's pending confirmation

**Solution**:
```javascript
// Check if NFT is locked before transfer
const isLocked = await nft.lockedTokens(myAddress, tokenId);

if (!isLocked) {
    await nft.transferFrom(myAddress, recipient, tokenId);
} else {
    console.log("NFT is locked, waiting for teleport confirmation");
}
```

### Issue 3: Unlock Fails with "Not enough funds to unlock"

**Cause**: Mismatch between locked amount and unlock amount

**Solution**: This should never happen in normal operation. If it does, it indicates:
- Bug in lock/unlock logic
- Direct manipulation of locked state (should be impossible)
- Check contract implementation

## Next Steps

- **[Batch Processing](batch-processing.md)** - Optimize multiple transfers
- **[Atomic Reverts](atomic-reverts.md)** - Deep dive on rollback mechanisms
- **[Cross-Chain Messaging](crosschain-messaging.md)** - Message lifecycle details
- **[Smart Contracts Integration](../../../build/intermediate/endpoint-integration.md)** - Building with Atomic Teleport

## Additional Resources

- [ERC-20 Standard](https://eips.ethereum.org/EIPS/eip-20)
- [ERC-721 Standard](https://eips.ethereum.org/EIPS/eip-721)
- [ERC-1155 Standard](https://eips.ethereum.org/EIPS/eip-1155)
- [Atomic Teleport Overview](overview.md)
