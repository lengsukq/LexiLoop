/// 词书包领域模型与纯函数工具（纯 Dart，不依赖 Flutter/IO/Drift）。
library;

import 'dart:convert';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';

/// 词书包分类。
enum WordPackCategory implements WireEnum {
  /// 基础词汇（牛津核心 / 中考 / 高考）。
  foundation('FOUNDATION', '基础词汇'),

  /// 国内考试（四级 / 六级 / 考研）。
  examCn('EXAM_CN', '国内考试'),

  /// 出国留学（雅思 / 托福 / GRE）。
  examIntl('EXAM_INTL', '出国留学'),

  /// 自定义或本地导入词书。
  custom('CUSTOM', '自定义');

  new(this.wire, this.label);

  @override
  final String wire;

  /// 面向用户的分类名。
  final String label;

  /// 从 wire 值反查分类，未知值回退为 [custom]。
  static WordPackCategory fromWire(String? raw) =>
      wireLookup(values, raw ?? '') ?? custom;
}

/// 词书包的预初始化载荷等级。
enum WordPackContentMode implements WireEnum {
  /// 已在构建期通过有道词典完成全量预初始化，入库即 `READY`。
  fullYoudao('FULL_YOUDAO', '有道全量预初始化'),

  /// 基于 MIT 开源 ECDICT 预填充基础释义/音标/词形/有道音频 URL，
  /// 入库即 `PARTIAL` 可直接背诵，客户端再按需懒加载有道补全例句与短语。
  ecdictBase('ECDICT_BASE', '基础预填充 · 按需有道补全'),

  /// 仅含词条列表，入库为 `PENDING`，需走有道初始化后学习。
  wordlistOnly('WORDLIST_ONLY', '轻量词表 · 端侧补全');

  new(this.wire, this.label);

  @override
  final String wire;

  /// 面向用户的展示文案。
  final String label;

  /// 从 wire 值反查模式，未知值回退为 [ecdictBase]。
  static WordPackContentMode fromWire(String? raw) =>
      wireLookup(values, raw ?? '') ?? ecdictBase;
}

/// 单词本的来源作用域筛选。
enum WordSourceScope {
  /// 全部词条（个人词库 + 词书包）。
  all('全部'),

  /// 仅个人词库（`is_personal = 1`）。
  personal('个人词库'),

  /// 仅词书包词条（`EXISTS word_pack_items`）。
  packs('词书包');

  new(this.label);

  /// 展示标签。
  final String label;
}

/// 内置下载通道类型。
enum WordPackChannelKind {
  /// 智能优选（按可用加速通道顺位回退至 GitHub 直连）。
  auto('auto', '智能优选', '自动优先使用最快的国内加速通道，失败时自动切换直连'),

  /// jsDelivr GCore 边缘节点。
  jsdelivrGcore('jsdelivr_gcore', '加速通道 · jsDelivr (GCore)', '国内友好 CDN 加速'),

  /// jsDelivr Fastly 边缘节点。
  jsdelivrFastly('jsdelivr_fastly', '加速通道 · jsDelivr (Fastly)', '备用全球 CDN 节点'),

  /// ghfast.top 国内 GitHub 代理。
  ghfast('ghfast', '加速通道 · ghfast 镜像', '国内 GitHub Raw 加速代理'),

  /// gh-proxy.com 国内 GitHub 代理。
  ghproxy('ghproxy', '加速通道 · gh-proxy 镜像', '备用 GitHub 国内加速代理'),

  /// GitHub 官方直连。
  githubDirect('github_direct', '直连通道 · GitHub 官方', '直接访问 GitHub Raw 源文件'),

  /// 用户自定义加速前缀或自建静态源。
  custom('custom', '自定义通道', '使用自建镜像 / Cloudflare Worker 加速地址');

  new(this.id, this.label, this.subtitle);

  /// 持久化 ID。
  final String id;

  /// 通道名称。
  final String label;

  /// 通道说明。
  final String subtitle;

  /// 从持久化 ID 还原枚举，未知时回退为 [auto]。
  static WordPackChannelKind fromId(String? id) {
    for (final item in values) {
      if (item.id == id) return item;
    }
    return auto;
  }
}

/// 词书包下载通道配置（持久化在 `settings` 表）。
class WordPackDownloadConfig {
  /// 构造通道配置。
  const new({
    this.channel = WordPackChannelKind.auto,
    this.customBaseUrl = '',
    this.repoOverride = '',
    this.refOverride = '',
  });

  /// 从原始 JSON 反序列化。
  factory fromJson(Object? raw) {
    if (raw is! Map) return const WordPackDownloadConfig();
    return WordPackDownloadConfig(
      channel: WordPackChannelKind.fromId(_str(raw['channel'])),
      customBaseUrl: _str(raw['customBaseUrl']),
      repoOverride: _str(raw['repoOverride']),
      refOverride: _str(raw['refOverride']),
    );
  }

  /// 当前选中的通道。
  final WordPackChannelKind channel;

  /// 自定义源基础 URL 或代理前缀（例如 `https://my-proxy.example.com/`）。
  final String customBaseUrl;

  /// 可选覆盖仓库（`owner/repo`）。
  final String repoOverride;

  /// 可选覆盖 tag/branch。
  final String refOverride;

  /// 生效的仓库名。
  String get effectiveRepo {
    final clean = repoOverride.trim();
    return clean.isEmpty ? wordPackDefaultRepo : clean;
  }

  /// 生效的分支/标签名。
  String get effectiveRef {
    final clean = refOverride.trim();
    return clean.isEmpty ? wordPackDefaultRef : clean;
  }

  /// 复制并修改部分字段。
  WordPackDownloadConfig copyWith({
    WordPackChannelKind? channel,
    String? customBaseUrl,
    String? repoOverride,
    String? refOverride,
  }) => WordPackDownloadConfig(
    channel: channel ?? this.channel,
    customBaseUrl: customBaseUrl ?? this.customBaseUrl,
    repoOverride: repoOverride ?? this.repoOverride,
    refOverride: refOverride ?? this.refOverride,
  );

  /// 序列化为 JSON Map。
  Map<String, Object?> toJson() => <String, Object?>{
    'channel': channel.id,
    'customBaseUrl': customBaseUrl,
    'repoOverride': repoOverride,
    'refOverride': refOverride,
  };
}

/// 远端/内置词书目录中的单本词书描述。
class WordPackCatalogItem {
  /// 构造目录条目。
  const new({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
    required this.description,
    required this.version,
    required this.contentMode,
    required this.wordCount,
    required this.compressedBytes,
    required this.sha256,
    required this.relativePath,
    this.releaseAssetName = '',
    this.sourceLicense = '',
  });

  /// 稳定 ID。
  final String id;

  /// 路由友好短名。
  final String slug;

  /// 词书展示名。
  final String name;

  /// 词书分类。
  final WordPackCategory category;

  /// 简介。
  final String description;

  /// 版本号。
  final String version;

  /// 载荷预初始化等级。
  final WordPackContentMode contentMode;

  /// 预计/精确词量。
  final int wordCount;

  /// 压缩包字节数。
  final int compressedBytes;

  /// 期望 SHA-256（为空字符串时表示跳过强校验，仅允许从可信/远端刷新获取）。
  final String sha256;

  /// 仓库内相对路径（如 `packs/cet4.lexipack.json.gz`）。
  final String relativePath;

  /// GitHub Release 资产文件名（可选）。
  final String releaseAssetName;

  /// 词表开源协议说明。
  final String sourceLicense;

  /// 从 JSON Map 解析。
  static WordPackCatalogItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _str(raw['id']);
    final name = _str(raw['name']);
    final path = _str(raw['relativePath']);
    if (id.isEmpty || name.isEmpty || path.isEmpty) return null;
    return WordPackCatalogItem(
      id: id,
      slug: _str(raw['slug']).isEmpty ? id : _str(raw['slug']),
      name: name,
      category: WordPackCategory.fromWire(_str(raw['category'])),
      description: _str(raw['description']),
      version: _str(raw['version']).isEmpty ? '1.0' : _str(raw['version']),
      contentMode: WordPackContentMode.fromWire(_str(raw['contentMode'])),
      wordCount: _int(raw['wordCount']),
      compressedBytes: _int(raw['compressedBytes']),
      sha256: _str(raw['sha256']).toLowerCase(),
      relativePath: path,
      releaseAssetName: _str(raw['releaseAssetName']),
      sourceLicense: _str(raw['sourceLicense']),
    );
  }
}

/// 词书目录清单。
class WordPackCatalog {
  /// 构造词书目录。
  const new({
    required this.repo,
    required this.ref,
    required this.updatedAt,
    required this.packs,
  });

  /// 从 JSON 字符串解析目录。
  factory parse(String raw) {
    final decoded = _decodeJson(raw);
    if (decoded is! Map) {
      throw const ValidationError(AppErrorCode.wordPackInvalidFormat);
    }
    final rawPacks = decoded['packs'];
    if (rawPacks is! List) {
      throw const ValidationError(AppErrorCode.wordPackInvalidFormat);
    }
    final packs = <WordPackCatalogItem>[
      for (final item in rawPacks) ?WordPackCatalogItem.fromJson(item),
    ];
    final repo = _str(decoded['repo']);
    final ref = _str(decoded['ref']);
    return WordPackCatalog(
      repo: repo.isEmpty ? wordPackDefaultRepo : repo,
      ref: ref.isEmpty ? wordPackDefaultRef : ref,
      updatedAt: _str(decoded['updatedAt']),
      packs: List<WordPackCatalogItem>.unmodifiable(packs),
    );
  }

  /// 仓库标识（`owner/repo`）。
  final String repo;

  /// 标签/分支。
  final String ref;

  /// 清单更新时间（ISO-8601）。
  final String updatedAt;

  /// 词书列表。
  final List<WordPackCatalogItem> packs;
}

/// 词书包内单条词汇载荷。
class WordPackEntry {
  /// 构造单条词书载荷。
  const new({
    required this.term,
    required this.rank,
    this.sourceLanguage = 'en',
    this.targetLanguage = 'zh',
    this.contentType = LexicalContentType.word,
    this.definitions = const <Map<String, Object?>>[],
    this.pronunciations = const <Map<String, Object?>>[],
    this.examples = const <Map<String, Object?>>[],
    this.phrases = const <Map<String, Object?>>[],
    this.forms = const <Map<String, Object?>>[],
    this.synonyms = const <Map<String, Object?>>[],
    this.wordFamily = const <Map<String, Object?>>[],
    this.tags = const <String>[],
    this.summary,
  });

  /// 词条原文。
  final String term;

  /// 词书内部排序号（1 起）。
  final int rank;

  /// 源语言。
  final String sourceLanguage;

  /// 目标语言。
  final String targetLanguage;

  /// 内容类型。
  final LexicalContentType contentType;

  /// 释义列表（与 `word_contents.definitions_json` 同构）。
  final List<Map<String, Object?>> definitions;

  /// 发音列表（与 `word_contents.pronunciations_json` 同构）。
  final List<Map<String, Object?>> pronunciations;

  /// 例句列表。
  final List<Map<String, Object?>> examples;

  /// 短语列表。
  final List<Map<String, Object?>> phrases;

  /// 词形变化列表。
  final List<Map<String, Object?>> forms;

  /// 同近义词列表。
  final List<Map<String, Object?>> synonyms;

  /// 同根词列表。
  final List<Map<String, Object?>> wordFamily;

  /// 词条标签列表。
  final List<String> tags;

  /// 可选摘要（词频 / CEFR 等）。
  final Map<String, Object?>? summary;

  /// 是否已包含有效释义。
  bool get hasDefinitions =>
      definitions.any((item) => _str(item['text']).isNotEmpty);

  /// 是否已包含有道深度内容（例句或短语）。
  bool get hasRichContent => examples.isNotEmpty || phrases.isNotEmpty;

  /// 从 JSON Map 解析。
  static WordPackEntry? fromJson(Object? raw, int fallbackRank) {
    if (raw is! Map) return null;
    final term = _str(raw['term']);
    if (term.isEmpty) return null;
    final rank = _int(raw['rank']);
    return WordPackEntry(
      term: term,
      rank: rank > 0 ? rank : fallbackRank,
      sourceLanguage: _str(raw['sourceLanguage']).isEmpty
          ? 'en'
          : _str(raw['sourceLanguage']),
      targetLanguage: _str(raw['targetLanguage']).isEmpty
          ? 'zh'
          : _str(raw['targetLanguage']),
      contentType:
          wireLookup(LexicalContentType.values, _str(raw['contentType'])) ??
          LexicalContentType.word,
      definitions: _mapList(raw['definitions']),
      pronunciations: _mapList(raw['pronunciations']),
      examples: _mapList(raw['examples']),
      phrases: _mapList(raw['phrases']),
      forms: _mapList(raw['forms']),
      synonyms: _mapList(raw['synonyms']),
      wordFamily: _mapList(raw['wordFamily']),
      tags: _stringList(raw['tags']),
      summary: _mapOrNull(raw['summary']),
    );
  }
}

/// 解压并解析后的完整词书包载荷。
class WordPackPayload {
  /// 构造词书包载荷。
  const new({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
    required this.description,
    required this.version,
    required this.contentMode,
    required this.entries,
  });

  /// 从 UTF-8 JSON 字符串解析词书包。
  factory parse(String raw) {
    final decoded = _decodeJson(raw);
    if (decoded is! Map) {
      throw const ValidationError(AppErrorCode.wordPackInvalidFormat);
    }
    if (_str(decoded['format']) != wordPackFormatId) {
      throw const ValidationError(AppErrorCode.wordPackInvalidFormat);
    }
    final formatVersion = _int(decoded['formatVersion']);
    if (formatVersion < 1 || formatVersion > wordPackFormatVersion) {
      throw const ValidationError(AppErrorCode.wordPackInvalidFormat);
    }
    final meta = _mapOrNull(decoded['pack']) ?? decoded;
    final id = _str(meta['id']);
    final name = _str(meta['name']);
    final rawEntries = decoded['entries'];
    if (id.isEmpty || name.isEmpty || rawEntries is! List) {
      throw const ValidationError(AppErrorCode.wordPackInvalidFormat);
    }
    final entries = <WordPackEntry>[];
    for (var i = 0; i < rawEntries.length; i += 1) {
      final entry = WordPackEntry.fromJson(rawEntries[i], i + 1);
      if (entry != null) entries.add(entry);
    }
    return WordPackPayload(
      id: id,
      slug: _str(meta['slug']).isEmpty ? id : _str(meta['slug']),
      name: name,
      category: WordPackCategory.fromWire(_str(meta['category'])),
      description: _str(meta['description']),
      version: _str(meta['version']).isEmpty ? '1.0' : _str(meta['version']),
      contentMode: WordPackContentMode.fromWire(_str(meta['contentMode'])),
      entries: List<WordPackEntry>.unmodifiable(entries),
    );
  }

  /// 词书 ID。
  final String id;

  /// 词书 slug。
  final String slug;

  /// 词书名称。
  final String name;

  /// 词书分类。
  final WordPackCategory category;

  /// 简介。
  final String description;

  /// 数据版本。
  final String version;

  /// 预初始化等级。
  final WordPackContentMode contentMode;

  /// 词条列表。
  final List<WordPackEntry> entries;
}

/// 根据下载通道与相对路径构造候选 URL 列表（按优先级排序）。
List<String> resolveWordPackUrls({
  required WordPackDownloadConfig config,
  required String relativePath,
  String? repo,
  String? ref,
}) {
  final cleanPath = relativePath.replaceFirst(RegExp('^/+'), '');
  final targetRepo = (repo == null || repo.trim().isEmpty)
      ? config.effectiveRepo
      : repo.trim();
  final targetRef = (ref == null || ref.trim().isEmpty)
      ? config.effectiveRef
      : ref.trim();

  if (config.channel == WordPackChannelKind.auto) {
    return <String>[
      if (config.customBaseUrl.trim().isNotEmpty)
        buildChannelUrl(
          kind: WordPackChannelKind.custom,
          repo: targetRepo,
          ref: targetRef,
          relativePath: cleanPath,
          customBaseUrl: config.customBaseUrl,
        ),
      for (final kind in _autoChannelOrder)
        buildChannelUrl(
          kind: kind,
          repo: targetRepo,
          ref: targetRef,
          relativePath: cleanPath,
        ),
    ];
  }
  final url = buildChannelUrl(
    kind: config.channel,
    repo: targetRepo,
    ref: targetRef,
    relativePath: cleanPath,
    customBaseUrl: config.customBaseUrl,
  );
  return url.isEmpty ? const <String>[] : <String>[url];
}

/// 自动模式下的通道尝试顺序：国内加速通道优先，GitHub 官方直连兜底。
const List<WordPackChannelKind> _autoChannelOrder = <WordPackChannelKind>[
  WordPackChannelKind.jsdelivrGcore,
  WordPackChannelKind.ghfast,
  WordPackChannelKind.ghproxy,
  WordPackChannelKind.jsdelivrFastly,
  WordPackChannelKind.githubDirect,
];

/// 为指定通道拼出单个下载 URL。
String buildChannelUrl({
  required WordPackChannelKind kind,
  required String repo,
  required String ref,
  required String relativePath,
  String customBaseUrl = '',
}) {
  final cleanPath = relativePath.replaceFirst(RegExp('^/+'), '');
  final rawUrl = 'https://raw.githubusercontent.com/$repo/$ref/$cleanPath';
  return switch (kind) {
    WordPackChannelKind.auto =>
      'https://gcore.jsdelivr.net/gh/$repo@$ref/$cleanPath',
    WordPackChannelKind.jsdelivrGcore =>
      'https://gcore.jsdelivr.net/gh/$repo@$ref/$cleanPath',
    WordPackChannelKind.jsdelivrFastly =>
      'https://fastly.jsdelivr.net/gh/$repo@$ref/$cleanPath',
    WordPackChannelKind.ghfast => 'https://ghfast.top/$rawUrl',
    WordPackChannelKind.ghproxy => 'https://gh-proxy.com/$rawUrl',
    WordPackChannelKind.githubDirect => rawUrl,
    WordPackChannelKind.custom => _buildCustomUrl(
      customBaseUrl,
      rawUrl,
      cleanPath,
    ),
  };
}

String _buildCustomUrl(String rawBase, String githubRawUrl, String cleanPath) {
  final base = rawBase.trim();
  if (base.isEmpty) return '';
  if (base.contains('{url}')) {
    return base.replaceAll('{url}', githubRawUrl);
  }
  if (base.contains('{path}')) {
    return base.replaceAll('{path}', cleanPath);
  }
  final normalized = base.endsWith('/') ? base : '$base/';
  return '$normalized$cleanPath';
}

/// 格式化文件大小（如 `1.4 MB`、`480 KB`）。
String formatPackBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes >= bytesPerMiB) {
    return '${(bytes / bytesPerMiB).toStringAsFixed(1)} MB';
  }
  if (bytes >= bytesPerKiB) {
    return '${(bytes / bytesPerKiB).round()} KB';
  }
  return '$bytes B';
}

Object? _decodeJson(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException catch (error) {
    throw ValidationError(
      AppErrorCode.wordPackInvalidFormat,
      details: error.message,
    );
  }
}

String _str(Object? value) => value is String ? value.trim() : '';

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

Map<String, Object?>? _mapOrNull(Object? value) {
  if (value is! Map) return null;
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  for (final item in value) {
    final map = _mapOrNull(item);
    if (map != null) result.add(map);
  }
  return result;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return <String>[
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
