import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api";
import { callLlmWithFallback, resolveLlmProviders } from "@/modules/llm/client";
import { getSettings } from "@/modules/settings/service";
import { translateMissingWordContent } from "@/modules/translations/service";

function isChineseMnemonic(value: string): boolean {
  return (value.match(/[\u3400-\u9fff]/g)?.length ?? 0) >= 4;
}

export async function generateChineseMnemonic(wordId: number): Promise<string> {
  const word = (await sqlite.prepare("SELECT term, source_language, target_language, content_type, entry_type FROM words WHERE id = ?").get(wordId)) as
    | Record<string, unknown>
    | undefined;
  if (!word) throw new ApiError("WORD_NOT_FOUND");
  const settings = await getSettings();
  const { primary, fallback } = resolveLlmProviders(settings);
  if (!primary) {
    const purpose = settings.llmConfig.ai;
    if (!purpose.enabled) throw new ApiError("AI_DISABLED");
    throw new ApiError("AI_CONFIG_INCOMPLETE");
  }
  const purpose = settings.llmConfig.ai;

  const row = (await sqlite.prepare("SELECT * FROM word_contents WHERE word_id = ?").get(wordId)) as Record<string, unknown> | undefined;
  const term = String(word.term);

  let definitionSummary = "";
  let rootsInfo = "";
  let affixesInfo = "";
  let confusedInfo = "";
  if (row) {
    try {
      const defs = JSON.parse(String(row.definitions_json || "[]")) as Array<{ text: string }>;
      if (defs.length > 0) definitionSummary = defs.map((d) => d.text).join("; ");
      const roots = JSON.parse(String(row.roots_json || "[]")) as Array<{ root: string; meaning: string }>;
      if (roots.length > 0) rootsInfo = roots.map((r) => `${r.root}(${r.meaning})`).join(", ");
      const affixes = JSON.parse(String(row.affixes_json || "[]")) as Array<{ type: string; value: string; meaning: string }>;
      if (affixes.length > 0) affixesInfo = affixes.map((a) => `${a.type === "PREFIX" ? "前缀" : "后缀"}${a.value}(${a.meaning})`).join(", ");
      const confused = JSON.parse(String(row.confused_words_json || "[]")) as Array<{ word: string }>;
      if (confused.length > 0) confusedInfo = confused.map((c) => c.word).join(", ");
    } catch {
      // Keep empty if parse fails
    }
  }

  const prompt =
    `你是一个专业的英语高效学习与记忆专家。请为以下单词创作一个结构清晰、生动好记的中文助记解析。\n\n` +
    `目标单词: ${term}\n` +
    `中文释义: ${definitionSummary || "无"}\n` +
    (rootsInfo ? `已知词根: ${rootsInfo}\n` : "") +
    (affixesInfo ? `已知词缀: ${affixesInfo}\n` : "") +
    (confusedInfo ? `易混词: ${confusedInfo}\n` : "") +
    `\n助记创作要求：\n` +
    `- 重点帮助中国学习者在做错题后快速建立记忆钩子（Memory Hook）\n` +
    `- 优先结合【词根词缀拆解】（如有）或【中文生动谐音/画面联想/生活场景】\n` +
    `- 若有易混词，用一句话点明区分诀窍\n` +
    `- 语言生动简洁，总字数在 15-120 个汉字左右\n` +
    `- 必须使用简体中文叙述，只输出助记内容本身，不要 Markdown 标题、引号或额外开场白`;

  const request = async (correction = ""): Promise<string> => {
    const mnemonic = await callLlmWithFallback(primary, fallback, `${prompt}${correction}`, {
      systemPrompt: "你是一个优秀的英语助记大师。只能用简体中文讲解记忆法；不得输出英文完整句子或长篇无关叙述。",
      maxOutputTokens: purpose.maxOutputTokens ?? 300,
      temperature: purpose.temperature ?? 0.7,
      thinkingEnabled: purpose.thinkingEnabled ?? false,
      thinkingBudgetTokens: purpose.thinkingBudgetTokens,
      reasoningEffort: purpose.reasoningEffort,
    });
    if (!mnemonic) throw new ApiError("AI_EMPTY_RESPONSE");
    return mnemonic;
  };

  let mnemonic = await request();
  if (!isChineseMnemonic(mnemonic)) mnemonic = await request("\n\n上一版没有按要求使用中文。请完全重写：只保留目标英文词本身，其他叙述必须是简体中文。");
  if (!isChineseMnemonic(mnemonic)) throw new ApiError("AI_MNEMONIC_LANGUAGE_INVALID");

  const learning = row?.learning_json ? JSON.parse(String(row.learning_json)) : { pronunciationTip: null, mnemonic: null, commonMistakes: [] };
  learning.mnemonic = mnemonic.trim();
  const now = Date.now();
  if (row) await sqlite.prepare("UPDATE word_contents SET learning_json = ?, content_version = content_version + 1, updated_at = ? WHERE word_id = ?").run(JSON.stringify(learning), now, wordId);
  else await sqlite.prepare("INSERT INTO word_contents(word_id, learning_json, content_version, initialized_at, updated_at) VALUES (?, ?, 1, ?, ?)").run(wordId, JSON.stringify(learning), now, now);

  return learning.mnemonic;
}

export async function runSupplementalTask(taskType: "MNEMONIC" | "EXAMPLE_TRANSLATIONS", wordId: number): Promise<void> {
  if (taskType === "MNEMONIC") {
    await generateChineseMnemonic(wordId);
    return;
  }
  await translateMissingWordContent(wordId);
}
