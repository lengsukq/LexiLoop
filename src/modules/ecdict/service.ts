import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import { Readable } from "node:stream";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { updateSettings, getSettings } from "@/modules/settings/service";

const DOWNLOAD_URL = "https://github.com/skywind3000/ECDICT/releases/download/1.0.28/ecdict-sqlite-28.zip";
const execFileAsync = promisify(execFile);

function databasePath(): string {
  return path.resolve(/* turbopackIgnore: true */ process.env.ECDICT_DATABASE_PATH ?? "./data/reference/ecdict.sqlite");
}

function validate(filePath: string): void {
  const database = new Database(filePath, { readonly: true, fileMustExist: true });
  try {
    const integrity = database.pragma("integrity_check", { simple: true });
    if (integrity !== "ok") throw new Error(`SQLite integrity_check: ${String(integrity)}`);
    const table = database.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='stardict'").get();
    if (!table) throw new Error("文件不是有效的 ECDICT SQLite 数据库：缺少 stardict 表");
    database.prepare("SELECT word, translation FROM stardict LIMIT 1").get();
  } finally {
    database.close();
  }
}

export async function getEcdictStatus() {
  const file = databasePath();
  const settings = await getSettings();
  return {
    installed: fs.existsSync(file),
    enabled: settings.ecdictEnabled,
    fileSize: fs.existsSync(file) ? fs.statSync(file).size : 0,
    path: file,
    downloadUrl: DOWNLOAD_URL,
  };
}

export async function installUploadedEcdict(buffer: Buffer) {
  const destination = databasePath();
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  const temporary = `${destination}.uploading`;
  fs.writeFileSync(temporary, buffer, { mode: 0o600 });
  try {
    validate(temporary);
    fs.renameSync(temporary, destination);
    await updateSettings({ ecdictEnabled: true });
    return getEcdictStatus();
  } catch (error) {
    fs.rmSync(temporary, { force: true });
    throw error;
  }
}

export async function downloadAndInstallEcdict() {
  const destination = databasePath();
  const directory = path.dirname(destination);
  fs.mkdirSync(directory, { recursive: true });
  const zipPath = path.join(/* turbopackIgnore: true */ directory, "ecdict-download.zip");
  const extractedPath = path.join(/* turbopackIgnore: true */ directory, "stardict.db");
  fs.rmSync(zipPath, { force: true });
  fs.rmSync(extractedPath, { force: true });
  const response = await fetch(DOWNLOAD_URL, { signal: AbortSignal.timeout(15 * 60_000), redirect: "follow" });
  if (!response.ok || !response.body) throw new Error(`下载 ECDICT 失败：HTTP ${response.status}`);
  await pipeline(Readable.fromWeb(response.body as unknown as Parameters<typeof Readable.fromWeb>[0]), fs.createWriteStream(zipPath));
  await execFileAsync("unzip", ["-j", "-o", zipPath, "*stardict.db", "-d", directory], { timeout: 15 * 60_000, maxBuffer: 10 * 1024 * 1024 });
  if (!fs.existsSync(extractedPath)) throw new Error("压缩包中未找到 stardict.db");
  validate(extractedPath);
  fs.copyFileSync(extractedPath, `${destination}.installing`);
  fs.renameSync(`${destination}.installing`, destination);
  fs.rmSync(zipPath, { force: true });
  fs.rmSync(extractedPath, { force: true });
  await updateSettings({ ecdictEnabled: true });
  return getEcdictStatus();
}

export async function setEcdictEnabled(enabled: boolean) {
  if (enabled && !fs.existsSync(databasePath())) throw new Error("ECDICT_NOT_INSTALLED");
  await updateSettings({ ecdictEnabled: enabled });
  return getEcdictStatus();
}

export async function removeEcdict() {
  fs.rmSync(databasePath(), { force: true });
  await updateSettings({ ecdictEnabled: false });
  return getEcdictStatus();
}
