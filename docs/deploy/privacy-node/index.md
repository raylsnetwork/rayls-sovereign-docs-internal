# Privacy Node Deployment Guide

This guide provides instructions for deploying a Rayls Privacy Node in various environments using the **axyl** node client.

## Supported Deployment Scenarios

| Scenario | Best For | Guide |
|----------|----------|-------|
| [Local Development](local.md) | Testing, development | Docker Compose multi-validator cluster |
| [VPS/Virtual Machine](vps.md) | Small deployments, staging | Docker Compose or Systemd |
| [Kubernetes](kubernetes.md) | Production, scalable | Full K8s manifests (StatefulSet) |

## What is a Privacy Node?

A Privacy Node (PN) is a private, fully EVM-compatible blockchain infrastructure that can be installed on-premises or in any cloud environment.

The blockchain client is **axyl** — a Rust node (binary `rayls`, crate `rayls-network`) that combines:

- A **reth-based EVM execution layer** (Rust, EVM-compatible), exposing the standard `eth_*` JSON-RPC namespace plus a `rayls_*` namespace (and an optional faucet).
- A **Narwhal + Bullshark multi-validator BFT consensus layer**. The committee is multi-validator (4 validators by default) and is tracked on-chain via the `ConsensusRegistry` contract, rotating each epoch.

A Privacy Node is therefore **not a single node** — it is a **multi-validator cluster**. A 1-of-1 committee has no Byzantine fault tolerance and is refused by the client unless it was built with the `dev` feature (local development only).

The Privacy Node is responsible for:

- Executing private transactions
- Maintaining a private ledger via the BFT-ordered EVM chain
- Exposing JSON-RPC endpoints for downstream components

!!! info "Migration from the legacy Geth client"
    Earlier Privacy Node releases shipped a single-node Geth fork that used Clique signing, an embedded signer keystore, and a MongoDB (`--db.engine mongodb`) backend. That client has been replaced by **axyl**. The procedures below describe the axyl multi-validator model; the old `geth init` / `geth` flow no longer applies.

## Node Modes

Each axyl node reports one of three modes, declared by the orchestrator:

| Mode | Description |
|------|-------------|
| `CvvActive` | Committee-voting validator currently participating in consensus (proposing, voting). |
| `CvvInactive` | Allowlisted validator that is catching up (runs the state-sync subscriber) or temporarily out of consensus. |
| `Observer` | Non-validating node that streams committed consensus output from a peer and serves RPC only. |

## System Requirements

These requirements are **per validator** (a default cluster runs 4 validators).

### Minimum (Development/Testing)

| Resource | Requirement |
|----------|-------------|
| CPU | 2 vCPU |
| RAM | 4 GB |
| Storage | 100 GB SSD |
| Docker | 20.10+ |
| Kubernetes | 1.20+ (if using K8s) |

### Recommended (Production)

| Resource | Requirement |
|----------|-------------|
| CPU | 4+ vCPU |
| RAM | 16 GB |
| Storage | 500 GB High-performance SSD |
| Docker | 24.0+ |
| Kubernetes | 1.25+ (if using K8s) |

!!! note "Networking"
    Consensus runs over libp2p **QUIC-v1 (UDP)**. Each validator must be able to reach every other validator's primary and worker QUIC/UDP ports. Plan firewall rules for UDP, not just the TCP HTTP-RPC port.

## Quick Reference

### Node Image

The Privacy Node runs from the **`rayls-stack-node-client`** image, built from the axyl repository's `etc/docker-network/Dockerfile` and published to Rayls' private container registry.

> NOTE: There is no public registry mirror for the axyl client. Pull `rayls-stack-node-client` from Rayls' private registry, or build the image locally from the axyl repository.

You can also build the binary directly from source:

```bash
# From a checkout of the axyl repository
cargo build -p rayls-network --release
# Binary: target/release/rayls-network  (installed as /usr/local/bin/rayls)
```

### Deployment Outline

A Privacy Node is brought up in three phases:

1. **Key generation** — each validator runs `rayls keytool generate validator` to create its encrypted BLS keys, deterministic Ed25519 network keys, and `node-info.yaml`.
2. **Genesis ceremony** — one operator collects every validator's `node-info.yaml`, runs `rayls genesis` to produce `genesis.yaml`, `committee.yaml`, and `parameters.yaml`, then distributes those files to all validators.
3. **Run** — each validator runs `rayls node` against its data directory.

See [Local Development](local.md) for the concrete commands.

### Test Connection

```bash
curl -X POST http://localhost:8545 -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

The result is the hex-encoded chain ID set with `rayls genesis --chain-id`.

## Environment Variables for Downstream Components

Components connecting to a Privacy Node validator's HTTP-RPC require:

```bash
BLOCKCHAIN_CHAINID=487
BLOCKCHAIN_CHAINURL=http://rayls-sovereign-node:8545  # Kubernetes (service name)
BLOCKCHAIN_CHAINURL=http://localhost:8545           # Docker
BLOCKCHAIN_CHAINURL=http://<vps-ip>:8545            # VPS
```

> NOTE: Point downstream components at a validator's HTTP-RPC port, or at a load balancer in front of several validators. The chain ID must match the value passed to `rayls genesis --chain-id`.

## Network Profiles

The `--network {local|devnet|testnet|mainnet}` flag (also settable via the `RAYLS_NETWORK` environment variable) selects the baked-in hardfork profile. Profiles differ in their EIP-1559 activation block: local and mainnet activate at block 0, devnet at block 50, and testnet at block 281800.

## Resources

- **Node Image:** `rayls-stack-node-client` (Rayls private registry)
- **Build from source:** `cargo build -p rayls-network --release`

!!! warning "Version Compatibility"
    All validators in the same network must run identical client versions and the **same** `genesis.yaml`, `committee.yaml`, and `parameters.yaml`.

## Next Steps

Choose your deployment scenario:

- **Getting started?** Begin with [Local Development](local.md)
- **Deploying to a server?** See [VPS Deployment](vps.md)
- **Production deployment?** Follow [Kubernetes Guide](kubernetes.md)
- **Need configuration details?** Check [Configuration Reference](configuration.md)
