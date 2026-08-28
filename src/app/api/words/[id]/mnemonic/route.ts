import { ApiError, handleRouteError, ok, requireRouteId } from "@/lib/api";
import { getWordDetail } from "@/modules/words/queries";
import { generateChineseMnemonic } from "@/modules/ai-tasks/supplemental";
import { queueAiTask } from "@/modules/initialization/service";

export const dynamic = "force-dynamic";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    const word = await getWordDetail(id);
    if (!word) throw new ApiError("WORD_NOT_FOUND", "词条不存在。");

    return ok({
      id: word.id,
      term: word.term,
      entryType: word.entryType,
      sourceLanguage: word.sourceLanguage,
      targetLanguage: word.targetLanguage,
      definitions: word.content.definitions,
      pronunciations: word.content.pronunciations,
      roots: word.content.roots,
      affixes: word.content.affixes,
      confusedWords: word.content.confusedWords,
      wordFamily: word.content.wordFamily,
      learning: word.content.learning,
      examples: word.content.examples,
      forms: word.content.forms,
      phrases: word.content.phrases,
      synonyms: word.content.synonyms,
      antonyms: word.content.antonyms,
    });
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "获取助记信息失败。" });
  }
}

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    let sync = true;
    try {
      const body = await request.json() as { sync?: boolean };
      if (body && typeof body.sync === "boolean") sync = body.sync;
    } catch {
      // Body is empty or not JSON, default sync=true
    }

    if (!sync) {
      return ok({ jobId: await queueAiTask(id, "MNEMONIC"), queued: true });
    }

    const mnemonic = await generateChineseMnemonic(id);
    const word = await getWordDetail(id);

    return ok({
      success: true,
      mnemonic,
      learning: word?.content.learning ?? { pronunciationTip: null, mnemonic, commonMistakes: [] },
      roots: word?.content.roots ?? [],
      affixes: word?.content.affixes ?? [],
      confusedWords: word?.content.confusedWords ?? [],
    });
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "生成助记失败。" });
  }
}
