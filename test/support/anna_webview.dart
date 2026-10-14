import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

void installAnnaWebView() => InAppWebViewPlatform.instance = _AnnaPlatform();
PlatformInAppWebViewWidgetCreationParams? annaViewParams;

class _AnnaPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _AnnaView(params);
  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _AnnaCookies(params);
}

class _AnnaView extends PlatformInAppWebViewWidget {
  _AnnaView(super.params) : super.implementation() {
    annaViewParams = params;
  }
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();
  @override
  void dispose() {}
}

class _AnnaCookies extends PlatformCookieManager {
  _AnnaCookies(super.params) : super.implementation();
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async => [Cookie(name: 'verified', value: 'yes')];
}

class AnnaPageController extends PlatformInAppWebViewController {
  AnnaPageController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'anna'),
      );
  WebUri url = WebUri('https://annas-archive.pk/search?q=book');
  String body = '<title>DDoS-Guard</title>';
  @override
  Future<WebUri?> getUrl() async => url;
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async => source == 'navigator.userAgent' ? 'Browser-UA' : body;
  @override
  void dispose({bool isKeepAlive = false}) {}
}
