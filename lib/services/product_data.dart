import 'package:flutter/material.dart';
import 'package:shopmall/models/product.dart';

/// 앱 내 상품 더미 데이터 저장소
///
/// 실제 서비스에서는 API 클라이언트로 교체됩니다.
class ProductDataService {
  ProductDataService._();

  // ─── 전체 상품 목록 ───
  static final List<Product> all = [
    // ── 신상품 ──
    Product(
      id: 'p001',
      name: '친환경 롤매트 2m',
      originalPrice: 43000,
      discountRate: 19,
      tag: 'NEW',
      tagColor: const Color(0xFF4CAF50),
      category: '롤매트',
      icon: Icons.view_column,
      rating: 4.6,
      reviewCount: 128,
      description:
          '친환경 소재로 제작된 롤매트입니다. 두께 10mm의 고밀도 폼으로 충격 흡수력이 뛰어나며, '
          '항균 처리가 되어 위생적입니다. 길이 2m로 다양한 공간에 활용 가능합니다.\n\n'
          '• 소재: EVA 친환경 폼\n'
          '• 크기: 200 x 100 cm (두께 10mm)\n'
          '• 특징: 항균·방수 처리, 미끄럼 방지 하단\n'
          '• 색상: 아이보리, 그레이, 민트 (택1)',
    ),
    Product(
      id: 'p002',
      name: '디자인 현관 매트',
      originalPrice: 21900,
      discountRate: 0,
      tag: 'NEW',
      tagColor: const Color(0xFF4CAF50),
      category: '현관발매트',
      icon: Icons.door_front_door,
      rating: 4.3,
      reviewCount: 74,
      description:
          '모던한 디자인의 현관 매트입니다. 흡수력이 뛰어난 극세사 소재를 사용하여 '
          '신발 바닥의 수분과 먼지를 효과적으로 제거합니다.\n\n'
          '• 소재: 극세사 + 미끄럼방지 고무 하단\n'
          '• 크기: 45 x 75 cm\n'
          '• 특징: 세탁기 세탁 가능\n'
          '• 디자인: 체크, 스트라이프, 단색 (택1)',
    ),
    Product(
      id: 'p003',
      name: '인조잔디 롤 50cm',
      originalPrice: 18500,
      discountRate: 0,
      tag: 'NEW',
      tagColor: const Color(0xFF4CAF50),
      category: '인조잔디',
      icon: Icons.grass,
      rating: 4.7,
      reviewCount: 201,
      description:
          '사실적인 잔디 느낌의 인조잔디 롤입니다. 베란다, 옥상, 실내 인테리어 등 다양한 장소에 활용하세요.\n\n'
          '• 소재: PP 인조잔디\n'
          '• 크기: 50cm 단위 판매 (폭 1m)\n'
          '• 파일 높이: 25mm\n'
          '• 특징: UV 코팅, 배수홀 처리',
    ),
    Product(
      id: 'p004',
      name: '대걸레 청소세트',
      originalPrice: 12000,
      discountRate: 0,
      tag: 'NEW',
      tagColor: const Color(0xFF4CAF50),
      category: '청소용품',
      icon: Icons.cleaning_services,
      rating: 4.2,
      reviewCount: 53,
      description:
          '회전 대걸레와 양동이가 포함된 올인원 청소 세트입니다.\n\n'
          '• 구성: 대걸레 손잡이(120cm) + 헤드 + 양동이 + 교체용 패드 2개\n'
          '• 특징: 360° 회전 헤드, 탈수 페달 방식\n'
          '• 패드 소재: 극세사',
    ),

    // ── 베스트 상품 ──
    Product(
      id: 'p005',
      name: '프리미엄 롤매트',
      originalPrice: 58000,
      discountRate: 22,
      tag: 'BEST',
      tagColor: const Color(0xFFE53935),
      category: '롤매트',
      icon: Icons.view_column,
      rating: 4.9,
      reviewCount: 512,
      description:
          '두께 15mm 고급 폼의 프리미엄 롤매트입니다. 장기간 사용에도 복원력이 뛰어납니다.\n\n'
          '• 소재: 고밀도 EVA 폼\n'
          '• 크기: 200 x 130 cm (두께 15mm)\n'
          '• 특징: 피부 자극 없는 무독성 인증, 냄새 없음\n'
          '• 색상: 아이보리, 그레이, 라이트 핑크',
    ),
    Product(
      id: 'p006',
      name: '현관 항균 매트',
      originalPrice: 19800,
      discountRate: 0,
      tag: 'BEST',
      tagColor: const Color(0xFFE53935),
      category: '현관발매트',
      icon: Icons.door_front_door,
      rating: 4.5,
      reviewCount: 389,
      description:
          '항균 처리된 현관 매트로 세균 번식을 99.9% 억제합니다.\n\n'
          '• 소재: 항균 마이크로파이버\n'
          '• 크기: 40 x 60 cm\n'
          '• 특징: 항균 인증, 미끄럼 방지\n'
          '• 색상: 다크그레이, 베이지, 네이비',
    ),
    Product(
      id: 'p007',
      name: '인조잔디 타일',
      originalPrice: 8900,
      discountRate: 0,
      tag: 'BEST',
      tagColor: const Color(0xFFE53935),
      category: '인조잔디',
      icon: Icons.grass,
      rating: 4.4,
      reviewCount: 176,
      description:
          '30x30cm 타일 형태로 쉽게 깔고 분리할 수 있는 인조잔디 타일입니다.\n\n'
          '• 소재: PP 인조잔디\n'
          '• 크기: 30 x 30 cm / 장\n'
          '• 파일 높이: 20mm\n'
          '• 특징: 퍼즐 결합 방식, 이동 편리',
    ),
    Product(
      id: 'p008',
      name: '극세사 이불세트',
      originalPrice: 67000,
      discountRate: 18,
      tag: 'BEST',
      tagColor: const Color(0xFFE53935),
      category: '침구',
      icon: Icons.king_bed,
      rating: 4.8,
      reviewCount: 293,
      description:
          '부드러운 극세사 소재의 이불 세트입니다. 가볍고 따뜻하여 사계절 사용 가능합니다.\n\n'
          '• 구성: 이불 + 베개커버 2개\n'
          '• 소재: 극세사 (충전재: 마이크로 화이버)\n'
          '• 크기: 150 x 200 cm (싱글)\n'
          '• 세탁: 세탁기 가능',
    ),
  ];

  /// ID로 단일 상품 조회 (없으면 null)
  static Product? findById(String id) {
    try {
      return all.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 신상품 목록
  static List<Product> get newProducts =>
      all.where((p) => p.tag == 'NEW').toList();

  /// 베스트 상품 목록
  static List<Product> get bestProducts =>
      all.where((p) => p.tag == 'BEST').toList();
}

