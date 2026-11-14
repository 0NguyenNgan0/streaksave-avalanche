"use client";

import { txUrl } from "@/lib/chain";
import type { Hash } from "viem";

export function TxFeedback({ state, hash, error }: { state: string; hash?: Hash; error?: string }) {
  if (state === "idle") return null;
  return (
    <div className={state === "error" ? "notice warn" : "notice"}>
      <strong>{state === "success" ? "Transaction confirmed ✓" : state.replaceAll("-", " ")}</strong>
      {error && <div className="tx">{error}</div>}
      {hash && (
        <div className="tx">
          <a href={txUrl(hash)} target="_blank" rel="noreferrer">View transaction on Avalanche Explorer ↗</a>
        </div>
      )}
    </div>
  );
}
