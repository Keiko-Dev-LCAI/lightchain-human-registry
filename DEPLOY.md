# How to deploy the Human Registry on Lightchain (chain 9200)

- **Author:** KeikoDev
- **Status:** ⚠️ **NOT TESTED.** No step below has been run yet. Every step is marked **[UNTESTED]**.
- **Network:** Lightchain mainnet, chain ID 9200, RPC `https://rpc.mainnet.lightchain.ai`, explorer `https://mainnet.lightscan.app`.
- **Background:** [`research-zkpassport.md`](research-zkpassport.md) (with source links for every ZKPassport fact).

> **Safety:** never paste a private key into a file, a chat or a repo. Use a hardware wallet, or your tool's encrypted keystore with an interactive password prompt. No script in this folder holds keys, and none should.

---

## What you'll deploy

| Part | Whose code | What it does |
|---|---|---|
| ZKPassport verifiers (UltraHonk `HonkVerifier` set) | ZKPassport / Aztec, Apache-2.0 | Check the zero-knowledge proof math |
| ZKPassport `RootRegistry` + `RegistryInstance` (certificate, circuit) | ZKPassport, Apache-2.0 | Hold the passport trust list ("roots") |
| ZKPassport `SubVerifier`, `RootVerifier`, `VerifierHelper` | ZKPassport, Apache-2.0 | Tie it together; the entry point apps call |
| `HumanRegistry.sol` | This repo, MIT | One badge per passport; `isHuman(wallet)` |

**Prerequisites (do these before step 1)**
- **Lightchain already has the needed math.** BN254 add, multiply, pairing and modexp all passed on 2026-11-17, and the block gas limit is 60,000,000.
- **Pick a permanent website domain** for proof requests (for example a DAO-owned domain). It becomes part of every user's code, so it can never change.
- **Get a deployer wallet** with enough LCAI for gas.
- **Install a Solidity toolchain** (for example Foundry), on a machine you control.

---

## Step 1: Deploy ZKPassport's verifier stack [UNTESTED]

ZKPassport's Solidity project is meant to deploy "on any EVM chain".

1. Get ZKPassport's source from its official GitHub org:
   - `zkpassport/circuits` → `src/solidity/` (the UltraHonk verifiers and deploy scripts)
   - `zkpassport/zkpassport-packages` → `packages/registry-contracts/` (registries and verifier wrappers)
2. Pick the **exact release** you deploy and write the version down. The repo showed `0.23.0` on Ethereum and `0.20.0` on Base on 2026-11-17.
3. **EVM version:** On 2026-11-17, read-only mainnet calls executed Shanghai `PUSH0` and Cancun `TLOAD` and `BLOBHASH` and each returned 32 zero bytes. That is opcode support, not a deployed verifier. ZKPassport compiles with solc 0.8.30. If a real deploy fails, compile with an older `evm_version` and record which one worked. The verifier's gas is still unmeasured.
4. Deploy, in this order. Script names are from ZKPassport's repo; read each one before running it.
   1. `RootRegistry` (admin = your deployer for now, guardian = optional).
   2. `RegistryInstance` for **certificate** (registry ID `1`) and **circuit** (registry ID `2`). Set the **oracle** to the wallet that will post roots (step 2), and choose a root validation mode. `VALID_AT_TIMESTAMP` checks a root against the proof's own date.
   3. Register both instances in the `RootRegistry` with `addRegistry(id, address)`.
   4. The `HonkVerifier` contracts (`OuterCount4` … `OuterCount13`).
   5. `RootVerifier`, then `SubVerifier`. Call `addProofVerifiers` (vkeyHash → verifier address), then `RootVerifier.addSubVerifier(version, subVerifier)`.
   6. `VerifierHelper` (pointing at your `RootRegistry`), then `RootVerifier.addHelper(version, helper)`.
5. Write down the **RootVerifier address**. HumanRegistry needs it.
6. **Keep ZKPassport's Apache-2.0 license and copyright notices** with anything you republish.

## Step 2: Keep the passport trust list (roots) updated [UNTESTED]

Proofs are only accepted if their **certificate root** and **circuit root** are known to your registry on Lightchain.

1. **Seed:** copy ZKPassport's current certificate root and circuit root, with their timestamp, leaf count and IPFS cid, into your Lightchain registry instances with `updateRoot(...)` or `batchUpdateRoots(...)`, called from the **oracle** wallet. The source of truth is ZKPassport's registry on Ethereum mainnet (`RootRegistry` at `0x1D0000020038d6E40E1d98e09fA1bb3A7DAA8B70`).
2. **Keep it current:** run a small "mirror" job that watches for new roots on Ethereum and posts each one to Lightchain. If it stops, new users' proofs start failing.
3. **New circuit versions:** when ZKPassport releases new circuits, deploy and register the matching verifiers (repeat steps 1.4.4–1.4.6).
4. **Who runs the mirror:** ideally the Lightchain core team or a DAO-funded operator. The oracle wallet should hold only gas money.
5. **[UNCONFIRMED]** ZKPassport has a helper script `script/test/get-latest-roots.sh`; we have not read it. Ask ZKPassport (the docs invite chains to "reach out") whether they would publish roots to Lightchain directly.

## Step 3: Deploy HumanRegistry [UNTESTED]

1. **Before deploying**, compare the structs and interfaces at the top of `contracts/HumanRegistry.sol` with ZKPassport's `lib/Types.sol` for the release you deployed. They are marked **UNVERIFIED**.
2. Compile `contracts/HumanRegistry.sol` (Solidity ^0.8.24, MIT). Review it and get it audited.
3. Constructor arguments:
   - `_admin`: your deployer for now (handed to the DAO in step 4)
   - `_verifier`: the **RootVerifier** address from step 1
   - `_domain`: your permanent website domain (exact string)
   - `_chainTag`: `lightchain:9200`
   - `_verifierDelay`: at least `172800` (2 days); a longer delay is safer
   - `_validityPeriod`: proof max age in seconds (between 300 and 604800)
4. Deploy, then verify the source on the explorer.
5. **Fee:** it starts at `0`. Any fee is for the DAO to decide later with `setFee`.
6. **Front end:** use the ZKPassport SDK with:
   - `mode: "compressed-evm"`
   - `scope: "lightchain-human-registry"`
   - bind `user_address` = the user's wallet
   - bind `custom_data` = `lightchain:9200`

   Then call `register(params, false)` for new users, or `register(params, true)` for a lost-wallet move. Point the SDK output at **your** verifier, not ZKPassport's Ethereum address.
7. **Smoke test with a real document**, using a throwaway wallet. Mock proofs (dev mode) are rejected by design.
8. **Measure gas** for `register` and record it. This is still unmeasured.

## Step 4: Hand admin to the DAO [UNTESTED]

1. **HumanRegistry:** `transferAdmin(<DAO timelock address>)`, then the DAO executes `acceptAdmin()` through a proposal.
2. **ZKPassport contracts you deployed:** call `transferAdmin(<DAO timelock>)` on `RootRegistry`, each `RegistryInstance`, `RootVerifier` and `SubVerifier`. These are single-step in ZKPassport's code, so **double-check the address** before sending.
3. **Oracle:** move the oracle role (`setOracle`) to the DAO-approved mirror operator.
4. **Guardian (optional):** a DAO security council that can pause in an emergency.
5. Publish all addresses and the transaction hashes so anyone can check that no individual holds admin.

## Checklist before announcing [UNTESTED]

- [ ] Struct/ABI match confirmed against the deployed ZKPassport release
- [ ] Gas for `register` measured on Lightchain
- [ ] Roots seeded and the mirror job running
- [ ] Real-document registration works; second wallet blocked; move works; stale-proof replay blocked
- [ ] Contracts verified on the explorer
- [ ] Admin roles held by the DAO timelock
- [ ] Independent review or audit
