import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:papyrus/papyrus.dart';

void main() {
  runApp(const PapyrusTestbedApp());
}

class PapyrusTestbedApp extends StatelessWidget {
  const PapyrusTestbedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Papyrus Testbed',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
      ),
      home: const PapyrusTestbedHomePage(),
    );
  }
}

enum TestbedViewport { mobile, tablet, desktop }

extension TestbedViewportValues on TestbedViewport {
  String get label {
    return switch (this) {
      TestbedViewport.mobile => 'Mobile',
      TestbedViewport.tablet => 'Tablet',
      TestbedViewport.desktop => 'Desktop',
    };
  }

  Size get size {
    return switch (this) {
      TestbedViewport.mobile => const Size(390, 844),
      TestbedViewport.tablet => const Size(768, 1024),
      TestbedViewport.desktop => const Size(1440, 900),
    };
  }

  IconData get icon {
    return switch (this) {
      TestbedViewport.mobile => Icons.smartphone,
      TestbedViewport.tablet => Icons.tablet_mac,
      TestbedViewport.desktop => Icons.desktop_windows,
    };
  }
}

class PapyrusTestbedHomePage extends StatefulWidget {
  const PapyrusTestbedHomePage({super.key});

  @override
  State<PapyrusTestbedHomePage> createState() => _PapyrusTestbedHomePageState();
}

class _PapyrusTestbedHomePageState extends State<PapyrusTestbedHomePage> {
  final TextEditingController _htmlInputController = TextEditingController(
    text: _defaultHtml,
  );
  final TextEditingController _mimeInputController = TextEditingController(
    text: _defaultMime,
  );

  final PapyrusController _rawHtmlPreviewController =
      PapyrusController.create();
  final PapyrusController _mimePreviewController = PapyrusController.create();

  final PapyrusConfiguration _configuration = PapyrusProfiles.emailHtmlViewer();

  late final String _initialMimeHtml;

  TestbedViewport _activeViewport = TestbedViewport.mobile;
  String? _rawHtmlError;
  String? _mimeError;
  String _mimeSummary = '';

  @override
  void initState() {
    super.initState();
    final initial = MimeHtmlExtractor.extract(_defaultMime);
    _initialMimeHtml = initial.html;
    _mimeSummary = initial.summary;
  }

  @override
  void dispose() {
    _htmlInputController.dispose();
    _mimeInputController.dispose();
    _rawHtmlPreviewController.dispose();
    _mimePreviewController.dispose();
    super.dispose();
  }

  Future<void> _renderRawHtml() async {
    final raw = _htmlInputController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _rawHtmlError = 'Provide HTML content before rendering.';
      });
      return;
    }

    try {
      await _rawHtmlPreviewController.load(
        PapyrusHtmlRequest(
          html: raw,
          metadata: const PapyrusContentMetadata(
            contentType: 'text/html',
            source: 'papyrus_testbed_raw_html',
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _rawHtmlError = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _rawHtmlError = 'Failed to render HTML: $error';
      });
    }
  }

  Future<void> _renderMime() async {
    final raw = _mimeInputController.text;
    if (raw.trim().isEmpty) {
      setState(() {
        _mimeError = 'Provide MIME content before extraction.';
      });
      return;
    }

    try {
      final extracted = MimeHtmlExtractor.extract(raw);
      await _mimePreviewController.load(
        PapyrusHtmlRequest(
          html: extracted.html,
          metadata: const PapyrusContentMetadata(
            contentType: 'text/html',
            source: 'papyrus_testbed_mime',
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _mimeError = null;
        _mimeSummary = extracted.summary;
      });
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _mimeError = error.message;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _mimeError = 'Failed to parse MIME: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = _activeViewport.size;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Papyrus Testbed'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Raw HTML + CSS'),
              Tab(text: 'Raw MIME Email'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final selector = SegmentedButton<TestbedViewport>(
                    segments: TestbedViewport.values
                        .map(
                          (value) => ButtonSegment<TestbedViewport>(
                            value: value,
                            icon: Icon(value.icon),
                            label: Text(value.label),
                          ),
                        )
                        .toList(),
                    selected: {_activeViewport},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) {
                        return;
                      }
                      setState(() {
                        _activeViewport = selection.first;
                      });
                    },
                  );

                  final label = Text(
                    'Viewport: ${_activeViewport.label} '
                    '(${viewport.width.toInt()} x ${viewport.height.toInt()})',
                    style: Theme.of(context).textTheme.titleMedium,
                  );

                  if (constraints.maxWidth < 920) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        label,
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: selector,
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: label),
                      const SizedBox(width: 12),
                      selector,
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  _buildSplitPane(
                    editor: _buildRawHtmlEditor(),
                    preview: _buildPapyrusPreview(
                      controller: _rawHtmlPreviewController,
                      initialHtml: _defaultHtml,
                    ),
                  ),
                  _buildSplitPane(
                    editor: _buildMimeEditor(),
                    preview: _buildPapyrusPreview(
                      controller: _mimePreviewController,
                      initialHtml: _initialMimeHtml,
                      summary: _mimeSummary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitPane({required Widget editor, required Widget preview}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1100) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Expanded(flex: 5, child: editor),
                const SizedBox(height: 12),
                Expanded(flex: 6, child: preview),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(flex: 5, child: editor),
              const SizedBox(width: 12),
              Expanded(flex: 6, child: preview),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRawHtmlEditor() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Raw HTML + CSS Input',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _htmlInputController,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Paste HTML with embedded or linked CSS here',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _renderRawHtml,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Render in Papyrus'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    _htmlInputController.text = _defaultHtml;
                    _renderRawHtml();
                  },
                  child: const Text('Reset Sample'),
                ),
              ],
            ),
            if (_rawHtmlError != null) ...[
              const SizedBox(height: 8),
              Text(
                _rawHtmlError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMimeEditor() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Raw MIME Email Input',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _mimeInputController,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Paste a full MIME message with headers and body.',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _renderMime,
                  icon: const Icon(Icons.mark_email_read_outlined),
                  label: const Text('Extract + Render'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    _mimeInputController.text = _defaultMime;
                    _renderMime();
                  },
                  child: const Text('Reset Sample'),
                ),
              ],
            ),
            if (_mimeError != null) ...[
              const SizedBox(height: 8),
              Text(
                _mimeError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPapyrusPreview({
    required PapyrusController controller,
    required String initialHtml,
    String? summary,
  }) {
    final viewport = _activeViewport.size;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Papyrus Preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${_activeViewport.label}: '
              '${viewport.width.toInt()} x ${viewport.height.toInt()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (summary != null && summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(summary, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final resolvedViewport = _resolveViewportSize(
                      constraints: constraints,
                      baseViewport: viewport,
                      viewportType: _activeViewport,
                    );
                    return Center(
                      child: Container(
                        width: resolvedViewport.width,
                        height: resolvedViewport.height,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: PapyrusView(
                          controller: controller,
                          configuration: _configuration,
                          initialRequest: PapyrusHtmlRequest(html: initialHtml),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Size _resolveViewportSize({
    required BoxConstraints constraints,
    required Size baseViewport,
    required TestbedViewport viewportType,
  }) {
    var width = baseViewport.width;
    var height = baseViewport.height;

    if (viewportType == TestbedViewport.desktop && width > constraints.maxWidth) {
      final scale = constraints.maxWidth / width;
      width = constraints.maxWidth;
      height *= scale;
    }

    if (height > constraints.maxHeight) {
      final scale = constraints.maxHeight / height;
      height = constraints.maxHeight;
      width *= scale;
    }

    return Size(width, height);
  }
}

class MimeHtmlExtraction {
  const MimeHtmlExtraction({required this.html, required this.summary});

  final String html;
  final String summary;
}

class MimeHtmlExtractor {
  static MimeHtmlExtraction extract(String rawMime) {
    final normalized = _normalizeLineEndings(rawMime);
    if (normalized.trim().isEmpty) {
      throw const FormatException('MIME input is empty.');
    }

    final root = _MimeEntity.parse(normalized);
    final leaves = <_MimeEntity>[];
    root.collectLeaves(leaves);

    _MimeEntity? htmlPart;
    _MimeEntity? plainTextPart;
    final cssParts = <_MimeEntity>[];

    for (final part in leaves) {
      if (part.contentType == 'text/html' && htmlPart == null) {
        htmlPart = part;
      } else if (part.contentType == 'text/plain' && plainTextPart == null) {
        plainTextPart = part;
      } else if (part.contentType == 'text/css') {
        cssParts.add(part);
      }
    }

    if (htmlPart != null) {
      var html = htmlPart.decodeBody();
      if (cssParts.isNotEmpty) {
        final css = cssParts.map((part) => part.decodeBody()).join('\n\n');
        if (css.trim().isNotEmpty) {
          html = _injectCss(html, css);
        }
      }
      final summary = cssParts.isEmpty
          ? 'MIME extraction: rendering text/html part.'
          : 'MIME extraction: rendering text/html part + '
                '${cssParts.length} text/css part(s).';
      return MimeHtmlExtraction(html: html, summary: summary);
    }

    if (plainTextPart != null) {
      return MimeHtmlExtraction(
        html: _plainTextToHtml(plainTextPart.decodeBody()),
        summary:
            'MIME extraction: text/html part not found, using text/plain fallback.',
      );
    }

    if (_looksLikeHtml(normalized)) {
      return MimeHtmlExtraction(
        html: normalized,
        summary: 'Input looked like raw HTML; rendered directly as HTML.',
      );
    }

    throw const FormatException(
      'No text/html or text/plain body part was found in the MIME message.',
    );
  }

  static String _normalizeLineEndings(String input) {
    return input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static String _injectCss(String html, String css) {
    final styleTag = '<style>\n$css\n</style>';
    final closingHead = RegExp(r'</head>', caseSensitive: false);
    if (closingHead.hasMatch(html)) {
      return html.replaceFirst(closingHead, '$styleTag\n</head>');
    }
    return '$styleTag\n$html';
  }

  static String _plainTextToHtml(String text) {
    final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(text);
    return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <style>
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        padding: 16px;
        line-height: 1.4;
      }
      pre {
        margin: 0;
        white-space: pre-wrap;
        word-break: break-word;
      }
    </style>
  </head>
  <body><pre>$escaped</pre></body>
</html>
''';
  }

  static bool _looksLikeHtml(String text) {
    return RegExp(
      r'<!doctype\s+html|<html|<body|<head|<style',
      caseSensitive: false,
    ).hasMatch(text);
  }
}

class _MimeEntity {
  _MimeEntity({
    required this.headers,
    required this.body,
    required this.contentType,
    required this.parameters,
    required this.parts,
  });

  final Map<String, String> headers;
  final String body;
  final String contentType;
  final Map<String, String> parameters;
  final List<_MimeEntity> parts;

  static _MimeEntity parse(String input) {
    final separatorIndex = input.indexOf('\n\n');
    final headerBlock = separatorIndex >= 0
        ? input.substring(0, separatorIndex)
        : '';
    final body = separatorIndex >= 0
        ? input.substring(separatorIndex + 2)
        : input;

    final headers = _parseHeaders(headerBlock);
    final contentTypeHeader = headers['content-type'] ?? 'text/plain';
    final contentType = _mediaType(contentTypeHeader);
    final parameters = _parseHeaderParameters(contentTypeHeader);

    final boundary = parameters['boundary'];
    final isMultipart = contentType.startsWith('multipart/');
    final parts = isMultipart && boundary != null && boundary.isNotEmpty
        ? _parseMultipartParts(body, boundary)
        : <_MimeEntity>[];

    return _MimeEntity(
      headers: headers,
      body: body,
      contentType: contentType,
      parameters: parameters,
      parts: parts,
    );
  }

  void collectLeaves(List<_MimeEntity> output) {
    if (parts.isEmpty) {
      output.add(this);
      return;
    }
    for (final part in parts) {
      part.collectLeaves(output);
    }
  }

  String decodeBody() {
    final transferEncoding = (headers['content-transfer-encoding'] ?? '')
        .toLowerCase();
    final raw = body.trim();
    if (raw.isEmpty) {
      return '';
    }

    late Uint8List bytes;
    if (transferEncoding == 'base64') {
      try {
        bytes = Uint8List.fromList(
          base64.decode(raw.replaceAll(RegExp(r'\s+'), '')),
        );
      } on Object {
        bytes = Uint8List.fromList(raw.codeUnits);
      }
    } else if (transferEncoding == 'quoted-printable') {
      bytes = _decodeQuotedPrintable(raw);
    } else {
      bytes = Uint8List.fromList(raw.codeUnits);
    }

    final charset = parameters['charset'];
    final encoding = charset == null
        ? null
        : Encoding.getByName(charset.toLowerCase());
    if (encoding != null) {
      try {
        return encoding.decode(bytes);
      } on Object {
        return latin1.decode(bytes, allowInvalid: true);
      }
    }

    try {
      return utf8.decode(bytes, allowMalformed: true);
    } on Object {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  static Map<String, String> _parseHeaders(String block) {
    final unfolded = <String>[];
    final lines = block.split('\n');
    for (final line in lines) {
      if (line.isEmpty) {
        continue;
      }
      if ((line.startsWith(' ') || line.startsWith('\t')) &&
          unfolded.isNotEmpty) {
        unfolded[unfolded.length - 1] = '${unfolded.last} ${line.trimLeft()}';
      } else {
        unfolded.add(line);
      }
    }

    final headers = <String, String>{};
    for (final line in unfolded) {
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      headers[key] = value;
    }
    return headers;
  }

  static String _mediaType(String contentTypeHeader) {
    return contentTypeHeader.split(';').first.trim().toLowerCase();
  }

  static Map<String, String> _parseHeaderParameters(String headerValue) {
    final pieces = headerValue.split(';');
    final params = <String, String>{};
    for (var i = 1; i < pieces.length; i++) {
      final piece = pieces[i].trim();
      final separator = piece.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final key = piece.substring(0, separator).trim().toLowerCase();
      var value = piece.substring(separator + 1).trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      params[key] = value;
    }
    return params;
  }

  static List<_MimeEntity> _parseMultipartParts(String body, String boundary) {
    final startMarker = '--$boundary';
    final chunks = body.split(startMarker);
    if (chunks.length <= 1) {
      return const [];
    }

    final parts = <_MimeEntity>[];
    for (var i = 1; i < chunks.length; i++) {
      var chunk = chunks[i];
      if (chunk.startsWith('--')) {
        break;
      }
      chunk = chunk.trim();
      if (chunk.isEmpty) {
        continue;
      }
      parts.add(parse(chunk));
    }
    return parts;
  }

  static Uint8List _decodeQuotedPrintable(String input) {
    final output = <int>[];
    var i = 0;
    while (i < input.length) {
      final char = input[i];
      if (char == '=') {
        final nextIndex = i + 1;
        if (nextIndex >= input.length) {
          break;
        }

        final next = input[nextIndex];
        if (next == '\n') {
          i += 2;
          continue;
        }

        if (next == '\r' && i + 2 < input.length && input[i + 2] == '\n') {
          i += 3;
          continue;
        }

        if (i + 2 < input.length) {
          final hex = input.substring(i + 1, i + 3);
          final value = int.tryParse(hex, radix: 16);
          if (value != null) {
            output.add(value);
            i += 3;
            continue;
          }
        }
      }

      output.add(char.codeUnitAt(0));
      i += 1;
    }
    return Uint8List.fromList(output);
  }
}

const String _defaultHtml = '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      :root {
        --card-width: min(92vw, 560px);
        --bg: #f5f7fa;
        --text: #0f172a;
        --accent: #0f766e;
      }

      html,
      body {
        margin: 0;
        padding: 0;
        background: var(--bg);
        color: var(--text);
        font-family: "Segoe UI", system-ui, sans-serif;
      }

      .shell {
        min-height: 100vh;
        display: grid;
        place-items: center;
        padding: 16px;
      }

      .card {
        width: var(--card-width);
        border-radius: 14px;
        background: white;
        border: 1px solid #d1d5db;
        padding: 18px;
        box-shadow: 0 8px 30px rgba(15, 23, 42, 0.08);
      }

      h1 {
        margin: 0 0 8px;
        font-size: 24px;
        color: var(--accent);
      }

      p {
        margin: 0;
        line-height: 1.4;
      }
    </style>
  </head>
  <body>
    <main class="shell">
      <section class="card">
        <h1>Papyrus Testbed</h1>
        <p>Edit this HTML/CSS and click "Render in Papyrus" to preview.</p>
      </section>
    </main>
  </body>
</html>
''';

const String _defaultMime = '''
From: sender@example.com
To: receiver@example.com
Subject: Papyrus MIME Sample
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="papyrus-boundary-1"

--papyrus-boundary-1
Content-Type: text/plain; charset="utf-8"

Hello from plain text fallback.

--papyrus-boundary-1
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: quoted-printable

<!doctype html>
<html>
  <head>
    <meta charset=3D"utf-8" />
    <style>
      body { font-family: Segoe UI, sans-serif; padding: 16px; }
      .panel { border: 1px solid #0f766e; border-radius: 10px; padding: 14px; }
      .title { color: #0f766e; margin: 0 0 8px; }
      .note { margin: 0; }
    </style>
  </head>
  <body>
    <article class=3D"panel">
      <h2 class=3D"title">MIME HTML Part</h2>
      <p class=3D"note">This preview is extracted from raw MIME input.</p>
    </article>
  </body>
</html>

--papyrus-boundary-1--
''';
