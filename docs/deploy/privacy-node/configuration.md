# Configuration Reference

This page documents the configuration options for a Rayls Privacy Node running the **axyl** client (binary `rayls`).

A Privacy Node is configured in three places:

- **Genesis ceremony** (`rayls genesis`) — fixes the chain ID, fee model, epoch duration, admins, and the validator committee. Immutable after the chain is created.
- **Data directory files** — written by `keytool`/`genesis` and read by `rayls node`.
- **`rayls node` flags / environment variables** — per-validator runtime options.

---

## Data Directory Layout

Everything a validator needs lives under `--datadir`:

| Path | Description |
|------|-------------|
| `node-keys/` | AES-GCM-SIV-encrypted BLS keys + deterministic Ed25519 network keys |
| `node-info.yaml` | This validator's public key, proof of possession, execution address, primary/worker multiaddrs |
| `genesis/genesis.yaml` | Genesis state (chain ID, allocations, `baseFeePerGas`) — produced by the genesis ceremony |
| `genesis/committee.yaml` | The validator committee at genesis |
| `parameters.yaml` | Network parameters (header delays, `min_base_fee`, `gas_limit`, network profile, fee admin) |
| `db/` | reth (execution) database — **MDBX** |
| `consensus-db/` | consensus database — **MDBX** |
| `static_files/` | reth static file segments |
| `blobstore/` | consensus worker batch storage |

> NOTE: Storage is MDBX for both the execution and consensus databases — there is no LevelDB, Pebble, or MongoDB backend in axyl.

---

## `rayls keytool generate` — Key Generation

Generates a validator's (or observer's) keys and `node-info.yaml`.

```bash
rayls keytool generate validator \
  --datadir <dir> \
  --address <execution_addr> \
  [--external-primary-addr <multiaddr>] \
  [--external-worker-addrs <multiaddrs>]
```

| Flag | Env | Description |
|------|-----|-------------|
| `--datadir` | — | Data directory to write `node-keys/` and `node-info.yaml` into |
| `--address` | `EXECUTION_ADDRESS` | Execution-layer (fee-recipient) address. Pass `0` for the zero address |
| `--external-primary-addr` | `RL_EXTERNAL_PRIMARY_ADDR` | Public QUIC multiaddr for the primary p2p network, e.g. `/ip4/<host>/udp/49590/quic-v1` |
| `--external-worker-addrs` | `RL_EXTERNAL_WORKER_ADDRS` | Comma-separated public QUIC multiaddr(s) for the worker p2p network |
| `--workers` | — | Number of workers (currently must be `1`) |
| `--force` | — | Overwrite existing keys (existing keys are lost) |

Use `rayls keytool generate observer` for a non-validating (Observer) node.

> NOTE: If the external multiaddrs are omitted, the CLI defaults to `/ip4/127.0.0.1/udp/<random-port>/quic-v1`, which is only useful for local tests. Always set a publicly reachable multiaddr for real deployments.

---

## `rayls genesis` — Genesis Ceremony

Run once by one operator after collecting every validator's `node-info.yaml` into `<datadir>/genesis/validators/`. Produces `genesis/genesis.yaml`, `genesis/committee.yaml`, and `parameters.yaml`, which must be distributed to every validator.

```bash
rayls genesis \
  --datadir <dir> \
  --chain-id <id> \
  --epoch-duration-in-secs <n> \
  [--base-fee 0 --min-base-fee 0] \
  [--consensus-registry-owner <addr>] \
  [--network-admin <addr>] \
  [--fee-aggregator-admin <addr>] \
  [--max-header-delay-ms <ms>] \
  [--min-header-delay-ms <ms>] \
  [--accounts <yaml>]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--chain-id` | `2017` (`0x7e1`) | Numeric chain ID written into genesis. Accepts decimal or `0x` hex |
| `--epoch-duration-in-secs` | `86400` (24h) | Epoch length; controls how often the committee rotates |
| `--base-fee` | `48 Gwei` | Genesis block base fee (in wei). Set to `0` for gasless |
| `--min-base-fee` | `48 Gwei` | EIP-1559 base-fee floor (in wei). Set to `0` for gasless |
| `--gas-limit` | (binary default) | Block gas limit (gas units) |
| `--consensus-registry-owner` | governance safe | Owner of the `ConsensusRegistry` contract in genesis. Use a multisig in production |
| `--network-admin` | governance safe | Admin for all precompile contracts (replaces deployer admin) |
| `--fee-aggregator-admin` | governance safe | Admin for the `FeeAggregator` contract |
| `--basefee-address` | FeeAggregator | Recipient of base fees |
| `--initial-stake-per-validator` | `5,000,000 RLS` | Stake credited to each validator in genesis |
| `--min-withdraw-amount` | `1,000 RLS` | Minimum withdrawal amount |
| `--max-header-delay-ms` / `--min-header-delay-ms` | — | Bounds on how often a node produces a new consensus header |
| `--accounts <yaml>` | — | YAML file of extra accounts to merge into genesis (dev/test) |
| `--dev-funded-account <str>` | — | Deterministically derive and fund an account from a string. **Dev/test only** |

!!! warning "Genesis is immutable"
    `chain-id`, the fee model, epoch duration, and the committee are fixed at genesis. Changing any of them requires creating a new chain. All validators must use the **identical** genesis bundle.

---

## `rayls node` — Running a Validator

Starts the node (execution + consensus).

```bash
rayls node \
  --datadir <dir> \
  --http --http.addr 0.0.0.0 --http.port <port> --http.api all \
  --network {local|devnet|testnet|mainnet} \
  --metrics <addr> \
  [reth txpool/gpo flags]
```

### Core Flags

| Flag | Env | Description |
|------|-----|-------------|
| `--datadir` | — | Data directory (see [layout](#data-directory-layout)) |
| `--network` | `RAYLS_NETWORK` | Hardfork profile: `local`, `devnet`, `testnet`, `mainnet` |
| `--http` | — | Enable the HTTP JSON-RPC server |
| `--http.addr` | — | RPC bind address (use `0.0.0.0` in containers) |
| `--http.port` | — | RPC port (default `8545`) |
| `--http.api` | — | Enabled namespaces (`all`, or a subset such as `eth,rayls`) |
| `--metrics` | — | Prometheus metrics socket, e.g. `127.0.0.1:9101` |
| `--observer` | — | Run as an Observer (follows consensus, serves RPC, never in committee) |
| `--healthcheck <port>` | `HEALTHCHECK_TCP_PORT` | Spawn a TCP health-check endpoint (place behind a firewall) |
| `--bls-passphrase-source` | — | Where to read the BLS passphrase: `env` (default, `RL_BLS_PASSPHRASE`), `stdin`, or `ask` |
| `--log.*` | — | Logging options (see [Troubleshooting](troubleshooting.md#logging)) |

### Consensus Database Flags

| Flag | Description |
|------|-------------|
| `--consensus-db.max-size` | Maximum size of the consensus MDBX database |

> NOTE: Additional `--consensus-db.*` flags exist for tuning the consensus MDBX environment. Run `rayls node --help` for the full set.

### Canonical Production Flag Set

The flag set axyl uses in `etc/docker-network/compose.yaml` (a good production baseline, gasless-friendly):

```bash
rayls node \
  --datadir <dir> \
  --metrics 127.0.0.1:9101 \
  --full \
  --storage.v2 \
  --txpool.pending-max-count 50000 \
  --txpool.pending-max-size 62144000 \
  --txpool.basefee-max-count 50000 \
  --txpool.basefee-max-size 1048556000 \
  --txpool.queued-max-count 50000 \
  --txpool.queued-max-size 1048556000 \
  --txpool.max-pending-txns 50000 \
  --txpool.max-new-txns 50000 \
  --txpool.minimal-protocol-fee 0 \
  --txpool.gas-limit 999999999999 \
  --txpool.max-tx-gas 999999999999 \
  --txpool.max-tx-input-bytes 999999999999 \
  --txpool.max-account-slots 50000 \
  --gpo.default-suggested-fee 0 \
  --http \
  --http.addr 0.0.0.0 \
  --http.api all
```

!!! note "Single-validator networks are refused"
    A 1-of-1 committee has no Byzantine fault tolerance and the node refuses to start. A true single node is only possible with a binary built with the `dev` feature, run via `rayls node --dev` against a single-validator genesis. Use a committee of at least 2 (4 recommended) for any real deployment.

---

## Network Profiles

`--network` (or `RAYLS_NETWORK`) selects a baked-in hardfork schedule. The profiles differ in their EIP-1559 activation block:

| Profile | EIP-1559 activation block |
|---------|---------------------------|
| `local` | `0` |
| `devnet` | `50` |
| `testnet` | `281800` |
| `mainnet` | `0` |

All validators on the same network must use the same profile.

---

## Gasless (Feeless) Mode

To run a zero-fee chain, set **both** of the following at genesis:

```bash
rayls genesis --base-fee 0 --min-base-fee 0 ...
```

- `--base-fee 0` sets the genesis block's `baseFeePerGas` to `0` (written to `genesis.yaml`).
- `--min-base-fee 0` sets the EIP-1559 base-fee floor to `0` (written to `parameters.yaml`).

Both are required: EIP-1559 keeps the base fee at `0` indefinitely once it starts at `0`, but only if the floor is also `0`. Setting only one is **not** sufficient. The default for both is 48 Gwei.

On a gasless network, run validators with `--txpool.minimal-protocol-fee 0` so the transaction pool accepts zero-fee transactions.

---

## On-chain Validator Registration

Validators (not observers) must register on-chain before joining the committee. The sequence:

| Step | Contract / function | Sent by |
|------|---------------------|---------|
| Fund | native transfer to the operator key | Admin |
| Allowlist | `ConsensusRegistry.allowlistValidator(<address>)` | Admin (`MAINTAINER` role) |
| Stake | `ConsensusRegistry.stake(...)` (calldata from `rayls keytool stake-calldata`) | Validator operator key |
| Activate | `ConsensusRegistry.activate()` | Validator operator key |

Activation moves the validator to `PendingActivation`; it becomes `Active` at the next epoch boundary. To retire, call `ConsensusRegistry.beginExit()` (finalises over two epochs, then `unstake()` becomes callable one epoch later).

Observers skip all of this — they provision a data directory and run `rayls node --observer`.

---

## Environment Variables

The container/process reads these environment variables:

### Core

| Variable | Equivalent flag | Description | Example |
|----------|-----------------|-------------|---------|
| `RAYLS_NETWORK` | `--network` | Hardfork profile | `mainnet` |
| `RL_BLS_PASSPHRASE` | (via `--bls-passphrase-source env`) | Passphrase to decrypt the BLS keys | `change-me` |
| `EXECUTION_ADDRESS` | `--address` (keytool) | Execution/fee-recipient address used at key generation | `0x1111...1111` |
| `HEALTHCHECK_TCP_PORT` | `--healthcheck` | TCP health-check port | `8080` |

### Key Generation

| Variable | Equivalent flag | Description |
|----------|-----------------|-------------|
| `RL_EXTERNAL_PRIMARY_ADDR` | `--external-primary-addr` | Public primary QUIC multiaddr |
| `RL_EXTERNAL_WORKER_ADDRS` | `--external-worker-addrs` | Public worker QUIC multiaddr(s), comma-separated |

### Logging

| Variable | Description |
|----------|-------------|
| `RUST_LOG` | Log filter, e.g. `info` or `info,execution=debug` |

### Docker Compose Example

```yaml
services:
  privacy-node:
    image: rayls-stack-node-client:<tag>
    container_name: rayls-sovereign-node
    restart: unless-stopped
    user: "1101:1101"
    environment:
      - RUST_LOG=info
      - RAYLS_NETWORK=mainnet
      - RL_BLS_PASSPHRASE=change-me
      - PRIMARY_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49590/quic-v1
      - WORKER_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49595/quic-v1
    command: >
      /usr/local/bin/rayls node --datadir /home/nonroot/data --metrics 127.0.0.1:9101
      --full --storage.v2 --txpool.minimal-protocol-fee 0
      --gpo.default-suggested-fee 0 --http --http.addr 0.0.0.0 --http.api all
    ports:
      - "8545:8545"
      - "49590:49590/udp"
      - "49595:49595/udp"
    volumes:
      - ./data:/home/nonroot/data
```

### Kubernetes Secret (BLS passphrase)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rayls-secrets
  namespace: rayls
type: Opaque
stringData:
  RL_BLS_PASSPHRASE: "change-me"
```

---

## For Downstream Components

Applications connecting to a Privacy Node validator's HTTP-RPC typically require:

| Variable | Description | Example |
|----------|-------------|---------|
| `BLOCKCHAIN_CHAINID` | Chain ID (matches `rayls genesis --chain-id`) | `487` |
| `BLOCKCHAIN_CHAINURL` | HTTP-RPC endpoint URL | `http://localhost:8545` |

**Docker Compose:**
```yaml
services:
  your-app:
    environment:
      - BLOCKCHAIN_CHAINID=487
      - BLOCKCHAIN_CHAINURL=http://rayls-sovereign-node:8545
```

**Kubernetes:**
```yaml
env:
- name: BLOCKCHAIN_CHAINID
  value: "487"
- name: BLOCKCHAIN_CHAINURL
  value: "http://rayls-sovereign-node.rayls.svc.cluster.local:8545"
```

> NOTE: axyl exposes `eth_*` and `rayls_*` JSON-RPC over HTTP (plus an optional faucet). If a downstream component needs WebSocket subscriptions, confirm the WS server is enabled on the node build you run.

---

## Chain ID Reference

| Environment | Suggested chain ID | Purpose |
|-------------|--------------------|---------|
| Production (mainnet) | `487` | Main deployment |
| Devnet (default) | `2017` (`0x7e1`) | Shared development network |
| Local | any non-production ID | Local clusters |

!!! tip "Chain ID best practice"
    Use a distinct chain ID per environment to prevent accidental cross-environment transactions. Do not point a `--dev` build at a production chain ID — the client refuses it.

---

## Related Pages

- [Local Development](local.md) - Quick start guide
- [VPS Deployment](vps.md) - Server deployment
- [Kubernetes](kubernetes.md) - Production K8s setup
- [Monitoring](monitoring.md) - Observability setup
- [Troubleshooting](troubleshooting.md) - Common issues
