# Avalanche Fuji Deployment Guide & Checklist

**Target Network:** Avalanche Fuji C-Chain  
**Chain ID:** `43113`  
**Explorer:** `https://explorer-test.avax.network/c-chain` (also compatible with Snowtrace testnet verification)  
**Default RPC:** `https://api.avax-test.network/ext/bc/C/rpc`  
**Deployment Script:** [`contracts/script/Deploy.s.sol`](../contracts/script/Deploy.s.sol)  
**Environment Template:** [`contracts/.env.example`](../contracts/.env.example)

---

## 1. Current Deployment Gate Status

> [!WARNING]
> **DO NOT DEPLOY THE CURRENT CONTRACT AS THE FINAL MVP SUBMISSION YET.**
> `StreakSavings.sol` currently implements **principal accounting and the epoch clock only**. Streak tracking, weight accounting, `addMockYield`, `rewardOf`, and `claimReward` are blocked until **BL-01, BL-02, BL-03, BL-10, BL-11, and BL-13** are approved by the team (`docs/MEMBER-A-TECHNICAL-DECISIONS.md`).
>
> Furthermore, actual Fuji broadcast requires explicit user authorization plus a funded Dev Wallet private key in `contracts/.env` (untracked by Git).

---

## 2. Pre-Flight Checklist

Before executing any broadcast to Avalanche Fuji:

1. **Business Logic & Code Gate:**
   - [ ] Team approves BL-01, BL-02, BL-03, BL-10, BL-11, BL-13 (or user explicitly authorizes deploying the current principal+epoch milestone for smoke testing).
   - [ ] `forge fmt --check`, `forge build --sizes`, and `forge test -vvv` pass with zero failures/skips.
2. **Wallet & Secret Hygiene:**
   - [ ] Generate or select a **dedicated Fuji Dev Wallet** (zero mainnet assets).
   - [ ] Fund the Dev Wallet with test AVAX via the Avalanche Fuji faucet for gas.
   - [ ] Copy `contracts/.env.example` to `contracts/.env`.
   - [ ] Set `DEPLOYER_PRIVATE_KEY=0x...` in `contracts/.env`.
   - [ ] Verify `git status` shows `.env` is ignored and never staged.
   - [ ] Never pass `--private-key` on shared terminal history or commit keys.
3. **Constructor Parameters:**
   - [ ] `EPOCH_DURATION=60` for the 2–3 minute Fuji hackathon demo (or `604800` for 7-day production concept).
   - [ ] `INITIAL_DEMO_MINT=1000000000` (1,000 MockUSDC with 6 decimals) minted to the deployer, or `0` to mint later.
   - [ ] `MOCK_USDC_ADDRESS=` left empty to deploy a fresh `MockUSDC`, or set to an existing `MockUSDC` address.
   - [ ] `ALLOW_LOCAL_CHAIN=false` on Fuji.

---

## 3. Dry-Run Simulation (No Broadcast)

Run a read-only simulation against Fuji RPC before sending transactions:

```powershell
cd contracts
Get-Content .env | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim()) }
}
forge script script/Deploy.s.sol:Deploy --rpc-url $env:FUJI_RPC_URL -vvvv
```

Verify the simulation logs show:
- `Chain ID: 43113`
- Expected `Deployer` address (never print the private key)
- `Epoch Duration: 60`
- Zero verification reverts inside `_verifyDeployment(...)`.

---

## 4. Broadcast Deployment to Avalanche Fuji

Only after explicit authorization and successful dry-run simulation:

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

*(If explorer verification times out during hackathon traffic, deploy with `--broadcast` first and verify separately with `forge verify-contract`.)*

---

## 5. Post-Deployment Verification & Smoke Tests

`Deploy.s.sol` automatically verifies on-chain during execution that:
- `MockUSDC` and `StreakSavings` have deployed bytecode (`code.length > 0`).
- `MockUSDC.decimals() == 6`.
- When deploying fresh `MockUSDC`, `MockUSDC.minter() == deployer` and `MockUSDC.totalSupply() == INITIAL_DEMO_MINT`.
- `StreakSavings.usdc() == MockUSDC`, `StreakSavings.epochDuration() == EPOCH_DURATION`, `StreakSavings.totalPrincipal() == 0`, `StreakSavings.currentEpoch() == 0`.

Additional manual `cast` verification after broadcast:

```powershell
# Verify bytecode & metadata on Fuji
cast code <MOCK_USDC_ADDRESS> --rpc-url https://api.avax-test.network/ext/bc/C/rpc
cast call <MOCK_USDC_ADDRESS> "decimals()(uint8)" --rpc-url https://api.avax-test.network/ext/bc/C/rpc
cast call <MOCK_USDC_ADDRESS> "minter()(address)" --rpc-url https://api.avax-test.network/ext/bc/C/rpc

cast code <STREAK_SAVINGS_ADDRESS> --rpc-url https://api.avax-test.network/ext/bc/C/rpc
cast call <STREAK_SAVINGS_ADDRESS> "usdc()(address)" --rpc-url https://api.avax-test.network/ext/bc/C/rpc
cast call <STREAK_SAVINGS_ADDRESS> "epochDuration()(uint64)" --rpc-url https://api.avax-test.network/ext/bc/C/rpc
cast call <STREAK_SAVINGS_ADDRESS> "currentEpoch()(uint64)" --rpc-url https://api.avax-test.network/ext/bc/C/rpc
```

---

## 6. ABI Export Procedure (Coordinate with Member C)

When contracts are finalized for shared integration, export clean ABIs from Foundry output (`contracts/out/`):

```powershell
cd contracts
forge inspect MockUSDC abi --json > ../shared/abi/MockUSDC.json
forge inspect StreakSavings abi --json > ../shared/abi/StreakSavings.json
```

Coordinate placement into `shared/abi/` and `shared/config/contracts.ts` with Member C (do not overwrite Member B's `apps/web/lib/contracts.ts` without agreement).

---

## 7. Deployment Record (Not Yet Deployed)

| Field | Value |
|---|---|
| **Deployment Status** | **Not deployed** (awaiting BL decisions & user authorization + funded `.env`) |
| **Network** | Avalanche Fuji C-Chain (`43113`) |
| **MockUSDC Address** | _TBD after actual broadcast_ |
| **StreakSavings Address** | _TBD after actual broadcast_ |
| **Epoch Duration** | _Planned: `60` seconds for Fuji demo_ |
| **Deployer Address** | _TBD_ |
| **Deployment Tx Hashes** | _TBD after actual broadcast_ |
| **Explorer Links** | _TBD after actual broadcast_ |
