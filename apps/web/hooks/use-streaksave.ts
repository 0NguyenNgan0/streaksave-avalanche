
"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  formatUnits,
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

import { fuji } from "@/lib/chain";
import { parsePositiveUsdc, USDC_DECIMALS } from "@/lib/amount";
import {
  contractsConfigured,
  erc20Abi,
  STREAK_CONTRACT,
  streakSavingsAbi,
  USDC_CONTRACT,
} from "@/lib/contracts";

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

function toBigInt(value: unknown): bigint {
  if (typeof value === "bigint") return value;
  if (typeof value === "number" && Number.isFinite(value)) {
    return BigInt(Math.floor(value));
  }
  if (typeof value === "string" && value.length > 0) {
    return BigInt(value);
  }
  return 0n;
}

function formatUsdc(value: bigint): string {
  return formatUnits(value, USDC_DECIMALS);
}

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return "Đã xảy ra lỗi không xác định.";
}

export function useStreakSave() {
  const { address, chainId, isConnected } = useAccount();
  const publicClient = usePublicClient({ chainId: fuji.id });
  const { writeContractAsync } = useWriteContract();

  const configured = contractsConfigured;
  const correctChain = chainId === fuji.id;
  const enabled =
    configured && isConnected && !!address && correctChain;

  const contractAddress = STREAK_CONTRACT as Address;
  const tokenAddress = USDC_CONTRACT as Address;
  const userAddress = address ?? zeroAddress;

  const [actionState, setActionState] = useState<ActionState>("idle");
  const [lastHash, setLastHash] = useState<Hash | undefined>();
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const [rewardEpochs, setRewardEpochs] = useState<RewardEpoch[]>([]);
  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState<string | null>(null);
  const [hasOlderRewards, setHasOlderRewards] = useState(false);
  const [olderCursor, setOlderCursor] = useState<bigint | null>(null);

  const inFlight = useRef(false);

  // Contract reads
  const principal = useReadContract({
    address: contractAddress,
    abi: streakSavingsAbi,
    functionName: "principalOf",
    args: [userAddress],
    chainId: fuji.id,
    query: { enabled },
  });

  const effectiveStreak = useReadContract({
    address: contractAddress,
    abi: streakSavingsAbi,
    functionName: "effectiveStreakOf",
    args: [userAddress],
    chainId: fuji.id,
    query: { enabled },
  });

  const reward = useReadContract({
    address: contractAddress,
    abi: streakSavingsAbi,
    functionName: "rewardOf",
    args: [userAddress],
    chainId: fuji.id,
    query: { enabled },
  });

  const balance = useReadContract({
    address: tokenAddress,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [userAddress],
    chainId: fuji.id,
    query: { enabled },
  });

  const allowance = useReadContract({
    address: tokenAddress,
    abi: erc20Abi,
    functionName: "allowance",
    args: [userAddress, contractAddress],
    chainId: fuji.id,
    query: { enabled },
  });

  const currentEpoch = useReadContract({
    address: contractAddress,
    abi: streakSavingsAbi,
    functionName: "currentEpoch",
    chainId: fuji.id,
    query: { enabled },
  });

  const timeUntilNextEpoch = useReadContract({
    address: contractAddress,
    abi: streakSavingsAbi,
    functionName: "timeUntilNextEpoch",
    chainId: fuji.id,
    query: { enabled },
  });

  const principalValue = toBigInt(principal.data);
  const streakValue = toBigInt(effectiveStreak.data);
  const rewardValue = toBigInt(reward.data);
  const balanceValue = toBigInt(balance.data);
  const allowanceValue = toBigInt(allowance.data);
  const epochValue = toBigInt(currentEpoch.data);
  const countdownValue = toBigInt(timeUntilNextEpoch.data);

  const busy =
    actionState === "approving" ||
    actionState === "depositing" ||
    actionState === "claiming" ||
    actionState === "withdrawing";

  // Read pending reward for a specific epoch.
  const scanRange = useCallback(
    async (start: bigint, end: bigint): Promise<RewardEpoch[]> => {
      if (!publicClient || !address || start >= end) return [];

      const found: RewardEpoch[] = [];

      for (
        let batchStart = start;
        batchStart < end;
        batchStart += BigInt(SCAN_BATCH_SIZE)
      ) {
        const batchEnd =
          batchStart + BigInt(SCAN_BATCH_SIZE) < end
            ? batchStart + BigInt(SCAN_BATCH_SIZE)
            : end;

        const epochs: bigint[] = [];

        for (let epoch = batchStart; epoch < batchEnd; epoch++) {
          epochs.push(epoch);
        }

        const results = await Promise.all(
          epochs.map(async (epoch) => {
            const amount = (await publicClient.readContract({
              address: contractAddress,
              abi: streakSavingsAbi,
              functionName: "rewardInEpoch",
              args: [address, epoch],
            })) as bigint;

            return { epoch, amount };
          }),
        );

        found.push(...results.filter((item) => item.amount > 0n));
      }

      return found;
    },
    [publicClient, address, contractAddress],
  );

  // Scan the latest finalized epochs.
  const scanLatest = useCallback(async () => {
    const end = currentEpoch.data as bigint | undefined;

    if (!enabled || end === undefined) return;

    setScanning(true);
    setScanError(null);

    try {
      const start =
        end > BigInt(EPOCH_PAGE_SIZE)
          ? end - BigInt(EPOCH_PAGE_SIZE)
          : 0n;

      const found = await scanRange(start, end);

      setRewardEpochs(
        found.sort((a, b) => (a.epoch > b.epoch ? -1 : 1)),
      );

      setOlderCursor(start);
      setHasOlderRewards(start > 0n);
    } catch (scanFailure) {
      setScanError(getErrorMessage(scanFailure));
    } finally {
      setScanning(false);
    }
  }, [enabled, currentEpoch.data, scanRange]);

  // Load older epochs in pages.
  const loadOlderRewards = useCallback(async () => {
    if (!enabled || olderCursor === null || olderCursor <= 0n) {
      setHasOlderRewards(false);
      return;
    }

    setScanning(true);
    setScanError(null);

    try {
      const end = olderCursor;
      const start =
        end > BigInt(EPOCH_PAGE_SIZE)
          ? end - BigInt(EPOCH_PAGE_SIZE)
          : 0n;

      const found = await scanRange(start, end);

      setRewardEpochs((previous) => {
        const merged = [...previous, ...found];
        const unique = new Map<string, RewardEpoch>();

        for (const item of merged) {
          unique.set(item.epoch.toString(), item);
        }

        return Array.from(unique.values()).sort((a, b) =>
          a.epoch > b.epoch ? -1 : 1,
        );
      });

      setOlderCursor(start);
      setHasOlderRewards(start > 0n);
    } catch (scanFailure) {
      setScanError(getErrorMessage(scanFailure));
    } finally {
      setScanning(false);
    }
  }, [enabled, olderCursor, scanRange]);

  useEffect(() => {
    if (!enabled) {
      setRewardEpochs([]);
      setOlderCursor(null);
      setHasOlderRewards(false);
      return;
    }

    void scanLatest();
  }, [enabled, scanLatest]);

  // Refresh all contract reads and reward history.
  const refetchAll = useCallback(async () => {
    await Promise.allSettled([
      principal.refetch(),
      effectiveStreak.refetch(),
      reward.refetch(),
      balance.refetch(),
      allowance.refetch(),
      currentEpoch.refetch(),
      timeUntilNextEpoch.refetch(),
    ]);

    await scanLatest();
  }, [
    principal,
    effectiveStreak,
    reward,
    balance,
    allowance,
    currentEpoch,
    timeUntilNextEpoch,
    scanLatest,
  ]);

  // Common transaction handler.
  const run = useCallback(
    async (
      nextState: ActionState,
      action: () => Promise<Hash>,
      successMessage: string,
    ) => {
      if (inFlight.current) return;

      if (!configured) {
        setError("Chưa cấu hình địa chỉ smart contract.");
        setActionState("error");
        return;
      }

      if (!isConnected || !address) {
        setError("Vui lòng kết nối ví trước.");
        setActionState("error");
        return;
      }

      if (!correctChain) {
        setError("Vui lòng chuyển ví sang Avalanche Fuji Testnet.");
        setActionState("error");
        return;
      }

      if (!publicClient) {
        setError("Không thể kết nối Fuji RPC.");
        setActionState("error");
        return;
      }

      inFlight.current = true;
      setActionState(nextState);
      setError(null);
      setNotice(null);
      setLastHash(undefined);

      try {
        const hash = await action();
        setLastHash(hash);

        const receipt = await publicClient.waitForTransactionReceipt({
          hash,
        });

        if (receipt.status !== "success") {
          throw new Error("Giao dịch thất bại trên blockchain.");
        }

        setActionState("success");
        setNotice(successMessage);

        await refetchAll();
      } catch (transactionError) {
        setActionState("error");
        setError(getErrorMessage(transactionError));
      } finally {
        inFlight.current = false;
      }
    },
    [
      configured,
      isConnected,
      address,
      correctChain,
      publicClient,
      refetchAll,
    ],
  );

  const getAmount = useCallback((amount: string): bigint => {
    const parsed = parsePositiveUsdc(amount);

    if (typeof parsed !== "bigint" || parsed <= 0n) {
      throw new Error("Số tiền USDC không hợp lệ.");
    }

    return parsed;
  }, []);

  // Approve USDC spending.
  const approve = useCallback(
    async (amount: string) => {
      let parsedAmount: bigint;

      try {
        parsedAmount = getAmount(amount);
      } catch (amountError) {
        setError(getErrorMessage(amountError));
        setActionState("error");
        return;
      }

      await run(
        "approving",
        () =>
          writeContractAsync({
            address: tokenAddress,
            abi: erc20Abi,
            functionName: "approve",
            args: [contractAddress, parsedAmount],
            chainId: fuji.id,
          }),
        "Approve USDC thành công.",
      );
    },
    [getAmount, run, writeContractAsync, tokenAddress, contractAddress],
  );

  // Deposit USDC.
  const deposit = useCallback(
    async (amount: string) => {
      let parsedAmount: bigint;

      try {
        parsedAmount = getAmount(amount);

        if (parsedAmount > balanceValue) {
          throw new Error("Số dư USDC không đủ.");
        }

        if (parsedAmount > allowanceValue) {
          throw new Error("Allowance chưa đủ. Hãy approve USDC trước.");
        }
      } catch (amountError) {
        setError(getErrorMessage(amountError));
        setActionState("error");
        return;
      }

      await run(
        "depositing",
        () =>
          writeContractAsync({
            address: contractAddress,
            abi: streakSavingsAbi,
            functionName: "deposit",
            args: [parsedAmount],
            chainId: fuji.id,
          }),
        "Deposit USDC thành công.",
      );
    },
    [
      getAmount,
      balanceValue,
      allowanceValue,
      run,
      writeContractAsync,
      contractAddress,
    ],
  );

  // Claim the latest finalized epoch.
  const claimReward = useCallback(async () => {
    await run(
      "claiming",
      () =>
        writeContractAsync({
          address: contractAddress,
          abi: streakSavingsAbi,
          functionName: "claimReward",
          args: [],
          chainId: fuji.id,
        }),
      "Claim reward thành công.",
    );
  }, [run, writeContractAsync, contractAddress]);

  // Claim a specific finalized epoch.
  const claimRewardFor = useCallback(
    async (epoch: bigint) => {
      await run(
        "claiming",
        () =>
          writeContractAsync({
            address: contractAddress,
            abi: streakSavingsAbi,
            functionName: "claimRewardFor",
            args: [epoch],
            chainId: fuji.id,
          }),
        `Claim reward epoch ${epoch.toString()} thành công.`,
      );
    },
    [run, writeContractAsync, contractAddress],
  );

  // Withdraw principal.
  const withdraw = useCallback(
    async (amount: string) => {
      let parsedAmount: bigint;

      try {
        parsedAmount = getAmount(amount);

        if (parsedAmount > principalValue) {
          throw new Error("Số tiền rút vượt quá principal hiện tại.");
        }
      } catch (amountError) {
        setError(getErrorMessage(amountError));
        setActionState("error");
        return;
      }

      await run(
        "withdrawing",
        () =>
          writeContractAsync({
            address: contractAddress,
            abi: streakSavingsAbi,
            functionName: "withdraw",
            args: [parsedAmount],
            chainId: fuji.id,
          }),
        "Withdraw USDC thành công.",
      );
    },
    [
      getAmount,
      principalValue,
      run,
      writeContractAsync,
      contractAddress,
    ],
  );

  const totalClaimable = useMemo(
    () => rewardEpochs.reduce((sum, item) => sum + item.amount, 0n),
    [rewardEpochs],
  );

  const values = useMemo(
    () => ({
      principal: formatUsdc(principalValue),
      streak: streakValue.toString(),
      reward: formatUsdc(rewardValue),
      balance: formatUsdc(balanceValue),
      epoch: epochValue.toString(),
      epochCountdown: countdownValue.toString(),
    }),
    [
      principalValue,
      streakValue,
      rewardValue,
      balanceValue,
      epochValue,
      countdownValue,
    ],
  );

  const raw = useMemo(
    () => ({
      principal: principalValue,
      reward: rewardValue,
      allowance: allowanceValue,
      balance: balanceValue,
      effectiveStreak: streakValue,
      currentEpoch: epochValue,
      secondsUntilNextEpoch: countdownValue,
      totalClaimable,
    }),
    [
      principalValue,
      rewardValue,
      allowanceValue,
      balanceValue,
      streakValue,
      epochValue,
      countdownValue,
      totalClaimable,
    ],
  );

  return {
    configured,
    address,
    isConnected,
    correctChain,
    busy,
    actionState,
    lastHash,
    error,
    notice,

    values,
    raw,

    rewardEpochs,
    scanning,
    scanError,
    hasOlderRewards,

    approve,
    deposit,
    claimReward,
    claimRewardFor,
    withdraw,

    loadOlderRewards,
    refresh: refetchAll,
  };
}
