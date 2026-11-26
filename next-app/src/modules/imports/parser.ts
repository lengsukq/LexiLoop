import Papa from "papaparse";
import { z } from "zod";

const rowSchema = z.object({
  queryText: z.string().trim().min(1, "queryText 不能为空").max(300, "queryText 不能超过 300 个字符"),
  queryFromLanguage: z.string().trim().min(1, "queryFromLanguage 不能为空").max(50),
  queryToLanguage: z.string().trim().min(1, "queryToLanguage 不能为空").max(50),
  timestamp: z.string().trim().optional().default(""),
});

export interface ParsedEasyDictRow {
  rowNumber: number;
  raw: Record<string, string>;
  data?: z.infer<typeof rowSchema>;
  errors: string[];
}

export interface ParsedCsv {
  rows: ParsedEasyDictRow[];
  headers: string[];
  parseErrors: string[];
}

const REQUIRED_HEADERS = ["queryText", "queryFromLanguage", "queryToLanguage"];

export function parseEasyDictCsv(content: string): ParsedCsv {
  const cleaned = content.charCodeAt(0) === 0xfeff ? content.slice(1) : content;
  if (cleaned.includes("\uFFFD")) {
    return { rows: [], headers: [], parseErrors: ["文件不是有效的 UTF-8 编码。"] };
  }

  const result = Papa.parse<Record<string, string>>(cleaned, {
    header: true,
    skipEmptyLines: "greedy",
    transformHeader: (header) => header.trim(),
  });
  const headers = result.meta.fields ?? [];
  const missing = REQUIRED_HEADERS.filter((header) => !headers.includes(header));
  if (missing.length > 0) {
    return { rows: [], headers, parseErrors: [`缺少必要列：${missing.join("、")}`] };
  }

  const rows = result.data.map((raw, index) => {
    const validation = rowSchema.safeParse(raw);
    if (!validation.success) {
      return {
        rowNumber: index + 2,
        raw,
        errors: validation.error.issues.map((issue) => issue.message),
      };
    }
    const timestamp = validation.data.timestamp;
    if (timestamp && Number.isNaN(new Date(timestamp).getTime())) {
      return { rowNumber: index + 2, raw, errors: ["timestamp 不是有效日期"] };
    }
    return { rowNumber: index + 2, raw, data: validation.data, errors: [] };
  });

  return {
    rows,
    headers,
    parseErrors: result.errors.map((error) => `第 ${error.row === undefined ? "?" : error.row + 2} 行：${error.message}`),
  };
}
