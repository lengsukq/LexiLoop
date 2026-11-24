/// 多源文章加载器：本地文件（TXT / MD / SRT / VTT / HTML）与网页正文抓取。
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/domain/article_import/article_source_parser.dart';

/// 允许导入的本地文章文件扩展名。
const List<String> articleAllowedExtensions = <String>[
  'txt',
  'md',
  'markdown',
  'srt',
  'vtt',
  'html',
  'htm',
];

const Map<String, String> _webFetchHeaders = <String, String>{
  'Accept': 'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) LexiLoop/1.0',
};

/// 多源文章加载服务。
class ArticleSourceLoader {
  /// 以 HTTP 客户端构造。
  const new(this._fetcher);

  final HttpFetcher _fetcher;

  /// 打开系统文件选择器并解析本地文章/字幕文件；取消选择返回 `null`。
  Future<ParsedArticleSource?> pickLocalFile() async {
    final files = await FilePickerPlatform.instance.pickFiles(
      dialogTitle: '选择文章或字幕文件（TXT / MD / SRT / VTT / HTML）',
      type: FileType.custom,
      allowedExtensions: articleAllowedExtensions,
    );
    if (files.isEmpty) return null;
    final picked = files.first;
    final bytes = await picked.readAsBytes();
    if (bytes.length > maxArticleFileBytes) {
      throw const ValidationError(
        AppErrorCode.validationError,
        details: '所选文件过大（上限 2 MB），请拆分后导入。',
      );
    }
    final raw = _decodeUtf8(bytes);
    return parseArticleSource(raw, filename: picked.name);
  }

  /// 抓取网页并提取正文；不支持或失败时抛出可操作的 [AppError]。
  Future<ParsedArticleSource> fetchWebArticle(String rawUrl) async {
    final url = rawUrl.trim();
    if (!looksLikeHttpUrl(url)) {
      throw const ValidationError(
        AppErrorCode.validationError,
        details: '请输入有效的 http:// 或 https:// 网页链接。',
      );
    }
    try {
      final response = await _fetcher.get(
        url,
        headers: _webFetchHeaders,
        timeout: const Duration(milliseconds: defaultLlmTimeoutMs),
      );
      return _extractWebArticle(response);
    } on AppError {
      rethrow;
    } on Object catch (error) {
      const webTip = kIsWeb ? '（浏览器受跨域限制，建议直接复制正文粘贴）' : '';
      throw ExternalServiceError(
        kIsWeb
            ? AppErrorCode.browserCorsBlocked
            : AppErrorCode.networkUnavailable,
        details: '无法抓取该网页$webTip：$error',
      );
    }
  }

  ParsedArticleSource _extractWebArticle(HttpFetchResponse response) {
    if (response.statusCode < httpStatusOkMin ||
        response.statusCode >= httpStatusOkMax) {
      throw ExternalServiceError(
        AppErrorCode.networkUnavailable,
        details: '抓取网页失败（HTTP ${response.statusCode}），可复制网页正文后直接粘贴。',
      );
    }
    final parsed = parseArticleSource(response.body, contentType: 'text/html');
    if (parsed.text.trim().length < minArticleChars) {
      throw const ValidationError(
        AppErrorCode.validationError,
        details: '该网页未提取到足够正文（可能需要登录或由 JS 动态渲染），请复制文章正文后粘贴。',
      );
    }
    return parsed;
  }

  String _decodeUtf8(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      return text.startsWith('\uFEFF') ? text.substring(1) : text;
    } on FormatException {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}
