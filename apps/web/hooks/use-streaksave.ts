
"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  formatUnits,
  parseUnits,
  zeroAddress,
  type Address,
  type Hash,
} from "viem";
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useWriteContract,
} from "wagmi";
import {
  contractsConfigured,
  erc20Abi,
  STREAK_CONTRACT,
  streakSavingsAbi,
  USDC_CONTRACT,
} from "@/lib/contracts";

const USDC_DECIMALS = 6;
const EPOCH_PAGE_SIZE = 50;
const SCAN_BATCH_SIZE = 10;

type ActionState =
  | "idle"
  | "approving"
  | "depositing"
  | "claiming"
  | "withdrawing"
  | "success"
  | "error";

export type RewardEpoch = {
  epoch: bigint;
  amount: bigint;
};

function formatUsdc(value?: bigint) {
  if (value === undefined) return "—";

  const n = Number(formatUnits(value, USDC_DECIMALS));
  return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
}

export function useStreakSave() {
  const { address } = useAccount();
  const publicClient = usePublicClient();
  const { writeContractAsync } = useWriteContract();

  const [actionState, setActionState] = useState<ActionState>("idle");
  const [lastHash, setLastHash] = useState<Hash>();
  const [error, setError] = useState<string>();

  const [rewardEpochs, setRewardEpochs] = useState<RewardEpoch[]>([]);
  const [scanBefore, setScanBefore] = useState<bigint | null>(null);
  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState<string>();

  const enabled = Boolean(address && contractsConfigured);
  const user = address ?? zeroAddress;
  const streakAddress = STREAK_CONTRACT ?? zeroAddress;
  const usdcAddress = USDC_CONTRACT ?? zeroAddress;

  const principal = useReadContract({
    address: streakAddress,
    abi: streakSavingsAbi,
    functionName: "principalOf",
    args: [user],
    query: { enabled },
  });

  const streak = useReadContract({
    address: streakAddress,
    abi: streakSavingsAbi,
    functionName: "streakOf",
    args: [user],
    query: { enabled },
  });

  const reward = useReadContract({
    address: streakAddress,
    abi: streakSavingsAbi,
    functionName: "rewardOf",
    args: [user],
    query: { enabled },
  });

  const currentEpoch = useReadContract({
    address: streakAddress,
    abi: streakSavingsAbi,
    functionName: "currentEpoch",
    query: { enabled },
  });

  const balance = useReadContract({
    address: usdcAddress,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [user],
    query: { enabled },
  });

  const allowance = useReadContract({
    address: usdcAddress,
    abi: erc20Abi,
    functionName: "allowance",
    args: [user, streakAddress],
    query: { enabled },
  });

  // Read rewards in small batches to avoid overwhelming the RPC.
  const scanRange = useCallback(
    async (from: bigint, to: bigint): Promise<RewardEpoch[]> => {
      const contractAddress = STREAK_CONTRACT;

      if (!publicClient || !address || !contractAddress) {
        return [];
      }

      const found: RewardEpoch[] = [];

      for (
        let batchStart = from;
        batchStart < to;
        batchStart += BigInt(SCAN_BATCH_SIZE)
      ) {
        const batchEnd =
          batchStart + BigInt(SCAN_BATCH_SIZE) < to
            ? batchStart + BigInt(SCAN_BATCH_SIZE)
            : to;

        const epochs: bigint[] = [];

        for (let epoch = batchStart; epoch < batchEnd; epoch++) {
          epochs.push(epoch);
        }

        const results = await Promise.all(
          epochs.map(async (epoch) => {
            const amount = await publicClient.readContract({
              address: contractAddress,
              abi: streakSavingsAbi,
              functionName: "rewardInEpoch",
              args: [address, epoch],
            });

            return { epoch, amount };
          }),
        );

        found.push(...results.filter((item) => item.amount > 0n));
      }

      return found;
    },
    [publicClient, address],
  );

  // Scan the latest 50 finalized epochs.
  const scanLatest = useCallback(async () => {
    if (!enabled || currentEpoch.data === undefined) return;

    setScanning(true);
    setScanError(undefined);

    try {
      const end = currentEpoch.data;

      const start =
        end > BigInt(EPOCH_PAGE_SIZE)
          ? end - BigInt(EPOCH_PAGE_SIZE)
          : 0n;

      const found = await scanRange(start, end);

      setRewardEpochs(found);
      setScanBefore(start > 0n ? start : 0n);
    } catch (e) {
      setScanError(
        e instanceof Error ? e.message : "Could not load reward epochs.",
      );
    } finally {
      setScanning(false);
    }
  }, [enabled, currentEpoch.data, scanRange]);

  // Load another 50 older epochs.
  const loadOlderRewards = useCallback(async () => {
    if (scanBefore === null || scanBefore === 0n || scanning) return;

    setScanning(true);
    setScanError(undefined);

    try {
      const end = scanBefore;

      const start =
        end > BigInt(EPOCH_PAGE_SIZE)
          ? end - BigInt(EPOCH_PAGE_SIZE)
          : 0n;

      const found = await scanRange(start, end);

      setRewardEpochs((previous) => {
        const merged = [...previous, ...found];

        const unique = new Map(
          merged.map((item) => [item.epoch.toString(), item]),
        );

        return [...unique.values()].sort((a, b) =>
          a.epoch > b.epoch ? -1 : a.epoch < b.epoch ? 1 : 0,
        );
      });

      setScanBefore(start);
    } catch (e) {
      setScanError(
        e instanceof Error ? e.message : "Could not load older rewards.",
      );
    } finally {
      setScanning(false);
    }
  }, [scanBefore, scanning, scanRange]);

  // Reset and scan when the connected wallet or current epoch changes.
  useEffect(() => {
    setRewardEpochs([]);
    setScanBefore(null);

    if (enabled && currentEpoch.data !== undefined) {
      void scanLatest();
    }
  }, [enabled, address, currentEpoch.data, scanLatest]);

  async function wait(hash: Hash) {
    setLastHash(hash);

    if (!publicClient) {
      throw new Error("Fuji public client is unavailable.");
    }

    const receipt = await publicClient.waitForTransactionReceipt({ hash });

    if (receipt.status !== "success") {
      throw new Error("Transaction reverted.");
    }
  }

  async function refetchAll() {
    await Promise.all([
      principal.refetch(),
      streak.refetch(),
      reward.refetch(),
      currentEpoch.refetch(),
      balance.refetch(),
      allowance.refetch(),
    ]);

    await scanLatest();
  }

  function guard() {
    if (!address) {
      throw new Error("Connect your wallet first.");
    }

    if (!contractsConfigured || !STREAK_CONTRACT || !USDC_CONTRACT) {
      throw new Error("Contract addresses are not configured yet.");
    }
  }

  async function run(state: ActionState, fn: () => Promise<void>) {
    try {
      setError(undefined);
      setActionState(state);

      await fn();
      await refetchAll();

      setActionState("success");
    } catch (e) {
      const message =
        e instanceof Error ? e.message : "Transaction failed.";

      setError(message);
      setActionState("error");
    }
  }

  async function approve(amount: string) {
    await run("approving", async () => {
      guard();

      const raw = parseUnits(amount, USDC_DECIMALS);

      const hash = await writeContractAsync({
        address: USDC_CONTRACT as Address,
        abi: erc20Abi,
        functionName: "approve",
        args: [STREAK_CONTRACT as Address, raw],
      });

      await wait(hash);
    });
  }

  async function deposit(amount: string) {
    await run("depositing", async () => {
      guard();

      const raw = parseUnits(amount, USDC_DECIMALS);

      const hash = await writeContractAsync({
        address: STREAK_CONTRACT as Address,
        abi: streakSavingsAbi,
        functionName: "deposit",
        args: [raw],
      });

      await wait(hash);
    });
  }

  async function claimReward() {
    await run("claiming", async () => {
      guard();

      const hash = await writeContractAsync({
        address: STREAK_CONTRACT as Address,
        abi: streakSavingsAbi,
        functionName: "claimReward",
      });

      await wait(hash);
    });
  }

  async function claimRewardFor(epoch: bigint) {
    await run("claiming", async () => {
      guard();

      const hash = await writeContractAsync({
        address: STREAK_CONTRACT as Address,
        abi: streakSavingsAbi,
        functionName: "claimRewardFor",
        args: [epoch],
      });

      await wait(hash);
    });
  }

  async function withdraw(amount: string) {
    await run("withdrawing", async () => {
      guard();

      const raw = parseUnits(amount, USDC_DECIMALS);

      const hash = await writeContractAsync({
        address: STREAK_CONTRACT as Address,
        abi: streakSavingsAbi,
        functionName: "withdraw",
        args: [raw],
      });

      await wait(hash);
    });
  }

  const rawAllowance = allowance.data ?? 0n;

  const values = useMemo(
    () => ({
      principal: formatUsdc(principal.data),
      streak: streak.data === undefined ? "—" : streak.data.toString(),
      reward: formatUsdc(reward.data),
      balance: formatUsdc(balance.data),
      rawAllowance,
    }),
    [principal.data, streak.data, reward.data, balance.data, rawAllowance],
  );

  const totalClaimable = rewardEpochs.reduce(
    (total, item) => total + item.amount,
    0n,
  );

  return {
    configured: contractsConfigured,
    address,
    actionState,
    lastHash,
    error,
    values,
    raw: {
      principal: principal.data ?? 0n,
      reward: reward.data ?? 0n,
      allowance: rawAllowance,
      totalClaimable,
    },
    rewardEpochs,
    scanning,
    scanError,
    hasOlderRewards: scanBefore !== null && scanBefore > 0n,
    loadOlderRewards,
    scanLatest,
    approve,
    deposit,
    claimReward,
    claimRewardFor,
    withdraw,
    refresh: refetchAll,
  };
}
