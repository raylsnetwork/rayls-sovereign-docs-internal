# Glossary

Key terms used throughout the Enygma documentation.

---

## A

### Anonymity Set
The group of participants included in a batch. An observer cannot determine which participant initiated a transfer within this set. Enygma supports k=2 through k=6, matching the number of registered Privacy Nodes (capped at 6).

### Authorized Address
A contract address that has been granted permission to interact with the Endpoint for cross-chain messaging. Token contracts must be authorized via `endpoint.addAuthorizedAddresses()` before they can send cross-chain transfers.

---

## B

### BabyJubJub Curve
The elliptic curve used by Enygma for cryptographic operations. It's embedded within BN254 (used by Ethereum), making it efficient for zero-knowledge proof verification on-chain.

### Batch
A collection of transfers grouped together for proof generation. All transfers in a batch share a single ZK proof, reducing gas costs. Rules: one batch per chain ID, one batch per resource ID.

### Blinding Factor
See [R Value](#r-value).

### BN254
The elliptic curve used by Ethereum for pairing-based cryptography. Enygma uses BN254's precompiled contracts to verify Groth16 proofs efficiently.

---

## C

### Callable
An optional action that executes on the destination chain after a transfer completes. Each transfer can include up to 5 callables (contract calls with payload).

### Commitment
A cryptographic hash that hides a value while binding the committer to it. In Enygma, balances are stored as Pedersen commitments: `C = value × G + randomness × H`. See [Pedersen Commitment](#pedersen-commitment).

### Conservation Law
The mathematical guarantee that the sum of all balance commitments equals the total supply commitment. This ensures no tokens can be created or destroyed except through proper mint/burn operations.

### crossMint()
Function called by the destination relayer to mint tokens to the recipient after a cross-chain transfer is verified.

### crossTransfer()
Function called by users to initiate a cross-chain private transfer. Burns tokens on source chain and triggers the proof generation process. Supports multiple recipients across different chains in a single call.

---

## D

### Discrete Logarithm Problem (DLP)
The mathematical problem underlying Enygma's security: given a point P = n × G, it's computationally infeasible to find n. Breaking DLP would compromise all commitments.

---

## E

### Endpoint
The core Rayls contract deployed on each Privacy Node Ledger that handles cross-chain messaging. Contracts must be authorized with the Endpoint to send cross-chain messages. The Endpoint resolves Resource IDs to contract addresses and routes messages through the Relayer.

### Empty Batch
A batch with no transfers, submitted to trigger finalization of pending transactions. Required to advance the block state machine.

### EnygmaTeleport
The contract on the Hub that broadcasts events to all relayers. Emits `EnygmaTransfer` and `BalancesFinalized` events.

### EnygmaV1
The core coordinator contract on the Private Network Hub. Manages balance commitments, verifies proofs, and processes transfers.

---

## F

### Finalization
The process of committing pending transactions to permanent state. Triggered by an empty batch. After finalization, balance commitments are immutable at that block number.

---

## G

### Generator Point (G)
A fixed point on the BabyJubJub curve used to encode values. The "value" generator in Pedersen commitments.

### gnark-api
The proof generation service that creates Groth16 proofs. Endpoints: `/gen-proof-k` for k=2 through k=6 (e.g., `/gen-proof-2`, `/gen-proof-3`, ..., `/gen-proof-6`).

### Groth16
The zero-knowledge proof system used by Enygma. Properties: small proof size (~200 bytes), fast verification (O(1)), non-interactive.

---

## H

### H Point
A second generator point on the BabyJubJub curve, used for the randomness/blinding component in Pedersen commitments. Derived independently from G to ensure security.

### Hiding Property
A commitment's ability to conceal the underlying value. Given only the commitment point, observers cannot determine what value was committed.

### Homomorphic Property
The ability to perform arithmetic on commitments. Adding two Pedersen commitments produces a commitment to the sum of values: `C1 + C2 = Commit(v1 + v2, r1 + r2)`.

### Hub
See [Private Network Hub](#private-network-hub).

---

## K

### k-Anonymity
Privacy property where each transfer is indistinguishable from k-1 other potential transfers. Enygma supports k=2 through k=6. With k=2, an observer has 50% chance of guessing correctly; with k=6, approximately 17%.

### KMM (Key Management Module)
Rayls' secure key management system that stores BabyJubJub secret keys. Keys never leave the Privacy Node; only proofs are transmitted.

---

## L

### linearCrossTransfer()
A simplified version of `crossTransfer()` for single-recipient transfers. Takes individual parameters instead of arrays, making it easier to use for 1-to-1 transfers with optional single callable.

---

## N

### Nullifier
A unique value derived through a multi-step Poseidon hash chain that prevents double-spending. Each nullifier can only be used once within a pending block window.

```
shared_secret    = Poseidon(previousR, secret_key)
arrayHashSecret  = Poseidon(shared_secret, shared_secret)
nullifier        = Poseidon(arrayHashSecret, blockNumber)
```

---

## P

### Pedersen Commitment
A cryptographic commitment scheme: `C = v × G + r × H`. Properties: hiding (value unknown from C), binding (can't change value), homomorphic (can add commitments).

### Pending Transaction
A transfer that has been verified but not yet finalized. Stored in `pendingTransactions` array until finalization.

### Privacy Node Ledger (PN)
An individual blockchain operated by a participant. Users interact with Enygma through the RaylsEnygmaHandler contract on their Privacy Node Ledger.

### Private Network Hub
The central blockchain that coordinates all Privacy Node Ledgers. EnygmaV1 and related contracts are deployed here.

### Proof
See [Groth16](#groth16). A cryptographic proof that demonstrates a statement is true without revealing why.

### Public Signal
The public inputs to a Groth16 proof. Includes: array hash secrets, public keys, previous commitments, output commitments, nullifier, block number, k-index values, and message tags (total: 8k + 2 values). These values are verified on-chain.

---

## R

### R Value
The random blinding factor in a Pedersen commitment. Each batch has a single R value shared by all transfers in that batch. Essential for the hiding property.

### RaylsEnygmaHandler
The user-facing contract deployed on each Privacy Node Ledger. Functions: `crossTransfer()`, `mint()`, `burn()`, `crossMint()`.

### Reference Balance
The balance commitment stored on-chain: `referenceBalance[blockNumber][chainId] = Point`. Represents the committed balance at a specific block for a specific chain.

### Reference ID
A unique identifier for each transfer, derived from source chain, sender, recipients, and block data. Used to track transfer status (SENT → RECEIVED).

### ReferenceIdStatus
Enum tracking the lifecycle of a transfer. Values: `NOSTATUS` (0), `SENT` (1), `RECEIVED` (2), `DEPOSITED` (3), `WITHDRAW_ASKED` (4), `WITHDRAW_RECEIVED` (5). Query with `referenceIdsStatus(referenceId)`.

### Relayer
The off-chain service that coordinates Enygma operations. Responsibilities: listen for events, batch transfers, generate proofs, submit to Hub, distribute to destinations.

### Resource ID
A unique identifier for an Enygma token across all chains. Used to track which token a transfer involves.

---

## S

### Scalar Multiplication
Multiplying a curve point by a number: `n × G = G + G + ... + G` (n times). Computationally efficient with double-and-add algorithm.

### Secret Key
The BabyJubJub private key that proves ownership of balance commitments. Never transmitted; stored securely in KMM.

---

## T

### Total Supply
The sum of all token balances. Tracked as both a scalar (`totalSupply`) and a curve point (`totalSupplyX`, `totalSupplyY`) for verification.

### transferBatch()
The main function on EnygmaV1 that processes batched transfers. Verifies the Groth16 proof and updates state.

---

## V

### Verifier Contract
Smart contract that verifies Groth16 proofs on-chain. Each k value (2 through 6) has its own verifier contract due to different public signal sizes.

---

## Z

### Zero-Knowledge Proof
A proof that demonstrates a statement is true without revealing any information beyond the statement's validity. Enygma uses ZK proofs to verify transfers without revealing amounts.

---

**Back to:** [Enygma Overview](index.md)
