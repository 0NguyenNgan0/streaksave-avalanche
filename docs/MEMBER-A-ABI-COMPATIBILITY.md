# Member A — Frontend & Shared ABI Compatibility Report

**Status:** Final contract ABI stable for MVP integration.  
**Date:** 18/11/2026  
**Frontend inspected:** `apps/web/lib/contracts.ts`, `apps/web/hooks/use-streaksave.ts`, `apps/web/lib/chain.ts`, `apps/web/app/*`  
**Contracts inspected:** `contracts/src/MockUSDC.sol`, `contracts/src/StreakSavings.sol`  
**Shared folder:** `shared/` is still Member C's integration task; this document is the handoff source of truth until then.

---

## 1. Compatibility Summary

### `MockUSDC`
| Frontend expectation | Contract | Status |
|---|---|---|
| `allowance`, `balanceOf`, `approve` | OZ `ERC20` | Compatible |
| 6 decimals | `decimals() == 6` | Compatible |
| `mint` | Deployer-only, not exposed to users | Demo/admin only |

### `StreakSavings`
| Frontend expectation | Contract | Status |
|---|---|---|
| `principalOf(address) → uint256` | Implemented | Compatible |
| `streakOf(address) → uint256` | Implemented (stored streak) | Compatible |
| `rewardOf(address) → uint256` | Implemented (latest finalized epoch) | Compatible signature; see §3 |
| `deposit(uint256)` | Implemented | Compatible |
| `withdraw(uint256)` | Implemented | Compatible |
| `claimReward()` | Implemented (latest finalized epoch) | Compatible |
| `claimRewardFor(uint64)` | Implemented (older epochs) | **New; add to frontend ABI when historical claims are surfaced** |
| `addMockYield(uint256)` | Implemented (yieldProvider only) | **New; demo/admin action, not a user action** |

No existing frontend function signature was removed or changed. No frontend files were modified.

---

## 2. Available Contract Interface

### Views
- `usdc() → address`
- `epochDuration() → uint64`
- `startTime() → uint64`
- `yieldProvider() → address`
- `principalOf(address) → uint256`
- `streakOf(address) → uint256` — stored streak; 0 after full withdrawal
- `effectiveStreakOf(address) → uint256` — 0 after a missed epoch; intended for UI display
- `weightOf(address) → uint256` — cached active weight
- `lastDepositEpochOf(address) → uint64`
- `totalPrincipal() → uint256`
- `totalWeight() → uint256`
- `totalRewardPool() → uint256`
- `currentEpoch() → uint64`
- `epochAt(uint256) → uint64`
- `epochStart(uint64) → uint256`
- `epochEnd(uint64) → uint256`
- `nextEpochTimestamp() → uint256`
- `timeUntilNextEpoch() → uint256`
- `isEpochFinalized(uint64) → bool`
- `weightInEpoch(address, uint64) → uint256`
- `totalWeightInEpoch(uint64) → uint256`
- `rewardPoolInEpoch(uint64) → uint256`
- `claimedInEpoch(address, uint64) → bool`
- `rewardInEpoch(address, uint64) → uint256`
- `rewardOf(address) → uint256`

### State-changing
- `deposit(uint256)`
- `withdraw(uint256)`
- `addMockYield(uint256)` — only `yieldProvider`
- `claimReward()`
- `claimRewardFor(uint64)`

---

## 3. Important Semantics for the Frontend

### `rewardOf` is latest-epoch only
`rewardOf(user)` returns the claimable amount for `currentEpoch() - 1` only. It does not sum all historical unclaimed epochs. This keeps the zero-argument `claimReward()` O(1) and avoids an unbounded history scan.

- Normal demo flow (one deposit per epoch) works with `rewardOf` + `claimReward()`.
- If a user returns after several epochs, older rewards remain claimable via `claimRewardFor(epoch)`.
- To display a lifetime total, the frontend must query `rewardInEpoch` for the relevant epochs or index `RewardClaimed` events.
- A user who has already claimed the latest finalized epoch will see `rewardOf == 0` even if older epochs are unclaimed.

### `streakOf` vs `effectiveStreakOf`
- `streakOf` returns the stored streak. It can remain non-zero during the grace epoch after the last check-in.
- `effectiveStreakOf` returns 0 once at least one full epoch has been missed. Use it for the "current streak" UI.
- Both return 0 when principal is 0.

### Epoch countdown
Use `currentEpoch()`, `nextEpochTimestamp()`, or `timeUntilNextEpoch()` for the countdown required by Plan v3 §16.2.

### Deposit UX
- The existing approve → deposit state machine remains valid.
- A deposit in the same epoch after the first one is a top-up: principal increases, streak does not.
- A full withdrawal resets the streak; the next deposit starts at 1.

### Claim UX
- `claimReward()` claims the latest finalized epoch. It reverts if no reward exists or the epoch is already claimed.
- For older rewards, expose `claimRewardFor(epoch)` or a history list.
- Claiming never changes principal.

### Mock yield
- `addMockYield` is restricted to `yieldProvider` (the deployment account).
- The provider must `approve` `StreakSavings` for the mock USDC amount before calling.
- Yield is assigned to the current epoch and requires at least one checked-in user.
- Do not present mock yield as real DeFi yield.

### Events
- `Deposit(address indexed user, uint256 amount)`
- `Withdraw(address indexed user, uint256 amount, uint256 principalRemaining)`
- `StreakUpdated(address indexed user, uint64 indexed epoch, uint64 oldStreak, uint64 newStreak)`
- `StreakReset(address indexed user, uint64 indexed epoch, uint64 previousStreak)`
- `MockYieldAdded(address indexed provider, uint64 indexed epoch, uint256 amount, uint256 epochRewardPool)`
- `RewardClaimed(address indexed user, uint64 indexed epoch, uint256 amount)`

The current frontend only checks receipt status and refetches views, so event additions do not break it.

---

## 4. Required Frontend Updates (Member B)

1. Add `claimRewardFor(uint64)` and `addMockYield(uint256)` to `streakSavingsAbi` if those flows are surfaced.
2. Add `rewardInEpoch(address,uint64)`, `effectiveStreakOf(address)`, `currentEpoch()`, and `timeUntilNextEpoch()` for history and countdown.
3. Use `effectiveStreakOf` for the main streak display, or compare `lastDepositEpochOf` with `currentEpoch()`.
4. Do not display `rewardOf` as a lifetime total; label it "latest epoch reward" or build an epoch history.
5. Do not point the frontend at an address until the deployed bytecode matches this ABI and the deployment record is updated.

---

## 5. Integration Sequence

1. Member C exports ABI from `contracts/out/` into `shared/abi/`.
2. Member C records Fuji addresses in `shared/config/`.
3. Member B imports from `shared/` or updates `apps/web/lib/contracts.ts` with the additions above.
4. Run an end-to-end fresh-wallet flow: approve → deposit → stake across epochs → add yield → claim → withdraw.
