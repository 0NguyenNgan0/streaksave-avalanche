import { http, createConfig } from "wagmi";
import { injected } from "wagmi/connectors";
import { fuji } from "./chain";

export const wagmiConfig = createConfig({
  chains: [fuji],
  connectors: [injected()],
  transports: {
    [fuji.id]: http(fuji.rpcUrls.default.http[0]),
  },
  ssr: true,
});
