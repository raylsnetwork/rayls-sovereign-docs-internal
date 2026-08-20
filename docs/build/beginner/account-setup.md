# Account Setup

This guide explains which accounts you need to interact with the Rayls system in your local development environment and how to configure them.

## Gas and the Rayls Network

!!! info "Gas Fees"
    In the private network (PN and PN Hub) the gas is free. In the public network the gas is paid.

## Understanding Accounts

In Rayls (like Ethereum), an **account** is a pair consisting of:

- **Address**: Public identifier (e.g., `0xf39Fd6...2266`)
- **Private Key**: Secret key used to sign transactions

Rayls requires accounts to:

- Deploy smart contracts to the blockchains
- Sign and submit transactions
- Authorize operations like cross-chain transfers

In the Docker development environment, **all accounts are pre-funded** with test ETH, so you can start testing immediately without worrying about gas fees or balances.

## Default Accounts for Local Development

The Rayls Docker environment uses two pre-configured accounts that are the **well-known public Anvil/Hardhat test accounts** (accounts #0 and #1). These are **safe to use for local development** because your Docker environment is isolated.

!!! danger "Never use these keys on a shared or production network"
    These are publicly documented test keys — anyone can sign with them. Use them for local development only. For any shared testnet or production deployment, generate your own keys and keep them secret.

### System/Deployer Account

This is the primary account used for all contract deployments and system operations.

**Address:**
```
0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

**Private Key:**
```
0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

**Used for:**
- Deploying all smart contracts (Private Network Hub, Privacy Nodes)
- System administration and configuration
- Authorizing relayers
- Registering participants

**Pre-funded:** ✓ Yes (in Docker environment)

### User Account

This is a secondary account for testing user interactions and transactions.

**Address:**
```
0x70997970C51812dc3A010C7d01b50e0d17dc79C8
```

**Private Key:**
```
0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

**Used for:**
- Testing token transfers
- Minting and burning tokens
- Cross-chain transaction testing
- User-level contract interactions

**Pre-funded:** ✓ Yes (in Docker environment)

## Account Roles Explained

Understanding what each account does helps you know when and where to use them.

### System/Deployer Account (`PRIVATE_KEY_SYSTEM`)

**Primary Role:** Contract deployer and system administrator

**Permissions:**
- Deploys all contracts to the Private Network Hub and Privacy Nodes
- Becomes the `initialOwner` of all deployed contracts
- Owns the `DeploymentProxyRegistry` (contract discovery system)
- Can register new contracts in the registry
- Can register new participants on the Private Network Hub
- Can authorize relayer addresses for cross-chain messaging
- Initial owner of governance contracts

**Used On:**
- Private Network Hub
- All Privacy Nodes (A through F)
- Public Chain (if testing public-to-private transfers)

**Required For:**
- All deployment operations (`deploy:commit-chain`, `deploy:privacy-ledger`)
- Participant registration
- Relayer authorization
- System configuration tasks

### User Account (`PRIVATE_KEY_USER`)

**Primary Role:** Testing and user interactions

**Permissions:**
- Standard Ethereum account permissions
- Can call public contract functions
- Can sign transactions for token operations
- No special administrative privileges

**Used For:**
- Testing ERC20/721/1155 token interactions
- Simulating user-initiated transfers
- Cross-chain transfer testing
- Verifying transaction flows from a non-admin account

**Used On:**
- Privacy Nodes (where users interact)
- Public Chain (for testing)

**Required For:**
- User-level testing (optional)
- Separating admin and user operations in tests

### Relayer Accounts (KMS-managed)

**Primary Role:** Bridge messages between chains

**Management:**
- Automatically managed by the Key Management Service (KMS)
- Created and funded during Docker environment setup
- No manual configuration required for local development

**Permissions:**
- Authorized to post messages to the Private Network Hub
- Can execute cross-chain transactions on destination Privacy Nodes
- Retrieve and decrypt encrypted messages

**Used For:**
- Listening to events on Privacy Nodes
- Encrypting and posting messages to the Private Network Hub
- Decrypting messages from the Private Network Hub
- Executing transactions on destination Privacy Nodes

**Required For:**
- All cross-chain transfers (automatic)

## Complete .env Reference

For a full local development environment with 6 participants, here's the complete `.env` configuration:

??? note "Expand to see complete .env file"

    ```bash
    # ===========================================
    # ACCOUNT CONFIGURATION
    # ===========================================
    PRIVATE_KEY_SYSTEM=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
    PRIVATE_KEY_USER=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

    # ===========================================
    # COMMIT CHAIN (PRIVATE NETWORK HUB)
    # ===========================================
    RPC_URL_NODE_CC=http://commit-chain:3445
    NODE_CC_CHAIN_ID=1337

    # ===========================================
    # PRIVACY LEDGERS (PARTICIPANTS A-F)
    # ===========================================
    RPC_URL_NODE_A=http://pl-a:8545
    NODE_A_CHAIN_ID=12345

    RPC_URL_NODE_B=http://pl-b:8546
    NODE_B_CHAIN_ID=12346

    RPC_URL_NODE_C=http://pl-c:8547
    NODE_C_CHAIN_ID=12347

    RPC_URL_NODE_D=http://pl-d:8548
    NODE_D_CHAIN_ID=12348

    RPC_URL_NODE_E=http://pl-e:8549
    NODE_E_CHAIN_ID=12349

    RPC_URL_NODE_F=http://pl-f:8550
    NODE_F_CHAIN_ID=12350

    # ===========================================
    # PUBLIC CHAIN (OPTIONAL)
    # ===========================================
    RPC_URL_NODE_PC=http://public-chain:3446
    NODE_PC_CHAIN_ID=7331

    # ===========================================
    # PARTICIPANT REGISTRATION
    # ===========================================
    PARTICIPANTS=12345,12346,12347,12348,12349,12350

    # ===========================================
    # DEPLOYMENT REGISTRY ADDRESSES
    # (Set after deploying Private Network Hub)
    # ===========================================
    NODE_CC_DEPLOYMENTPROXYREGISTRY=
    NODE_A_DEPLOYMENTPROXYREGISTRY=
    NODE_B_DEPLOYMENTPROXYREGISTRY=
    NODE_C_DEPLOYMENTPROXYREGISTRY=
    NODE_D_DEPLOYMENTPROXYREGISTRY=
    NODE_E_DEPLOYMENTPROXYREGISTRY=
    NODE_F_DEPLOYMENTPROXYREGISTRY=

    # ===========================================
    # KMS CONFIGURATION (OPTIONAL - for production)
    # ===========================================
    # KMS_OPERATION_SERVICE_ROOT_URL_A=http://kos-a:3000
    # KMS_OPERATION_SERVICE_ROOT_URL_B=http://kos-b:3001
    # KMS_OPERATION_SERVICE_ROOT_URL_C=http://kos-c:3002
    # KMS_OPERATION_SERVICE_ROOT_URL_D=http://kos-d:3003
    # KMS_OPERATION_SERVICE_ROOT_URL_E=http://kos-e:3004
    # KMS_OPERATION_SERVICE_ROOT_URL_F=http://kos-f:3005
    ```

## Verifying Your Setup

After configuring your accounts, verify everything is set up correctly:

### Check Account Addresses

```bash
cd ~/work/parfin/rayls-sovereign-contracts

# View the addresses derived from your private keys
npx hardhat accounts --network localCC
```

**Expected output:**
```
0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

### Check Account Balance (Optional)

```bash
# Check system account balance on Private Network Hub
npx hardhat run scripts/check-balance.js --network localCC
```

The system account should have a large balance (pre-funded in Docker).

### Verify .env Loading

```bash
# Test that environment variables are loaded
node -e "require('dotenv').config(); console.log('PRIVATE_KEY_SYSTEM:', process.env.PRIVATE_KEY_SYSTEM ? 'Set ✓' : 'Not set ✗')"
```

**Expected output:**
```
PRIVATE_KEY_SYSTEM: Set ✓
```

## Security Considerations

!!! warning "Local Development Only"
    The private keys shown in this guide are **publicly known test keys** and should **ONLY be used for local development** in your isolated Docker environment.

    **DO NOT:**
    - Use these keys in production
    - Use these keys on public testnets (Goerli, Sepolia, etc.)
    - Use these keys on mainnet
    - Share these keys (they're already public!)

    **DO:**
    - Use them freely in your local Docker environment
    - Replace them with secure keys for any non-local environment
    - Use hardware wallets or KMS for production deployments

**Why are these keys safe for local dev?**
- Your Docker environment is isolated from the internet
- The blockchains are private (not connected to public networks)
- All other developers use the same keys for consistency
- Pre-funded accounts mean you don't need to manage test tokens

## Next Steps

Now that your accounts are configured, you're ready to:

**If you haven't deployed the Docker environment yet:**
→ [Docker Setup](docker-setup.md) - Start the local development environment

**If Docker is already running:**
→ [First Transaction](first-transaction.md) - Send your first cross-chain transfer

**For more background:**
→ [Architecture Overview](architecture-overview.md) - Understand how accounts fit into the system
→ [Prerequisites](prerequisites.md) - Review system requirements

## Troubleshooting

### "Account not funded" error

If you see errors about insufficient funds:

1. Verify Docker environment is running: `docker compose ps`
2. Check that the genesis blocks include pre-funded accounts
3. Restart the Docker environment: `./start_dev.sh --clean`

### "Invalid private key" error

If you see errors about invalid private keys:

1. Verify the private key starts with `0x`
2. Ensure the private key is 64 hex characters (66 with `0x` prefix)
3. Check for typos in your `.env` file
4. Ensure `.env` file is in the `rayls-sovereign-contracts` root directory

### "Cannot find .env file"

If environment variables aren't loading:

1. Verify `.env` file exists: `ls -la ~/work/parfin/rayls-sovereign-contracts/.env`
2. Check file permissions: `chmod 644 ~/work/parfin/rayls-sovereign-contracts/.env`
3. Ensure you're running commands from the `rayls-sovereign-contracts` directory
