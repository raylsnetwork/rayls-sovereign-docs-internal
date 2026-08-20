# Glossary

Official terminology for the Rayls ecosystem. Always use these terms when referring to Rayls components and concepts.

!!! note "Formerly Known As (fka)"
    Some terms have changed from previous documentation. We use "fka" to indicate the former name.

---

## User Roles & Personas

### Private Network Operator
**Formerly known as:** Governor

A governing financial institution that has installed and runs a Rayls Private Network - usually an FMI (Financial Market Infrastructure), Central Bank, or global bank.


---

### Rayls Privacy Node Operator

A transacting financial institution that has installed and runs a [Rayls Privacy Node](#rayls-sovereign-node) - usually a commercial bank.


---

### Private Network Auditor

A designated entity that is assigned Auditor View powers within a Private Network - usually a financial regulator.


---

### Rayls Private Validator

Financial institutions, selected by a Private Network Operator, that run a node of the Private Hub (e.g. Besu) of their Private Network, in order to decentralize the Hub network.

---

## Rayls Privacy Node

### Rayls Privacy Node
**Formerly known as:** Privacy Ledger (the complete infrastructure)

A private, fully EVM-compatible blockchain infrastructure that is installed privately on-premises or in a private cloud by a Rayls Privacy Node Operator (i.e. a transacting financial institution). Rayls Privacy Nodes (RPNs) contain one or more Ledgers and Relayers, which are spun up as required to form dedicated institution-internal chains and crosschain transaction bridges between Rayls Private Networks, the Rayls Public Chain and other public blockchains. A Rayls Privacy Node also contains a variety of governance, monitoring and integration components to enhance usability within regulated financial markets.

The Rayls Privacy Node therefore is a single infrastructure that can enable institutions to issue tokens, manage internal transaction operations and then seamlessly transfer value across many public and permissioned chains, in a fully private, controlled and compliant manner.

**Components:**
- [Privacy Node Ledger](#privacy-node-ledger)
- [Relayer](#relayer)
- [Key Management Module (KMM)](#key-management-module-kmm)
- [Privacy Node Dashboard](#privacy-node-dashboard)
- [Privacy Node Ledger Explorer](#privacy-node-ledger-explorer)

**Related:** [Privacy Node Components](../learn/components/architecture/privacy-node-components.md)

---

### Privacy Node Ledger
**Formerly known as:** Privacy Ledger (the blockchain component only)

A scalable, fully EVM-compatible ledger — **axyl**, a Rust client with a reth-based EVM execution layer and Narwhal + Bullshark BFT consensus (state stored in MDBX) — connecting an enterprise architecture with a full EVM chain for tokenization, onchain transactions, smart contract deployments and crosschain interoperability.

**Repository:** `axyl`


---

### Relayer

Facilitates secure and efficient communication between Rayls Privacy Node Ledgers, Private Hubs and Rayls Public Chain, ensuring that these transactions are properly validated and executed.

**Repository:** `rayls-sovereign-relayer`


---

### Key Management Module (KMM)
**Formerly known as:** Key Operation Service (KOS)

An internal module within the Rayls Privacy Node - one per Ledger - that manages secure and efficient cryptographic key operations, logs and connections to cloud HSM providers.


---

### Privacy Node SDK

Enables seamless integration with Rayls services using JavaScript or Python, offering full flexibility to embed Rayls functionalities, such as token operations, transaction management, and smart contract interactions—directly into your applications.

Built for blockchain interoperability, the SDK simplifies crosschain development by abstracting the complexities of working with diverse blockchain protocols.

**Supports:**
- Layer 3s (Rayls Private Networks)
- Layer 2s (Rayls Public Chain, powered by Arbitrum Orbit stack)


---

### Privacy Node API

A RESTful interface that enables applications and services to interact with the Rayls crosschain ecosystem in a secure and scalable manner.

**Capabilities:**
- Token transfers between Rayls Ecosystem networks
- Crosschain messaging and invoking smart contracts
- Transaction status tracking and event querying
- Network and asset discovery across Rayls chains


---

### Privacy Node Ledger Explorer

An integrated block explorer for Privacy Node internal transaction monitoring - one Explorer per Ledger.

---

### Privacy Node Dashboard

A web application that aggregates data across the Ledgers of a Rayls Privacy Node to provide consolidated monitoring and instruct onchain transactions across a range of transaction primitives - both internal to the Privacy Node and crosschain with other Private Networks and the Rayls Public Chain.

**Features:**
- Multi-chain institutional wallet
- Aggregated block explorer view
- Graphical, interactive insights dashboard
- Governance console

---

## Rayls Private Network

### Private Network Hub
**Formerly known as:** Commit Chain

A permissioned EVM blockchain (e.g. Besu / Quorum) that acts as the shared hub of the hub and spoke model to connect multiple Rayls Privacy Nodes to form a Rayls Private Network. All transactions between Rayls Privacy Nodes flow through and are recorded to the Private Network Hub, which is set up, run and governed by the Private Network Operator.


---

### Private Hub Node

A full node of the permissioned Private Hub blockchain (e.g. Besu / Quorum), enabling the node operator to hold a full copy of the ledger and all data of the Private Hub blockchain. Increasing the number of Private Hub nodes increases decentralization and redundancy of the Rayls Private Hub chain.

---

### Rayls Private Network

A network formed by connecting multiple Rayls Privacy Nodes through a Private Network Hub. The network is governed by a Private Network Operator and can be audited by a Private Network Auditor.

**Related:** [Private Network Hub](../learn/components/private-network-hub/index.md)

---

### Private Network Governance

The Private Network Operator is provided with a selection of governance capabilities that they can instruct to govern their Private Network, including:

**Capabilities:**
- **Registries** - Management of the Private Network participant registry, assigning and changing roles, token registry and registered token statuses
- **Governance contracts** - Power to freeze/unfreeze participant, freeze/unfreeze token, freeze/unfreeze token for a specific participant
- **Governance API** - A simple interface for the Private Network Operator to instruct governance actions

**Repository:** `rayls-sovereign-pnh-governance`


---

### Private Network Explorer

A block explorer displaying the encrypted transaction history data of the Private Hub. The Private Network Explorer is a shared utility, operated by the Private Network Operator, with permissioned access granted to all Rayls Privacy Nodes connected to the Private Hub.

Rayls Privacy Nodes can utilize this data to decrypt their own transactions and to confirm the status of Private Network crosschain transactions (RPN → Private Hub → RPN) - proving that they also completed successfully on the Private Hub, not only that the transaction executed on their Privacy Node Ledger.

---

### Auditor View

A feature enabling a designated Auditor role (e.g. a financial regulator) to decrypt and have unique view access to Private Hub data. This includes 4 elements:

1. Access to a list of Private Network participants, via the Private Hub participant registry
2. Access to a list of Private Network registered tokens, via the Private Hub token registry
3. Balances of each registered token held by each Privacy Node, which are automatically submitted by each Privacy Node as a ZK proof every few seconds to the Private Hub, then decrypted by the Auditor
4. A private block explorer, run and accessible only by the Auditor institution, with a fully decrypted record of all Private Hub transactions

Combined, by having access to these 4 data sources the Private Network Auditor has a real time view of all Private Network participants, tokens in circulation, balances held by each participant and transactions. This information can be used to monitor overall Private Network activity, flag inconsistencies and identify potentially fraudulent activity.


---

### Auditor Flagger

This component supports transaction processing and state validation, with built-in capabilities to detect double-spending or fraudulent activity within the Private Network. It serves as a tool for auditors to identify potential issues and notify the Private Network Operator. Through the governance mechanism, the operator can then take appropriate actions—such as freezing tokens, modifying participant roles, or enforcing other corrective measures on the Private Network.

---

### Operator Dashboard

A private web application providing the Private Network Operator with an interactive dashboard for participant management, governance rules and key custody.

---

### Auditor Dashboard

A private web application providing the Private Network Auditor with a visual dashboard of the Auditor View data.

---

## Protocols

### Teleport Atomic

An encrypted crosschain messaging and value transfer protocol, enabling transactions between two Rayls Privacy Nodes via the Private Hub.

**Features:**
- Crosschain arbitrary messaging
- Crosschain token transfers, supporting ERC-20, ERC-721 and ERC-1155 token standards
- Batch transaction processing - enabling hundreds of transactions on a Privacy Node to be bundled into one transaction on the Private Hub
- Automated transaction revert in the case of a failed transaction

**Related:** [Teleport Atomic Protocol](../learn/protocols/teleport-atomic/overview.md)

---

### Rayls Enygma

A private, zero knowledge (ZK) crosschain value transfer protocol with anonymity and confidentiality - deployed as a package of smart contracts onto a Private Hub or onto the Rayls Public Chain.

**Variants:**

**Enygma Payments** - Supports the private and fully atomic transfers of fungible tokens (ERC-20) between transacting users.

**Enygma DvP** - Supports the private and fully atomic exchange of fungible (ERC-20), non-fungible (ERC-721) and hybrid (ERC-1155) tokens between transacting users.

**Features:**
- Automatic synchronization with Rayls Privacy Nodes to issue/burn wrapped tokens, ensuring a 1-1 relationship
- 'Double' transaction batching (batched at the Rayls Privacy Node, then batched again on the Private Hub)
- Governance rules including token locking (immobilizing a balance for a specific institution), freezing (preventing an institution or a certain token from being transacted), and seizing (an authority role removing an amount of Enygma balance from an institution's account)

**Related:** [Enygma Protocol](../learn/protocols/enygma/index.md)

---

## Authorization

### AccessManager (RaylsAccessManagerV1)

The central authorization contract deployed on each chain. Manages named roles, function-level permission mappings, execution delays, guardians, and per-contract emergency pause. Each chain (Private Network Hub, Privacy Node) has its own independent instance.

**Related:** [Authorization](../learn/governance/authorization/index.md)

---

### restricted Modifier

The unified authorization modifier used on all privileged contract functions. Delegates authorization decisions to the AccessManager via `canCall(caller, target, selector)`. Applied to every function that requires role-based access control.

**Related:** [Access Manager](../learn/governance/authorization/access-manager.md)

---

### Target-Scoped Grant

A role grant that is bound to a specific contract instance rather than applying globally. Used for token handlers where a deployer receives TOKEN_OWNER only on their specific token, not on all tokens in the system.

**Related:** [Roles and Permissions](../learn/governance/authorization/roles-and-permissions.md)

---

### Execution Delay

A configurable waiting period before a scheduled operation can be executed. Provides a detection window for guardians to cancel suspicious or erroneous operations before they take effect.

**Related:** [Authorization Flows](../learn/governance/authorization/authorization-flows.md)

---

## Technical Terms

### Participants

Network members registered in the Private Network participant registry. Each participant has a role (participant, issuer, auditor) and status (new, active, inactive, frozen).

**Related:** [Participants](../learn/governance/participants.md)

---

### Tokens

Digital assets registered on a Privacy Node via the PN Token Registry (`PNTokenRegistryV1`) and catalogued network-wide on the Hub `TokenRegistryV1` when submitted. Support multiple ERC standards (ERC-20, ERC-721, ERC-1155) and Enygma privacy tokens.

**Related:** [Tokens](../learn/governance/tokens.md), [PN Token Registry](../learn/components/smart-contracts/pn-token-registry.md)

---

### PN Token Registry

The Privacy Node's own modular token registry (`PNTokenRegistryV1`, with modules `PNTokenCoreV1` and `PNTokenFreezeManagerV1`). It is the PN-side entry point for token registration (`registerToken`) and tracks each token through three independent status state machines:

- **`PrivacyNodeStatus`** (`UNDEFINED`, `WAITING_APPROVAL`, `AUTHORIZED`, `UNAUTHORIZED`, `FROZEN`) — owned by the PN operator; `FROZEN` blocks all operations.
- **`HubStatus`** (same values) — set by PNH cross-chain callbacks; governs Hub cross-chain operations.
- **`PublicChainStatus`** (`UNDEFINED`, `PENDING_DEPLOYMENT`, `DEPLOYED`, `FROZEN`, `DEPRECATED`) — owned by the relayer/bridge; governs public-chain operations.

This is distinct from the Hub-side `TokenRegistryV1`, which uses a single `updateStatus(resourceId, ACTIVE)` model for the network catalog.

**Related:** [PN Token Registry](../learn/components/smart-contracts/pn-token-registry.md)

---

### zkTLS

A cryptographic protocol that leverages zero-knowledge proofs to enable secure, private communication by authenticating parties without revealing sensitive identity or credential information. Rayls utilizes this technology to enable Crypto Users to self-issue zero knowledge bank identity (KYC) attestations so they can transact across the Rayls Public Chain.

---

### Actively Validated Services (AVS)

Specialized off-chain operations performed by independent validator nodes that continuously verify, attest, and provide proofs of specific blockchain computations or services, enhancing trust, security, and reliability.

---

### Data Availability

A decentralized service that ensures transaction data is published, accessible, and verifiable, enabling users to independently confirm transaction validity and protect against data withholding attacks.

---

### Sequencer

A single centralized node, managed by the Rayls Foundation, responsible for ordering, batching, and submitting transactions to the underlying Ethereum L1 blockchain to enhance scalability, reduce transaction fees, and improve throughput.

---

### Wallet

The piece of software that a user utilizes to store their blockchain keys, sign blockchain transactions, and view their blockchain balance. The most popular wallet is MetaMask, but these can come in many different forms.

---

### Public Bridge

The service(s) used to transfer tokens between the Rayls Public Chain and other public blockchains.

---

### Private Bridge

The service used to transfer tokens between the Rayls Public Chain and the Rayls private ecosystem.

---

## Deprecated Terms

These terms are no longer used in official documentation. Use the new terminology instead.

| Deprecated Term | Current Term |
|----------------|--------------|
| Governor | [Private Network Operator](#private-network-operator) |
| Commit Chain | [Private Network Hub](#private-network-hub) |
| Privacy Ledger | [Privacy Node Ledger](#privacy-node-ledger) or [Rayls Privacy Node](#rayls-sovereign-node) (depending on context) |
| Key Operation Service (KOS) | [Key Management Module (KMM)](#key-management-module-kmm) |
| DH Keys / CSIDH Keys | Rayls View Keys (ML-KEM-768) |
| ECDSA Keys | Rayls Sign Keys |
| Baby JubJub Keys / Enygma Keys | Payment Spend Keys (for Enygma) and DVP Spend Keys (for ZkDVP) |
| PQIES | ML-KEM + AES-GCM (key agreement and encryption) |

---

## See Also

- [Learn: Components Overview](../learn/components/index.md)
- [Build: Docker Setup](../build/beginner/docker-setup.md)
