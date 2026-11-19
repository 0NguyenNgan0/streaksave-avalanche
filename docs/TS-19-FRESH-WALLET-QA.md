# TS-19 — Fresh Wallet E2E & Failure-Path QA

**Owner:** Member C • **Priority:** MUST (P0) • **Status:** NOT YET EXECUTED on Fuji • **Date prepared:** 2026-11-19

> The progress checklist requires testing insufficient balance, wallet rejection, double actions and streak reset. This is an execution protocol, NOT a claim that the tests have passed. Attach hashes and observed values in [TS-19-EVIDENCE.md](TS-19-EVIDENCE.md).

## Preconditions and ownership

1. Member A provides a verified deployed `MockUSDC`, `StreakSavings`, epoch duration, immutable `yieldProvider` and explorer links. Check chain ID **43113**, bytecode exists, token `decimals() == 6`, and `StreakSavings.usdc()` equals the MockUSDC address.
2. Member B configures `apps/web/.env.local` with **public addresses only**, restarts the frontend, and confirms wallet's selected chain is Fuji. Read/write ABI checks and production build pass.
3. Prepare **fresh user wallet U** (no prior contract principal), **yield provider P** (authorized deployer), and optional **second user V**. Do not reuse mainnet keys. U needs test AVAX for transaction gas and 5+ MockUSDC. P needs test AVAX and enough MockUSDC to add mock yield. Deployer/minter funds U and V by ERC-20 transfer or controlled mint; no new token distributor contract is necessary.
4. Complete the main positive flow before trying destructive negative scenarios. Use smaller amounts if account balances are limited. Record U and P as addresses only; **never record private keys**.
5. Prefer a fresh session or incognito browser for UI tests; allow adequate buffer around the 60-second epoch boundary. The chain's `currentEpoch()` is authoritative; browser clock alone is not sufficient.

## Main positive flow — U / P

| ID | Actor / Action | Expected result | Required evidence |
|---|---|---|---|
| E01 | U: open app; connect injected wallet; switch to Fuji | Displays correct account, chain 43113 and non-placeholder on-chain data | Browser screenshot + wallet address |
| E02 | Provider: transfer 10 test MockUSDC to U; U has test AVAX | U `balanceOf` updates; receipt successful | Token funding transaction hash |
| E03 | U: approve 5 MockUSDC | Allowance ≥ 5, approval receipt successful; Deposit enabled only after confirmation | Approve hash, allowance before/after |
| E04 | U: deposit 5 MockUSDC | `principalOf(U)` increases by 5, first effective streak is 1, token balance decreases by 5 | Deposit hash, epoch ID, principal and streak |
| E05 | P: approve and call `addMockYield` with 2 MockUSDC **while E04's epoch is still current** | `rewardPoolInEpoch(E)` increases by 2; provider-only call succeeds | Provider approval hash, yield hash, epoch ID |
| E06 | Allow epoch E to finalize; reload Rewards | `currentEpoch() > E`; `rewardInEpoch(U,E)` is claimable. `rewardOf(U)` covers E **only while E remains the latest finalized epoch** | Epoch + reward read, screenshot |
| E07 | U: `claimReward()` for latest finalized epoch E | Reward tokens transferred once; reward display refreshes; `principalOf(U)` unchanged | Claim hash, balance and principal before/after |
| E08 | U: withdraw 5 MockUSDC | U receives original 5 principal; `principalOf(U)=0`; active streak resets to 0 | Withdraw hash, principal before/after |
| E09 | Refresh and/or reload page | No fake balance; on-chain data remains consistent after page reload | Screenshot and read results |

**Timing pitfall:** `claimReward()` claims only `currentEpoch()-1`. If E is no longer the latest finalized epoch, use `claimRewardFor(E)` in an authorized contract interface/`cast`; record this distinction and do not claim that the UI supports historical epoch claims. For the 2–3 minute demo, coordinate yield funding and claiming within the intended epoch windows.

## Required negative and boundary tests

Perform with another fresh user or after re-funding; do **not** assume a rejected wallet prompt created a transaction.

| ID | Scenario | Expected | Evidence |
|---|---|---|---|
| N01 | U with balance < amount attempts Approve/Deposit | UI blocks invalid deposit or contract reverts without principal change | UI error screenshot, before/after state |
| N02 | U rejects an Approve or Deposit wallet prompt | UI returns to actionable state, no false success, no new principal | Screenshot; absence of successful hash |
| N03 | Double-click action rapidly | At most one transaction is submitted by UI for the action | UI behavior, wallet prompt count, hashes |
| N04 | U changes wallet to wrong network | Approve/Deposit/Claim/Withdraw blocked or prompt switch to Fuji | Screenshot, chain ID |
| N05 | U enters 0, malformed amount, 7+ decimals, > balance/available principal | Action disabled or explicit error; no transaction | Screenshots, no state change |
| N06 | U deposits again within same epoch | Principal increases but streak does not increment twice | Two deposit hashes, same epoch, streak |
| N07 | U deposits in the **next consecutive** epoch | Streak increases by exactly 1 | Epoch IDs, streak before/after |
| N08 | U misses at least one complete epoch | `effectiveStreakOf(U)==0` until next deposit; new check-in resets stored streak to 1 | Epochs and contract reads |
| N09 | Partial withdrawal while principal remains >0 | Principal decreases; streak preserved | Withdraw hash and state reads |
| N10 | Full withdrawal | Principal reaches 0; effective streak and weight reset | Withdraw hash and state reads |
| N11 | Unauthorized wallet V calls `addMockYield` | Reverts with `UnauthorizedYieldProvider`; reward pool unchanged | Simulation/revert result, before/after reads |
| N12 | Try same finalized epoch claim a second time | Reverts/disabled; no second token transfer | Attempt evidence, balance before/after |
| N13 | Claim before finalization | Claim unavailable or reverts, principal unchanged | Epoch read and attempt |
| N14 | Refresh page, disconnect/reconnect, switch between U/V | Balances/streak/reward belong to selected account; no stale mock values | Screenshots |
| N15 | Mobile widths 390px and 320px | Primary actions visible and usable; no horizontal clipping of critical UI | Screenshots |

## Financial/contract invariants to check

- For every successful deposit/withdraw, `principalOf(U)` moves by the exact input raw USDC amount (6 decimals). An Approve alone cannot increase principal.
- Reward claims must not reduce `principalOf(U)` or any other user's principal; `totalPrincipal` must track deposits minus withdrawals.
- `MockUSDC.balanceOf(StreakSavings) >= totalPrincipal + totalRewardPool` after each successful financial action.
- A later full withdrawal cannot retroactively change a **finalized** epoch snapshot.
- `rewardOf` is **latest-finalized-epoch only**; do not equate it to lifetime rewards.
- Epoch-weight calculations are end-of-epoch snapshots. In a two-user test, read `weightInEpoch` and `totalWeightInEpoch` for the tested epoch and verify pro-rata share with integer rounding.

## Evidence collection and completion gate

Use [TS-19-EVIDENCE.md](TS-19-EVIDENCE.md). For each row record PASS / FAIL / BLOCKED, a timestamp, actual observed result, relevant hash/screenshot, and reviewer. Never mark PASS based only on an existing feature's implementation or a successful build.

TS-19 can be marked **DONE** only when:

- A fresh U finishes the **actual Fuji** flow E01–E09, with provider operation from P, and explorer transaction evidence.
- Required N01–N15 tests have outcomes recorded, with failures fixed/re-tested or documented as blockers.
- Chain ID, contract bytecode and addresses confirmed; account balance/principal/reward invariants hold.
- The mobile UI and reconnect checks pass; a second team member reviews the evidence.
- Vercel URL (if published) is tested in incognito; any open issues preventing the demo are resolved.

If deployment is pending, leave TS-19 **BLOCKED — awaiting addresses and operator funding**. Local ABI/build gates are supporting checks, not acceptance of TS-19.
