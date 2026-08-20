import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api";
import { callLlm } from "@/modules/llm/client";
import { getSettings, settingsForAiAttempt } from "@/modules/settings/service";
import { translateMissingWordContent } from "@/modules/translations/service";

function isChineseMnemonic(value: string): boolean {
  return (value.match(/[\u3400-\u9fff]/g)?.length ?? 0) >= 4;
}

export async function generateChineseMnemonic(wordId: number, attemptCount = 1): Promise<void> {
  const word = await sqlite.prepare("SELECT term, source_language, target_language FROM words WHERE id = ?").get(wordId) as Record<string, unknown> | undefined;
  if (!word) throw new ApiError("WORD_NOT_FOUND");
  const settings = settingsForAiAttempt(await getSettings(), attemptCount);
  const purpose = settings.llmConfig.purposes.IMPORT_ENRICHMENT;
  if (!purpose.enabled) throw new ApiError("AI_DISABLED");
  const provider = settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
  if (!provider || !provider.apiKey.trim() || !provider.baseUrl.trim() || !purpose.model.trim()) throw new ApiError("AI_CONFIG_INCOMPLETE");

  const term = String(word.term);
  const prompt = `你是一个语言学习助记生成器。为以下单词创作一个有趣、易记的中文助记方法，帮助英文基础较弱的中文母语者记住这个单词。\n\n单词: ${term}\n语言: ${String(word.source_language)} → ${String(word.target_language)}\n\n要求：\n- 助记要简短有趣，4-150 个汉字\n- 必须用简体中文叙述；目标英文词或必要词根可以出现，但不得输出英文完整句子、英文释义或纯英文拆词说明\n- 优先使用中文谐音、中文画面、中文故事或中文词义联想\n- 只输出助记本身，不要前缀、引号或 Markdown`;
  const baseUrl = provider.baseUrl.trim().replace(/\/+$/, "");
  const request = async (correction = ""): Promise<string> => {
    const mnemonic = await callLlm(
      { apiType: provider.apiType, baseUrl, apiKey: provider.apiKey, model: purpose.model, timeoutMs: purpose.timeoutMs ?? 30_000 },
      `${prompt}${correction}`,
      { systemPrompt: "只能用简体中文讲解；不得输出英文完整句子或英文释义。", maxOutputTokens: 300, temperature: 0.7 },
    );
    if (!mnemonic) throw new ApiError("AI_EMPTY_RESPONSE");
    return mnemonic;
  };

  let mnemonic = await request();
  if (!isChineseMnemonic(mnemonic)) mnemonic = await request("\n\n上一版没有按要求使用中文。请完全重写：只保留目标英文词本身，其他叙述必须是简体中文。");
  if (!isChineseMnemonic(mnemonic)) throw new ApiError("AI_MNEMONIC_LANGUAGE_INVALID");

  const row = await sqlite.prepare("SELECT learning_json FROM word_contents WHERE word_id = ?").get(wordId) as { learning_json: string | null } | undefined;
  const learning = row?.learning_json ? JSON.parse(row.learning_json) : { pronunciationTip: null, mnemonic: null, commonMistakes: [] };
  learning.mnemonic = mnemonic;
  const now = Date.now();
  if (row) await sqlite.prepare("UPDATE word_contents SET learning_json = ?, content_version = content_version + 1, updated_at = ? WHERE word_id = ?").run(JSON.stringify(learning), now, wordId);
  else await sqlite.prepare("INSERT INTO word_contents(word_id, learning_json, content_version, initialized_at, updated_at) VALUES (?, ?, 1, ?, ?)").run(wordId, JSON.stringify(learning), now, now);
}

export async function runSupplementalTask(taskType: "MNEMONIC" | "EXAMPLE_TRANSLATIONS", wordId: number, attemptCount = 1): Promise<void> {
  if (taskType === "MNEMONIC") return generateChineseMnemonic(wordId, attemptCount);
  await translateMissingWordContent(wordId, attemptCount);
}
