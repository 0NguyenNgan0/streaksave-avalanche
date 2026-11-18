# Business Logic Decisions — Proposal for Team Approval

**Contract:** `StreakSavings.sol`
**Author:** Member A (Smart Contract)
**Date:** 16/11/2026
**Status:** **SUPERSEDED on 18/11/2026.** The team confirmed BR-01..BR-06, including same-epoch no-increment, full-withdrawal reset, zero-principal zero-weight, epoch-scoped end-of-epoch snapshots, permanent unclaimed rewards, and the dual claim API. The final implementation is recorded in `docs/MEMBER-A-TECHNICAL-DECISIONS.md` and `docs/SMART-CONTRACT-ARCHITECTURE.md`. This document remains as the 16/11 proposal history.

| Label | Meaning |
|---|---|
| **CONFIRMED** | Stated in the MVP Execution Plan v3 or already implemented. |
| **PROPOSED** | Member A's recommendation. Not implemented until the team approves. |
| **REQUIRES APPROVAL** | A team decision is needed before the related code is written. |
| **BLOCKED** | No implementation until the decision is approved. |

This document does not override the plan. It narrows the 15 open rules from `docs/TS-02-StreakSavings-Design.md` into concrete options and recommendations. Nothing here is a team decision yet.

---

## 1. Confirmed baseline

These points are already fixed by the execution plan and are not reopened here:

1. **CONFIRMED:** `epochDuration` is a constructor parameter. Fuji demo example: 60 seconds; production concept: 7 days (plan §16.2).
2. **CONFIRMED:** there is no `advanceEpoch()` admin function (plan §16.2).
3. **CONFIRMED:** first deposit → `streak = 1`; deposit in the next epoch → `streak += 1`; missing at least one epoch → next deposit sets `streak = 1` (plan §4.3).
4. **CONFIRMED:** `weight = streak`; no `principal × multiplier` in the MVP (plan §4.4).
5. **CONFIRMED:** principal is never penalized; principal and reward pool are separate accounting domains (plan §3, §16.5).
6. **CONFIRMED:** no loop over all users in deposit, withdraw, add yield or claim (plan §16.1).
7. **CONFIRMED:** yield is mock yield, not real DeFi yield; no Aave/Benqi integration in the MVP (plan §2.3, §5).
8. **CONFIRMED frontend interface:** `deposit(uint256)`, `withdraw(uint256)`, `principalOf(address)`, `streakOf(address)`, `rewardOf(address)`, `claimReward()`, plus ERC-20 `approve`/`allowance` (`apps/web/lib/contracts.ts`).

Any change to the above needs an explicit team decision, not a silent implementation choice.

---

## 2. Blocking decisions

### BL-01 — Does a second deposit in the same epoch change the streak?

**Problem in plain terms.** The plan defines streak growth per *epoch*, but users can press Deposit more than once in the same epoch. If every deposit increments the streak, a user can reach an arbitrarily high streak in one epoch with many small deposits.

**Options**

| Option | Behavior | Accounting consequence | Risk |
|---|---|---|---|
| **A. No streak change (recommended)** | Principal increases; `lastDepositEpoch` stays; weight unchanged. | `totalPrincipal += amount`; `totalWeight` unchanged. | None identified; deposit stays a top-up. |
| B. Increment per deposit | Every deposit adds 1 to streak. | `totalWeight` grows per deposit; reward shares explode. | **Critical gaming vector.** 100 deposits → streak 100 in one epoch. |
| C. Reject second deposit | `revert` if `epoch == lastDepositEpoch`. | No state change. | Blocks legitimate top-ups; bad UX; forces users to wait. |

**Recommendation: A.** It matches the epoch-based rule in the plan and removes the obvious exploit.

**Storage/calculation impact:** requires `uint64 lastDepositEpoch` in `UserInfo`; branch `epoch == lastDepositEpoch` leaves `streak` and `weight` unchanged. No extra mapping. `Deposit` can still emit the amount.

**Status: REQUIRES APPROVAL — blocks streak implementation.**

---

### BL-02 — Does a full withdrawal reset the streak?

**Problem in plain terms.** A user can withdraw all principal and later come back. Does the old streak survive, or do they start over? The plan explicitly leaves this rule to the team (plan §4.3: "rule streak phải được team chốt").

**Options**

| Option | Behavior | Accounting consequence | Risk |
|---|---|---|---|
| **A. Keep streak, zero weight (recommended)** | Streak remains as history; while principal is 0, weight is 0. | On full withdrawal, `weight → 0`; `streak` unchanged. Re-deposit in the next epoch continues the streak. | User can keep a high streak with little capital at risk between epochs. Requires BL-03. |
| B. Reset streak to 0 on full withdrawal | Next deposit starts at 1. | `streak = 0`; weight 0. | Punishes users who need their money back, conflicting with the "no penalty" narrative. |
| C. Grace period (one epoch) | Streak survives one empty epoch. | Adds time-based state and rules. | More complexity for a small benefit; easy to mis-test. |

**Recommendation: A, paired with BL-03.** It preserves the no-penalty product story without allowing reward farming while principal is zero. If the team wants capital commitment, B is the stricter alternative.

**Storage/calculation impact:** no new field if weight is derived; if cached, update weight on full withdrawal. `withdraw` must checkpoint rewards before changing weight once rewards exist.

**Status: REQUIRES APPROVAL — blocks final withdrawal semantics and weight logic.**

---

### BL-03 — Must weight become zero when principal becomes zero?

**Problem in plain terms.** Weight drives reward share. If a user can withdraw all principal and keep weight, they earn yield with no money at risk.

**Options**

| Option | Behavior | Accounting consequence | Risk |
|---|---|---|---|
| **A. Weight = 0 when principal = 0 (recommended)** | No reward share without principal. | `totalWeight -= oldWeight`; `weight = 0`. | None; closes free-riding. |
| B. Weight = streak regardless of principal | Withdrawn users keep earning. | `totalWeight` unchanged. | **Critical economic exploit:** deposit once, withdraw, keep earning forever. |
| C. Weight proportional to principal | `weight = streak × principal` or similar. | Contradicts plan §4.4 (no principal multiplier). | Out of MVP scope; needs a new formula and tests. |

**Recommendation: A.** It is the minimum fix that keeps `weight = streak` for funded users.

**Storage/calculation impact:** weight is cached and updated on withdraw; `totalWeight` must use the `-old / +new` delta. No new field. Must be combined with BL-02.

**Status: REQUIRES APPROVAL — blocks reward eligibility and weight math.**

---

### BL-10 — Can rewards be claimed immediately, or only after the epoch closes?

**Problem in plain terms.** If rewards are split by epoch weight, the final weight total is unknown until the epoch ends. Allowing claims mid-epoch means the denominator can still change, so earlier claimants may take too much or too little.

**Options**

| Option | Model | Accounting consequence | Demo/UX consequence |
|---|---|---|---|
| **A. Claim after epoch close (recommended for MVP)** | Epoch-scoped pot. | Snapshot the epoch's total weight; `reward = epochPool × userWeight / epochTotalWeight`. No retroactive change. | User waits for the next epoch (60 s on Fuji demo). UI already needs an epoch countdown. |
| B. Immediate continuous accrual | MasterChef accumulator. | `accRewardPerWeight` + `rewardDebt` checkpoints; claims can happen anytime. | Instant claim, but more state and the stale-weight problem (below). |
| C. Hybrid | Accrue immediately, settle at close. | Two accounting layers. | Highest complexity; not justified for a 5-day MVP. |

**Stale-weight warning for B.** Weight only changes when a user acts. An inactive user keeps weight and keeps accruing forever unless the protocol iterates users (forbidden) or uses epoch participation. Model A avoids this by scoping eligibility to depositors of the epoch.

**Recommendation: A for the MVP**, as suggested by plan §16.1 ("one active reward epoch, claim theo epoch"). Revisit B only after T1–T8 pass and the team accepts the extra accounting.

**Storage/calculation impact:** Model A needs per-epoch mappings (`weightInEpoch`, `totalWeightInEpoch`, `rewardPoolInEpoch`). Model B needs `accRewardPerWeight`, `rewardCredit`, `rewardDebt`. These layouts are incompatible; this decision must be made before reward code.

**Status: REQUIRES APPROVAL — blocks all reward code.**

---

### BL-11 — Is claiming global, latest-epoch-only, or epoch-specific?

**Problem in plain terms.** With epoch rewards, a user may have unclaimed rewards from several epochs. One no-argument `claimReward()` cannot safely loop over an unbounded history, and the frontend already calls it without arguments.

**Options**

| Option | Behavior | Gas | Frontend impact |
|---|---|---|---|
| **A. `claimReward()` = latest matured epoch only (recommended)** | Claims the newest epoch with an unclaimed balance. Add `claimRewardFor(uint64 epoch)` for older epochs. | O(1) | Existing no-arg ABI keeps working. |
| B. `claimReward(uint64 epoch)` only | Caller must specify the epoch. | O(1) | Breaks the current frontend ABI; requires Member B change. |
| C. `claimReward()` loops all matured epochs | Claims everything at once. | Unbounded; can exceed block gas. | Convenient but unsafe. |
| D. Accumulator `claimReward()` | Claims the whole accrued balance. | O(1) | Compatible; depends on BL-10 option B. |

**Recommendation: A** if BL-10 = A. Keep the no-arg function that the frontend already expects, and add an explicit epoch function for completeness. If BL-10 = B, use D.

**Storage/calculation impact:** per-epoch claim tracking (`mapping(address => mapping(uint64 => bool)) claimed` or per-epoch credit). Must not allow double claims.

**Status: REQUIRES APPROVAL — blocks the claim interface and storage.**

---

## 3. Non-blocking reviews

These do not block today's principal implementation, but they must be settled before the related feature ships.

### BL-04 — Does a partial withdrawal preserve full streak weight?

- **Options:** (A) keep weight = streak; (B) scale weight by remaining principal; (C) require full withdrawal only.
- **Analysis:** The plan explicitly says `weight = streak`, so (A) is consistent. (B) introduces a principal multiplier that the plan defers beyond the MVP. (A) has a known weakness: a user can withdraw 99% and keep a high weight.
- **Recommendation:** (A) for MVP. Document the weakness. If the team considers it unacceptable, the correct fix is a principal/lock multiplier, which is a product change, not a contract detail.
- **Status: REQUIRES APPROVAL, non-blocking for principal.**

### BL-05 — Can a zero-principal user claim previously earned rewards?

- **Options:** (A) yes, pay accrued `rewardCredit`; (B) forfeit on full withdrawal.
- **Analysis:** Earned yield should not be confiscated; (B) creates an incentive to never withdraw. Weight can be zero without deleting earned rewards.
- **Recommendation:** (A). Keep `rewardCredit` separate from `weight`.
- **Status: PROPOSED, non-blocking.**

### BL-06 — What happens to `addMockYield` when no user has weight?

- **Options:** (A) revert `NoActiveWeight`; (B) keep unallocated and roll into the next distribution; (C) keep stranded forever.
- **Analysis:** (B) retroactively rewards future depositors with past yield. (C) silently locks funds. (A) is the clearest MVP behavior and avoids retroactivity.
- **Recommendation:** (A). The demo adds yield only after deposits exist.
- **Status: PROPOSED, non-blocking today.**

### BL-07 — Who can call `addMockYield`?

- **Options:** (A) anyone (donation); (B) deployer/demo account only.
- **Analysis:** (A) needs no admin role and cannot harm the pool; it only adds funds. (B) adds an owner surface that the plan does not require.
- **Recommendation:** (A), permissionless donation.
- **Status: PROPOSED, non-blocking today.**

### BL-08 — Is there a minimum deposit?

- **Options:** (A) no minimum, reject zero; (B) minimum 1 USDC; (C) minimum 5 USDC to match the UI.
- **Analysis:** A minimum is not specified in the plan and would invalidate the "save small" message. Dust deposits are cheap on Fuji and harmless. Rejecting zero prevents streak-free deposits.
- **Recommendation:** (A) for MVP; document that production may add a minimum.
- **Status: PROPOSED, non-blocking.**

### BL-09 — Should `streakOf()` show the stored or effective streak after missed epochs?

- **Options:** (A) stored streak (historical); (B) effective value (0 once an epoch is missed, until the next deposit); (C) stored streak plus a separate `effectiveWeightOf`.
- **Analysis:** Reward eligibility must not rely on a stale display value. Model A already scopes rewards by epoch deposits, so the UI can show "streak broken" separately. Returning 0 from `streakOf` would erase history and confuse the dashboard.
- **Recommendation:** (C): keep `streakOf` historical, expose weight/eligibility separately. Member B can render a countdown and a "broken" state.
- **Status: REQUIRES APPROVAL (UI semantics), non-blocking for principal.**

### BL-12 — Is `epochDuration` immutable?

- **Options:** (A) immutable constructor value; (B) owner can change it.
- **Analysis:** Changing epoch length mid-game changes streak fairness and can be used to manipulate reward epochs. (A) matches "no admin" and plan §16.2.
- **Recommendation:** (A).
- **Status: PROPOSED with strong security rationale; needs confirmation.**

### BL-13 — Are unclaimed epoch rewards rolled forward, forfeited, or claimable forever?

- **Options:** (A) claimable forever; (B) roll into the next epoch; (C) forfeit after N epochs.
- **Analysis:** (C) confiscates user property and needs an admin/expiry mechanism. (B) creates retroactive distribution to later participants. (A) is the safest accounting default, at the cost of permanent per-epoch storage.
- **Recommendation:** (A) for MVP.
- **Status: REQUIRES APPROVAL, non-blocking today.**

### BL-14 — Can a user deposit for another address?

- **Options:** (A) `msg.sender` only; (B) `depositFor(address, uint256)`.
- **Analysis:** (B) complicates allowance, beneficiary and streak ownership; no product requirement. (A) is simpler and safer.
- **Recommendation:** (A).
- **Status: PROPOSED, non-blocking.**

### BL-15 — Is there a TVL/deposit cap?

- **Options:** (A) no cap on Fuji testnet; (B) per-user cap; (C) global cap.
- **Analysis:** Caps are a production risk control, not a hackathon requirement. Mock USDC has no value. A cap adds state and admin rules.
- **Recommendation:** (A) for MVP; add caps before any real-value deployment.
- **Status: PROPOSED, non-blocking.**

---

## 4. Summary

| ID | Recommendation | Blocks today? | Status |
|---|---|---|---|
| BL-01 | Same-epoch deposit: no streak change | **Yes** | REQUIRES APPROVAL |
| BL-02 | Full withdrawal: keep streak, weight 0 | **Yes** | REQUIRES APPROVAL |
| BL-03 | Weight 0 when principal 0 | **Yes** | REQUIRES APPROVAL |
| BL-04 | Partial withdrawal keeps weight | No | REQUIRES APPROVAL |
| BL-05 | Zero-principal user keeps earned rewards | No | PROPOSED |
| BL-06 | Revert `addMockYield` with no weight | No | PROPOSED |
| BL-07 | Permissionless `addMockYield` | No | PROPOSED |
| BL-08 | No minimum deposit; reject zero | No | PROPOSED |
| BL-09 | Historical `streakOf` + separate eligibility view | No | REQUIRES APPROVAL (UI) |
| BL-10 | Claim after epoch close (epoch pot) | **Yes** | REQUIRES APPROVAL |
| BL-11 | `claimReward()` latest epoch + `claimRewardFor(epoch)` | **Yes** | REQUIRES APPROVAL |
| BL-12 | Immutable epoch duration | No | PROPOSED |
| BL-13 | Unclaimed rewards claimable forever | No | REQUIRES APPROVAL |
| BL-14 | No deposit for another address | No | PROPOSED |
| BL-15 | No TVL cap on Fuji | No | PROPOSED |

---

## 5. Implementation boundary as of 16/11/2026

**Unblocked and implemented today:** principal accounting, `deposit`, `withdraw`, `principalOf`, `totalPrincipal`, token-delta verification, reentrancy guard, principal invariants. These do not depend on BL-01, BL-02, BL-03, BL-10 or BL-11 because no streak, weight or reward state exists yet.

**Blocked until approval:**

- streak storage and updates (BL-01, BL-02);
- weight and reward eligibility (BL-03, BL-04);
- `addMockYield`, `rewardOf`, `claimReward` (BL-06, BL-10, BL-11, BL-13);
- final `streakOf`/UI semantics (BL-09).

**Frontend note:** `apps/web/lib/contracts.ts` already expects `streakOf` and `rewardOf`. The principal-only contract does not expose them yet, so the frontend must stay in preview mode / must not be pointed at a principal-only deployment. This is a deliberate scope boundary, not an oversight.

---

## 6. Approval request

Team, please confirm or change **BL-01, BL-02, BL-03, BL-10, BL-11** first. They determine storage layout and cannot be changed cheaply after rewards are deployed. The remaining items can be confirmed in the same review or deferred.

Once approved, Member A will update this document with the decision and implement the next layer in the order defined by plan §16.7.
