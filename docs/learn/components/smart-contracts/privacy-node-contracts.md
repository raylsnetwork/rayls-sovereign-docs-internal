# Privacy Node Contracts

Smart contracts deployed on each institution's Rayls Privacy Node. These contracts are organized into two categories based on their communication target.

---

## Rayls Protocol Contracts (Private ↔ Private)

These contracts handle communication between Privacy Nodes through the Private Network Hub. They manage cross-chain messaging within the private Rayls network.

### EndpointV1

The central entry point for all cross-chain communication with the Private Network Hub.

**What it does:**

- Dispatches outgoing messages to other Privacy Nodes via the Hub
- Executes incoming messages from the Hub
- Manages message IDs and prevents replay attacks
- Appends context (messageId, fromChainId, sender) to calldata

**Key operations:**

- `send()` - Dispatch a message to another Privacy Node
- `receivePayload()` - Process an incoming message from the Hub
- `isExecuted()` - Check if a message was already processed

### Registry Replicas

Local copies of Hub registries, synchronized via cross-chain messages. These enable local validation without querying the Hub.

**ParticipantStorageReplicaV1:**

- Syncs participant data from the Hub's ParticipantStorage
- Stores public keys for encryption (Rayls View Keys, Payment Spend Keys)
- Enables local participant validation
- Updated automatically when participants join or change

### PN Token Registry

The Privacy Node maintains its own modular token registry that centralizes token registration and lifecycle management on the PN side. This is the PN-side counterpart to the Hub's `TokenRegistryV1`.

**PNTokenRegistryV1:**

- UUPS facade for all PN-side token registration
- Entry point for registering a token locally: `registerToken(tokenAddress)` (reads name/symbol/totalSupply on-chain, enforces symbol uniqueness)
- Tracks three independent status state machines per token: `PrivacyNodeStatus` (PN operator), `HubStatus` (set via PNH cross-chain callbacks), and `PublicChainStatus` (relayer/bridge)
- Coordinates promotion to the Hub (`submitToHub`) and to a public chain (`submitToPublicChain`)

**Modules:**

- **PNTokenCoreV1** - Registration lifecycle and status transitions (`updatePrivacyNodeStatus`, `submitToHub`, `submitToPublicChain`, `activateToken`)
- **PNTokenFreezeManagerV1** - Freeze/unfreeze a token independently on the Privacy Node, Hub, or public-chain layer

See [PN Token Registry](pn-token-registry.md) for the full status model, flows, and query surface.

### Token Handlers

Token handlers process cross-chain token operations within the private network. Each handler extends a base contract and implements teleport/receive logic.

**RaylsErc20Handler:**

- Burns tokens on source Privacy Node
- Mints tokens on destination Privacy Node
- Supports both standard and atomic teleports

**RaylsErc721Handler:**

- Locks or burns NFT on source chain
- Mints NFT with same tokenId on destination
- Preserves token metadata across chains

**RaylsErc1155Handler:**

- Supports batch transfers of multiple token types
- Burns tokens on source, mints on destination
- Maintains token balances across chains

**RaylsEnygmaHandler:**

- Processes privacy-preserving transfers with hidden amounts
- Works with ZK proofs for privacy
- Coordinates with Gnark API for proof verification

**RaylsErc721ZkDvpHandler:**

- Deposits NFTs into ZK-DvP escrow
- Participates in atomic cross-chain swaps
- Withdraws NFTs after successful settlement

**RaylsErc1155ZkDvpHandler:**

- Similar to ERC-721 handler but for multi-tokens
- Supports batch deposits and withdrawals
- Coordinates with ZkDvp contract on Hub

---

## RN Contracts (Private ↔ Public)

These contracts handle **one-to-one** communication between a Privacy Node and a specific public blockchain. Each Privacy Node connects to exactly one public chain. The "RN" prefix stands for "Rayls Node".

### EIP-5164 Pattern

The RN contracts implement the [EIP-5164](https://eips.ethereum.org/EIPS/eip-5164) cross-chain execution standard using the MessageDispatcher/MessageExecutor pattern:

- **MessageDispatcher** - Sends messages to another chain
- **MessageExecutor** - Receives and executes messages from another chain

This standard defines how cross-chain messages are structured, dispatched, and executed with proper context (messageId, fromChainId, sender).

### RNEndpointV1

The entry point coordinating cross-chain communication with the public chain.

**What it does:**

- Coordinates between dispatcher and executor components
- Manages the one-to-one connection to a specific public chain
- Handles message routing in both directions

### RNMessageDispatcherV1

Implements the EIP-5164 MessageDispatcher interface for outgoing messages.

**What it does:**

- Encodes messages for cross-chain transport to public chain
- Emits `MessageDispatched` events for Relayer detection
- Manages message metadata and sequencing

### RNMessageExecutorV1

Implements the EIP-5164 MessageExecutor interface for incoming messages.

**What it does:**

- Validates incoming messages from public chain
- Prevents reentrancy attacks
- Ensures only authorized relayers can execute messages

### RNContractFactoryV1

Deploys contracts using CREATE2 for deterministic addresses.

**What it does:**

- Deploys token contracts on demand
- Ensures same contract address across chains
- Uses bytecode from ResourceRegistry on the Hub

### Governance Contracts

See [Governance Contracts](governance.md) for details on:

- **RNUserGovernanceV1** - Address pair management (public ↔ private mapping)
- **RelayAuthorizationRegistry** - Authorized relayers for public chain messages

Public-chain token bridging is no longer a separate governance contract. It is driven by the [PN Token Registry](pn-token-registry.md) (`submitToPublicChain`, with the relayer calling `updatePublicTokenAddress`).

---

**Navigate:**

- [Back to Smart Contracts Overview](index.md)
