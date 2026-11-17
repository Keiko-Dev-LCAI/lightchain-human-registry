# Lightchain Human Registry

*One badge per human. No personal data on chain. Owned by the community.*

- **Author:** KeikoDev
- **Status:** proof of concept (concept demo, contract source and deploy guide). Nothing is deployed.
- **License:** MIT. Anyone can deploy it.

---

## 1. The problem

On any open chain, one person can create thousands of wallets for free. That breaks anything meant to be "one per person":

- **Giveaways and sweepstakes** get farmed by bot wallets, so real community members lose out.
- **Free tiers** in apps get drained. A new wallet means a new free tier, again and again.
- **Polls and community votes** can be stuffed by one person with many wallets.
- **Spam** in disputes, messages and comment systems costs nothing to send from throwaway wallets.

Today each app fights this alone, usually by collecting emails, phone numbers or KYC documents. That data then becomes a target for leaks.

## 2. The idea

A single, shared **Human Registry** contract on Lightchain (chain 9200).

- A person proves **once** that they hold a real government-issued passport or ID card.
- Their wallet gets a "verified human" badge.
- Any Lightchain app can ask one question: `isHuman(wallet)`. The answer is yes or no.
- **One passport, one badge.** The same passport cannot give badges to two wallets at once.

## 3. How it works

1. **Prove on your own phone.** The user opens the free ZKPassport app and taps their passport or ID card on the phone. The phone reads the chip and checks the government's digital signature.
2. **A zero-knowledge proof is created on the phone.** It says "this is a real, valid document" and nothing else: no name, no birthday, no photo, no document number.
3. **A private code comes with it.** The proof includes an app-specific code (a "nullifier"). The same passport always produces the same code for this registry, but the code reveals nothing about the person. It also can't be linked to other apps that use ZKPassport.
4. **Submit from your wallet.** The proof is tied to the wallet that submits it. The registry contract checks the proof on chain and records the pair *(code → wallet)*.
5. **Second wallet, same passport?** The registry recognises the code and says "already verified human". No second badge.
6. **Lost your wallet?** Prove again from your new wallet and choose "move badge". The badge moves, and the old wallet is switched off.
7. **Apps just ask.** `isHuman(0x…)` returns true or false. Apps never see any personal data.

## 4. Privacy

- **The registry stores only two things:** a code and a wallet address.
- **The phone is the intended place the document is read.** ZKPassport's on-chain path can use their cloud prover for compressed proofs. Treat "the document never leaves the phone" as their app's claim, not as a promise this proof of concept can make.
- **Ask for a salted code.** ZKPassport's default (unsalted) code can be recomputed by anyone who has the chip data, including the government that issued the document, and then matched to the wallet. This draft contract accepts both salted and unsalted codes so the flow can be demonstrated. A production registry should require the salted code.
- **No names, emails, birth dates, photos, nationalities or document numbers** are stored, and the registry never asks the proof to reveal them.
- **Apps learn one bit:** human or not.
- **The code is specific to this registry.** It can't be matched with codes from other apps.
- **What the chain does show:** that a wallet has a badge, and when a badge moved. If you don't want that public for a given wallet, don't register that wallet.

## 5. Why ZKPassport

We compared several proof-of-personhood systems. Details and sources are in [`research-zkpassport.md`](research-zkpassport.md).

- **Open source, Apache-2.0.** The verifier contracts can be redeployed on any EVM chain, including Lightchain, as long as the license notices are kept.
- **No special hardware.** It works with an ordinary phone with NFC and an e-passport or e-ID. ZKPassport says it covers 130+ countries.
- **Lightchain already has the math it needs.** On 2026-11-17 we tested Lightchain mainnet's built-in cryptography functions with read-only calls: modexp, BN254 add, BN254 multiply and BN254 pairing all returned correct results.
- **It fits.** ZKPassport's verifiers already run on Ethereum mainnet and Base. Lightchain's block gas limit is 60,000,000, so verification fits comfortably. The exact gas cost will be measured before any deployment.
- **Already used in production.** ZKPassport cites Aztec and the Ethereum Foundation as users.

## 6. Use cases

- **Giveaways and sweepstakes:** one entry per passport, so a pile of empty wallets cannot each enter.
- **One free tier per passport:** apps can give a free tier to each badge instead of each wallet.
- **Verified-only polls:** one vote per badge, run alongside the token-weighted DAO rather than replacing it. See the document limits below. This is not one-person-one-vote.
- **Trust signals:** wallet scanners and safety tools (OrcaGuard-style) can show a "verified human" mark.
- **Spam filters:** dispute systems, messaging and comment apps can accept submissions from verified humans only, or rank them first.
- **Agents and listings:** a "human-owned" badge for AI agents or app directory listings.

## 7. Honest limits

- **Tied to the document, not the person.**
  - Someone with two passports (dual citizen) can get two badges.
  - A renewed passport is a new document and a new code. The lost-wallet move works only for the same document, so it does not carry the old badge onto the new passport.
  - It stops bots and wallet farms. It does not make every human exactly one.
- **The passport trust list must be kept updated on chain.**
  - Proofs are checked against a list of government certificates (a "root").
  - On Lightchain, someone has to copy new roots over regularly. If that stops, new proofs fail.
  - This is the main ongoing job, and the reason we're asking the core team / DAO to own it.
- **It doesn't stop someone acting on another person's behalf.** A real person can lend their passport, or sell their verified wallet. The registry proves a real document was used, not who is holding the wallet today.
- **Not everyone has a supported document.** Apps should treat the badge as a bonus or an option, not the only way in.
- **It depends on ZKPassport's phone app** for creating proofs.

## 8. Governance ask

We are not asking anyone to trust KeikoDev. The goal is the opposite.

1. **The Lightchain core team or the DAO adopts it** and deploys the official instance, or deploys our open-source code as is.
2. **Admin goes to the DAO.**
   - The contract has a two-step handover (`transferAdmin` then `acceptAdmin`), so admin can move to the DAO's timelock in one proposal.
   - Admin can only set the fee, set the proof freshness window, and change the verifier address. A verifier change must wait out a public timelock delay.
   - Admin cannot remove or move anyone's badge.
3. **The trust-list update job** (the "oracle") is run by, or on behalf of, the DAO.
4. **Fees are the DAO's decision.** The contract supports an optional fee, set to zero by default. This proposal does not suggest any amount.
5. **Anyone can deploy it.** The code is MIT. If the DAO says no, any community member can still run their own instance.

## 9. FAQ

**Do I have to show my passport to anyone?**
The registry contract does not receive your name, photo, or document number. The phone app is meant to read the chip. If the proof uses ZKPassport's cloud prover, that prover is outside this contract, and an unsalted code can still be tied back to the document by whoever can recompute it.

**What exactly is stored on chain?**
A code (a 32-byte number that means nothing on its own) and your wallet address.

**Can an app find out my name or country?**
Not from this registry. It never asks the proof to reveal those things.

**What if I lose my wallet?**
Prove again from a new wallet and choose "move badge". The old wallet loses its badge.

**Can someone steal my badge?**
Moving a badge requires a fresh proof made with your physical passport, tied to the wallet that submits it. Older proofs can't be replayed to move a badge back.

**Does this cost anything?**
The contract allows an optional fee, which is zero by default. Any fee is up to the DAO. Normal network gas applies.

**Is this live?**
No. Today it is a concept demo, contract source code and a deploy guide. Nothing is deployed.

**Who is behind this?**
KeikoDev, a Lightchain community builder. The plan is for the project not to depend on KeikoDev at all.

---

*Files in this proof of concept: [`README.md`](README.md) · [`contracts/HumanRegistry.sol`](contracts/HumanRegistry.sol) · [`DEPLOY.md`](DEPLOY.md) · [`demo/index.html`](demo/index.html)*
