# Configuration

Each service is configured with an env file (passed as `run --env <file>`). Below are complete `.env` templates — replace the `<...>` placeholders. Values marked `# secret` come from the [secret store](security.md#secrets), never hard-coded.

!!! note "Ports are defaults"
    The ports shown (`8080`, `8090`, `4222`, `9000`, `3003`, …) are application defaults and fully configurable. Only the values that must be wired between two components are called out.

---

## CTS — `cts.env`

```dotenv
# --- Database (must pre-exist; CTS auto-migrates) ---
CTS_DATABASE_CONNECTIONSTRING=postgres://<user>:<pass>@<host>:5432/rayls_cts_<name>?sslmode=disable

# --- API auth (secret) ---
CTS_API_KEY=<secret>
CTS_SECRET=<secret>
CTS_CORSDOMAIN=*

# --- At-rest encryption (KMS) ---
CTS_ENCRYPTORSERVICE=aws            # plaintext | aws | gcp  (use aws/gcp in prod)
CTS_AWSPROFILE=<aws-profile>        # if aws
CTS_AWSALIAS=<kms-alias>            # if aws
# CTS_GCPPROJECT=<...>              # if gcp
# CTS_GCPLOCATION=<...>
# CTS_GCPKEYRING=<...>
# CTS_GCPCRYPTOKEY=<...>

# --- Chains ---
BLOCKCHAIN_CHAIN_ID=<pno-chain-id>
PNH_OPERATOR_CHAIN_ID=<pnh-operator-chain-id>
PNH_RPC_URL=http://<pnh-host>:<port>
PRIVACY_NODE_RPC_URL=http://<pno-host>:<port>
PNH_DEPLOYMENT_PROXY_REGISTRY=<0x... from PNH deploy>
PRIVACY_NODE_DEPLOYMENT_PROXY_REGISTRY=<0x... from PNo deploy>
# Public chain (only if the public relayer is used):
PUBLIC_CHAIN_RPC_URL=https://mainnet-rpc.rayls.com
PUBLIC_CHAIN_DEPLOYMENT_PROXY_REGISTRY=<0x... from public-chain deploy>

# --- NATS (mTLS) ---
NATS_URL=nats://<nats-host>:4222
NATS_TLS_CA_FILE=/certs/ca.crt
NATS_TLS_CERT_FILE=/certs/cts.crt
NATS_TLS_KEY_FILE=/certs/cts.key

# --- gRPC/HTTP server (mTLS); ports are defaults, configurable ---
CTS_GRPC_PORT=8080
CTS_HTTP_PORT=8090
CTS_TLS_CA_FILE=/certs/ca.crt
CTS_TLS_CERT_FILE=/certs/server.crt
CTS_TLS_KEY_FILE=/certs/server.key

# --- Logging ---
LOG_LEVEL=INFO
LOG_HANDLER=Text
```

!!! danger "Never run production with plaintext at-rest encryption"
    Set `CTS_ENCRYPTORSERVICE=aws` (or `gcp`) in production. See [Security → KMS](security.md#kms-cts-at-rest-encryption).

The `*_DEPLOYMENT_PROXY_REGISTRY` values come from [Smart-Contract Deployment](smart-contracts.md#values-to-capture).

---

## Private Relayer — `relayer.env`

```dotenv
# --- Database (must pre-exist; auto-migrates) ---
PRIVATE_RELAYER_DATABASE_CONNECTIONSTRING=postgres://<user>:<pass>@<host>:5432/rayls_privacy_relayer_<name>?sslmode=disable

# --- Privacy Node (PNo) ---
PRIVACY_NODE_CHAIN_ID=<pno-chain-id>
PRIVACY_NODE_RPC_URL=http://<pno-host>:<port>
PRIVACY_NODE_STARTING_BLOCK=<block-at-deploy>
PRIVACY_NODE_DEPLOYMENT_PROXY_REGISTRY=<0x... from PNo deploy>
PRIVACY_NODE_ENYGMA_PROOF_API_ADDRESS=http://<gnark-host>:3003
PRIVACY_NODE_EXECUTOR_BATCH_MESSAGES=1000
PRIVACY_NODE_EXECUTOR_ENYGMA_BATCH_MESSAGES=1000
PRIVACY_NODE_EXECUTOR_ENYGMA_MAX_CONCURRENT_RESOURCE_IDS=2
BLOCKCHAIN_LISTENER_BATCH_BLOCKS=50

# --- Private Network Hub (PNH) ---
PNH_RPC_URL=http://<pnh-host>:<port>
PNH_CHAIN_ID=<pnh-chain-id>
PNH_OPERATOR_CHAIN_ID=<pnh-operator-chain-id>
PNH_DEPLOYMENT_PROXY_REGISTRY=<0x... from PNH deploy>
PNH_CHAIN_STARTING_BLOCK=<block-at-deploy>
PNH_ATOMIC_REVERT_STARTING_BLOCK=<block-at-deploy>
PNH_EXPIRATION_REVERT_TIME_IN_MINUTES=30m

# --- CTS client (gRPC over mTLS) ---
CTS_GRPC_URL=<cts-host>:8080
CTS_API_KEY=<secret>
CTS_SECRET=<secret>
KOS_APP_API_KEY=<same as CTS_API_KEY>     # v3.0.0 requires this second pair
KOS_APP_SECRET=<same as CTS_SECRET>
CTS_CLIENT_TLS_CA_FILE=/certs/ca.crt
CTS_CLIENT_TLS_CERT_FILE=/certs/private-relayer.crt
CTS_CLIENT_TLS_KEY_FILE=/certs/private-relayer.key

# --- NATS (mTLS) ---
NATS_URL=nats://<nats-host>:4222
NATS_TLS_CA_FILE=/certs/ca.crt
NATS_TLS_CERT_FILE=/certs/private-relayer.crt
NATS_TLS_KEY_FILE=/certs/private-relayer.key

# --- Enygma / misc ---
NUMBER_OF_JS_PARAMS_IN=10
DVP_MERKLE_TREE_DEPTH=8

# --- Health / logging (port is default, configurable) ---
PRIVATE_RELAYER_HEALTHCHECK_PORT=9000
LOG_LEVEL=INFO
LOG_HANDLER=Text
```

!!! info "v3.0.0 requires the second CTS credential pair"
    Set `KOS_APP_API_KEY` / `KOS_APP_SECRET` to the same values as `CTS_API_KEY` / `CTS_SECRET`. Omitting them fails validation on startup.

The private relayer bridges **PNo ↔ PNH** — see [Relayer](../../learn/components/relayer/relayer.md).

---

## Public Relayer — `pubrelayer.env`

```dotenv
# --- Database (must pre-exist; auto-migrates) ---
RAYLS_NODE_DATABASE_CONNECTIONSTRING=postgres://<user>:<pass>@<host>:5432/rayls_privacy_relayer_public_<name>?sslmode=disable

# --- Privacy Node (PNo) ---
PRIVACY_NODE_CHAIN_ID=<pno-chain-id>
PRIVACY_NODE_RPC_URL=http://<pno-host>:<port>
PRIVACY_NODE_STARTING_BLOCK=<block-at-deploy>
PRIVACY_NODE_DEPLOYMENT_PROXY_REGISTRY=<0x... from PNo deploy>

# --- Public Chain = Rayls Mainnet ---
PUBLIC_CHAIN_RPC_URL=https://mainnet-rpc.rayls.com
PUBLIC_CHAIN_CHAIN_ID=72957
PUBLIC_CHAIN_STARTING_BLOCK=<Mainnet block at onboarding>   # do NOT use 0 on a live chain
PUBLIC_CHAIN_DEPLOYMENT_PROXY_REGISTRY=<0x... from public-chain deploy>

# --- CTS client (gRPC over mTLS) ---
CTS_GRPC_URL=<cts-host>:8080
CTS_API_KEY=<secret>
CTS_SECRET=<secret>
CTS_CLIENT_TLS_CA_FILE=/certs/ca.crt
CTS_CLIENT_TLS_CERT_FILE=/certs/public-relayer.crt
CTS_CLIENT_TLS_KEY_FILE=/certs/public-relayer.key

# --- NATS (mTLS) ---
NATS_URL=nats://<nats-host>:4222
NATS_TLS_CA_FILE=/certs/ca.crt
NATS_TLS_CERT_FILE=/certs/public-relayer.crt
NATS_TLS_KEY_FILE=/certs/public-relayer.key

# --- Logging ---
LOG_LEVEL=INFO
LOG_HANDLER=Text
```

The public relayer bridges **PNo ↔ Rayls Mainnet** and is **required to use the public chain** — see [Public Relayer](../../learn/components/relayer/public-relayer.md).

---

## Secret keys

Read from the [secret store](security.md#secrets): `CTS_API_KEY`, `CTS_SECRET`, the Postgres connection material, `MONGODB_CONN` (if backend), and the backend keys (`OWNER_PRIVATE_KEY`, `USER_AUTH_KEY`, `OPERATOR_AUTH_KEY`).

---

**Navigate:**

- [Next: Security](security.md)
- [Smart-Contract Deployment](smart-contracts.md)
- [Verification & Troubleshooting](verification.md)
