## 0.1.1

* Added package-local LICENSE and example to improve pub.dev quality signals.

* Expanded public API documentation coverage for Linux implementation.

* Documentation and metadata refinements for pub score conformance.

## 0.1.0

* Initial release.
* Linux WebKitGTK backend for the Papyrus federated plugin.
* Uses the Flutter desktop overlay model.
* Navigation routed through WebKitGTK `decide-policy`; local-storage, cookie,
  and cache policy knobs applied via WebKit website-data manager.
* `clearCache` and `clearStorage` backed by `WebKitWebsiteDataManager`.
* `file://` and file-path loads blocked when `allowFileAccess` is false.
