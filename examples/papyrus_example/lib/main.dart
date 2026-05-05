import 'package:flutter/material.dart';
import 'package:papyrus/papyrus.dart';

void main() {
  runApp(const PapyrusExampleApp());
}

class PapyrusExampleApp extends StatefulWidget {
  const PapyrusExampleApp({super.key});

  @override
  State<PapyrusExampleApp> createState() => _PapyrusExampleAppState();
}

class _PapyrusExampleAppState extends State<PapyrusExampleApp> {
  final controller = PapyrusController.create();
  PapyrusConfiguration configuration = PapyrusProfiles.documentViewer();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Papyrus Example')),
        body: Column(
          children: [
            SegmentedButton<PapyrusConfiguration>(
              segments: [
                ButtonSegment(
                  value: PapyrusProfiles.documentViewer(),
                  label: const Text('Docs'),
                ),
                ButtonSegment(
                  value: PapyrusProfiles.emailHtmlViewer(),
                  label: const Text('Email'),
                ),
              ],
              selected: {configuration},
              onSelectionChanged: (value) {
                setState(() => configuration = value.single);
              },
            ),
            Expanded(
              child: PapyrusView(
                controller: controller,
                configuration: configuration,
                initialRequest: const PapyrusHtmlRequest(
                  html: '<h1>Papyrus</h1><p>Controlled HTML content.</p>',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
