/// 业务错误的类型化表示。
///
/// **为什么不用字符串判错**：`docs/CLEAN_CODE_BASELINE.md` 记录旧版有约 15 处
/// `error.message === "WORD_NOT_FOUND"` 这类字符串比较，编译器无法发现拼写错误，
/// 也无法在新增错误码时提示遗漏分支。这里用 `sealed class` + `switch` 让
/// 分支穷尽性由编译器保证。
///
/// 旧版把 HTTP 状态码与文案绑在一起；纯本地应用没有 HTTP 层，
/// 因此保留**错误码与中文文案**，去掉状态码，改用 `isTransient` 表达「可否重试」。
library;

/// 业务错误码。
///
/// 每个取值的文档说明**何时会被抛出**；面向用户的文案在 [defaultMessage]，
/// 两者不重复。文案与旧版 `src/lib/api.ts` 的 `ERROR_MESSAGES` 表逐条对应。
enum AppErrorCode {
  // ── 通用 ──

  /// 请求参数缺失或类型不符。
  validationError('VALIDATION_ERROR', '参数无效。'),

  /// 按 ID 查找的目标不存在，且没有更具体的错误码可用。
  notFound('NOT_FOUND', '目标不存在。'),

  // ── 词条 ──

  /// 词条 ID 不是正整数。
  wordIdInvalid('WORD_ID_INVALID', '词条 ID 无效。'),

  /// 指定 ID 的词条不存在。
  wordNotFound('WORD_NOT_FOUND', '词条不存在。'),

  /// 词条尚未初始化完成，不能进入学习。
  wordNotReady('WORD_NOT_READY', '词条尚未初始化完成。'),

  /// 词条已被用户暂停学习。
  wordSuspended('WORD_SUSPENDED', '词条已暂停学习。'),

  /// 词条存在复习日志或会话记录，硬删除会破坏历史聚合。
  wordHasLearningHistory(
    'WORD_HAS_LEARNING_HISTORY',
    '该词条已有学习记录，不能硬删除。请改为暂停学习。',
  ),

  /// 词条文本为空。
  termRequired('TERM_REQUIRED', '词条文本不能为空。'),

  /// 词条文本超过长度上限。
  termTooLong('TERM_TOO_LONG', '词条文本过长。'),

  /// 修改后的词条文本与库中已有词条重复。
  termAlreadyExists('TERM_ALREADY_EXISTS', '已存在相同词条，无法修改为该文本。'),

  /// 试图把当前词条作为它自己的关联词加入。
  relatedWordSameAsParent('RELATED_WORD_SAME_AS_PARENT', '不能把当前词条再次加入词库。'),

  /// 指定 ID 的例句不存在。
  exampleNotFound('EXAMPLE_NOT_FOUND', '例句不存在。'),

  // ── 初始化任务 ──

  /// 任务 ID 不是正整数。
  jobIdInvalid('JOB_ID_INVALID', '任务 ID 无效。'),

  /// 指定 ID 的初始化任务不存在。
  jobNotFound('JOB_NOT_FOUND', '任务不存在。'),

  // ── 学习与复习 ──

  /// 学习会话不存在或已过期释放。
  sessionNotFound('SESSION_NOT_FOUND', '学习会话不存在。'),

  /// 会话中的题目项不存在。
  studyItemNotFound('STUDY_ITEM_NOT_FOUND', '学习题目不存在。'),

  /// 该题已被作答，重复提交被拒绝。
  studyItemAlreadyProcessed('STUDY_ITEM_ALREADY_PROCESSED', '该题目已经处理，不能重复操作。'),

  /// 提交的词条 ID 与会话题目记录的不一致。
  studyItemWordMismatch('STUDY_ITEM_WORD_MISMATCH', '提交的词条与学习题目不匹配。'),

  /// 提交的题型与会话题目记录的不一致。
  studyItemQuestionMismatch('STUDY_ITEM_QUESTION_MISMATCH', '提交的题型与学习题目不匹配。'),

  /// 只提供了会话 ID 或题目 ID 其中之一。
  invalidStudyContext('INVALID_STUDY_CONTEXT', '学习会话和题目参数必须同时提供。'),

  /// 同一答案标识被用于不同题目，幂等键冲突。
  idempotencyKeyConflict('IDEMPOTENCY_KEY_CONFLICT', '该答案请求标识已被其他提交使用。'),

  /// 当日 AI 推荐题已全部完成。
  aiRecommendedAllDone('AI_RECOMMENDED_ALL_DONE', '今日 AI 必做题已全部完成，明天再来吧。'),

  // ── 游戏、配对、音标 ──

  /// 可学习词条不足 4 个，无法开局。
  notEnoughGameWords('NOT_ENOUGH_GAME_WORDS', '至少需要 4 个带有效释义的可学习词条。'),

  /// 可配对且释义不重复的词条不足 4 个。
  notEnoughMatchingWords('NOT_ENOUGH_MATCHING_WORDS', '至少需要 4 个带释义且不重复的可学习词条。'),

  /// 带音标的单词不足 4 个。
  notEnoughPhoneticWords(
    'NOT_ENOUGH_PHONETIC_WORDS',
    '至少需要 4 个带有对应音标的可学习单词。请先在初始化页补齐音标。',
  ),

  /// 小游戏会话不存在或已失效。
  gameSessionNotFound('GAME_SESSION_NOT_FOUND', '小游戏会话不存在或已经失效。'),

  /// 配对会话不存在或已失效。
  matchSessionNotFound('MATCH_SESSION_NOT_FOUND', '配对会话不存在或已经失效。'),

  /// 音标训练会话不存在或已失效。
  phoneticSessionNotFound('PHONETIC_SESSION_NOT_FOUND', '音标训练会话不存在或已经失效。'),

  /// 通用练习会话不存在或已失效。
  practiceSessionNotFound('PRACTICE_SESSION_NOT_FOUND', '练习会话不存在或已经失效。'),

  // ── 导入 ──

  /// 未选择 CSV 文件。
  csvRequired('CSV_REQUIRED', '请选择 EasyDict CSV 文件。'),

  /// 所选文件扩展名不是 `.csv`。
  csvTypeInvalid('CSV_TYPE_INVALID', '仅支持 .csv 文件。'),

  /// CSV 文件超过 10MB 上限。
  csvTooLarge('CSV_TOO_LARGE', 'CSV 文件不能超过 10MB。'),

  /// CSV 行数超过 20,000 行上限。
  csvTooManyRows('CSV_TOO_MANY_ROWS', 'CSV 不能超过 20,000 行。'),

  /// 文件不是合法 UTF-8（解码后出现替换字符 U+FFFD）。
  csvEncodingInvalid('CSV_ENCODING_INVALID', '文件不是有效的 UTF-8 编码。'),

  /// CSV 缺少 `queryText` / `queryFromLanguage` / `queryToLanguage` 之一。
  csvMissingHeaders('CSV_MISSING_HEADERS', '缺少必要列。'),

  /// 导入预览令牌已过期或已被消费。
  importPreviewExpired('IMPORT_PREVIEW_EXPIRED', '导入预览已过期，请重新上传。'),

  /// 导入批次 ID 不是正整数。
  importBatchIdInvalid('IMPORT_BATCH_ID_INVALID', '导入批次 ID 无效。'),

  /// 批次内词条已产生学习记录、会话或被后续导入引用，撤销会破坏数据。
  importBatchHasDependencies(
    'IMPORT_BATCH_HAS_DEPENDENCIES',
    '该批次的部分词条已经产生学习记录、会话或后续导入，不能安全撤销。',
  ),

  /// 批次的静态条件不满足无损撤销（改过已有词条或重置过学习进度）。
  importBatchNotRollbackable('IMPORT_BATCH_NOT_ROLLBACKABLE', '该批次无法无损撤销。'),

  // ── 备份 ──

  /// 备份文件超过 100MB 上限。
  backupTooLarge('BACKUP_TOO_LARGE', '备份文件过大。'),

  /// 备份文件不是合法 JSON。
  backupInvalidJson('BACKUP_INVALID_JSON', '备份文件不是有效的 JSON。'),

  /// 备份缺少 `format` 字段或 `format` 不匹配。
  backupInvalidFormat('BACKUP_INVALID_FORMAT', '备份格式无效，或不是 LexiLoop 备份文件。'),

  // ── AI 与外部服务 ──

  /// 设置中未启用 AI。
  aiDisabled('AI_DISABLED', '该 AI 功能未启用。'),

  /// AI 提供商、Base URL、API Key 或模型缺失。
  aiConfigIncomplete('AI_CONFIG_INCOMPLETE', 'AI 服务配置不完整，请到设置页补全。'),

  /// 模型返回空内容，通常值得切换备用模型重试。
  aiEmptyResponse('AI_EMPTY_RESPONSE', 'AI 没有返回有效内容，请重试或更换模型。'),

  /// 模型返回的内容无法解析为预期结构。
  aiResponseInvalid('AI_RESPONSE_INVALID', 'AI 返回的内容格式无效，请重试或更换模型。'),

  /// 助记词任务返回的内容不含足够中文。
  aiMnemonicLanguageInvalid('AI_MNEMONIC_LANGUAGE_INVALID', 'AI 生成的助记词不是中文。'),

  /// 网络或服务端错误导致请求失败。
  aiRequestFailed('AI_REQUEST_FAILED', 'AI 服务请求失败。'),

  /// 质量评分低于阈值，内容被整份丢弃。
  aiQualityLow('AI_QUALITY_LOW', 'AI 生成的内容质量不达标，已丢弃。'),

  /// 模型输出因 token 上限被截断。
  aiOutputTruncated('AI_OUTPUT_TRUNCATED', 'AI 输出被截断，内容不完整。'),

  /// 返回内容中的目标词与请求词条不一致。
  aiTermMismatch('AI_TERM_MISMATCH', 'AI 返回的内容与目标词条不一致。'),

  /// 内容未通过语义校验（如例句不含目标词）。
  aiSemanticInvalid('AI_SEMANTIC_INVALID', 'AI 返回的内容未通过语义校验。'),

  /// 返回内容不满足 JSON Schema。
  aiSchemaInvalid('AI_SCHEMA_INVALID', 'AI 返回的内容不符合预期结构。'),

  /// 请求超时。
  aiTimeout('AI_TIMEOUT', 'AI 服务响应超时。'),

  // ── 词典 provider ──

  /// 数据源瞬时失败（超时、网络、限流），退避后可重试。
  providerTransientFailure('PROVIDER_TRANSIENT_FAILURE', '数据源暂时不可用，稍后会自动重试。'),

  /// 所有数据源都没有返回所需字段。
  requestedFieldsEmpty('REQUESTED_FIELDS_EMPTY', '所选数据源没有返回需要的字段。'),

  /// 指定的数据源 ID 不在已知列表内。
  providerNotFound('PROVIDER_NOT_FOUND', '指定的数据源不存在。'),

  /// 设备无网络连接。
  networkUnavailable('NETWORK_UNAVAILABLE', '网络不可用。'),

  // ── 语音 ──

  /// 系统 TTS 引擎不可用或缺少所需语音包。
  ttsUnavailable('TTS_UNAVAILABLE', '系统语音合成不可用，请在系统设置中安装语音包。'),

  /// 合成过程出错。
  ttsSynthesisFailed('TTS_SYNTHESIS_FAILED', '语音合成失败。'),

  // ── 任务执行 ──

  /// 任务执行中抛出未预期的异常。
  workerException('WORKER_EXCEPTION', '任务执行时发生未预期的错误。'),

  /// 任务锁超过阈值未更新，判定为失效并重新入队。
  staleLock('STALE_LOCK', '任务锁已失效，已重新排队。'),

  /// 维护任务自动重试了失败任务。
  autoRetry('AUTO_RETRY', '任务自动重试。');

  // 枚举构造函数隐式为 const，无需显式标注。
  new(this.code, this.defaultMessage);

  /// 机器可读的错误码，用于日志与持久化。
  final String code;

  /// 面向用户的默认中文文案。
  final String defaultMessage;

  /// 按错误码字符串反查；未知码返回 `null`。
  ///
  /// 用于从数据库读回历史错误码时还原枚举。
  static AppErrorCode? fromCode(String code) {
    for (final value in AppErrorCode.values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

/// 所有业务错误的基类。
///
/// 用 `sealed` 修饰，使 `switch` 分支必须穷尽——新增子类时编译器会
/// 在每个 switch 处报错，避免遗漏处理。
sealed class AppError implements Exception {
  /// 以错误码构造。
  const new(this.code, {this.details});

  /// 错误码。
  final AppErrorCode code;

  /// 附加上下文，用于日志与调试，不展示给用户。
  final Object? details;

  /// 面向用户的提示文案。
  String get message => code.defaultMessage;

  /// 该错误是否值得重试。
  ///
  /// 旧版用 `(error as ApiError & { transient?: boolean })` 这种类型断言 hack
  /// 传递可重试性，此处改为正式字段。
  bool get isTransient => false;

  @override
  String toString() => 'AppError(${code.code}): $message';
}

/// 输入或参数不合法——重试无意义。
final class ValidationError extends AppError {
  /// 以错误码构造。
  const new(super.code, {super.details});
}

/// 目标不存在。
final class NotFoundError extends AppError {
  /// 以错误码构造。
  const new(super.code, {super.details});
}

/// 状态冲突，通常是并发或重复操作。
final class ConflictError extends AppError {
  /// 以错误码构造。
  const new(super.code, {super.details});
}

/// 外部服务（AI、词典、翻译）失败。
///
/// [isTransient] 决定是否切换备用 provider 或退避重试：
/// 超时、网络错误、空响应、限流属于瞬时错误；
/// 鉴权失败与响应格式错误切换无意义。
final class ExternalServiceError extends AppError {
  /// 以错误码与可重试性构造。
  const new(super.code, {this.isTransient = false, super.details});

  @override
  final bool isTransient;
}

/// 本地平台能力不可用（如系统 TTS 缺少语音包）。
final class PlatformCapabilityError extends AppError {
  /// 以错误码构造。
  const new(super.code, {super.details});
}

/// 把任意异常归一化为 [AppError]。
///
/// 用于 catch 边界，避免上层被迫处理未知类型，也避免旧版那种
/// `reason instanceof Error ? reason.message : fallback` 在二十多处重复。
AppError normalizeError(
  Object error, {
  AppErrorCode fallback = AppErrorCode.workerException,
}) {
  if (error is AppError) return error;
  return ExternalServiceError(fallback, details: error);
}
