"use client";

import { useState } from "react";
import { formatUnits } from "viem";
import { AppShell } from "@/components/app-shell";
import { TxFeedback } from "@/components/tx-feedback";
import { useStreakSave } from "@/hooks/use-streaksave";

export default function WithdrawPage() {
  const api = useStreakSave();
  const [amount, setAmount] = useState("");
  const full = formatUnits(api.raw.principal, 6);
  const busy = api.actionState === "withdrawing";
  return (
    <AppShell>
      <div className="stack">
        <div className="page-head"><div className="eyebrow">Rút tiền</div><h1 className="page-title">Tiền gốc vẫn là của bạn. Luôn vậy. 🛡️</h1></div>
        <section className="card stack" style={{maxWidth:760}}>
          <div className="stat"><div className="stat-icon">👛</div><div className="stat-label">Principal có thể rút</div><div className="stat-value">{api.values.principal} USDC</div></div>
          <input className="input" aria-label="Withdraw amount" placeholder="Số USDC muốn rút" value={amount} onChange={(e)=>setAmount(e.target.value.replace(/[^0-9.]/g,""))} />
          <button className="button secondary" disabled={api.raw.principal===0n} onClick={() => setAmount(full)}>Dùng toàn bộ principal</button>
          <button className="button" disabled={busy || !api.configured || !api.address || !amount || Number(amount)<=0} onClick={() => api.withdraw(amount)}>{busy ? "Đang rút…" : `Rút ${amount || "0"} USDC`}</button>
          <div className="notice good">✓ Không áp dụng phạt lên principal trong flow MVP.</div>
          <TxFeedback state={api.actionState} hash={api.lastHash} error={api.error} />
        </section>
      </div>
    </AppShell>
  );
}
