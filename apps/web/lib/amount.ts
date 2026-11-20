import { parseUnits } from "viem";

export const USDC_DECIMALS = 6;

/** Only plain positive USDC decimal strings with at most six fractional digits. */
export function parsePositiveUsdc(input: string): bigint | undefined {
  const value = input.trim();
  if (!/^(?:\d+)(?:\.\d{1,6})?$/.test(value)) return undefined;
  try {
    const amount = parseUnits(value, USDC_DECIMALS);
    return amount > 0n ? amount : undefined;
  } catch {
    return undefined;
  }
}

export function usdcAmountError(input: string, available?: bigint): string | undefined {
  const amount = parsePositiveUsdc(input);
  if (amount === undefined) return "Nhập số USDC lớn hơn 0, tối đa 6 chữ số thập phân.";
  if (available !== undefined && amount > available) return "Số tiền vượt quá số dư khả dụng.";
  return undefined;
}
