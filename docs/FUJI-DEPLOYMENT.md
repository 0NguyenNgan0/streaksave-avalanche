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
> The contract implementation is complete and locally verified (103 tests). **No Fuji deployment has been performed.** A broadcast requires:
> 1. explicit user authorization;
> 2. a dedicated, funded Fuji Dev Wallet;
> 3. `contracts/.env` populated locally (never committed);
> 4. a successful dry-run simulation.

The deployer account becomes both the `MockUSDC` minter and the immutable `StreakSavings.yieldProvider`.

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
| Deployment status | **Not deployed** (awaiting explicit authorization + funded `.env`) |
| Network | Avalanche Fuji C-Chain (`43113`) |
| MockUSDC address | _TBD after broadcast_ |
| StreakSavings address | _TBD after broadcast_ |
| Epoch duration | _Planned: 60 seconds_ |
| Yield provider | _Deployer address_ |
| Deployer address | _TBD_ |
| Transaction hashes | _TBD_ |
| Explorer links | _TBD_ |
