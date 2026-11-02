import 'package:flutter/material.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 실시간 택배사 배송추적 인앱 웹뷰 바텀시트
class DeliveryTrackingSheet extends StatefulWidget {
  final String carrierName;
  final String trackingNo;
  final String? customTrackingUrl;

  const DeliveryTrackingSheet({
    super.key,
    required this.carrierName,
    required this.trackingNo,
    this.customTrackingUrl,
  });

  /// 실시간 배송조회 바텀시트 열기 헬퍼
  static Future<void> show(
    BuildContext context, {
    required String carrierName,
    required String trackingNo,
    String? customTrackingUrl,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DeliveryTrackingSheet(
        carrierName: carrierName,
        trackingNo: trackingNo,
        customTrackingUrl: customTrackingUrl,
      ),
    );
  }

  @override
  State<DeliveryTrackingSheet> createState() => _DeliveryTrackingSheetState();
}

class _DeliveryTrackingSheetState extends State<DeliveryTrackingSheet> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _targetUrl = '';

  @override
  void initState() {
    super.initState();
    _targetUrl = _resolveTrackingUrl();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(_targetUrl));
  }

  /// 택배사명과 운송장번호를 기반으로 최적의 실시간 배송조회 URL 생성
  String _resolveTrackingUrl() {
    if (widget.customTrackingUrl != null &&
        widget.customTrackingUrl!.isNotEmpty) {
      return widget.customTrackingUrl!.replaceAll(
        '{tracking_no}',
        widget.trackingNo,
      );
    }

    final cleanNo = widget.trackingNo.replaceAll(RegExp(r'[^0-9]'), '');
    final name = widget.carrierName.toLowerCase();

    if (name.contains('cj') || name.contains('대한통운')) {
      return 'https://trace.cjlogistics.com/web/detail.jsp?slipno=$cleanNo';
    } else if (name.contains('우체국')) {
      return 'https://service.epost.go.kr/trace.RetrieveDomRtgTraceList.comm?sid1=$cleanNo';
    } else if (name.contains('한진')) {
      return 'https://www.hanjin.com/kor/CMS/DeliveryMgr/WaybillResult.do?mCode=MN038&schLang=KR&wblnumText2=$cleanNo';
    } else if (name.contains('롯데')) {
      return 'https://www.lotteglogis.com/home/reservation/tracking/linkView?InvNo=$cleanNo';
    } else if (name.contains('로젠')) {
      return 'https://www.ilogen.com/m/personal/trace/$cleanNo';
    }

    // 기본값: 배송조회 스마트 통합 검색 링크
    return 'https://search.naver.com/search.naver?query=${Uri.encodeComponent('${widget.carrierName} $cleanNo 배송조회')}';
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.85;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          // 드래그 핸들 및 헤더
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.local_shipping,
                      color: AppTheme.point,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '실시간 배송 조회 (${widget.carrierName})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '운송장번호: ${widget.trackingNo}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      color: const Color(0xFF64748B),
                      onPressed: () {
                        setState(() => _isLoading = true);
                        _controller.reload();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      color: const Color(0xFF64748B),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 웹뷰 영역
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.primary),
                        SizedBox(height: 12),
                        Text(
                          '택배사 배송 정보를 불러오는 중입니다...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

