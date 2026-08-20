# Circuits

The Gnark API implements six circuit families for different privacy-preserving operations. Each circuit defines constraints that must be satisfied to generate a valid proof.

---

## Circuit Families

| Circuit | K Values | Purpose |
|---------|----------|---------|
| **Enygma Transfer** | 2-6 | Private transfers between K parties |
| **Enygma Deposit** | 2-6 | Deposit funds into the system |
| **Enygma Withdraw** | 2-6 | Withdraw funds from the system |
| **Enygma Join-Split** | Single | Atomic join-split operations |
| **ERC-721 Ownership** | Single | Prove NFT ownership privately |
| **ERC-1155 Join-Split** | Single | Multi-token join-splits |

---

## K-Parameterized Circuits

The K parameter determines the number of participants in a transaction:

- **K=2**: Two parties (sender + recipient)
- **K=3**: Three parties (1 sender + 2 recipients, or vice versa)
- **K=4, 5, 6**: Larger multi-party transactions

Higher K values increase circuit complexity and proof generation time, but enable more complex transaction patterns.

---

## Enygma Transfer

Enables private transfers between K participants:

**What it proves:**
- Sender owns sufficient balance (without revealing the amount)
- Transaction values sum correctly (balance conservation)
- Sender is a valid participant in the batch
- No double-spending (via nullifier)

**Key constraints:**
- Sender membership in participant list
- Pedersen commitment validation
- Balance conservation (inputs = outputs)
- Range proofs on amounts

---

## Enygma Deposit

Proves deposits into the privacy pool:

**What it proves:**
- Deposit amount matches commitment
- Depositor owns the funds
- Deposit is linked to correct address

**Additional parameters:** Hash, public key for deposit, address

---

## Enygma Withdraw

Proves withdrawals from the privacy pool:

**What it proves:**
- Withdrawal amount is valid
- Withdrawer has sufficient balance
- Previous deposits support the withdrawal

**Additional parameters:** Deposit hashes, deposit secrets, per-deposit values

---

## Enygma Join-Split

Handles atomic join-split operations for Enygma notes:

**Specifications:**
- Inputs: 10 notes maximum
- Outputs: 2 notes
- Merkle tree depth: 8

**What it proves:**
- Input notes exist in the Merkle tree
- Input values sum to at least output values
- Nullifiers are correctly computed
- Output commitments are valid

---

## ERC-721 Ownership

Proves ownership of an NFT without revealing the owner's identity:

**Specifications:**
- Inputs: 1 note
- Outputs: 1 note
- Merkle tree depth: 8

**What it proves:**
- Prover knows the private key for the note
- Note exists in the Merkle tree
- Unique ID is preserved across the transfer

---

## ERC-1155 Join-Split

Handles multi-token join-splits for ERC-1155 tokens:

**Specifications:**
- Inputs: 10 notes maximum
- Outputs: 2 notes
- Merkle tree depth: 8

**Difference from Enygma Join-Split:**
- Includes contract address and token ID
- Unique ID computed from: contract + tokenId + amount

---

## Cryptographic Building Blocks

The circuits use these cryptographic primitives:

| Primitive | Purpose |
|-----------|---------|
| **Pedersen Commitment** | Hide values: `C = value × G + random × H` |
| **Poseidon Hash** | Compute nullifiers, unique IDs |
| **BabyJubJub Curve** | Elliptic curve operations inside circuits |
| **Merkle Proof** | Prove set membership (depth 8) |
| **Range Proof** | Ensure values are non-negative |

---

## Nullifiers

Nullifiers prevent double-spending:

```
nullifier = Poseidon(privateKey, blockNumber)
```

- Unique per note and block
- Published on-chain when spending
- Checked against nullifier set to detect reuse

---

## Commitments

Values are hidden using Pedersen commitments:

```
commitment = value × G + randomness × H
```

Where:
- `G`, `H` are generator points on BabyJubJub
- `value` is the hidden amount
- `randomness` provides hiding

This allows proving properties about values without revealing them.

---

**Navigate:**

- [Back to Gnark API Overview](index.md)
- [Proving Keys](proving-keys.md) - Key management and Git LFS
