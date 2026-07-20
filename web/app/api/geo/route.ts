import { NextRequest, NextResponse } from "next/server";

/**
 * Server-side country check gating the Rewards screen's "Convert payout" step — MARGIN_SPEC.md
 * section 4: Stock Tokens aren't available in the US, so that step must be hidden entirely for
 * US users. This must never run client-side (a client-side check is trivially bypassed).
 *
 * Three-tier lookup, cheapest/most-reliable first:
 * 1. CDN-provided geo headers (Vercel's `x-vercel-ip-country`, Cloudflare's `cf-ipcountry`) —
 *    zero cost/latency if this ever sits behind either of those.
 * 2. IP-based lookup via ip-api.com (free, no API key, ~45 req/min per source IP) using the
 *    client IP Railway's proxy puts in `x-forwarded-for`. This is what actually runs on Railway,
 *    which sets neither CDN header. Result is cached in-memory per IP for an hour so repeat
 *    requests from the same user don't re-query or eat into the rate limit.
 * 3. Unknown — fails closed, Convert step stays hidden. Showing a compliance-sensitive feature
 *    to someone we couldn't verify is the wrong direction to be wrong in.
 *
 * TODO before this matters at real scale: ip-api.com's free tier is HTTP-only (not HTTPS) and
 * rate-limited — fine for testing/early traffic, swap for a paid geolocation API or a MaxMind
 * GeoIP2 database lookup before this needs to hold up under real load. The in-memory cache also
 * resets on every deploy/restart and isn't shared across instances — a real cache (Redis etc.)
 * is the next step up, not needed yet.
 */

type CacheEntry = { country: string | null; expiresAt: number };
const CACHE_TTL_MS = 60 * 60 * 1000;
const ipCountryCache = new Map<string, CacheEntry>();

function getClientIp(request: NextRequest): string | null {
  const forwardedFor = request.headers.get("x-forwarded-for");
  if (forwardedFor) {
    const first = forwardedFor.split(",")[0]?.trim();
    if (first) return first;
  }
  const realIp = request.headers.get("x-real-ip");
  if (realIp) return realIp;
  return null;
}

function isPrivateOrLocalIp(ip: string): boolean {
  return (
    ip === "127.0.0.1" ||
    ip === "::1" ||
    ip.startsWith("10.") ||
    ip.startsWith("192.168.") ||
    /^172\.(1[6-9]|2\d|3[0-1])\./.test(ip)
  );
}

async function lookupCountryByIp(ip: string): Promise<string | null> {
  const cached = ipCountryCache.get(ip);
  if (cached && cached.expiresAt > Date.now()) return cached.country;

  try {
    const res = await fetch(`http://ip-api.com/json/${ip}?fields=status,countryCode`, {
      signal: AbortSignal.timeout(3000),
    });
    const data = await res.json();
    const country = data?.status === "success" ? (data.countryCode as string) : null;
    ipCountryCache.set(ip, { country, expiresAt: Date.now() + CACHE_TTL_MS });
    return country;
  } catch {
    return null; // network error, timeout, etc. — fail closed, don't cache a transient failure
  }
}

export async function GET(request: NextRequest) {
  const cdnCountry = request.headers.get("x-vercel-ip-country") || request.headers.get("cf-ipcountry");

  let country: string | null = cdnCountry || null;
  if (!country) {
    const ip = getClientIp(request);
    if (ip && !isPrivateOrLocalIp(ip)) {
      country = await lookupCountryByIp(ip);
    }
  }

  const isUS = country === "US";
  const isKnown = country !== null;

  return NextResponse.json({
    country,
    convertStepAllowed: isKnown && !isUS,
  });
}
