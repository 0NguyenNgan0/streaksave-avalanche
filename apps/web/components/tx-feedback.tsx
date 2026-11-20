
"use client";

import { txUrl } from "@/lib/chain";
import type { Hash } from "viem";

export function TxFeedback({
  state,
  hash,
  error,
  notice,
}: {
  state: string;
  hash?: Hash;
  error?: string | null;
  notice?: string | null;
}) {
  if (state === "idle") return null;

  const confirmed = state === "success";

  return (
    <div
      className={
        state === "error"
          ? "notice warn"
          : confirmed
            ? "notice good"
            : "notice"
      }
      role="status"
      aria-live="polite"
    >
      <strong>
        {confirmed
          ? "Transaction confirmed ✓"
          : state === "error"
            ? "Giao dịch chưa hoàn tất"
            : "Đang xử lý giao dịch…"}
      </strong>

      {error && <div className="tx">{error}</div>}
      {notice && <div className="tx">{notice}</div>}

      {hash && (
        <div className="tx">
          <a
            href={txUrl(hash)}
            target="_blank"
            rel="noopener noreferrer"
          >
            Xem transaction trên Avalanche Explorer ↗
          </a>
        </div>
      )}
    </div>
  );
}
