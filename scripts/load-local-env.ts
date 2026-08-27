import fs from "node:fs";
import path from "node:path";

export function loadLocalEnv(): void {
  for (const envFile of [path.join(process.cwd(), ".env"), path.join(process.cwd(), ".env.local")]) {
    if (!fs.existsSync(envFile)) continue;
    for (const line of fs.readFileSync(envFile, "utf8").split("\n")) {
      const match = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
      if (!match) continue;
      const key = match[1];
      const value = match[2];
      if (key && value !== undefined && !(key in process.env)) process.env[key] = value;
    }
  }
}
