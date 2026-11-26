/// 多源文章解析器的纯 Dart 单元测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/article_import/article_source_parser.dart';

void main() {
  group('looksLikeHttpUrl', () {
    test('识别合法 http/https 链接并拒绝普通文本', () {
      expect(looksLikeHttpUrl('https://example.com/article?id=1'), isTrue);
      expect(looksLikeHttpUrl('  http://news.bbc.co.uk/story  '), isTrue);
      expect(looksLikeHttpUrl('ftp://example.com/file.txt'), isFalse);
      expect(looksLikeHttpUrl('https://example.com two words'), isFalse);
      expect(looksLikeHttpUrl('Just an English sentence.'), isFalse);
      expect(looksLikeHttpUrl(''), isFalse);
    });
  });

  group('字幕解析（SRT / WebVTT）', () {
    test('SRT 去除序号、时间戳、样式标签并按句号合段', () {
      const srt = r'''
1
00:00:01,000 --> 00:00:03,500
<i>Resilient</i> ecosystems adapt quickly

2
00:00:03,600 --> 00:00:06,000
{\an8}to subtle environmental shifts.

3
00:00:06,100 --> 00:00:09,000
Scientists observe these changes carefully!
''';
      final parsed = parseArticleSource(srt, filename: 'ted_talk.srt');
      expect(parsed.format, ArticleSourceFormat.subtitle);
      expect(parsed.title, 'ted_talk');
      expect(
        parsed.text,
        'Resilient ecosystems adapt quickly to subtle environmental shifts.\n\n'
        'Scientists observe these changes carefully!',
      );
    });

    test('WebVTT 忽略头信息、NOTE 块与连续重复行', () {
      const vtt = '''
WEBVTT
Kind: captions
Language: en

NOTE This is a comment block
that spans two lines.

00:01.000 --> 00:03.000
Ubiquitous sensors gather data.

00:03.000 --> 00:05.000
Ubiquitous sensors gather data.
''';
      final parsed = parseArticleSource(vtt);
      expect(parsed.format, ArticleSourceFormat.subtitle);
      expect(parsed.text, 'Ubiquitous sensors gather data.');
    });
  });

  group('Markdown 解析', () {
    test('去除代码块、图片、链接地址与修饰符并提取一级标题', () {
      const md = '''
# Sustainable Architecture

Modern **cities** adopt [green roofs](https://example.com) and `passive` cooling.

![diagram](img/roof.png)

```python
print("ignore code block")
```

> Pragmatic planners balance cost and longevity.
''';
      final parsed = parseArticleSource(md, filename: 'arch.md');
      expect(parsed.format, ArticleSourceFormat.markdown);
      expect(parsed.title, 'Sustainable Architecture');
      expect(parsed.text, contains('Modern cities adopt green roofs'));
      expect(parsed.text, contains('Pragmatic planners balance cost'));
      expect(parsed.text, isNot(contains('ignore code block')));
      expect(parsed.text, isNot(contains('https://example.com')));
      expect(parsed.text, isNot(contains('diagram')));
    });
  });

  group('HTML 网页正文提取', () {
    test('优先提取 article 正文，剔除导航/脚本并解码实体', () {
      final longBody =
          'Contemporary economists scrutinize fiscal resilience &amp; '
              'monetary policy across emerging markets. ' *
          5;
      final html =
          '''
<!doctype html>
<html>
  <head>
    <title>Fiscal &amp; Monetary Review</title>
    <style>.nav { display: none; }</style>
  </head>
  <body>
    <nav><a href="/">Home</a><a href="/about">About</a></nav>
    <article>
      <h1>Fiscal Review</h1>
      <p>$longBody</p>
      <p>Policy makers must remain &#x201C;pragmatic&#x201D; &mdash; always.</p>
    </article>
    <script>console.log("noise");</script>
    <footer>Copyright 2026</footer>
  </body>
</html>
''';
      final parsed = parseArticleSource(html, contentType: 'text/html');
      expect(parsed.format, ArticleSourceFormat.html);
      expect(parsed.title, 'Fiscal & Monetary Review');
      expect(parsed.text, contains('Contemporary economists scrutinize'));
      expect(parsed.text, contains('“pragmatic” — always.'));
      expect(parsed.text, isNot(contains('Copyright 2026')));
      expect(parsed.text, isNot(contains('console.log')));
      expect(parsed.text, isNot(contains('Home')));
    });
  });
}
