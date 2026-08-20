# What is Rayls?

Rayls is a **privacy-preserving institutional blockchain network** that enables regulated financial institutions to transfer assets securely across organizational boundaries while maintaining transaction confidentiality.

## The Vision

Financial markets are built on trust, but that trust comes at a cost. Today, transferring assets between institutions requires intermediaries, reconciliation processes, and days of settlement time. Blockchain technology promises to streamline this, but public blockchains expose sensitive financial data to anyone watching.

Rayls bridges this gap by providing:

- **Blockchain efficiency** - Near-instant settlement, atomic transactions, programmable assets
- **Institutional privacy** - Transaction details visible only to authorized parties
- **Regulatory compliance** - Audit capabilities for authorized regulators
- **Operational sovereignty** - Each institution controls their own infrastructure

## The Problem: Why Blockchain Fails for Institutions

Traditional blockchain adoption faces six fundamental challenges:

### 1. Transaction Privacy

On public blockchains, anyone can see who transacted with whom, how much was transferred, and the complete transaction history. For financial institutions, this exposure enables competitive intelligence gathering, front-running, and market manipulation.

### 2. Data Sovereignty

Traditional consortium blockchains require all members to share a single ledger, meaning everyone sees everyone's transactions. This creates operational coupling, data residency issues, and complex exit scenarios.

### 3. Regulatory Compliance

Privacy-focused systems often conflict with audit requirements. Institutions need the ability to provide transaction data when legally required while maintaining privacy from other market participants.

### 4. Settlement Finality

Traditional settlement takes T+1 to T+3 days, creating counterparty risk, capital inefficiency, and reconciliation overhead. During this delay, either party might default.

### 5. Trustless Exchange

When two parties want to exchange different assets, someone must go first. This creates settlement risk and requires intermediaries like clearinghouses.

### 6. Interoperability

Blockchain networks are typically isolated. Cross-chain bridges have security vulnerabilities and poor user experience.

## How Rayls Solves It

| Problem | Rayls Solution |
|---------|----------------|
| **Transaction Privacy** | End-to-end encryption between institutions |
| **Data Sovereignty** | Each institution runs their own Rayls Privacy Node |
| **Regulatory Compliance** | Governance API enables authorized audit access |
| **Settlement Finality** | 30-60 second settlement with cryptographic finality |
| **Trustless Exchange** | DVP atomic swaps - both parties or neither |
| **Interoperability** | Native EIP-5164 cross-chain protocol |

For technical details on how these solutions work, see [How It Works](how-it-works.md).
For a complete list of capabilities, see [Key Features](key-features.md).

## How Rayls is Different

### vs. Public Blockchains (Ethereum, etc.)

| Aspect | Public Blockchain | Rayls |
|--------|-------------------|-------|
| Transaction visibility | Everyone can see everything | Only authorized parties |
| Settlement finality | Minutes to hours | Seconds |
| Regulatory compliance | Challenging | Built-in audit capabilities |
| Operational control | None | Full sovereignty per institution |

### vs. Private/Consortium Blockchains

| Aspect | Traditional Private Chain | Rayls |
|--------|---------------------------|-------|
| Cross-chain transfers | Complex, often manual | Native protocol support |
| Privacy between members | Limited (all members see data) | End-to-end encryption |
| Zero-knowledge proofs | Rarely supported | Native Enygma and DVP |
| Interoperability | Siloed | Hub-and-spoke architecture |

### vs. Traditional Settlement Systems

| Aspect | Traditional Systems | Rayls |
|--------|---------------------|-------|
| Settlement time | T+1 to T+3 days | Seconds |
| Reconciliation | Manual, error-prone | Automatic, cryptographic |
| Intermediaries | Multiple required | Direct peer-to-peer |
| Transparency | Limited audit trail | Full blockchain auditability |

## Core Principles

### Institutional Sovereignty

Each organization runs their own Rayls Privacy Node. Your data never leaves your infrastructure unless you explicitly transfer it. No shared database, no single point of failure, no dependency on other participants' operations.

### Privacy by Design

Messages between institutions are encrypted using public-key cryptography. The Hub routes messages without accessing their contents. Even in Enygma transfers, the receiving institution only learns their balance changed, not the specific amounts.

### Regulatory Readiness

The Governance API provides authorized auditors with decryption capabilities, real-time monitoring, and compliance reporting - all while maintaining privacy from other market participants.

### Blockchain Native

Rayls doesn't abstract away the blockchain - it enhances it. You still write Solidity contracts, use standard token interfaces, and interact via JSON-RPC. The privacy and cross-chain capabilities are additive.

## Who Uses Rayls

Rayls is designed for organizations that need:

- **Banks and Financial Institutions** - Inter-bank settlements, correspondent banking
- **Asset Managers** - Fund administration, NAV calculations, share transfers
- **Exchanges and Clearinghouses** - Trade settlement, margin management
- **Central Banks and Regulators** - CBDC infrastructure, market oversight
- **Corporate Treasury** - Internal fund transfers, intercompany settlements

## Next Steps

| Goal | Next Step |
|------|-----------|
| Learn technical capabilities | [Key Features](key-features.md) |
| Understand the architecture | [How It Works](how-it-works.md) |
| Start building | [Build Section](../../build/index.md) |
