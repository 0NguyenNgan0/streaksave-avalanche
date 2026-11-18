"use client";

import Link from "next/link";
import { AppShell } from "@/components/app-shell";
import { useStreakSave } from "@/hooks/use-streaksave";

const preview = { streak: "7", principal: "125", reward: "3.42" };

function FireArt() {
  return (
    <svg viewBox="0 0 260 230" className="hero-fire" aria-hidden="true">
      <defs>
        <linearGradient id="fireOuter" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#ff3d24"/>
          <stop offset="1" stopColor="#ff9b18"/>
        </linearGradient>
        <linearGradient id="fireInner" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#fff16b"/>
          <stop offset="1" stopColor="#ffb326"/>
        </linearGradient>
        <linearGradient id="grass" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#c9e951"/>
          <stop offset="1" stopColor="#77bd2d"/>
        </linearGradient>
        <filter id="glow"><feGaussianBlur stdDeviation="7"/></filter>
      </defs>
      <ellipse cx="132" cy="198" rx="84" ry="21" fill="#ffd857" opacity=".25" filter="url(#glow)"/>
      <ellipse cx="132" cy="198" rx="87" ry="18" fill="url(#grass)"/>
      <path d="M132 190c-49 0-72-31-56-70 9-21 32-32 27-69 29 17 42 42 35 64 12-13 24-26 20-49 25 24 36 51 25 77-9 27-27 47-51 47Z" fill="url(#fireOuter)"/>
      <path d="M132 177c-26 0-39-17-31-38 5-12 17-19 15-39 17 10 25 25 21 38 8-8 15-15 14-28 13 13 20 28 14 43-6 15-17 24-33 24Z" fill="url(#fireInner)"/>
      <path d="M118 199c-20-6-29-17-31-31 15 10 28 15 45 18-3 8-7 11-14 13Z" fill="#92cf36"/>
      <path d="M157 197c17-6 27-16 29-28-13 8-25 13-42 17 4 7 7 9 13 11Z" fill="#8bc832"/>
      <g fill="#ffad14">
        <path d="M206 57l5 13 13 5-13 5-5 13-5-13-13-5 13-5 5-13Z"/>
        <path d="M224 99l3 8 8 3-8 3-3 8-3-8-8-3 8-3 3-8Z"/>
        <path d="M61 91l4 10 10 4-10 4-4 10-4-10-10-4 10-4 4-10Z"/>
      </g>
    </svg>
  );
}

function MascotArt() {
  return (
    <svg viewBox="0 0 520 320" className="mascot-art" aria-hidden="true">
      <defs>
        <linearGradient id="hill1" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#bceab0"/><stop offset="1" stopColor="#7ccf79"/>
        </linearGradient>
        <linearGradient id="hill2" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#c8c8ff"/><stop offset="1" stopColor="#9cb6ef"/>
        </linearGradient>
        <linearGradient id="mascot" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#ff7f4f"/><stop offset="1" stopColor="#ef4148"/>
        </linearGradient>
      </defs>
      <path d="M0 205 75 120l76 63 72-96 86 118 77-57 134 92v80H0Z" fill="url(#hill2)" opacity=".52"/>
      <path d="M0 232c70-44 132-28 201 10 70 38 165 14 319-25v103H0Z" fill="url(#hill1)"/>
      <g opacity=".9" fill="#73bf5b">
        <ellipse cx="37" cy="244" rx="10" ry="34" transform="rotate(-25 37 244)"/>
        <ellipse cx="59" cy="242" rx="9" ry="30" transform="rotate(25 59 242)"/>
        <ellipse cx="464" cy="247" rx="11" ry="35" transform="rotate(24 464 247)"/>
        <ellipse cx="487" cy="239" rx="10" ry="31" transform="rotate(-28 487 239)"/>
      </g>
      <g transform="translate(112 93)">
        <path d="M70 164c-45 0-71-30-61-69 7-26 27-44 39-73 10-24 11-35 12-48 21 15 35 31 45 51 8 16 13 30 15 45 6 43-8 94-50 94Z" fill="url(#mascot)"/>
        <ellipse cx="36" cy="86" rx="12" ry="9" fill="#3b2b38"/>
        <ellipse cx="91" cy="86" rx="12" ry="9" fill="#3b2b38"/>
        <path d="M49 105c9 10 21 10 30 0" fill="none" stroke="#3b2b38" strokeWidth="5" strokeLinecap="round"/>
        <circle cx="28" cy="105" r="10" fill="#ffb0a1" opacity=".75"/>
        <circle cx="101" cy="105" r="10" fill="#ffb0a1" opacity=".75"/>
        <path d="M48 125 70 91l23 34h-14l-9-14-9 14Z" fill="white"/>
        <path d="M13 96c-21 0-34 11-42 28" fill="none" stroke="#4b3a38" strokeWidth="16" strokeLinecap="round"/>
        <path d="M110 83c20-23 34-44 47-64" fill="none" stroke="#4b3a38" strokeWidth="16" strokeLinecap="round"/>
        <circle cx="160" cy="13" r="29" fill="#ffc83d" stroke="#f3a91e" strokeWidth="8"/>
        <path d="m160-4 6 12 13 2-10 9 3 13-12-6-12 6 3-13-10-9 13-2Z" fill="#fff2a6"/>
        <ellipse cx="25" cy="166" rx="24" ry="17" fill="#4b3a38"/>
        <ellipse cx="91" cy="166" rx="24" ry="17" fill="#4b3a38"/>
      </g>
      <g transform="translate(300 148)">
        <rect x="0" y="15" width="105" height="135" rx="25" fill="#d5fbf1" stroke="#78c9b7" strokeWidth="8"/>
        <rect x="16" y="0" width="73" height="28" rx="12" fill="#82cfbe"/>
        <rect x="16" y="68" width="73" height="38" rx="10" fill="#fff3cd"/>
        <text x="52" y="92" textAnchor="middle" fontSize="18" fontWeight="900" fill="#7e6446">SAVING</text>
        <g fill="#f4ba38"><ellipse cx="28" cy="125" rx="16" ry="7"/><ellipse cx="53" cy="122" rx="16" ry="7"/><ellipse cx="76" cy="130" rx="16" ry="7"/></g>
      </g>
    </svg>
  );
}

function Badge({ kind, locked = false }: { kind: "4" | "7" | "14" | "30"; locked?: boolean }) {
  const label = kind === "4" ? "🔥" : kind === "7" ? "✦" : "🔒";
  return (
    <div className={"badge-item " + (locked ? "locked" : "")}>
      <div className={"badge-shield badge-" + kind}><span>{label}</span></div>
      <strong>{kind} ngày</strong>
      {!locked && <i>✓</i>}
    </div>
  );
}

export default function HomePage() {
  const { values, address } = useStreakSave();
  const data = address ? values : preview;

  return (
    <AppShell>
      <section className="approved-dashboard">
        <div className="left-column">
          <div className="event-pill"><span className="mini-avax">A</span>Avalanche Team1 Vietnam – UniHack 2026</div>
          <h1 className="approved-title">Tiết kiệm đều,<br/>nhận thưởng <span>vui!</span><b>⌁</b></h1>
          <p className="approved-copy">Duy trì thói quen tiết kiệm trên Avalanche,<br/>tích lũy streak và nhận thêm phần thưởng<br/>theo thời gian.</p>
          <div className="mascot-wrap"><MascotArt/></div>
        </div>

        <div className="center-column">
          <div className="streak-hero">
            <div className="streak-copy">
              <div className="streak-label">🔥 Streak hiện tại <span className="info-dot">i</span></div>
              <div className="approved-streak">{data.streak} ngày</div>
              <div className="maintain-chip">🔥 Đang duy trì!</div>
            </div>
            <FireArt/>
          </div>

          <div className="metric-row">
            <div className="metric-card">
              <div className="metric-heading"><span className="metric-icon coin-icon">◎</span>Đã tiết kiệm</div>
              <div className="metric-number">{data.principal} USDC</div>
            </div>
            <div className="metric-card">
              <div className="metric-heading"><span className="metric-icon gift-icon">🎁</span>Phần thưởng dự kiến <span className="info-dot small">i</span></div>
              <div className="metric-number">{data.reward} USDC</div>
            </div>
          </div>

          <Link href="/deposit" className="approved-cta"><span className="cta-coins">◎</span>Tiết kiệm 5 USDC ngay <span>→</span></Link>
        </div>

        <div className="right-column">
          <div className="journey-panel">
            <h2><span className="target-icon">◉</span>Hành trình streak</h2>
            <div className="progress-line">
              <div className="progress-fill"/>
              <div className="step done"><span>✓</span><b>4 ngày</b></div>
              <div className="step current"><span>✓</span><b>7 ngày</b></div>
              <div className="step"><span/><b>14 ngày</b></div>
              <div className="step"><span/><b>30 ngày</b></div>
            </div>
            <div className="next-reward">
              <div className="gift-square">🎁</div>
              <div><small>Mốc tiếp theo</small><strong>Huy hiệu 14 ngày</strong></div>
              <b className="chev">›</b>
            </div>
          </div>

          <div className="benefit-panel">
            <h2><span>🏆</span>Phần thưởng streak</h2>
            <ul>
              <li><b>✓</b>Tích lũy streak càng lâu, thưởng càng lớn</li>
              <li><b>✓</b>Giao dịch nhanh, phí thấp trên Avalanche</li>
              <li><b>✓</b>Minh bạch và an toàn on-chain</li>
            </ul>
          </div>
        </div>
      </section>

      <section className="badge-strip">
        <div className="badge-copy">
          <div className="ribbon-icon">🏅</div>
          <div><h2>Bộ sưu tập huy hiệu</h2><p>Mở khóa huy hiệu khi duy trì streak!</p></div>
        </div>
        <div className="badge-divider"/>
        <Badge kind="4"/>
        <Badge kind="7"/>
        <Badge kind="14" locked/>
        <Badge kind="30" locked/>
      </section>
    </AppShell>
  );
}
