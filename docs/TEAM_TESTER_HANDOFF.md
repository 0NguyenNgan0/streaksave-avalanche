# TS-19 — Tester handoff (StreakSave / Fuji)

## Mission
Independently verify that a **new test wallet** can complete a real demo on Avalanche Fuji: Connect → fund wallet → Approve → Deposit → Streak → authorized mock yield → epoch close → Claim → Withdraw; capture evidence and negative tests. Owner tester: **TBD**. Reviewer (different person): **TBD**.

Read first:
- `docs/FUJI_DEPLOYMENT_SUMMARY.md` (public addresses and hashes)
- `docs/TS-19-FRESH-WALLET-QA.md` (full E01–E09 and N01–N15 protocol)
- `docs/TS-19-EVIDENCE.md` (fill results; do not mark PASS without evidence)
- `docs/SMART-CONTRACT-ARCHITECTURE.md`, `docs/FUJI-DEPLOYMENT.md`

## Preconditions
1. Install/unlock MetaMask or Core Wallet in the **same browser** as the app. Browser must detect EVM provider. If no wallet provider is detected, **do not mark wallet UI as failed until installation is checked**. Log screenshots and console errors if app still fails.
2. Switch wallet to Fuji C-Chain, ID `43113`; use a dedicated test-only wallet. No mainnet money or seed phrase needed.
3. Configure `apps/web/.env.local` with public values in `FUJI_DEPLOYMENT_SUMMARY.md`; `npm ci` then `npm run dev` in `apps/web`.
4. Verify Fuji on-chain config using `scripts/verify-fuji-readonly.ps1`; if RPC errors or mismatches occur, stop and alert A.
5. User U needs test AVAX and 5+ MockUSDC. Ask A to transfer a modest amount of MockUSDC; A/deployer alone can mint. Provider P must have test AVAX and sufficient MockUSDC for mock yield. **Never share mnemonic/private key.**
6. Coordinate EPOCH TIMING: demo has planned 60s epochs. Add yield into the **same** epoch as user's deposit before that epoch ends. Use on-chain currentEpoch, not wall-clock guesses.

## First positive journey (do in order; use fresh U)
- E01: Load app, connect wallet, verify address and chain 43113. Save screenshot.
- E02: A funds U with MockUSDC and gas token. Save token transfer tx hash and balances.
- E03: U approves 5 MockUSDC to StreakSavings. Save approve tx hash; confirm allowance.
- E04: U deposits 5 MockUSDC. Save deposit tx hash, epoch E, principalOf(U)=5, effectiveStreakOf(U)=1 (first deposit).
- E05: P approves token and calls `addMockYield(2 USDC)` before E closes. Save both hashes and `rewardPoolInEpoch(E)`.
- E06: After E closes, check `rewardInEpoch(U,E)` and current epoch. Reward is not claimable before finalization.
- E07: Claim: UI `claimReward()` is for **latest closed epoch only**. If E became older than latest closed, use `claimRewardFor(E)` via verified operator/contract interaction and flag that as a frontend UX gap. Record tx hash, balance and principal before/after.
- E08: Withdraw full principal 5 USDC; verify principalOf(U)=0 and effective streak=0, no principal penalty.
- E09: Refresh, disconnect/reconnect, check on-chain values stay consistent and no fake preview data appears.

**Critical:** Zero-argument `claimReward` only targets `currentEpoch()-1`; historical rewards are permanently claimable on-chain via `claimRewardFor(epoch)`, but the UI may not support them yet. Do not claim UI full E2E PASS if this causes user flow to fail.

## Negative / boundary suite
Execute all N01–N15 from `docs/TS-19-FRESH-WALLET-QA.md`: insufficient balance; reject; double submit; wrong network; invalid amount; same-epoch extra deposit; next consecutive epoch; missed epoch; partial/full withdraw; unauthorized yield; double claim; pre-finalization claim; account switching; 390px/320px mobile.

## Invariants
- `principalOf` follows deposit/withdraw exact 6-decimal units.
- Claim does not reduce principal.
- `MockUSDC.balanceOf(StreakSavings) >= totalPrincipal + totalRewardPool` at each check.
- Finalized end-of-epoch snapshot and reward share consistent; note integer truncation.

## Evidence required
Record in `docs/TS-19-EVIDENCE.md`: integrated commit hash, tester, independent reviewer, wallet public addresses, Fuji addresses, E01–E09 statuses, N01–N15 statuses, tx hashes/URLs, screenshots, observed principal/reward/streak, and any bugs with severity. No secrets, no unredacted unrelated personal information.

## Blocker protocol
- A: no token, yield-provider unavailable, on-chain mismatch, contract revert, epoch scheduling
- B: wallet connect, wrong-network UI, wrong allowance, transaction feedback, reward history UI, mobile breakage
- C: reproducibility, ABI mismatch, documentation, regression gates, evidence/release sign-off

Log blocker as **BLOCKED** or **FAIL**, not PASS. Assign owner, observed behavior, transaction / browser evidence, and re-test result.

## Acceptance
TS-19 DONE only after E01–E09 and required negative cases have recorded, reviewable outcomes, high-priority blockers are resolved, accounting checked and a second person signs off. CI and local builds alone do not meet this definition.
