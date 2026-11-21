# StreakSave — Release readiness / submission handoff (21 Nov 2026)

**Baseline reviewed:** `dev` commit `1f989ed` (21 Nov 2026 local time), with QA report by Member C. This is a status record, **not** a release approval. Revalidate if `dev` changes.

## Verified / reported results

| Gate | Status | Basis |
|---|---|---|
| Source integration | PASS | Merged PR #1, #2 and #3 on `dev` |
| ABI / TypeScript / Next.js production build | PASS (local) | Operator ran commands on `dev` at `1f989ed` on 21 Nov |
| Local integration | PASS (local) | `scripts/check-integration.ps1` reported PASS on `dev`; Foundry locally SKIPPED |
| Solidity contract CI | Previously PASS | GitHub Actions Contracts CI passed on earlier commit(s); exact `dev` tip CI not shown by current workflow due to path filter |
| Fuji contract configuration | PASS (read-only) | Chain 43113, code present, linked USDC, decimals 6, provider and epoch 60 verified in CLI log |
| Core wallet functional QA | 4/4 PASS **reported by Member C** | `docs/QA_REPORT.md` dated 21 Nov; transaction hashes absent in report |
| Edge-case QA | 4/4 PASS **reported by Member C** | `docs/QA_REPORT.md`; does not represent all 15 protocol negatives |
| Full TS-19 sign-off | PENDING | See `docs/TS-19-EVIDENCE.md` for gaps |
| GitHub access | Checked | Repo PUBLIC, 3 collaborators; verify identities and external Incognito view |
| `main` protection | Configured | PR required, one approval, last-push approval, force-push and deletion disabled; **admin enforcement disabled** |
| Dependency audit | RISK ACCEPTED — TESTNET ONLY | 27 unresolved advisories (16 High, 11 Moderate). Lê Trí Trọng, Nguyễn Thanh Ngân and Lương Thị Thu Huyền agreed to temporary acceptance for the Fuji MVP on 21 Nov 2026. No security fixes were applied. |
| Git history secret scan | PENDING | Lightweight current-tree scan only; no full-history scan evidenced |
| Live frontend | PENDING | No verified Vercel URL and no Incognito smoke result |
| Release to `main` | PENDING | `main` remains initial starter at last check; PR `dev` → `main` with review required |
| Slides / video / submission | Owner C | Separate submission deliverables; do not claim uploaded or accepted without confirmation |

## Known npm audit risks

The operator-reported production dependency audit listed `decode-uri-component` (High DoS), `ws` (High disclosure/DoS), `zod` (High memory exhaustion) and `uuid` (Moderate bounds check), inherited through wallet integrations including wagmi/WalletConnect/Reown/MetaMask. These are dependency advisories, not proof of exploitability in the StreakSave UI. `npm ci`, ABI, typecheck and production build passed. `npm audit fix --dry-run` failed with an `ERESOLVE` attempt to choose old `wagmi@2.0.0` against React Query; the actual lockfile and installed tree matched at `wagmi@2.19.5`, `viem@2.57.19`, `@tanstack/react-query@5.107.1`. **No fixes were applied; do not describe audit as PASS.**

## Release decision checklist

- [ ] C/A confirm required E2E evidence and accepted residual QA gaps; attach receipts / reviewer note.
- [x] Team accepted the unresolved 16 High and 11 Moderate advisories for the Fuji-only hackathon demo; see the security review for restrictions and follow-up.
- [ ] Confirm no secrets in current tree/history and repo access/branch protection.
- [ ] Provide verified public live app URL, check Fuji connection and Incognito access.
- [ ] Update README and submission URLs after Vercel release.
- [ ] Open and review PR `dev` → `main`; obtain approval from a different person than last pusher; avoid force push.
- [ ] Verify final `main` content, links, GitHub actions and submission form receipt.

Do not claim real yield, security audit certification, a completely executed TS-19 suite or a successful final submission before the evidence exists.
