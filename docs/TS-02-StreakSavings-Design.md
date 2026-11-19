# TS-02 — `StreakSavings.sol` Technical Design (Draft)

**Status:** Design only — no `StreakSavings.sol` reward or streak code is implemented on 15/11/2026.
**Author:** Member A (Smart Contract / Blockchain)
**Date:** 15/11/2026
**Sources:** Team Dimple MVP Execution Plan v3, §3, §4, §16; TS-02 task brief.

**Update 16/11/2026:** principal accounting is implemented in `contracts/src/StreakSavings.sol`. Streak and reward layers remain blocked on the decisions in `docs/BL-DECISIONS-PROPOSAL.md`.

**Update 18/11/2026:** BR-01..BR-06 were confirmed. The final implementation uses Model A (epoch-scoped pot), per-epoch weight snapshots, and the claim semantics documented in `docs/SMART-CONTRACT-ARCHITECTURE.md`. This document remains as design history; the architecture and technical-decision documents are authoritative for the shipped code.

Labels used below:

- **CONFIRMED** — stated in the execution plan.
- **PROPOSED** — engineering proposal; requires team confirmation before implementation.
- **OPEN** — business rule not defined anywhere; must be decided before coding.

---

## 1. Scope

One non-upgradeable business contract, `StreakSavings.sol`, that:

1. Accepts `MockUSDC` deposits and records principal per user.
2. Tracks a global epoch clock and a per-user saving streak.
3. Holds a mock community yield pool, separate from principal.
4. Distributes yield proportionally to streak weight.
5. Lets users claim rewards and withdraw principal without penalty.

Out of scope today: NFT badges, Aave/Benqi, ERC-4626, upgradeability, admin dashboard, Fuji deployment, frontend.

`MockUSDC` is already implemented and tested (TS-01). It is a test token with no monetary value.

---

## 2. Proposed external interface

| Function | Kind | Notes |
|---|---|---|
| `constructor(IERC20 usdc, uint64 epochDuration)` | constructor | `usdc` must be non-zero; `epochDuration > 0`. |
| `deposit(uint256 amount)` | external | Pulls `amount` from `msg.sender`. |
| `withdraw(uint256 amount)` | external | Pays principal only. |
| `claimReward()` | external | Pays accrued mock yield. |
| `addMockYield(uint256 amount)` | external | Pulls test USDC into the reward pool. |
| `principalOf(address user)` | view | Recorded principal. |
| `streakOf(address user)` | view | Stored streak. |
| `weightOf(address user)` | view | Current reward weight. |
| `rewardOf(address user)` | view | Claimable reward. |
| `currentEpoch()` | view | `(block.timestamp - startTime) / epochDuration`. |
| `epochDuration()` | view | Immutable configuration. |

The plan (§4.2) suggests exactly these entry points (`deposit`, `withdraw`, `streakOf`, `principalOf`, `rewardOf`, `addMockYield`, `claimReward`). Any additional function must be justified.

---

## 3. State layout (proposed)

### 3.1 Immutables / constants

| Name | Type | Purpose |
|---|---|---|
| `usdc` | `IERC20 immutable` | Mock USDC token. |
| `epochDuration` | `uint64 immutable` | Configurable at deploy (CONFIRMED). Plan examples: 60 s for the Fuji demo, 7 days for the production concept. |
| `startTime` | `uint64 immutable` | Deployment timestamp; epoch anchor. |
| `PRECISION` | `uint256 constant = 1e18` | Accumulator precision (only if Model B is chosen). |

### 3.2 Global accounting

| Name | Type | Purpose |
|---|---|---|
| `totalPrincipal` | `uint256` | Sum of all user principal. Never includes yield. |
| `rewardPool` | `uint256` | Unclaimed mock yield held for users. Excludes principal. |
| `totalWeight` | `uint256` | Sum of active user weights (Model B) or current-epoch participants (Model A). |
| `accRewardPerWeight` | `uint256` | Yield-per-weight accumulator, scaled by `PRECISION` (Model B only). |

### 3.3 Per-user data

```solidity
struct UserInfo {
    uint256 principal;        // recorded deposits, never rewards
    uint64  streak;           // consecutive deposit epochs
    uint64  lastDepositEpoch; // epoch of the most recent counted deposit
    uint256 weight;           // cached reward weight
    uint256 rewardCredit;     // checkpointed, unclaimed yield
    uint256 rewardDebt;       // accumulator checkpoint (Model B)
}
mapping(address => UserInfo) public users;
```

Model A (epoch-scoped pot) additionally needs:

```solidity
mapping(address => mapping(uint64 => uint256)) public weightInEpoch;
mapping(uint64 => uint256) public totalWeightInEpoch;
mapping(uint64 => uint256) public rewardPoolInEpoch;
```

---

## 4. Epoch model

- **CONFIRMED:** `epochDuration` is a constructor parameter. Fuji demo uses a short epoch (e.g. 60 s); production concept is 7 days.
- **CONFIRMED:** no `advanceEpoch()` admin function. Epochs are derived from time (lazy).
- **PROPOSED:** a single global anchor `startTime = block.timestamp` at deployment, so all users share the same epoch boundaries:

  ```solidity
  function currentEpoch() public view returns (uint64) {
      return uint64((block.timestamp - startTime) / epochDuration);
  }
  ```

- Epoch 0 starts at deployment. A deposit exactly on a boundary belongs to the new epoch.
- **OPEN:** whether the anchor should be global (recommended) or the user's first deposit.

---

## 5. Principal accounting

Rules:

1. `users[u].principal` changes only on `deposit` and `withdraw`.
2. `totalPrincipal` is adjusted by the same delta in the same transaction.
3. Withdrawal is capped at `users[u].principal`; rewards can never be withdrawn through `withdraw`.
4. Contract token balance is **not** an accounting variable. Liabilities are `totalPrincipal + rewardPool`.
5. Invariant: `usdc.balanceOf(address(this)) >= totalPrincipal + rewardPool`. Equality holds unless someone donates tokens directly.
6. **PROPOSED:** after `safeTransferFrom`, compare the actual balance delta with `amount` and revert on mismatch (defends against fee-on-transfer tokens; MockUSDC is standard, so this is a guard, not a feature).

---

## 6. Deposit flow (proposed)

1. Reject `amount == 0` (**OPEN:** plan does not state it; zero deposits would still advance streak, so rejecting is recommended).
2. `epoch = currentEpoch()`.
3. Pull `amount` with `SafeERC20.safeTransferFrom`; verify received delta.
4. `principal += amount`; `totalPrincipal += amount`.
5. Update streak:

   | Condition | New streak |
   |---|---|
   | `streak == 0` (first deposit ever) | `1` (CONFIRMED) |
   | `epoch == lastDepositEpoch` | `streak` — repeated deposit in the same epoch must not double-count (**OPEN**, see BL-01) |
   | `epoch == lastDepositEpoch + 1` | `streak + 1` (CONFIRMED) |
   | `epoch > lastDepositEpoch + 1` | `1` (CONFIRMED) |

6. `lastDepositEpoch = epoch`.
7. Checkpoint reward accounting **before** the weight change (see §8/§9).
8. Update weight: `weight = streak`; `totalWeight -= oldWeight; totalWeight += newWeight` (CONFIRMED safeguard §16.4). Never `totalWeight += newWeight` without removing the old value.
9. Emit `Deposit` and, if the streak changed, `StreakUpdated`.

Deposits for another address are **not** proposed; keeping `msg.sender` avoids allowance/beneficiary confusion.

---

## 7. Withdraw flow (proposed)

1. Reject `amount == 0` and `amount > principal` (`InsufficientPrincipal`).
2. Checkpoint reward accounting before changing weight.
3. `principal -= amount`; `totalPrincipal -= amount`.
4. Weight rule (**OPEN**, see BL-02/BL-03):
   - Proposed: if `principal == 0`, set `weight = 0` so a zero-balance account cannot keep earning.
   - Proposed: partial withdrawal leaves `streak` and `weight` unchanged.
   - Proposed: streak is historical and is not reset by withdrawal; the next deposit in the next epoch continues it (needs confirmation).
5. Update `totalWeight` with old/new delta.
6. Transfer with `safeTransfer` after state changes (`nonReentrant`, checks-effects-interactions).
7. Emit `Withdraw`.

Withdrawal must never touch `rewardPool`, and `claimReward` must never touch `totalPrincipal`.

---

## 8. Streak and weight

- **CONFIRMED:** `weight = streak` (plan §4.4); no principal multiplier.
- **CONFIRMED:** missing one or more epochs resets the streak to 1 on the next deposit.
- Streak is evaluated lazily (only when the user acts). There is no cron and no per-user loop.
- **CONFIRMED:** `totalWeight` must be updated as `-oldWeight` then `+newWeight`; a test must assert `totalWeight == Σ weights` for the fixture.
- **OPEN:** whether `streakOf()` should return the stored value or an "effective" value (0/stale) when the user has missed epochs. A stale stored streak is misleading to the UI.

### Known structural issue: stale weight

Because weight only changes when a user acts, an inactive user keeps their weight and keeps earning yield forever unless `weight` is zeroed. Excluding inactive users from a global denominator requires either iterating users (forbidden by safeguard §16.1) or per-epoch participation accounting.

This is the main accounting decision for TS-02. Two candidate models follow.

---

## 9. Reward accounting — two candidate models

### Model A — epoch-scoped participation pot (recommended for MVP)

- Rewards are attached to a specific epoch `E`.
- Only users who deposited during `E` participate in `E`'s pot.
- On each deposit in `E`, update `weightInEpoch[user][E]` and `totalWeightInEpoch[E]` by the delta.
- `addMockYield` adds to `rewardPoolInEpoch[E]`.
- After epoch `E` closes, a participant claims:

  ```text
  reward = rewardPoolInEpoch[E] * weightInEpoch[user][E] / totalWeightInEpoch[E]
  ```

- No loops; every value is O(1) per action.
- T3 (two adds) is a simple sum within the epoch; T4/T5 (claim between adds) work only across epochs, because claims wait for the epoch to close. If the team requires claiming between two adds **inside the same epoch**, Model B is required.
- Matches plan §16.1 ("one active reward epoch, claim per epoch").
- Costs: per-epoch mappings; claim requires an epoch argument or a "latest matured epoch" convention; claims must wait for the epoch to close.

### Model B — continuous accumulator (later upgrade)

```text
on addMockYield (requires totalWeight > 0):
    accRewardPerWeight += amount * PRECISION / totalWeight
    rewardPool += amount

settle(user):
    checkpoint = user.weight * accRewardPerWeight / PRECISION
    user.rewardCredit += checkpoint - user.rewardDebt   // preserve earned yield
    user.rewardDebt = checkpoint

on weight change (deposit/withdraw):
    settle(user)
    totalWeight -= oldWeight
    user.weight = newWeight
    totalWeight += newWeight
    user.rewardDebt = user.weight * accRewardPerWeight / PRECISION

on claim:
    settle(user)
    amount = user.rewardCredit
    user.rewardCredit = 0
    rewardPool -= amount
    safeTransfer(user, amount)
```

- Immediate claiming, no epoch maturity.
- Handles interleaved add/claim correctly (T4/T5).
- **But:** does not remove inactive weight, so inactive users keep accruing; and it needs careful checkpointing on every weight change.
- Plan §16.1 allows this only after the MVP works and the extra tests exist.

**Recommendation:** implement Model A first (simpler, matches the plan's "claim per epoch" MVP and avoids continuous accrual), keep Model B as a post-MVP option. This is a team decision, not a confirmed rule.

### Reward boundaries (regardless of model)

1. `rewardPool` and `totalPrincipal` are separate state variables; `balanceOf(this)` is never used as either.
2. `claimReward` decrements `rewardPool` by exactly the amount transferred.
3. `withdraw` never reads or writes `rewardPool`.
4. Yield is only distributed when `totalWeight > 0`; otherwise revert or keep it unallocated (**OPEN**, BL-06).
5. Rounding is floor division; dust stays in the pool. Invariant: `Σ claimable <= rewardPool`.
6. Yield added after a user's weight checkpoint must not be retroactively claimable by that user (Model B checkpointing; Model A epoch scoping).
7. No loop over users in `addMockYield`, `claimReward`, or `withdraw`.

---

## 10. Events (proposed)

| Event | Parameters |
|---|---|
| `Deposit` | `address indexed user, uint256 amount, uint64 indexed epoch, uint64 streak` |
| `Withdraw` | `address indexed user, uint256 amount, uint256 principalRemaining` |
| `StreakUpdated` | `address indexed user, uint64 oldStreak, uint64 newStreak` |
| `YieldAdded` | `address indexed sender, uint256 amount, uint256 newRewardPool` |
| `RewardClaimed` | `address indexed user, uint256 amount` |

Events must be emitted after state changes so indexers/frontend see final values.

---

## 11. Custom errors (proposed)

| Error | When |
|---|---|
| `StreakSavings__ZeroAmount()` | Deposit/withdraw/add yield with `amount == 0`. |
| `StreakSavings__InsufficientPrincipal(uint256 requested, uint256 available)` | Withdraw above principal. |
| `StreakSavings__NoReward()` | Claim with nothing accrued. |
| `StreakSavings__InvalidEpochDuration()` | Constructor receives 0. |
| `StreakSavings__ZeroAddress()` | Constructor receives the zero token address. |
| `StreakSavings__NoActiveWeight()` | `addMockYield` while no weight exists (if that rule is chosen). |
| `StreakSavings__TransferMismatch(uint256 expected, uint256 received)` | Token delta check fails. |

---

## 12. External dependencies

| Dependency | Use |
|---|---|
| `MockUSDC` (`IERC20`, 6 decimals) | Principal and yield token; address fixed at construction. |
| OpenZeppelin `SafeERC20` | Safe `transfer` / `transferFrom`. |
| OpenZeppelin `ReentrancyGuard` | `nonReentrant` on deposit/withdraw/claim/addMockYield. |
| OpenZeppelin `IERC20` | Typed token interface. |

No oracles, no Aave/Benqi, no proxy, no upgradeability, no NFT. No admin/owner is proposed; the trade-off is that a stuck-token rescue function is impossible, which is acceptable for a testnet hackathon.

---

## 13. Security risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Reentrancy through token hooks | Drain funds | `nonReentrant` + state updates before transfers. |
| Principal/reward commingling | Claim eats principal | Separate variables and invariant tests. |
| `totalWeight` drift | Wrong reward shares | Delta updates (`-old`, `+new`) and a fixture invariant test. |
| Zero-principal weight farming | Free reward share | Set `weight = 0` when principal is 0 (BL-03). |
| Inactive/stale weight | Rewards to non-participants | Model A epoch scoping, or accept and document for Model B. |
| Retroactive yield | Late depositors claim old yield | Checkpoints (Model B) or epoch scoping (Model A). |
| Epoch-boundary gaming | Double streak in one epoch | `epoch == lastDepositEpoch` is a no-op for streak. |
| Rounding dust | Last claimer underflow | Floor division; dust stays in pool. |
| Fee-on-transfer token | Accounting mismatch | Balance-delta check after `transferFrom`. |
| Direct token donation | Inflated balance | Never use `balanceOf` for accounting. |
| Unlimited mock mint | Fake scarcity | Test-only token, documented; never use real funds. |
| No upgrade path | Bug is permanent | Freeze + full tests before Fuji; keep contract small. |
| Stale `streakOf` display | Misleading UI | Decide effective-value semantics (BL-09). |

---

## 14. Minimum test matrix before TS-02 merge

Map to plan §16.6, plus principal invariants:

| ID | Scenario | Pass condition |
|---|---|---|
| T1 | Alice deposits before Bob | Reward shares follow weights at distribution time. |
| T2 | Different streaks | Reward ratio equals weight ratio. |
| T3 | Two `addMockYield` calls | No double counting. |
| T4 | Alice claims between adds | Later reward still correct. |
| T5 | Bob claims last | Nothing is lost. |
| T6 | Streak/weight changes | `totalWeight` never accumulates incorrectly. |
| T7 | Withdraw principal then add yield | Reward math unchanged. |
| T8 | Claim reward | `totalPrincipal` untouched. |
| P1 | Deposit/withdraw sequences | `Σ principal == totalPrincipal`. |
| P2 | Any flow | `balanceOf(this) >= totalPrincipal + rewardPool`. |
| P3 | Repeated deposit in one epoch | Streak and weight unchanged; principal increases. |
| P4 | Missed epoch | Next deposit sets streak to 1. |
| P5 | Full withdrawal | Weight is 0; reward pool unchanged. |
| P6 | Unauthorized/zero-amount/over-withdraw | Reverts with the documented custom error. |

---

## 15. Open business rules — must be confirmed before implementation

| ID | Question | Why it matters | Proposal (not decided) |
|---|---|---|---|
| BL-01 | Multiple deposits in the same epoch: does the second deposit change the streak? | Double-counting would let one epoch produce many streak points. | Streak unchanged; principal adds. |
| BL-02 | Does a full withdrawal reset the streak? | Affects whether a user can leave and resume a streak. | Keep streak as history; weight 0 while principal 0. |
| BL-03 | Should weight be 0 when principal is 0? | Prevents free reward share. | Yes. |
| BL-04 | Does a partial withdrawal keep the full streak weight? | A user could withdraw 99% and keep a high weight. | Keep weight; no principal multiplier per plan §4.4. |
| BL-05 | Can a user with zero principal claim previously earned rewards? | Earned yield should not be confiscated. | Yes, claim credit only. |
| BL-06 | What happens to `addMockYield` when no user has weight? | Stranded or retroactively distributed yield. | Revert with `NoActiveWeight` for MVP. |
| BL-07 | Can anyone call `addMockYield`, or only a demo account? | Permissionless donations are harmless; restricted adds an admin role. | Permissionless. |
| BL-08 | What is the minimum deposit (if any)? | Dust deposits and gas griefing. | No minimum for hackathon; document. |
| BL-09 | Should `streakOf()` show the stored or effective streak after missed epochs? | UI correctness and reward eligibility. | Effective view: 0 if more than one epoch missed, until next deposit. |
| BL-10 | Reward claim timing: immediate (Model B) or after epoch close (Model A)? | Determines the accounting model and UI flow. | Model A with claim after close. |
| BL-11 | One claim per epoch or one `claimReward()` for all matured epochs? | Interface and gas; loops. | `claimReward(uint64 epoch)` plus a latest-epoch convenience. |
| BL-12 | Is `epochDuration` immutable, or can it change? | Changing it mid-game breaks fairness. | Immutable. |
| BL-13 | Are unclaimed epoch rewards rolled forward, forfeited, or left claimable forever? | Pool solvency and UI. | Left claimable forever (no expiry) for MVP. |
| BL-14 | Can users deposit for another address? | Allowance/beneficiary complexity. | No. |
| BL-15 | Is there a TVL/deposit cap? | Demo safety only; not specified. | No cap for testnet. |

---

## 16. Suggested implementation order (after decisions)

1. Confirm BL-01, BL-02, BL-03, BL-10, BL-11 (the five that change storage layout).
2. Implement principal accounting + deposit/withdraw + events/errors.
3. Add epoch and streak logic; test P3/P4.
4. Add reward accounting for the chosen model; run T1–T8 and P1–P6.
5. Only then consider Fuji deployment, frontend ABI export, and the NFT bonus.

**Gate:** no `addMockYield` / `claimReward` implementation until the principal invariants P1/P2 and the weight invariant T6 pass.
