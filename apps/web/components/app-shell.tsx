"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { WalletButton } from "./wallet-button";

const navItems = [
  { href: "/", label: "Trang chủ", icon: "⌂" },
  { href: "/deposit", label: "Nạp tiền", icon: "⊕" },
  { href: "/rewards", label: "Phần thưởng", icon: "♙" },
  { href: "/withdraw", label: "Rút tiền", icon: "⇄" },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();

  return (
    <main className="app-root">
      <header className="topbar">
        <div className="topbar-inner">
          <Link href="/" className="brand-clean">
            <span className="brand-symbol">A</span>
            <span>StreakSave</span>
          </Link>

          <nav className="desktop-nav" aria-label="Primary navigation">
            {navItems.map((item) => {
              const active = pathname === item.href;

              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={active ? "active" : ""}
                  aria-current={active ? "page" : undefined}
                >
                  <span aria-hidden="true">{item.icon}</span>
                  {item.label}
                </Link>
              );
            })}
          </nav>

          <div className="topbar-actions">
            <div className="network-pill">
              <span className="ava-mini">A</span>
              <span>Avalanche Fuji</span>
              <span>⌄</span>
            </div>
            <WalletButton />
          </div>
        </div>
      </header>

      <div className="page-container">{children}</div>

      <nav className="mobile-nav" aria-label="Mobile navigation">
        {navItems.map((item) => {
          const active = pathname === item.href;

          return (
            <Link
              key={item.href}
              href={item.href}
              className={active ? "active" : ""}
              aria-current={active ? "page" : undefined}
            >
              <span className="mobile-nav-icon" aria-hidden="true">
                {item.icon}
              </span>
              <span>{item.label}</span>
            </Link>
          );
        })}
      </nav>
    </main>
  );
}
