# Email HTML Usage

Papyrus can render sanitized email HTML when paired with a separate MIME and
sanitization pipeline. The mail pipeline remains responsible for MIME parsing,
body selection, charset decoding, CID extraction, attachment extraction, HTML
sanitization, CSS cleanup, link rewriting, and tracking policy.

```dart
final config = PapyrusProfiles.emailHtmlViewer().copyWith(
  display: const PapyrusDisplayPolicy(autoHeight: true),
  resources: PapyrusResourcePolicy(
    remoteResources: PapyrusRemoteResourceMode.block,
    virtualResourceOrigin: Uri.parse('papyrus-resource://email.local/'),
  ),
);

await controller.load(
  PapyrusHtmlRequest(
    html: preparedEmail.sanitizedHtml,
    baseUri: preparedEmail.baseUri,
    virtualResources: preparedEmail.inlineResources,
  ),
);
```

Remote images are blocked by default. Inline resources are served through
`PapyrusVirtualResource` or `PapyrusVirtualResourceProvider`.

