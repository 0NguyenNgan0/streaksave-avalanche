"use client";

import { useStreakSave } from "@/hooks/use-streaksave";

export function ContractStatus() {
  const { configured, address, correctChain, readsLoading, readError } =
    useStreakSave({ scanRewards: false });
  if (!configured) return <div className="notice warn">Preview mode: chưa có địa chỉ StreakSavings và MockUSDC hợp lệ trong .env.local.</div>;
  if (!address) return <div className="notice">Đã cấu hình contract Fuji. Kết nối ví để tải số dư thực.</div>;
  if (!correctChain) return <div className="notice warn">Ví không ở Avalanche Fuji (43113). Chuyển mạng trước khi thực hiện giao dịch.</div>;
  if (readError) return <div className="notice warn" role="alert">Không đọc được dữ liệu on-chain: {readError}</div>;
  if (readsLoading) return <div className="notice">Đang tải dữ liệu on-chain từ Fuji…</div>;
  return <div className="notice good">Đã cấu hình contract Fuji và ví đang ở đúng mạng. Các số liệu bên trên được đọc on-chain.</div>;
}
