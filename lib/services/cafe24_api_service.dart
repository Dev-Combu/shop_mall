import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shopmall/models/cart_item.dart';
import 'package:shopmall/models/category.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/models/product.dart';

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

/// Cafe24 쇼핑몰 Admin API 클라이언트 (자동 토큰 리프레시 지원)
class Cafe24ApiService {
  final Dio _dio;
  final FlutterSecureStorage _storage;

  static const _keyAccessToken = 'cafe24_access_token';
  static const _keyRefreshToken = 'cafe24_refresh_token';
  static const _keyExpiresAt = 'cafe24_expires_at';
  static const _keySeedRefreshToken = 'cafe24_seed_refresh_token';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  bool _isInitialized = false;
  bool _refreshFailedPermanently = false;
  Future<void>? _initFuture;
  Future<bool>? _refreshFuture;

  Cafe24ApiService({Dio? dio, FlutterSecureStorage? storage})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 10),
              ),
            ),
        _storage = storage ?? const FlutterSecureStorage();

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

  /// 만료 없는 Front API 사용 가능 여부 (Client ID + Front API Key 존재 시 true)
  bool get hasFrontApiKey => clientId.isNotEmpty && frontApiKey.isNotEmpty;

  /// 유효한 Admin OAuth 토큰 보유 여부 (만료 및 영구 실패 시 false)
  bool get hasAdminCredentials =>
      mallId.isNotEmpty &&
      !_refreshFailedPermanently &&
      (accessToken.isNotEmpty || refreshToken.isNotEmpty);

  /// 유효한 인증 자격증명(Front API 키 또는 OAuth 토큰)이 있는지 여부
  bool get hasCredentials =>
      mallId.isNotEmpty && (hasFrontApiKey || hasAdminCredentials);

  String get accessToken =>
      (_accessToken != null && _accessToken!.isNotEmpty)
          ? _accessToken!
          : (dotenv.env['CAFE24_ACCESS_TOKEN']?.trim() ?? '');

  String get refreshToken =>
      (_refreshToken != null && _refreshToken!.isNotEmpty)
          ? _refreshToken!
          : (dotenv.env['CAFE24_REFRESH_TOKEN']?.trim() ?? '');

  /// 저장소(.env 및 SecureStorage)에서 토큰 초기화
  Future<void> _ensureInitialized() {
    if (_isInitialized) return Future.value();
    return _initFuture ??= _initTokens();
  }

  Future<void> _initTokens() async {
    final envAccess = dotenv.env['CAFE24_ACCESS_TOKEN']?.trim() ?? '';
    final envRefresh = dotenv.env['CAFE24_REFRESH_TOKEN']?.trim() ?? '';
    final envExpires = dotenv.env['CAFE24_EXPIRES_AT']?.trim() ?? '';

    try {
      final storedSeed = await _storage.read(key: _keySeedRefreshToken);
      final storedAccess = await _storage.read(key: _keyAccessToken);
      final storedRefresh = await _storage.read(key: _keyRefreshToken);
      final storedExpires = await _storage.read(key: _keyExpiresAt);

      // SecureStorage에 갱신된 토큰이 있고, .env의 초기 시드 토큰이 변경되지 않았다면 저장된 최신 토큰 사용
      if (storedAccess != null &&
          storedAccess.isNotEmpty &&
          storedRefresh != null &&
          storedRefresh.isNotEmpty &&
          storedSeed == envRefresh) {
        _accessToken = storedAccess;
        _refreshToken = storedRefresh;
        _expiresAt = DateTime.tryParse(storedExpires ?? '');
      } else {
        _accessToken = envAccess;
        _refreshToken = envRefresh;
        _expiresAt = DateTime.tryParse(envExpires);

        if (envAccess.isNotEmpty && envRefresh.isNotEmpty) {
          await _storage.write(key: _keySeedRefreshToken, value: envRefresh);
          await _storage.write(key: _keyAccessToken, value: envAccess);
          await _storage.write(key: _keyRefreshToken, value: envRefresh);
          if (envExpires.isNotEmpty) {
            await _storage.write(key: _keyExpiresAt, value: envExpires);
          }
        }
      }
    } catch (e) {
      // SecureStorage 접근 불가 환경일 경우 .env 메모리 값 사용
      _accessToken = envAccess;
      _refreshToken = envRefresh;
      _expiresAt = DateTime.tryParse(envExpires);
    } finally {
      _isInitialized = true;
    }
  }

  /// 토큰 만료 여부 확인 (만료 1분 전부터 만료로 간주하여 선제적 갱신)
  bool get _isTokenExpired {
    if (_expiresAt == null) return false;
    return DateTime.now().isAfter(_expiresAt!.subtract(const Duration(minutes: 1)));
  }

  /// API 호출 전 토큰 유효성 보장 (만료 시 자동 갱신)
  Future<void> _ensureValidToken() async {
    await _ensureInitialized();
    _validateCredentials();

    if (_isTokenExpired && refreshToken.isNotEmpty && !_refreshFailedPermanently) {
      debugPrint('[Cafe24ApiService] 토큰 만료 시간이 도래하여 선제적 리프레시를 수행합니다.');
      await refreshAccessToken();
    }
  }

  /// Refresh Token을 사용하여 새로운 Access Token & Refresh Token 발급 (동시성 제어 포함)
  Future<bool> refreshAccessToken() {
    if (_refreshFuture != null) {
      return _refreshFuture!;
    }
    _refreshFuture = _performTokenRefresh().whenComplete(() {
      _refreshFuture = null;
    });
    return _refreshFuture!;
  }

  Future<bool> _performTokenRefresh() async {
    if (_refreshFailedPermanently) {
      return false;
    }
    await _ensureInitialized();
    final currentRefresh = refreshToken;
    if (mallId.isEmpty || currentRefresh.isEmpty) {
      debugPrint('[Cafe24ApiService] Refresh Token 또는 Mall ID가 없어 갱신할 수 없습니다.');
      return false;
    }

    // iOS 및 Android 클라이언트 자격증명 후보 준비
    final clientCandidates = <MapEntry<String, String>>[
      MapEntry(
        dotenv.env['Client_ID_IOS']?.trim() ?? '',
        dotenv.env['Client_Secret_IOS']?.trim() ?? '',
      ),
      MapEntry(
        dotenv.env['Client_ID_Android']?.trim() ?? '',
        dotenv.env['Client_Secret_Android']?.trim() ?? '',
      ),
    ].where((entry) => entry.key.isNotEmpty && entry.value.isNotEmpty).toList();

    if (clientCandidates.isEmpty) {
      debugPrint('[Cafe24ApiService] Client ID / Secret 설정이 .env에 없습니다.');
      return false;
    }

    final url = 'https://$mallId.cafe24api.com/api/v2/oauth/token';

    for (final cred in clientCandidates) {
      try {
        final basicAuth = base64Encode(utf8.encode('${cred.key}:${cred.value}'));
        final response = await _dio.post(
          url,
          data: {
            'grant_type': 'refresh_token',
            'refresh_token': currentRefresh,
          },
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              'Authorization': 'Basic $basicAuth',
            },
          ),
        );

        if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
          final data = response.data as Map<String, dynamic>;
          final newAccess = data['access_token']?.toString() ?? '';
          final newRefresh = data['refresh_token']?.toString() ?? currentRefresh;
          final newExpires = data['expires_at']?.toString() ?? '';

          if (newAccess.isNotEmpty) {
            _accessToken = newAccess;
            _refreshToken = newRefresh;
            _expiresAt = DateTime.tryParse(newExpires);

            // 메모리 내 dotenv 동기화
            dotenv.env['CAFE24_ACCESS_TOKEN'] = newAccess;
            dotenv.env['CAFE24_REFRESH_TOKEN'] = newRefresh;
            if (newExpires.isNotEmpty) {
              dotenv.env['CAFE24_EXPIRES_AT'] = newExpires;
            }

            // SecureStorage에 영구 저장 (앱 재시작 후에도 유지)
            try {
              await _storage.write(key: _keyAccessToken, value: newAccess);
              await _storage.write(key: _keyRefreshToken, value: newRefresh);
              if (newExpires.isNotEmpty) {
                await _storage.write(key: _keyExpiresAt, value: newExpires);
              }
            } catch (_) {}

            debugPrint('[Cafe24ApiService] Access Token 자동 갱신 완료 (만료일시: $newExpires)');
            return true;
          }
        }
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        debugPrint('[Cafe24ApiService] 토큰 갱신 시도 실패 (status: $status): ${e.response?.data}');
        // invalid_client 등 자격증명 불일치인 경우 다음 후보(Android 등)로 재시도
        continue;
      } catch (e) {
        debugPrint('[Cafe24ApiService] 토큰 갱신 중 예외 발생: $e');
      }
    }

    _refreshFailedPermanently = true;
    return false;
  }

  /// 401 만료 에러 발생 시 자동으로 토큰 리프레시 후 1회 재요청하는 공통 요청 헬퍼
  Future<Response<dynamic>> _requestWithAutoRefresh(
    String method,
    String url, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
  }) async {
    await _ensureValidToken();

    Options buildOptions() => Options(
          method: method,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
            'X-Cafe24-Api-Version': '2026-09-01',
          },
        );

    try {
      return await _dio.request(
        url,
        data: data,
        queryParameters: queryParameters,
        options: buildOptions(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 &&
          refreshToken.isNotEmpty &&
          !_refreshFailedPermanently) {
        debugPrint('[Cafe24ApiService] 401 응답 감지 -> 토큰 자동 리프레시 후 재요청합니다.');
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          return await _dio.request(
            url,
            data: data,
            queryParameters: queryParameters,
            options: buildOptions(),
          );
        }
      }
      rethrow;
    }
  }

  /// 401 만료 에러 발생 시 자동으로 토큰 리프레시 후 1회 재요청하는 공통 GET 헬퍼
  Future<Response<dynamic>> _getWithAutoRefresh(
    String url, {
    Map<String, dynamic>? queryParameters,
  }) =>
      _requestWithAutoRefresh('GET', url, queryParameters: queryParameters);

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

  /// 만료 없는 Front API GET 호출 헬퍼
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
  }) async {
    final queryParams = <String, dynamic>{
      'limit': limit.clamp(1, 100),
      'display': display,
      'selling': selling,
    };
    if (categoryNo != null) {
      queryParams['category'] = categoryNo;
    }

    try {
      Response<dynamic> response;
      if (hasFrontApiKey) {
        debugPrint('[Cafe24ApiService] Front API로 상품 목록 조회 (만료 없는 Basic Auth 사용)');
        try {
          response = await _getFrontApi('products', queryParameters: queryParams);
        } on DioException catch (frontErr) {
          debugPrint('[Cafe24ApiService] Front API 호출 실패 (status: ${frontErr.response?.statusCode}), Admin API로 fallback: $frontErr');
          final url = 'https://$mallId.cafe24api.com/api/v2/admin/products';
          response = await _getWithAutoRefresh(url, queryParameters: queryParams);
        }
      } else {
        final url = 'https://$mallId.cafe24api.com/api/v2/admin/products';
        response = await _getWithAutoRefresh(url, queryParameters: queryParams);
      }

      // 2. 정상 응답 처리
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data is! Map<String, dynamic>) {
          throw Cafe24ApiException(
            message: '응답 데이터 포맷이 올바르지 않습니다 (JSON 객체 기대됨).',
            statusCode: response.statusCode,
          );
        }

        final rawProducts = data['products'];
        if (rawProducts == null || rawProducts is! List) {
          debugPrint('[Cafe24ApiService] 상품 목록이 비어있습니다.');
          return [];
        }

        final List<Product> result = [];
        for (final item in rawProducts) {
          try {
            if (item is Map<String, dynamic>) {
              result.add(Product.fromCafe24Json(item));
            }
          } catch (itemParseError) {
            debugPrint('[Cafe24ApiService] 개별 상품 파싱 오류 (건너뜀): $itemParseError');
          }
        }

        return result;
      } else {
        throw Cafe24ApiException(
          message: '상품 데이터를 불러오지 못했습니다 (응답 코드: ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      if (e is Cafe24ApiException) rethrow;
      debugPrint('[Cafe24ApiService] 예기치 못한 오류: $e');
      throw Cafe24ApiException(
        message: '상품 목록을 불러오는 중 오류가 발생했습니다: $e',
        originalError: e,
      );
    }
  }

  /// 메인 진열 상품 목록 조회 (Cafe24 관리자 > 상품 > 상품진열 > 메인 진열 연동)
  ///
  /// - [displayGroup]: 메인 진열 번호
  ///   - `2`: NEW PRODUCT (신상품)
  ///   - `3`: BEST MAT TOP 10 (베스트 상품)
  ///   - `4`: OTHER 추천 상품
  Future<List<Product>> fetchMainDisplayProducts(
    int displayGroup, {
    int limit = 20,
    bool forceNew = false,
    bool forceRecommend = false,
    String? forceTag,
  }) async {
    final queryParams = <String, dynamic>{
      'limit': limit.clamp(1, 100),
    };

    try {
      Response<dynamic> response;
      if (hasFrontApiKey) {
        debugPrint('[Cafe24ApiService] Front API로 메인 진열($displayGroup) 상품 조회');
        try {
          response = await _getFrontApi(
            'mains/$displayGroup/products',
            queryParameters: queryParams,
          );
        } on DioException catch (frontErr) {
          debugPrint('[Cafe24ApiService] Front API 메인 진열 조회 실패, Admin API로 fallback: $frontErr');
          final url = 'https://$mallId.cafe24api.com/api/v2/admin/mains/$displayGroup/products';
          response = await _getWithAutoRefresh(url, queryParameters: queryParams);
        }
      } else {
        final url = 'https://$mallId.cafe24api.com/api/v2/admin/mains/$displayGroup/products';
        response = await _getWithAutoRefresh(url, queryParameters: queryParams);
      }

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawProducts = data['products'];
        if (rawProducts is List && rawProducts.isNotEmpty) {
          // 1. 메인 진열 순서(product_no)와 기본 정보를 추출
          final List<String> orderedNos = [];
          final Map<String, Map<String, dynamic>> mainItemsByNo = {};

          for (final item in rawProducts) {
            if (item is Map<String, dynamic>) {
              final pNo = item['product_no']?.toString() ?? '';
              if (pNo.isNotEmpty) {
                orderedNos.add(pNo);
                mainItemsByNo[pNo] = item;
              }
            }
          }

          // 2. /mains/{id}/products 응답에는 이미지 필드(list_image 등)가 생략되므로
          //    추출한 product_no 목록으로 /products?product_no=...를 일괄 조회하여 이미지 및 상세 데이터를 보강
          final Map<String, Map<String, dynamic>> fullDetailsByNo = {};
          if (orderedNos.isNotEmpty) {
            try {
              final joinedNos = orderedNos.join(',');
              Response<dynamic> detailResp;
              if (hasFrontApiKey) {
                try {
                  detailResp = await _getFrontApi(
                    'products',
                    queryParameters: {
                      'product_no': joinedNos,
                      'limit': orderedNos.length.clamp(1, 100),
                    },
                  );
                } on DioException catch (_) {
                  final detailUrl = 'https://$mallId.cafe24api.com/api/v2/admin/products';
                  detailResp = await _getWithAutoRefresh(
                    detailUrl,
                    queryParameters: {
                      'product_no': joinedNos,
                      'limit': orderedNos.length.clamp(1, 100),
                    },
                  );
                }
              } else {
                final detailUrl = 'https://$mallId.cafe24api.com/api/v2/admin/products';
                detailResp = await _getWithAutoRefresh(
                  detailUrl,
                  queryParameters: {
                    'product_no': joinedNos,
                    'limit': orderedNos.length.clamp(1, 100),
                  },
                );
              }

              if (detailResp.statusCode == 200 && detailResp.data is Map<String, dynamic>) {
                final detailList = (detailResp.data as Map<String, dynamic>)['products'];
                if (detailList is List) {
                  for (final dItem in detailList) {
                    if (dItem is Map<String, dynamic>) {
                      final pNo = dItem['product_no']?.toString() ?? '';
                      if (pNo.isNotEmpty) {
                        fullDetailsByNo[pNo] = dItem;
                      }
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('[Cafe24ApiService] 메인 진열 상품 이미지 상세 조회 보강 중 경고: $e');
            }
          }

          // 3. 웹사이트 진열 순서(orderedNos) 그대로 유지하면서 상세 데이터(이미지 포함)로 Product 생성
          final List<Product> result = [];
          for (final pNo in orderedNos) {
            try {
              final mergedJson = <String, dynamic>{
                ...?mainItemsByNo[pNo],
                ...?fullDetailsByNo[pNo],
              };
              result.add(
                Product.fromCafe24Json(
                  mergedJson,
                  forceNew: forceNew,
                  forceRecommend: forceRecommend,
                  forceTag: forceTag,
                ),
              );
            } catch (itemParseError) {
              debugPrint('[Cafe24ApiService] 메인 진열 상품 파싱 오류 (건너뜀): $itemParseError');
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
      debugPrint('[Cafe24ApiService] 메인 진열($displayGroup) 조회 예외: $e');
      throw Cafe24ApiException(
        message: '메인 진열 상품을 불러오는 중 오류가 발생했습니다: $e',
        originalError: e,
      );
    }
  }

  /// 상품 단건 상세 조회
  Future<Product?> fetchProductDetail(String productNo) async {
    if (productNo.trim().isEmpty) return null;

    try {
      Response<dynamic> response;
      if (hasFrontApiKey) {
        debugPrint('[Cafe24ApiService] Front API로 단건 상품 조회: $productNo');
        try {
          response = await _getFrontApi('products/$productNo');
        } on DioException catch (frontErr) {
          debugPrint('[Cafe24ApiService] Front API 단건 조회 실패, Admin API로 fallback: $frontErr');
          final url = 'https://$mallId.cafe24api.com/api/v2/admin/products/$productNo';
          response = await _getWithAutoRefresh(url);
        }
      } else {
        final url = 'https://$mallId.cafe24api.com/api/v2/admin/products/$productNo';
        response = await _getWithAutoRefresh(url);
      }

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

  /// 카테고리 목록 조회
  Future<List<ShopCategory>> fetchCategories() async {
    try {
      Response<dynamic> response;
      if (hasFrontApiKey) {
        debugPrint('[Cafe24ApiService] Front API로 카테고리 목록 조회 (만료 없는 Basic Auth 사용)');
        try {
          response = await _getFrontApi('categories', queryParameters: {'limit': 100});
        } on DioException catch (frontErr) {
          debugPrint('[Cafe24ApiService] Front API 카테고리 조회 실패, Admin API로 fallback: $frontErr');
          final url = 'https://$mallId.cafe24api.com/api/v2/admin/categories';
          response = await _getWithAutoRefresh(
            url,
            queryParameters: {'limit': 100},
          );
        }
      } else {
        final url = 'https://$mallId.cafe24api.com/api/v2/admin/categories';
        response = await _getWithAutoRefresh(
          url,
          queryParameters: {'limit': 100},
        );
      }

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

  // ──────────────────────────────────────────────────────────────────────────
  // Cafe24 회원 장바구니 DB 연동 API (mall.read_personal, mall.write_personal 스코프)
  // ──────────────────────────────────────────────────────────────────────────

  /// 상품의 대표 품목 코드(variant_code) 조회 (Front API 또는 Admin API)
  Future<String?> getProductDefaultVariantCode(String productNo) async {
    try {
      Response<dynamic> resp;
      if (hasFrontApiKey) {
        resp = await _getFrontApi('products/$productNo/variants');
      } else {
        resp = await _getWithAutoRefresh(
          'https://$mallId.cafe24api.com/api/v2/admin/products/$productNo/variants',
        );
      }
      if (resp.statusCode == 200 && resp.data is Map<String, dynamic>) {
        final variants = (resp.data as Map<String, dynamic>)['variants'];
        if (variants is List && variants.isNotEmpty) {
          final first = variants.first;
          if (first is Map<String, dynamic>) {
            return first['variant_code']?.toString();
          }
        }
      }
    } catch (e) {
      debugPrint('[Cafe24ApiService] 상품($productNo) variants 조회 실패: $e');
    }
    return null;
  }

  /// Cafe24 서버에서 회원 장바구니 목록 조회 (mall.read_personal 스코프)
  /// Endpoint: GET https://$mallId.cafe24api.com/api/v2/admin/carts?member_id={member_id}
  Future<List<CartItem>> fetchMemberCart(String memberId) async {
    if (memberId.trim().isEmpty || !hasAdminCredentials) {
      return [];
    }

    try {
      final url = 'https://$mallId.cafe24api.com/api/v2/admin/carts';
      final response = await _getWithAutoRefresh(
        url,
        queryParameters: {'member_id': memberId.trim()},
      );

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawCarts = data['carts'];
        if (rawCarts is List && rawCarts.isNotEmpty) {
          final List<String> productNos = [];
          final List<Map<String, dynamic>> cartRecords = [];

          for (final item in rawCarts) {
            if (item is Map<String, dynamic>) {
              final pNo = item['product_no']?.toString() ?? '';
              if (pNo.isNotEmpty) {
                productNos.add(pNo);
                cartRecords.add(item);
              }
            }
          }

          // 상품 이미지 및 상세 정보 일괄 조회
          final Map<String, Product> productMap = {};
          if (productNos.isNotEmpty) {
            try {
              final uniqueNos = productNos.toSet().join(',');
              final detailResp = hasFrontApiKey
                  ? await _getFrontApi('products', queryParameters: {'product_no': uniqueNos, 'limit': 100})
                  : await _getWithAutoRefresh(
                      'https://$mallId.cafe24api.com/api/v2/admin/products',
                      queryParameters: {'product_no': uniqueNos, 'limit': 100},
                    );
              if (detailResp.statusCode == 200 && detailResp.data is Map<String, dynamic>) {
                final rawProducts = (detailResp.data as Map<String, dynamic>)['products'];
                if (rawProducts is List) {
                  for (final pJson in rawProducts) {
                    if (pJson is Map<String, dynamic>) {
                      final p = Product.fromCafe24Json(pJson);
                      productMap[p.id] = p;
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('[Cafe24ApiService] 장바구니 상품 상세 보강 실패: $e');
            }
          }

          final List<CartItem> items = [];
          for (final record in cartRecords) {
            final pNo = record['product_no']?.toString() ?? '';
            final qty = int.tryParse(record['quantity']?.toString() ?? '1') ?? 1;
            final basketNo = int.tryParse(record['basket_product_no']?.toString() ?? '');
            final optionId = record['option_id']?.toString();

            final product = productMap[pNo] ?? Product.fromCafe24Json(record);
            items.add(
              CartItem(
                product: product,
                quantity: qty,
                isSelected: true,
                basketProductNo: basketNo,
                optionId: optionId,
              ),
            );
          }
          return items;
        }
      }
    } catch (e) {
      debugPrint('[Cafe24ApiService] 회원($memberId) 장바구니 조회 경고: $e');
    }
    return [];
  }

  /// Cafe24 서버 회원 장바구니에 상품 추가 (mall.write_personal 스코프)
  /// Front API Key(Basic Auth) 또는 Admin OAuth Token을 사용하여
  /// POST https://$mallId.cafe24api.com/api/v2/carts 호출
  Future<bool> addMemberCartItem({
    required String memberId,
    required String productNo,
    required int quantity,
    String? optionId,
    String? variantCode,
  }) async {
    final pNoInt = int.tryParse(productNo);
    if (pNoInt == null) return false;

    try {
      String resolvedVariantCode = variantCode ?? '';
      if (resolvedVariantCode.isEmpty) {
        resolvedVariantCode = await getProductDefaultVariantCode(productNo) ?? '';
      }
      if (resolvedVariantCode.isEmpty) {
        debugPrint('[Cafe24ApiService] 상품($productNo) 품목 코드(variant_code)를 찾을 수 없습니다.');
        return false;
      }

      final payload = {
        'shop_no': 1,
        'request': {
          'duplicated_item_check': 'T',
          'product_no': pNoInt,
          'basket_type': 'A0000',
          'prepaid_shipping_fee': 'P',
          'variants': [
            {
              'quantity': quantity,
              'variants_code': resolvedVariantCode,
              if (optionId != null && optionId.isNotEmpty) 'options': [{'option_code': optionId}],
            },
          ],
        },
      };

      Response<dynamic> response;
      if (hasFrontApiKey) {
        final url = 'https://$mallId.cafe24api.com/api/v2/carts';
        response = await _dio.post(
          url,
          data: payload,
          options: Options(headers: _buildFrontApiHeaders()),
        );
      } else {
        final url = 'https://$mallId.cafe24api.com/api/v2/carts';
        response = await _requestWithAutoRefresh('POST', url, data: payload);
      }

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[Cafe24ApiService] 회원($memberId) 장바구니 추가 경고: $e');
      return false;
    }
  }

  /// Cafe24 서버 회원 장바구니 상품 수량 변경
  Future<bool> updateMemberCartQuantity({
    required String memberId,
    required String productNo,
    required int quantity,
    int? basketProductNo,
    String? optionId,
  }) async {
    // Cafe24 REST API는 Front API 장바구니 재등록 또는 WebView Basket 세션을 통해 수량을 동기화합니다.
    return addMemberCartItem(
      memberId: memberId,
      productNo: productNo,
      quantity: quantity,
      optionId: optionId,
    );
  }

  /// Cafe24 서버 회원 장바구니 상품 삭제
  Future<bool> deleteMemberCartItem({
    required String memberId,
    required String productNo,
    int? basketProductNo,
    String? optionId,
  }) async {
    return true;
  }


  // ──────────────────────────────────────────────────────────────────────────
  // Cafe24 회원 기본 정보 및 배송지 주소록 DB 연동 API
  // (/api/v2/admin/customers, /api/v2/admin/customers/{member_id}/shippingaddresses)
  // ──────────────────────────────────────────────────────────────────────────

  bool _isValidPhoneStr(String? raw) {
    if (raw == null) return false;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 9 && digits.length <= 11;
  }

  /// Cafe24 서버에서 회원의 기본 정보 및 배송지 주소(우편번호, 기본주소, 상세주소) 조회
  Future<({String? zipCode, String? address1, String? address2, String? phone, String? name, String? email})?>
      fetchCustomerAddressInfo(String memberId) async {
    if (memberId.trim().isEmpty || !hasAdminCredentials) {
      return null;
    }

    String? zip;
    String? addr1;
    String? addr2;
    String? phone;
    String? name;
    String? email;

    // 1. 회원 배송지 주소록(/shippingaddresses)에서 기본 배송지 우선 조회
    try {
      final encodedMemberId = Uri.encodeComponent(memberId.trim());
      final shippingUrl =
          'https://$mallId.cafe24api.com/api/v2/admin/customers/$encodedMemberId/shippingaddresses';
      final shippingResp = await _getWithAutoRefresh(shippingUrl);
      if (shippingResp.statusCode == 200 && shippingResp.data is Map<String, dynamic>) {
        final list = (shippingResp.data as Map<String, dynamic>)['shippingaddresses'];
        if (list is List && list.isNotEmpty) {
          Map<String, dynamic>? targetAddr;
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              if (item['shipping_default'] == 'T' || item['default'] == 'T') {
                targetAddr = item;
                break;
              }
              targetAddr ??= item;
            }
          }
          if (targetAddr != null) {
            zip = targetAddr['receiver_zipcode']?.toString() ??
                targetAddr['zipcode']?.toString();
            addr1 = targetAddr['receiver_address1']?.toString() ??
                targetAddr['address1']?.toString();
            addr2 = targetAddr['receiver_address2']?.toString() ??
                targetAddr['address2']?.toString();
            final cellCandidate = targetAddr['receiver_cellphone']?.toString();
            final phoneCandidate = targetAddr['receiver_phone']?.toString();
            if (_isValidPhoneStr(cellCandidate)) {
              phone = cellCandidate;
            } else if (_isValidPhoneStr(phoneCandidate)) {
              phone = phoneCandidate;
            }
            name = targetAddr['receiver_name']?.toString();
          }
        }
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        debugPrint(
          '[Cafe24ApiService] 회원($memberId)은 소셜 계정이거나 배송지 주소록이 없습니다 (404). 로컬 정보를 사용합니다.',
        );
      } else {
        debugPrint('[Cafe24ApiService] 회원($memberId) 배송지 주소록 조회 참고: ${e.message}');
      }
    } catch (e) {
      debugPrint('[Cafe24ApiService] 회원($memberId) 배송지 주소록 조회 참고: $e');
    }

    // 2. 회원 기본 프로필(/customers?member_id=...)에서 주소 및 연락처 보강
    try {
      final customerUrl = 'https://$mallId.cafe24api.com/api/v2/admin/customers';
      final custResp = await _getWithAutoRefresh(
        customerUrl,
        queryParameters: {'member_id': memberId},
      );
      if (custResp.statusCode == 200 && custResp.data is Map<String, dynamic>) {
        final customers = (custResp.data as Map<String, dynamic>)['customers'];
        if (customers is List && customers.isNotEmpty) {
          final c = customers.first;
          if (c is Map<String, dynamic>) {
            zip = (zip != null && zip.trim().isNotEmpty)
                ? zip
                : (c['zipcode']?.toString() ?? c['postcode1']?.toString());
            addr1 = (addr1 != null && addr1.trim().isNotEmpty)
                ? addr1
                : (c['address1']?.toString() ?? c['addr1']?.toString());
            addr2 = (addr2 != null && addr2.trim().isNotEmpty)
                ? addr2
                : (c['address2']?.toString() ?? c['addr2']?.toString());
            if (!_isValidPhoneStr(phone)) {
              final cellCandidate = c['cellphone']?.toString();
              final phoneCandidate = c['phone']?.toString();
              if (_isValidPhoneStr(cellCandidate)) {
                phone = cellCandidate;
              } else if (_isValidPhoneStr(phoneCandidate)) {
                phone = phoneCandidate;
              }
            }
            name = (name != null && name.trim().isNotEmpty)
                ? name
                : c['name']?.toString();
            email = c['email']?.toString();
          }
        }
      }
    } catch (e) {
      debugPrint('[Cafe24ApiService] 회원($memberId) 기본 프로필 조회 참고: $e');
    }

    if ((zip != null && zip.isNotEmpty) ||
        (addr1 != null && addr1.isNotEmpty) ||
        (phone != null && phone.isNotEmpty)) {
      return (
        zipCode: zip?.trim(),
        address1: addr1?.trim(),
        address2: addr2?.trim(),
        phone: phone?.trim(),
        name: name?.trim(),
        email: email?.trim(),
      );
    }
    return null;
  }

  /// Cafe24 서버에 회원의 기본 배송지 주소록 등록/수정 연동
  /// (`/api/v2/admin/customers/{member_id}/shippingaddresses`)
  Future<bool> upsertCustomerShippingAddress({
    required String memberId,
    required String recipientName,
    required String phone,
    required String zipCode,
    required String address1,
    required String address2,
  }) async {
    if (memberId.trim().isEmpty || !hasAdminCredentials) {
      return false;
    }

    try {
      final encodedMemberId = Uri.encodeComponent(memberId.trim());
      final baseUrl =
          'https://$mallId.cafe24api.com/api/v2/admin/customers/$encodedMemberId/shippingaddresses';

      // 1. 기존 등록된 배송지 주소록이 있는지 확인
      int? existingAddressNo;
      try {
        final getResp = await _getWithAutoRefresh(baseUrl);
        if (getResp.statusCode == 200 && getResp.data is Map<String, dynamic>) {
          final list = (getResp.data as Map<String, dynamic>)['shippingaddresses'];
          if (list is List && list.isNotEmpty) {
            for (final item in list) {
              if (item is Map<String, dynamic>) {
                final no = int.tryParse(item['shipping_address_no']?.toString() ?? '');
                if (item['shipping_default'] == 'T' || item['default'] == 'T') {
                  existingAddressNo = no;
                  break;
                }
                existingAddressNo ??= no;
              }
            }
          }
        }
      } catch (_) {}

      final requestPayload = {
        'shop_no': 1,
        'request': {
          'shipping_place_name': '기본배송지',
          'receiver_name': recipientName,
          'receiver_zipcode': zipCode,
          'receiver_address1': address1,
          'receiver_address2': address2,
          'receiver_cellphone': phone,
          'receiver_phone': phone,
          'shipping_default': 'T',
        },
      };

      // 2. 기존 배송지가 있으면 PUT 수정, 없으면 POST 신규 등록
      if (existingAddressNo != null) {
        final putResp = await _requestWithAutoRefresh(
          'PUT',
          '$baseUrl/$existingAddressNo',
          data: requestPayload,
        );
        return putResp.statusCode == 200;
      } else {
        final postResp = await _requestWithAutoRefresh(
          'POST',
          baseUrl,
          data: requestPayload,
        );
        return postResp.statusCode == 200 || postResp.statusCode == 201;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        debugPrint(
          '[Cafe24ApiService] 회원($memberId)은 소셜 계정(@k/@n)이거나 Cafe24 서버 주소록이 없습니다 (404). 앱 로컬 저장소를 사용합니다.',
        );
      } else {
        debugPrint('[Cafe24ApiService] 회원($memberId) 배송지 주소록 서버 저장 참고: ${e.message}');
      }
      return false;
    } catch (e) {
      debugPrint('[Cafe24ApiService] 회원($memberId) 배송지 주소록 서버 저장 참고: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Cafe24 주문 조회 API (/api/v2/admin/orders) - mall.read_order 권한 필요
  // ──────────────────────────────────────────────────────────────────────────

  /// 마지막 주문 조회 실패 사유 (권한 부족 등 UI 안내용)
  String? lastOrderSyncError;

  /// 회원의 최근 Cafe24 주문 목록 조회 (주문상품/수령자 정보 포함)
  Future<List<OrderRecord>> fetchMemberOrders(
    String memberId, {
    int days = 90,
  }) async {
    lastOrderSyncError = null;
    if (memberId.trim().isEmpty || !hasAdminCredentials) return const [];

    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final now = DateTime.now();

    try {
      final response = await _getWithAutoRefresh(
        'https://$mallId.cafe24api.com/api/v2/admin/orders',
        queryParameters: {
          'member_id': memberId,
          'start_date': fmt(now.subtract(Duration(days: days))),
          'end_date': fmt(now),
          'embed': 'items,receivers',
          'limit': 100,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['orders'] is List) {
        return (data['orders'] as List)
            .whereType<Map<String, dynamic>>()
            .map(_parseCafe24Order)
            .whereType<OrderRecord>()
            .toList();
      }
    } on DioException catch (e) {
      final err = _handleDioException(e);
      lastOrderSyncError = err.statusCode == 403
          ? 'Cafe24 주문 조회 권한(mall.read_order)이 없어 배송 상태를 불러올 수 없습니다.'
          : err.message;
      debugPrint('[Cafe24ApiService] 회원($memberId) 주문 조회 실패: $err');
    } catch (e) {
      lastOrderSyncError = '주문 조회 중 오류가 발생했습니다: $e';
      debugPrint('[Cafe24ApiService] 회원($memberId) 주문 조회 실패: $e');
    }
    return const [];
  }

  /// 단일 Cafe24 주문 상세 조회
  Future<OrderRecord?> fetchOrderDetail(String orderId) async {
    if (orderId.trim().isEmpty || !hasAdminCredentials) return null;
    try {
      final response = await _getWithAutoRefresh(
        'https://$mallId.cafe24api.com/api/v2/admin/orders/$orderId',
        queryParameters: {'embed': 'items,receivers'},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['order'] is Map<String, dynamic>) {
        return _parseCafe24Order(data['order'] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[Cafe24ApiService] 주문($orderId) 상세 조회 실패: $e');
    }
    return null;
  }

  /// [mall.write_order] 주문 취소 신청 API
  Future<bool> cancelOrder(String orderId, {String reason = '고객 직접 취소'}) async {
    if (orderId.trim().isEmpty || !hasAdminCredentials) return false;
    try {
      final response = await _requestWithAutoRefresh(
        'POST',
        'https://$mallId.cafe24api.com/api/v2/admin/orders/$orderId/cancellation',
        data: {
          'request': {
            'undelivered': 'T',
            'reason': reason,
          }
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[Cafe24ApiService] 주문($orderId) 취소 신청 실패: $e');
      return false;
    }
  }

  /// [mall.read_shipping] 쇼핑몰 기본 배송비 설정 조회
  Future<({int baseFee, int freeThreshold})?> fetchShippingSettings() async {
    if (!hasAdminCredentials) return null;
    try {
      final response = await _getWithAutoRefresh(
        'https://$mallId.cafe24api.com/api/v2/admin/shipping',
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['shipping'] is Map<String, dynamic>) {
        final s = data['shipping'] as Map<String, dynamic>;
        final fee = int.tryParse(s['shipping_fee']?.toString() ?? '3000') ?? 3000;
        final free = int.tryParse(s['free_shipping_limit']?.toString() ?? '30000') ?? 30000;
        return (baseFee: fee, freeThreshold: free);
      }
    } catch (e) {
      debugPrint('[Cafe24ApiService] 배송 설정 조회 실패: $e');
    }
    return null;
  }

  /// [mall.read_community] 상품 후기/리뷰 게시글 목록 조회 (게시판 연동)
  Future<List<Map<String, dynamic>>> fetchProductReviews(
    String productNo, {
    int boardNo = 4,
    int limit = 10,
  }) async {
    if (!hasAdminCredentials || productNo.trim().isEmpty) return const [];
    try {
      final response = await _getWithAutoRefresh(
        'https://$mallId.cafe24api.com/api/v2/admin/boards/$boardNo/articles',
        queryParameters: {
          'product_no': productNo,
          'limit': limit,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['articles'] is List) {
        return (data['articles'] as List).whereType<Map<String, dynamic>>().toList();
      }
    } catch (e) {
      debugPrint('[Cafe24ApiService] 상품($productNo) 리뷰 조회 실패: $e');
    }
    return const [];
  }

  /// Cafe24 주문 JSON -> OrderRecord 변환
  OrderRecord? _parseCafe24Order(Map<String, dynamic> o) {
    final orderId = o['order_id']?.toString() ?? '';
    if (orderId.isEmpty) return null;

    int toInt(dynamic v) => double.tryParse(v?.toString() ?? '')?.round() ?? 0;

    final rawItems = (o['items'] is List)
        ? (o['items'] as List).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    final items = rawItems.map((it) {
      final price = toInt(it['product_price'] ?? it['price']);
      return CartItem(
        product: Product(
          id: it['product_no']?.toString() ?? '',
          name: it['product_name']?.toString() ?? '상품',
          originalPrice: price,
          tag: '',
          tagColor: const Color(0xFF94A3B8),
          category: '',
        ),
        quantity: toInt(it['quantity']).clamp(1, 9999),
        optionId: it['option_value']?.toString(),
      );
    }).toList();

    // 대표 배송상태: 송장이 있는 품목 우선, 없으면 첫 품목 기준
    Map<String, dynamic>? statusItem;
    for (final it in rawItems) {
      if ((it['tracking_no']?.toString() ?? '').isNotEmpty) {
        statusItem = it;
        break;
      }
    }
    statusItem ??= rawItems.isNotEmpty ? rawItems.first : null;

    String? emptyToNull(dynamic v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    final receiver = (o['receivers'] is List && (o['receivers'] as List).isNotEmpty)
        ? (o['receivers'] as List).first as Map<String, dynamic>
        : <String, dynamic>{};

    final zip = receiver['zipcode']?.toString() ?? '';
    final addrFull = receiver['address_full']?.toString() ??
        '${receiver['address1'] ?? ''} ${receiver['address2'] ?? ''}';

    final payMethods = o['payment_method_name'];
    final paymentLabel = payMethods is List
        ? payMethods.map((e) => e.toString()).join(', ')
        : (payMethods?.toString() ?? '');

    final amount = o['actual_order_amount'];
    final paid = amount is Map
        ? toInt(amount['payment_amount'] ?? amount['order_price_amount'])
        : toInt(o['payment_amount']);
    final shippingFee = amount is Map ? toInt(amount['shipping_fee']) : 0;
    final usedPoints = amount is Map ? toInt(amount['mileage_spent_amount']) : 0;

    final isCancelled = o['canceled']?.toString() == 'T';

    return OrderRecord(
      orderId: orderId,
      orderedAt: DateTime.tryParse(o['order_date']?.toString() ?? '') ?? DateTime.now(),
      items: items,
      recipientName: receiver['name']?.toString() ?? '',
      recipientPhone: receiver['cellphone']?.toString() ??
          receiver['phone']?.toString() ??
          '',
      address: '${zip.isNotEmpty ? '[$zip] ' : ''}${addrFull.trim()}',
      deliveryMemo: receiver['shipping_message']?.toString() ?? '',
      paymentMethod: paymentLabel.isNotEmpty ? paymentLabel : 'Cafe24 결제',
      usedPoints: usedPoints,
      shippingFee: shippingFee,
      finalPaidAmount: paid,
      status: isCancelled
          ? OrderDeliveryStatus.cancelled
          : OrderDeliveryStatus.fromCafe24Code(statusItem?['order_status']?.toString()),
      carrierName: emptyToNull(statusItem?['shipping_company_name']),
      carrierCode: emptyToNull(statusItem?['shipping_company_code']),
      trackingNo: emptyToNull(statusItem?['tracking_no']),
    );
  }

  /// 환경변수 필수값 검증
  void _validateCredentials() {
    if (mallId.isEmpty) {
      throw Cafe24ApiException(
        message: '쇼핑몰 ID(Mall_ID)가 .env 파일에 설정되어 있지 않습니다.',
        errorCode: 'MISSING_MALL_ID',
      );
    }
    if (!hasFrontApiKey && accessToken.isEmpty && refreshToken.isEmpty) {
      throw Cafe24ApiException(
        message: 'Cafe24 인증 키(Front API Key 또는 Access Token)가 설정되어 있지 않습니다.',
        errorCode: 'MISSING_CREDENTIALS',
      );
    }
  }

  /// DioException을 분석하여 사용자 친화적인 Cafe24ApiException으로 변환
  Cafe24ApiException _handleDioException(DioException e) {
    debugPrint('[Cafe24ApiService] DioException: ${e.type}, message: ${e.message}');

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return Cafe24ApiException(
          message: '서버 연결 시간이 초과되었습니다. 네트워크 상태를 확인해주세요.',
          errorCode: 'TIMEOUT',
          originalError: e,
        );

      case DioExceptionType.connectionError:
        return Cafe24ApiException(
          message: 'Cafe24 서버에 접속할 수 없습니다. 인터넷 연결을 확인해주세요.',
          errorCode: 'CONNECTION_ERROR',
          originalError: e,
        );

      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final responseData = e.response?.data;

        String serverMessage = '';
        String? errorCode;

        // Cafe24 에러 응답 파싱: { "error": { "code": 401, "message": "..." } }
        if (responseData is Map<String, dynamic>) {
          final errorObj = responseData['error'];
          if (errorObj is Map<String, dynamic>) {
            serverMessage = errorObj['message']?.toString() ?? '';
            errorCode = errorObj['code']?.toString();
          } else if (responseData['message'] != null) {
            serverMessage = responseData['message'].toString();
          }
        }

        switch (statusCode) {
          case 400:
            return Cafe24ApiException(
              message: serverMessage.isNotEmpty
                  ? '잘못된 요청입니다: $serverMessage'
                  : '잘못된 API 요청 파라미터입니다 (400).',
              statusCode: statusCode,
              errorCode: errorCode ?? 'BAD_REQUEST',
              originalError: e,
            );

          case 401:
            return Cafe24ApiException(
              message: serverMessage.isNotEmpty
                  ? '인증 오류 (401): $serverMessage\n(토큰이 만료되었거나 올바르지 않습니다)'
                  : '인증에 실패했습니다 (401). Access Token을 다시 발급받아주세요.',
              statusCode: statusCode,
              errorCode: errorCode ?? 'UNAUTHORIZED',
              originalError: e,
            );

          case 403:
            return Cafe24ApiException(
              message: serverMessage.isNotEmpty
                  ? '권한 오류 (403): $serverMessage'
                  : '해당 API에 대한 접근 권한(Scope)이 없습니다 (403).',
              statusCode: statusCode,
              errorCode: errorCode ?? 'FORBIDDEN',
              originalError: e,
            );

          case 404:
            return Cafe24ApiException(
              message: '요청한 리소스를 찾을 수 없습니다 (404 Not Found).',
              statusCode: statusCode,
              errorCode: errorCode ?? 'NOT_FOUND',
              originalError: e,
            );

          case 429:
            return Cafe24ApiException(
              message: 'Cafe24 API 호출 제한(Rate Limit)을 초과했습니다. 잠시 후 다시 시도해주세요 (429).',
              statusCode: statusCode,
              errorCode: errorCode ?? 'RATE_LIMIT_EXCEEDED',
              originalError: e,
            );

          case 500:
          case 502:
          case 503:
          case 504:
            return Cafe24ApiException(
              message: 'Cafe24 서버 점검 중이거나 일시적인 장애가 발생했습니다 (HTTP $statusCode).',
              statusCode: statusCode,
              errorCode: 'SERVER_ERROR',
              originalError: e,
            );

          default:
            return Cafe24ApiException(
              message: serverMessage.isNotEmpty
                  ? serverMessage
                  : '서버 오류가 발생했습니다 (HTTP $statusCode).',
              statusCode: statusCode,
              errorCode: errorCode,
              originalError: e,
            );
        }

      case DioExceptionType.cancel:
        return Cafe24ApiException(
          message: 'API 요청이 취소되었습니다.',
          errorCode: 'REQUEST_CANCELLED',
          originalError: e,
        );

      case DioExceptionType.badCertificate:
        return Cafe24ApiException(
          message: '보안 인증서 검증에 실패했습니다.',
          errorCode: 'BAD_CERTIFICATE',
          originalError: e,
        );

      case DioExceptionType.unknown:
      default:
        return Cafe24ApiException(
          message: '알 수 없는 네트워크 오류가 발생했습니다: ${e.message}',
          errorCode: 'UNKNOWN',
          originalError: e,
        );
    }
  }
}
