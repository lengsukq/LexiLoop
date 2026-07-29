import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { previewConfiguredInitialization, queueConfiguredInitialization, queueWordInitialization } from "@/modules/initialization/service";

function insertWord(term: string, phonetic?: string): number {
  const now = Date.now();
  const result = sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'PENDING', ?, ?)`)
    .run(term, term.toLowerCase(), now, now);
  const wordId = Number(result.lastInsertRowid);
  if (phonetic) {
    sqlite.prepare(`INSERT INTO word_contents
      (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json,
       synonyms_json, antonyms_json, tags_json, provider_metadata_json, updated_at)
      VALUES (?, '[]', ?, '[]', '[]', '[]', '[]', '[]', '[]', '[]', ?)`)
      .run(wordId, JSON.stringify([{ accent: "US", phonetic, audioUrl: null, source: "test", isSynthetic: false }]), now);
  }
  return wordId;
}

describe("configured initialization queue", () => {
  it("previews and queues only words missing the selected field", () => {
    const completeId = insertWord("alpha", "alpha");
    const missingId = insertWord("beta");
    const input = {
      requestedFields: ["pronunciations.phonetic" as const],
      requestedProviders: ["merriam-webster" as const, "ecdict" as const],
      providerStrategy: "PRIORITY_FALLBACK" as const,
      mode: "FILL_MISSING_FIELDS" as const,
      onlyMissing: true,
    };

    const preview = previewConfiguredInitialization(input);
    expect(preview.existingWords).toBe(2);
    expect(preview.selectedWords).toBe(1);
    expect(preview.skippedExisting).toBe(1);
    expect(preview.sample).toEqual([{ id: missingId, term: "beta" }]);

    const queued = queueConfiguredInitialization(input);
    expect(queued.createdJobs).toBe(1);
    expect((sqlite.prepare("SELECT count(*) AS count FROM initialization_jobs WHERE word_id = ?").get(completeId) as { count: number }).count).toBe(0);
    const job = sqlite.prepare(`SELECT requested_fields_json, requested_providers_json, provider_strategy
      FROM initialization_jobs WHERE word_id = ?`).get(missingId) as {
        requested_fields_json: string; requested_providers_json: string; provider_strategy: string;
      };
    expect(JSON.parse(job.requested_fields_json)).toEqual(["pronunciations.phonetic"]);
    expect(JSON.parse(job.requested_providers_json)).toEqual(["merriam-webster", "ecdict"]);
    expect(job.provider_strategy).toBe("PRIORITY_FALLBACK");
  });

  it("upgrades a queued field-only task to a full initialization request", () => {
    const wordId = insertWord("gamma");
    queueWordInitialization(wordId, "FILL_MISSING_FIELDS", 100, {
      requestedFields: ["pronunciations.phonetic"],
      requestedProviders: ["ecdict"],
      providerStrategy: "PRIORITY_FALLBACK",
    });
    queueWordInitialization(wordId);
    const job = sqlite.prepare("SELECT requested_fields_json, requested_providers_json FROM initialization_jobs WHERE word_id = ?").get(wordId) as {
      requested_fields_json: string | null; requested_providers_json: string | null;
    };
    expect(job.requested_fields_json).toBeNull();
    expect(job.requested_providers_json).toBeNull();
  });
});
