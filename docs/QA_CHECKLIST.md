# StreakSave Code Freeze — QA evidence checklist (19 Nov 2026)

The checked items below MUST be verified against the integrated commit, not inherited from a different branch's CI run.

## Automated gates
- [ ] `node scripts/check-abi-compat.mjs` PASS
- [ ] `cd apps/web; node scripts/check-abi.mjs` PASS
- [ ] `cd apps/web; npm ci; npm run typecheck; npm run build` PASS
- [ ] `cd contracts; forge fmt --check; forge build --sizes; forge test -vvv` PASS (or successful CI for the EXACT integrated commit)
- [ ] `git status --porcelain` empty before PR
- [ ] No secrets in tracked files and Git history (rotate any exposed key)

## Frontend guardrails
- [ ] Dashboard no longer presents fake balances or fake completed milestones
- [ ] Wallet on wrong chain cannot approve/deposit/claim/withdraw
- [ ] Contract addresses pass validity checks; addresses not zero
- [ ] Amount zero, invalid decimal, >6 decimal places, and over-balance denied
- [ ] Duplicate button clicks do not submit duplicate transaction
- [ ] Approve waits for confirmation and allowance refresh before Deposit
- [ ] Successful on-chain transaction not reported as failed solely because of refetch failure
- [ ] User-rejected wallet action displays error and action becomes available again
- [ ] Transaction hash links to Fuji explorer
- [ ] Wallet disconnect and account switch update UI correctly
- [ ] Responsive at 390px and 320px; no hidden essential buttons

## Contract / full Fuji E2E
- [ ] Only yieldProvider can add mock yield
- [ ] Same-epoch extra deposit does not increment streak
- [ ] Next-epoch deposit increments streak; missed epoch resets effective streak
- [ ] Reward unavailable before epoch close, available after closure
- [ ] Claim once succeeds; second claim does not transfer rewards
- [ ] Partial withdraw preserves streak; full withdraw resets streak
- [ ] Principal is never spent for reward claims
- [ ] Fresh wallet flow (Connect -> faucet/mint -> Approve -> Deposit -> mock yield -> epoch close -> Claim -> Withdraw)
- [ ] Live Vercel smoke test and incognito access

## Evidence (do not fabricate)
```text
Integrated commit:
Contracts CI run URL:
MockUSDC address:
StreakSavings address:
Epoch duration:
Yield provider:
Approve tx:
Deposit tx:
Mock yield tx:
Claim tx:
Withdraw tx:
Vercel URL:
Reviewer:
Date:
Result:
```
