import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { getSettings } from "@/modules/settings/service";

export const dynamic = "force-dynamic";

export async function POST(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const id = Number((await params).id);
    if (!Number.isInteger(id) || id <= 0) return fail("WORD_ID_INVALID", "词条 ID 无效。");

    const { db, sqlite } = await import("@/db/client");
    const row = sqlite.prepare("SELECT term, source_language, target_language FROM words WHERE id = ?").get(id) as Record<string, unknown> | undefined;
    if (!row) return fail("WORD_NOT_FOUND", "词条不存在。", 404);

    const term = row.term as string;
    const sourceLanguage = row.source_language as string;
    const targetLanguage = row.target_language as string;

    const settings = await getSettings();
    const purpose = settings.llmConfig.purposes.IMPORT_ENRICHMENT;
    if (!purpose.enabled) return fail("AI_DISABLED", "AI 词条初始化未启用，请在设置中配置。");

    const provider = settings.llmConfig.providers.find((p) => p.id === purpose.providerId);
    if (!provider) return fail("AI_PROVIDER_MISSING", "AI Provider 未配置。");
    if (!provider.apiKey.trim() || !provider.baseUrl.trim() || !purpose.model.trim()) {
      return fail("AI_CONFIG_INCOMPLETE", "AI 提供商、API Key、接口地址或模型未配置完整。");
    }

    // Build prompt for mnemonic generation
    const prompt = `你是一个语言学习助记生成器。为以下单词创作一个有趣、易记的中文助记方法，帮助中文母语者记住这个单词。

单词: ${term}
语言: ${sourceLanguage} → ${targetLanguage}

要求:
- 助记要简短有趣，20-150字
- 可以包含发音联想、词形拆解、故事联想等
- 只说助记本身，不要前缀、不要引号、不要 markdown
- 只输出纯文本，不要其他内容`;

    const baseUrl = provider.baseUrl.trim().replace(/\/+$/, "");
    const endpoint = `${baseUrl}/chat/completions`;
    const timeoutMs = purpose.timeoutMs ?? 30000;

    const response = await fetch(endpoint, {
      method: "POST",
      signal: AbortSignal.timeout(timeoutMs),
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${provider.apiKey}` },
      body: JSON.stringify({
        model: purpose.model,
        messages: [
          { role: "system", content: "你是一位有趣的语言学习助记创作者。请用中文输出简短有趣的记忆方法。" },
          { role: "user", content: prompt },
        ],
        temperature: 0.7,
        max_tokens: 300,
      }),
    });

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      return fail("AI_REQUEST_FAILED", `AI 请求失败 (${response.status}): ${body.slice(0, 200)}`);
    }

    const json = await response.json() as { choices: Array<{ message: { content: string } }> };
    const mnemonic = json.choices?.[0]?.message?.content?.trim() ?? "";
    if (!mnemonic) return fail("AI_EMPTY_RESPONSE", "AI 返回内容为空。");

    // Update learning_json's mnemonic field only
    const contentRow = sqlite.prepare("SELECT learning_json FROM word_contents WHERE word_id = ?").get(id) as { learning_json: string | null } | undefined;
    const learning = contentRow?.learning_json ? JSON.parse(contentRow.learning_json) : { pronunciationTip: null, mnemonic: null, commonMistakes: [] };
    learning.mnemonic = mnemonic;
    const now = Date.now();

    if (contentRow) {
      sqlite.prepare("UPDATE word_contents SET learning_json = ?, updated_at = ? WHERE word_id = ?")
        .run(JSON.stringify(learning), now, id);
    } else {
      sqlite.prepare(`INSERT INTO word_contents(word_id, learning_json, content_version, initialized_at, updated_at)
        VALUES (?, ?, 1, ?, ?)`)
        .run(id, JSON.stringify(learning), now, now);
    }

    return ok({ mnemonic });
  } catch (error) {
    if (error instanceof DOMException && error.name === "TimeoutError") {
      return fail("AI_TIMEOUT", "AI 请求超时，请稍后重试。");
    }
    return internalError(error, "生成助记失败。");
  }
}
