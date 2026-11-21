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

## Git history secret scan — 21 Nov 2026

Gitleaks 8.30.1 was run against the local Git repository:

- Command: `gitleaks git . --redact --report-format json --exit-code 1`
- Commits scanned: 37
- Data scanned: approximately 2.38 MB
- Findings: 1
- Exit code: 1 (finding detected)

### Finding triage

- Rule: `generic-api-key`
- File: `scripts/verify-fuji-readonly.ps1`
- Line: 3
- Commit: `d851efbf32f85e8d86b831186f5c2452f79bf01e`
- Classification: **False positive — public Avalanche Fuji MockUSDC contract address**.
- No credential revocation or Git history rewrite required for this finding.

The flagged value was independently checked against the source file and the documented public MockUSDC contract address. No actual secret was confirmed among the detected findings.

This result applies to the commits and detection rules covered by this Gitleaks run. It is not proof that the repository or complete Git history contains no secrets.
## npm production dependency advisories (OPEN)

`npm audit --omit=dev` reported **27 vulnerability findings: 16 high, 11 moderate** in the installed dependency tree. Distinct packages highlighted include `decode-uri-component`, `ws`, `zod`, `uuid`, with many transitive dependents (WalletConnect, wagmi, MetaMask, Reown). Advisory exposure depends on whether vulnerable paths are reachable.

- No dependency updates or automatic fixes were committed.
- `npm audit fix --dry-run` failed at dependency resolution (`ERESOLVE`, `wagmi@2.0.0` against React Query peer requirement).
- Actual lockfile and installed direct package versions matched: wagmi 2.19.5, viem 2.57.19, @tanstack/react-query 5.107.1.
- Code build/typecheck PASS does **not** resolve security findings.

## Temporary Dependency Risk Acceptance — Avalanche UniHack 2026

**Decision:** ACCEPTED WITH RESTRICTIONS — FUJI TESTNET MVP ONLY

**Approved by team consensus (21 Nov 2026):**
- Lê Trí Trọng — Smart Contracts & Deployment
- Nguyễn Thanh Ngân — Frontend & UI/UX
- Lương Thị Thu Huyền — Integration & QA

**Scope:** 27 unresolved production dependency advisories
(16 High, 11 Moderate).

**Rationale:** A limited dependency update was tested. TypeScript
and Next.js build passed, but the vulnerability count remained 27.
The team chose to preserve the tested wallet integration for the
hackathon demonstration.

**Conditions:**
- Avalanche Fuji Testnet and test-only assets only.
- No claim of independent security audit or production readiness.
- All 27 advisories remain unresolved.
- Remediation and wallet regression testing required before
  any real-asset deployment.

**Residual risk:** Temporarily accepted, not eliminated.
## Before any public release

- [x] Run Gitleaks Git-history scan and triage the detected finding (37 commits scanned; one false positive).
- [ ] Confirm active collaborator permissions, branch protection behavior and no unintended admin bypass.
- [x] Team approved temporary acceptance of 27 unresolved dependency advisories for the Fuji Testnet MVP.
- [ ] Verify deploy settings and Vercel environment contain **only public data** in `NEXT_PUBLIC_*`, and no private keys are exposed in client bundles.
- [ ] Check public links, Incognito access, minimal wallet disclosure and testnet-only claims.

**TS-23 status: PARTIAL — dependency risks accepted for Fuji-only demo; remaining release and access checks still require sign-off.**
