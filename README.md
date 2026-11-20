# StreakSave

**Save small. Keep the streak. Earn together.**

StreakSave is a behavioral-savings MVP built for **Avalanche UniHack 2026**. On Avalanche Fuji, users deposit test-only MockUSDC, build a streak by checking in once per epoch, and can claim their share of a **mock** community-yield pool. Missing an epoch changes streak eligibility; it does **not** confiscate deposited principal. This is an educational testnet demo, **not** a real-yield, audited or production savings service.

## What works, and what is pending

- Implemented: wallet connection (injected Core Wallet/MetaMask), Dashboard, Deposit, Rewards, Withdraw, Fuji network switch, USDC approval, on-chain reads/writes, transaction feedback.
- Implemented in Solidity: test token, principal accounting, configurable epoch clock, check-in streak, per-epoch weight snapshots, provider-funded mock rewards and claims.
- The frontend and shared ABI compatibility checks, TypeScript typecheck, and Next.js production build passed locally on the integration branch (reported 19 Nov 2026). Contract GitHub Actions CI reported success on the integration branch; verify the exact release SHA before final sign-off. **Those results are not a full Fuji E2E pass.**
- **Fuji deployment and read-only calls verified; signed E2E transaction evidence and a verified public frontend URL are still pending.** See [`docs/FUJI_TERMINAL_EVIDENCE_2026-11-19.md`](docs/FUJI_TERMINAL_EVIDENCE_2026-11-19.md) and [`docs/TS-19-EVIDENCE.md`](docs/TS-19-EVIDENCE.md).

## MVP flow

```text
Connect wallet on Fuji (chain ID 43113)
  -> Receive test AVAX for gas and test MockUSDC
  -> Approve MockUSDC allowance
  -> Deposit 5 MockUSDC (one streak check-in in current epoch)
  -> Authorized yieldProvider approves and adds mock yield to same epoch
  -> Epoch closes (configured 60 seconds in the intended demo)
  -> Reward becomes claimable for the latest finalized epoch
  -> Claim reward
  -> Withdraw principal without a streak-loss penalty
```

**Important:** The `addMockYield` action is provider-only; regular users do not have an operator action in the UI. A demo operator funds yield via a separate authorized transaction. Claiming an epoch before its end is not possible. Depositing again **within the same epoch does not increment the streak**. For the next streak increment, deposit in the next consecutive epoch. Completing a full withdrawal resets the streak; partial withdrawal preserves it.

## Architecture

```text
apps/web/            Next.js 16 + React 19 frontend, wagmi/viem
    app/             Dashboard, deposit, rewards, withdraw
    hooks/           Wallet contract reads and transaction actions
    lib/abi/         Frontend ABI copies used at build time
contracts/           Foundry / Solidity 0.8.24
    src/MockUSDC.sol        6-decimal ERC-20 demo token
    src/StreakSavings.sol   Principal + epoch/streak + reward accounting
    src/libraries/          Pure accounting helpers
    test/             Foundry unit and invariant tests
    script/Deploy.s.sol    Deployment and verification
shared/abi/          Canonical ABIs shared across team
scripts/             ABI and integration checks
 docs/               Architecture, Fuji deployment, QA, demo
```

The business contract records `principalOf(user)` separately from reward liabilities (`totalRewardPool`). Weight for a finalized epoch is based on its end-of-epoch snapshot, without iterating over all users. `rewardOf(user)` and zero-argument `claimReward()` cover **only the latest finalized epoch**; older unclaimed epochs are accessible with `rewardInEpoch(user, epoch)` and `claimRewardFor(epoch)` on the contract, not through an all-history UI.

For implementation details see [`docs/SMART-CONTRACT-ARCHITECTURE.md`](docs/SMART-CONTRACT-ARCHITECTURE.md) and [`docs/MEMBER-A-TECHNICAL-DECISIONS.md`](docs/MEMBER-A-TECHNICAL-DECISIONS.md).

## Requirements

- Node.js **22** and npm (matches the contract CI setup).
- Core Wallet or MetaMask with access to Avalanche Fuji.
- Test AVAX for gas, and MockUSDC issued by the authorized deployer/minter.
- Foundry (`forge`, `cast`) only for contract development/testing/deployment. On Windows, use a Foundry-compatible shell or rely on the GitHub contract workflow for contract tests when Foundry is unavailable locally.

## Run the frontend locally

From the repo root in PowerShell:

```powershell
cd C:\StreakSave\apps\web
npm ci
Copy-Item .env.example .env.local
```

Populate **only public addresses** in `apps/web/.env.local` **after Fuji deployment**:

```dotenv
NEXT_PUBLIC_STREAK_CONTRACT=0xE71Ae741c3bEe9f7F21057d825FE7dA8984406f9
NEXT_PUBLIC_USDC_CONTRACT=0x1aaB5693678b18753dCFD5096f497031c1A1f126
NEXT_PUBLIC_FUJI_RPC_URL=https://api.avax-test.network/ext/bc/C/rpc
```

These are public Fuji testnet addresses. Never put private keys or recovery phrases in `NEXT_PUBLIC_*` variables. Run:

```powershell
npm run dev
# open http://localhost:3000
```

The UI can render without addresses as a non-transactional preview; a successful build alone does not prove that deployed contracts are reachable.

## Build and test

From the repo root:

```powershell
node .\scripts\check-abi-compat.mjs
cd apps\web
node .\scripts\check-abi.mjs
npm run typecheck
npm run build
```

The project also has a combined local checker:

```powershell
cd C:\StreakSave
powershell -ExecutionPolicy Bypass -File .\scripts\check-integration.ps1
```

This requires a clean Git working tree at startup and skips Foundry if `forge` is not installed. Next.js may regenerate `apps/web/next-env.d.ts`; inspect it before restoring generated changes rather than discarding unrelated edits.

Foundry checks, in an environment with Foundry and contract dependencies installed:

```bash
cd contracts
npm ci
forge fmt --check
forge build --sizes
forge test -vvv
```

See [`.github/workflows/contracts.yml`](.github/workflows/contracts.yml) for CI. Local ABI/build passes and contract CI passes on another commit do not replace full E2E verification for the integrated/deployed commit.

## Avalanche Fuji deployment (owner: Member A)

- **Network:** Avalanche Fuji C-Chain, chain ID `43113`.
- **RPC:** `https://api.avax-test.network/ext/bc/C/rpc`.
- **Explorer:** https://explorer-test.avax.network/c-chain
- **Observed on Fuji (19 Nov 2026):** `epochDuration() = 60` seconds, MockUSDC `decimals() = 6`, `usdc()` links to MockUSDC, and both contracts have bytecode (read-only checks).
- **StreakSavings:** `0xE71Ae741c3bEe9f7F21057d825FE7dA8984406f9`.
- **MockUSDC:** `0x1aaB5693678b18753dCFD5096f497031c1A1f126`.
- **Deployer / confirmed `yieldProvider()`:** `0x8986EC1B5E6Ca6Ceeb5ea608E8BA718b72D7Fd67`.
- **Initial mint:** 1,000 test MockUSDC according to the deployment record; read-only balance at deployer was 1,000 at test time.
- **Live frontend URL:** **NOT YET VERIFIED**.

Deployment hashes: [`contracts/FUJI_DEPLOYMENT_RECORD.txt`](contracts/FUJI_DEPLOYMENT_RECORD.txt). CLI evidence: [`docs/FUJI_TERMINAL_EVIDENCE_2026-11-19.md`](docs/FUJI_TERMINAL_EVIDENCE_2026-11-19.md). **No signed Fuji end-to-end user transaction flow has been verified.** Never put private keys or recovery phrases in the repository.

## TS-19: Fresh wallet E2E and QA

Follow the executable testing protocol in [`docs/TS-19-FRESH-WALLET-QA.md`](docs/TS-19-FRESH-WALLET-QA.md). Record verified chain, contracts, account roles, observed balances, transaction hashes, negative tests and reviewer sign-off in [`docs/TS-19-EVIDENCE.md`](docs/TS-19-EVIDENCE.md). Optional local preflight: `powershell -ExecutionPolicy Bypass -File .\scripts\ts19-preflight.ps1`.

**Definition of done:** fresh wallet can complete Connect â†’ fund test token â†’ Approve â†’ Deposit â†’ mock yield funded by authorized provider â†’ finalized reward â†’ Claim â†’ Withdraw, and edge cases (reject, insufficient balance, repeated action, streak reset, principal accounting) are verified. Git/ABI/build checks alone are **not** E2E.

## Responsible scope and security

- MockUSDC and mock yield have **no real economic value**. No real USDC, fixed APY, or audited DeFi yield is claimed.
- This MVP is not production-grade or independently audited. Production roadmap might evaluate external lending integrations only after security review.
- Never commit `.env`, `.env.local`, private keys, seed phrases, or wallet credentials. Use dedicated Fuji-only test wallets.
- Contract principal is modeled without a streak-loss fee; this does not guarantee protection from smart-contract, token or testnet operational risks.
- Bonus features (NFT badge, Privy, Aave/Benqi, shared streak) are out of the mandatory working-demo scope.

## Submission and other docs

- [Integration runbook](docs/INTEGRATION_RUNBOOK.md)
- [QA checklist](docs/QA_CHECKLIST.md)
- [Demo script](docs/DEMO_SCRIPT.md)
- [Submission checklist](docs/SUBMISSION_CHECKLIST.md)
- [Contract security review](docs/SMART-CONTRACT-SECURITY-REVIEW.md)

**Team Dimple Â· Avalanche UniHack 2026**
