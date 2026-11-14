"use client";

import { useStreakSave } from "@/hooks/use-streaksave";

export function ContractStatus() {
  const { configured } = useStreakSave();
  if (configured) return <div className="notice good">Fuji contracts configured ✓</div>;
  return (
    <div className="notice warn">
      UI preview mode. Add NEXT_PUBLIC_STREAK_CONTRACT and NEXT_PUBLIC_USDC_CONTRACT to .env.local to enable real Fuji actions.
    </div>
  );
}
