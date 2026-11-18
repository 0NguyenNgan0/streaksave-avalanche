"use client";

import Link from "next/link";
import { AppShell } from "@/components/app-shell";
import { ContractStatus } from "@/components/contract-status";
import { useStreakSave } from "@/hooks/use-streaksave";

const preview = {
  streak: "7",
  principal: "125",
  reward: "3.42",
  epoch: "12",
  epochCountdown: "00:42",
};

function Milestone({
  label,
  unlocked,
}: {
  label: string;
  unlocked?: boolean;
}) {
  return (
    <div className={`journey-step ${unlocked ? "is-unlocked" : ""}`}>
      <div className="journey-dot">{unlocked ? "✓" : "🔒"}</div>
      <strong>{label}</strong>
      <span>{unlocked ? "Unlocked" : "Locked"}</span>
    </div>
  );
}

export default function HomePage() {
  const { values, address } = useStreakSave();
  const data = address ? values : preview;

  const streakNumber = Number(data.streak === "—" ? 0 : data.streak);
  const active = streakNumber > 0;

  return (
    <AppShell>
      <div className="home-shell">
        <section className="hero-clean">
          <div className="hero-copy">
            <h1>
              Tiết kiệm đều, duy trì streak,
              <br />
              nhận thưởng minh bạch.
            </h1>

            <p>
              Xây dựng thói quen tiết kiệm trên Avalanche Fuji với cơ chế streak
              và reward minh bạch on-chain.
            </p>

            <Link href="/deposit" className="primary-cta">
              <span className="cta-icon">◉</span>
              <span>Tiết kiệm 5 USDC</span>
              <span className="cta-arrow">→</span>
            </Link>
          </div>

          <div className="hero-dashboard">
            <section className="streak-summary-card">
              <div className="streak-main">
                <div className="summary-label">
                  <span className="summary-icon">▣</span>
                  <span>Streak hiện tại</span>
                </div>

                <div className="streak-number">{data.streak} ngày</div>

                <div className={`status-pill ${active ? "active" : "inactive"}`}>
                  <span>{active ? "✓" : "•"}</span>
                  <span>{active ? "Đang duy trì" : "Chưa bắt đầu"}</span>
                </div>
              </div>

              <div className="epoch-panel">
                <div className="epoch-row">
                  <span className="epoch-icon">◇</span>
                  <strong>Epoch #{data.epoch}</strong>
                </div>
                <div className="epoch-row countdown">
                  <span className="epoch-icon">◷</span>
                  <span>
                    Còn <strong>{data.epochCountdown}</strong>
                  </span>
                </div>
              </div>
            </section>

            <div className="metric-grid">
              <section className="metric-card">
                <div className="metric-icon green">◉</div>
                <div>
                  <div className="metric-label">Tổng đã tiết kiệm</div>
                  <div className="metric-value">{data.principal} USDC</div>
                </div>
              </section>

              <section className="metric-card">
                <div className="metric-icon violet">🎁</div>
                <div>
                  <div className="metric-label">Phần thưởng có thể nhận</div>
                  <div className="metric-value">{data.reward} USDC</div>
                </div>
              </section>
            </div>
          </div>
        </section>

        <ContractStatus />

        <section className="journey-card">
          <div className="journey-title">
            <span className="journey-title-icon">⚑</span>
            <h2>Hành trình streak</h2>
          </div>

          <div className="journey-track">
            <div className="journey-line">
              <span className="journey-progress" />
            </div>

            <Milestone label="4 ngày" unlocked />
            <Milestone label="7 ngày" unlocked />
            <Milestone label="14 ngày" />
            <Milestone label="30 ngày" />
          </div>
        </section>

        <section className="avalanche-card">
          <div className="avalanche-brand-block">
            <div className="ava-mark">A</div>
            <div>
              <div className="ava-kicker">Why Avalanche</div>
              <div className="ava-sub">Fuji Testnet</div>
            </div>
          </div>

          <div className="avalanche-benefits">
            <div className="benefit">
              <div className="benefit-icon">◇</div>
              <div>
                <strong>An toàn &amp; minh bạch</strong>
                <span>Dữ liệu on-chain, dễ kiểm chứng</span>
              </div>
            </div>

            <div className="benefit">
              <div className="benefit-icon">ϟ</div>
              <div>
                <strong>Giao dịch nhanh, phí thấp</strong>
                <span>Phù hợp khoản tiết kiệm nhỏ</span>
              </div>
            </div>

            <div className="benefit">
              <div className="benefit-icon">▱</div>
              <div>
                <strong>Không phụ thuộc trung gian</strong>
                <span>Quy tắc được thực thi on-chain</span>
              </div>
            </div>
          </div>
        </section>
      </div>
    </AppShell>
  );
}
