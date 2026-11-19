# StreakSave — Main release gate (19 Nov 2026)

## Current truth
- `main` is still initial starter (`8ac875c` at time of kit creation).
- `dev` now has new Member A deployment record and ABI export (`8845de0`), which the integration branch (`5f49cc1`) must merge.
- Member C's local ABI/typecheck/build gates passed before this new upstream sync.
- Contract bytecode presence verified by user through Fuji RPC; **no full successful wallet E2E recorded**.
- Last browser wallet-connect attempt could not proceed because EVM wallet extension was not detected (`window.ethereum === undefined`). Assign wallet-equipped tester.

## Gates and responsibility
| Gate | Owner | Requirement | Status at kit creation |
|---|---|---|---|
| G0 Latest dev synced | C | integration contains `8845de0` and diff reviewed | PENDING |
| G1 Code quality | B/C | ABI checks, frontend typecheck + production build green on final integrated SHA | needs re-run after sync |
| G2 Contract quality | A | Foundry CI green against final merged commit / same deployment ABI | needs final SHA evidence |
| G3 Fuji config | A/C | chain ID=43113, 2 bytecodes, linked usdc(), 6 decimals, correct provider and 60s duration, receipts | bytecode only confirmed |
| G4 Fresh-wallet E2E | B/C tester | E01–E09 TX hashes and N01–N15 QA evidence | NOT RUN |
| G5 Release / links | C | clean repo, no secrets, README updated with verified contracts, live app smoke, incognito access | PENDING |

**Recommendation:** Prepare release PR now but leave it open until G0–G5 are verified. If the team merges before E2E by conscious decision, label release `UNVERIFIED E2E` and do not claim the MVP demo is complete.

## Safe Git procedure (user can execute in VS Code; assistant has read-only GitHub access)

```powershell
cd C:\StreakSave
git status --short                  # MUST be empty before merge
git fetch origin
git branch backup/integration-before-release
git -c core.editor=true merge --no-ff --no-edit origin/dev
# Stop and inspect if conflict; do not force reset.
git merge-base --is-ancestor origin/dev HEAD
$LASTEXITCODE                      # 0 = dev merged into integration
node .\scripts\check-abi-compat.mjs
cd apps\web
npm ci
npm run typecheck
npm run build
cd ..\..
git status --short                  # Next.js may rewrite apps/web/next-env.d.ts; inspect diff before restore
```

Then run `scripts/verify-fuji-readonly.ps1`, and use original `scripts/check-integration.ps1` when the tree is clean. Ensure CI checks pass and tester fills evidence. Commit handoff docs and updated README with verified Fuji addresses, push `feature/member-c-integration`, create a PR to `dev`. Once tested on `dev`, create PR from `dev` to `main` and merge via GitHub interface with approvals/branch protection. **Do not force-push main.**

If the team explicitly chooses immediate main merge without full QA, mark the QA evidence `NOT RUN` and document risk, rather than asserting PASS. No tag `v1.0-unihack` until the demo gate is green.
