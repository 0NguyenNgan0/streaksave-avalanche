"use client";

import { useMemo, useState } from "react";
import { parseUnits } from "viem";
import { AppShell } from "@/components/app-shell";
import { TxFeedback } from "@/components/tx-feedback";
import { useStreakSave } from "@/hooks/use-streaksave";

const OPTIONS = ["5", "10", "20", "50"];

export default function DepositPage() {
  const [amount, setAmount] = useState("5");
  const api = useStreakSave();
  const required = useMemo(() => {
    try { return parseUnits(amount || "0", 6); } catch { return 0n; }
  }, [amount]);
  const needsApproval = api.raw.allowance < required;
  const busy = ["approving", "depositing"].includes(api.actionState);

  return (
    <AppShell>
      <div className="stack">
        <div className="page-head"><div className="eyebrow">Nạp tiền</div><h1 className="page-title">Một bước nhỏ cho streak hôm nay 🌱</h1><p className="subtle">Số dư ví: {api.values.balance} USDC</p></div>
        <section className="card stack" style={{maxWidth:760}}>
          <div>
            <div className="stat-label">Chọn số tiền</div>
            <div className="amounts">
              {OPTIONS.map((x) => <button key={x} className={`amount ${amount===x?"active":""}`} onClick={() => setAmount(x)}>{x} USDC</button>)}
            </div>
          </div>
          <input className="input" aria-label="Custom amount" value={amount} onChange={(e)=>setAmount(e.target.value.replace(/[^0-9.]/g,""))} />

          {!api.configured && <div className="notice warn">Đang ở chế độ preview. Thêm địa chỉ contract vào .env.local để bật giao dịch Fuji thật.</div>}

          <div className="next-box">
            <div><strong>{needsApproval ? "Bước 1/2 · Cho phép USDC" : "Bước 2/2 · Hoàn tất nạp"}</strong><div className="subtle">UI chỉ mở bước tiếp theo sau khi giao dịch trước đã confirm.</div></div>
            <div style={{fontSize:30}}>{needsApproval ? "🔐" : "🌱"}</div>
          </div>

          {needsApproval ? (
            <button className="button" disabled={busy || !api.configured || !api.address || required===0n} onClick={() => api.approve(amount)}>
              {api.actionState === "approving" ? "Đang approve…" : `Bước 1: Approve ${amount} USDC`}
            </button>
          ) : (
            <button className="button" disabled={busy || !api.configured || !api.address || required===0n} onClick={() => api.deposit(amount)}>
              {api.actionState === "depositing" ? "Đang nạp…" : `Bước 2: Tiết kiệm ${amount} USDC`}
            </button>
          )}
          <TxFeedback state={api.actionState} hash={api.lastHash} error={api.error} />
        </section>
      </div>
    </AppShell>
  );
}
