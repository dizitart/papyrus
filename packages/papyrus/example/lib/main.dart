// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:papyrus/papyrus.dart';

void main() {
  runApp(const PapyrusExampleApp());
}

class PapyrusExampleApp extends StatelessWidget {
  const PapyrusExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Papyrus Example',
      home: const WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final PapyrusController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PapyrusController.create();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Papyrus WebView')),
      body: PapyrusView(
        controller: _controller,
        initialRequest: PapyrusHtmlRequest(
          html: '''
<!DOCTYPE html>
<html>
<head><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body>
  <h1>Hello from Papyrus!</h1>
  <p>A secure, policy-driven WebView for Flutter.</p>
</body>
</html>
''',
        ),
        onPageFinished: (uri) => print('Page finished: $uri'),
        onError: (event) => print('Error: ${event.message}'),
      ),
    );
  }
}
