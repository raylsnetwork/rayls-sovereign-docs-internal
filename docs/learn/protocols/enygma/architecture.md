# Architecture

The components and structure of the Enygma protocol.

## Three-Layer Architecture

Enygma operates across three distinct layers:

```mermaid
flowchart TB
    subgraph PN["PRIVACY NODE LEDGER LAYER"]
        direction LR
        PLA["RaylsEnygmaHandler<br/>(PN A)<br/>• crossTransfer()<br/>• mint() / burn()"]
        PLB["RaylsEnygmaHandler<br/>(PN B)<br/>• crossMint()<br/>• mint() / burn()"]
        PLC["..."]
    end

    subgraph HUB["PRIVATE NETWORK HUB LAYER"]
        direction TB
        EnygmaV1["EnygmaV1<br/>• transferBatch() - Process batched transfers<br/>• updateSupply() - Handle mints and burns<br/>• Verify Groth16 proofs<br/>• Track balance commitments<br/>• Manage pending transactions"]

        subgraph HubContracts[" "]
            direction LR
            Teleport["EnygmaTeleport<br/>• Emit events<br/>• Signal relayers"]
            Curve["CurveBabyJubJub<br/>• Point math<br/>• Commitments"]
            ZkDvpInt["EnygmaZkDvp<br/>Integration<br/>• ZkDVP bridge"]
        end
    end

    subgraph RELAY["RELAYER & PROOF LAYER"]
        direction LR
        Relayer["Relayer<br/>• Batch txs<br/>• Request proofs<br/>• Submit to Hub<br/>• Distribute"]
        GnarkAPI["gnark-api<br/>• /gen-proof-2<br/>• /gen-proof-6<br/>• Groth16 proving"]
        Relayer <--> GnarkAPI
    end

    PLA & PLB -->|"Events & Messages"| EnygmaV1
    EnygmaV1 --> HubContracts
    HUB -->|"Proof Requests"| RELAY
```

## Smart Contracts

### EnygmaV1 (Core Coordinator)

The central contract on the Private Network Hub that manages all Enygma token state.

**Key State Variables:**

```solidity
// Token metadata
string private name;
string private symbol;
uint8 private decimals;

// Total supply as a curve point
uint256 public totalSupplyX;
uint256 public totalSupplyY;
uint256 public totalSupply;  // Scalar value

// Balance commitments per block and chain
mapping(uint256 => mapping(uint256 => EnygmaPointWithChainId)) public referenceBalance;
// referenceBalance[blockNumber][chainId] = Point(c1, c2, chainId)

// Verifier contracts for each k value
mapping(uint256 => address) public transferVerifiers;
// transferVerifiers[k] = verifier contract address

// Pending state
PendingTransaction[] public pendingTransactions;
PendingMintOrBurn[] public pendingMintsAndBurns;
```

**Key Functions:**

| Function | Purpose |
|----------|---------|
| `transferBatch()` | Process a batch of private transfers with ZK proof |
| `updateSupply()` | Handle mint or burn operations |
| `finalisePendingTransactions()` | Advance the block state machine |
| `processPendingActions()` | Apply pending mints/burns to total supply |

The `transferBatch()` function applies a `checkFreeze` modifier that queries the `TokenFreezeManager` (via `TokenRegistry`) to verify the token is not frozen on the current chain before processing. If the token is frozen, the transaction reverts. See [Token Freezing](../../governance/tokens.md#token-freezing) for details.

### RaylsEnygmaHandler (User Interface)

Deployed on each Privacy Node Ledger, this is what users interact with.

**Key Functions:**

| Function | Purpose |
|----------|---------|
| `mint()` | Create new tokens (owner only) |
| `burn()` | Destroy tokens (owner only) |
| `crossTransfer()` | Initiate cross-chain private transfer |
| `crossMint()` | Receive tokens from cross-chain transfer |
| `depositToZkDvp()` | Send tokens to ZkDVP for atomic swaps |
| `callWithdrawFromZkDvp()` | Request withdrawal from ZkDVP |

**Programmability:**

Each transfer can include up to 5 "callables" - actions to execute on the destination:

```solidity
struct EnygmaCrossTransferCallable {
    bytes32 resourceId;       // Target contract by resource ID
    address contractAddress;  // OR direct address
    bytes payload;            // Call data to execute
}
```

### EnygmaTeleport (Event Broadcaster)

Emits events that relayers listen for to coordinate cross-chain operations.

**Key Events:**

```solidity
// Signals a transfer batch was submitted
event EnygmaTransfer(bytes32 indexed resourceId, uint256 indexed toChainId, bytes encryptedMessage);

// Signals balances are finalized for a block
event BalancesFinalized(bytes32 indexed resourceId, uint256 indexed finalizedBlockNumber, ...);

// Signals supply was updated
event EnygmaSupplyUpdated(bytes32 indexed resourceId, uint256 indexed blockNumber, ...);
```

### CurveBabyJubJub (Cryptography Library)

Pure math functions for elliptic curve operations.

**Key Functions:**

| Function | Purpose |
|----------|---------|
| `pointAdd()` | Add two curve points |
| `pointDouble()` | Double a curve point |
| `derivePk()` | Compute v×G (scalar multiplication) |
| `derivePkH()` | Compute r×H (scalar multiplication with H) |
| `pedCom()` | Compute v×G + r×H (Pedersen commitment) |
| `isOnCurve()` | Verify a point is on the curve |

### EnygmaZkDvpIntegration (ZkDVP Bridge)

Enables Enygma tokens to participate in ZkDVP atomic swaps.

**Key Functions:**

| Function | Purpose |
|----------|---------|
| `depositToZkDvp()` | Deposit Enygma commitment into ZkDVP |
| `withdrawFromZkDvp()` | Withdraw from ZkDVP back to Enygma |
| `consolidateFunds()` | Merge multiple ZkDVP deposits |

## Data Structures

### EnygmaTransferBatch

Represents a batch of transfers to process together:

```solidity
struct EnygmaTransferBatch {
    string ResourceId;              // Token identifier
    *big.Int BlockNumberCC;         // Block number on Hub
    *big.Int FromChainID;           // Source chain
    *big.Int ToChainID;             // Destination chain
    *big.Int ToRValueToAdd;         // R-factor for this chain
    []*EnygmaTransferBatchTx Transactions;  // Individual transfers
}
```

### EnygmaTransferBatchTx

A single transfer within a batch:

```solidity
struct EnygmaTransferBatchTx {
    [32]byte ReferenceId;           // Unique identifier
    common.Address FromAddress;     // Sender
    *big.Int ToAmount;              // Transfer amount
    common.Address ToAddress;       // Recipient
    []EnygmaCrossTransferCallable ToCallables;  // Actions to execute
}
```

### Point

A point on the BabyJubJub curve:

```solidity
struct Point {
    uint256 c1;  // X coordinate
    uint256 c2;  // Y coordinate
}
```

### EnygmaPointWithChainId

A point associated with a specific chain:

```solidity
struct EnygmaPointWithChainId {
    uint256 c1;      // X coordinate
    uint256 c2;      // Y coordinate
    uint256 chainId; // Associated chain
}
```

### TransferProof

The Groth16 proof structure:

```solidity
struct TransferProof {
    uint256[2] pi_a;         // Proof element A
    uint256[2][2] pi_b;      // Proof element B (2x2 matrix)
    uint256[2] pi_c;         // Proof element C
    uint256[] public_signal; // Public inputs (size varies by k)
}
```

### PendingTransaction

A transfer awaiting finalization:

```solidity
struct PendingTransaction {
    EnygmaPointWithChainId[] pointsToAddToBalance;  // Output commitments
    uint256 nullifier;                              // Prevents double-spend
    TxType transactionType;                         // Transfer/Deposit/Withdraw
}
```

### Transaction Types

```solidity
enum TxType {
    Creation,   // 0 - Initial token creation
    Mint,       // 1 - New tokens minted
    Burn,       // 2 - Tokens destroyed
    Transfer,   // 3 - Standard transfer
    Deposit,    // 4 - Deposit to ZkDVP
    Withdraw    // 5 - Withdraw from ZkDVP
}
```

## Relayer Components

### EnygmaBatchingService

Orchestrates the batching and proof generation process:

- Groups transactions by resource ID and chain ID
- Enforces batch limits (default: 1000 tx per batch)
- Manages k-anonymity set fulfillment
- Coordinates with proof service
- Handles retries and errors

### EnygmaProofService

Interfaces with the gnark-api for proof generation:

- Prepares proof inputs (keys, balances, commitments)
- Calls appropriate proof endpoint (/gen-proof-k, where k=2 to 6)
- Parses and validates proof responses
- Generates random factors for commitments

### EnygmaSyncService

Maintains state consistency:

- Validates checkpoint finalization
- Syncs database state with on-chain state
- Handles discrepancy resolution

## Batching Flow

The complete batching process from user transactions to final distribution:

```mermaid
flowchart TB
    subgraph users["USER TRANSACTIONS"]
        direction LR
        Alice["Alice<br/>crossTransfer()"]
        Bob["Bob<br/>crossTransfer()"]
        Jack["Jack<br/>crossTransfer()"]
    end

    subgraph handler["PRIVACY NODE LEDGER"]
        EnygmaHandler["RaylsEnygmaHandler<br/>• Burns tokens<br/>• Emits EnygmaSendTransferCC event"]
    end

    subgraph relayer["RELAYER BATCHING"]
        direction TB
        PLListener["PN Listener<br/>Collects transfer events"]

        subgraph sorting["BATCH ORGANIZATION"]
            direction LR
            SortResource["Sort by<br/>Resource ID"]
            SortChain["Sort by<br/>Chain ID"]
            SortResource --> SortChain
        end

        rules["Batching Rules:<br/>• 1 batch per chain ID<br/>• 1 batch per resource ID<br/>• 1 batch has many txs<br/>• 1 R value per batch"]

        PLListener --> sorting --> rules
    end

    subgraph anonymity["K-ANONYMITY DETERMINATION"]
        direction LR
        k2["PLs involved = 2<br/>→ k = 2"]
        k2alt["PLs involved = 4<br/>→ k = 2"]
        k6["PLs involved = 6<br/>→ k = 6"]
    end

    subgraph proofgen["PROOF GENERATION (gnark-api)"]
        direction LR
        GenProof2["/gen-proof-2<br/>(2 participants)"]
        GenProof6["/gen-proof-6<br/>(6 participants)"]
    end

    subgraph execution["HUB EXECUTION"]
        direction TB
        Encrypt["Encrypt batches<br/>(per destination)"]
        TransferBatch["transferBatch()<br/>on EnygmaV1"]
        Verify["Verify Groth16 proof<br/>Update balance commitments"]
        Teleport["EnygmaTeleport<br/>Emit BalancesFinalized"]

        Encrypt --> TransferBatch --> Verify --> Teleport
    end

    subgraph distribution["RELAYER DISTRIBUTION"]
        direction TB
        subgraph relayerA["Relayer A (Source)"]
            RA["Responsibility:<br/>Nothing to mint<br/>(tokens already burned)"]
        end
        subgraph relayerB["Relayer B (Destination)"]
            RB["Responsibility:<br/>Mint all transactions<br/>Execute callables"]
        end
        subgraph relayerC["Relayer C (Passthrough)"]
            RC["Responsibility:<br/>Update R value only<br/>(no mints/burns)"]
        end
    end

    subgraph finalize["FINALIZATION"]
        direction TB
        Decrypt["Decrypt batch<br/>for this chain"]
        CrossMint["crossMint()<br/>on destination PN"]
        Execute["Execute callables<br/>(if any)"]
        Success["Transfer Complete"]

        Decrypt --> CrossMint --> Execute --> Success
    end

    users --> handler --> relayer
    relayer --> anonymity --> proofgen
    proofgen --> execution
    execution --> distribution --> finalize
```

### Batching Rules Detail

| Rule | Description |
|------|-------------|
| **One batch per chain ID** | All transfers to the same destination chain are grouped together |
| **One batch per resource ID** | Each token type is batched separately |
| **Multiple transactions per batch** | A single batch can contain many individual transfers |
| **One R value per batch** | Each batch uses a single random factor for commitment blinding |

### Relayer Responsibilities

Different relayers have different roles based on their relationship to each transfer:

| Relayer Role | Action | Reason |
|--------------|--------|--------|
| **Source (A)** | Nothing | Tokens already burned on source PN |
| **Destination (B)** | Mint all txs | Must create tokens for recipients |
| **Passthrough (C)** | Update R only | Part of anonymity set but no local transfers |

### Data Flow

```mermaid
flowchart LR
    subgraph input["INPUT DATA"]
        Tx1["EnygmaTransferBatchTx<br/>• referenceId<br/>• fromAddress<br/>• toAmount<br/>• toAddress<br/>• callables"]
        Tx2["EnygmaTransferBatchTx"]
        Tx3["EnygmaTransferBatchTx"]
    end

    subgraph batch["BATCH STRUCTURE"]
        Batch["EnygmaTransferBatch<br/>• resourceId<br/>• blockNumberCC<br/>• fromChainID<br/>• toChainID<br/>• toRValueToAdd<br/>• transactions[]"]
    end

    subgraph proof["PROOF GENERATION"]
        Inputs["Proof Inputs:<br/>• Old balance commitments<br/>• New balance commitments<br/>• Chain IDs<br/>• Random factors"]
        Proof["Groth16 Proof:<br/>• pi_a, pi_b, pi_c<br/>• public_signals"]
    end

    subgraph onchain["ON-CHAIN"]
        Call["transferBatch(<br/>  k,<br/>  commitments[],<br/>  proof,<br/>  chainIds[],<br/>  encryptedBatches[]<br/>)"]
    end

    input --> batch --> proof --> onchain
```

## Component Interaction

User wants to send 100 Enygma tokens from PN A to PN B:

```mermaid
sequenceDiagram
    participant User
    participant PN_A as RaylsEnygmaHandler (PN A)
    participant Relayer_A as Relayer A
    participant Gnark as gnark-api
    participant Hub as EnygmaV1 (Hub)
    participant Relayer_B as Relayer B
    participant PN_B as RaylsEnygmaHandler (PN B)

    User->>PN_A: crossTransfer([addressB], [100], [chainIdB], [])
    PN_A->>PN_A: Burns tokens
    PN_A-->>Relayer_A: EnygmaSendTransferCC event

    Relayer_A->>Relayer_A: Groups with other transfers
    Relayer_A->>Gnark: /gen-proof-{k} with inputs
    Gnark-->>Relayer_A: Groth16 proof

    Relayer_A->>Hub: transferBatch(k, commitments, proof, chainIds, encryptedBatches)
    Hub->>Hub: Freeze check, verifies proof, updates state
    Hub-->>Relayer_B: BalancesFinalized event (via EnygmaTeleport)

    Relayer_B->>Relayer_B: Decrypts batch
    Relayer_B->>PN_B: crossMint()
    PN_B->>PN_B: Mints tokens to recipient
    PN_B-->>User: Transfer complete
```

---

**Next:** [The Proof System](the-proof-system.md) - How batching and k-anonymity work in detail.
