"use client";

import { useEffect, useState } from "react";

const GLOBALLY_ENABLED = process.env.NEXT_PUBLIC_CONVERT_STEP_ENABLED === "true";

/**
 * Two independent gates, both must pass (MARGIN_SPEC.md section 4 / Phase 4):
 * 1. NEXT_PUBLIC_CONVERT_STEP_ENABLED — a global kill switch, off until legal review is done.
 * 2. /api/geo's server-side country check — hidden entirely for US users.
 */
export function useConvertStepAllowed(): { allowed: boolean; loading: boolean; country: string | null } {
  const [country, setCountry] = useState<string | null>(null);
  const [loading, setLoading] = useState(GLOBALLY_ENABLED);

  useEffect(() => {
    if (!GLOBALLY_ENABLED) return;
    fetch("/api/geo")
      .then((r) => r.json())
      .then((data) => setCountry(data.country))
      .catch(() => setCountry(null))
      .finally(() => setLoading(false));
  }, []);

  if (!GLOBALLY_ENABLED) return { allowed: false, loading: false, country: null };
  return { allowed: !loading && country !== "US" && country !== null, loading, country };
}
