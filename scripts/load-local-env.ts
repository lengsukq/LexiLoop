import fs from "node:fs";
import path from "node:path";

/**
 * Loads .env.local for standalone scripts (tsx) that run outside Next.js,
 * which normally applies environment files itself. Existing process.env
 * values always win.
 */
export function loadLocalEnv(): void {
  const envFile = path.join(process.cwd(), ".env.local");
  if (!fs.existsSync(envFile)) return;
  for (const line of fs.readFileSync(envFile, "utf8").split("\n")) {
    const match = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (!match) continue;
    const key = match[1];
    const value = match[2];
    if (key && value !== undefined && !(key in process.env)) process.env[key] = value;
  }
}
