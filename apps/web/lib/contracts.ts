import { getAddress, isAddress, type Abi, type Address } from "viem";
import streakSavingsAbiJson from "./abi/StreakSavings.json";
import mockUsdcAbiJson from "./abi/MockUSDC.json";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

function configuredAddress(value: string | undefined): Address | undefined {
  const candidate = value?.trim();

  // Accept any valid hex address, even when its casing is not an EIP-55 checksum.
  // Environment values are frequently copied in lowercase from explorers; rejecting
  // them would silently disable every contract read. Normalize before use instead.
  if (!candidate || !isAddress(candidate, { strict: false })) {
    return undefined;
  }

  const normalized = getAddress(candidate);
  return normalized === ZERO_ADDRESS ? undefined : normalized;
}

export const STREAK_CONTRACT = configuredAddress(process.env.NEXT_PUBLIC_STREAK_CONTRACT);
export const USDC_CONTRACT = configuredAddress(process.env.NEXT_PUBLIC_USDC_CONTRACT);
export const contractsConfigured = Boolean(STREAK_CONTRACT && USDC_CONTRACT && STREAK_CONTRACT !== USDC_CONTRACT);

// ABI files are copied from shared/abi by the existing integration workflow.
export const streakSavingsAbi = streakSavingsAbiJson as Abi;
export const erc20Abi = mockUsdcAbiJson as Abi;
