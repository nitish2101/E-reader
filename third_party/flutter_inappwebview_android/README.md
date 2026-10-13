# Renderer disposal patch of flutter_inappwebview_android 1.1.3

Source: pub.dev 1.1.3 (SHA-256
62557c15a5c2db5d195cb3892aab74fcaec266d7b86d59a6f0027abd672cddba),
https://github.com/pichillilorenzo/flutter_inappwebview.
Original license retained. Dart API unchanged.

Native red reproduction on Android 16: first Page.crash recovered; second killed
host PID 5263 with “crash wasn't handled by all associated webviews”. Source
inspection found dispose installs a plain WebViewClient and reloads about:blank.
A terminated view cannot complete this normally; the disposal client can remain
associated with the next renderer and does not handle its subsequent death.

Patch (three Java files): remember termination in both supported WebViewClients;
destroy dead viewers directly instead of loading about:blank; have the disposal
client also handle renderer exit while a normal blank load is pending; make
destruction idempotent. Live viewer callbacks and normal loading are unchanged.
The app removes its failed platform view before awaiting checkpoint persistence.
Rebase this scoped override explicitly with any upstream upgrade.
