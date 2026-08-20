# Public Chain Bridge

A developer guide for creating tokens on the Rayls Privacy Node Ledger that can be transferred to and from a public blockchain.

---

## Prerequisites

- [ ] Completed the [First Transaction](../beginner/first-transaction.md) tutorial
- [ ] Read the [Public Chain Integration](../../learn/components/public-chain/index.md) overview
- [ ] Rayls development environment running

!!! info "You Write One Contract"
    You write a token contract on the **Privacy Node Ledger** by inheriting from a handler (`RaylsErc20Handler`, `RaylsErc721Handler`, or `RaylsErc1155Handler`). You deploy it, register it, and activate it. The system automatically deploys a mirror contract on the public chain and wires everything up.

    **You only write one contract.** The public chain side is handled for you.

---

## Quick Start — Your First Bridgeable ERC-20

### Step 1: Write the Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "rayls-protocol-sdk/tokens/RaylsErc20Handler.sol";

contract MyToken is RaylsErc20Handler {
    constructor(
        address _endpoint,
        address _raylsNodeEndpoint,
        address _userGovernance
    )
        RaylsErc20Handler(
            "My Token",           // name
            "MTK",                // symbol
            _endpoint,            // Rayls endpoint on the Privacy Node Ledger
            _raylsNodeEndpoint,   // RNEndpointV1 on the Privacy Node Ledger
            _userGovernance,      // RNUserGovernanceV1 on the Privacy Node Ledger
            msg.sender,           // owner
            false                 // isCustom (false = standard token)
        )
    {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }
}
```

That's the entire contract. The handler gives you bridging, minting, burning, locking, and cross-chain receive methods out of the box.

### Step 2: Deploy on the Privacy Node Ledger

Deploy the contract to your Privacy Node Ledger using Hardhat, passing the three infrastructure addresses that are already deployed on the chain.

### Step 3: Register and Authorize the Token

Register the token on the Privacy Node's PN Token Registry, then have the PN operator authorize it:

```bash
# Register on the PN Token Registry (single argument, no storage slot)
npx hardhat tokens:register --pl A --token-address <TOKEN_ADDRESS>

# PN operator authorizes the token locally
npx hardhat tokens:approve-pn --symbol MTK
```

`registerToken(tokenAddress)` reads the token's name / symbol / totalSupply on-chain and sets `privacyNodeStatus = WAITING_APPROVAL`. After `updatePrivacyNodeStatus(tokenAddress, AUTHORIZED)`, the token is operational locally and can be submitted to a public chain. See the [PN Token Registry](../../learn/components/smart-contracts/pn-token-registry.md) page for the full three-status model.

### Step 4: Submit the Token to the Public Chain

To make the token bridgeable, submit it to the public chain. This requires the token to be PN `AUTHORIZED`:

```bash
npx hardhat submitTokenToPublicChain --symbol MTK
```

Under the hood this calls `PNTokenRegistryV1.submitToPublicChain(tokenAddress)`, which sets `publicChainStatus = PENDING_DEPLOYMENT`.

!!! note "What Happens Automatically"
    After `submitToPublicChain`, the following happens without any developer action:

    1. `publicChainStatus` becomes `PENDING_DEPLOYMENT`
    2. The public relayer/bridge deploys a `PublicChainERC20` mirror contract on the public chain
    3. The relayer calls `updatePublicTokenAddress(tokenAddress, publicAddr)` on the PN Token Registry, setting `publicChainStatus = DEPLOYED`
    4. The relayer calls `addAuthorizedSender()` to authorize the new public contract as a sender on `PublicRNEndpointV1`

    Your token is now bridgeable.

### Step 5: Transfer Private to Public

A user on the Privacy Node Ledger moves tokens to the public chain:

```solidity
myToken.teleportToPublicChain(
    recipientAddress,  // who receives on the public chain
    1000 * 10 ** 18,   // amount
    publicChainId      // destination chain ID
);
```

What happens under the hood:

- Tokens are **locked** on the Privacy Node Ledger (transferred to the owner address)
- The relayer picks up the dispatched message
- The relayer calls `receiveTeleportFromPrivacyNode(sender, srcChainId, recipient, amount)` on the public chain mirror contract
- The mirror contract mints tokens for the recipient on the public chain

!!! warning "User Registration Required"
    `teleportToPublicChain` requires the caller to be registered in `UserGovernance`. This is enforced by the `onlyRegisteredUsers` modifier.

### Step 6: Transfer Public to Private

A user on the public chain moves tokens back to the Privacy Node Ledger:

```solidity
publicToken.teleportToPrivacyNode(
    recipientAddress,  // who receives on the Privacy Node Ledger
    1000 * 10 ** 18,   // amount
    privateLedgerChainId
);
```

What happens under the hood:

- Tokens are **burned** on the public chain
- The relayer picks up the dispatched message
- The relayer calls `receiveTeleportFromPublicChain(recipient, amount)` on the Privacy Node Ledger token
- Recipient's previously locked tokens are unlocked and transferred back

If the unlock fails on the Privacy Node Ledger, the relayer's revert service automatically calls `revertTeleportToPrivacyNode(sender, amount)` on the public chain contract to mint the tokens back.

---

## Handler Reference

### Privacy Node Ledger — `RaylsErc20Handler`

| Function | Purpose |
|---|---|
| `teleportToPublicChain(to, amount, chainId)` | Lock on private, mint on public |
| `receiveTeleportFromPublicChain(to, amount)` | Receive tokens from public chain (unlock + transfer) |
| `revertTeleportToPublicChain(from, amount)` | Restore locked tokens when private→public transfer fails |
| `mint(to, amount)` | Mint tokens (owner only) + notify Private Network Hub |
| `burn(from, amount)` | Burn tokens (owner only) + notify Private Network Hub |
| `setResourceId(bytes32)` | Set the resource ID (called only by the PN Token Registry via the `activateToken` callback) |
| `submitTokenUpdate(updateType, amount)` | Notify Private Network Hub of supply changes |
| `getLockedAmount(account)` | View locked balance for an address |

### Public Chain — Auto-Deployed `PublicChainERC20`

| Function | Purpose |
|---|---|
| `teleportToPrivacyNode(to, amount, chainId)` | Burn on public, unlock on private |
| `receiveTeleportFromPrivacyNode(from, srcChainId, to, amount)` | Receive mint from Privacy Node Ledger |
| `revertTeleportToPrivacyNode(to, amount)` | Mint tokens back on failed public→private transfer |

!!! note "Protected Functions"
    The `receiveTeleportFromPrivacyNode` and `revertTeleportToPrivacyNode` functions are protected by the `receiveMethod` modifier — only the trusted message executor can call them. Users only call `teleportToPrivacyNode` directly.

---

## Token Standards

=== "ERC-20"

    **Inherit:** `RaylsErc20Handler`

    ```solidity
    constructor(
        string memory _name,
        string memory _symbol,
        address _endpoint,
        address _raylsNodeEndpoint,
        address _userGovernance,
        address _owner,
        bool _isCustom
    )
    ```

    **Bridge function:** `teleportToPublicChain(address to, uint256 amount, uint256 chainId)`

    **Public mirror:** `PublicChainERC20` (auto-deployed)

=== "ERC-721"

    **Inherit:** `RaylsErc721Handler`

    ```solidity
    constructor(
        string memory uri,
        string memory name_,
        string memory symbol_,
        address _endpoint,
        address _raylsNodeEndpoint,
        address _userGovernance,
        address _owner,
        bool _isCustom
    )
    ```

    **Bridge function:** `teleportToPublicChain(address to, uint256 tokenId, uint256 chainId)`

    **Public mirror:** `PublicChainERC721` (auto-deployed)

    **Minimal example:**

    ```solidity
    import "rayls-protocol-sdk/tokens/RaylsErc721Handler.sol";

    contract MyNFT is RaylsErc721Handler {
        uint256 private _tokenIdCounter;

        constructor(address _endpoint, address _raylsNodeEndpoint, address _userGovernance)
            RaylsErc721Handler(
                "https://api.example.com/nft/",
                "My NFT",
                "MNFT",
                _endpoint,
                _raylsNodeEndpoint,
                _userGovernance,
                msg.sender,
                false
            )
        {}

        function mintItem(address to) public onlyOwner returns (uint256) {
            uint256 tokenId = _tokenIdCounter++;
            _mint(to, tokenId);
            return tokenId;
        }
    }
    ```

=== "ERC-1155"

    **Inherit:** `RaylsErc1155Handler`

    ```solidity
    constructor(
        string memory _uriParam,
        string memory _name,
        address _endpoint,
        address _raylsNodeEndpoint,
        address _userGovernance,
        address _owner,
        bool _isCustom
    )
    ```

    **Bridge function:** `teleportToPublicChain(address to, uint256 id, uint256 amount, uint256 chainId, bytes memory data)`

    **Public mirror:** `PublicChainERC1155` (auto-deployed)

    **Minimal example:**

    ```solidity
    import "rayls-protocol-sdk/tokens/RaylsErc1155Handler.sol";

    contract MyMultiToken is RaylsErc1155Handler {
        uint256 public constant GOLD = 0;
        uint256 public constant SILVER = 1;

        constructor(address _endpoint, address _raylsNodeEndpoint, address _userGovernance)
            RaylsErc1155Handler(
                "https://api.example.com/token/{id}.json",
                "My Multi Token",
                _endpoint,
                _raylsNodeEndpoint,
                _userGovernance,
                msg.sender,
                false
            )
        {
            _mint(msg.sender, GOLD, 1000, "");
            _mint(msg.sender, SILVER, 5000, "");
        }
    }
    ```

---

## Customization Patterns

### Custom Decimals

Override `decimals()` to change from the default:

```solidity
contract StableCoin is RaylsErc20Handler {
    // ... constructor ...

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
```

### Role-Based Access Control

Add OpenZeppelin `AccessControl` for fine-grained permissions:

```solidity
import "@openzeppelin/contracts/access/AccessControl.sol";
import "rayls-protocol-sdk/tokens/RaylsErc20Handler.sol";

contract ManagedToken is AccessControl, RaylsErc20Handler {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address _endpoint, address _raylsNodeEndpoint, address _userGovernance)
        RaylsErc20Handler(
            "Managed Token", "MGD",
            _endpoint, _raylsNodeEndpoint, _userGovernance,
            msg.sender, true  // isCustom = true
        )
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) public override onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        _submitTokenUpdate(SharedObjects.BalanceUpdateType.MINT, amount);
    }
}
```

!!! tip "Set `isCustom` to `true`"
    When adding custom access control or business logic, set `isCustom` to `true` in the constructor. This signals the system to use the custom factory deployment path, using your contract's own bytecode and initializer params.

### Custom Initialization for Cross-Chain Deployment

When the system deploys your token on other Privacy Node Ledgers (via the contract factory), it uses the initializer params your contract provides. Override `_generateInitializerParams()` to include custom fields:

```solidity
function _generateInitializerParams() internal view override returns (bytes memory) {
    return abi.encodeWithSignature(
        "initialize(string,string,uint256,address)",
        tokenName,
        tokenSymbol,
        fundManagerChainId,
        fundManagerAddress
    );
}
```

Then implement a matching `initialize()` function that accepts those parameters.

### Override Receive Methods

Add custom validation when receiving cross-chain transfers:

```solidity
function receiveTeleportFromPublicChain(address to, uint256 value) public override {
    require(to != address(0), "Cannot unlock to zero address");
    // Add your custom validation here
    super.receiveTeleportFromPublicChain(to, value);
}
```

---

??? info "Constructor Parameters Reference"

    | Parameter | Description | Where to Find It |
    |---|---|---|
    | `_endpoint` | `EndpointV1` — The Rayls protocol endpoint on the Privacy Node Ledger. Routes messages between Privacy Node Ledgers via the Private Network Hub. | Deployed during Privacy Node Ledger setup. Available from `DeploymentProxyRegistry`. |
    | `_raylsNodeEndpoint` | `RNEndpointV1` — The Rayls Node endpoint on the Privacy Node Ledger. Routes messages between the Privacy Node Ledger and the public chain. | Deployed during Privacy Node Ledger setup. Available from `DeploymentProxyRegistry`. |
    | `_userGovernance` | `RNUserGovernanceV1` — User registry on the Privacy Node Ledger. Controls which addresses can use `teleportToPublicChain`. Pass `address(0)` to disable user checks. | Deployed during Privacy Node Ledger setup. Available from `DeploymentProxyRegistry`. |
    | `_owner` | Contract owner address. Has permissions for `mint`, `burn`, and `submitTokenUpdate`. | Typically `msg.sender`. |
    | `_isCustom` | Whether this token uses custom initialization logic. Set `true` if you override `_generateInitializerParams()` or `initialize()`. Set `false` for standard tokens. | Developer's choice. |

---

## Key Concepts

### Two Endpoints, Two Purposes

Your Privacy Node Ledger token interacts with **two** endpoints:

- **`endpoint`** (`EndpointV1`) — Used for private-to-private communication via the Private Network Hub. Functions like `teleport()` and `_raylsSend()` use this endpoint. Token registration is handled separately by the PN Token Registry (`PNTokenRegistryV1`), not by the token itself.
- **`raylsNodeEndpoint`** (`RNEndpointV1`) — Used for private-to-public communication. `teleportToPublicChain()` uses this endpoint. The public-chain mirror address is resolved from the private address via the mapping the relayer records with `updatePublicTokenAddress` on the PN Token Registry.

### Lock vs Burn

The bridge uses different mechanisms depending on direction:

| Direction | Source Action | Destination Action |
|---|---|---|
| Private to Public | **Lock** (tokens stay on Privacy Node Ledger, held by owner) | **Mint** (new tokens created on public chain) |
| Public to Private | **Burn** (tokens destroyed on public chain) | **Unlock** (previously locked tokens released and transferred) |

On the Privacy Node Ledger, tokens are locked (not burned) to maintain on-chain collateral. On the public chain, tokens are burned and minted — no locked state is tracked.

### Revert Safety

Every cross-chain message includes a revert payload. If the destination chain execution fails:

- **Private to Public failure:** The relayer sends `unlock(sender, amount)` back to the Privacy Node Ledger to release the locked tokens
- **Public to Private failure:** The relayer sends `revertTeleportToPrivacyNode(sender, amount)` back to the public chain to mint the tokens back

This happens automatically. You don't need to implement any revert logic.

---

**Navigate:**

- [Enygma Privacy](enygma-privacy.md) — Privacy-preserving transfers
- [DVP Atomic Swaps](dvp-atomic-swaps.md) — Atomic swap operations
- [Back to Build Overview](../index.md)
