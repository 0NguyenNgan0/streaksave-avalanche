# TS-19 â€” Fuji E2E evidence record

**Status: BLOCKED / NOT EXECUTED** (change only after running actual transactions).

## Environment and review

| Field | Actual value (fill after verification) |
|---|---|
| Date/time + timezone | TBD |
| Git integrated commit SHA | TBD |
| Frontend URL / local version | TBD |
| Network / chain ID | Avalanche Fuji / 43113 (to verify) |
| RPC / explorer | https://api.avax-test.network/ext/bc/C/rpc / https://explorer-test.avax.network/c-chain |
| MockUSDC contract + explorer | TBD |
| StreakSavings contract + explorer | TBD |
| Epoch duration (seconds) | TBD (60 proposed) |
| Yield provider public address | TBD |
| Fresh wallet U public address | TBD |
| Secondary wallet V public address (optional) | TBD |
| Tester / independent reviewer | TBD |
| Contract CI URL for exact integrated commit | TBD |
| Local ABI / typecheck / build | Reported PASS on 19 Nov 2026; paste fresh output when tested |
| Foundry locally | SKIPPED on 19 Nov 2026 (not installed in Windows PowerShell) |

## Main flow results

| Test | Status | TX hash or explorer link / screenshot | Epoch and observed values | Notes |
|---|---|---|---|---|
| E01 Connect/Fuji | NOT RUN | â€” | â€” | |
| E02 Token funding | NOT RUN | â€” | â€” | |
| E03 Approve | NOT RUN | â€” | â€” | |
| E04 Deposit | NOT RUN | â€” | â€” | |
| E05 Provider mock yield | NOT RUN | â€” | â€” | |
| E06 Finalized reward | NOT RUN | â€” | â€” | |
| E07 Claim | NOT RUN | â€” | â€” | |
| E08 Withdraw | NOT RUN | â€” | â€” | |
| E09 Reload/readback | NOT RUN | â€” | â€” | |

## Negative tests

| Test | Status | Evidence | Actual outcome / ticket |
|---|---|---|---|
| N01 | NOT RUN | â€” | â€” |
| N02 | NOT RUN | â€” | â€” |
| N03 | NOT RUN | â€” | â€” |
| N04 | NOT RUN | â€” | â€” |
| N05 | NOT RUN | â€” | â€” |
| N06 | NOT RUN | â€” | â€” |
| N07 | NOT RUN | â€” | â€” |
| N08 | NOT RUN | â€” | â€” |
| N09 | NOT RUN | â€” | â€” |
| N10 | NOT RUN | â€” | â€” |
| N11 | NOT RUN | â€” | â€” |
| N12 | NOT RUN | â€” | â€” |
| N13 | NOT RUN | â€” | â€” |
| N14 | NOT RUN | â€” | â€” |
| N15 | NOT RUN | â€” | â€” |

## Financial assertions

| Assertion | Status | Actual raw/decimal values | Evidence |
|---|---|---|---|
| principal not changed by reward claim | NOT RUN | â€” | â€” |
| totalPrincipal consistent | NOT RUN | â€” | â€” |
| balance >= totalPrincipal + totalRewardPool | NOT RUN | â€” | â€” |
| epoch snapshots and reward share consistent | NOT RUN | â€” | â€” |

## Sign-off

- [ ] Main flow E01â€“E09 verified on Fuji
- [ ] Negative suite N01â€“N15 executed and findings resolved
- [ ] No known P0/P1 blocking defects
- [ ] One fresh wallet, one authorized provider, separate reviewer
- [ ] Incognito URL verified (if deployed)
- [ ] No keys, seed phrases, or sensitive wallet data in evidence

**Final TS-19 status:** BLOCKED â€” pending deployment + on-chain transactions.
**Tester:** TBD
**Reviewer:** TBD
**Sign-off date:** TBD
