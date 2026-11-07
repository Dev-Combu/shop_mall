import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 수지씨앤엘 Cafe24 쇼핑몰의 게시판/마이쇼핑/약관 페이지 경로 모음.
///
/// 쇼핑몰 관리자 설정(게시판 번호)이 다르면 이 값만 수정하면 됩니다.
class MallPages {
  static const String base = 'https://suzicnl.com';

  static const String notice = '/board/free/list.html?board_no=1';
  static const String event = '/board/free/list.html?board_no=2';
  static const String faq = '/board/free/list.html?board_no=3';
  static const String review = '/board/product/list.html?board_no=4';
  static const String inquiry = '/board/consult/list.html'; // 1:1 맞춤상담
  static const String orders = '/myshop/order/list.html'; // 마이쇼핑 주문/배송조회
  static const String guestOrder = '/order/order_login.html'; // 비회원 주문조회 로그인
  static const String coupon = '/myshop/coupon/coupon.html';
  static const String mileage = '/myshop/mileage/historyList.html';
  static const String terms = '/member/mall_agreement.html';
  static const String privacy = '/member/privacy.html';
}

/// 쇼핑몰 웹 페이지를 앱 내부에서 보여주는 공용 화면.
/// 앱과 동일한 WebKit 쿠키 저장소를 사용하므로 로그인 세션이 유지됩니다.
class MallWebPage extends StatefulWidget {
  final String title;
  final String path;

  const MallWebPage({super.key, required this.title, required this.path});

  @override
  State<MallWebPage> createState() => _MallWebPageState();
}

class _MallWebPageState extends State<MallWebPage> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    final url = widget.path.startsWith('http')
        ? widget.path
        : '${MallPages.base}${widget.path}';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onNavigationRequest: (req) {
            final ok = req.url.startsWith('http://') ||
                req.url.startsWith('https://') ||
                req.url.startsWith('about:');
            return ok ? NavigationDecision.navigate : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else if (context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary)),
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: AppTheme.primary, size: 20),
            onPressed: () => context.pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: AppTheme.primary),
              onPressed: () => _controller.reload(),
            ),
          ],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress / 100,
                    minHeight: 2,
                    color: AppTheme.point,
                    backgroundColor: Colors.transparent,
                  ),
                )
              : null,
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
