# Security / Access / Dependency Review — 21 Nov 2026

**Scope:** Operator-provided PowerShell and `gh` CLI output, plus `docs/TS20_TS23_HANDOFF.md`. No independent complete Git history or production deployment audit performed. Owner for final approval: Member C / repository admin.

## GitHub access and protection

- Repository `0NguyenNgan0/streaksave-avalanche`: **PUBLIC**, default branch `main`.
- GitHub CLI authenticated as repository admin `0NguyenNgan0`.
- Collaborators returned by GitHub API: `0NguyenNgan0` (admin), `trong256` (write), `icyyth` (write). Team should confirm the latter two identities and expected permissions.
- `main` branch protection API returned: required PR approvals = **1**, `require_last_push_approval=true`, force pushes disabled, deletions disabled, admin enforcement **false**.
- `dev` was reported unprotected at the time checked; convenient for integration but exposes direct-push risk.

## Current-tree scan and handling of findings

- Local `git status --short` clean on `dev` commit `1f989ed`.
- `git ls-files "*env*" "*.pem" "*.key"` showed `apps/web/.env.example`, `apps/web/next-env.d.ts`, `contracts/.env.example`; neither `apps/web/.env.local` nor a tracked `.key`/`.pem` was returned.
- Heuristic scan of 147 tracked files identified **3 review flags**: the two `.env.example` sample files and a Foundry `forge-std` test mnemonic. Manual inspection found the example deployer key empty; the library mnemonic was a public test fixture. **Those 3 flags are classified as expected samples, not exposed team credentials.** This is not a guarantee about other secrets or Git history.

## npm production dependency advisories (OPEN)

`npm audit --omit=dev` reported **27 vulnerability findings: 16 high, 11 moderate** in the installed dependency tree. Distinct packages highlighted include `decode-uri-component`, `ws`, `zod`, `uuid`, with many transitive dependents (WalletConnect, wagmi, MetaMask, Reown). Advisory exposure depends on whether vulnerable paths are reachable.

- No dependency updates or automatic fixes were committed.
- `npm audit fix --dry-run` failed at dependency resolution (`ERESOLVE`, `wagmi@2.0.0` against React Query peer requirement).
- Actual lockfile and installed direct package versions matched: wagmi 2.19.5, viem 2.57.19, @tanstack/react-query 5.107.1.
- Code build/typecheck PASS does **not** resolve security findings.

## Before any public release

- [ ] Scan full Git history with trusted tools, review all findings without publishing secret values.
- [ ] Confirm active collaborator permissions, branch protection behavior and no unintended admin bypass.
- [ ] Document owner-approved disposition for 27 advisories; if fixing, do so on separate branch with ABI/typecheck/build and real wallet smoke regression.
- [ ] Verify deploy settings and Vercel environment contain **only public data** in `NEXT_PUBLIC_*`, and no private keys are exposed in client bundles.
- [ ] Check public links, Incognito access, minimal wallet disclosure and testnet-only claims.

**TS-23 status: PARTIAL — access reviewed and current-tree flags triaged; history scan, advisory disposition and final access/release sign-off pending.**
