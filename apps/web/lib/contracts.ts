import type { Abi, Address } from "viem";
import streakSavingsAbiJson from "./abi/StreakSavings.json";
import mockUsdcAbiJson from "./abi/MockUSDC.json";

export const STREAK_CONTRACT = process.env.NEXT_PUBLIC_STREAK_CONTRACT as Address | undefined;
export const USDC_CONTRACT = process.env.NEXT_PUBLIC_USDC_CONTRACT as Address | undefined;
export const contractsConfigured = Boolean(STREAK_CONTRACT && USDC_CONTRACT);

// Synced from Member A exported ABI.
export const streakSavingsAbi = streakSavingsAbiJson as Abi;
export const erc20Abi = mockUsdcAbiJson as Abi;
