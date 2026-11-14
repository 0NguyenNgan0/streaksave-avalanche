"use client";

import Link from "next/link";
import { AppShell } from "@/components/app-shell";
import { ContractStatus } from "@/components/contract-status";
import { useStreakSave } from "@/hooks/use-streaksave";

const preview = { streak: "7", principal: "125", reward: "3.42" };

export default function HomePage() {
  const { values, address } = useStreakSave();
  const data = address ? values : preview;

  return (
    <AppShell>
      <div className="stack">
        <section className="hero-layout">
          <div className="intro">
            <div className="badge-line">🔺 Avalanche Team1 Vietnam · UniHack 2026</div>
            <h1 className="h1">Tiết kiệm đều,<br/>nhận thưởng <span className="fun">vui!</span></h1>
            <p className="subtle intro-copy">
              Xây thói quen tiết kiệm cùng cộng đồng trên Avalanche. Duy trì streak càng lâu, mở khóa thêm cột mốc và nhận phần thưởng theo quy tắc minh bạch on-chain.
            </p>
            <div className="mascot-scene" aria-label="Friendly savings mascot illustration">
              <div className="mascot"><div className="mascot-mouth"/><div className="mascot-logo">A</div></div>
              <div className="jar"><div className="jar-coins"/></div>
              <div style={{alignSelf:"center"}}>
                <strong style={{fontSize:20}}>Mỗi tuần một chút 🌱</strong>
                <div className="subtle" style={{marginTop:6}}>Không cần thật nhiều. Quan trọng là đều đặn.</div>
              </div>
            </div>
          </div>

          <section className="card streak-card">
            <div>
              <div className="eyebrow">Streak hiện tại</div>
              <div className="streak-value">{data.streak} ngày</div>
              <div className="status-chip">🔥 Đang duy trì!</div>

              <div className="stats">
                <div className="stat">
                  <div className="stat-icon">🪙</div>
                  <div className="stat-label">Đã tiết kiệm</div>
                  <div className="stat-value">{data.principal} USDC</div>
                </div>
                <div className="stat">
                  <div className="stat-icon">🎁</div>
                  <div className="stat-label">Phần thưởng có thể nhận</div>
                  <div className="stat-value">{data.reward} USDC</div>
                </div>
              </div>
              <Link href="/deposit" className="button cta" style={{display:"block",textAlign:"center"}}>Tiết kiệm 5 USDC ngay →</Link>
            </div>
            <div className="fire-illustration" aria-hidden="true">
              <span className="spark s1">✦</span><span className="spark s2">✦</span><span className="spark s3">✦</span>
              <div className="fire-orb">🔥</div>
            </div>
          </section>
        </section>

        <ContractStatus />

        <section className="content-grid">
          <div className="card journey">
            <div>
              <div className="eyebrow">Hành trình streak</div>
              <h2 className="section-title">Cứ đều đặn, phần thưởng sẽ đến ✨</h2>
            </div>
            <div className="journey-track">
              <div className="milestone done"><div className="milestone-dot">✓</div><span>4 ngày</span></div>
              <div className="milestone current"><div className="milestone-dot">✓</div><span>7 ngày</span></div>
              <div className="milestone"><div className="milestone-dot">14</div><span>14 ngày</span></div>
              <div className="milestone"><div className="milestone-dot">30</div><span>30 ngày</span></div>
            </div>
            <div className="next-box">
              <div><strong>🎁 Mốc tiếp theo</strong><div className="subtle">Huy hiệu 14 ngày</div></div>
              <div style={{fontSize:34}}>🏅</div>
            </div>
          </div>

          <div className="card fun-note">
            <div className="eyebrow">Vì sao trên Avalanche?</div>
            <h2 className="section-title">Web3 ở phía sau, trải nghiệm ở phía trước.</h2>
            <div className="fun-list">
              <div><span>✓</span><span>Phí giao dịch thấp, phù hợp khoản tiết kiệm nhỏ.</span></div>
              <div><span>✓</span><span>Xác nhận nhanh trên Fuji testnet cho demo mượt.</span></div>
              <div><span>✓</span><span>Quy tắc streak và reward minh bạch on-chain.</span></div>
            </div>
          </div>
        </section>

        <section className="card">
          <div className="row">
            <div><div className="eyebrow">Bộ sưu tập huy hiệu</div><h2 className="section-title">Nhìn lại những cột mốc nhỏ mà vui 🥳</h2></div>
            <span className="subtle">Duy trì streak để mở khóa</span>
          </div>
          <div className="badges">
            <div className="badge-card"><div className="badge-medal">🔥</div><strong>4 ngày</strong><div className="subtle">Warm-up</div></div>
            <div className="badge-card"><div className="badge-medal">⭐</div><strong>7 ngày</strong><div className="subtle">On a roll</div></div>
            <div className="badge-card locked"><div className="badge-medal">🏅</div><strong>14 ngày</strong><div className="subtle">Locked</div></div>
            <div className="badge-card locked"><div className="badge-medal">💎</div><strong>30 ngày</strong><div className="subtle">Locked</div></div>
          </div>
        </section>
      </div>
    </AppShell>
  );
}
