import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shopmall/models/category.dart';
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

  /// 유효한 인증 자격증명(Front API 키 또는 OAuth 토큰)이 있는지 여부
  bool get hasCredentials =>
      mallId.isNotEmpty &&
      (hasFrontApiKey || accessToken.isNotEmpty || refreshToken.isNotEmpty);

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

    if (_isTokenExpired && refreshToken.isNotEmpty) {
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

    return false;
  }

  /// 401 만료 에러 발생 시 자동으로 토큰 리프레시 후 1회 재요청하는 공통 GET 헬퍼
  Future<Response<dynamic>> _getWithAutoRefresh(
    String url, {
    Map<String, dynamic>? queryParameters,
  }) async {
    await _ensureValidToken();

    try {
      return await _dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
            'X-Cafe24-Api-Version': '2026-09-01',
          },
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && refreshToken.isNotEmpty) {
        debugPrint('[Cafe24ApiService] 401 응답 감지 -> 토큰 자동 리프레시 후 재요청합니다.');
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          return await _dio.get(
            url,
            queryParameters: queryParameters,
            options: Options(
              headers: {
                'Authorization': 'Bearer $accessToken',
                'Content-Type': 'application/json',
                'X-Cafe24-Api-Version': '2026-09-01',
              },
            ),
          );
        }
      }
      rethrow;
    }
  }

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
