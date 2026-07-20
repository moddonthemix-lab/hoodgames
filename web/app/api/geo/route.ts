import { NextRequest, NextResponse } from "next/server";

/**
 * Server-side country check gating the Rewards screen's "Convert payout" step — MARGIN_SPEC.md
 * section 4: Stock Tokens aren't available in the US, so that step must be hidden entirely for
 * US users. This must never run client-side (a client-side check is trivially bypassed).
 *
 * Reads CDN-provided geo headers rather than calling a third-party geolocation API: Vercel sets
 * `x-vercel-ip-country`, Cloudflare sets `cf-ipcountry`. This works out of the box on either
 * platform with zero added latency/cost/external dependency.
 *
 * TODO before this is trustworthy in production: if self-hosting without one of those CDNs in
 * front of it, neither header will be present. Wire in a MaxMind GeoIP2 database lookup (or a
 * paid geolocation API) as a fallback in that case — do NOT ship this gate as-is.
 *
 * Fails closed: unknown country -> convert step stays hidden. Showing a compliance-sensitive
 * feature to someone we couldn't verify is the wrong direction to be wrong in.
 */
export async function GET(request: NextRequest) {
  const country =
    request.headers.get("x-vercel-ip-country") || request.headers.get("cf-ipcountry") || null;

  const isUS = country === "US";
  const isKnown = country !== null;

  return NextResponse.json({
    country,
    convertStepAllowed: isKnown && !isUS,
  });
}
