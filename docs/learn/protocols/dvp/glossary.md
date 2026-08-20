# Glossary

Key terms used throughout the DVP documentation.

---

## A

### AssetGroup

A grouping of CoinVaults that defines which vaults can be paired for swaps and exchanges. Each group maintains its own Merkle tree to track token membership.

| Group ID | Name             | Contains                |
| -------- | ---------------- | ----------------------- |
| 0        | Fungibles        | Enygma, ERC20           |
| 1        | Non-Fungibles    | ERC721, ERC1155         |

### Atomic Swap

An exchange where both parties' transactions either complete together or both fail. In DVP, this means the asset transfer and payment happen simultaneously — there is no state where one party has both assets.

---

## C

### CoinVault

A smart contract that manages a specific asset type within DVP. Each CoinVault inherits from `AbstractCoinVault` (which inherits from `Merkle.sol`), combining an incremental Poseidon Merkle tree with asset-specific deposit, withdraw, and transfer logic.

| CoinVault            | Token Type ID | Asset                  |
| -------------------- | ------------- | ---------------------- |
| `Erc721CoinVault`    | 2             | ERC-721 NFTs           |
| `Erc1155CoinVault`   | 3             | ERC-1155 multi-tokens  |
| `EnygmaCoinVault`    | 4             | Enygma privacy tokens  |

### Coin Locking

The mechanism that reserves an initiator's input coins between `initiateSwap` and either `completeSwap` (settlement) or `cancelSwap` / `expireSwap` (refund). When `Dvp.initiateSwap` is called, each input nullifier is added to the CoinVault's `lockedNullifiers` mapping via `lockCoin`. Locked coins cannot be spent in any other transaction. `completeSwap` unlocks and nullifies them in the same call; `cancelSwap` / `expireSwap` unlocks them and registers the [revert commitment](#revert-commitment) instead.

### Commitment

A cryptographic hash that binds a user to a value without revealing it. In DVP, commitments represent ownership of assets within CoinVault Merkle trees. Each asset type uses a different formula — see [Unique ID](#unique-id) for the per-vault commitment shape. ERC-721 and ERC-1155 commitments include a per-deposit [salt](#salt) so two commitments to the same note data are indistinguishable.

See also: [Pedersen Commitment](../enygma/glossary.md#pedersen-commitment).

### Cancel Preimage

The Poseidon hash of the underlying salt — `poseidon(destSalt)` — stored by the relayer as `swap.CancelPreimage` at swap creation time. Passed to `Dvp.cancelSwap(sharedId, preimage)` on the Hub; the contract verifies `poseidon([preimage, preimage]) == passphrase` before allowing the cancellation. Both the initiator and the responder derive the same preimage (from the same `destSalt`), so either side can cancel. See [Swap Cancellation: Passphrase Derivation](swap-cancellation.md#passphrase-derivation).

### Cancellation

The process of terminating an in-progress swap. Can be triggered manually by calling `cancelSwap()` on the token handler contract, or automatically when the swap's [validity time](#validity-time) expires. Manual cancellation uses `Dvp.cancelSwap(sharedId, preimage)` which verifies the [cancel preimage](#cancel-preimage) against the [passphrase](#passphrase-cancel) committed at `initiateSwap`. Automatic expiration uses `Dvp.expireSwap(sharedId)`. Both paths transition the contract's [SwapStatus](#swapstatus) to `Cancelled` or `TimedOut` and register the initiator's [revert commitment](#revert-commitment) to their vault. See [Swap Cancellation](swap-cancellation.md) for details.

### Consolidation

The process of merging multiple small coins into fewer larger ones via `mixFunds()`. Required when a user has more coins than the JoinSplit proof can handle (max 10 inputs). A JoinSplit ProofReceipt consumes up to 10 input coins and produces 2 output coins.

---

## D

### Deposit

The process of moving an asset from standard on-chain representation into the DVP system. Creates a commitment in the appropriate CoinVault's Merkle tree that can be used in swaps.

### DVP (Delivery versus Payment)

A settlement mechanism where delivery of an asset occurs if and only if payment is made. Rayls DVP adds zero-knowledge proofs to enable private DVP transactions.

### Dvp.sol

The central orchestrator contract deployed on the Private Network Hub. Owns the swap state machine (`initiateSwap`, `completeSwap`, `cancelSwap`, `expireSwap`, `isSwapExpired`) and delegates to CoinVaults for all tree operations, proof verification, and nullifier lock/unlock/spend management.

### DvpTeleport

The **event-only** contract on the Private Network Hub. It exposes a small set of `emit*` hooks that are callable only by the authorized `Dvp` contract, CoinVaults, factories, or relayer. It emits the cross-chain `SwapInitiated` / `SwapCompleted` / `SwapCancelled` / `SwapTimedOut` events plus the per-vault `Commitments` / `Nullifier` events. Transactional swap methods are no longer on this contract — they all moved to `Dvp` in v2.

### dvpId

The internal swap identifier used inside the `Dvp` contract. Computed as `keccak256(commitments[0], message)` on the initiator side and `keccak256(message, commitments[0])` on the responder side — the asymmetric ordering means the responder's `(message, commitments[0])` must equal the initiator's `(commitments[0], message)` for the lookup to succeed. This is the binding between the two on-chain calls. The user-facing identifier is the [shared ID](#shared-id), which the contract maps to `dvpId` via `_sharedIdToDvpId`.

---

## E

### Enygma Integration

The combination of DVP atomic swaps with Enygma privacy tokens via the `EnygmaDvpIntegration` bridge contract. Allows swapping NFTs for privacy-preserving fungible tokens where the payment amount remains hidden.

---

## I

### Initiate / Complete (2-phase swap)

The two halves of a v2 DVP swap. The party whose transaction lands first becomes the **initiator** — their relayer submits `Dvp.initiateSwap`, which locks their input nullifiers and emits `SwapInitiated`. The other party becomes the **responder** — their relayer submits `Dvp.completeSwap`, which unlocks the initiator's nullifiers, spends them, and inserts both new commitments in a single transaction. Roles are determined dynamically by which transaction arrives first; both parties run the same CLI command pattern.

---

## J

### JoinSplit Proof

A zero-knowledge proof used for fungible token operations (ERC1155, Enygma). Proves that multiple input UTXOs are combined and split into new outputs while conserving total value. Named for its ability to "join" inputs and "split" outputs.

Properties:

- Up to 10 inputs, 2 outputs
- Proves value conservation
- Hides individual amounts

---

## M

### Merkle Root

The top hash of a Merkle tree that uniquely represents all commitments in the tree. DVP proofs include the Merkle root to prove membership without revealing which specific commitment is being spent.

### Merkle Tree

A binary tree structure where each leaf is a commitment and each parent is the Poseidon hash of its children. Each CoinVault maintains its own independent Merkle tree. When a tree reaches capacity, a new tree version is created (`treeNumber` increments). Tree membership proofs are O(log n) in size.

### Message

A `uint256` field on `ProofReceipt`. Combined with `commitments[0]` to derive the [dvpId](#dvpid) that binds the initiator's `initiateSwap` and the responder's `completeSwap` into a single atomic swap. (Historically, v1 DVP also used `message` for paired-proof cross-references via `require(receipt1.message == receipt2.commitments[0], ...)` — that mechanism is gone in v2; atomicity is now enforced by the contract `SwapStatus` state machine.)

### ML-KEM Ciphertext

A 768-byte ML-KEM-768 (post-quantum KEM) ciphertext attached to every `SwapInitiated` event. The initiator's relayer encapsulates against the responder's view public key to derive a shared secret used as a per-swap [salt](#salt) for AES-GCM encryption of the trade message. Only the responder can decapsulate the ciphertext and recover the salt to decrypt the message.

---

## N

### Nullifier

A unique value derived from the owner's secret key and the coin's position in the Merkle tree that prevents double-spending:

```text
nullifier = Poseidon(secretKey, pathIndex) mod BN254
```

When a coin is spent, its nullifier is recorded permanently in the CoinVault. Attempting to spend the same coin again produces the same nullifier, which is rejected. See also: [Nullifier](../enygma/glossary.md#nullifier).

---

## O

### Ownership Proof

A zero-knowledge proof used for NFT operations (ERC721). Proves ownership of a specific token without revealing which commitment in the tree is being spent.

Properties:

- 1 input, 1 output
- Proves ownership transfer
- Simpler than JoinSplit

---

## P

### Passphrase (Cancel)

A Poseidon hash commitment — `poseidon([preimage, preimage])` — submitted to `Dvp.initiateSwap` and stored on-chain as part of the swap data. Gates manual cancellation: `Dvp.cancelSwap` must supply a [cancel preimage](#cancel-preimage) that hashes to this value. The passphrase is derived from the initiator's `destSalt`; both sides of the swap can derive the same preimage, so either can cancel. See [Swap Cancellation: Passphrase Derivation](swap-cancellation.md#passphrase-derivation).

### Poseidon

A ZK-friendly hash function used throughout DVP for commitments, unique IDs, nullifiers, and Merkle tree construction. Optimized for ZK circuits (~300 constraints per hash vs ~27,000 for Keccak256).

### ProofReceipt

The universal data structure for all DVP ZK operations, replacing the older `OwnershipTransaction` and `JoinSplitTransaction` types:

```solidity
struct ProofReceipt {
    SnarkProof proof;            // Groth16 proof (a, b, c)
    uint256[] treeNumbers;       // Merkle tree version per input
    uint256 message;             // Used (with commitments[0]) to derive dvpId
    uint256[] merkleRoots;       // Root per input
    uint256[] commitments;       // Output commitments
    uint256[] nullifiers;        // Input nullifiers
    uint256 revertCommitment;    // Pre-computed commitment registered on cancelSwap / expireSwap
}
```

JoinSplit receipts use exactly 10 entries in `treeNumbers` / `merkleRoots` / `nullifiers` (padded with the dummy nullifier in unused slots) and 2 commitments. Ownership receipts use exactly 1 of each.

### Proof Types

DVP uses two types of proofs depending on the asset:

| Proof Type  | Used For                  | Inputs | Outputs |
| ----------- | ------------------------- | ------ | ------- |
| Ownership   | ERC721                    | 1      | 1       |
| JoinSplit   | ERC1155, Enygma           | 10     | 2       |

---

## R

### Revert Commitment

A self-addressed output commitment baked into every DVP swap proof at initiation time. Computed inside the circuit from `(senderPK, revertSalt, tokenData…)` so it locks exactly the same value the proof is spending. On `Dvp.cancelSwap` (manual cancel) or `Dvp.expireSwap` (auto-timeout), the contract registers this commitment to the initiator's vault via `IAbstractCoinVault.registerCoins(...)`. The revert commitment is the reason cancel/timeout requires no second proof — Alice's funds are recoverable from the data she already submitted at `initiateSwap`.

---

## S

### Salt

A fresh, per-deposit `uint256` value mixed into every commitment so two commitments to the same note data are indistinguishable. Generated via ML-KEM-768 encapsulation against the recipient's view public key (the encapsulated ciphertext travels alongside the salt so the recipient can recover it). Required for ERC-721 and ERC-1155 commitments; ERC-20 commitments still use the v1 `H(uniqueId, publicKey)` formula without salt.

### Settlement

DVP swaps settle in a single 2-phase flow on the `Dvp` contract:

1. Initiator's relayer calls `Dvp.initiateSwap` — locks the initiator's input nullifiers and emits `SwapInitiated`.
2. Responder's relayer calls `Dvp.completeSwap` — unlocks, spends, and inserts both new commitments.

There is no longer a separate "Full" vs "Two-Phase" mode. The legacy `swap()` / `exchange()` / `submitPartialSettlement()` functions are commented out in `IDvp.sol` for historical reference only.

### Shared ID

A `bytes32` value that identifies a swap across chains. Both parties agree on it off-chain before initiating, and both transactions reference it. The `Dvp` contract uses `_sharedIdToDvpId[sharedId]` to look up the internal [dvpId](#dvpid) for the swap state machine. Also used to identify which swap to cancel via `Dvp.cancelSwap(sharedId, preimage)` or `Dvp.expireSwap(sharedId)`.

### SwapStatus

The on-chain enum in `Dvp` representing the swap state:

| Value | Name | Description |
|-------|------|-------------|
| 0 | `None` | No swap with this dvpId exists |
| 1 | `Pending` | `initiateSwap` succeeded; awaiting `completeSwap`, `cancelSwap`, or `expireSwap` |
| 2 | `Completed` | `completeSwap` settled the swap atomically |
| 3 | `Failed` | Reserved for future proof-verification failure reporting |
| 4 | `Cancelled` | `cancelSwap(sharedId, preimage)` succeeded (manual cancel) |
| 5 | `TimedOut` | `expireSwap(sharedId)` succeeded (post-`expiresAt`) |

The relayer maintains its own 8-value `DvpSwapStatus` enum (`Created`, `Initiated`, `InitiationFailed`, `WaitingConfirmation`, `Completed`, `Failed`, `Cancelled`, `TimedOut`) for off-chain bookkeeping.

---

## T

### Token Type ID

An identifier for the asset type managed by a CoinVault:

| Token Type ID | CoinVault            | Asset                 |
| ------------- | -------------------- | --------------------- |
| 2             | `Erc721CoinVault`    | ERC-721 NFTs          |
| 3             | `Erc1155CoinVault`   | ERC-1155 multi-tokens |
| 4             | `EnygmaCoinVault`    | Enygma privacy tokens |

### Tree Number

A version counter for a CoinVault's Merkle tree. When a tree reaches capacity, a new tree version is created and `treeNumber` increments. Proofs include `treeNumbers` to indicate which version each input coin belongs to.

---

## U

### Unique ID

An asset-specific identifier hashed into each commitment. Computed using chained 2-input Poseidon. ERC-721 and ERC-1155 commitments now combine the unique ID with `Poseidon(spendPK, salt)`; ERC-20 retains the v1 `Poseidon(uniqueId, publicKey)` shape:

| CoinVault            | Commitment formula                                                                  |
| -------------------- | ----------------------------------------------------------------------------------- |
| `Erc721CoinVault`    | `H(H(spendPK, salt), H(tokenAddress, nftId))`                                       |
| `Erc1155CoinVault`   | `H(H(H(H(spendPK, salt), tokenAddress), tokenId), amount)`                          |
| `Erc20CoinVault`     | `H(H(amount, tokenAddress), publicKey)`                                             |
| `EnygmaCoinVault`    | Caller-supplied (`hashCommitment`); see [Enygma Integration](enygma-integration.md) |

### UTXO (Unspent Transaction Output)

A model where balances are represented as discrete "outputs" that can be spent exactly once. DVP uses UTXOs for all asset types — each deposit creates an output (coin), and transfers consume outputs while creating new ones.

---

## V

### Validity Time

The duration for which a swap remains active before automatic expiration. Passed to `Dvp.initiateSwap` as `validityTime`; the contract stores `expiresAt = block.timestamp + validityTime` and emits it in the `SwapInitiated` event. The contract is the single source of truth for expiry — the relayer polls `Dvp.isSwapExpired(sharedId)` rather than mirroring a deadline locally.

| Parameter | Value |
|-----------|-------|
| Default | 2 days |
| Minimum | 5 hours |
| Maximum | 14 days |

When the validity time elapses, the next call to `Dvp.completeSwap` self-routes to `expireSwap(sharedId)`, and the relayer's expiration ticker calls `expireSwap(sharedId)` for any pending swap whose deadline has passed. See [Swap Cancellation](swap-cancellation.md#automatic-expiration).

---

## W

### Withdraw

The process of moving an asset from the DVP system back to standard on-chain representation. Requires a valid ProofReceipt proving ownership of the commitment. The CoinVault records the nullifier and releases the underlying asset.

---

**See also:**

- [DVP Overview](index.md)
- [Enygma Glossary](../enygma/glossary.md) - Related cryptographic terms
