# Fuji Deployment Verification Report

## 1. Network

- Network: Avalanche Fuji Testnet
- Chain ID: 43113
- RPC: https://api.avax-test.network/ext/bc/C/rpc
- Verification date: 2026-11-19
- Environment: Testnet only

## 2. Deployed Contracts

| Contract | Address |
|---|---|
| MockUSDC | `0x1aaB5693678b18753dCFD5096f497031c1A1f126` |
| StreakSavings | `0xE71Ae741c3bEe9f7F21057d825FE7dA8984406f9` |

Deployer / Yield Provider:

`0x8986EC1B5E6Ca6Ceeb5ea608E8BA718b72D7Fd67`

## 3. Deployment Transactions

| Operation | Transaction Hash |
|---|---|
| Deploy MockUSDC | `0xb0af271c7c1e77d08a6aa113a75343de2352cc825f9ffd2b9bd1ea898d14d825` |
| Mint initial MockUSDC | `0x775f53f6f994dd175ddfbc9d57e4f9cec23d50aa908e4eb93a8170591cd8ff2c` |
| Deploy StreakSavings | `0x745a71eb4597f50e976160835c8f8088a1867f07401c349a305ea719a40f9d05` |

Deployment block: `61334056`

## 4. On-chain Verification

RPC read checks executed on 2026-11-19:

| Function | Observed Result | Status |
|---|---|---|
| MockUSDC `decimals()` | 6 | PASS |
| MockUSDC `balanceOf(deployer)` | 1000000000 (1,000 MockUSDC) | PASS |
| StreakSavings `epochDuration()` | 60 seconds | PASS |
| StreakSavings `yieldProvider()` | `0x8986EC1B5E6Ca6Ceeb5ea608E8BA718b72D7Fd67` | PASS |

Both contracts also have non-empty deployed bytecode.

## 5. Explorer Source Verification

- Explorer: https://build.avax.network/explorer/fuji/c-chain
- Compiler version: `0.8.24+commit.e11b9ed9`
- Optimizer: Enabled
- Optimizer runs: 200

| Contract | Verification Status | Explorer Link |
|---|---|---|
| MockUSDC | Verified | https://build.avax.network/explorer/fuji/c-chain/verify/0x1aab5693678b18753dcfd5096f497031c1a1f126 |
| StreakSavings | Verified | https://build.avax.network/explorer/fuji/c-chain/verify/0xe71ae741c3bee9f7f21057d825fe7da8984406f9 |

Both contract source codes have been successfully verified on Avalanche Fuji Explorer.

## 6. Test Results

- Foundry tests: 104 passed
- Failed: 0
- Skipped: 0
- Invariant testing: 128 runs, 4,096 calls each, 0 reverts

## 7. Limitations

- Deployed on Avalanche Fuji Testnet only.
- MockUSDC is a test token, not real USDC.
- No third-party security audit is claimed.
- Frontend end-to-end integration and team QA are pending.

## 8. Overall Status

- [x] Contracts deployed to Fuji
- [x] Contract bytecode verified on-chain
- [x] Initial MockUSDC mint verified
- [x] Contract configuration verified
- [x] MockUSDC Explorer source-code verification
- [x] StreakSavings Explorer source-code verification
- [ ] Frontend end-to-end testing
- [ ] Team QA sign-off