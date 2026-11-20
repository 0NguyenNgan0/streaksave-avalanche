
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
  if (typeof error === "object" && error !== null) {
    const shortMessage = (error as { shortMessage?: unknown }).shortMessage;

    if (typeof shortMessage === "string" && shortMessage.length > 0) {
      return shortMessage;
    }
  }

  if (error instanceof Error) return error.message;
  return "Đã xảy ra lỗi không xác định.";
}

export function useStreakSave(options: { scanRewards?: boolean } = {}) {
  const { address, chainId, isConnected } = useAccount();
  const publicClient = usePublicClient({ chainId: fuji.id });
  const { writeContractAsync } = useWriteContract();

  const configured = contractsConfigured;
  const correctChain = chainId === fuji.id;
  const enabled =
    configured && isConnected && !!address && correctChain;
  const scanRewards = options.scanRewards ?? true;
  const rewardsEnabled = enabled && scanRewards;

  const contractAddress = STREAK_CONTRACT as Address;
  const tokenAddress = USDC_CONTRACT as Address;
  const userAddress = address ?? zeroAddress;

  const [actionState, setActionState] = useState<ActionState>("idle");
  const [lastHash, setLastHash] = useState<Hash | undefined>();
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const [clock, setClock] = useState(0);
  const [countdownAnchor, setCountdownAnchor] = useState<{
    seconds: bigint;
    at: number;
  } | null>(null);

  const [rewardEpochs, setRewardEpochs] = useState<RewardEpoch[]>([]);
  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState<string | null>(null);
  const [hasScanned, setHasScanned] = useState(false);
  const [hasOlderRewards, setHasOlderRewards] = useState(false);
  const [olderCursor, setOlderCursor] = useState<bigint | null>(null);

  const inFlight = useRef(false);
  const scanRequestId = useRef(0);

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
    query: { enabled, refetchInterval: 10_000 },
  });

  const reward = useReadContract({
    address: contractAddress,
    abi: streakSavingsAbi,
    functionName: "rewardOf",
    args: [userAddress],
    chainId: fuji.id,
    query: { enabled, refetchInterval: 15_000 },
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
    query: { enabled, refetchInterval: 5_000 },
  });

  const timeUntilNextEpoch = useReadContract({
    address: contractAddress,
    abi: streakSavingsAbi,
    functionName: "timeUntilNextEpoch",
    chainId: fuji.id,
    query: { enabled, refetchInterval: 5_000 },
  });

  const principalValue = toBigInt(principal.data);
  const streakValue = toBigInt(effectiveStreak.data);
  const rewardValue = toBigInt(reward.data);
  const balanceValue = toBigInt(balance.data);
  const allowanceValue = toBigInt(allowance.data);
  const epochValue = toBigInt(currentEpoch.data);
  const countdownData =
    timeUntilNextEpoch.data === undefined || timeUntilNextEpoch.data === null
      ? undefined
      : toBigInt(timeUntilNextEpoch.data);

  useEffect(() => {
    if (!enabled || countdownData === undefined) {
      setCountdownAnchor(null);
      return;
    }

    setCountdownAnchor({ seconds: countdownData, at: Date.now() });
  }, [enabled, countdownData]);

  useEffect(() => {
    if (!enabled) {
      setClock(0);
      return;
    }

    setClock(Date.now());
    const timer = window.setInterval(() => setClock(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [enabled]);

  const countdownValue = useMemo(() => {
    if (!enabled || countdownData === undefined) return undefined;
    if (!countdownAnchor || clock === 0) return countdownData;

    const elapsed = BigInt(
      Math.max(0, Math.floor((clock - countdownAnchor.at) / 1000)),
    );

    return countdownAnchor.seconds > elapsed
      ? countdownAnchor.seconds - elapsed
      : 0n;
  }, [enabled, countdownData, countdownAnchor, clock]);

  const readResults = [
    principal,
    effectiveStreak,
    reward,
    balance,
    allowance,
    currentEpoch,
    timeUntilNextEpoch,
  ];
  const readsReady =
    enabled && readResults.every((result) => result.isSuccess);
  const readsLoading =
    enabled && readResults.some((result) => result.isPending);

  const readError = useMemo(() => {
    if (!enabled) return null;

    const failures: Array<[string, unknown]> = [
      ["principal", principal.error],
      ["streak", effectiveStreak.error],
      ["reward gần nhất", reward.error],
      ["số dư USDC", balance.error],
      ["allowance USDC", allowance.error],
      ["epoch hiện tại", currentEpoch.error],
      ["countdown", timeUntilNextEpoch.error],
    ];
    const failed = failures.find(([, value]) => Boolean(value));

    return failed
      ? `Không đọc được ${failed[0]} từ Fuji RPC: ${getErrorMessage(failed[1])}`
      : null;
  }, [
    enabled,
    principal.error,
    effectiveStreak.error,
    reward.error,
    balance.error,
    allowance.error,
    currentEpoch.error,
    timeUntilNextEpoch.error,
  ]);

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

  // Scan the latest finalized epochs. Read the boundary fresh so a stale React
  // Query value can never make the UI skip a newly finalized epoch.
  const scanLatest = useCallback(async () => {
    if (!rewardsEnabled || !publicClient || !address) return;

    const requestId = ++scanRequestId.current;

    setScanning(true);
    setScanError(null);
    setHasScanned(false);

    try {
      const latestEpoch = (await publicClient.readContract({
        address: contractAddress,
        abi: streakSavingsAbi,
        functionName: "currentEpoch",
      })) as bigint;

      if (requestId !== scanRequestId.current) return;

      const start =
        latestEpoch > BigInt(EPOCH_PAGE_SIZE)
          ? latestEpoch - BigInt(EPOCH_PAGE_SIZE)
          : 0n;

      const found = await scanRange(start, latestEpoch);

      if (requestId !== scanRequestId.current) return;

      setRewardEpochs(
        found.sort((a, b) => (a.epoch > b.epoch ? -1 : 1)),
      );

      setOlderCursor(start);
      setHasOlderRewards(start > 0n);
      setHasScanned(true);
    } catch (scanFailure) {
      if (requestId !== scanRequestId.current) return;

      setRewardEpochs([]);
      setOlderCursor(null);
      setHasOlderRewards(false);
      setHasScanned(false);
      setScanError(getErrorMessage(scanFailure));
    } finally {
      if (requestId === scanRequestId.current) {
        setScanning(false);
      }
    }
  }, [
    rewardsEnabled,
    publicClient,
    address,
    contractAddress,
    scanRange,
  ]);

  // Load older epochs in pages.
  const loadOlderRewards = useCallback(async () => {
    if (
      !rewardsEnabled ||
      !publicClient ||
      !address ||
      olderCursor === null ||
      olderCursor <= 0n
    ) {
      setHasOlderRewards(false);
      return;
    }

    const requestId = ++scanRequestId.current;

    setScanning(true);
    setScanError(null);

    try {
      const end = olderCursor;
      const start =
        end > BigInt(EPOCH_PAGE_SIZE)
          ? end - BigInt(EPOCH_PAGE_SIZE)
          : 0n;

      const found = await scanRange(start, end);

      if (requestId !== scanRequestId.current) return;

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
      if (requestId !== scanRequestId.current) return;
      setScanError(getErrorMessage(scanFailure));
    } finally {
      if (requestId === scanRequestId.current) {
        setScanning(false);
      }
    }
  }, [
    rewardsEnabled,
    publicClient,
    address,
    olderCursor,
    scanRange,
  ]);

  // Never leave another account's rewards on screen while a new scan runs.
  useEffect(() => {
    scanRequestId.current += 1;
    setRewardEpochs([]);
    setOlderCursor(null);
    setHasOlderRewards(false);
    setHasScanned(false);
    setScanError(null);
  }, [address]);

  useEffect(() => {
    if (!rewardsEnabled) {
      scanRequestId.current += 1;
      setRewardEpochs([]);
      setOlderCursor(null);
      setHasOlderRewards(false);
      setHasScanned(false);
      setScanError(null);
      setScanning(false);
      return;
    }

    void scanLatest();
  }, [rewardsEnabled, scanLatest]);

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
      principal:
        enabled && principal.data !== undefined
          ? formatUsdc(principalValue)
          : "—",
      streak:
        enabled && effectiveStreak.data !== undefined
          ? streakValue.toString()
          : "—",
      reward:
        enabled && reward.data !== undefined ? formatUsdc(rewardValue) : "—",
      balance:
        enabled && balance.data !== undefined ? formatUsdc(balanceValue) : "—",
      epoch:
        enabled && currentEpoch.data !== undefined
          ? epochValue.toString()
          : "—",
      epochCountdown:
        enabled && countdownValue !== undefined
          ? countdownValue.toString()
          : "—",
    }),
    [
      enabled,
      principal.data,
      effectiveStreak.data,
      reward.data,
      balance.data,
      currentEpoch.data,
      countdownValue,
      principalValue,
      streakValue,
      rewardValue,
      balanceValue,
      epochValue,
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
      secondsUntilNextEpoch: countdownValue ?? 0n,
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
    readsReady,
    readsLoading,
    readError,

    rewardEpochs,
    scanning,
    scanError,
    hasScanned,
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
