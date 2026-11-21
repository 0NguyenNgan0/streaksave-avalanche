# TS-19 — Fuji E2E evidence reconciliation (21 Nov 2026)

**Status: PARTIALLY REPORTED PASS; FULL TS-19 SIGN-OFF PENDING.**

This file reconciles the earlier `NOT RUN` template with [`QA_REPORT.md`](QA_REPORT.md), which now reports tests executed by Member C on 21 Nov 2026. It is **not** a new independent test run. Do not interpret the reported test counts as proof that the entire E01–E09 / N01–N15 matrix was executed.

## Environment (per QA_REPORT.md)

| Field | Value / source status |
|---|---|
| Test date | 21 Nov 2026 |
| QA lead | Lương Thị Thu Huyền |
| Branch | `dev` (exact tested SHA not recorded in QA report) |
| Frontend | `http://localhost:3000` (local only) |
| Network | Avalanche Fuji, chain ID 43113 |
| Wallet | Core Wallet; address redacted in report as `0x53F0...D574` |
| MockUSDC | `0x1aaB5693678b18753dCFD5096f497031c1A1f126` |
| StreakSavings | `0xE71Ae741c3bEe9f7F21057d825FE7dA8984406f9` |
| Contract configuration | Public RPC/ABI verified separately in [`FUJI_TERMINAL_EVIDENCE_2026-11-19.md`](FUJI_TERMINAL_EVIDENCE_2026-11-19.md) |
| Transaction hashes / transaction receipts | Not included in QA_REPORT.md; **pending** |
| Independent reviewer / final sign-off | Not recorded; **pending** |

## Cases reported by C (not independently re-executed here)

| QA case | Reported result | Observed notes in QA_REPORT.md | Missing release evidence |
|---|---|---|---|
| TC-01 Wallet/Fuji | PASS (reported) | Connected to Fuji; read state | Wallet/browser screenshot or reviewer evidence |
| TC-02 Approve | PASS (reported) | 5 MockUSDC allowance flow | Approval TX hash and receipt |
| TC-03 Deposit | PASS (reported) | Wallet balance 66 → 61 after 5 deposit | Deposit TX hash; principal/streak readback |
| TC-04 Claim + Withdraw | PASS (reported) | Successful flow described | Claim/withdraw TX hashes; reward and principal assertions |
| EC-01 Double action | PASS (reported) | Approve button blocks repeated clicks | Screenshot or recording |
| EC-02 Reject tx | PASS (reported) | User rejection handled; balance unchanged | Screenshot or log |
| EC-03 Insufficient balance | PASS (reported) | Entering 100 when wallet has 66 disables action | Screenshot or log |
| EC-04 Streak reset | PASS (reported) | Epoch 1625 → 1626, displayed streak 1 → 0 | On-chain streak/principal confirmation |

**Reported totals:** 4/4 functional test cases + 4/4 edge cases PASS; 0 blocking/critical bugs **reported**. This does not automatically cover provider `addMockYield`, specific historical reward epochs, exact principal conservation, the complete 9-step protocol, or all 15 negative scenarios.

## Broader TS-19 acceptance matrix

| Required check | Status as of this reconciliation |
|---|---|
| Wallet connection on Fuji | Reported PASS — TC-01 |
| Test-token funding | Not individually evidenced |
| Signed Approve | Reported PASS — TC-02; hash pending |
| Signed Deposit | Reported PASS — TC-03; hash pending |
| Authorized mock yield injection in same epoch | Not individually evidenced |
| Finalized-epoch reward readback | Not individually evidenced |
| Signed Claim | Reported PASS in TC-04; hash pending |
| Signed Withdraw | Reported PASS in TC-04; hash pending |
| Reload/reconnect state consistency | Not individually evidenced |
| 15 negative/edge scenarios from TS-19 protocol | Four categories reported PASS; full matrix incomplete |
| Accounting invariants | Not independently evidenced |
| Independent reviewer approval | Pending |
| Public deployment / Incognito | Pending |

## Evidence completion for Member C / A

- [ ] Add **public** Fuji transaction hash links for approval, deposit, provider yield, claim, and withdrawal, matching the wallet and epoch used.
- [ ] Record finalized epoch, reward calculation, and principal before/after claim and withdrawal; verify financial invariants.
- [ ] Attach relevant screenshots/video or link to team-approved demo evidence; exclude secrets and unrelated private data.
- [ ] Mark each unexecuted protocol case as NOT RUN / OUT OF SCOPE explicitly rather than treating 8 reported passes as 24 passes.
- [ ] Have a separate teammate review and sign off on release-readiness.

**Final TS-19 sign-off:** PENDING evidence and reviewer acceptance. The QA report is valid as a statement of the tester's observed outcomes, but this document does not independently verify them.
