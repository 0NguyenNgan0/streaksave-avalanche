import { Inter } from "next/font/google";
import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/components/providers";

export const metadata: Metadata = {
  title: "StreakSave Â· Avalanche UniHack 2026",
  description: "Tiáº¿t kiá»‡m Ä‘á»u, giá»¯ streak, nháº­n thÆ°á»Ÿng vui trÃªn Avalanche.",
};

const inter = Inter({
  subsets: ["latin", "vietnamese"],
  display: "swap",
  variable: "--font-inter",
});
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="vi" suppressHydrationWarning>
      <body className={inter.variable}><Providers>{children}</Providers></body>
    </html>
  );
}
