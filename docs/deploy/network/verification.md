# Verification & Troubleshooting

Once the stack is up, confirm each component is healthy and processing, then use the symptom table to diagnose the common failure modes.

---

## Verification

- **Relayer health** — `GET /healthcheck` on the private/public relayer.
- **Relayer progress** — `GET /merkletree` returns the last processed block for the merkle tree and the private hub.
- **CTS** — `GET /public/addresses?service=private_relayer` returns `200` once CTS has its keys.
- **End-to-end** — a cross-chain transfer confirms the full path (the `rayls-sovereign-contracts` test suites exercise this).

```bash
# Private relayer health
curl -s http://<private-relayer-host>:9000/healthcheck

# Relayer progress (last processed blocks)
curl -s http://<private-relayer-host>:9000/merkletree

# CTS keys ready (200 once CTS has its keys)
curl -s -o /dev/null -w "%{http_code}\n" \
  "http://<cts-host>:8090/public/addresses?service=private_relayer"
```

!!! tip "Confirm the ledgers first"
    Before checking the relayers, verify the Privacy Node and PNH RPCs answer `eth_chainId` / `eth_blockNumber` and that the block number is advancing. See the [Privacy Node validation steps](../privacy-node/local.md#step-6-validate).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Relayer fails validation on startup | missing required var / empty registry | ensure contracts are deployed and the `*_DEPLOYMENT_PROXY_REGISTRY` values are set (see [Smart-Contract Deployment](smart-contracts.md)) |
| CTS `/ready` never green | relayer keys not authorized on-chain | run `add-authorized-relayers` (see [Authorize the relayer keys](smart-contracts.md#authorize-the-relayer-keys-on-chain)) |
| NATS clients rejected | cert not signed by the shared CA, or hostname ≠ server-cert SAN | reissue leaf certs off the shared CA; use a hostname in the SAN (see [Security → mTLS](security.md#mtls-mandatory-in-v300)) |
| Postgres "database does not exist" | per-participant DB not pre-created | create the relayer/public-relayer/CTS databases (see [Databases](prerequisites.md#databases)) |
| CTS/relayer `context deadline exceeded` on a chain | wrong/unreachable RPC URL | point at the reachable PNo/PNH RPC |
| Public relayer sees nothing | wrong Mainnet registry or `STARTING_BLOCK=0` | set the onboarding registry + the onboarding block |

---

**Navigate:**

- [Back to Overview](index.md)
- [Configuration](configuration.md)
- [Privacy Node Troubleshooting](../privacy-node/troubleshooting.md)
