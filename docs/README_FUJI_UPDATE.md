# README deployment status update — instructions

The existing `README.md` on integration branch still says Fuji addresses pending. After syncing `dev` and verifying public addresses from `contracts/FUJI_DEPLOYMENT_RECORD.txt`, update the **Avalanche Fuji deployment** section of the README with:

- Network Fuji chain ID `43113`.
- MockUSDC `0x1aaB5693678b18753dCFD5096f497031c1A1f126`.
- StreakSavings `0xE71Ae741c3bEe9f7F21057d825FE7dA8984406f9`.
- Deployer/expected yield provider `0x8986EC1B5E6Ca6Ceeb5ea608E8BA718b72D7Fd67`.
- Planned 60s epoch — change to confirmed only after calling `epochDuration()`.
- 1,000 MockUSDC demo mint according to Member A record.
- Link to `docs/FUJI_DEPLOYMENT_SUMMARY.md` and `docs/TS-19-EVIDENCE.md`.
- **Fuji deployment recorded and both contract bytecodes checked; full E2E remains unverified.**
- Live Vercel URL only when confirmed publicly available.

Do NOT replace pending TS-19 status with PASS until signed evidence exists. Do NOT commit `.env.local`, keys or wallet secrets.
