import type { Config } from "tailwindcss";

// MARGIN theme: Bloomberg-terminal-meets-degen (MARGIN_SPEC.md section 6), translated from the
// Stoke Fire reference screenshots' dark card / bottom-tab-nav mobile layout. Dark navy-black
// base (not pure black — closer to a real trading terminal), a violet accent carried over from
// Stoke Fire's mauve buttons, and green/red reserved strictly for P&L / status semantics.
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: {
          DEFAULT: "#0a0d14",
          card: "#131826",
          raised: "#1b2233",
          border: "#262f45",
        },
        accent: {
          DEFAULT: "#7c6fe0",
          hover: "#9186e8",
          muted: "#3a3560",
        },
        profit: {
          DEFAULT: "#22e5a0",
          dim: "#0f4a38",
        },
        loss: {
          DEFAULT: "#ff4d6a",
          dim: "#4a1420",
        },
        warn: {
          DEFAULT: "#ffb020",
          dim: "#4a3410",
        },
        ink: {
          DEFAULT: "#e8ecf6",
          muted: "#8891ab",
          faint: "#5a6280",
        },
      },
      fontFamily: {
        mono: [
          "ui-monospace",
          "SFMono-Regular",
          "Menlo",
          "Consolas",
          "Roboto Mono",
          "monospace",
        ],
        sans: [
          "-apple-system",
          "BlinkMacSystemFont",
          "Segoe UI",
          "Inter",
          "Helvetica Neue",
          "Arial",
          "sans-serif",
        ],
      },
      boxShadow: {
        card: "0 1px 0 0 rgba(255,255,255,0.03) inset, 0 8px 24px -12px rgba(0,0,0,0.6)",
      },
      animation: {
        "pulse-danger": "pulse-danger 1.6s ease-in-out infinite",
        ticker: "ticker 30s linear infinite",
      },
      keyframes: {
        "pulse-danger": {
          "0%, 100%": { opacity: "1" },
          "50%": { opacity: "0.55" },
        },
        ticker: {
          "0%": { transform: "translateX(0%)" },
          "100%": { transform: "translateX(-50%)" },
        },
      },
    },
  },
  plugins: [],
};

export default config;
