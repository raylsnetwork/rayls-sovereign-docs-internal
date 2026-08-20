# Local Development

This guide walks you through setting up a local Rayls Privacy Node for development and testing with the **axyl** client. Because a Privacy Node is a multi-validator BFT cluster, the local setup brings up **four validators** via Docker Compose — the same model axyl ships in `etc/docker-network/`.

The flow has three phases:

1. **Setup** — each validator generates its keys and `node-info.yaml`.
2. **Genesis ceremony** — one container collects all four `node-info.yaml` files and produces `genesis.yaml`, `committee.yaml`, and `parameters.yaml`, then distributes them.
3. **Run** — the four validators start with `rayls node`.

!!! note "Single-node mode"
    A 1-of-1 committee has no Byzantine fault tolerance and is **refused** by a standard build. Running a true single node is only possible with a binary built with the `dev` feature (`cargo build -p rayls-network --release --features dev`, then `rayls node --dev`). For a representative local environment, use the four-validator cluster below.

## Prerequisites

- Docker 20.10+ and the Docker Compose plugin
- At least 4 GB RAM per validator (16 GB total recommended)
- 100 GB free disk space

## Step 1: Obtain the Node Image

Pull the `rayls-stack-node-client` image from Rayls' private registry, or build it locally from a checkout of the axyl repository:

```bash
# Build the image from the axyl repo root
docker build -f etc/docker-network/Dockerfile -t rayls-stack-node-client:local .
```

> NOTE: The examples below tag the image `rayls-stack-node-client:local`. Replace it with the image reference you pulled from Rayls' private registry if you are not building from source.

The axyl repository also provides a ready-made four-validator Compose stack at `etc/docker-network/compose.yaml`, driven by `make up` / `make down`. The steps below reproduce that stack so you can run it standalone.

## Step 2: Create the Setup Script

Each validator generates its own keys. Create `setup_validator.sh`:

```bash
cat > setup_validator.sh <<'EOF'
#!/bin/bash
set -e

USER_ID=1101

if [ ! -d /home/nonroot/data/node-keys ]; then
    /usr/local/bin/rayls keytool generate validator \
        --datadir /home/nonroot/data \
        --address "${EXECUTION_ADDRESS}"
    chown -R ${USER_ID}:${USER_ID} /home/nonroot/data
    echo "Keys generated and ownership set"

    # Clean any stale databases on first setup only.
    # Do NOT run this when keys already exist — a running validator would crash.
    rm -rf /home/nonroot/data/blobstore
    rm -rf /home/nonroot/data/consensus-db
    rm -rf /home/nonroot/data/db
    rm -rf /home/nonroot/data/static_files
    mkdir -p /home/nonroot/data/static_files
    chown ${USER_ID}:${USER_ID} /home/nonroot/data/static_files
else
    echo "Setup already complete"
fi
EOF
chmod +x setup_validator.sh
```

`rayls keytool generate validator` writes:

- `node-keys/` — AES-GCM-SIV-encrypted BLS keys plus deterministic Ed25519 network keys
- `node-info.yaml` — this validator's public key, proof of possession, execution address, and its primary/worker QUIC multiaddrs

The `--external-primary-addr` / `--external-worker-addrs` multiaddrs are supplied via the `RL_EXTERNAL_PRIMARY_ADDR` and `RL_EXTERNAL_WORKER_ADDRS` environment variables (read by `keytool generate`).

## Step 3: Create the Genesis Script

One container runs the genesis ceremony after all four validators have generated keys. Create `genesis.sh`:

```bash
cat > genesis.sh <<'EOF'
#!/bin/bash
set -e

# Optional gasless flags: set GASLESS=true to make the chain zero-fee.
GASLESS_FLAGS=""
if [ "$GASLESS" = "true" ]; then
    GASLESS_FLAGS="--base-fee 0 --min-base-fee 0"
    echo "Gasless mode enabled"
fi

# Collect each validator's node-info.yaml into genesis/validators/
mkdir -p /home/nonroot/data/genesis/validators
cp /home/nonroot/data/validator-1/node-info.yaml /home/nonroot/data/genesis/validators/validator-1.yaml
cp /home/nonroot/data/validator-2/node-info.yaml /home/nonroot/data/genesis/validators/validator-2.yaml
cp /home/nonroot/data/validator-3/node-info.yaml /home/nonroot/data/genesis/validators/validator-3.yaml
cp /home/nonroot/data/validator-4/node-info.yaml /home/nonroot/data/genesis/validators/validator-4.yaml

/usr/local/bin/rayls genesis \
    --datadir /home/nonroot/data/ \
    --chain-id 0x1e7 \
    --epoch-duration-in-secs 60 \
    --dev-funded-account 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --max-header-delay-ms 1000 \
    --min-header-delay-ms 500 \
    --consensus-registry-owner 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --network-admin 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --fee-aggregator-admin 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    ${GASLESS_FLAGS}

# Distribute the genesis bundle to every validator
for i in {1..4}; do
    mkdir -p /home/nonroot/data/validator-$i/genesis/
    cp /home/nonroot/data/genesis/genesis.yaml \
       /home/nonroot/data/genesis/committee.yaml \
       /home/nonroot/data/validator-$i/genesis/
    cp /home/nonroot/data/parameters.yaml /home/nonroot/data/validator-$i/
done
chown -R 1101:1101 /home/nonroot/data
echo "done"
EOF
chmod +x genesis.sh
```

`rayls genesis` produces `genesis/genesis.yaml`, `genesis/committee.yaml`, and `parameters.yaml`, which must be copied into every validator's data directory.

!!! warning "Development keys only"
    The address `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` is the well-known Anvil/Hardhat test account (private key `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`). It is used here for `--consensus-registry-owner`, `--network-admin`, `--fee-aggregator-admin`, and `--dev-funded-account` for local convenience only. **Never** use it on any shared or production network.

## Step 4: Create the Docker Compose File

This Compose stack runs four `setup` containers (key generation), then a `committee` container (genesis ceremony), then the four validators.

```yaml title="compose.yaml"
services:
  setup1:
    image: rayls-stack-node-client:local
    environment:
      - RL_EXTERNAL_PRIMARY_ADDR=/ip4/10.10.0.21/udp/49590/quic-v1
      - RL_EXTERNAL_WORKER_ADDRS=/ip4/10.10.0.21/udp/49595/quic-v1
      - EXECUTION_ADDRESS=0x1111111111111111111111111111111111111111
      - RL_BLS_PASSPHRASE=local
    user: "root"
    command: ["bash", "/setup_validator.sh"]
    volumes:
      - ./setup_validator.sh:/setup_validator.sh
      - validator1-data:/home/nonroot/data
  setup2:
    image: rayls-stack-node-client:local
    environment:
      - RL_EXTERNAL_PRIMARY_ADDR=/ip4/10.10.0.22/udp/49590/quic-v1
      - RL_EXTERNAL_WORKER_ADDRS=/ip4/10.10.0.22/udp/49595/quic-v1
      - EXECUTION_ADDRESS=0x2222222222222222222222222222222222222222
      - RL_BLS_PASSPHRASE=local
    user: "root"
    command: ["bash", "/setup_validator.sh"]
    volumes:
      - ./setup_validator.sh:/setup_validator.sh
      - validator2-data:/home/nonroot/data
  setup3:
    image: rayls-stack-node-client:local
    environment:
      - RL_EXTERNAL_PRIMARY_ADDR=/ip4/10.10.0.23/udp/49590/quic-v1
      - RL_EXTERNAL_WORKER_ADDRS=/ip4/10.10.0.23/udp/49595/quic-v1
      - EXECUTION_ADDRESS=0x3333333333333333333333333333333333333333
      - RL_BLS_PASSPHRASE=local
    user: "root"
    command: ["bash", "/setup_validator.sh"]
    volumes:
      - ./setup_validator.sh:/setup_validator.sh
      - validator3-data:/home/nonroot/data
  setup4:
    image: rayls-stack-node-client:local
    environment:
      - RL_EXTERNAL_PRIMARY_ADDR=/ip4/10.10.0.24/udp/49590/quic-v1
      - RL_EXTERNAL_WORKER_ADDRS=/ip4/10.10.0.24/udp/49595/quic-v1
      - EXECUTION_ADDRESS=0x4444444444444444444444444444444444444444
      - RL_BLS_PASSPHRASE=local
    user: "root"
    command: ["bash", "/setup_validator.sh"]
    volumes:
      - ./setup_validator.sh:/setup_validator.sh
      - validator4-data:/home/nonroot/data

  # Genesis ceremony: collect node-info.yaml files and distribute the bundle
  committee:
    image: rayls-stack-node-client:local
    environment:
      - RL_BLS_PASSPHRASE=local
      - GASLESS=${GASLESS:-}
    user: "root"
    command: ["bash", "/genesis.sh"]
    depends_on:
      setup1: { condition: service_completed_successfully }
      setup2: { condition: service_completed_successfully }
      setup3: { condition: service_completed_successfully }
      setup4: { condition: service_completed_successfully }
    volumes:
      - ./genesis.sh:/genesis.sh
      - validator1-data:/home/nonroot/data/validator-1
      - validator2-data:/home/nonroot/data/validator-2
      - validator3-data:/home/nonroot/data/validator-3
      - validator4-data:/home/nonroot/data/validator-4

  validator1:
    image: rayls-stack-node-client:local
    depends_on:
      committee: { condition: service_completed_successfully }
    environment:
      - RUST_LOG=info,execution=debug
      - RL_BLS_PASSPHRASE=local
      - RAYLS_NETWORK=devnet
      - PRIMARY_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49590/quic-v1
      - WORKER_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49595/quic-v1
    user: "1101:1101"
    command: >
      /usr/local/bin/rayls node --datadir /home/nonroot/data --metrics 127.0.0.1:9101
      --full --storage.v2
      --txpool.pending-max-count 50000 --txpool.pending-max-size 62144000
      --txpool.basefee-max-count 50000 --txpool.basefee-max-size 1048556000
      --txpool.queued-max-count 50000 --txpool.queued-max-size 1048556000
      --txpool.max-pending-txns 50000 --txpool.max-new-txns 50000
      --txpool.minimal-protocol-fee 0 --txpool.gas-limit 999999999999
      --txpool.max-tx-gas 999999999999 --txpool.max-tx-input-bytes 999999999999
      --txpool.max-account-slots 50000 --gpo.default-suggested-fee 0
      --http --http.addr 0.0.0.0 --http.api all
    ports:
      - "7545:8545"
    volumes:
      - validator1-data:/home/nonroot/data
    networks:
      validators: { ipv4_address: 10.10.0.21 }
  validator2:
    image: rayls-stack-node-client:local
    depends_on:
      committee: { condition: service_completed_successfully }
    environment:
      - RUST_LOG=info,execution=debug
      - RL_BLS_PASSPHRASE=local
      - RAYLS_NETWORK=devnet
      - PRIMARY_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49590/quic-v1
      - WORKER_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49595/quic-v1
    user: "1101:1101"
    command: >
      /usr/local/bin/rayls node --datadir /home/nonroot/data --metrics 127.0.0.1:9101
      --full --storage.v2 --txpool.minimal-protocol-fee 0
      --gpo.default-suggested-fee 0 --http --http.addr 0.0.0.0 --http.api all
    ports:
      - "7544:8545"
    volumes:
      - validator2-data:/home/nonroot/data
    networks:
      validators: { ipv4_address: 10.10.0.22 }
  validator3:
    image: rayls-stack-node-client:local
    depends_on:
      committee: { condition: service_completed_successfully }
    environment:
      - RUST_LOG=info,execution=debug
      - RL_BLS_PASSPHRASE=local
      - RAYLS_NETWORK=devnet
      - PRIMARY_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49590/quic-v1
      - WORKER_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49595/quic-v1
    user: "1101:1101"
    command: >
      /usr/local/bin/rayls node --datadir /home/nonroot/data --metrics 127.0.0.1:9101
      --full --storage.v2 --txpool.minimal-protocol-fee 0
      --gpo.default-suggested-fee 0 --http --http.addr 0.0.0.0 --http.api all
    ports:
      - "7543:8545"
    volumes:
      - validator3-data:/home/nonroot/data
    networks:
      validators: { ipv4_address: 10.10.0.23 }
  validator4:
    image: rayls-stack-node-client:local
    depends_on:
      committee: { condition: service_completed_successfully }
    environment:
      - RUST_LOG=info,execution=debug
      - RL_BLS_PASSPHRASE=local
      - RAYLS_NETWORK=devnet
      - PRIMARY_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49590/quic-v1
      - WORKER_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49595/quic-v1
    user: "1101:1101"
    command: >
      /usr/local/bin/rayls node --datadir /home/nonroot/data --metrics 127.0.0.1:9101
      --full --storage.v2 --txpool.minimal-protocol-fee 0
      --gpo.default-suggested-fee 0 --http --http.addr 0.0.0.0 --http.api all
    ports:
      - "7542:8545"
    volumes:
      - validator4-data:/home/nonroot/data
    networks:
      validators: { ipv4_address: 10.10.0.24 }

volumes:
  validator1-data:
  validator2-data:
  validator3-data:
  validator4-data:

networks:
  validators:
    driver: bridge
    ipam:
      config:
        - subnet: 10.10.0.0/16
```

!!! note "BLS passphrase"
    The encrypted BLS keys are unlocked with a passphrase. In this stack it is supplied via `RL_BLS_PASSPHRASE` (the default source for the `--bls-passphrase-source env` global flag). For anything beyond local development, use a real secret and consider `--bls-passphrase-source {stdin|ask}`.

!!! note "Fixed validator IPs"
    The external QUIC multiaddrs baked into the keys at setup time (`10.10.0.2x`) must match the static IPs the validators run on, so consensus peers can dial each other over UDP. Keep the `setup` IPs and the validator `ipv4_address` values aligned.

## Step 5: Start the Cluster

```bash
docker compose up -d

# For a zero-fee (gasless) chain instead:
GASLESS=true docker compose up -d
```

### How it Works

- The four `setup` containers run `rayls keytool generate validator`, writing each validator's `node-keys/` and `node-info.yaml`.
- The `committee` container runs `rayls genesis`, collecting the four `node-info.yaml` files into `genesis/validators/`, producing `genesis.yaml` / `committee.yaml` / `parameters.yaml`, and distributing them.
- The four `validator` containers run `rayls node`, open their reth (`db/`) and consensus (`consensus-db/`) MDBX databases, dial each other over QUIC, and begin producing BFT-ordered blocks.

## Step 6: Validate

The four validators expose HTTP-RPC on host ports 7545, 7544, 7543, and 7542.

```bash
curl http://localhost:7545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

**Expected response:**

```json
{"jsonrpc":"2.0","id":1,"result":"0x1e7"}
```

`0x1e7` is the hex chain ID set by `--chain-id 0x1e7` (decimal 487). Check that the block number is advancing across validators:

```bash
curl http://localhost:7545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

## Managing the Cluster

### View Logs

```bash
docker compose logs -f validator1
```

### Stop / Start

```bash
docker compose stop
docker compose start
```

### Reset Data

To start fresh, tear down the containers **and** the named volumes so keys and databases are regenerated:

```bash
docker compose down -v
docker compose up -d
```

!!! warning "Do not delete a running validator's databases"
    Removing `db/`, `consensus-db/`, `blobstore/`, or `static_files/` while a validator is running will crash it. The setup script only cleans these on first setup (when `node-keys/` is absent).

## Connecting Applications

Configure your applications to connect to one validator's HTTP-RPC:

```bash
# Environment variables
BLOCKCHAIN_CHAINID=487
BLOCKCHAIN_CHAINURL=http://localhost:7545
```

### Using with Hardhat

```javascript
// hardhat.config.js
module.exports = {
  networks: {
    rayls: {
      url: "http://localhost:7545",
      chainId: 487,
    }
  }
};
```

### Using with ethers.js

```javascript
const provider = new ethers.JsonRpcProvider("http://localhost:7545");
```

## Next Steps

- Ready for production? See [VPS Deployment](vps.md) or [Kubernetes](kubernetes.md)
- Need to customize settings? Check [Configuration Reference](configuration.md)
- Having issues? See [Troubleshooting](troubleshooting.md)
