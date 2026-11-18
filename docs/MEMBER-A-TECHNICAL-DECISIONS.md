# Member A — Technical & Business Logic Decision Register

**Contract Scope:** `MockUSDC.sol`, `StreakSavings.sol`, `StreakAccountingMath.sol`, `Deploy.s.sol`  
**Author:** Member A (Smart Contract & Avalanche Engineer)  
**Final implementation:** 18/11/2026  
**Repository Branch:** `feature/principal-accounting`  
**Authoritative Inputs:** Team-confirmed BR-01..BR-06 (18/11/2026), MVP Execution Plan v3, `docs/TS-02-StreakSavings-Design.md`, `docs/BL-DECISIONS-PROPOSAL.md`.

> **History note:** The 16/11 BL proposal and 17/11 decision register listed BL-01, BL-02, BL-03, BL-10, BL-11, and BL-13 as blocked. On 18/11/2026 the team confirmed BR-01..BR-06. This register records the approved rules and the final implementation; the earlier documents remain as design history.

---

## 1. Confirmed Business Rules (Implemented)

| ID | Rule | Implementation |
|---|---|---|
| **BR-01** | At most one streak check-in per epoch. First deposit ever → 1; consecutive epoch → +1; same epoch → no change; missed epoch → 1. | `deposit()` classifies the epoch relation and updates `streak`; repeated same-epoch deposits only add principal. |
| **BR-02** | Full withdrawal resets the active streak. Partial withdrawal does not. A later deposit starts at 1. | `withdraw()` resets `streak`, `lastDepositEpoch`, and active weight when remaining principal is zero. |
| **BR-03** | `weight = streak` if principal > 0; `weight = 0` if principal == 0. Global weight uses `-old + new`. | `UserInfo.weight`, `totalWeight`, and `StreakAccountingMath.applyWeightDelta`. |
| **BR-04** | Epoch-scoped reward pool using the weight snapshot at the END of each epoch; closed epochs are immutable; no user loop. | Per-epoch `weightInEpoch` and `totalWeightInEpoch`, written only while that epoch is current; claims require `epoch < currentEpoch()`. |
| **BR-05** | Unclaimed rewards never expire. | No expiry logic; per-epoch `claimedInEpoch`; `claimRewardFor(epoch)` remains available forever. |
| **BR-06** | Preserve `claimReward()` and add `claimRewardFor(uint64 epoch)`. Prevent double claims and claims before finalization. | Implemented both; `claimedInEpoch` and `EpochNotFinalized`. |

The existing `MockUSDC` specification also remains confirmed: name `Mock USDC`, symbol `USDC`, 6 decimals, zero initial supply, immutable deployer-only minter, zero-address rejection, test-only value.

---

## 2. Technical Decisions

| ID | Decision | Rationale |
|---|---|---|
| **TD-01** | Global epoch anchor `startTime = block.timestamp` in the constructor. | All users share one clock; no per-user drift. |
| **TD-02** | Reject zero-address and code-less token addresses in the constructor. | Fails fast on misconfiguration without an admin setter. |
| **TD-03** | Verify the exact token balance delta after every `safeTransferFrom` (deposit and mock yield). | Rejects fee-on-transfer/under-delivering tokens. |
| **TD-04** | Use `SafeCast.toUint64` for timestamps/epochs and expose `TimestampBeforeStart`. | Prevents silent truncation. |
| **TD-05** | Keep all epoch boundary/countdown helpers as views. | Frontend countdown and deterministic boundaries, zero storage writes. |
| **TD-06** | Use Model A (epoch-scoped pot), not a continuous accumulator. | Matches BR-04's end-of-epoch snapshot and eliminates the stale-weight problem for rewards. |
| **TD-07** | Snapshot mechanism = per-epoch mappings written only during the current epoch + time-gated claims. | O(1) per user action; no epoch-finalization transaction; no user iteration. Closed epochs are unreachable for writes. |
| **TD-08** | `addMockYield` is restricted to an immutable `yieldProvider` set to the deployer. | Prevents arbitrary users from choosing which epoch receives mock yield; matches the demo-account funding flow. |
| **TD-09** | `rewardOf(user)` reports the latest finalized epoch only; `rewardInEpoch(user, epoch)` exposes history; `claimReward()` claims the latest finalized epoch; `claimRewardFor(epoch)` claims older epochs. | Preserves the frontend zero-argument ABI and avoids an unbounded historical scan. Older rewards never expire. |
| **TD-10** | `streakOf` returns the stored streak; `effectiveStreakOf` returns 0 after a missed epoch. | Keeps historical/accounting state explicit while giving the UI a correct active-streak view. |
| **TD-11** | Use `Math.mulDiv` for reward shares and accumulator math. | Prevents multiplication overflow and preserves floor behavior. |
| **TD-12** | Rounding dust remains in `totalRewardPool` and the contract balance; it is never redistributed or confiscated. | Conservative solvency accounting; no admin rescue. |
| **TD-13** | No owner/pause/upgrade/rescue surface. | Minimizes privilege; testnet MVP. |
| **TD-14** | Keep `Deposit` and `Withdraw` signatures unchanged; add `StreakUpdated`, `StreakReset`, `MockYieldAdded`, `RewardClaimed`. | Avoids breaking the current frontend integration. |

---

## 3. Epoch Snapshot Design

### State
- `weightInEpoch[user][E]` — the user's weight for epoch `E`.
- `totalWeightInEpoch[E]` — sum of weights of users who checked in during `E`.
- `rewardPoolInEpoch[E]` — mock yield assigned to `E`.

### Write discipline
- `deposit()` writes only `weightInEpoch[user][currentEpoch()]`.
- `withdraw()` writes only the current epoch's weight when principal becomes zero.
- No function accepts an arbitrary epoch for writes.
- When `currentEpoch()` advances, the previous epoch's mappings are unreachable for mutation.

### Finalization
`isEpochFinalized(E)` is `E < currentEpoch()`. Claims require finalization. No separate finalization transaction exists; time itself closes the epoch. This is the explicit lazy-finalization mechanism.

### End-of-epoch correctness
- A user who checked in during `E` has their last weight of `E` stored.
- A user who did not check in during `E` has zero weight for `E`.
- A full withdrawal during `E` zeroes the current epoch's weight.
- A full withdrawal after `E` closes cannot touch `E`'s stored values.
- Repeated deposits in `E` do not change the streak, so they cannot change the snapshot.

---

## 4. Reward Math and Solvency

```text
share(E) = floor(rewardPoolInEpoch[E] * weightInEpoch[user][E] / totalWeightInEpoch[E])
```

- `Math.mulDiv` is used to avoid intermediate overflow.
- `sum(shares) <= rewardPoolInEpoch[E]`; the difference is dust.
- `totalRewardPool` = yield funded minus reward amounts already claimed. It includes dust and any pool that became unallocatable.
- Invariants:
  - `totalPrincipal == Σ principalOf(user)`
  - `usdc.balanceOf(this) >= totalPrincipal + totalRewardPool`
  - `totalWeight == Σ weightOf(user)` for all users in the test fixture
  - no claim changes `totalPrincipal` or any principal
- A zero-weight epoch is never funded (`addMockYield` reverts) and a zero-weight snapshot always yields zero.

### Known edge
If yield is funded in an epoch and every participant fully withdraws before the epoch closes, the pool has no beneficiaries. The funds remain in `totalRewardPool` and are backed by the contract balance, but are not redistributed. This is documented rather than hidden behind an admin rescue.

---

## 5. Claim Behavior and Frontend Compatibility

| Function | Behavior |
|---|---|
| `claimReward()` | Claims the latest finalized epoch (`currentEpoch() - 1`). Reverts if no epoch is finalized, no reward, or already claimed. |
| `claimRewardFor(uint64 epoch)` | Claims a specific finalized epoch. Older rewards remain claimable indefinitely. |
| `rewardOf(user)` | Reward for the latest finalized epoch only. |
| `rewardInEpoch(user, epoch)` | Reward for a specific finalized epoch. |
| `streakOf(user)` | Stored streak (0 after full withdrawal). |
| `effectiveStreakOf(user)` | 0 if principal is 0 or at least one full epoch has been missed; otherwise the stored streak. |
| `weightOf(user)` | Cached active weight. |
| `totalWeight` | Cached sum of user weights. Epoch snapshots are authoritative for rewards. |

`apps/web/lib/contracts.ts` expects `principalOf`, `streakOf`, `rewardOf`, `deposit`, `withdraw`, and `claimReward`. All signatures remain compatible. `claimRewardFor`, `addMockYield`, `rewardInEpoch`, `effectiveStreakOf`, and the epoch views are available for Member B to add when needed.

---

## 6. Access Control

- `deposit` / `withdraw`: any user for their own principal.
- `claimReward` / `claimRewardFor`: any user for their own reward.
- `addMockYield`: only `yieldProvider` (deployer/demo account).
- `MockUSDC.mint`: only the immutable deployer minter.
- No owner, pause, upgrade, rescue, blacklist, or fee switch.

---

## 7. Deferred / Out of MVP Scope

- NFT badges, Privy, Aave/Benqi, ERC-4626, agent wallets, shared streaks, custom L1.
- Production-grade principal-weighted or minimum-lock eligibility (the MVP remains `weight = streak`).
- A UI that paginates or aggregates historical epoch rewards beyond the latest finalized epoch.

---

## 8. Verification

- `forge fmt --check`: pass.
- `forge build --sizes`: pass.
- `forge test -vvv`: **103 tests passed, 0 failed, 0 skipped**.
- Two invariant suites: 128 runs each, 4,096 calls, 0 reverts.
- Fuji deployment: **not performed**; requires explicit authorization and a funded Dev Wallet.
