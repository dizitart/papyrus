# Loading Content

Papyrus supports typed load requests:

- `PapyrusHtmlRequest` for HTML strings.
- `PapyrusUriRequest` for remote URLs.
- `PapyrusFileRequest` for explicitly allowed absolute local files.
- `PapyrusDataRequest` for bytes with a MIME type.

HTML string loads can include a base URI, metadata, and virtual resources:

```dart
await controller.load(
  PapyrusHtmlRequest(
    html: sanitizedHtml,
    baseUri: Uri.parse('papyrus-resource://message/42/'),
    metadata: const PapyrusContentMetadata(
      contentType: 'text/html',
      source: 'email',
      identifier: 'message-42',
    ),
    virtualResources: inlineResources,
  ),
);
```

Papyrus may inject a caller-supplied Content Security Policy for HTML string
loads. This is deterministic document composition, not HTML sanitization.

