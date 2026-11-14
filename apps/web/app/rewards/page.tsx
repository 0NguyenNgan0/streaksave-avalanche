"use client";

import { AppShell } from "@/components/app-shell";
import { TxFeedback } from "@/components/tx-feedback";
import { useStreakSave } from "@/hooks/use-streaksave";

export default function RewardsPage() {
  const api = useStreakSave();
  const busy = api.actionState === "claiming";
  return (
    <AppShell>
      <div className="stack">
        <div className="page-head"><div className="eyebrow">Phần thưởng</div><h1 className="page-title">Giữ nhịp đều, nhận niềm vui nhỏ 🎁</h1></div>
        <section className="card streak-card" style={{minHeight:340}}>
          <div>
            <div className="stat-label">Streak hiện tại</div>
            <div className="streak-value" style={{fontSize:64}}>🔥 {api.values.streak}x</div>
            <div className="stat-label">Có thể nhận</div>
            <div className="stat-value" style={{fontSize:42}}>{api.values.reward} USDC</div>
            <button className="button cta" disabled={busy || !api.configured || !api.address || api.raw.reward === 0n} onClick={() => api.claimReward()}>{busy ? "Đang nhận…" : "Nhận phần thưởng"}</button>
            <TxFeedback state={api.actionState} hash={api.lastHash} error={api.error} />
          </div>
          <div className="fire-illustration"><div className="fire-orb">🎁</div></div>
        </section>
        <section className="card"><div className="eyebrow">Quy tắc minh bạch</div><h2 className="section-title">Reward tách riêng khỏi tiền gốc.</h2><p className="subtle">Community yield được phân bổ theo trọng số streak đã công bố. Principal của bạn vẫn được theo dõi riêng và có thể rút theo logic contract.</p></section>
      </div>
    </AppShell>
  );
}
