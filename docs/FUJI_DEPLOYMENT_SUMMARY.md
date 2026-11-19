# Fuji Deployment Summary — public information

**Provided by Member A in `FUJI_DEPLOYMENT_RECORD.txt`.** Contract bytecode existence was subsequently confirmed by a teammate's `eth_getCode` checks. This is not proof that every configuration value or transaction flow passed.

| Field | Value |
|---|---|
| Network | Avalanche Fuji C-Chain |
| Chain ID | `43113` (`0xa869`) |
| RPC | `https://api.avax-test.network/ext/bc/C/rpc` |
| MockUSDC | `0x1aaB5693678b18753dCFD5096f497031c1A1f126` |
| StreakSavings | `0xE71Ae741c3bEe9f7F21057d825FE7dA8984406f9` |
| Deployer (expected yieldProvider) | `0x8986EC1B5E6Ca6Ceeb5ea608E8BA718b72D7Fd67` |
| Epoch duration | `60` seconds **planned; verify on-chain** |
| Token | 6 decimals **per source implementation; verify on-chain** |
| Mint to deployer | 1,000 MockUSDC according to Member A deployment record |

## Transactions provided by A
- Deploy MockUSDC: `0xb0af271c7c1e77d08a6aa113a75343de2352cc825f9ffd2b9bd1ea898d14d825`
- Mint 1,000 MockUSDC: `0x775f53f6f994dd175ddfbc9d57e4f9cec23d50aa908e4eb93a8170591cd8ff2c`
- Deploy StreakSavings: `0x745a71eb4597f50e976160835c8f8088a1867f07401c349a305ea719a40f9d05`

Explorer (use the official Fuji explorer to look up each address/hash): https://explorer-test.avax.network/c-chain

## Frontend env (public only)
File: `apps/web/.env.local` (ignored by Git). **Do not commit secrets**.
```dotenv
NEXT_PUBLIC_STREAK_CONTRACT=0xE71Ae741c3bEe9f7F21057d825FE7dA8984406f9
NEXT_PUBLIC_USDC_CONTRACT=0x1aaB5693678b18753dCFD5096f497031c1A1f126
NEXT_PUBLIC_FUJI_RPC_URL=https://api.avax-test.network/ext/bc/C/rpc
```

Actual deployment and test readiness must be confirmed from chain receipts, constructor configuration and `docs/TS-19-EVIDENCE.md`. The deployed address alone is not a test pass.
