# Fuji Terminal Verification — 19/11/2026

**Status:** READ-ONLY + SIMULATION CHECKS REPORTED BY OPERATOR; **NOT** full wallet/browser/signed E2E. Source: PowerShell/Node.js stdout pasted by Member B in chat, from local working tree `C:\StreakSave\apps\web` using viem and Avalanche Fuji RPC. No transaction hashes were emitted by these tests. Results are time-specific; epoch and balances may change. A/C should re-run from the repository and attach a timestamp/log for the release gate.

## Public environment

| Field | Value |
|---|---|
| Network | Avalanche Fuji C-Chain, 43113 |
| RPC | `https://api.avax-test.network/ext/bc/C/rpc` |
| MockUSDC | `0x1aaB5693678b18753dCFD5096f497031c1A1f126` |
| StreakSavings | `0xE71Ae741c3bEe9f7F21057d825FE7dA8984406f9` |
| Deployer + observed yieldProvider | `0x8986EC1B5E6Ca6Ceeb5ea608E8BA718b72D7Fd67` |
| Local integration gate | ABI compatibility PASS, TypeScript typecheck PASS, Next.js production build PASS; Foundry SKIPPED locally |

## Read-only checks — observed PASS

- Chain ID returned **43113**.
- Both MockUSDC and StreakSavings returned deployed bytecode, not `0x`.
- `StreakSavings.usdc()` matched MockUSDC contract address.
- MockUSDC `decimals() = 6`.
- `epochDuration() = 60` seconds.
- At moment of sample: `currentEpoch() = 102`, `timeUntilNextEpoch() = 42` seconds. **Not permanent values.**
- At moment of sample: `principalOf(deployer) = 0` MockUSDC, `balanceOf(deployer) = 1000` MockUSDC. **Not permanent values.**
- Output marker: `=== FUJI READ-ONLY TEST PASS ===`.

## Simulated `eth_call` transactions — observed

| Check | Result | Interpretation |
|---|---|---|
| `yieldProvider()` | Same as deployer above | Provider address confirmed on-chain |
| `allowance(deployer, StreakSavings)` | `0` | No live approval at test time |
| `approve(StreakSavings, 5 MockUSDC)` from deployer | Simulation completed | Would not revert in tested state; **did not change allowance** |
| `deposit(5 MockUSDC)` from deployer | Reverted with selector `0xfb8f41b2` | Likely allowance/`safeTransferFrom` failure; exact revert selector **not independently decoded** |
| `addMockYield(5 MockUSDC)` from `0x000000000000000000000000000000000000dEaD` | Reverted | Consistent with yieldProvider access restriction; negative test was simulated, not a signed transaction |
| Broadcast/tx hashes | **None** | No on-chain write transaction made by these tests |

**Do not mark TS-12 / TS-14 / TS-19 DONE from these results.** Browser wallet UX, state changes, signed approve/deposit/yield/claim/withdraw and negative suite N01–N15 still require tester evidence.

## Reproduction

Run from project root (read-only, no secrets):

```powershell
cd C:\StreakSave\apps\web
node .\fuji-check-cli.mjs
```

The script tests a safe subset, returns a nonzero exit on unexpected conditions, and prints no secrets.
