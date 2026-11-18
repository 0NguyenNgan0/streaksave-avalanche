import Link from "next/link";
import { WalletButton } from "./wallet-button";

function BrandMark() {
  return <span className="avax-mark"><i/><b/></span>;
}

export function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <main className="app-root">
      <header className="topbar">
        <Link href="/" className="top-brand"><BrandMark/><span>StreakSave</span></Link>
        <nav className="desktop-nav" aria-label="Primary">
          <Link href="/" className="active"><span>⌂</span>Trang chủ</Link>
          <Link href="/deposit"><span>◎</span>Nạp tiền</Link>
          <Link href="/rewards"><span>♔</span>Phần thưởng</Link>
          <Link href="/withdraw"><span>▣</span>Rút tiền</Link>
        </nav>
        <div className="top-actions">
          <div className="network-pill"><BrandMark/><span>Avalanche Fuji</span><b>⌄</b></div>
          <WalletButton />
        </div>
      </header>

      <div className="page-canvas">{children}</div>

      <nav className="mobile-nav" aria-label="Mobile primary">
        <Link href="/"><span>⌂</span>Trang chủ</Link>
        <Link href="/deposit"><span>◎</span>Nạp tiền</Link>
        <Link href="/rewards"><span>♔</span>Phần thưởng</Link>
        <Link href="/withdraw"><span>▣</span>Rút tiền</Link>
      </nav>
    </main>
  );
}
