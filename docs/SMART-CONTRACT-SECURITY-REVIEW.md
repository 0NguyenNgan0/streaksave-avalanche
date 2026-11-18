# Smart Contract Security Review — StreakSave

**Reviewer:** Member A (Smart Contract & Avalanche Engineer)  
**Date:** 18/11/2026  
**Scope:**
- [`contracts/src/MockUSDC.sol`](../contracts/src/MockUSDC.sol)
- [`contracts/src/StreakSavings.sol`](../contracts/src/StreakSavings.sol)
- [`contracts/src/libraries/StreakAccountingMath.sol`](../contracts/src/libraries/StreakAccountingMath.sol)
- [`contracts/script/Deploy.s.sol`](../contracts/script/Deploy.s.sol)

> [!NOTE]
> This is an internal engineering review, not an independent third-party audit. The contracts are testnet MVP code using a valueless mock token.

---

## 1. Threat Model

- **Assets / liabilities:** `MockUSDC` principal and mock-yield rewards. The token has zero monetary value but is treated with real-ERC20 rigor.
- **Actors:**
  - *Users:* untrusted; call `deposit`, `withdraw`, `claimReward`, `claimRewardFor` for themselves.
  - *Yield provider:* trusted demo account; the only account allowed to call `addMockYield`.
  - *MockUSDC minter:* deployer; can mint test tokens by design.
  - *Adversarial tokens:* used in tests to simulate fee-on-transfer and reentrancy.
- **Core properties:**
  1. `totalPrincipal == Σ principalOf(user)`.
  2. `usdc.balanceOf(this) >= totalPrincipal + totalRewardPool`.
  3. Claims never reduce principal; withdrawals never reduce another user's rewards.
  4. A closed epoch's weight snapshot cannot change.
  5. No operation loops over all users.
  6. Reward claims are at most once per user per epoch.

---

## 2. Security Checklist

| # | Area | Status | Evidence |
|---|---|---|---|
| 1 | Reentrancy | **Mitigated** | `nonReentrant` on `deposit`, `withdraw`, `addMockYield`, `claimReward`, `claimRewardFor`. Tests: deposit, withdraw, and claim reentrancy via malicious tokens. |
| 2 | Checks-Effects-Interactions | **Verified** | `withdraw` and `_claimReward` update state before transfers. `deposit`/`addMockYield` pull first only to measure the exact delta; both are guarded and state changes occur after the delta check. |
| 3 | Principal accounting | **Verified** | Principal changes only in `deposit`/`withdraw`; `totalPrincipal` delta matches. Stateful invariant suite with ghost accounting. |
| 4 | Reward/principal separation | **Verified** | Separate `totalPrincipal` and `totalRewardPool`; claims cannot alter principal; withdrawals cannot alter reward pools. |
| 5 | Double claims | **Prevented** | `claimedInEpoch[user][epoch]` is set before transfer; double-claim test reverts. |
| 6 | Claims before finalization | **Prevented** | `claimRewardFor` requires `epoch < currentEpoch()`; `claimReward` requires `currentEpoch() > 0`. |
| 7 | End-of-epoch snapshot | **Verified** | Per-epoch mappings are written only during their epoch; later deposits/withdrawals cannot touch closed epochs. T6/T7 cover this. |
| 8 | Unbounded loops | **None** | No loops in production contracts. Invariant/test loops are bounded fixtures only. |
| 9 | Overflow / underflow | **Mitigated** | Solidity 0.8 checked arithmetic; `Math.mulDiv` for reward products; `SafeCast` for timestamps/epochs. |
| 10 | Rounding / dust | **Explicit** | Floor division; dust stays in `totalRewardPool` and the contract balance; test verifies 1-base-unit dust. |
| 11 | Zero-weight epoch | **Handled** | `addMockYield` reverts with `NoActiveWeight`; snapshots with zero weight yield zero and cannot distribute. |
| 12 | Reward pool over-distribution | **Prevented** | `sum(shares) <= epoch pool`; fuzz test and invariant `balance >= principal + totalRewardPool`. |
| 13 | Access control | **Restricted** | `addMockYield` only `yieldProvider`; no owner/pause/upgrade. Unauthorized test reverts. |
| 14 | Fee-on-transfer tokens | **Rejected** | Exact balance-delta check in `_pullTokens`; fee token test reverts. |
| 15 | Direct donations | **Isolated** | `balanceOf` is never used as accounting; donations create surplus only. |
| 16 | Front-running / late deposits | **Accepted for MVP** | A user can deposit before `addMockYield` within the same epoch and share that epoch's pool. This is the confirmed end-of-epoch snapshot model, not a bug. Production should use time-weighted or lock-based eligibility. |
| 17 | Inactive/stale weight | **Contained** | `totalWeight` is a cached aggregate; reward snapshots count only users who checked in during that epoch, so inactive users cannot dilute later epochs. |
| 18 | Zero-principal farming | **Prevented** | Full withdrawal sets weight to 0; `addMockYield` requires active epoch weight. |
| 19 | Same-epoch streak inflation | **Prevented** | Same-epoch deposits do not increment streak; fuzz test with up to 20 deposits. |
| 20 | Full withdrawal streak reuse | **Prevented** | Streak and last checkpoint reset; next deposit starts at 1. |
| 21 | Unclaimed reward expiry | **None** | No expiry logic; `claimRewardFor` works after 100 epochs in tests. |
| 22 | Privileged fund rescue | **Absent by design** | No admin can move principal or rewards. Trade-off: stuck/unallocated mock yield cannot be rescued. |
| 23 | Storage collisions | **N/A** | Non-upgradeable, no delegatecall/proxy. |
| 24 | Event correctness | **Verified** | Events emit after state changes; `Deposit`/`Withdraw` signatures unchanged. |

---

## 3. Findings and Design Trade-offs

### Resolved during implementation

| ID | Issue | Resolution |
|---|---|---|
| SEC-01 | Silent `uint64` truncation on arbitrary timestamps | `SafeCast` + `TimestampBeforeStart`. |
| SEC-02 | Zero epoch duration division by zero | Constructor revert. |
| SEC-03 | Unsafe deployment broadcast | Chain ID, key, duration, and post-deploy checks. |
| SEC-04 | Same-epoch streak farming | Same-epoch deposits are principal-only (BR-01). |
| SEC-05 | Zero-principal weight farming | Full withdrawal zeroes active weight (BR-03). |
| SEC-06 | Reward over-distribution / overflow | `Math.mulDiv`, floor shares, pool invariants. |
| SEC-07 | Double claim | `claimedInEpoch` set before transfer. |
| SEC-08 | Closed epoch manipulation | All snapshot writes target `currentEpoch()` only. |

### Remaining risks (accepted for the MVP)

| ID | Severity | Risk | Mitigation / note |
|---|---|---|---|
| RISK-01 | Low | **`rewardOf` reports only the latest finalized epoch.** Older unclaimed rewards are not included in that view. | Rewards never expire; use `claimRewardFor(epoch)` / `rewardInEpoch`. Frontend must not label it as a lifetime total. |
| RISK-02 | Low | **Unallocated pool if all participants withdraw before an epoch closes.** | Funds remain in `totalRewardPool` and are backed; no user is entitled. No admin rescue by design. |
| RISK-03 | Low | **99% partial withdrawal retains full streak weight** (`weight = streak`, no principal multiplier). | Confirmed MVP rule; production should add principal-weighted or minimum-lock eligibility. |
| RISK-04 | Low | **`yieldProvider` key loss prevents new mock yield.** | Demo account key is controlled by the team; no admin transfer by design. |
| RISK-05 | Low | **Late same-epoch deposit can share yield added earlier in that epoch.** | Consequence of the confirmed end-of-epoch snapshot; acceptable for mock yield on Fuji. |
| RISK-06 | Informational | **`totalWeight` can include cached weights of users who stopped checking in.** | Reward math never uses `totalWeight`; it uses per-epoch snapshots. |
| RISK-07 | Informational | **No third-party audit.** | Hackathon testnet scope; do not use with real funds. |

---

## 4. Verification Results

Commands run from `contracts/` on 18/11/2026:

```powershell
forge fmt --check
forge clean
forge build --sizes
forge test -vvv
```

| Suite | Passed | Failed | Skipped |
|---|---:|---:|---:|
| `Deploy.t.sol` | 5 | 0 | 0 |
| `MockUSDC.t.sol` | 13 | 0 | 0 |
| `StreakAccountingMath.t.sol` | 22 | 0 | 0 |
| `StreakSavings.t.sol` | 35 | 0 | 0 |
| `StreakSavings.rewards.t.sol` | 26 | 0 | 0 |
| `StreakSavings.invariant.t.sol` | 1 | 0 | 0 |
| `StreakSavings.rewards.invariant.t.sol` | 1 | 0 | 0 |
| **Total** | **103** | **0** | **0** |

- Two invariant suites: 128 runs each, 4,096 calls, 0 reverts.
- `forge fmt --check`: pass.
- `forge build --sizes`: pass.

### Contract sizes

| Contract | Runtime | Initcode |
|---|---:|---:|
| `MockUSDC` | 2,072 B | 2,564 B |
| `StreakSavings` | 6,449 B | 7,002 B |

Both are within the 24 KB EIP-170 limit.

---

## 5. Deployment Status

**Not deployed.** Fuji deployment requires explicit user authorization and a funded Dev Wallet. The deployment script is prepared and tested locally; see [`FUJI-DEPLOYMENT.md`](./FUJI-DEPLOYMENT.md).
