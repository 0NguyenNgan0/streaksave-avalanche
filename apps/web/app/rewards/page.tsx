"use client";

import { AppShell } from "@/components/app-shell";
import { TxFeedback } from "@/components/tx-feedback";
import { useStreakSave } from "@/hooks/use-streaksave";

export default function RewardsPage() {
  const api = useStreakSave();
  return (
    <AppShell>
      <div className="stack">
        <div className="page-head"><div className="eyebrow">Phần thưởng</div><h1 className="page-title">Giữ nhịp đều, nhận niềm vui nhỏ 🎁</h1></div>
        <section className="card streak-card" style={{ minHeight: 340 }}>
          <div>
            <div className="stat-label">Streak hiện tại</div>
            <div className="streak-value" style={{ fontSize: 64 }}>🔥 {api.values.streak}x</div>
            <div className="stat-label">Reward có thể claim từ epoch mới kết thúc</div>
            <div className="stat-value" style={{ fontSize: 42 }}>{api.values.reward} USDC</div>
            <p className="subtle">Reward chỉ có thể claim sau khi epoch kết thúc và yieldProvider đã thêm mock yield. Đang ở epoch {api.values.epoch}; còn {api.values.epochCountdown} tới epoch tiếp theo.</p>
            {api.address && !api.correctChain && <div className="notice warn">Vui lòng chuyển ví sang Avalanche Fuji.</div>}
            <button className="button cta" disabled={api.busy || !api.configured || !api.address || !api.correctChain || api.raw.reward === 0n} onClick={() => void api.claimReward()}>{api.actionState === "claiming" ? "Đang nhận…" : "Nhận phần thưởng"}</button>
            <TxFeedback state={api.actionState} hash={api.lastHash} error={api.error} notice={api.notice} />
          </div>
          <div className="fire-illustration"><div className="fire-orb">🎁</div></div>
        </section>
        <section className="card"><div className="eyebrow">Quy tắc minh bạch</div><h2 className="section-title">Reward tách riêng khỏi tiền gốc.</h2><p className="subtle">MVP dùng mock yield, không phải lợi nhuận DeFi thật. Reward được phân bổ theo snapshot trọng số streak của epoch đã kết thúc. Tiền gốc được theo dõi riêng.</p></section>
      </div>
    </AppShell>
  );
}
