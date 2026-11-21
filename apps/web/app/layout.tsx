import { Inter } from "next/font/google";
import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/components/providers";

export const metadata: Metadata = {
  title: "StreakSave | Avalanche UniHack 2026",
  description:
    "Xây dựng thói quen tiết kiệm, duy trì streak và nhận phần thưởng minh bạch trên Avalanche Fuji.",
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
