# Avalanche Fuji Deployment Guide & Checklist

**Target Network:** Avalanche Fuji C-Chain  
**Chain ID:** `43113`  
**Explorer:** `https://explorer-test.avax.network/c-chain`  
**Default RPC:** `https://api.avax-test.network/ext/bc/C/rpc`  
**Deployment Script:** [`contracts/script/Deploy.s.sol`](../contracts/script/Deploy.s.sol)  
**Environment Template:** [`contracts/.env.example`](../contracts/.env.example)

---

## 1. Gate Status

> [!IMPORTANT]
> The contract implementation is complete and locally verified (103 tests). **No Fuji deployment has been performed.** On 19/11/2026 the Fuji dry run passed, but the real broadcast is **BLOCKED** because `contracts/.env` / `DEPLOYER_PRIVATE_KEY` are absent and no funded deployer wallet is configured in this environment. A broadcast requires:
> 1. explicit user authorization;
> 2. a dedicated, funded Fuji Dev Wallet;
> 3. `contracts/.env` populated locally (never committed);
> 4. a successful dry-run simulation.

The deployer account becomes both the `MockUSDC` minter and the immutable `StreakSavings.yieldProvider`.

### 1.1 Readiness audit — 19/11/2026

| Check | Result |
|---|---|
| Source branch | `feature/principal-accounting` |
| Member A contract commit | `b6055f2` |
| Integration copy | `origin/feature/member-c-integration` contains `b6055f2`; contract sources and both ABIs are byte-identical |
| `dev` / `main` | Still at `8ac875c`; contracts are not merged into `dev` or `main` |
| PR | PR #1 head is `b6055f2`; not merged |
| Fuji RPC | Reachable at `https://api.avax-test.network/ext/bc/C/rpc` |
| Fuji chain ID | Verified `43113` |
| Dry run | **Passed** with a public, unfunded test key; no broadcast |
| Dry-run parameters | `EPOCH_DURATION=60`, `INITIAL_DEMO_MINT=1,000,000,000` (1,000 USDC), fresh MockUSDC |
| Deployer credentials | **Missing** — no `contracts/.env`, no `DEPLOYER_PRIVATE_KEY` in the environment |
| Funded wallet | **Not configured**; wallet balance cannot be checked without an address |
| Broadcast | **Not executed** |

The dry-run addresses are simulation-only and are not deployment records. Do not use them in the frontend.

### 1.2 Unblock checklist

1. Create a dedicated Fuji Dev Wallet and fund it from the Avalanche Fuji faucet.
2. Copy `contracts/.env.example` to `contracts/.env` locally.
3. Set `DEPLOYER_PRIVATE_KEY`, `FUJI_RPC_URL`, `EPOCH_DURATION=60`, `INITIAL_DEMO_MINT=1000000000`, and leave `MOCK_USDC_ADDRESS` empty.
4. Never print, commit, or share the private key.
5. Confirm the wallet balance with `cast balance <deployer-address> --rpc-url $env:FUJI_RPC_URL`.
6. Re-run the dry run, then obtain explicit owner authorization before adding `--broadcast`.

---

## 2. Pre-Flight Checklist

1. **Code gate**
   - [ ] `forge fmt --check` passes.
   - [ ] `forge build --sizes` passes.
   - [ ] `forge test -vvv` passes with zero failures/skips.
2. **Wallet and secret hygiene**
   - [ ] Dedicated Fuji Dev Wallet with no mainnet assets.
   - [ ] Funded with test AVAX for gas.
   - [ ] `contracts/.env` copied from `.env.example` and populated.
   - [ ] `git status` confirms `.env` is ignored and unstaged.
   - [ ] Never pass `--private-key` in shared shell history.
3. **Configuration**
   - [ ] `EPOCH_DURATION=60` for the demo (or `604800` for the production concept).
   - [ ] `INITIAL_DEMO_MINT=1000000000` (1,000 MockUSDC in 6-decimal units) or `0`.
   - [ ] `MOCK_USDC_ADDRESS=` empty to deploy a fresh token.
   - [ ] `ALLOW_LOCAL_CHAIN=false` for Fuji.

---

## 3. Dry-Run Simulation (No Broadcast)

```powershell
cd contracts
Get-Content .env | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') {
    [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())
  }
}
forge script script/Deploy.s.sol:Deploy --rpc-url $env:FUJI_RPC_URL -vvvv
```

Expected:
- `Chain ID: 43113`
- expected deployer address (never the private key)
- `Epoch Duration: 60`
- zero `_verifyDeployment(...)` reverts

---

## 4. Broadcast Deployment

Only after explicit authorization and a clean dry run:

```powershell
cd contracts
forge script script/Deploy.s.sol:Deploy `
  --rpc-url $env:FUJI_RPC_URL `
  --broadcast `
  --verify `
  --verifier-url "https://api.routescan.io/v2/network/testnet/evm/43113/etherscan" `
  --etherscan-api-key $env:SNOWTRACE_API_KEY `
  -vvvv
```

If explorer verification times out, deploy with `--broadcast` and verify separately with `forge verify-contract`.

---

## 5. Post-Deployment Verification

`Deploy.s.sol` verifies on-chain:
- Both contracts have bytecode.
- `MockUSDC.decimals() == 6`.
- Fresh token: `minter() == deployer`, `totalSupply() == INITIAL_DEMO_MINT`.
- `StreakSavings.usdc()`, `epochDuration()`, `totalPrincipal() == 0`, `totalWeight() == 0`, `totalRewardPool() == 0`.
- `StreakSavings.yieldProvider() == deployer`.
- `currentEpoch() == 0`.

Manual checks:

```powershell
cast code <MOCK_USDC_ADDRESS> --rpc-url https://api.avax-test.network/ext/bc/C/rpc
cast call <MOCK_USDC_ADDRESS> "decimals()(uint8)" --rpc-url https://api.avax-test.network/ext/bc/C/rpc
cast call <MOCK_USDC_ADDRESS> "minter()(address)" --rpc-url https://api.avax-test.network/ext/bc/C/rpc
cast call <STREAK_SAVINGS_ADDRESS> "yieldProvider()(address)" --rpc-url https://api.avax-test.network/ext/bc/C/rpc
cast call <STREAK_SAVINGS_ADDRESS> "currentEpoch()(uint64)" --rpc-url https://api.avax-test.network/ext/bc/C/rpc
cast call <STREAK_SAVINGS_ADDRESS> "timeUntilNextEpoch()(uint256)" --rpc-url https://api.avax-test.network/ext/bc/C/rpc
```

---

## 6. Demo Funding Flow (Mock Yield)

`addMockYield` is restricted to `yieldProvider` (the deployer). Before calling it:

```powershell
# 1. Approve StreakSavings to pull mock USDC from the provider
cast send <MOCK_USDC_ADDRESS> "approve(address,uint256)" <STREAK_SAVINGS_ADDRESS> 1000000000 `
  --rpc-url $env:FUJI_RPC_URL --private-key $env:DEPLOYER_PRIVATE_KEY

# 2. Fund the current epoch (requires at least one checked-in user)
cast send <STREAK_SAVINGS_ADDRESS> "addMockYield(uint256)" 5000000 `
  --rpc-url $env:FUJI_RPC_URL --private-key $env:DEPLOYER_PRIVATE_KEY
```

Never commit `DEPLOYER_PRIVATE_KEY` or paste it into frontend environment variables.

---

## 7. ABI Export (Coordinate with Member C)

```powershell
cd contracts
forge inspect MockUSDC abi --json > ../shared/abi/MockUSDC.json
forge inspect StreakSavings abi --json > ../shared/abi/StreakSavings.json
```

Coordinate `shared/abi/` and `shared/config/contracts.ts` with Member C. Do not overwrite Member B's `apps/web/lib/contracts.ts` without agreement.

---

## 8. Deployment Record

| Field | Value |
|---|---|
| Deployment status | **Blocked — no local deployer credentials (19/11/2026)** |
| Approved contract source | `b6055f2` (`feature/principal-accounting`; identical copy in `feature/member-c-integration`) |
| Network | Avalanche Fuji C-Chain (`43113`) |
| MockUSDC address | _TBD after broadcast_ |
| StreakSavings address | _TBD after broadcast_ |
| Epoch duration | _Planned: 60 seconds_ |
| Yield provider | _Deployer address_ |
| Deployer address | _TBD_ |
| Transaction hashes | _TBD_ |
| Explorer links | _TBD_ |
| Dry run | Passed 19/11/2026; no transactions sent |
