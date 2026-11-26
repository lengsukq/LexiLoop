import type { DictionaryContent, ProviderAttempt } from "./content";
import type { EntryType } from "./core";

export interface ImportPreviewRow {
  rowNumber: number; term: string; normalizedTerm: string; sourceLanguage: string; targetLanguage: string;
  sourceLanguageName: string; targetLanguageName: string; entryType: EntryType; sourceCreatedAt: string | null;
  status: "NEW" | "EXISTING" | "DUPLICATE" | "INVALID"; errors: string[];
}
export interface ImportPreview {
  previewToken: string; filename: string; totalRows: number; validRows: number; invalidRows: number; duplicateRows: number;
  newRows: number; existingRows: number; languages: Record<string, number>; entryTypes: Record<string, number>;
  rows: ImportPreviewRow[]; expiresAt: string;
}
export interface ManualContentPreview {
  previewToken: string; term: string; normalizedTerm: string; sourceLanguage: string; targetLanguage: string;
  sourceLanguageName: string; targetLanguageName: string; contentType: EntryType; content: DictionaryContent;
  providerAttempts: ProviderAttempt[]; existingWordId: number | null; expiresAt: string;
}
