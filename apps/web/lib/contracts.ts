import { isAddress, type Abi, type Address } from "viem";
import streakSavingsAbiJson from "./abi/StreakSavings.json";
import mockUsdcAbiJson from "./abi/MockUSDC.json";

function configuredAddress(value: string | undefined): Address | undefined {
  return value && isAddress(value) && value !== "0x0000000000000000000000000000000000000000"
    ? (value as Address)
    : undefined;
}

export const STREAK_CONTRACT = configuredAddress(process.env.NEXT_PUBLIC_STREAK_CONTRACT);
export const USDC_CONTRACT = configuredAddress(process.env.NEXT_PUBLIC_USDC_CONTRACT);
export const contractsConfigured = Boolean(STREAK_CONTRACT && USDC_CONTRACT && STREAK_CONTRACT !== USDC_CONTRACT);

// ABI files are copied from shared/abi by the existing integration workflow.
export const streakSavingsAbi = streakSavingsAbiJson as Abi;
export const erc20Abi = mockUsdcAbiJson as Abi;
