## 0.1.0

* Initial release.
* Linux WebKitGTK backend for the Papyrus federated plugin.
* Uses the Flutter desktop overlay model.
* Navigation routed through WebKitGTK `decide-policy`; local-storage, cookie,
  and cache policy knobs applied via WebKit website-data manager.
* `clearCache` and `clearStorage` backed by `WebKitWebsiteDataManager`.
* `file://` and file-path loads blocked when `allowFileAccess` is false.
