"use client";

import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { fuji } from "@/lib/chain";

function shortAddress(value?: string) {
  return value ? `${value.slice(0, 6)}…${value.slice(-4)}` : "";
}

export function WalletButton() {
  const { address, isConnected, chainId } = useAccount();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain, isPending: switching } = useSwitchChain();

  if (!isConnected) {
    const connector = connectors[0];
    return (
      <button
        className="pill"
        disabled={!connector || isPending}
        onClick={() => connector && connect({ connector })}
      >
        {isPending ? "Connecting…" : "Connect wallet"}
      </button>
    );
  }

  if (chainId !== fuji.id) {
    return (
      <button className="pill" disabled={switching} onClick={() => switchChain({ chainId: fuji.id })}>
        {switching ? "Switching…" : "Switch to Fuji"}
      </button>
    );
  }

  return (
    <button className="pill" title="Disconnect wallet" onClick={() => disconnect()}>
      {shortAddress(address)} · Fuji
    </button>
  );
}
