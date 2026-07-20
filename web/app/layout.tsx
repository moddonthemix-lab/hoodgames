import type { Metadata, Viewport } from "next";
import "./globals.css";
import { Providers } from "./providers";

export const metadata: Metadata = {
  title: "MARGIN — Onchain Fund Survival Game",
  description: "Run an onchain fund. Rebalance every 72h or get margin called.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  themeColor: "#0a0d14",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-bg text-ink">
        <Providers>
          <div className="mx-auto flex min-h-screen max-w-md flex-col">{children}</div>
        </Providers>
      </body>
    </html>
  );
}
