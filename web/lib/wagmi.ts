import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { localChain, robinhoodChain, robinhoodTestnetChain, isLocalDev } from "@/config/chains";

// TODO: get a real project ID at https://cloud.walletconnect.com — required for WalletConnect
// (mobile wallet) support in RainbowKit. The placeholder below works for browser-extension
// wallets (MetaMask etc.) in local dev but WalletConnect connections will not function until set.
const walletConnectProjectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "TODO-get-from-cloud.walletconnect.com";

// Two separate calls (rather than a shared conditional `chains` array) so TypeScript can infer
// the required non-empty-tuple type for `chains` at each call site.
export const wagmiConfig = isLocalDev
  ? getDefaultConfig({
      appName: "MARGIN",
      projectId: walletConnectProjectId,
      chains: [localChain, robinhoodChain],
      ssr: true,
    })
  : getDefaultConfig({
      appName: "MARGIN",
      projectId: walletConnectProjectId,
      chains: [robinhoodChain, robinhoodTestnetChain],
      ssr: true,
    });
