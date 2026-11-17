# Smart Contract Security Review — StreakSave

**Reviewer:** Member A (Smart Contract & Avalanche Engineer)  
**Date:** 17/11/2026  
**Scope:**
- [`contracts/src/MockUSDC.sol`](../contracts/src/MockUSDC.sol)
- [`contracts/src/StreakSavings.sol`](../contracts/src/StreakSavings.sol)
- [`contracts/src/libraries/StreakAccountingMath.sol`](../contracts/src/libraries/StreakAccountingMath.sol)
- [`contracts/script/Deploy.s.sol`](../contracts/script/Deploy.s.sol)

> [!NOTE]
> This is an **internal engineering security review**, not an independent third-party audit. Streak, weight, `addMockYield`, `rewardOf`, and `claimReward` state transitions are **not** yet implemented on `StreakSavings.sol` because blocking business rules (`BL-01`, `BL-02`, `BL-03`, `BL-10`, `BL-11`, `BL-13`) remain unapproved.

---

## 1. Threat Model

- **Assets / Liabilities:** Testnet `MockUSDC` (6 decimals, zero real monetary value; treated with real-ERC20 rigor to preserve MVP correctness).
- **Actors:**
  - *Depositors (`msg.sender`):* untrusted external EOAs or contracts calling `deposit(uint256)` and `withdraw(uint256)`.
  - *Deployer (`minter` on `MockUSDC`):* trusted testnet demo operator holding the immutable `MockUSDC` mint privilege; holds **zero** privileged controls on `StreakSavings` (no owner, no pause, no rescue, no `advanceEpoch()`).
  - *Direct Donors / Adversarial Tokens:* actors transferring tokens directly to `StreakSavings` outside `deposit()`, or test setups pairing fee-on-transfer / reentrant tokens.
- **Core Security Properties:**
  1. `totalPrincipal == Σ principalOf(user)` across all users.
  2. `usdc.balanceOf(address(streakSavings)) >= totalPrincipal` at all times.
  3. Direct token transfers to `StreakSavings` never inflate any user's withdrawable principal.
  4. Users can withdraw up to their recorded principal at any time regardless of epoch transitions or missing future features.
  5. Epoch clock arithmetic never truncates silently, never divides by zero, and never requires admin intervention.

---

## 2. Sixteen-Point Security Checklist (Current Codebase)

| # | Area | Status | Notes / Evidence |
|---|---|---|---|
| 1 | **Reentrancy** | **Mitigated** | Both `deposit` and `withdraw` use OpenZeppelin `ReentrancyGuard` (`nonReentrant`). Covered by `test_RevertWhen_DepositReenters` and `test_RevertWhen_WithdrawReenters` using `ReentrantToken`. |
| 2 | **Checks-Effects-Interactions (CEI)** | **Verified** | `withdraw` checks `amount > 0` and `amount <= available`, updates `_principal[msg.sender]` and `totalPrincipal`, then calls `safeTransfer`. `deposit` pulls tokens first solely to verify actual received delta, protected by `nonReentrant`, and credits principal only after delta verification succeeds. |
| 3 | **Incorrect Accounting** | **Verified** | Principal changes only in `deposit` and `withdraw` by identical deltas on `_principal[msg.sender]` and `totalPrincipal`. Verified across 128 stateful invariant runs (4,096 calls, 0 reverts). |
| 4 | **Integer Overflow / Underflow / Truncation** | **Mitigated** | Solidity `0.8.24` checked arithmetic throughout; `SafeCast.toUint64` guards `startTime`, `currentEpoch()`, `epochAt(uint256)`, and `StreakAccountingMath.computeEpoch(...)` against silent `uint256 -> uint64` downcast truncation. Covered by `test_Epoch_EpochAtRevertWhen_OverflowUint64`. |
| 5 | **Precision & Rounding Errors** | **Analyzed / Tested** | Principal accounting uses integer 6-decimal base units with zero division. Reward floor-division formulas in `StreakAccountingMath` preserve `sum(shares) <= pool` across fuzz runs (`testFuzz_RewardMath_SumOfSharesNeverExceedsPool`); Model B adds up to 1 wei of floor-division dust per yield addition compared to Model A (`test_T3_Math_TwoYieldAdditionsSumWithoutDoubleCounting`). |
| 6 | **Timestamp Boundary Issues** | **Verified** | `epochDuration == 0` rejected in constructor; `epochAt(timestamp < startTime)` reverts cleanly (`TimestampBeforeStart`); boundary tests verify `T - 1`, `T`, and `T + 1` plus 256 fuzz runs (`testFuzz_Epoch_BoundariesAndCountdownAreConsistent`). |
| 7 | **Unbounded Loops** | **Verified** | Zero loops anywhere in `MockUSDC`, `StreakSavings`, or `StreakAccountingMath`. All operations are `O(1)`. |
| 8 | **Unexpected External Calls** | **Mitigated** | Constructor rejects zero-address and EOA token addresses (`address(usdc_).code.length == 0`). `usdc` is `immutable` and uses OpenZeppelin `SafeERC20`. |
| 9 | **Privileged Access** | **Verified** | `StreakSavings` has **no** owner, admin, pause, upgradeability, or rescue backdoor. `MockUSDC` restricts `mint` exclusively to `immutable minter` (`testFuzz_RevertWhen_AnyNonMinterMints`). |
| 10 | **Token Incompatibility** | **Mitigated** | `SafeERC20` handles non-standard return values; actual balance delta check (`received != amount`) rejects fee-on-transfer / rebasing-down deposits (`test_RevertWhen_FeeOnTransferDeposit`). |
| 11 | **Denial-of-Service Conditions** | **Verified** | Direct token transfers to `StreakSavings` cannot break `deposit` or `withdraw` because `totalPrincipal` and balance deltas are independent of prior donated balances (`test_DirectDonationBeforeAnyDepositDoesNotAffectPrincipal`). |
| 12 | **Storage Collision Risks** | **Verified** | Contracts are non-upgradeable (no proxy or `delegatecall`). |
| 13 | **Incorrect Event Emission** | **Verified** | `Deposit` and `Withdraw` emit only after state updates succeed, with `principalRemaining` matching post-withdrawal state. |
| 14 | **Front-Running Implications** | **Low / Not Applicable Yet** | No AMM pricing or yield-stealing surface is deployed yet; epoch-based yield front-running (`addMockYield` vs late epoch `deposit`) is analyzed below for the upcoming reward phase. |
| 15 | **Reward Double-Claiming** | **Blocked / Design-Gated** | Not yet deployed; will require strict per-epoch `claimedInEpoch` (Model A) or checkpoint `rewardDebt` advance (Model B) before `safeTransfer`. |
| 16 | **Principal / Reward Commingling** | **Enforced at Core** | `balanceOf(address(this))` is never used as `totalPrincipal`; future `rewardPool` must remain a separate state variable. |

---

## 3. Findings & Risk Register

### 3.1 Resolved / Confirmed Hardening Implemented

| ID | Category | Finding & Fix |
|---|---|---|
| **SEC-01** | Input / Truncation Guard (Low) | **Silent `uint64` downcast risk on arbitrary timestamps in `epochAt(uint256)`**: Using raw `uint64(...)` would silently wrap if `epochAt` received a far-future `uint256` timestamp with `epochDuration = 1`. **Fixed** using OpenZeppelin `SafeCast.toUint64` in `StreakSavings.sol` and `StreakAccountingMath.sol`, plus `StreakSavings__TimestampBeforeStart` for `timestamp < startTime`. |
| **SEC-02** | Configuration Validation (Low) | **Zero-duration epoch clock**: Passing `epochDuration = 0` would trigger division-by-zero panic on `currentEpoch()`. **Fixed** by rejecting `epochDuration_ == 0` with `StreakSavings__InvalidEpochDuration()` in constructor and `Deploy.s.sol`. |
| **SEC-03** | Deployment Safety (Low) | **Accidental wrong-chain or default-key broadcast**: Script execution without explicit key or against an unintended network could misdeploy. **Fixed** in `Deploy.s.sol` by rejecting missing/zero keys, validating chain ID (`43113` or opt-in `31337`), and asserting post-deployment invariants on-chain. |

### 3.2 Remaining Theoretical & Design Risks (For Upcoming Streak/Reward Phases & Production)

| ID | Severity | Risk Description | Recommended Mitigation |
|---|---|---|---|
| **RISK-01** | **High (if BL-03 misconfigured)** | **Zero-principal weight farming:** If `weight` stays non-zero after full withdrawal (`BL-03` Option B), an attacker can build a streak once, withdraw 100% principal, and claim yield risk-free. | Team must adopt **BL-03 Option A** (`weight = 0` when `principal == 0`). |
| **RISK-02** | **High (if BL-01 misconfigured)** | **Same-epoch streak inflation:** Incrementing streak per deposit (`BL-01` Option B) lets one user split 1 deposit into N micro-deposits to gain weight N in 1 epoch. | Team must adopt **BL-01 Option A** (same-epoch deposit does not increment streak). |
| **RISK-03** | **Medium (Design Trade-off)** | **Deposit-before-yield MEV / last-second epoch entry:** Under Model A or Model B, if `addMockYield` is broadcast in the mempool, an observer could front-run with a `deposit` inside the same epoch to capture weight in that epoch. | Acceptable for a mock community yield hackathon demo on Fuji; production integration with real yield (Aave/Benqi) should enforce time-weighted / min-lock eligibility or epoch-lagged weight activation. |
| **RISK-04** | **Medium (Design Trade-off)** | **99% partial withdrawal retains full streak weight (`BL-04`):** Because Plan v3 §4.4 fixes `weight = streak` (no principal multiplier), a user with 100 USDC can withdraw 99.999999 USDC and retain full weight while `principal > 0`. | Explicitly documented in `BL-DECISIONS-PROPOSAL.md` (`BL-04`). Production version should introduce principal-weighted or minimum-principal thresholds. |
| **RISK-05** | **Medium (Model B only)** | **Inactive stale weight in continuous accumulator:** If Model B is chosen without epoch pruning, inactive depositors who never withdraw keep `weight` in `totalWeight` indefinitely. | Prefer **Model A** (epoch-scoped participation) for MVP, or explicitly document stale weight if Model B is chosen for demo UX. |
| **RISK-06** | **Low (Mock Token)** | **Unlimited `MockUSDC` minting by deployer & unrecovered direct transfers:** Deployer can mint arbitrary test USDC, and tokens sent directly via `ERC20.transfer` remain unallocated in the contract (no admin rescue function exists). | Intentional for trust-minimized testnet demo (`MockUSDC` has zero monetary value; absence of rescue avoids admin fund-drain vectors). |

---

## 4. Verification Commands & Observed Results

Executed on `D:\Trong\4. UniHack\contracts` after all code and test edits (`17/11/2026`):

```powershell
forge fmt --root "D:\Trong\4. UniHack\contracts" --check
forge clean --root "D:\Trong\4. UniHack\contracts"
forge build --root "D:\Trong\4. UniHack\contracts" --sizes
forge test --root "D:\Trong\4. UniHack\contracts" -vvv
```

### Contract Size Output (`Solc 0.8.24`, optimizer `200` runs, `shanghai`)

| Contract | Runtime Size (B) | Initcode Size (B) | Runtime Margin (B) |
|---|---|---|---|
| `MockUSDC` | 2,072 | 2,564 | 22,504 |
| `StreakSavings` | 2,760 | 3,269 | 21,816 |

### Test Suite Results

| Test Suite | Passed | Failed | Skipped | Notes |
|---|---|---|---|---|
| `test/Deploy.t.sol:DeployTest` | 5 | 0 | 0 | Chain ID checks, zero-key/duration reverts, Fuji & Anvil dry runs |
| `test/MockUSDC.t.sol:MockUSDCTest` | 13 | 0 | 0 | Includes 2 fuzz tests × 256 runs each |
| `test/StreakAccountingMath.t.sol:StreakAccountingMathTest` | 22 | 0 | 0 | Includes 3 fuzz tests × 256 runs each + T1–T8 math verification |
| `test/StreakSavings.t.sol:StreakSavingsTest` | 35 | 0 | 0 | Includes 3 fuzz tests × 256 runs each (principal + epoch clock) |
| `test/StreakSavings.invariant.t.sol:StreakSavingsInvariantTest` | 1 | 0 | 0 | 5 stateful invariants across 128 runs, 4,096 calls, 0 reverts |
| **Total** | **76** | **0** | **0** | `forge fmt --check` exited `0` |
