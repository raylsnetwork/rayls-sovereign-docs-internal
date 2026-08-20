# Smart-Contract Deployment

Contracts live in `rayls-sovereign-contracts` (`version/3.0.0`). **Order is fixed: PNH first, then the Privacy Node, then (if using Mainnet) the public chain.** The relayer and CTS cannot start correctly without the resulting **deployment-proxy-registry** addresses.

!!! note "You deploy contracts onto the public chain — not the chain itself"
    You do **not** deploy the public **chain** (Rayls Mainnet already exists) — but you **do** deploy **your participant's Rayls Node contracts onto** it, which produces the public-chain registry.

For background on what these contracts are, see [Smart Contracts](../../learn/components/smart-contracts/index.md).

---

## Prerequisite — configure the contracts repo

**Before any deploy**, configure `rayls-sovereign-contracts`. All names below (**network names, participant letters, chain IDs**) are **defined by you** — the dev values shown are only examples.

1. **Networks** — add an entry per chain in `hardhat.config.ts` (RPC URL + chainId). You need one for the **PNH**, one per **PNo**, and one for the **public chain**. Dev examples: `development` (PNH), `dev_pn_0`..`dev_pn_5` (PNos), `public_chain_dev` (public).
2. **`.env`** — fill the deploy configuration:

    ```dotenv
    PRIVATE_KEY_SYSTEM=<deployer/system private key>
    PNH_RPC_URL=<pnh rpc>
    PNH_CHAIN_ID=<pnh chain id>
    PRIVACY_NODE_A_RPC_URL=<pno-A rpc>
    PRIVACY_NODE_A_CHAIN_ID=<pno-A chain id>
    # ...repeat PRIVACY_NODE_<X>_* per participant
    ```

---

## Deploy — run the hardhat tasks

The examples deploy **participant A**. Substitute your own network names / participant letters.

```bash
# 1. PNH (Private Network Hub)
npx hardhat deploy:private-hub --network development

# 2. Privacy Node — once per participant
npx hardhat deploy:privacy-node --privacy-node A --network dev_pn_0

# 3. Public chain — once per participant (OPTIONAL, only to use Mainnet)
#    ./deploy/pcDeployContractsAndUpdateEnvs.sh <PARTICIPANT> <NETWORK> <CHAIN_ID>
./deploy/pcDeployContractsAndUpdateEnvs.sh A public_chain_dev 1337
```

- The **PNH** deploy activates business roles (`NETWORK_OPERATOR`, `NETWORK_AUDITOR`, `COMPLIANCE_OFFICER`, `TOKEN_MANAGER`); the **PNo** deploy activates its own roles; the **public-chain** deploy grants the public AccessManager roles.
- `deploy:public-chain` deploys the participant's Rayls Node contracts **onto the public chain** — it does **not** create the chain (Rayls Mainnet already exists).

!!! warning "Production substitution — chain id"
    The `1337` above is the **dev testnet** chain id. In production use the **Rayls Mainnet** network (RPC `https://mainnet-rpc.rayls.com`, **chainId `72957`**), e.g.

    ```bash
    ./deploy/pcDeployContractsAndUpdateEnvs.sh A <mainnet-network> 72957
    ```

---

## Values to capture

Record these outputs — they are consumed by CTS and the relayers via [environment variables](configuration.md):

| Output | Consumed as |
|---|---|
| PNH deployment-proxy-registry | `PNH_DEPLOYMENT_PROXY_REGISTRY` (relayer + CTS) |
| PNo deployment-proxy-registry | `PRIVACY_NODE_DEPLOYMENT_PROXY_REGISTRY` (relayer + CTS) |
| **Public-chain registry** | `PUBLIC_CHAIN_DEPLOYMENT_PROXY_REGISTRY` (public relayer + CTS) |
| PNH / PNo / public starting blocks | `*_STARTING_BLOCK` (relayers) |

!!! warning "Do not use a zero starting block on a live chain"
    For the public chain, capture the **onboarding block** and set `PUBLIC_CHAIN_STARTING_BLOCK` to it. `STARTING_BLOCK=0` on a live Mainnet makes the public relayer scan the entire chain history.

---

## Authorize the relayer keys on-chain

This is what lets the relayers actually sign. **Run it after CTS is up** (CTS exposes the relayer key addresses that these tasks read). Grant `RELAYER` on each AccessManager:

```bash
# Private Network Hub
npx hardhat add-authorized-relayers-pnh

# Privacy Node (private relayer). Add --with-public-relayer true to ALSO
# authorize the public relayer's addresses on the public-chain AccessManager.
npx hardhat add-authorized-relayers --pn A
npx hardhat add-authorized-relayers --pn A --with-public-relayer true

# verify:
npx hardhat list-authorized-relayers
```

!!! info "Why CTS readiness is gated on /public/addresses"
    Until this runs, CTS `/ready` stays `503` and the relayer cannot sign — that is why CTS readiness is gated on `/public/addresses` (which answers `200` pre-authorization) rather than `/ready`.

For the full catalogue of role-management tasks, see [Authorization Operations](../privacy-node/authorization-operations.md).

---

**Navigate:**

- [Next: Configuration](configuration.md)
- [Prerequisites & Bring-up Order](prerequisites.md)
- [Authorization Operations](../privacy-node/authorization-operations.md)
