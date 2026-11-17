# Member A — Technical & Business Logic Decision Register

**Contract Scope:** `MockUSDC.sol`, `StreakSavings.sol`, `StreakAccountingMath.sol`, `Deploy.s.sol`  
**Author:** Member A (Smart Contract & Avalanche Engineer)  
**Date:** 17/11/2026  
**Repository Branch:** `feature/principal-accounting`  
**Authoritative Inputs:**
- `Team_Dimple_UniHack_2026_MVP_Execution_Plan_v3_Technical_Safeguards.docx` (`extracted_plan.txt`)
- `docs/TS-02-StreakSavings-Design.md`
- `docs/BL-DECISIONS-PROPOSAL.md`

---

## 1. Classification Legend

| Status | Meaning | Implementation Rule |
|---|---|---|
| **APPROVED** | Explicitly confirmed in Team Dimple's MVP Execution Plan v3 or baseline specifications. | Implemented in production contract code and verified by tests. |
| **TECHNICAL DECISION** | Engineering detail that does not alter unapproved user-facing business rules. | Independently decided and implemented by Member A. |
| **PROPOSED** | Recommendation by Member A in `docs/BL-DECISIONS-PROPOSAL.md`; not yet team-confirmed. | Documented only; **not** hard-coded into `StreakSavings.sol` state transitions. |
| **BLOCKED** | Unresolved business rule whose choice changes contract storage layout, external API, or user funds/rewards. | Cannot be implemented in `StreakSavings.sol` until team approval is recorded. |
| **DEFERRED** | Explicitly outside MVP scope per Plan v3 §0 and §5. | Excluded from MVP contracts. |

---

## 2. APPROVED Items (Implemented Baseline)

1. **`MockUSDC` Token Specification** (Plan v3 §4.1, §7)
   - ERC-20 with `name = "Mock USDC"`, `symbol = "USDC"`, `decimals() = 6`.
   - Zero initial supply at deployment; immutable `minter = msg.sender`; zero-address mint rejection.
   - Test-only faucet token with no monetary value.
2. **Principal Accounting & No-Loss Isolation** (Plan v3 §3, §4.2, §4.3, §16.5, §16.6)
   - `deposit(uint256)`, `withdraw(uint256)`, `principalOf(address)`, `totalPrincipal`.
   - Contract token balance is never treated as `totalPrincipal` or `rewardPool`.
   - Breaking or losing a streak never confiscates or penalizes user principal.
3. **Configurable Global Epoch Clock without Admin Override** (Plan v3 §4.3, §16.2; `BL-DECISIONS-PROPOSAL.md` §1)
   - `epochDuration` is a constructor parameter (`uint64`, e.g., `60` seconds for Fuji demo, `7 days` for production concept) and cannot be zero.
   - No `advanceEpoch()` admin backdoor; epochs derive deterministically from `block.timestamp`.
4. **Core Confirmed Streak & Weight Formulas** (Plan v3 §4.3, §4.4, §16.4)
   - First deposit ever sets `streak = 1`.
   - Deposit in consecutive epoch (`lastDepositEpoch + 1`) sets `streak = currentStreak + 1`.
   - Deposit after missing at least one epoch (`> lastDepositEpoch + 1`) sets `streak = 1`.
   - `weight = streak` (no `principal * multiplier` in MVP).
   - Global weight update must subtract old weight before adding new weight: `totalWeight = totalWeight - oldWeight + newWeight`.
5. **No Unbounded User Iteration & Mock Yield Only** (Plan v3 §2.3, §5, §16.1)
   - Zero loops over all depositors in `deposit`, `withdraw`, `addMockYield`, or `claimReward`.
   - Yield is simulated mock yield (`addMockYield`), never represented as real DeFi yield.

---

## 3. TECHNICAL DECISIONS (Independently Decided by Member A)

| ID | Decision | Rationale | Location |
|---|---|---|---|
| **TD-01** | Anchor epoch 0 globally at `startTime = SafeCast.toUint64(block.timestamp)` in `StreakSavings` constructor. | Aligns all users on one shared epoch countdown (needed for Plan §16.2 UI countdown and Model A shared epoch pots) and removes per-user clock drift. | `StreakSavings.sol` |
| **TD-02** | Reject `address(0)` AND addresses with `code.length == 0` for `usdc_` in `StreakSavings` constructor. | Fails fast on misconfigured deployments (e.g., EOA passed instead of `MockUSDC`) without requiring admin setter functions. | `StreakSavings.sol` |
| **TD-03** | Verify actual received token delta (`balanceAfter - balanceBefore == amount`) in `deposit`. | Protects principal solvency invariants if a non-standard/fee-on-transfer token is ever paired in tests. | `StreakSavings.sol` |
| **TD-04** | Use OpenZeppelin `SafeCast.toUint64` for `startTime`, `currentEpoch()`, and `epochAt(uint256)` plus `TimestampBeforeStart` custom error. | Prevents silent truncation on arbitrary `uint256` inputs to `epochAt` while keeping normal runtime timestamps safe (`uint64` covers >584 billion years at 1s epochs). | `StreakSavings.sol`, `StreakAccountingMath.sol` |
| **TD-05** | Expose countdown/boundary helpers (`epochAt`, `epochStart`, `epochEnd`, `nextEpochTimestamp`, `timeUntilNextEpoch`). | Supports frontend epoch countdown (Plan §16.2) as pure/view calculations with zero extra storage writes. | `StreakSavings.sol` |
| **TD-06** | Isolate confirmed pure math (epoch transitions, `applyWeightDelta`, Model A/B reward math) in `StreakAccountingMath.sol` while gating `SameEpoch` with `UnapprovedSameEpochRule()`. | Allows unit/fuzz validation of T1–T8 math and Plan §16.4 invariants without exposing unfinished public reward/streak state on `StreakSavings.sol` before BL approval. | `StreakAccountingMath.sol` |
| **TD-07** | Do **not** expose stub `streakOf`, `rewardOf`, `claimReward`, or `addMockYield` on `StreakSavings.sol` yet. | Prevents frontend/QA from confusing a stubbed zero-returning endpoint with finished streak/reward behavior. | `StreakSavings.sol` |
| **TD-08** | Enforce explicit `DEPLOYER_PRIVATE_KEY`, chain ID (`43113` Fuji or opt-in `31337` Anvil), non-zero `epochDuration`, and on-chain post-deploy verification in `Deploy.s.sol`. | Eliminates accidental mainnet broadcasts, zero-duration deployments, or unverified token wiring. | `Deploy.s.sol` |

---

## 4. BLOCKED & PROPOSED Business Logic Decisions

> **Audit Check (17/11/2026):** No newer team approval record exists in the repository beyond `docs/BL-DECISIONS-PROPOSAL.md` (`16/11/2026`). Therefore, all blocking decisions remain unresolved and are **not** encoded into `StreakSavings.sol` state transitions.

### 4.1 Critical Blocking Decisions (Storage Layout, State Transitions, Public API)

#### BL-01 — Multiple deposits in the same epoch
- **Current Status:** `BLOCKED` (`REQUIRES APPROVAL`).
- **Evidence:** `docs/BL-DECISIONS-PROPOSAL.md` §2; `docs/TS-02-StreakSavings-Design.md` §6, §15. Plan v3 §4.3 specifies first deposit, next epoch, and missed epoch, but omits same-epoch repeat deposits.
- **Is it genuinely unresolved?** Yes.
- **Technical Consequences:**
  - Option A (Recommended): keep streak unchanged (`epoch == lastDepositEpoch` acts as a principal top-up only). Prevents infinite streak farming in one epoch.
  - Option B: increment per deposit (critical exploit: N small deposits in 60 seconds yield streak N).
  - Option C: revert on second deposit in same epoch (hurts UX if user wants to top up savings).
- **Storage Layout Implications:** Requires `uint64 lastDepositEpoch` (plus an initialization flag or `lastDepositEpoch + 1` sentinel / `streak > 0` check) in `UserInfo`. Option A/B/C share the field, but Model A's `weightInEpoch[user][epoch]` updates differ if Option A vs B is chosen.
- **Function/API Implications:** Affects `deposit(uint256)` streak update branch and whether `StreakUpdated` emits on repeat same-epoch deposits.
- **Test Cases Affected:** `P3` (repeated deposit in same epoch), `StreakAccountingMathTest.test_Streak_PendingBL01_SameEpochTransitionIsClassifiedAndGated`.
- **What It Blocks:** Implementing `streak` state updates inside `StreakSavings.deposit()`.

#### BL-02 — Full withdrawal and streak behavior
- **Current Status:** `BLOCKED` (`REQUIRES APPROVAL`).
- **Evidence:** Plan v3 §4.3 explicitly defers this to the team ("Withdraw: Không làm mất principal; rule streak phải được team chốt và test rõ ràng"). `docs/BL-DECISIONS-PROPOSAL.md` §2.
- **Is it genuinely unresolved?** Yes.
- **Technical Consequences:**
  - Option A (Recommended, paired with BL-03 Option A): keep historical `streak`, set active `weight = 0` while `principal == 0`. Preserves "no penalty" narrative while preventing zero-capital farming.
  - Option B: reset `streak = 0` and `lastDepositEpoch = 0` on full withdrawal. Forces capital lock-in across epochs to retain streak.
  - Option C: 1-epoch grace period (adds complexity).
- **Storage Layout Implications:** Affects whether `withdraw()` mutates `UserInfo.streak` and `UserInfo.lastDepositEpoch`, and whether `UserInfo.weight` is stored separately from `UserInfo.streak` (required by Option A, redundant under Option B).
- **Function/API Implications:** `withdraw(uint256)` state transition, `streakOf(address)`, and `weightOf(address)` return values after full withdrawal.
- **Test Cases Affected:** `P5` (full withdrawal behavior), `T7` (withdraw then add yield).
- **What It Blocks:** Streak/weight mutation inside `StreakSavings.withdraw()` and `UserInfo` struct finalization.

#### BL-03 — Weight when principal is zero
- **Current Status:** `BLOCKED` (`REQUIRES APPROVAL`).
- **Evidence:** `docs/BL-DECISIONS-PROPOSAL.md` §2; Plan v3 §4.4 states `weight = streak` without specifying what happens when `principal == 0`.
- **Is it genuinely unresolved?** Yes.
- **Technical Consequences:**
  - Option A (Recommended): `weight = 0` whenever `principal == 0`, restoring `weight = streak` upon deposit. Closes the zero-principal free-rider exploit.
  - Option B: `weight = streak` even when `principal == 0` (severe economic flaw: deposit 1 wei, withdraw immediately, farm rewards forever).
  - Option C: `weight = streak * principal` (explicitly excluded from MVP by Plan v3 §4.4).
- **Storage Layout Implications:** Under BL-02 Option A + BL-03 Option A, `UserInfo` must distinguish `streak` from active `weight` (or derive `weight = principal > 0 ? streak : 0`). Also mandates updating `totalWeight` in `withdraw()` and `deposit()` whenever `principal` crosses between `0` and `> 0`.
- **Function/API Implications:** `deposit(uint256)`, `withdraw(uint256)`, `weightOf(address)`.
- **Test Cases Affected:** `P5`, `T6`, `T7`, zero-principal invariant checks.
- **What It Blocks:** All `weight` and `totalWeight` state transitions and reward eligibility math.

#### BL-10 — Reward distribution timing & accounting model
- **Current Status:** `BLOCKED` (`REQUIRES APPROVAL`).
- **Evidence:** Plan v3 §16.1 recommends starting with one clear epoch-scoped reward model ("MVP ưu tiên 1 reward epoch rõ ràng; chỉ nâng lên accumulator `accRewardPerWeight + rewardDebt` khi test đầy đủ"). `docs/TS-02-StreakSavings-Design.md` §9 and `docs/BL-DECISIONS-PROPOSAL.md` §2 lay out Model A vs Model B as an unresolved team decision.
- **Is it genuinely unresolved?** Yes.
- **Technical Consequences & Storage/API Implications:**
  - **Model A (Epoch-scoped pot — Recommended for MVP):** Requires `mapping(uint64 epoch => uint256) rewardPoolInEpoch`, `mapping(uint64 epoch => uint256) totalWeightInEpoch`, `mapping(address => mapping(uint64 => uint256)) weightInEpoch`, `mapping(address => mapping(uint64 => bool)) claimedInEpoch`, plus tracking active/claimable epochs. Claims occur only after epoch close (`epoch < currentEpoch()`).
  - **Model B (Continuous accumulator):** Requires `accRewardPerWeight`, `rewardPool`, `totalWeight`, `UserInfo.rewardCredit`, `UserInfo.rewardDebt`. Allows immediate intra-epoch claims (`T4`) but suffers from inactive stale weight unless combined with epoch participation pruning.
  - Because storage layouts and user wait UX (`60s` wait vs immediate claim) are mutually incompatible, Model A vs Model B must be chosen before writing reward storage.
- **Test Cases Affected:** Entire `T1`–`T8` suite and reward solvency invariants (`T4`/`T5` behavior differs across intra-epoch vs inter-epoch claims).
- **What It Blocks:** All reward storage, `addMockYield`, `rewardOf`, and `claimReward`.

#### BL-11 — Claim scope and API (`claimReward()`)
- **Current Status:** `BLOCKED` (`REQUIRES APPROVAL`).
- **Evidence:** `apps/web/lib/contracts.ts` defines `claimReward()` with zero arguments and `rewardOf(address)` returning `uint256`. Plan v3 §4.2 and §16.1 require no unbounded loops.
- **Is it genuinely unresolved?** Yes (directly coupled to BL-10).
- **Technical Consequences:**
  - Option A (Recommended if BL-10 = Model A): `claimReward()` claims the latest matured/eligible epoch in `O(1)` (or tracks a single user-claimable epoch pointer / latest deposited matured epoch), plus `claimRewardFor(uint64 epoch)` for explicit historical epochs. Preserves frontend ABI without unbounded loops.
  - Option B: `claimReward(uint64 epoch)` only (breaks current `apps/web/lib/contracts.ts` signature).
  - Option C: `claimReward()` loops over all past epochs (violates Plan §16.1 gas safeguard; unbounded DoS risk).
  - Option D (Required if BL-10 = Model B): `claimReward()` settles and transfers `rewardCredit` in `O(1)`.
- **Storage Layout Implications:** Under Model A Option A, must maintain an `O(1)` reference or per-user epoch cursor so `claimReward()` and `rewardOf(address)` do not scan unbounded epoch history (e.g., `lastParticipatedEpoch` or a capped/linked list). Under Option D, only `rewardCredit` + `rewardDebt` are needed.
- **Function/API Implications:** External signatures of `claimReward()`, `rewardOf(address)`, and optional `claimRewardFor(uint64)`.
- **Test Cases Affected:** `T4`, `T5`, `T8`, and frontend ABI compatibility.
- **What It Blocks:** `claimReward` and `rewardOf` implementation.

#### BL-13 — Lifecycle of unclaimed epoch rewards (Prerequisite for Reward Implementation)
- **Current Status:** `BLOCKED` (`REQUIRES APPROVAL`).
- **Evidence:** `docs/TS-02-StreakSavings-Design.md` §15; `docs/BL-DECISIONS-PROPOSAL.md` §3, §5 ("Blocked until approval: `addMockYield`, `rewardOf`, `claimReward` (BL-06, BL-10, BL-11, BL-13)").
- **Investigation of Day 2 Report Ambiguity:** `docs/BL-DECISIONS-PROPOSAL.md` §3 originally tagged BL-13 "non-blocking today" *specifically relative to Day 2 principal-only accounting*, while §5 correctly listed BL-13 as a blocker for `addMockYield`, `rewardOf`, and `claimReward`. Under Model A (epoch-scoped reward pools), BL-13 is a direct implementation prerequisite because the contract must define what happens when an epoch closes with unclaimed funds or zero claims:
  - Option A (Recommended): **Claimable forever** — `rewardPoolInEpoch[E]` remains reserved for epoch `E` participants via `claimRewardFor(E)` with no expiry. Safest no-confiscation rule and simplest accounting (`rewardPool >= sum of unclaimed epoch entitlements`).
  - Option B: **Roll forward into epoch `E + 1`** — requires an explicit expiry threshold + sweep mechanism, retroactively redistributes unclaimed rewards to future depositors, and introduces edge cases when `claimReward` races with rollover.
  - Option C: **Forfeit after N epochs** — requires admin/treasury destination and conflicts with StreakSave's user-protection positioning.
- **Storage & Accounting Implications:** Determines whether `rewardPool` can decrement only on actual user claims (Option A) or requires epoch rollover accounting/state cleanup (Options B/C). Also governs whether `rewardOf(user)` under Option A must query historical unclaimed epochs vs just `lastDepositedEpoch`.
- **What It Blocks:** Final Model A reward pool accounting, `claimReward` / `claimRewardFor`, and reward pool conservation invariants.

### 4.2 Non-Blocking Pending Decisions (`PROPOSED` / `REQUIRES APPROVAL` for Next Layers)

| ID | Question | Recommendation | Status | Blocks |
|---|---|---|---|---|
| **BL-04** | Partial withdrawal preserves full streak weight? | Keep `weight = streak` (Plan §4.4); document 99%-withdraw trade-off. | `REQUIRES APPROVAL` | Weight update in `withdraw()`. |
| **BL-05** | Zero-principal user keeps earned rewards? | Yes — pay previously accrued `rewardCredit`. | `PROPOSED` | `withdraw()` / `claimReward()` interaction. |
| **BL-06** | `addMockYield` when `totalWeight == 0`? | Revert with `StreakSavings__NoActiveWeight()`. | `PROPOSED` | `addMockYield()` validation. |
| **BL-07** | Who can call `addMockYield`? | Permissionless donation (no admin role needed). | `PROPOSED` | `addMockYield()` access control. |
| **BL-08** | Minimum deposit amount? | No minimum; reject zero (`amount == 0`). | `PROPOSED` | `deposit()` input validation. |
| **BL-09** | `streakOf(address)` stored vs effective after missed epoch? | Keep `streakOf` stored/historical + add `effectiveStreakOf` / `weightOf` for UI. | `REQUIRES APPROVAL` (UI semantics) | `streakOf()` semantics & UI display. |
| **BL-12** | Is `epochDuration` immutable? | Yes (`immutable` constructor param — already implemented). | `PROPOSED` (implemented as immutable per Plan §16.2) | Would require governance/admin if mutable. |
| **BL-14** | Deposit for another address (`depositFor`)? | No (`msg.sender` only). | `PROPOSED` | Not part of MVP interface. |
| **BL-15** | TVL / deposit cap on Fuji? | No cap for testnet MVP. | `PROPOSED` | Production risk control later. |

---

## 5. Architectural Evaluation: Model A vs. Model B Reward Accounting

This comparison evaluates the two candidate reward accounting models referenced in MVP Execution Plan v3 §16.1 and `docs/TS-02-StreakSavings-Design.md` §9 across all 10 engineering criteria.

| Criterion | Model A — Epoch-Scoped Accounting | Model B — Continuous Accumulator (`accRewardPerWeight` + `rewardDebt`) |
|---|---|---|
| **1. Storage Complexity** | Moderate-High per epoch: `rewardPoolInEpoch[E]`, `totalWeightInEpoch[E]`, `weightInEpoch[user][E]`, `claimedInEpoch[user][E]`, plus a non-looping pointer (`lastParticipatedEpoch[user]` or active-epoch queue) for `claimReward()`. | Compact: global `accRewardPerWeight`, `rewardPool`, `totalWeight`; per-user `weight`, `rewardCredit`, `rewardDebt` inside `UserInfo`. |
| **2. Gas Cost** | `O(1)` per `deposit`, `addMockYield`, and `claimRewardFor(epoch)`. Slightly higher SSTORE count during `deposit` to write epoch-scoped weight maps; `claimReward()` needs an `O(1)` epoch pointer to avoid scanning history. | `O(1)` across all operations (`deposit`, `withdraw`, `addMockYield`, `claimReward`). Single checkpoint helper `_settle(user)` touches only user struct + 2 globals. |
| **3. Historical Reward Preservation** | Naturally isolated by epoch: once epoch `E` closes, `totalWeightInEpoch[E]` and `weightInEpoch[user][E]` never change retroactively. | Preserved via `_settle(user)` checkpoint into `user.rewardCredit` **before** any weight or debt update. |
| **4. Weight Changes** | Simple within epoch `E`: `applyWeightDelta(totalWeightInEpoch[E], prevEpochWeight, newEpochWeight)`. Does not mutate past closed epochs. | Must settle `user` first, update `totalWeight` via `-old + new`, update `user.weight`, then reset `rewardDebt = user.weight * acc / PRECISION`. |
| **5. Multiple Yield Additions** | Multiple `addMockYield` calls in epoch `E` simply increment `rewardPoolInEpoch[E]`. No double counting. | Multiple `addMockYield` calls increment `accRewardPerWeight += amount * PRECISION / totalWeight`. No double counting. |
| **6. Claims Between Yield Additions (T4/T5)** | **Cannot happen within the same epoch**: users must wait until epoch `E` closes before claiming from `E`. Works cleanly *across* epochs (`add in E` -> close `E` -> `claim E` -> `add in E+1`). | **Works immediately within the same epoch**: `rewardDebt` advances on claim so subsequent yield additions only accrue the delta `accNew - accOld`. |
| **7. Unclaimed Rewards (BL-13)** | Unclaimed rewards stay per-epoch (`rewardPoolInEpoch[E]`). If a user skips claiming epoch `E` and deposits in `E+1`, a single `lastDepositedEpoch` pointer risks stranding `E` unless `claimRewardFor(E)` or a linked list/bitmap is exposed. | Automatically unified in `rewardCredit + pending`. Never stranded across epochs—one zero-arg `claimReward()` collects 100% of past unclaimed yield in `O(1)`. |
| **8. Rounding Behavior** | Floor division `(epochPool * weightInEpoch) / totalWeightInEpoch` at claim time. Rounding dust (`<= 1` wei per user per epoch) remains safely in contract balance (`sum <= epochPool`). | Floor division both when computing `accRewardPerWeight` delta (`yield * 1e18 / totalWeight`) and when settling `user.weight * acc / 1e18`. With `1e18` precision, dust per operation is negligible (`<= 1` base unit per user); `rewardPool` always covers `sum(claims)`. |
| **9. Frontend API Complexity** | Needs epoch awareness in UI (`claimableEpoch` / `claimRewardFor(epoch)` or explanation why current-epoch rewards cannot be claimed until countdown hits 0). | Matches `apps/web/lib/contracts.ts` (`rewardOf(address)` + `claimReward()`) out of the box with zero extra arguments or epoch pagination. |
| **10. Testability** | Clean per-epoch invariants, but requires testing multi-epoch boundary transitions and skipped-epoch claim UX (`claimReward()` vs `claimRewardFor(E)`). | Direct fit for T1–T8 tests without artificial epoch waits, but requires strict property/invariant tests verifying the **stale-weight** caveat (inactive users who never withdraw/deposit keep `weight` unless deactivated on epoch participation). |

### Recommendation for MVP

- **Primary Recommendation (MVP Alignment):** **Model A (Epoch-Scoped Accounting)** combined with **BL-11 Option A** (`claimReward()` + `claimRewardFor(uint64 epoch)`) and **BL-13 Option A** (claimable forever), **if and only if** the team accepts waiting 1 epoch (`60s` on Fuji demo) before claiming that epoch's yield. It completely eliminates the **stale-weight** problem (an inactive depositor from Epoch 0 cannot passively dilute active savers in Epoch 50 without depositing in Epoch 50) and directly implements Plan v3 §16.1 ("MVP ưu tiên 1 reward epoch rõ ràng").
- **Alternative if Immediate Intra-Epoch Demo Claim is Required:** **Model B (Continuous Accumulator)** should only be chosen if the 3-minute hackathon demo cannot wait `60s` between `addMockYield` and `claimReward` AND the team explicitly accepts the documented stale-weight behavior (no automatic decay of inactive users without user action).

---

## 6. DEFERRED Items (Out of MVP Scope)

Per Team Dimple MVP Execution Plan v3 §0, §5, and §16.7:
- `NFTBadge.sol` (streak milestone NFTs — bonus #1 only after Deposit -> Streak -> Reward -> Claim -> Withdraw E2E passes on Fuji).
- Privy Embedded Wallet integration (optional UI enhancement).
- Real DeFi yield adapters (Aave / Benqi).
- Agent Wallet / automated recurring deposits.
- Shared Streak / social pools.
- ERC-4626 tokenized vault standard.
- Custom Avalanche L1.
