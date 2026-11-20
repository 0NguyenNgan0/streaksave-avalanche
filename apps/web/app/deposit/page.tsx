"use client";

import { useMemo, useState } from "react";
import { AppShell } from "@/components/app-shell";
import { TxFeedback } from "@/components/tx-feedback";
import { useStreakSave } from "@/hooks/use-streaksave";
import { parsePositiveUsdc, usdcAmountError } from "@/lib/amount";

const OPTIONS = ["5", "10", "20", "50"];

export default function DepositPage() {
  const [amount, setAmount] = useState("5");
  const api = useStreakSave({ scanRewards: false });
  const required = useMemo(() => parsePositiveUsdc(amount), [amount]);
  const needsApproval = required !== undefined && api.raw.allowance < required;
  const inputError = api.readsReady
    ? usdcAmountError(amount, api.raw.balance)
    : undefined;
  const disabled = api.busy || !api.readsReady || !api.configured || !api.address || !api.correctChain || Boolean(inputError);

  return (
    <AppShell>
      <div className="stack">
        <div className="page-head"><div className="eyebrow">Nạp tiền</div><h1 className="page-title">Một bước nhỏ cho streak hôm nay 🌱</h1><p className="subtle">Số dư ví: {api.values.balance} USDC</p></div>
        <section className="card stack" style={{ maxWidth: 760 }}>
          <div><div className="stat-label">Chọn số tiền</div><div className="amounts">{OPTIONS.map((x) => <button key={x} type="button" className={`amount ${amount === x ? "active" : ""}`} disabled={api.busy} onClick={() => setAmount(x)}>{x} USDC</button>)}</div></div>
          <input className="input" aria-label="Custom amount" inputMode="decimal" value={amount} disabled={api.busy} onChange={(e) => setAmount(e.target.value)} aria-invalid={Boolean(inputError)} />
          {inputError && <div className="notice warn" role="alert">{inputError}</div>}
          {api.readError && <div className="notice warn" role="alert">{api.readError}</div>}
          {!api.configured && <div className="notice warn">Preview mode: chưa có địa chỉ hợp lệ trong .env.local.</div>}
          {api.address && !api.correctChain && <div className="notice warn">Vui lòng chuyển ví sang Avalanche Fuji.</div>}
          <div className="next-box"><div><strong>{needsApproval ? "Bước 1/2 · Cho phép USDC" : "Bước 2/2 · Hoàn tất nạp"}</strong><div className="subtle">Chờ transaction xác nhận trước khi tiếp tục.</div></div><div style={{ fontSize: 30 }}>{needsApproval ? "🔐" : "🌱"}</div></div>
          {needsApproval ? (
            <button className="button" disabled={disabled} onClick={() => void api.approve(amount)}>{api.actionState === "approving" ? "Đang approve…" : `Bước 1: Approve ${amount} USDC`}</button>
          ) : (
            <button className="button" disabled={disabled} onClick={() => void api.deposit(amount)}>{api.actionState === "depositing" ? "Đang nạp…" : `Bước 2: Tiết kiệm ${amount} USDC`}</button>
          )}
          <TxFeedback state={api.actionState} hash={api.lastHash} error={api.error} notice={api.notice} />
        </section>
      </div>
    </AppShell>
  );
}
