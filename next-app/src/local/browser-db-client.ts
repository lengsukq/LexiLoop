import type { SqliteLikeDatabase } from "@/db/types";
import { createPgliteFacade, type PgliteFacade } from "@/local/pglite-executor";

export const LOCAL_BROWSER_DB_URI = "idb://lexiloop-local";

const globalLocalDb = globalThis as typeof globalThis & {
  __lexiloopLocalDbFacade?: PgliteFacade;
};

export function getBrowserDbFacade(dataDir = LOCAL_BROWSER_DB_URI): PgliteFacade {
  if (!globalLocalDb.__lexiloopLocalDbFacade) {
    globalLocalDb.__lexiloopLocalDbFacade = createPgliteFacade(dataDir, {
      relaxedDurability: true,
    });
  }
  return globalLocalDb.__lexiloopLocalDbFacade;
}

export function setBrowserDbFacadeForTests(facade: PgliteFacade | undefined): void {
  globalLocalDb.__lexiloopLocalDbFacade = facade;
}

export async function ensureBrowserDbReady(): Promise<void> {
  await getBrowserDbFacade().ensureReady();
}

const browserDbProxy = new Proxy({} as SqliteLikeDatabase, {
  get(_target, prop) {
    const facade = getBrowserDbFacade();
    const value = (facade as unknown as Record<string, unknown>)[prop as string];
    return typeof value === "function" ? (value as (...args: unknown[]) => unknown).bind(facade) : value;
  },
});

export const sqlite: SqliteLikeDatabase = browserDbProxy;
export const db: SqliteLikeDatabase = browserDbProxy;
