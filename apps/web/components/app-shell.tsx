import Link from "next/link";
import { WalletButton } from "./wallet-button";

export function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <main className="shell">
      <header className="header">
        <Link href="/" className="brand">
          <span className="brand-mark">A</span>
          <span>StreakSave</span>
        </Link>
        <WalletButton />
      </header>
      {children}
      <nav className="nav" aria-label="Primary">
        <Link href="/"><span className="nav-icon">🏠</span>Trang chủ</Link>
        <Link href="/deposit"><span className="nav-icon">🪙</span>Nạp tiền</Link>
        <Link href="/rewards"><span className="nav-icon">🎁</span>Phần thưởng</Link>
        <Link href="/withdraw"><span className="nav-icon">👛</span>Rút tiền</Link>
      </nav>
    </main>
  );
}
