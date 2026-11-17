# Member A — Frontend & Shared ABI Compatibility Report

**Frontend Inspected:**
- [`apps/web/lib/contracts.ts`](../apps/web/lib/contracts.ts)
- [`apps/web/hooks/use-streaksave.ts`](../apps/web/hooks/use-streaksave.ts)
- [`apps/web/lib/chain.ts`](../apps/web/lib/chain.ts)
- [`apps/web/app/page.tsx`](../apps/web/app/page.tsx), [`deposit/page.tsx`](../apps/web/app/deposit/page.tsx), [`rewards/page.tsx`](../apps/web/app/rewards/page.tsx), [`withdraw/page.tsx`](../apps/web/app/withdraw/page.tsx)

**Contracts Inspected:**
- [`contracts/src/MockUSDC.sol`](../contracts/src/MockUSDC.sol)
- [`contracts/src/StreakSavings.sol`](../contracts/src/StreakSavings.sol)

**Shared Folder Status:** `shared/` does **not** exist yet in `feature/principal-accounting` (planned by Plan v3 §15.9 under Member C coordination).

---

## 1. Frontend Expectation vs. Current Contract Implementation

### 1.1 `MockUSDC` vs. `erc20Abi` (`apps/web/lib/contracts.ts`)

| Frontend Expects | Current `MockUSDC.sol` | Compatibility | Notes |
|---|---|---|---|
| `allowance(address owner, address spender) view returns (uint256)` | Inherited from OZ `ERC20` | **Compatible** | Returns 6-decimal allowance. |
| `balanceOf(address account) view returns (uint256)` | Inherited from OZ `ERC20` | **Compatible** | 6-decimal balance (`USDC_DECIMALS = 6` in `use-streaksave.ts` matches `MockUSDC.decimals() == 6`). |
| `approve(address spender, uint256 amount) returns (bool)` | Inherited from OZ `ERC20` | **Compatible** | Standard approve flow. |
| *(Not in frontend yet)* `mint(address to, uint256 amount)` | Implemented (deployer-only) | **Admin/Demo only** | Deployer mints test USDC to demo wallets via script or `cast`; not exposed to end users. |

### 1.2 `StreakSavings` vs. `streakSavingsAbi` (`apps/web/lib/contracts.ts`)

| Entry Point | Frontend Expects (`contracts.ts`) | Current `StreakSavings.sol` | Compatibility | Blocking Decision |
|---|---|---|---|---|
| `principalOf(address user)` | `view returns (uint256)` | `external view returns (uint256)` | **Compatible** | None |
| `deposit(uint256 amount)` | `nonpayable returns ()` | `external nonReentrant` | **Compatible (signature)** | Streak/weight update inside `deposit` awaits **BL-01** & **BL-03** |
| `withdraw(uint256 amount)` | `nonpayable returns ()` | `external nonReentrant` | **Compatible (signature)** | Streak/weight update inside `withdraw` awaits **BL-02** & **BL-03** |
| `streakOf(address user)` | `view returns (uint256)` | **Not yet implemented** | **MISSING (Blocked)** | **BL-01**, **BL-02**, **BL-09** |
| `rewardOf(address user)` | `view returns (uint256)` | **Not yet implemented** | **MISSING (Blocked)** | **BL-05**, **BL-10**, **BL-11**, **BL-13** |
| `claimReward()` | `nonpayable returns ()` (0 args) | **Not yet implemented** | **MISSING (Blocked)** | **BL-10**, **BL-11**, **BL-13** |

### 1.3 Additional Implemented Views Available for Member B / Member C

`StreakSavings.sol` now exposes the approved epoch clock views (not yet added to `apps/web/lib/contracts.ts`):
- `usdc() view returns (IERC20)`
- `totalPrincipal() view returns (uint256)`
- `epochDuration() view returns (uint64)`
- `startTime() view returns (uint64)`
- `currentEpoch() view returns (uint64)`
- `epochAt(uint256 timestamp) view returns (uint64)`
- `epochStart(uint64 epoch) view returns (uint256)`
- `epochEnd(uint64 epoch) view returns (uint256)`
- `nextEpochTimestamp() view returns (uint256)`
- `timeUntilNextEpoch() view returns (uint256)`

Member B can use `currentEpoch()` and `timeUntilNextEpoch()` / `nextEpochTimestamp()` to render the epoch countdown required by Plan v3 §16.2.

---

## 2. Critical Compatibility & Type Constraints Identified

1. **Do NOT point `apps/web` to a `StreakSavings` deployment before streak/reward methods exist:**
   - `useStreakSave()` unconditionally calls `principalOf`, `streakOf`, and `rewardOf` when `contractsConfigured` is true. On the current principal+epoch contract, `streakOf` and `rewardOf` calls would fail because those functions are intentionally withheld until BL approval.
   - Keep `NEXT_PUBLIC_STREAK_CONTRACT` unset (frontend preview mode) until streak & reward layers land.
2. **Return Type Alignment for `streakOf(address)` (`uint256` vs `uint64`):**
   - `apps/web/lib/contracts.ts` declares `streakOf(address)` returning `uint256` (while `TS-02` drafted `uint64` inside `UserInfo`).
   - **Action for Member A (once unblocked):** Either return `uint256` from `streakOf(address)` (zero impact on ABI encoding efficiency for callers, 100% compatible with `contracts.ts`), or notify Member B/C explicitly if `uint64` is used. Returning `uint256` from `streakOf(address)` is recommended to avoid unnecessary frontend ABI churn.
3. **Zero-Argument `claimReward()` Signature:**
   - `apps/web/lib/contracts.ts` and `use-streaksave.ts` call `claimReward()` with **no arguments**.
   - Under **BL-11 Option A** (Model A) or **Option D** (Model B), `claimReward()` remains zero-argument. If **BL-11 Option B** (`claimReward(uint64 epoch)` only) is chosen by the team, Member B must update `contracts.ts`, `use-streaksave.ts`, and `app/rewards/page.tsx` to supply the epoch argument.
4. **Missing Frontend Capabilities in Plan v3 MVP Flow:**
   - `addMockYield(uint256)` is required by MVP Demo Step 5 (Plan v3 §3) and is not yet in `apps/web/lib/contracts.ts` (either Member B adds a demo button / admin trigger or Member C invokes it via demo script/`cast`).
   - Effective vs. historical streak UI (`BL-09`): if `streakOf` returns stored history, Member B needs either a separate `effectiveStreakOf` / `weightOf` read or to compare `lastDepositEpoch` with `currentEpoch()` to display `"streak broken"` instead of a misleading stale streak.
5. **Event Alignment for Member B / Member C:**
   - Currently emitted events:
     - `Deposit(address indexed user, uint256 amount)`
     - `Withdraw(address indexed user, uint256 amount, uint256 principalRemaining)`
   - **Planned future change notice:** When streak & reward rules are approved, `Deposit` may gain `(uint64 indexed epoch, uint64 streak)` (per `TS-02` §10) or stay `(user, amount)` with a separate `StreakUpdated(address indexed user, uint64 oldStreak, uint64 newStreak)`. Currently `apps/web` does not parse logs directly (`waitForTransactionReceipt` only checks `receipt.status` and refetches views), so changing events only impacts indexers/scripts and will be documented in `shared/abi/`.
6. **Chain Configuration Check (`apps/web/lib/chain.ts`):**
   - `fuji.id = 43113`, RPC defaults to `https://api.avax-test.network/ext/bc/C/rpc` — matches `Deploy.s.sol` and `contracts/.env.example` cleanly.

---

## 3. Recommended Integration Sequence with Member B & C

1. Team resolves **BL-01, BL-02, BL-03, BL-10, BL-11, BL-13** (and **BL-09** for UI semantics).
2. Member A implements streak, weight, `addMockYield`, `rewardOf`, and `claimReward` in `StreakSavings.sol` and passes `T1`–`T8` + invariants.
3. Member A & C generate `shared/abi/MockUSDC.json`, `shared/abi/StreakSavings.json`, and `shared/config/contracts.ts` after authorized Fuji deployment.
4. Member B updates `apps/web/lib/contracts.ts` (or imports from `shared/`) to add epoch countdown views and any finalized `claimRewardFor` / `effectiveStreakOf` / `addMockYield` interfaces.
