import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 우편번호 검색 결과 모델
class PostcodeResult {
  final String zipCode;
  final String address;
  final String roadAddress;
  final String jibunAddress;
  final String buildingName;

  const PostcodeResult({
    required this.zipCode,
    required this.address,
    required this.roadAddress,
    required this.jibunAddress,
    required this.buildingName,
  });
}

/// Daum/Kakao 공식 우편번호 서비스(postcode.v2.js)를 내장한 주소 검색 모달 시트 호출 헬퍼
Future<PostcodeResult?> showPostcodeSearchSheet(BuildContext context) {
  return showModalBottomSheet<PostcodeResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => const _PostcodeSearchSheet(),
  );
}

class _PostcodeSearchSheet extends StatefulWidget {
  const _PostcodeSearchSheet();

  @override
  State<_PostcodeSearchSheet> createState() => _PostcodeSearchSheetState();
}

class _PostcodeSearchSheetState extends State<_PostcodeSearchSheet> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  static const String _postcodeHtml = '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>우편번호 검색</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body { width: 100%; height: 100%; overflow: hidden; background-color: #ffffff; }
    #wrap { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div id="wrap"></div>
  <script src="https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"></script>
  <script>
    function initPostcode() {
      if (typeof daum === 'undefined' || !daum.Postcode) {
        setTimeout(initPostcode, 150);
        return;
      }
      var wrap = document.getElementById('wrap');
      new daum.Postcode({
        oncomplete: function(data) {
          var addr = '';
          var extraAddr = '';

          if (data.userSelectedType === 'R') {
            addr = data.roadAddress || data.autoRoadAddress || '';
          } else {
            addr = data.jibunAddress || data.autoJibunAddress || '';
          }
          if (!addr) {
            addr = data.roadAddress || data.jibunAddress || data.address || '';
          }

          if (data.userSelectedType === 'R') {
            if (data.bname !== '' && /[동|로|가]\$/g.test(data.bname)) {
              extraAddr += data.bname;
            }
            if (data.buildingName !== '' && data.apartment === 'Y') {
              extraAddr += (extraAddr !== '' ? ', ' + data.buildingName : data.buildingName);
            }
            if (extraAddr !== '') {
              addr += ' (' + extraAddr + ')';
            }
          }

          var payload = {
            zonecode: data.zonecode || '',
            address: addr,
            roadAddress: data.roadAddress || data.autoRoadAddress || '',
            jibunAddress: data.jibunAddress || data.autoJibunAddress || '',
            buildingName: data.buildingName || ''
          };
          PostcodeBridge.postMessage(JSON.stringify(payload));
        },
        width: '100%',
        height: '100%',
        maxSuggestItems: 5
      }).embed(wrap);
    }
    window.addEventListener('DOMContentLoaded', initPostcode);
  </script>
</body>
</html>
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'PostcodeBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handlePostcodeSelected(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
        ),
      )
      ..loadHtmlString(
        _postcodeHtml,
        baseUrl: 'https://suzicnl.com',
      );
  }

  void _handlePostcodeSelected(String rawJson) {
    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final zipCode = (map['zonecode'] ?? '').toString().trim();
      final address = (map['address'] ?? '').toString().trim();
      final roadAddress = (map['roadAddress'] ?? '').toString().trim();
      final jibunAddress = (map['jibunAddress'] ?? '').toString().trim();
      final buildingName = (map['buildingName'] ?? '').toString().trim();

      if (zipCode.isNotEmpty || address.isNotEmpty) {
        Navigator.of(context).pop(
          PostcodeResult(
            zipCode: zipCode,
            address: address,
            roadAddress: roadAddress,
            jibunAddress: jibunAddress,
            buildingName: buildingName,
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenHeight * 0.82,
      child: Column(
        children: [
          // 상단 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '우편번호 / 주소 검색',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),

          // 본문 WebView
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
                          '우편번호 검색 서비스를 불러오는 중...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_hasError)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            size: 40,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '주소 검색 서비스를 불러오지 못했습니다.\n네트워크 연결을 확인해주세요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF64748B),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                                _hasError = false;
                              });
                              _controller.loadHtmlString(
                                _postcodeHtml,
                                baseUrl: 'https://suzicnl.com',
                              );
                            },
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('다시 시도'),
                          ),
                        ],
                      ),
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

