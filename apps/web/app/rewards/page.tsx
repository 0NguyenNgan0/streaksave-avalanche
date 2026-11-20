
"use client";

import { AppShell } from "@/components/app-shell";
import { TxFeedback } from "@/components/tx-feedback";
import { useStreakSave } from "@/hooks/use-streaksave";
import { formatUnits } from "viem";

export default function RewardsPage() {
  const api = useStreakSave();

  const busy = api.actionState === "claiming";
  const totalClaimable = formatUnits(api.raw.totalClaimable, 6);

  return (
    <AppShell>
      <div className="stack">
        <div className="page-head">
          <div className="eyebrow">Phần thưởng</div>
          <h1 className="page-title">Giữ nhịp đều, nhận niềm vui</h1>
        </div>

        <section className="card streak-card" style={{ minHeight: 340 }}>
          <div>
            <div className="stat-label">Streak hiện tại</div>

            <div className="streak-value" style={{ fontSize: 64 }}>
              🔥 {api.values.streak}x
            </div>

            <div className="stat-label">Tổng phần thưởng chưa nhận</div>

            <div className="stat-value" style={{ fontSize: 42 }}>
              {Number(totalClaimable).toLocaleString(undefined, {
                maximumFractionDigits: 6,
              })}{" "}
              USDC
            </div>

            <p className="subtle">
              Phần thưởng được tổng hợp từ các epoch đã kết thúc.
            </p>
          </div>

          <div className="fire-illustration">
            <div className="fire-orb">🎁</div>
          </div>
        </section>

        <section className="card">
          <div className="eyebrow">Lịch sử phần thưởng</div>
          <h2 className="section-title">Phần thưởng theo epoch</h2>

          {!api.address && (
            <p className="subtle">Kết nối ví để xem phần thưởng của bạn.</p>
          )}

          {api.scanning && (
            <p className="subtle">Đang kiểm tra các epoch...</p>
          )}

          {api.scanError && (
            <p className="subtle">{api.scanError}</p>
          )}

          {!api.scanning &&
            api.address &&
            api.rewardEpochs.length === 0 && (
              <p className="subtle">
                Chưa tìm thấy phần thưởng có thể nhận.
              </p>
            )}

          {api.rewardEpochs.map((item) => (
            <div
              key={item.epoch.toString()}
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                gap: 16,
                padding: "16px 0",
                borderBottom: "1px solid var(--border)",
              }}
            >
              <div>
                <div className="stat-label">
                  Epoch #{item.epoch.toString()}
                </div>

                <div className="stat-value">
                  {Number(formatUnits(item.amount, 6)).toLocaleString(
                    undefined,
                    { maximumFractionDigits: 6 },
                  )}{" "}
                  USDC
                </div>
              </div>

              <button
                className="button cta"
                disabled={
                  busy ||
                  api.scanning ||
                  !api.configured ||
                  !api.address
                }
                onClick={() => api.claimRewardFor(item.epoch)}
              >
                {busy ? "Đang nhận…" : "Nhận"}
              </button>
            </div>
          ))}

          {api.hasOlderRewards && (
            <button
              className="button"
              disabled={api.scanning || busy}
              onClick={() => api.loadOlderRewards()}
              style={{ marginTop: 16 }}
            >
              {api.scanning ? "Đang tải..." : "Tải epoch cũ hơn"}
            </button>
          )}

          <TxFeedback
            state={api.actionState}
            hash={api.lastHash}
            error={api.error}
          />
        </section>

        <section className="card">
          <div className="eyebrow">Quy tắc minh bạch</div>

          <h2 className="section-title">
            Reward tách riêng khỏi tiền gốc.
          </h2>

          <p className="subtle">
            Community yield được phân bổ theo trọng số streak đã công bố.
            Principal của bạn vẫn được theo dõi riêng và có thể rút theo
            logic contract.
          </p>
        </section>
      </div>
    </AppShell>
  );
}
