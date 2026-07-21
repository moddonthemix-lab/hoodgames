"use client";

import { useEffect, useState } from "react";

/**
 * False during SSR and the first client render, true after mount. Used to gate time-sensitive UI
 * (live countdowns, gather cooldowns) so the server-rendered HTML and the first client render
 * match — otherwise `Date.now()`-derived text differs between the two and React throws a
 * hydration mismatch (#418/#423/#425). This is a wallet dapp; SSR of live data has no value anyway.
 */
export function useMounted(): boolean {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  return mounted;
}
