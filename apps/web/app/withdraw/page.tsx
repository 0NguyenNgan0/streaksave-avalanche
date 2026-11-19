"use client";

import { useState } from "react";
import { formatUnits } from "viem";
import { AppShell } from "@/components/app-shell";
import { TxFeedback } from "@/components/tx-feedback";
import { useStreakSave } from "@/hooks/use-streaksave";
import { usdcAmountError } from "@/lib/amount";

export default function WithdrawPage() {
  const api = useStreakSave();
  const [amount, setAmount] = useState("");
  const full = formatUnits(api.raw.principal, 6);
  const inputError = amount ? usdcAmountError(amount, api.raw.principal) : undefined;
  const disabled = api.busy || !api.configured || !api.address || !api.correctChain || !amount || Boolean(inputError);
  return (
    <AppShell>
      <div className="stack">
        <div className="page-head"><div className="eyebrow">Rút tiền</div><h1 className="page-title">Tiền gốc vẫn là của bạn. Luôn vậy. 🛡️</h1></div>
        <section className="card stack" style={{ maxWidth: 760 }}>
          <div className="stat"><div className="stat-icon">👛</div><div className="stat-label">Principal có thể rút</div><div className="stat-value">{api.values.principal} USDC</div></div>
          <input className="input" aria-label="Withdraw amount" inputMode="decimal" placeholder="Số USDC muốn rút" disabled={api.busy} value={amount} onChange={(e) => setAmount(e.target.value)} aria-invalid={Boolean(inputError)} />
          {inputError && <div className="notice warn" role="alert">{inputError}</div>}
          {api.address && !api.correctChain && <div className="notice warn">Vui lòng chuyển ví sang Avalanche Fuji.</div>}
          <button className="button secondary" disabled={api.busy || api.raw.principal === 0n} onClick={() => setAmount(full)}>Dùng toàn bộ principal</button>
          <button className="button" disabled={Boolean(disabled)} onClick={() => void api.withdraw(amount)}>{api.actionState === "withdrawing" ? "Đang rút…" : `Rút ${amount || "0"} USDC`}</button>
          <div className="notice good">✓ Không áp dụng phạt lên principal trong flow MVP. Rút toàn bộ sẽ reset streak.</div>
          <TxFeedback state={api.actionState} hash={api.lastHash} error={api.error} notice={api.notice} />
        </section>
      </div>
    </AppShell>
  );
}
