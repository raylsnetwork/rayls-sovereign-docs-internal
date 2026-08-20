# Troubleshooting & Upgrades

This guide covers common issues, debugging techniques, performance tuning, and upgrade procedures for a Rayls Privacy Node running the **axyl** client (binary `rayls`).

## Common Issues

### Port Already in Use

**Symptom:** A validator fails to start with an "address already in use" error.

Remember that a validator binds **both** a TCP HTTP-RPC port and **UDP** QUIC consensus ports (primary + worker).

**Solution:**

```bash
# Find what is using the RPC (TCP) port
sudo lsof -i :8545

# Find what is using a consensus (UDP) port
sudo lsof -iUDP:49590

# Kill the process (if safe to do so)
sudo kill -9 <PID>

# Or change the RPC port
--http.port 8546
```

---

### Insufficient Disk Space

**Symptom:** Node crashes or stops producing blocks.

**Diagnosis:**

```bash
# Check disk usage
df -h

# Check data directory size (both MDBX databases live here)
du -sh /opt/rayls/data
du -sh /opt/rayls/data/db /opt/rayls/data/consensus-db /opt/rayls/data/static_files
```

**Solutions:**

1. **Add more disk space** to the volume.
2. **Clean Docker resources:**
   ```bash
   docker system prune -a
   ```

!!! danger "Never hand-delete the databases of a running node"
    Do **not** remove `db/`, `consensus-db/`, `blobstore/`, or `static_files/` while the node is running — it will crash, and on consensus DB loss the validator must catch up via state-sync (or, in the worst case, be re-provisioned). These are only safe to clear on a fully fresh setup before keys exist.

---

### Genesis / Key Generation Failed

**Symptom:** `rayls genesis` or `rayls keytool generate` returns an error.

**Solutions:**

1. **Validator info missing for the ceremony** — `rayls genesis` reads every validator's `node-info.yaml` from `<datadir>/genesis/validators/`. Confirm one `*.yaml` per validator is present and that each was produced by `keytool generate validator`.

2. **Proof-of-possession / signature mismatch** — the ceremony validates each validator's proof of possession. If a `node-info.yaml` was regenerated with a different key or execution address, recollect the current file from that validator.

3. **Keys already exist** — `keytool generate` will not overwrite existing keys unless you pass `--force` (which destroys the old keys). On first-time setup, ensure `node-keys/` does not already exist.

4. **BLS passphrase** — `genesis` and `node` need the passphrase that the keys were encrypted with. Confirm `RL_BLS_PASSPHRASE` (or `--bls-passphrase-source`) matches.

5. **Verify volume permissions** (the container runs as UID 1101):
   ```bash
   sudo chown -R 1101:1101 /opt/rayls/data
   ```

---

### RPC Connection Refused

**Symptom:** Cannot connect to `http://localhost:8545`.

**Checklist:**

1. **Is the container running?**
   ```bash
   docker ps | grep rayls
   ```

2. **Check logs for errors:**
   ```bash
   docker logs rayls-sovereign-node
   ```

3. **Verify HTTP-RPC is enabled** — these flags must be present:
   ```bash
   --http
   --http.addr 0.0.0.0
   --http.port 8545
   --http.api all
   ```

4. **Check port binding:**
   ```bash
   docker port rayls-sovereign-node
   ```

5. **Test from inside the container:**
   ```bash
   docker exec rayls-sovereign-node \
     wget -qO- http://localhost:8545 \
     --post-data='{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
     --header='Content-Type: application/json'
   ```

---

### Wrong Chain ID Response

**Symptom:** `eth_chainId` returns an unexpected value.

**Cause:** The validator is running against a different genesis than expected.

**Solution:** The chain ID is fixed at genesis (`rayls genesis --chain-id`) and stored in `genesis/genesis.yaml`. There is no separate `--networkid` flag to keep in sync as there was with Geth. Confirm every validator is using the **same** genesis bundle (`genesis.yaml`, `committee.yaml`, `parameters.yaml`). If they differ, redistribute the canonical bundle and restart.

---

### Node Not Producing Blocks / Stuck

**Symptom:** `eth_blockNumber` is not advancing.

Consensus is multi-validator BFT: the committee needs a quorum (`n >= 3f + 1`) to make progress. A 4-validator committee tolerates **one** failure; lose two and the chain halts.

**Checklist:**

1. **Are enough validators up?**
   ```bash
   docker ps        # or: kubectl get pods -n rayls
   ```

2. **Can validators reach each other over QUIC/UDP?** Consensus runs over libp2p QUIC-v1 (UDP). Verify the primary/worker UDP ports are open between every pair of validators (firewall, security groups). A validator that cannot dial its peers will sit in `CvvInactive` and never join consensus.

3. **Check the node mode in the logs** — a node catching up reports `CvvInactive` (running state-sync); a healthy committee member reports `CvvActive`. An observer reports `Observer`.

4. **Is the validator registered and active on-chain?** A validator only joins the committee after `ConsensusRegistry.activate()` and the next epoch boundary (see [Configuration](configuration.md#on-chain-validator-registration)).

5. **Was the validator's external multiaddr set correctly?** If the QUIC multiaddr baked into the keys is not the address the node is actually reachable at, peers cannot dial it.

---

### Container Keeps Restarting

**Symptom:** Container enters a restart loop.

**Diagnosis:**

```bash
# Check exit code
docker inspect rayls-sovereign-node --format='{{.State.ExitCode}}'

# View logs from the failed attempt
docker logs rayls-sovereign-node --tail 100
```

**Common causes:**

| Exit Code | Cause | Solution |
|-----------|-------|----------|
| 137 | OOM killed | Increase memory limit |
| 1 | Generic error (bad config, wrong/missing BLS passphrase, missing genesis bundle) | Check logs |
| 139 | Segmentation fault | Report a bug; try a known-good image version |

A frequent cause is a missing or wrong **BLS passphrase**, or a missing genesis bundle (`genesis.yaml` / `committee.yaml` / `parameters.yaml`) in the data directory.

---

## Debugging

### Querying the Node over JSON-RPC

axyl has no interactive console. Debug it the same way any client talks to it — JSON-RPC over HTTP with `curl`:

```bash
# Latest block number
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Chain ID
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'

# Gas price (0 on a gasless chain)
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}'

# Full latest block
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}'
```

In addition to the standard `eth_*` namespace, axyl exposes a `rayls_*` namespace; enable it with `--http.api all` (or include `rayls` explicitly).

### Logging

axyl logs to stdout (captured by `docker logs` / `kubectl logs`). Control verbosity with the `RUST_LOG` environment variable and the `--log.*` flags:

```bash
# Increase verbosity for a subsystem
RUST_LOG=info,execution=debug

# Or whole-process debug
RUST_LOG=debug
```

Useful `RUST_LOG` targets include `execution=debug` (EVM/reth) and the consensus targets. The `--log.*` flags (for example `--log.stdout.format`) control format and destination — run `rayls node --help` for the full set.

### Version

Check the client version (replaces `geth version`):

```bash
docker exec rayls-sovereign-node rayls --version
```

### Health Check

If started with `--healthcheck <port>` (or `HEALTHCHECK_TCP_PORT`), the node exposes a TCP health-check endpoint for load balancers and monitors. Keep it behind a firewall.

---

## Performance Tuning

### Memory

Right-size the container memory limit (a busy validator can use well over the 4 GB minimum). Watch for exit code 137 (OOM) and raise the limit accordingly.

### Transaction Pool

The reth-based execution layer is tuned with `--txpool.*` flags. The canonical high-throughput, gasless-friendly set (from `etc/docker-network/compose.yaml`) is reproduced in the [Configuration Reference](configuration.md#canonical-production-flag-set). Key entries:

```bash
--txpool.minimal-protocol-fee 0     # accept zero-fee txs (required on gasless chains)
--txpool.pending-max-count 50000
--txpool.queued-max-count 50000
--txpool.max-account-slots 50000
--gpo.default-suggested-fee 0
```

### Consensus Database

The consensus database is MDBX. Its size can be tuned with `--consensus-db.max-size` (and related `--consensus-db.*` flags). Use fast SSD-backed storage for both `db/` and `consensus-db/`.

### I/O

Use SSD storage for the data directory; both MDBX databases are I/O sensitive.

---

## Upgrade Procedure

### Pre-Upgrade Checklist

- [ ] Review release notes for breaking changes (especially genesis/hardfork-affecting ones)
- [ ] Back up each validator's `node-keys/` (irreplaceable) and snapshot the data PVC/volume
- [ ] Test the upgrade in a staging cluster
- [ ] Upgrade validators in a rolling fashion so the committee keeps quorum
- [ ] Confirm all validators end up on the **same** client version

!!! warning "Rolling upgrades preserve quorum"
    Because the chain needs a BFT quorum, upgrade validators one at a time and wait for each to rejoin (`CvvActive`, block height caught up) before moving to the next. Never restart enough validators at once to drop below quorum.

### Docker/VPS Upgrade (per validator, rolling)

```bash
# 1. Snapshot data and back up keys
docker compose down
tar -czf backup-pre-upgrade-$(date +%Y%m%d).tar.gz /opt/rayls/data

# 2. Update the image tag in docker-compose.yml to the new version
sed -i 's#rayls-stack-node-client:<old>#rayls-stack-node-client:<new>#g' /opt/rayls/docker-compose.yml

# 3. Pull and start the new version
docker compose pull
docker compose up -d

# 4. Verify it rejoins and catches up
docker compose logs -f
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

Repeat for the next validator only once this one is healthy.

### Kubernetes Upgrade (StatefulSet rolling update)

```bash
# 1. Update the image
kubectl set image statefulset/rayls-sovereign-node \
  validator=rayls-stack-node-client:<new> \
  -n rayls

# 2. Monitor the rolling update (StatefulSet updates pods one at a time)
kubectl rollout status statefulset/rayls-sovereign-node -n rayls

# 3. Verify
kubectl logs -f rayls-sovereign-node-0 -n rayls
```

### Rollback

**Docker/VPS:**
```bash
docker compose down
rm -rf /opt/rayls/data
tar -xzf backup-pre-upgrade-YYYYMMDD.tar.gz -C /
sed -i 's#rayls-stack-node-client:<new>#rayls-stack-node-client:<old>#g' /opt/rayls/docker-compose.yml
docker compose up -d
```

**Kubernetes:**
```bash
kubectl rollout undo statefulset/rayls-sovereign-node -n rayls
```

---

## Crash Recovery

axyl is designed to recover from on-disk state after an unclean stop:

- The execution chain is rebuilt from MDBX (`db/`); blocks only in memory at crash time are re-produced from the cached consensus output the consensus DB still holds.
- The consensus DAG is reconstructed from the certificate store in `consensus-db/`.
- A validator that was `Active` when it crashed typically comes back as `CvvInactive`, catches up from peers via state-sync, then re-promotes itself to `CvvActive`.

So the usual recovery action is simply to **restart the validator** and let it catch up — do not delete its databases.

---

## Getting Help

### Information to Collect

When reporting an issue, include:

1. **Client version:**
   ```bash
   docker exec rayls-sovereign-node rayls --version
   ```

2. **Configuration (sanitized):**
   - `docker-compose.yml` / StatefulSet manifest
   - the `rayls node` flags in use
   - `parameters.yaml` and the `chain-id` from `genesis.yaml`

3. **Logs:**
   ```bash
   docker logs rayls-sovereign-node --tail 500 > logs.txt
   ```

4. **System info:**
   ```bash
   uname -a
   docker --version
   free -h
   df -h
   ```

### Resources

- **Node Image:** `rayls-stack-node-client` (Rayls private registry)
- **Build from source:** `cargo build -p rayls-network --release`

---

## Related Pages

- [Configuration Reference](configuration.md) - All configuration options
- [Monitoring](monitoring.md) - Health checks and metrics
- [Local Development](local.md) - Quick start guide
