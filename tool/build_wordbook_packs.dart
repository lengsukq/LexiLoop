/// 词书包离线构建工具：从 MIT 开源 ECDICT CSV 切分 9 本权威词书并打包为
/// `.lexipack.json.gz` + `catalog.json`（含精确词量、压缩体积与 SHA-256）。
///
/// 支持两种内容构建模式：
/// - `--enrich=ecdict`（默认，约 3 秒完成，100% MIT 开源合规）：
///   填充音标、有道发音 URL、中英释义、词形变化与考试标签；客户端下载即 `PARTIAL`
///   可直接背诵，学习时自动按需懒加载有道补全双语例句/短语/同根词。
/// - `--enrich=youdao`（断点续传缓存，去重约 1.5 万词）：
///   直接复用 LexiLoop 现成 `YoudaoProvider` 抓取全量有道内容并打包为 `FULL_YOUDAO`。
///
/// 示例：
/// ```bash
/// dart run tool/build_wordbook_packs.dart \
///   --ecdict=/tmp/ecdict.csv \
///   --out=build/wordbook_packs \
///   --enrich=ecdict \
///   --version=2026.1
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/dictionary/merge_content.dart';
import 'package:lexiloop/data/dictionary/providers/youdao_parser.dart';
import 'package:lexiloop/domain/enums.dart';

/// 词书定义。
class _PackSpec {
  const new({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.ecdictTag,
    this.matchOxfordFlag = false,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String ecdictTag;
  final bool matchOxfordFlag;
}

const List<_PackSpec> _defaultPackSpecs = <_PackSpec>[
  _PackSpec(
    id: 'oxford-3000',
    name: '牛津核心 3000 词',
    category: 'FOUNDATION',
    description: '牛津词典精选高频基础核心词，适合夯实日常阅读与听说根基。',
    ecdictTag: 'oxford',
    matchOxfordFlag: true,
  ),
  _PackSpec(
    id: 'zhongkao',
    name: '初中 / 中考核心词汇',
    category: 'FOUNDATION',
    description: '覆盖初中阶段与中考高频考纲核心词汇，按词频有序排列。',
    ecdictTag: 'zk',
  ),
  _PackSpec(
    id: 'gaokao',
    name: '高中 / 高考核心词汇',
    category: 'FOUNDATION',
    description: '高中课标与高考常考核心词汇，含音标、有道发音地址与基础释义。',
    ecdictTag: 'gk',
  ),
  _PackSpec(
    id: 'cet4',
    name: '大学英语四级 (CET-4)',
    category: 'EXAM_CN',
    description: '大学英语四级考试核心词汇，下载即可背诵并自动按需补全有道例句与短语。',
    ecdictTag: 'cet4',
  ),
  _PackSpec(
    id: 'cet6',
    name: '大学英语六级 (CET-6)',
    category: 'EXAM_CN',
    description: '大学英语六级完整考纲词表，与四级共享 FSRS 进度，已掌握词汇不重复背诵。',
    ecdictTag: 'cet6',
  ),
  _PackSpec(
    id: 'kaoyan',
    name: '考研英语核心词汇',
    category: 'EXAM_CN',
    description: '全国硕士研究生招生考试英语大纲核心词汇，按真题词频排序。',
    ecdictTag: 'ky',
  ),
  _PackSpec(
    id: 'ielts',
    name: '雅思核心词汇 (IELTS)',
    category: 'EXAM_INTL',
    description: '雅思听、说、读、写学术与通用高频核心词汇。',
    ecdictTag: 'ielts',
  ),
  _PackSpec(
    id: 'toefl',
    name: '托福核心词汇 (TOEFL)',
    category: 'EXAM_INTL',
    description: '托福学术阅读、讲座听力与综合写作高频核心词汇。',
    ecdictTag: 'toefl',
  ),
  _PackSpec(
    id: 'gre',
    name: 'GRE 核心词汇',
    category: 'EXAM_INTL',
    description: 'GRE Verbal 填空与阅读进阶高难词汇。',
    ecdictTag: 'gre',
  ),
];

/// 解析后的 ECDICT 词条行。
class _EcdictRecord {
  const new({
    required this.word,
    required this.phonetic,
    required this.definition,
    required this.translation,
    required this.oxford,
    required this.tags,
    required this.bnc,
    required this.frq,
    required this.exchange,
  });

  final String word;
  final String phonetic;
  final String definition;
  final String translation;
  final bool oxford;
  final Set<String> tags;
  final int bnc;
  final int frq;
  final String exchange;

  int get sortRank {
    if (bnc > 0 && frq > 0) return bnc < frq ? bnc : frq;
    if (bnc > 0) return bnc;
    if (frq > 0) return frq;
    return 999999;
  }
}

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  final ecdictPath = opts['ecdict'] ?? '';
  if (ecdictPath.isEmpty) {
    stderr.writeln(
      '用法: dart run tool/build_wordbook_packs.dart --ecdict=<path/to/ecdict.csv> '
      '[--out=build/wordbook_packs] [--enrich=ecdict|youdao] '
      '[--cache=build/youdao_cache.jsonl] [--version=2026.1] '
      '[--repo=lengsukq/LexiLoop-packs] [--ref=v1.0.0] '
      '[--packs=cet4,ielts] [--delay-ms=400]',
    );
    exitCode = 64;
    return;
  }
  final ecdictFile = File(ecdictPath);
  if (!ecdictFile.existsSync()) {
    stderr.writeln('找不到 ECDICT CSV 文件: $ecdictPath');
    exitCode = 66;
    return;
  }

  final outDir = Directory(opts['out'] ?? 'build/wordbook_packs');
  final packsDir = Directory('${outDir.path}/packs')
    ..createSync(recursive: true);
  final enrichMode = (opts['enrich'] ?? 'ecdict').toLowerCase();
  final useYoudao = enrichMode == 'youdao';
  final version = opts['version'] ?? '2026.1';
  final repo = opts['repo'] ?? wordPackDefaultRepo;
  final ref = opts['ref'] ?? wordPackDefaultRef;
  final delayMs = int.tryParse(opts['delay-ms'] ?? '') ?? 400;
  final selectedIds = (opts['packs'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  final specs = selectedIds.isEmpty
      ? _defaultPackSpecs
      : _defaultPackSpecs
            .where((spec) => selectedIds.contains(spec.id))
            .toList(growable: false);

  stdout.writeln('读取 ECDICT: $ecdictPath ...');
  final buckets = await _scanEcdict(ecdictFile, specs);
  final uniqueRecords = <String, _EcdictRecord>{};
  for (final list in buckets.values) {
    for (final rec in list) {
      uniqueRecords.putIfAbsent(rec.word.toLowerCase(), () => rec);
    }
  }
  stdout.writeln('已切分 ${specs.length} 本词书，去重独立词条共 ${uniqueRecords.length} 个。');

  final youdaoCache = <String, Map<String, Object?>>{};
  if (useYoudao) {
    final cachePath = opts['cache'] ?? '${outDir.path}/youdao_cache.jsonl';
    await _enrichAllWithYoudao(
      records: uniqueRecords,
      cacheFile: File(cachePath),
      outCache: youdaoCache,
      delayMs: delayMs,
    );
  }

  final catalogPacks = <Map<String, Object?>>[];
  for (final spec in specs) {
    final list = buckets[spec.id] ?? <_EcdictRecord>[]
      ..sort((a, b) {
        final byRank = a.sortRank.compareTo(b.sortRank);
        return byRank != 0 ? byRank : a.word.compareTo(b.word);
      });
    final contentMode = useYoudao ? 'FULL_YOUDAO' : 'ECDICT_BASE';
    final entries = <Map<String, Object?>>[
      for (var i = 0; i < list.length; i += 1)
        _buildEntry(
          record: list[i],
          rank: i + 1,
          youdaoFields: youdaoCache[list[i].word.toLowerCase()],
        ),
    ];
    final payload = <String, Object?>{
      'format': wordPackFormatId,
      'formatVersion': wordPackFormatVersion,
      'pack': <String, Object?>{
        'id': spec.id,
        'slug': spec.id,
        'name': spec.name,
        'category': spec.category,
        'description': spec.description,
        'version': version,
        'contentMode': contentMode,
      },
      'entries': entries,
    };
    final jsonBytes = utf8.encode(jsonEncode(payload));
    final gzBytes = gzip.encode(jsonBytes);
    final fileName = '${spec.id}.lexipack.json.gz';
    final outFile = File('${packsDir.path}/$fileName')
      ..writeAsBytesSync(gzBytes);
    final digest = sha256.convert(gzBytes).toString().toLowerCase();
    final kb = (gzBytes.length / 1024).toStringAsFixed(1);
    stdout.writeln(
      '  ✓ ${spec.id}: ${entries.length} 词 | '
      '$kb KB | sha256=${digest.substring(0, 12)}…',
    );
    catalogPacks.add(<String, Object?>{
      'id': spec.id,
      'slug': spec.id,
      'name': spec.name,
      'category': spec.category,
      'description': spec.description,
      'version': version,
      'contentMode': contentMode,
      'wordCount': entries.length,
      'compressedBytes': outFile.lengthSync(),
      'sha256': digest,
      'relativePath': 'packs/$fileName',
      'releaseAssetName': fileName,
      'sourceLicense': useYoudao ? 'ECDICT (MIT) + Youdao' : 'MIT (ECDICT)',
    });
  }

  final catalog = <String, Object?>{
    'format': 'lexiloop-wordbook-catalog',
    'version': 1,
    'repo': repo,
    'ref': ref,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'packs': catalogPacks,
  };
  final catalogFile = File('${outDir.path}/catalog.json')
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(catalog));
  stdout.writeln('构建完成！目录清单已输出至: ${catalogFile.path}');
}

Future<Map<String, List<_EcdictRecord>>> _scanEcdict(
  File file,
  List<_PackSpec> specs,
) async {
  final buckets = <String, List<_EcdictRecord>>{
    for (final spec in specs) spec.id: <_EcdictRecord>[],
  };
  final seenPerPack = <String, Set<String>>{
    for (final spec in specs) spec.id: <String>{},
  };
  final lines = file
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  var isHeader = true;
  final colIndex = <String, int>{};

  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final cols = _parseCsvLine(line);
    if (isHeader) {
      isHeader = false;
      for (var i = 0; i < cols.length; i += 1) {
        colIndex[cols[i].trim().toLowerCase()] = i;
      }
      continue;
    }
    final word = _col(cols, colIndex['word']).trim();
    if (!_isValidEnglishWord(word)) continue;
    final tagSet = _col(
      cols,
      colIndex['tag'],
    ).toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet();
    final oxford = _col(cols, colIndex['oxford']).trim() == '1';
    final matching = specs
        .where(
          (spec) =>
              tagSet.contains(spec.ecdictTag) ||
              (spec.matchOxfordFlag && oxford),
        )
        .toList(growable: false);
    if (matching.isEmpty) continue;

    final record = _EcdictRecord(
      word: word,
      phonetic: _col(cols, colIndex['phonetic']).trim(),
      definition: _col(cols, colIndex['definition']).trim(),
      translation: _col(cols, colIndex['translation']).trim(),
      oxford: oxford,
      tags: tagSet,
      bnc: int.tryParse(_col(cols, colIndex['bnc']).trim()) ?? 0,
      frq: int.tryParse(_col(cols, colIndex['frq']).trim()) ?? 0,
      exchange: _col(cols, colIndex['exchange']).trim(),
    );
    final lower = word.toLowerCase();
    for (final spec in matching) {
      if (seenPerPack[spec.id]!.add(lower)) {
        buckets[spec.id]!.add(record);
      }
    }
  }
  return buckets;
}

Future<void> _enrichAllWithYoudao({
  required Map<String, _EcdictRecord> records,
  required File cacheFile,
  required Map<String, Map<String, Object?>> outCache,
  required int delayMs,
}) async {
  if (cacheFile.existsSync()) {
    for (final line in cacheFile.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is Map<String, Object?> && decoded['term'] is String) {
        final fields = decoded['fields'];
        if (fields is Map<String, Object?>) {
          outCache[(decoded['term']! as String).toLowerCase()] = fields;
        }
      }
    }
    stdout.writeln('已加载有道断点缓存: ${outCache.length} 词。');
  }

  final sink = cacheFile.openWrite(mode: FileMode.append);
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent = audioUserAgent;
  var fetched = 0;
  var failed = 0;
  final total = records.length;

  try {
    for (final entry in records.entries) {
      if (outCache.containsKey(entry.key)) continue;
      final word = entry.value.word;
      try {
        final fields = await _fetchYoudaoFields(client, word);
        if (fields != null && fields.isNotEmpty) {
          outCache[entry.key] = fields;
          sink.writeln(
            jsonEncode(<String, Object?>{'term': entry.key, 'fields': fields}),
          );
          fetched += 1;
        } else {
          failed += 1;
        }
      } on Object catch (error) {
        failed += 1;
        stderr.writeln('  ! 有道抓取失败 [$word]: $error');
      }
      if ((fetched + failed) % 50 == 0) {
        await sink.flush();
        stdout.writeln(
          '有道预初始化进度: ${outCache.length} / $total（本轮成功 $fetched，失败 $failed）',
        );
      }
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
  } finally {
    client.close(force: true);
    await sink.flush();
    await sink.close();
  }
}

Future<Map<String, Object?>?> _fetchYoudaoFields(
  HttpClient client,
  String word,
) async {
  final encoded = Uri.encodeComponent(word);
  final urls = <String>[
    'https://dict.youdao.com/w/eng/$encoded',
    'https://www.youdao.com/result?word=$encoded&lang=en',
  ];
  final parsedList = <Map<String, Object?>>[];
  for (final url in urls) {
    final html = await _getHtml(client, url);
    if (html == null || html.isEmpty) continue;
    final parsed = parseYoudaoHtml(
      html,
      term: word,
      contentType: LexicalContentType.word,
      targetLanguage: 'zh',
    );
    if (parsed != null && hasAnyYoudaoContent(parsed)) {
      parsedList.add(parsed);
    }
  }
  if (parsedList.isEmpty) return null;
  return mergeContentFields(parsedList);
}

Future<String?> _getHtml(HttpClient client, String url) async {
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, audioUserAgent);
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      return null;
    }
    return await response.transform(utf8.decoder).join();
  } on Object {
    return null;
  }
}

Map<String, Object?> _buildEntry({
  required _EcdictRecord record,
  required int rank,
  Map<String, Object?>? youdaoFields,
}) {
  final baseDefs = _parseEcdictDefinitions(record);
  final baseProns = _buildEcdictPronunciations(record);
  final baseForms = _parseEcdictExchange(record.exchange);
  final baseTags = _humanTags(record);
  final summary = record.bnc > 0
      ? <String, Object?>{'frequency': 'BNC #${record.bnc}'}
      : null;

  if (youdaoFields == null) {
    return <String, Object?>{
      'term': record.word,
      'rank': rank,
      'definitions': baseDefs,
      'pronunciations': baseProns,
      if (baseForms.isNotEmpty) 'forms': baseForms,
      if (baseTags.isNotEmpty) 'tags': baseTags,
      'summary': ?summary,
    };
  }

  final yDefs = _listOfMaps(youdaoFields['definitions']);
  final yProns = _listOfMaps(youdaoFields['pronunciations']);
  final yExamples = _listOfMaps(youdaoFields['examples']);
  final yPhrases = _listOfMaps(youdaoFields['phrases']);
  final yForms = _listOfMaps(youdaoFields['forms']);
  final ySynonyms = _listOfMaps(youdaoFields['synonyms']);
  final yFamily = _listOfMaps(youdaoFields['wordFamily']);
  return <String, Object?>{
    'term': record.word,
    'rank': rank,
    'definitions': yDefs.isNotEmpty ? yDefs : baseDefs,
    'pronunciations': yProns.isNotEmpty ? yProns : baseProns,
    if (yExamples.isNotEmpty) 'examples': yExamples.take(3).toList(),
    if (yPhrases.isNotEmpty) 'phrases': yPhrases.take(6).toList(),
    if (yForms.isNotEmpty || baseForms.isNotEmpty)
      'forms': yForms.isNotEmpty ? yForms : baseForms,
    if (ySynonyms.isNotEmpty) 'synonyms': ySynonyms.take(6).toList(),
    if (yFamily.isNotEmpty) 'wordFamily': yFamily.take(8).toList(),
    if (baseTags.isNotEmpty) 'tags': baseTags,
    'summary': ?summary,
  };
}

List<Map<String, Object?>> _parseEcdictDefinitions(_EcdictRecord record) {
  final out = <Map<String, Object?>>[];
  final posRe = RegExp(r'^([a-zA-Z]+)\.\s*(.+)$');
  for (final raw in record.translation.split(RegExp(r'\\n|\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final match = posRe.firstMatch(line);
    out.add(<String, Object?>{
      'language': 'zh',
      'partOfSpeech': match?.group(1),
      'text': (match?.group(2) ?? line).trim(),
      'source': ecdictDictionarySource,
      'isUserEdited': false,
    });
  }
  for (final raw in record.definition.split(RegExp(r'\\n|\n')).take(2)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final match = posRe.firstMatch(line);
    out.add(<String, Object?>{
      'language': 'en',
      'partOfSpeech': match?.group(1),
      'text': (match?.group(2) ?? line).trim(),
      'source': ecdictDictionarySource,
      'isUserEdited': false,
    });
  }
  return out;
}

List<Map<String, Object?>> _buildEcdictPronunciations(_EcdictRecord record) {
  final encoded = Uri.encodeComponent(record.word);
  final phonetic = record.phonetic.replaceAll(RegExp(r'[\[\]/]'), '').trim();
  if (phonetic.isEmpty) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    <String, Object?>{
      'accent': 'UK',
      'phonetic': phonetic,
      'audioUrl': '$youdaoAudioEndpoint?audio=$encoded&type=1',
      'source': ecdictDictionarySource,
      'isSynthetic': false,
    },
    <String, Object?>{
      'accent': 'US',
      'phonetic': phonetic,
      'audioUrl': '$youdaoAudioEndpoint?audio=$encoded&type=2',
      'source': ecdictDictionarySource,
      'isSynthetic': false,
    },
  ];
}

List<Map<String, Object?>> _parseEcdictExchange(String exchange) {
  if (exchange.isEmpty) return const <Map<String, Object?>>[];
  const map = <String, String>{
    'p': 'PAST',
    'd': 'PAST_PARTICIPLE',
    'i': 'PRESENT_PARTICIPLE',
    '3': 'THIRD_PERSON',
    'r': 'COMPARATIVE',
    't': 'SUPERLATIVE',
    's': 'PLURAL',
  };
  final out = <Map<String, Object?>>[];
  for (final part in exchange.split('/')) {
    final colon = part.indexOf(':');
    if (colon <= 0) continue;
    final type = map[part.substring(0, colon)];
    final value = part.substring(colon + 1).trim();
    if (type == null || value.isEmpty) continue;
    out.add(<String, Object?>{
      'type': type,
      'value': value,
      'source': ecdictDictionarySource,
    });
  }
  return out;
}

List<String> _humanTags(_EcdictRecord record) {
  const labels = <String, String>{
    'zk': '中考',
    'gk': '高考',
    'cet4': 'CET4',
    'cet6': 'CET6',
    'ky': '考研',
    'ielts': '雅思',
    'toefl': '托福',
    'gre': 'GRE',
  };
  final out = <String>[
    if (record.oxford) '牛津3000',
    for (final entry in labels.entries)
      if (record.tags.contains(entry.key)) entry.value,
  ];
  return out;
}

bool _isValidEnglishWord(String word) =>
    word.length >= 2 &&
    word.length <= 60 &&
    RegExp(r"^[a-zA-Z][a-zA-Z\s'-]*$").hasMatch(word);

String _col(List<String> cols, int? index) =>
    index == null || index < 0 || index >= cols.length ? '' : cols[index];

List<String> _parseCsvLine(String line) {
  final out = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i += 1) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        buffer.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      out.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  out.add(buffer.toString());
  return out;
}

List<Map<String, Object?>> _listOfMaps(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final item in raw)
      if (item is Map<String, Object?>) item,
  ];
}

Map<String, String> _parseArgs(List<String> args) {
  final result = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final eq = arg.indexOf('=');
    if (eq > 2) {
      result[arg.substring(2, eq)] = arg.substring(eq + 1);
    }
  }
  return result;
}
