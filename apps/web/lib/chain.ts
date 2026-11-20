import { defineChain } from "viem";

const fujiRpcUrl =
  process.env.NEXT_PUBLIC_FUJI_RPC_URL?.trim() ||
  "https://api.avax-test.network/ext/bc/C/rpc";

export const fuji = defineChain({
  id: 43113,
  name: "Avalanche Fuji C-Chain",
  nativeCurrency: { name: "Avalanche", symbol: "AVAX", decimals: 18 },
  rpcUrls: {
    default: {
      http: [fujiRpcUrl],
    },
  },
  blockExplorers: {
    default: {
      name: "Avalanche Explorer",
      url: "https://explorer-test.avax.network/c-chain",
    },
  },
  testnet: true,
});

export function txUrl(hash: string) {
  return `${fuji.blockExplorers.default.url}/tx/${hash}`;
}
