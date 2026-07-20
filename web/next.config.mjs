/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  webpack: (config) => {
    // Harmless "module not found" warnings from optional deps deep in wagmi's wallet
    // connectors: @react-native-async-storage/async-storage (MetaMask SDK's React Native path,
    // unused on web) and pino-pretty (WalletConnect logger's optional dev pretty-printer). Both
    // are well-known, widely-documented no-ops in this ecosystem — silenced here so Railway's
    // build log doesn't read as broken.
    config.resolve.alias = {
      ...config.resolve.alias,
      "@react-native-async-storage/async-storage": false,
      "pino-pretty": false,
    };
    return config;
  },
};

export default nextConfig;
