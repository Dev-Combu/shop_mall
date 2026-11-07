import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/models/category.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/models/product_option.dart';

/// Cafe24ApiService Riverpod 전역 Provider
final cafe24ApiServiceProvider = Provider<Cafe24ApiService>((ref) {
  return Cafe24ApiService();
});

/// Cafe24 API 요청 관련 커스텀 예외 클래스
class Cafe24ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? errorCode;
  final dynamic originalError;

  Cafe24ApiException({
    required this.message,
    this.statusCode,
    this.errorCode,
    this.originalError,
  });

  @override
  String toString() =>
      'Cafe24ApiException(status: $statusCode, code: $errorCode, message: $message)';
}

/// Cafe24 쇼핑몰 Front API 클라이언트 (Client Secret 없는 안전한 공개 API 전용)
///
/// 관리자 권한(Admin API 및 Client Secret)을 배제하고,
/// 공개 Front API(Client ID + Front API Key)만을 사용하여
/// 상품, 카테고리, 리뷰 등 쇼핑몰 공개 데이터를 실시간으로 조회합니다.
class Cafe24ApiService {
  final Dio _dio;

  Cafe24ApiService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 10),
              ),
            );

  String get mallId => dotenv.env['Mall_ID']?.trim() ?? '';

  /// 현재 플랫폼(iOS / Android)에 맞는 Client ID 반환
  String get clientId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidId = dotenv.env['Client_ID_Android']?.trim() ?? '';
      if (androidId.isNotEmpty) return androidId;
    }
    final iosId = dotenv.env['Client_ID_IOS']?.trim() ?? '';
    if (iosId.isNotEmpty) return iosId;
    return dotenv.env['Client_ID_Android']?.trim() ?? '';
  }

  /// 현재 플랫폼에 맞는 Front API Key 반환
  String get frontApiKey {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidKey = dotenv.env['Front_Api_Key_Android']?.trim() ?? '';
      if (androidKey.isNotEmpty) return androidKey;
    }
    final iosKey = dotenv.env['Front_Api_Key_IOS']?.trim() ?? '';
    if (iosKey.isNotEmpty) return iosKey;
    return dotenv.env['Front_Api_Key_Android']?.trim() ?? '';
  }

  /// Front API 사용 가능 여부 (Client ID + Front API Key 존재 시 true)
  bool get hasFrontApiKey => clientId.isNotEmpty && frontApiKey.isNotEmpty;

  /// 유효한 인증 자격증명 보유 여부
  bool get hasCredentials => mallId.isNotEmpty && hasFrontApiKey;

  /// 하위 호환용 (Admin API 제거됨)
  bool get hasAdminCredentials => false;
  String? get lastOrderSyncError => null;

  /// Front API 전용 Basic Auth 헤더 생성 (Client_ID:Front_Api_Key Base64 인코딩)
  Map<String, String> _buildFrontApiHeaders() {
    final basicAuth = base64Encode(utf8.encode('$clientId:$frontApiKey'));
    return {
      'Authorization': 'Basic $basicAuth',
      'X-Cafe24-Client-Id': clientId,
      'Content-Type': 'application/json',
      'X-Cafe24-Api-Version': '2026-09-01',
    };
  }

  /// Front API GET 호출 헬퍼
  Future<Response<dynamic>> _getFrontApi(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final cleanEndpoint = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    final url = 'https://$mallId.cafe24api.com/api/v2/$cleanEndpoint';

    return await _dio.get(
      url,
      queryParameters: queryParameters,
      options: Options(headers: _buildFrontApiHeaders()),
    );
  }

  /// 상품 목록 조회
  ///
  /// [limit]: 가져올 상품 개수 (기본 20개, 최대 100개)
  /// [display]: 진열 여부 ('T': 진열된 상품만, 'F': 미진열)
  /// [selling]: 판매 여부 ('T': 판매중인 상품만, 'F': 미판매)
  Future<List<Product>> fetchProducts({
    int limit = 20,
    String display = 'T',
    String selling = 'T',
    int? categoryNo,
    bool forceNew = false,
    bool forceRecommend = false,
    String? forceTag,
  }) async {
    if (!hasFrontApiKey) {
      debugPrint('[Cafe24ApiService] Front API 키가 설정되지 않았습니다.');
      return [];
    }

    try {
      final queryParams = <String, dynamic>{
        'limit': limit.clamp(1, 100),
        'display': display,
        'selling': selling,
      };
      if (categoryNo != null) {
        queryParams['category'] = categoryNo;
      }

      final response = await _getFrontApi('products', queryParameters: queryParams);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final rawProducts = data['products'];
        if (rawProducts is List) {
          final List<Product> result = [];
          for (final item in rawProducts) {
            if (item is Map<String, dynamic>) {
              result.add(
                Product.fromCafe24Json(
                  item,
                  forceNew: forceNew,
                  forceRecommend: forceRecommend,
                  forceTag: forceTag,
                ),
              );
            }
          }
          return result;
        }
      }
      return [];
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      if (e is Cafe24ApiException) rethrow;
      throw Cafe24ApiException(
        message: '상품 목록을 불러오는 중 오류가 발생했습니다: $e',
        originalError: e,
      );
    }
  }

  /// 메인 진열 상품 목록 조회 (신상품 / 추천상품)
  Future<List<Product>> fetchMainDisplayProducts(
    int mainGroupNo, {
    int limit = 10,
    bool forceNew = false,
    bool forceRecommend = false,
    String? forceTag,
  }) async {
    if (!hasFrontApiKey) return [];

    try {
      final queryParams = <String, dynamic>{
        'limit': limit.clamp(1, 100),
      };

      final response = await _getFrontApi(
        'mains/$mainGroupNo/products',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final rawProducts = data['products'];
        if (rawProducts is List) {
          final productNos = <int>[];
          for (final p in rawProducts) {
            if (p is Map<String, dynamic>) {
              final pNo = int.tryParse(p['product_no']?.toString() ?? '');
              if (pNo != null) productNos.add(pNo);
            }
          }

          final detailMap = <int, Map<String, dynamic>>{};
          if (productNos.isNotEmpty) {
            try {
              final detailResp = await _getFrontApi(
                'products',
                queryParameters: {
                  'product_no': productNos.join(','),
                  'limit': productNos.length,
                },
              );

              if (detailResp.statusCode == 200 && detailResp.data is Map<String, dynamic>) {
                final detailList = (detailResp.data as Map<String, dynamic>)['products'];
                if (detailList is List) {
                  for (final dItem in detailList) {
                    if (dItem is Map<String, dynamic>) {
                      final no = int.tryParse(dItem['product_no']?.toString() ?? '');
                      if (no != null) detailMap[no] = dItem;
                    }
                  }
                }
              }
            } catch (_) {}
          }

          final List<Product> result = [];
          for (final item in rawProducts) {
            if (item is Map<String, dynamic>) {
              final pNo = int.tryParse(item['product_no']?.toString() ?? '');
              final mergedJson = <String, dynamic>{
                ...item,
                if (pNo != null && detailMap.containsKey(pNo)) ...detailMap[pNo]!,
              };

              result.add(
                Product.fromCafe24Json(
                  mergedJson,
                  forceNew: forceNew,
                  forceRecommend: forceRecommend,
                  forceTag: forceTag ?? (forceNew ? 'NEW' : (forceRecommend ? 'BEST' : null)),
                  forceTagColor: forceNew
                      ? const Color(0xFF16A34A)
                      : (forceRecommend ? const Color(0xFF1E293B) : null),
                ),
              );
            }
          }
          return result;
        }
      }
      return [];
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      if (e is Cafe24ApiException) rethrow;
      throw Cafe24ApiException(
        message: '메인 진열 상품을 불러오는 중 오류가 발생했습니다: $e',
        originalError: e,
      );
    }
  }

  /// 상품 단건 상세 조회
  Future<Product?> fetchProductDetail(String productNo) async {
    if (productNo.trim().isEmpty || !hasFrontApiKey) return null;

    try {
      final response = await _getFrontApi('products/$productNo');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final productJson = data['product'];
        if (productJson is Map<String, dynamic>) {
          return Product.fromCafe24Json(productJson);
        }
      }
      return null;
    } on DioException catch (e) {
      final handled = _handleDioException(e);
      debugPrint('[Cafe24ApiService] 단건 상품 조회 실패: ${handled.message}');
      return null;
    } catch (e) {
      debugPrint('[Cafe24ApiService] 단건 상품 조회 예외: $e');
      return null;
    }
  }

  /// 상품 옵션 및 추가 상품 옵션 정보 조회
  Future<ProductOptionsData> fetchProductOptions(String productNo) async {
    if (productNo.trim().isEmpty || !hasFrontApiKey) {
      return const ProductOptionsData();
    }

    try {
      final response = await _getFrontApi('products/$productNo/options');
      if (response.statusCode == 200 && response.data != null) {
        return ProductOptionsData.fromJson(
          response.data as Map<String, dynamic>,
        );
      }
      return const ProductOptionsData();
    } catch (e) {
      debugPrint('[Cafe24ApiService] 상품 옵션 조회 실패: $e');
      return const ProductOptionsData();
    }
  }

  /// 카테고리 목록 조회
  Future<List<ShopCategory>> fetchCategories() async {
    if (!hasFrontApiKey) return [];

    try {
      final response = await _getFrontApi('categories', queryParameters: {'limit': 100});

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final rawCats = data['categories'];
        if (rawCats is List) {
          return rawCats
              .whereType<Map<String, dynamic>>()
              .map((c) => ShopCategory.fromCafe24Json(c))
              .toList();
        }
      }
      return [];
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      if (e is Cafe24ApiException) rethrow;
      throw Cafe24ApiException(
        message: '카테고리 목록을 불러오는 중 오류가 발생했습니다: $e',
        originalError: e,
      );
    }
  }

  /// 상품의 대표 품목 코드(variant_code) 조회
  Future<String?> getProductDefaultVariantCode(String productNo) async {
    if (!hasFrontApiKey) return null;
    try {
      final resp = await _getFrontApi('products/$productNo/variants');
      if (resp.statusCode == 200 && resp.data != null) {
        final variants = resp.data['variants'];
        if (variants is List && variants.isNotEmpty) {
          final first = variants.first;
          if (first is Map<String, dynamic>) {
            return first['variant_code']?.toString();
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 배송비 정책 조회 (기본값: 3,000원, 30,000원 이상 무료배송)
  Future<({int baseFee, int freeThreshold})?> fetchShippingSettings() async {
    return (baseFee: 3000, freeThreshold: 30000);
  }

  /// 상품 사용후기(리뷰) 목록 조회
  Future<List<Map<String, dynamic>>> fetchProductReviews(
    String productNo, {
    int limit = 10,
  }) async {
    if (!hasFrontApiKey || productNo.trim().isEmpty) return const [];

    try {
      final response = await _getFrontApi(
        'products/$productNo/reviews',
        queryParameters: {'limit': limit.clamp(1, 50)},
      );

      if (response.statusCode == 200 && response.data != null) {
        final rawReviews = response.data['reviews'];
        if (rawReviews is List) {
          return rawReviews
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 하위 호환용 (Admin API 제거됨 - 주문 내역은 로컬 영구 저장 및 쇼핑몰 웹뷰 연동 사용)
  Future<List<OrderRecord>> fetchMemberOrders(String memberId, {int days = 90}) async =>
      const [];

  Future<OrderRecord?> fetchOrderDetail(String orderId) async => null;

  Cafe24ApiException _handleDioException(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String message = 'API 요청 중 오류가 발생했습니다.';
    String? code;

    if (data is Map<String, dynamic>) {
      final errorObj = data['error'];
      if (errorObj is Map<String, dynamic>) {
        message = errorObj['message']?.toString() ?? message;
        code = errorObj['code']?.toString();
      } else if (data['message'] != null) {
        message = data['message'].toString();
      }
    }

    return Cafe24ApiException(
      message: message,
      statusCode: status,
      errorCode: code,
      originalError: e,
    );
  }
}
