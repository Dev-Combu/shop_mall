import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Cafe24 상품 상세설명(HTML)을 콘텐츠 높이에 맞춰 렌더링하는 위젯.
///
/// 내부 스크롤 없이 페이지 스크롤에 자연스럽게 이어지도록
/// 로드 후 문서 높이를 측정하여 위젯 높이를 동적으로 조정합니다.
class ProductDetailHtmlView extends StatefulWidget {
  final String html;

  const ProductDetailHtmlView({super.key, required this.html});

  @override
  State<ProductDetailHtmlView> createState() => _ProductDetailHtmlViewState();
}

class _ProductDetailHtmlViewState extends State<ProductDetailHtmlView> {
  late final WebViewController _controller;
  double _height = 400;
  bool _loading = true;
  bool _pageLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (_pageLoaded) return;
            _pageLoaded = true;
            _measure();
          },
          onNavigationRequest: (req) {
            // 최초 HTML 로드(baseUrl 기반)는 허용하고, 이후 링크 클릭만 외부 브라우저로 이동
            if (!_pageLoaded ||
                req.url.startsWith('about:') ||
                req.url.startsWith('data:')) {
              return NavigationDecision.navigate;
            }
            final uri = Uri.tryParse(req.url);
            if (uri != null && req.isMainFrame) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(_wrap(widget.html), baseUrl: 'https://suzicnl.com');
  }

  String _wrap(String body) => '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  html, body { margin:0; padding:0; overflow-x:hidden; word-break:break-all; }
  img, video, iframe, table { max-width:100% !important; height:auto; }
  img { display:block; }
</style></head>
<body>$body</body></html>''';

  /// 이미지 지연 로딩을 고려해 여러 번 높이를 측정
  Future<void> _measure() async {
    for (final delay in const [0, 500, 1500, 3000]) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      try {
        final result = await _controller.runJavaScriptReturningResult(
          'Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)',
        );
        final h = double.tryParse(result.toString().replaceAll('"', ''));
        if (h != null && h > 0 && mounted) {
          setState(() {
            _loading = false;
            if ((h - _height).abs() > 1) _height = h;
          });
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: _height,
          child: WebViewWidget(controller: _controller),
        ),
        if (_loading)
          const Positioned.fill(
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
