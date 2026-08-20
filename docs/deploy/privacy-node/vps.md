# VPS Deployment

This guide covers deploying a Rayls Privacy Node validator on a VPS or Virtual Machine using the **axyl** client.

A Privacy Node is a **multi-validator BFT cluster** (4 validators by default). In a VPS deployment you typically run **one validator per host** and wire the hosts together over QUIC/UDP. This guide describes provisioning a single validator host; repeat it for each validator and share one genesis bundle across them.

## Overview

Bringing up a validator on a host has three phases:

1. **Key generation** — `rayls keytool generate validator` writes the validator's keys and `node-info.yaml`.
2. **Genesis ceremony** — one operator collects every validator's `node-info.yaml`, runs `rayls genesis`, and distributes the resulting `genesis.yaml`, `committee.yaml`, and `parameters.yaml` to all hosts.
3. **Run** — each host runs `rayls node` (here, as a Docker Compose service managed by systemd).

!!! note "Coordinate the multiaddrs"
    Each validator's external QUIC multiaddr (`--external-primary-addr` / `--external-worker-addr`) is baked into its keys at generation time. Use each host's **publicly reachable IP and UDP port** so the other validators can dial it. Decide the host IPs and ports up front and keep them consistent across all phases.

## Prerequisites

Install Docker and the Docker Compose plugin on each VPS:

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Verify installation
docker --version
docker compose --version
```

> NOTE: Pull the `rayls-stack-node-client` image from Rayls' private registry, or build it from a checkout of the axyl repository with `docker build -f etc/docker-network/Dockerfile -t rayls-stack-node-client:local .`. The examples below reference `rayls-stack-node-client:local`.

### Setup Directory Structure

```bash
sudo mkdir -p /opt/rayls/{data,scripts}
cd /opt/rayls
```

## Phase 1: Generate Keys (each validator host)

On each validator host, generate its keys. Set `EXECUTION_ADDRESS` to the operator/fee-recipient address for this validator, and the external multiaddrs to this host's public IP and the UDP ports it will listen on.

```bash
sudo docker run --rm \
  -e RL_BLS_PASSPHRASE='change-me' \
  -e EXECUTION_ADDRESS='0x1111111111111111111111111111111111111111' \
  -e RL_EXTERNAL_PRIMARY_ADDR='/ip4/<this-host-public-ip>/udp/49590/quic-v1' \
  -e RL_EXTERNAL_WORKER_ADDRS='/ip4/<this-host-public-ip>/udp/49595/quic-v1' \
  -v /opt/rayls/data:/home/nonroot/data \
  rayls-stack-node-client:local \
  rayls keytool generate validator --datadir /home/nonroot/data --address "0x1111111111111111111111111111111111111111"
```

This writes `node-keys/` (encrypted BLS + deterministic Ed25519 network keys) and `node-info.yaml` into `/opt/rayls/data`.

!!! warning "Protect the BLS passphrase"
    The BLS keys are encrypted at rest with the passphrase supplied via `RL_BLS_PASSPHRASE`. Store it in a secret manager — not in shell history or the Compose file. The same passphrase is needed every time the node starts.

## Phase 2: Genesis Ceremony (one operator, once)

Collect each validator's `node-info.yaml` (one per host) into a `genesis/validators/` directory on the ceremony machine, then run the ceremony:

```bash
# genesis/validators/ should contain validator-1.yaml ... validator-N.yaml,
# each being a copy of that validator's node-info.yaml.

sudo docker run --rm \
  -e RL_BLS_PASSPHRASE='change-me' \
  -v /opt/rayls/genesis-work:/home/nonroot/data \
  rayls-stack-node-client:local \
  rayls genesis \
    --datadir /home/nonroot/data \
    --chain-id 487 \
    --epoch-duration-in-secs 86400 \
    --consensus-registry-owner 0xYOUR_GOVERNANCE_ADDR \
    --network-admin 0xYOUR_GOVERNANCE_ADDR \
    --fee-aggregator-admin 0xYOUR_GOVERNANCE_ADDR
```

This produces `genesis/genesis.yaml`, `genesis/committee.yaml`, and `parameters.yaml`. **Distribute the same three files to every validator host** (place `genesis.yaml` and `committee.yaml` under each host's `data/genesis/`, and `parameters.yaml` directly under each host's `data/`).

!!! tip "Gasless network"
    To run a zero-fee chain, add **both** `--base-fee 0` and `--min-base-fee 0` to the genesis command (setting only one is not sufficient). See [Configuration Reference](configuration.md#gasless-feeless-mode).

!!! warning "Genesis is immutable"
    `chain-id`, fee model, epoch duration, and the validator committee are fixed at genesis. Changing them requires a new genesis (and a fresh chain). All hosts must use the identical genesis bundle.

## Phase 3: Run the Validator

### Create the Docker Compose File

```bash
sudo tee /opt/rayls/docker-compose.yml > /dev/null <<'EOF'
services:
  privacy-node:
    image: rayls-stack-node-client:local
    container_name: rayls-sovereign-node
    restart: unless-stopped
    user: "1101:1101"
    environment:
      - RUST_LOG=info
      - RL_BLS_PASSPHRASE=change-me
      - RAYLS_NETWORK=mainnet
      - PRIMARY_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49590/quic-v1
      - WORKER_LISTENER_MULTIADDR=/ip4/0.0.0.0/udp/49595/quic-v1
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
      - "8545:8545"          # HTTP-RPC (TCP)
      - "49590:49590/udp"    # primary consensus (QUIC/UDP)
      - "49595:49595/udp"    # worker consensus (QUIC/UDP)
    volumes:
      - /opt/rayls/data:/home/nonroot/data
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "10"
EOF
```

!!! info "Network profile"
    `RAYLS_NETWORK` (equivalent to `--network`) selects the hardfork profile: `local`, `devnet`, `testnet`, or `mainnet`. It must be consistent across all validators on the network. See [Configuration Reference](configuration.md#network-profiles).

!!! info "Environment Variables"
    See [Configuration Reference](configuration.md#environment-variables) for detailed documentation of all environment variables and `rayls node` flags.

### Phase 4 (validators only): On-chain Registration

Before a freshly provisioned validator can join the committee, it must be registered on-chain (observers skip this). With the validator running:

1. **Fund** the validator's operator key with native tokens.
2. **Allowlist** it: an admin (`MAINTAINER` role) calls `ConsensusRegistry.allowlistValidator(<address>)`.
3. **Stake**: the operator key calls `ConsensusRegistry.stake(...)` using calldata produced by `rayls keytool stake-calldata`.
4. **Activate**: the operator key calls `ConsensusRegistry.activate()`.

The validator enters `PendingActivation` and becomes `Active` at the next epoch boundary. See [node lifecycle](configuration.md#on-chain-validator-registration) for the full sequence.

### Start the Service

```bash
cd /opt/rayls
sudo docker compose up -d

# Check logs
sudo docker compose logs -f privacy-node
```

### Create a Systemd Service for Docker Compose

Enable automatic startup on boot:

```bash
sudo tee /etc/systemd/system/rayls-sovereign-node.service > /dev/null <<EOF
[Unit]
Description=Rayls Privacy Node (axyl validator)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/rayls
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable rayls-sovereign-node
sudo systemctl start rayls-sovereign-node
```

### Managing the Service

```bash
# Check status
sudo systemctl status rayls-sovereign-node

# View logs
docker compose logs -f

# Restart
sudo systemctl restart rayls-sovereign-node

# Stop
sudo systemctl stop rayls-sovereign-node
```

---

## Firewall Configuration

Validators need their **HTTP-RPC (TCP)** port reachable by clients **and** their **consensus QUIC (UDP)** ports reachable by the other validators.

### UFW (Ubuntu/Debian)

```bash
# Allow SSH (if not already)
sudo ufw allow 22/tcp

# Allow RPC port (restrict to specific IPs in production)
sudo ufw allow 8545/tcp

# Allow consensus QUIC ports from peer validators (UDP)
sudo ufw allow 49590/udp
sudo ufw allow 49595/udp

# Enable firewall
sudo ufw enable
```

### Firewalld (CentOS/RHEL)

```bash
sudo firewall-cmd --permanent --add-port=8545/tcp
sudo firewall-cmd --permanent --add-port=49590/udp
sudo firewall-cmd --permanent --add-port=49595/udp
sudo firewall-cmd --reload
```

!!! warning "Security"
    In production, restrict port 8545 to known IP addresses or use a reverse proxy with authentication. Restrict the UDP consensus ports to the other validators' IPs.

---

## Validation

Test the node is running:

```bash
curl http://localhost:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

Expected (for `--chain-id 487`): `{"jsonrpc":"2.0","id":1,"result":"0x1e7"}`

Confirm blocks are advancing:

```bash
curl http://localhost:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

Test from remote (replace `<vps-ip>`):

```bash
curl http://<vps-ip>:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

---

## Connecting Applications

```bash
BLOCKCHAIN_CHAINID=487
BLOCKCHAIN_CHAINURL=http://<vps-ip>:8545
```

---

## Next Steps

- Need high availability? See [Kubernetes](kubernetes.md)
- Configure settings: [Configuration Reference](configuration.md)
- Set up monitoring: [Monitoring Guide](monitoring.md)
- Having issues? [Troubleshooting](troubleshooting.md)
