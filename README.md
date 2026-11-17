# Lightchain Human Registry: proof of concept

**One "verified human" badge per passport, for any Lightchain app. No personal data on chain.**

This is a community proof of concept by **KeikoDev**. It shows how a zero-knowledge proof-of-personhood registry could work on Lightchain (chain 9200), using ZKPassport proofs. **Nothing here is deployed.** The aim is for the Lightchain core team or the DAO to adopt it and hold its admin.

## What's in here

| File | What it is |
|---|---|
| [`PROPOSAL.md`](PROPOSAL.md) | The plain-language pitch: problem, how it works, privacy, limits, governance ask, FAQ |
| [`demo/index.html`](demo/index.html) | **Interactive concept demo, not a live product.** Runs entirely in the browser with pretend data and no blockchain. Live copy: https://keiko-dev-lcai.github.io/lightchain-human-registry/ |
| [`contracts/HumanRegistry.sol`](contracts/HumanRegistry.sol) | Registry contract source (MIT, Solidity ^0.8.24). **Not compiled, tested, audited or deployed.** Calls a ZKPassport verifier by address. |
| [`DEPLOY.md`](DEPLOY.md) | Step-by-step guide for anyone to deploy on Lightchain. All steps are marked untested. |
| [`research-zkpassport.md`](research-zkpassport.md) | Research notes on ZKPassport, with official source links |
| [`LICENSE`](LICENSE) | MIT |

## How the pieces connect

1. Read **PROPOSAL.md** for the idea.
2. Try **demo/index.html** to see the flow: connect, scan, badge, duplicate blocked, lost-wallet move, app check, giveaway.
3. **contracts/HumanRegistry.sol** is the on-chain version of what the demo simulates.
4. **DEPLOY.md** explains how to put the real thing on Lightchain, including the ZKPassport parts it depends on.

## Status

- Concept demo: ready to view offline.
- Contract: draft source. Its ZKPassport interface is marked **UNVERIFIED** until it is checked against a specific ZKPassport release.
- Deployment: none. Fees and admin choices are left to the DAO.

## Third-party code

This repo does **not** include ZKPassport code. The contract only references a deployed ZKPassport verifier by address. ZKPassport's own contracts are Apache-2.0 (verifiers © Aztec, registry contracts © ZKPassport). Anyone deploying them must keep those notices.

## License

MIT License. Copyright (c) 2026 KeikoDev. See [`LICENSE`](LICENSE).
