
"use client";

import { formatUnits } from "viem";
import { AppShell } from "@/components/app-shell";
import { TxFeedback } from "@/components/tx-feedback";
import { useStreakSave } from "@/hooks/use-streaksave";

export default function RewardsPage() {
  const api = useStreakSave();

  const busy = api.actionState === "claiming";
  const totalClaimable = formatUnits(api.raw.totalClaimable, 6);
  const totalClaimableDisplay =
    api.configured && api.address && api.correctChain && api.hasScanned
      ? Number(totalClaimable).toLocaleString(undefined, {
          maximumFractionDigits: 6,
        })
      : "—";

  return (
    <AppShell>
      <div className="stack">
        <div className="page-head">
          <div className="eyebrow">Phần thưởng</div>
          <h1 className="page-title">
            Giữ nhịp đều, nhận niềm vui nhỏ 🎁
          </h1>
        </div>

        <section className="card streak-card" style={{ minHeight: 340 }}>
          <div>
            <div className="stat-label">Streak hiện tại</div>

            <div className="streak-value" style={{ fontSize: 64 }}>
              🔥 {api.values.streak}x
            </div>

            <div className="stat-label">
              Tổng có thể nhận (các epoch đã quét)
            </div>

            <div className="stat-value" style={{ fontSize: 42 }}>
              {totalClaimableDisplay} USDC
            </div>

            <p className="subtle">
              Reward được tổng hợp từ các epoch đã kết thúc trong phạm vi
              đã quét. Đang ở epoch {api.values.epoch}; còn{" "}
              {api.values.epochCountdown} giây tới epoch tiếp theo.
            </p>

            {!api.configured && (
              <div className="notice warn" role="alert">
                Chưa cấu hình địa chỉ contract hợp lệ trong .env.local.
                Các số liệu on-chain đang tạm ẩn.
              </div>
            )}

            {api.readError && (
              <div className="notice warn" role="alert">
                {api.readError}
              </div>
            )}

            {api.address && !api.correctChain && (
              <div className="notice warn">
                Vui lòng chuyển ví sang Avalanche Fuji.
              </div>
            )}
          </div>

          <div className="fire-illustration">
            <div className="fire-orb">🎁</div>
          </div>
        </section>

        <section className="card">
          <div className="eyebrow">Lịch sử phần thưởng</div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              gap: 12,
              flexWrap: "wrap",
            }}
          >
            <h2 className="section-title">Phần thưởng theo epoch</h2>
            <button
              type="button"
              className="button secondary"
              disabled={
                api.scanning ||
                busy ||
                !api.configured ||
                !api.address ||
                !api.correctChain
              }
              onClick={() => void api.refresh()}
            >
              {api.scanning ? "Đang tải..." : "Làm mới"}
            </button>
          </div>

          {!api.configured && (
            <p className="subtle">
              Cần cấu hình contract trong .env.local trước khi tải lịch sử.
            </p>
          )}

          {!api.address && (
            <p className="subtle">
              Kết nối ví để xem phần thưởng của bạn.
            </p>
          )}

          {api.address && !api.correctChain && (
            <p className="subtle">
              Chuyển sang Avalanche Fuji để tải và nhận reward.
            </p>
          )}

          {api.scanning && (
            <p className="subtle">
              Đang kiểm tra các epoch...
            </p>
          )}

          {api.scanError && (
            <p className="notice warn" role="alert">
              Không tải được lịch sử phần thưởng: {api.scanError}
            </p>
          )}

          {!api.scanning &&
            api.readsReady &&
            api.address &&
            api.correctChain &&
            api.configured &&
            !api.hasScanned &&
            !api.scanError && (
              <p className="subtle">
                Chưa tải được lịch sử phần thưởng.
              </p>
            )}

          {!api.scanning &&
            api.address &&
            api.correctChain &&
            api.configured &&
            api.hasScanned &&
            !api.scanError &&
            api.rewardEpochs.length === 0 && (
              <p className="subtle">
                Chưa tìm thấy phần thưởng có thể nhận trong phạm vi đã kiểm tra.
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
                type="button"
                className="button cta"
                disabled={
                  busy ||
                  api.scanning ||
                  !api.configured ||
                  !api.address ||
                  !api.correctChain
                }
                onClick={() => void api.claimRewardFor(item.epoch)}
              >
                {busy ? "Đang nhận…" : "Nhận"}
              </button>
            </div>
          ))}

          {api.hasOlderRewards && (
            <button
              type="button"
              className="button"
              disabled={api.scanning || busy}
              onClick={() => void api.loadOlderRewards()}
              style={{ marginTop: 16 }}
            >
              {api.scanning ? "Đang tải..." : "Tải epoch cũ hơn"}
            </button>
          )}

          <TxFeedback
            state={api.actionState}
            hash={api.lastHash}
            error={api.error}
            notice={api.notice}
          />
        </section>

        <section className="card">
          <div className="eyebrow">Quy tắc minh bạch</div>

          <h2 className="section-title">
            Reward tách riêng khỏi tiền gốc.
          </h2>

          <p className="subtle">
            MVP sử dụng mock yield, không phải lợi nhuận DeFi thật.
            Reward được phân bổ theo snapshot trọng số streak của
            epoch đã kết thúc. Tiền gốc được theo dõi riêng và có
            thể rút theo logic contract.
          </p>
        </section>
      </div>
    </AppShell>
  );
}
