import { http, createConfig } from "wagmi";
import { injected } from "wagmi/connectors";
import { fuji } from "./chain";

export const wagmiConfig = createConfig({
  chains: [fuji],
  connectors: [injected()],
  transports: {
    [fuji.id]: http(process.env.NEXT_PUBLIC_FUJI_RPC_URL),
  },
  ssr: true,
});
