"use client";

import { useMemo, useRef, useState } from "react";
import { formatUnits, zeroAddress, type Address, type Hash } from "viem";
import { useAccount, usePublicClient, useReadContract, useWriteContract } from "wagmi";
import { fuji } from "@/lib/chain";
import { parsePositiveUsdc, USDC_DECIMALS } from "@/lib/amount";
import { contractsConfigured, erc20Abi, STREAK_CONTRACT, streakSavingsAbi, USDC_CONTRACT } from "@/lib/contracts";

type ActionState = "idle" | "approving" | "depositing" | "claiming" | "withdrawing" | "success" | "error";

function formatUsdc(value?: bigint) {
  if (value === undefined) return "—";
  return Number(formatUnits(value, USDC_DECIMALS)).toLocaleString(undefined, { maximumFractionDigits: 6 });
}

function formatCountdown(value?: bigint) {
  if (value === undefined) return "—";
  const t = Number(value);
  const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
  return h > 0 ? `${h}h ${String(m).padStart(2, "0")}m` : `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

export function useStreakSave() {
  const { address, chainId } = useAccount();
  const publicClient = usePublicClient({ chainId: fuji.id });
  const { writeContractAsync } = useWriteContract();
  const inFlight = useRef(false);
  const [actionState, setActionState] = useState<ActionState>("idle");
  const [lastHash, setLastHash] = useState<Hash>();
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const correctChain = chainId === fuji.id;
  const enabled = Boolean(address && contractsConfigured && correctChain);
  const contractEnabled = Boolean(contractsConfigured);
  const user = address ?? zeroAddress;
  const streakAddress = STREAK_CONTRACT ?? zeroAddress;
  const usdcAddress = USDC_CONTRACT ?? zeroAddress;

  const principal = useReadContract({ address: streakAddress, abi: streakSavingsAbi, functionName: "principalOf", args: [user], query: { enabled } });
  const streak = useReadContract({ address: streakAddress, abi: streakSavingsAbi, functionName: "effectiveStreakOf", args: [user], query: { enabled } });
  const reward = useReadContract({ address: streakAddress, abi: streakSavingsAbi, functionName: "rewardOf", args: [user], query: { enabled } });
  const balance = useReadContract({ address: usdcAddress, abi: erc20Abi, functionName: "balanceOf", args: [user], query: { enabled } });
  const allowance = useReadContract({ address: usdcAddress, abi: erc20Abi, functionName: "allowance", args: [user, streakAddress], query: { enabled } });
  const epoch = useReadContract({ address: streakAddress, abi: streakSavingsAbi, functionName: "currentEpoch", query: { enabled: contractEnabled, refetchInterval: 10_000 } });
  const countdown = useReadContract({ address: streakAddress, abi: streakSavingsAbi, functionName: "timeUntilNextEpoch", query: { enabled: contractEnabled, refetchInterval: 10_000 } });

  async function wait(hash: Hash) {
    setLastHash(hash);
    if (!publicClient) throw new Error("Không thể kết nối Avalanche Fuji RPC.");
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== "success") throw new Error("Giao dịch đã bị revert trên chain.");
  }
  async function refetchAll() {
    const results = await Promise.allSettled([
      principal.refetch(), streak.refetch(), reward.refetch(), balance.refetch(), allowance.refetch(), epoch.refetch(), countdown.refetch(),
    ]);
    if (results.some((r) => r.status === "rejected" || (r.status === "fulfilled" && r.value.isError))) {
      setNotice("Giao dịch đã được xác nhận. Một số dữ liệu chưa tải lại được; hãy refresh trang để đồng bộ.");
    }
  }
  function guard() {
    if (!address) throw new Error("Vui lòng kết nối ví trước.");
    if (!correctChain) throw new Error("Vui lòng chuyển ví sang Avalanche Fuji (chain ID 43113).");
    if (!contractsConfigured || !STREAK_CONTRACT || !USDC_CONTRACT) throw new Error("Chưa cấu hình đúng địa chỉ contract Fuji.");
    if (!publicClient) throw new Error("Fuji RPC hiện không khả dụng.");
  }
  function validAmount(value: string, available?: bigint) {
    const raw = parsePositiveUsdc(value);
    if (raw === undefined) throw new Error("Số USDC không hợp lệ (tối đa 6 chữ số thập phân).");
    if (available !== undefined && raw > available) throw new Error("Số tiền vượt quá số dư khả dụng.");
    return raw;
  }
  async function run(state: ActionState, fn: () => Promise<void>) {
    if (inFlight.current) return; // synchronous ref lock: blocks rapid duplicate submits
    inFlight.current = true;
    setError(undefined);
    setNotice(undefined);
    setLastHash(undefined);
    setActionState(state);
    try {
      guard();
      await fn();
      setActionState("success"); // receipt success must not turn into a transaction failure on refetch error
      await refetchAll();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Giao dịch thất bại.");
      setActionState("error");
    } finally {
      inFlight.current = false;
    }
  }
  async function approve(amount: string) {
    await run("approving", async () => {
      const raw = validAmount(amount, balance.data as bigint | undefined);
      const hash = await writeContractAsync({ chainId: fuji.id, address: USDC_CONTRACT as Address, abi: erc20Abi, functionName: "approve", args: [STREAK_CONTRACT as Address, raw] });
      await wait(hash);
    });
  }
  async function deposit(amount: string) {
    await run("depositing", async () => {
      const raw = validAmount(amount, balance.data as bigint | undefined);
      if (raw > ((allowance.data as bigint | undefined) ?? 0n)) throw new Error("Cần approve đủ USDC trước khi deposit.");
      const hash = await writeContractAsync({ chainId: fuji.id, address: STREAK_CONTRACT as Address, abi: streakSavingsAbi, functionName: "deposit", args: [raw] });
      await wait(hash);
    });
  }
  async function claimReward() {
    await run("claiming", async () => {
      if (((reward.data as bigint | undefined) ?? 0n) === 0n) throw new Error("Chưa có reward khả dụng từ epoch đã kết thúc.");
      const hash = await writeContractAsync({ chainId: fuji.id, address: STREAK_CONTRACT as Address, abi: streakSavingsAbi, functionName: "claimReward" });
      await wait(hash);
    });
  }
  async function withdraw(amount: string) {
    await run("withdrawing", async () => {
      const raw = validAmount(amount, principal.data as bigint | undefined);
      const hash = await writeContractAsync({ chainId: fuji.id, address: STREAK_CONTRACT as Address, abi: streakSavingsAbi, functionName: "withdraw", args: [raw] });
      await wait(hash);
    });
  }

  const rawAllowance = (allowance.data as bigint | undefined) ?? 0n;
  const rawPrincipal = (principal.data as bigint | undefined) ?? 0n;
  const rawReward = (reward.data as bigint | undefined) ?? 0n;
  const rawStreak = streak.data as bigint | undefined;
  const rawEpoch = epoch.data as bigint | undefined;
  const rawCountdown = countdown.data as bigint | undefined;
  const values = useMemo(() => ({
    principal: formatUsdc(rawPrincipal),
    streak: rawStreak === undefined ? "—" : rawStreak.toString(),
    reward: formatUsdc(rawReward),
    balance: formatUsdc(balance.data as bigint | undefined),
    epoch: rawEpoch === undefined ? "—" : rawEpoch.toString(),
    epochCountdown: formatCountdown(rawCountdown),
    rawAllowance,
  }), [rawPrincipal, rawStreak, rawReward, balance.data, rawEpoch, rawCountdown, rawAllowance]);
  const busy = ["approving", "depositing", "claiming", "withdrawing"].includes(actionState);
  return {
    configured: contractsConfigured, correctChain, address, actionState, busy, lastHash, error, notice, values,
    raw: { principal: rawPrincipal, reward: rawReward, allowance: rawAllowance, balance: (balance.data as bigint | undefined) ?? 0n, effectiveStreak: rawStreak ?? 0n, currentEpoch: rawEpoch ?? 0n, secondsUntilNextEpoch: rawCountdown ?? 0n },
    approve, deposit, claimReward, withdraw, refresh: refetchAll,
  };
}
