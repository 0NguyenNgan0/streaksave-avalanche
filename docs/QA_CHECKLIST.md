# QA Checklist

- [ ] Contracts CI green
- [ ] ABI checker PASS
- [ ] npm typecheck/build PASS
- [ ] UI uses effectiveStreakOf
- [ ] same-epoch extra deposit does not increment streak
- [ ] missed epoch => effective streak 0
- [ ] full withdraw resets streak
- [ ] partial withdraw preserves streak
- [ ] only yieldProvider can addMockYield
- [ ] rewardOf matches UI
- [ ] double claim rejected
- [ ] mobile 390px usable

Evidence:
```text
Commit:
MockUSDC:
StreakSavings:
epochDuration:
yieldProvider:
Approve tx:
Deposit tx:
Yield tx:
Claim tx:
Withdraw tx:
Vercel:
Result:
```
