# Building Custom Tokens

## Introduction

Rayls provides powerful token handler contracts that give you cross-chain capabilities out-of-the-box. Instead of building cross-chain token logic from scratch, you can inherit from Rayls handlers and focus on your token's unique features while getting enterprise-grade cross-chain functionality for free.

**Why build on Rayls handlers:**

- ✅ **Cross-chain ready**: Teleport methods included
- ✅ **Battle-tested**: Built on OpenZeppelin standards
- ✅ **Security**: Atomic transactions with auto-revert
- ✅ **Flexibility**: 50+ virtual methods to override
- ✅ **Proxy-friendly**: Initializable pattern for upgradeable deployments
- ✅ **Privacy options**: Enygma handlers for private tokens

**What you get for free:**

- Standard ERC20/ERC721/ERC1155 functionality
- Cross-chain teleport (vanilla and atomic)
- Automatic contract deployment on destination chains
- Lock/unlock mechanisms for atomic operations
- Public chain bridging support
- Resource ID-based logical addressing

**What you can customize:**

- Token logic (mint, burn, transfer validation)
- Access control (roles, permissions)
- Initial distribution
- Metadata and URIs
- Cross-chain receive behavior
- Custom functions and state

!!! info "Prerequisites"
    - Solidity basics and inheritance
    - Understand [Token Standards](token-standards.md) for teleport mechanisms
    - Read [Endpoint Integration](endpoint-integration.md) for cross-chain patterns
    - Familiar with OpenZeppelin contracts

**This guide teaches you:**

1. How to build custom ERC20, ERC721, and ERC1155 tokens
2. Common customization patterns (roles, validation, fees)
3. Advanced: Proxy initialization and custom parameters
4. Brief: Enygma privacy tokens and Dvp integration

---

## Understanding Token Handlers

### Handler Inheritance Hierarchy

All Rayls token handlers follow a consistent inheritance pattern:

```
Your Custom Token
    ↓ inherits
RaylsErc20Handler (or Erc721/Erc1155/Enygma)
    ↓ inherits
┌────────────────┬──────────────────┬───────────────┐
│   RaylsApp     │  ERC20/721/1155  │ Initializable │
│  (cross-chain) │  (OpenZeppelin)  │  (proxies)    │
└────────────────┴──────────────────┴───────────────┘
```

**What each layer provides:**

- **RaylsApp**: Cross-chain messaging, security modifiers, context extraction
- **ERC20/721/1155**: Standard token functionality (transfer, approve, balanceOf, etc.)
- **Initializable**: Proxy deployment support

**What this means for you:**

You inherit ALL functionality from these contracts. You only override what you want to customize.

---

### Handler Comparison

| Feature | ERC20Handler | ERC721Handler | ERC1155Handler | EnygmaHandler |
|---------|--------------|---------------|----------------|---------------|
| **Token Type** | Fungible | Non-fungible (NFT) | Semi-fungible | Fungible + Privacy |
| **Standard** | ERC20 | ERC721 | ERC1155 | Custom |
| **Use Case** | Currencies, utility | Art, collectibles | Gaming assets | Private tokens |
| **Cross-Chain** | teleport() | teleport() | teleport() | crossTransfer() |
| **Batch Support** | No | No | Yes | Yes (multi-dest) |
| **Privacy** | No | No | No | Yes (commitments) |
| **Callables** | No | No | No | Yes |

---

### Virtual Methods Concept

Handlers use the `virtual` keyword to mark methods you can override:

```solidity
// In RaylsErc20Handler.sol
function mint(address to, uint256 value) public virtual onlyOwner {
    _mint(to, value);
}
```

**This means you can:**

```solidity
// In your contract
function mint(address to, uint256 value) public override onlyOwner {
    require(totalSupply() + value <= MAX_SUPPLY, "Cap exceeded");
    _mint(to, value);  // Call internal OpenZeppelin mint
}
```

**Key point:** Use `override` keyword when replacing handler methods.

---

## Building Your First ERC20 Token

Let's build a simple cross-chain ERC20 token step-by-step.

### Step 1: Basic Structure

**Create file:** `MyToken.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc20Handler.sol";

contract MyToken is RaylsErc20Handler {
    constructor(
        string memory name,
        string memory symbol,
        address endpoint,
        address raylsNodeEndpoint,
        address userGovernance
    )
        RaylsErc20Handler(
            name,                // Token name
            symbol,              // Token symbol
            endpoint,            // Endpoint address
            raylsNodeEndpoint,   // Rayls Node endpoint
            userGovernance,      // User governance (or address(0))
            msg.sender,          // Owner
            false                // Not a proxy deployment
        )
    {
        // Constructor logic here
    }
}
```

**What each parameter means:**

- **name**: Token name (e.g., "My Token")
- **symbol**: Token symbol (e.g., "MTK")
- **endpoint**: EndpointV1 contract address on this chain
- **raylsNodeEndpoint**: RN Endpoint address (for private ledgers)
- **userGovernance**: User governance contract (or `address(0)` if not using)
- **msg.sender**: Will become the owner of the token
- **false**: Set to `true` for proxy deployments

---

### Step 2: Initial Token Distribution

Add minting in the constructor:

```solidity
constructor(
    string memory name,
    string memory symbol,
    address endpoint,
    address raylsNodeEndpoint,
    address userGovernance
)
    RaylsErc20Handler(name, symbol, endpoint, raylsNodeEndpoint, userGovernance, msg.sender, false)
{
    // Mint 1 million tokens to deployer
    _mint(msg.sender, 1_000_000 * 10**18);
}
```

**Note:** Always use `10**18` for 18 decimal tokens (standard).

---

### Complete Example: Simple Cross-Chain Token

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc20Handler.sol";

contract MyToken is RaylsErc20Handler {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10**18;

    constructor(
        string memory name,
        string memory symbol,
        address endpoint,
        address raylsNodeEndpoint,
        address userGovernance
    )
        RaylsErc20Handler(
            name,
            symbol,
            endpoint,
            raylsNodeEndpoint,
            userGovernance,
            msg.sender,
            false
        )
    {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
```

**That's it!** You now have a fully functional cross-chain ERC20 token.

---

### What You Get For Free

Your `MyToken` automatically has:

**Standard ERC20:**
- `transfer(address to, uint256 amount)`
- `approve(address spender, uint256 amount)`
- `transferFrom(address from, address to, uint256 amount)`
- `balanceOf(address account)`
- `totalSupply()`

**Cross-Chain Teleport:**
- `teleport(address to, uint256 value, uint256 chainId)` - One-way transfer
- `teleportAtomic(address to, uint256 value, uint256 destinationChainId)` - With auto-revert
- `teleportFrom(address from, address to, uint256 value, uint256 chainId)` - Third-party transfer
- `teleportAtomicFrom(address from, address to, uint256 value, uint256 destinationChainId)`

**Public Chain Bridge:**
- `teleportToPublicChain(address to, uint256 value, uint256 destinationChainId)`

**Owner Functions:**
- `mint(address to, uint256 value)` - Only owner
- `burn(address from, uint256 value)` - Only owner

See [Token Standards](token-standards.md) for detailed teleport mechanics.

---

## Customizing ERC20 Tokens

Now let's add custom features to your token.

### Pattern 1: Custom Validation

Override receive methods to add validation logic when tokens arrive from another chain.

**Use case:** Restrict which addresses can receive cross-chain transfers.

```solidity
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc20Handler.sol";

contract RestrictedToken is RaylsErc20Handler {
    mapping(address => bool) public blockedAddresses;

    constructor(
        string memory name,
        string memory symbol,
        address endpoint,
        address raylsNodeEndpoint
    )
        RaylsErc20Handler(name, symbol, endpoint, raylsNodeEndpoint, address(0), msg.sender, false)
    {
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function blockAddress(address account) external onlyOwner {
        blockedAddresses[account] = true;
    }

    function unblockAddress(address account) external onlyOwner {
        blockedAddresses[account] = false;
    }

    // Override atomic teleport receive method
    function receiveTeleportAtomic(address to, uint256 value)
        public
        override
        receiveMethod  // Keep security modifier!
    {
        require(!blockedAddresses[to], "Recipient is blocked");

        // Call parent implementation
        super.receiveTeleportAtomic(to, value);
    }

    // Also override regular receive
    function receiveTeleport(address to, uint256 value)
        public
        override
        receiveMethod
    {
        require(!blockedAddresses[to], "Recipient is blocked");
        super.receiveTeleport(to, value);
    }
}
```

**Key points:**

- Always keep `receiveMethod` modifier (security!)
- Call `super` to maintain base functionality
- Use `override` keyword
- Validate BEFORE calling super

**Real-world example from Rayls tests:**

**File:** `TokenExample.sol`

```solidity
contract TokenExample is RaylsErc20Handler {
    address public constant addressToFail = address(0x0000000000000000000555000000000000001123);

    constructor(
        string memory _name,
        string memory _symbol,
        address _endpoint,
        address _raylsNodeEndpoint,
        address _userGovernance
    )
        RaylsErc20Handler(_name, _symbol, _endpoint, _raylsNodeEndpoint, _userGovernance, msg.sender, false)
    {
        _mint(msg.sender, 2_000_000 * 10**18);
    }

    function receiveTeleportAtomic(address to, uint256 value) public override receiveMethod {
        // Custom validation for test purposes
        if (to == addressToFail) {
            revert("Destination address is the one that revert messages.");
        }

        super.receiveTeleportAtomic(to, value);
    }

    function receiveTeleportFromPublicChain(address to, uint256 value) public override {
        if (to == address(0)) {
            revert("Hit destination revert address.");
        }

        super.receiveTeleportFromPublicChain(to, value);
    }
}
```

---

### Pattern 2: Role-Based Access Control

Use OpenZeppelin's `AccessControl` for fine-grained permissions.

**Use case:** Multiple parties with different permissions (admin, minter, burner).

```solidity
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc20Handler.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract RoleBasedToken is AccessControl, RaylsErc20Handler {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bool public paused;

    constructor(
        string memory name,
        string memory symbol,
        address endpoint,
        address raylsNodeEndpoint
    )
        RaylsErc20Handler(name, symbol, endpoint, raylsNodeEndpoint, address(0), msg.sender, false)
    {
        // Grant roles to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        _mint(msg.sender, 1_000_000 * 10**18);
    }

    // Override mint to require MINTER_ROLE
    function mint(address to, uint256 amount) public override onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // Add custom burn function with BURNER_ROLE
    function burn(uint256 amount) public onlyRole(BURNER_ROLE) {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public onlyRole(BURNER_ROLE) {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    // Add pause functionality
    function pause() external onlyRole(PAUSER_ROLE) {
        paused = true;
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        paused = false;
    }

    // Override _update to enforce pause
    function _update(address from, address to, uint256 amount) internal virtual override {
        require(!paused, "Token transfers are paused");
        super._update(from, to, amount);
    }
}
```

**Key points:**

- Multiple inheritance: `AccessControl, RaylsErc20Handler`
- Define role constants with `keccak256`
- Grant roles in constructor
- Use `onlyRole` modifier on functions
- Override internal hooks like `_update` for global logic

**Real-world example:** `CustomTokenExample.sol` (partial)

```solidity
contract CustomTokenExample is AccessControl, RaylsErc20Handler {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    bytes32 public attestationUid;
    uint256 public fundManagerFeeChainId;
    address public fundManagerAddr;

    constructor(
        string memory name,
        string memory symbol,
        uint256 _fundManagerChainId,
        address _fundManagerAddr,
        address _endpointAddr,
        address _raylsNodeEndpoint
    ) RaylsErc20Handler(name, symbol, _endpointAddr, _raylsNodeEndpoint, address(0), msg.sender, true) {
        fundManagerFeeChainId = _fundManagerChainId;
        fundManagerAddr = _fundManagerAddr;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, _fundManagerAddr);
        _grantRole(BURNER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) public override onlyRole(MINTER_ROLE) {
        require(attestationUid != bytes32(0), "No risk analysis attestation emitted yet");
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}
```

---

### Pattern 3: Custom Decimals

Override `decimals()` for non-standard precision.

**Use case:** Stablecoins (USDC uses 6 decimals), price feeds, or tokens representing non-divisible assets.

```solidity
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc20Handler.sol";

contract StablecoinToken is RaylsErc20Handler {
    constructor(
        string memory name,
        string memory symbol,
        address endpoint,
        address raylsNodeEndpoint
    )
        RaylsErc20Handler(name, symbol, endpoint, raylsNodeEndpoint, address(0), msg.sender, false)
    {
        // Mint 1 million with 6 decimals = 1,000,000.000000
        _mint(msg.sender, 1_000_000 * 10**6);
    }

    // Override decimals to return 6 instead of 18
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
```

**From CustomTokenExample.sol:**

```solidity
function decimals() public pure override returns (uint8) {
    return 6;
}
```

---

### Pattern 4: Supply Cap

Prevent unlimited minting by enforcing a maximum supply.

```solidity
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc20Handler.sol";

contract CappedToken is RaylsErc20Handler {
    uint256 public constant MAX_SUPPLY = 10_000_000 * 10**18;

    constructor(
        string memory name,
        string memory symbol,
        address endpoint,
        address raylsNodeEndpoint
    )
        RaylsErc20Handler(name, symbol, endpoint, raylsNodeEndpoint, address(0), msg.sender, false)
    {
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    // Override mint to enforce cap
    function mint(address to, uint256 amount) public override onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }
}
```

**Key point:** Check `totalSupply()` before minting.

---

### Pattern 5: Transfer Fees

Deduct a fee on every transfer and send to a fee collector.

```solidity
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc20Handler.sol";

contract FeeToken is RaylsErc20Handler {
    uint256 public constant FEE_PERCENT = 1; // 1% fee
    address public feeCollector;

    constructor(
        string memory name,
        string memory symbol,
        address endpoint,
        address raylsNodeEndpoint,
        address _feeCollector
    )
        RaylsErc20Handler(name, symbol, endpoint, raylsNodeEndpoint, address(0), msg.sender, false)
    {
        feeCollector = _feeCollector;
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
    }

    // Override _update to deduct fees
    function _update(address from, address to, uint256 amount) internal virtual override {
        // Skip fee for minting and burning
        if (from == address(0) || to == address(0)) {
            super._update(from, to, amount);
            return;
        }

        // Calculate fee
        uint256 fee = (amount * FEE_PERCENT) / 100;
        uint256 amountAfterFee = amount - fee;

        // Transfer fee to collector
        if (fee > 0) {
            super._update(from, feeCollector, fee);
        }

        // Transfer remaining amount to recipient
        super._update(from, to, amountAfterFee);
    }
}
```

**Warning:** Be careful with `_update` overrides. Test thoroughly to avoid breaking token mechanics.

---

## Building ERC721 (NFT) Tokens

NFTs follow a similar pattern but with token IDs instead of amounts.

### Step-by-Step: Cross-Chain NFT

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc721Handler.sol";

contract MyNFT is RaylsErc721Handler {
    uint256 private _tokenIdCounter;

    constructor(
        string memory baseUri,
        string memory name,
        string memory symbol,
        address endpoint,
        address raylsNodeEndpoint,
        address userGovernance
    )
        RaylsErc721Handler(
            baseUri,            // Base URI for metadata
            name,               // Collection name
            symbol,             // Collection symbol
            endpoint,
            raylsNodeEndpoint,
            userGovernance,
            msg.sender,
            false
        )
    {
        // Mint initial NFTs to deployer
        _safeMint(msg.sender, 0);
        _safeMint(msg.sender, 1);
        _safeMint(msg.sender, 2);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "https://api.mynft.com/metadata/";
    }

    // Custom minting function with auto-increment
    function mintNFT(address to) public onlyOwner returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        _safeMint(to, tokenId);
        _tokenIdCounter++;
        return tokenId;
    }
}
```

**What you get:**

- All ERC721 functions (ownerOf, tokenURI, transferFrom, etc.)
- Cross-chain teleport: `teleport(address to, uint256 id, uint256 chainId)`
- Atomic teleport: `teleportAtomic(address to, uint256 id, uint256 chainId)`
- Public chain bridging

---

### Complete Example: NFT with Auto-Increment

**From Erc721Example.sol:**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc721Handler.sol";

contract RaylsErc721Example is RaylsErc721Handler {
    uint256 private _tokenIdCounter;
    string private _baseUri;

    constructor(
        string memory baseUri,
        string memory name,
        string memory symbol,
        address _endpoint,
        address _raylsNodeEndpoint,
        address _userGovernance
    )
        RaylsErc721Handler(baseUri, name, symbol, _endpoint, _raylsNodeEndpoint, _userGovernance, msg.sender, false)
    {
        // Mint initial NFTs
        _safeMint(msg.sender, 0);
        _safeMint(msg.sender, 100);
        _safeMint(msg.sender, 150);

        _baseUri = baseUri;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseUri;
    }

    function awardItem(address account) public returns (uint256) {
        uint256 newItemId = _tokenIdCounter;
        _mint(account, newItemId);
        _tokenIdCounter++;
        return newItemId;
    }
}
```

**Key patterns:**

- Store `_tokenIdCounter` for sequential IDs
- Override `_baseURI()` for metadata
- Custom mint function (`awardItem`) for public minting
- Initial mints in constructor

---

### Pattern: Dynamic Metadata

Override `tokenURI` for dynamic metadata generation.

```solidity
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc721Handler.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract DynamicNFT is RaylsErc721Handler {
    using Strings for uint256;

    mapping(uint256 => uint256) public tokenLevel;

    constructor(
        string memory name,
        string memory symbol,
        address endpoint,
        address raylsNodeEndpoint
    )
        RaylsErc721Handler("", name, symbol, endpoint, raylsNodeEndpoint, address(0), msg.sender, false)
    {}

    function mint(address to, uint256 id) public override onlyOwner {
        _safeMint(to, id);
        tokenLevel[id] = 1; // Start at level 1
    }

    function levelUp(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        tokenLevel[tokenId]++;
    }

    // Override tokenURI for dynamic metadata
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireOwned(tokenId);

        uint256 level = tokenLevel[tokenId];
        return string(abi.encodePacked(
            "https://api.dynamicnft.com/",
            tokenId.toString(),
            "/level/",
            level.toString()
        ));
    }
}
```

---

## Building ERC1155 (Multi-Token) Tokens

ERC1155 supports multiple token types in one contract.

### Complete Example: Gaming Token System

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc1155Handler.sol";

contract GameToken is RaylsErc1155Handler {
    // Token ID constants
    uint256 public constant GOLD = 0;
    uint256 public constant SILVER = 1;
    uint256 public constant BRONZE = 2;
    uint256 public constant SWORD = 100;
    uint256 public constant SHIELD = 101;

    constructor(
        string memory uri,
        string memory name,
        address endpoint,
        address raylsNodeEndpoint,
        address userGovernance
    )
        RaylsErc1155Handler(uri, name, endpoint, raylsNodeEndpoint, userGovernance, msg.sender, false)
    {
        // Mint initial currencies
        _mint(msg.sender, GOLD, 1000, "Initial gold");
        _mint(msg.sender, SILVER, 5000, "Initial silver");
        _mint(msg.sender, BRONZE, 10000, "Initial bronze");

        // Mint initial items (unique)
        _mint(msg.sender, SWORD, 1, "Legendary sword");
        _mint(msg.sender, SHIELD, 1, "Legendary shield");
    }

    // Custom minting for game rewards
    function rewardPlayer(address player, uint256 tokenId, uint256 amount) external onlyOwner {
        _mint(player, tokenId, amount, "Game reward");
    }
}
```

**What you get:**

- Multi-token management in one contract
- Cross-chain teleport: `teleport(address to, uint256 id, uint256 value, uint256 chainId, bytes memory data)`
- Atomic teleport: `teleportAtomic(address to, uint256 id, uint256 value, uint256 chainId, bytes memory data)`
- Batch operations (built into ERC1155)

**Key points:**

- Use constants for token IDs (readability)
- Mix fungible (currencies) and non-fungible (items) tokens
- Include meaningful data in mint calls

---

### Pattern: Token-Specific Validation

Different rules for different token types:

```solidity
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc1155Handler.sol";

contract RestrictedGameToken is RaylsErc1155Handler {
    uint256 public constant GOLD = 0;
    uint256 public constant LEGENDARY_ITEM = 100;

    constructor(
        string memory uri,
        string memory name,
        address endpoint,
        address raylsNodeEndpoint
    )
        RaylsErc1155Handler(uri, name, endpoint, raylsNodeEndpoint, address(0), msg.sender, false)
    {}

    // Override receive to add token-specific validation
    function receiveTeleportAtomic(
        address to,
        uint256 id,
        uint256 value,
        bytes memory data
    ) public override receiveMethod {
        // Legendary items: only 1 per address
        if (id >= 100 && id < 200) {
            require(balanceOf(to, id) == 0, "Already owns legendary item");
        }

        // Gold: max 10000 per address
        if (id == GOLD) {
            require(balanceOf(to, GOLD) + value <= 10000, "Exceeds gold limit");
        }

        super.receiveTeleportAtomic(to, id, value, data);
    }
}
```

---

## Advanced: Custom Initialize for Proxies

For upgradeable tokens using proxy patterns, you need custom initialization.

### Why Proxies?

**Use proxies when:**

- You want upgradeable contracts
- You need the same address across chains
- You want to deploy via registry

**Don't use proxies when:**

- Simple token with no upgrade needs
- Deploying directly (not via registry)

---

### Pattern: Custom Initialization Parameters

**From CustomTokenExample.sol:**

```solidity
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc20Handler.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract CustomTokenExample is AccessControl, RaylsErc20Handler {
    bytes32 public attestationUid;
    uint256 public fundManagerFeeChainId;
    address public fundManagerAddr;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(
        string memory name,
        string memory symbol,
        uint256 _fundManagerChainId,
        address _fundManagerAddr,
        address _endpointAddr,
        address _raylsNodeEndpoint
    ) RaylsErc20Handler(name, symbol, _endpointAddr, _raylsNodeEndpoint, address(0), msg.sender, true) {
        fundManagerFeeChainId = _fundManagerChainId;
        fundManagerAddr = _fundManagerAddr;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, _fundManagerAddr);
        _grantRole(BURNER_ROLE, msg.sender);
    }

    // Override decimals
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // Custom initialize function for proxy deployment
    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _fundManagerChainId,
        address _fundManagerAddr,
        bytes32 _attestationUuid
    ) public initializer {
        // Extract standard params from context
        address _owner = _getOwnerAddressOnInitialize();
        address _endpoint = _getEndpointAddressOnInitialize();
        resourceId = _getResourceIdOnInitialize();

        // Set token state
        tokenName = _name;
        tokenSymbol = _symbol;
        attestationUid = _attestationUuid;
        fundManagerFeeChainId = _fundManagerChainId;
        fundManagerAddr = _fundManagerAddr;

        // Initialize parent contracts
        _transferOwnership(_owner);
        endpoint = IRaylsEndpoint(_endpoint);

        // Set up roles
        _grantRole(MINTER_ROLE, _owner);
        _grantRole(BURNER_ROLE, _owner);
    }

    // Override to provide custom initialization parameters
    function _generateInitializerParams() internal view override returns (bytes memory) {
        return abi.encodeWithSignature(
            "initialize(string,string,uint256,address,bytes32)",
            tokenName,
            tokenSymbol,
            fundManagerFeeChainId,
            fundManagerAddr,
            attestationUid
        );
    }

    // Custom mint with attestation check
    function mint(address to, uint256 amount) public override onlyRole(MINTER_ROLE) {
        require(attestationUid != bytes32(0), "No risk analysis attestation emitted yet");
        _mint(to, amount);
    }
}
```

**Key points:**

1. **Constructor**: Pass `true` as last parameter (proxy flag)
2. **initialize()**: Marked with `initializer` modifier
3. **Extract context**: Use `_getOwnerAddressOnInitialize()`, `_getEndpointAddressOnInitialize()`, `_getResourceIdOnInitialize()`
4. **Set state**: Set token name, symbol, and custom parameters
5. **Initialize parents**: Call `_transferOwnership()` and set `endpoint`
6. **Override _generateInitializerParams()**: Return encoded initialize call with YOUR parameters

**When proxy is deployed:**

The registry will automatically call your `initialize()` function with the parameters from `_generateInitializerParams()`.

---

## Enygma Privacy Tokens

Enygma tokens provide privacy through Pedersen commitments and support cross-chain callables.

### What Makes Enygma Different

| Feature | Standard ERC20 | Enygma |
|---------|---------------|---------|
| **Privacy** | Balances public | Balances hidden in commitments |
| **Cross-Chain** | teleport() | crossTransfer() |
| **Batch** | No | Yes (multi-destination) |
| **Callables** | No | Yes (execute functions on arrival) |
| **Reference IDs** | No | Yes (track transaction status) |
| **Dvp** | Separate handler | Native integration |

### When to Use Enygma

**Use Enygma when:**

- Privacy is required (hidden balances)
- Batching transfers to multiple recipients
- Need to call functions after transfer (callables)
- Want Dvp integration for swaps

**Use standard handlers when:**

- Transparency is fine/required
- Simple cross-chain transfers
- Standard ERC20 compatibility needed

---

### Complete Example: Simple Privacy Token

**From EnygmaTokenExample.sol:**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsEnygmaHandler.sol";

contract EnygmaTokenExample is RaylsEnygmaHandler {
    string public message = "test";

    constructor(
        string memory _name,
        string memory _symbol,
        address _endpoint
    )
        RaylsEnygmaHandler(
            _name,          // Token name
            _symbol,        // Token symbol
            _endpoint,      // Endpoint address
            msg.sender,     // Owner
            18,             // Decimals
            false           // Not proxy
        )
    {}

    // Custom callable function
    // This can be executed via crossTransfer callables
    function receiveMsgA(string memory _msg) public {
        message = _msg;
    }
}
```

**Key differences:**

- No `raylsNodeEndpoint` or `userGovernance` parameters
- Specify `decimals` directly (18 standard)
- Custom functions can be called via cross-chain callables

---

### Pattern: Cross-Transfer with Callables

Enygma allows you to execute contract calls after a transfer:

```solidity
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsEnygmaHandler.sol";
import "@rayls/rayls-protocol-sdk/libraries/SharedObjects.sol";

contract CallableEnygma is RaylsEnygmaHandler {
    mapping(address => bool) public verified;

    constructor(
        string memory name,
        string memory symbol,
        address endpoint
    ) RaylsEnygmaHandler(name, symbol, endpoint, msg.sender, 18, false) {}

    // Function to be called after transfer
    function verifyUser(address user) public {
        verified[user] = true;
    }

    // Transfer with automatic verification on arrival
    function transferAndVerify(
        address to,
        uint256 amount,
        uint256 toChainId
    ) external returns (bytes32) {
        // Prepare arrays
        address[] memory toArray = new address[](1);
        uint256[] memory valueArray = new uint256[](1);
        uint256[] memory chainArray = new uint256[](1);

        toArray[0] = to;
        valueArray[0] = amount;
        chainArray[0] = toChainId;

        // Prepare callable
        SharedObjects.EnygmaCrossTransferCallable[][] memory callables =
            new SharedObjects.EnygmaCrossTransferCallable[][](1);
        SharedObjects.EnygmaCrossTransferCallable[] memory callableArray =
            new SharedObjects.EnygmaCrossTransferCallable[](1);

        callableArray[0] = SharedObjects.EnygmaCrossTransferCallable({
            resourceId: resourceId,  // Call this contract on destination
            contractAddress: address(0),
            payload: abi.encodeWithSignature("verifyUser(address)", to)
        });

        callables[0] = callableArray;

        // Execute cross-transfer with callable
        return crossTransfer(toArray, valueArray, chainArray, callables);
    }
}
```

**What happens:**

1. Tokens transferred to destination chain
2. Upon arrival, `verifyUser(to)` is automatically called
3. Recipient receives tokens AND gets verified

See [Token Standards](token-standards.md) for more details.

---

## Dvp Enhanced Tokens

Dvp (Zero-Knowledge Delivery vs Payment) handlers add atomic swap capabilities to NFTs and multi-tokens.

### What Dvp Adds

- **Atomic swaps**: Exchange NFTs for Enygma tokens atomically
- **Zero-knowledge**: Privacy-preserving swaps
- **Deposit/Withdraw**: Enygma deposit pool for swaps
- **Lock mechanisms**: Additional locks for pending swaps

### When to Use Dvp Handlers

**Use RaylsErc721DvpHandler when:**

- NFTs need to be swappable for tokens
- Want atomic NFT-for-token exchanges
- Privacy-focused NFT operations

**Use RaylsErc1155DvpHandler when:**

- Gaming items need token exchange
- Batch swaps required
- Semi-fungible token economy

---

### Key Dvp Methods

```solidity
// Deposit NFT into Dvp for swapping
function depositIntoDvp(uint256 _tokenId) public virtual

// Swap NFT for Enygma tokens
function swapWithDvpForEnygma(
    uint256 _enygmaAmount,
    bytes32 _enygmaResourceId,
    uint256 _destChainId,
    bytes32 _sharedId,
    uint256 _validityTime
) public virtual

// Withdraw NFT from Dvp
function withdrawFromDvp(uint256 _tokenId) public virtual

// Unlock after successful swap
function unlockFromDvp(uint256 _tokenId) public virtual
```

---

### Pattern: Custom Dvp Override

You can override Dvp behavior for custom requirements:

```solidity
pragma solidity ^0.8.20;

import "@rayls/rayls-protocol-sdk/tokens/RaylsErc721DvpHandler.sol";

contract CustomDvpNFT is RaylsErc721DvpHandler {
    constructor(
        string memory baseUri,
        string memory name,
        string memory symbol,
        address endpoint,
        address raylsNodeEndpoint
    )
        RaylsErc721DvpHandler(baseUri, name, symbol, endpoint, raylsNodeEndpoint, address(0), msg.sender, false)
    {}

    // Override burn to remove Dvp lock check (if needed)
    function burn(uint256 _id) public virtual override onlyOwner {
        // Custom logic instead of Dvp lock check
        require(canBurn(_id), "Cannot burn this token");

        _submitTokenUpdate(SharedObjects.BalanceUpdateType.BURN, _id);
        _burn(_id);

        if (resourceId != bytes32(0)) {
            IEnygmaPLEvents(getEnygmaEventsAdress()).dvp721Burn(resourceId, _id);
        }
    }

    function canBurn(uint256 _id) internal view returns (bool) {
        // Your custom burn logic
        return !lockedForDvp[_id] || hasAdminOverride(msg.sender);
    }

    function hasAdminOverride(address account) internal view returns (bool) {
        // Your admin logic
        return account == owner();
    }
}
```

See [DVP Atomic Swaps](../advanced/dvp-atomic-swaps.md) for complete documentation.

---

## Common Customization Patterns

Quick reference for common modifications.

### Pausable Token

```solidity
bool public paused;

function pause() external onlyOwner {
    paused = true;
}

function unpause() external onlyOwner {
    paused = false;
}

function _update(address from, address to, uint256 amount) internal virtual override {
    require(!paused, "Transfers paused");
    super._update(from, to, amount);
}
```

---

### Blacklist/Whitelist

```solidity
mapping(address => bool) public blacklisted;

function blacklist(address account) external onlyOwner {
    blacklisted[account] = true;
}

function _update(address from, address to, uint256 amount) internal virtual override {
    require(!blacklisted[from] && !blacklisted[to], "Blacklisted address");
    super._update(from, to, amount);
}
```

---

### Snapshot Balances

```solidity
mapping(uint256 => mapping(address => uint256)) private _snapshots;
uint256 private _currentSnapshotId;

function snapshot() external onlyOwner returns (uint256) {
    _currentSnapshotId++;
    return _currentSnapshotId;
}

function _update(address from, address to, uint256 amount) internal virtual override {
    if (_currentSnapshotId > 0) {
        _snapshots[_currentSnapshotId][from] = balanceOf(from);
        _snapshots[_currentSnapshotId][to] = balanceOf(to);
    }
    super._update(from, to, amount);
}

function balanceOfAt(address account, uint256 snapshotId) public view returns (uint256) {
    return _snapshots[snapshotId][account];
}
```

---

### Staking Mechanism

```solidity
mapping(address => uint256) public stakedBalance;

function stake(uint256 amount) external {
    _transfer(msg.sender, address(this), amount);
    stakedBalance[msg.sender] += amount;
}

function unstake(uint256 amount) external {
    require(stakedBalance[msg.sender] >= amount, "Insufficient stake");
    stakedBalance[msg.sender] -= amount;
    _transfer(address(this), msg.sender, amount);
}
```

---

### Governance Integration

```solidity
function getVotingPower(address account) external view returns (uint256) {
    return balanceOf(account);
}

function delegateVotes(address delegatee) external {
    // Your delegation logic
}
```

---

## Virtual Methods Reference

Quick lookup of overridable methods by handler type.

### RaylsErc20Handler

**Token Operations:**
- `mint(address to, uint256 value)` - Mint tokens
- `burn(address from, uint256 value)` - Burn tokens
- `decimals()` - Return token decimals

**Cross-Chain:**
- `teleport(...)` - Vanilla cross-chain transfer
- `teleportAtomic(...)` - Atomic cross-chain transfer
- `teleportFrom(...)` - Third-party teleport
- `teleportAtomicFrom(...)` - Third-party atomic
- `teleportToPublicChain(...)` - Bridge to public chain

**Receive Methods:**
- `receiveTeleport(address to, uint256 value)` - Receive vanilla teleport
- `receiveTeleportAtomic(address to, uint256 value)` - Receive atomic teleport
- `receiveTeleportFromPublicChain(address to, uint256 value)` - Receive from public chain (unlock + transfer)
- `revertTeleportToPublicChain(address from, uint256 amount)` - Restore locked tokens on failed private→public
- `revertTeleportMint(address to, uint256 value)` - Revert on failure (private-to-private)
- `revertTeleportBurn(uint256 value)` - Cleanup on revert (private-to-private)

**Internal Hooks:**
- `_update(address from, address to, uint256 amount)` - Called on every transfer
- `_generateInitializerParams()` - Custom initialize parameters

---

### RaylsErc721Handler

**Token Operations:**
- `mint(address to, uint256 id)` - Mint NFT
- `burn(uint256 id)` - Burn NFT
- `_baseURI()` - Return base metadata URI
- `tokenURI(uint256 tokenId)` - Return token metadata URI

**Cross-Chain:**
- `teleport(address to, uint256 id, uint256 chainId)`
- `teleportAtomic(address to, uint256 id, uint256 chainId)`
- `teleportToPublicChain(...)`

**Receive Methods:**
- `receiveTeleport(address to, uint256 id)`
- `receiveTeleportAtomic(address to, uint256 id)`
- `receiveTeleportFromPublicChain(address to, uint256 id)` - Receive from public chain
- `revertTeleportToPublicChain(address to, uint256 id)` - Restore locked NFT on failed private→public
- `revertTeleportMint(address to, uint256 id)` - Revert on failure (private-to-private)
- `revertTeleportBurn(uint256 id)` - Cleanup on revert (private-to-private)

**Internal Hooks:**
- `_update(address to, uint256 tokenId, address auth)` - Called on every transfer/mint/burn

---

### RaylsErc1155Handler

**Token Operations:**
- `mint(address to, uint256 id, uint256 value, bytes memory data)`
- `burn(address from, uint256 id, uint256 value)`

**Cross-Chain:**
- `teleport(address to, uint256 id, uint256 value, uint256 chainId, bytes memory data)`
- `teleportAtomic(address to, uint256 id, uint256 value, uint256 chainId, bytes memory data)`
- `teleportToPublicChain(...)`

**Receive Methods:**
- `receiveTeleport(address to, uint256 id, uint256 value, bytes memory data)`
- `receiveTeleportAtomic(address to, uint256 id, uint256 value, bytes memory data)`
- `receiveTeleportFromPublicChain(address to, uint256 id, uint256 amount)` - Receive from public chain
- `revertTeleportToPublicChain(address to, uint256 id, uint256 value)` - Restore locked tokens on failed private→public
- `revertTeleportMint(address to, uint256 id, uint256 value, bytes memory data)` - Revert on failure (private-to-private)
- `revertTeleportBurn(address to, uint256 id, uint256 value)` - Cleanup on revert (private-to-private)

---

### RaylsEnygmaHandler

**Token Operations:**
- `mint(address _to, uint256 _value)`
- `burn(address from, uint256 value)`

**Cross-Chain:**
- `crossTransfer(address[] memory _to, uint256[] memory _value, uint256[] memory _toChainId, EnygmaCrossTransferCallable[][] memory _callables)`
- `crossTransferFrom(...)` - Third-party transfer
- `linearCrossTransfer(...)` - Linear multi-chain transfer

**Dvp:**
- `depositToDvp(uint256 amount)`
- `callWithdrawFromDvp(uint256 amount)`
- `swapWithDvpForERC721(...)`
- `swapWithDvpForERC1155(...)`

**Receive Methods:**
- `crossMint(address _to, uint256 _value, bytes32 _referenceId, EnygmaCrossTransferCallable[] calldata _callables)`
- `crossRevertMint(address _to, uint256 _value, string memory _reason)`
- `receiveWithdrawFromDvp(address _to, uint256 _value, bytes32 _referenceId)`

---

## Best Practices

!!! tip "Comprehensive Security Guide"
    This section covers essential security practices for custom tokens. For complete security documentation including all modifiers, attack prevention strategies, and detailed security analysis, see [Security](security.md).

### Do's

✅ **Always call super when overriding**

```solidity
function mint(address to, uint256 amount) public override onlyOwner {
    require(totalSupply() + amount <= MAX_SUPPLY, "Cap exceeded");
    super.mint(to, amount);  // Or _mint(to, amount) for internal
}
```

✅ **Maintain security modifiers**

```solidity
function receiveTeleportAtomic(address to, uint256 value)
    public
    override
    receiveMethod  // Keep this!
{
    super.receiveTeleportAtomic(to, value);
}
```

✅ **Test cross-chain flows**

See [Testing](testing.md) for comprehensive test patterns.

✅ **Document your overrides**

```solidity
/// @notice Override to enforce supply cap
/// @dev Reverts if minting would exceed MAX_SUPPLY
function mint(address to, uint256 amount) public override onlyOwner {
    require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
    _mint(to, amount);
}
```

✅ **Use events for transparency**

```solidity
event SupplyCapChanged(uint256 oldCap, uint256 newCap);

function setMaxSupply(uint256 newCap) external onlyOwner {
    emit SupplyCapChanged(MAX_SUPPLY, newCap);
    MAX_SUPPLY = newCap;
}
```

---

### Don'ts

❌ **Don't break lock mechanisms**

```solidity
// ❌ Bad - bypasses atomic teleport locks
function forceTransfer(address to, uint256 amount) external onlyOwner {
    _transfer(owner(), to, amount);  // Ignores locked balances!
}

// ✅ Good - respect locks
function adminTransfer(address to, uint256 amount) external onlyOwner {
    bool success = _unlock(to, amount);
    if (success) {
        _transfer(owner(), to, amount);
    }
}
```

❌ **Don't skip supply tracking**

```solidity
// ❌ Bad - doesn't call _submitTokenUpdate
function mint(address to, uint256 amount) public override onlyOwner {
    _mint(to, amount);  // Missing _submitTokenUpdate!
}

// ✅ Good - maintain supply tracking (or call super)
function mint(address to, uint256 amount) public override onlyOwner {
    _submitTokenUpdate(SharedObjects.BalanceUpdateType.MINT, amount);
    _mint(to, amount);
}
```

❌ **Don't forget modifiers**

```solidity
// ❌ Bad - missing receiveMethod
function receiveTeleport(address to, uint256 value) public override {
    _mint(to, value);
}

// ✅ Good - has receiveMethod
function receiveTeleport(address to, uint256 value) public override receiveMethod {
    _mint(to, value);
}
```

---

## Summary

### Handler Selection Guide

**Choose RaylsErc20Handler for:**
- Currencies, utility tokens, stablecoins
- Standard fungible token use cases
- Simple cross-chain transfers

**Choose RaylsErc721Handler for:**
- NFTs, art, collectibles
- Unique tokens with metadata
- Cross-chain NFT transfers

**Choose RaylsErc1155Handler for:**
- Gaming assets (items + currencies)
- Multiple token types in one contract
- Efficient batch operations

**Choose RaylsEnygmaHandler for:**
- Privacy-focused tokens
- Batch transfers to multiple recipients
- Tokens with cross-chain callables
- Native Dvp integration

**Choose RaylsErc721DvpHandler for:**
- NFTs with atomic swap capabilities
- Privacy-enhanced NFT operations

**Choose RaylsErc1155DvpHandler for:**
- Gaming tokens with swap features
- Semi-fungible tokens with Dvp

---

### Customization Checklist

When building your custom token:

- [ ] Choose appropriate handler (ERC20/721/1155/Enygma)
- [ ] Define initial supply/distribution
- [ ] Add custom state variables if needed
- [ ] Override methods you want to customize
- [ ] Always call `super` unless replacing entirely
- [ ] Maintain security modifiers (`receiveMethod`, `onlyOwner`)
- [ ] Test cross-chain flows (see [Testing](testing.md))
- [ ] Document your customizations
- [ ] Consider proxy pattern if upgradeable
- [ ] Don't break lock mechanisms

---

### Related Documentation

**For understanding base functionality:**
- [Token Standards](token-standards.md) - Teleport mechanics and atomic operations
- [Endpoint Integration](endpoint-integration.md) - Cross-chain patterns and security

**For advanced features:**
- [Enygma Privacy](../advanced/enygma-privacy.md) - Privacy tokens in depth
- [DVP Atomic Swaps](../advanced/dvp-atomic-swaps.md) - Atomic swap mechanics

**For development:**
- [Testing](testing.md) - Test your custom tokens
- [Best Practices](../reference/best-practices.md) - Production guidelines

---

You now have everything you need to build custom cross-chain tokens on Rayls. Start with a simple token, test thoroughly, and add features incrementally.

Ready to deploy? See deployment documentation in the Deploy section.
