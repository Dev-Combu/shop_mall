class User {
  final String id;            // Cafe24 member_id (예: 'suzicnl_user1')
  final String email;         // 이메일
  final String name;          // 회원 이름
  final String? phone;        // 휴대폰 번호 (cellphone)
  final String? zipCode;      // 우편번호 (postcode1)
  final String? address1;     // 기본 주소 (addr1)
  final String? address2;     // 상세 주소 (addr2)
  final String? profileImageUrl;
  final String groupName;     // 회원 등급 (예: '일반회원', 'VIP 회원')
  final int points;           // 가용 적립금/포인트
  final int coupons;          // 보유 쿠폰 수
  final int orders;           // 진행/누적 주문 수
  final bool isCafe24Member;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.phone,
    this.zipCode,
    this.address1,
    this.address2,
    this.profileImageUrl,
    this.groupName = '일반회원',
    this.points = 0,
    this.coupons = 0,
    this.orders = 0,
    this.isCafe24Member = true,
  });

  /// 전체 주소 문자열 반환 (예: '[12285] 경기도 남양주시 ...')
  String get fullAddress {
    final parts = <String>[];
    if (zipCode != null && zipCode!.trim().isNotEmpty) {
      parts.add('[${zipCode!.trim()}]');
    }
    if (address1 != null && address1!.trim().isNotEmpty) {
      parts.add(address1!.trim());
    }
    if (address2 != null && address2!.trim().isNotEmpty) {
      parts.add(address2!.trim());
    }
    return parts.join(' ');
  }

  /// Cafe24 고객 데이터 JSON -> User 변환
  factory User.fromCafe24Customer(
    Map<String, dynamic> json, {
    int? points,
    int? coupons,
    int? orders,
  }) {
    final memberId = json['member_id']?.toString() ??
        json['id']?.toString() ??
        'cafe24_member';

    final rawName = json['name']?.toString() ??
        json['english_name']?.toString() ??
        json['nick_name']?.toString() ??
        '';
    final displayName = rawName.trim().isNotEmpty ? rawName.trim() : memberId;

    final rawEmail = json['email']?.toString() ?? '';
    final displayEmail =
        rawEmail.trim().isNotEmpty ? rawEmail.trim() : '$memberId@suzicnl.com';

    // Cafe24 적립금 파싱 (available_point 또는 total_point 등)
    int parsedPoints = points ?? 0;
    if (points == null) {
      final pointStr = json['available_point']?.toString() ??
          json['total_point']?.toString() ??
          json['points']?.toString() ??
          '0';
      parsedPoints = (double.tryParse(pointStr) ?? 0).round();
    }

    return User(
      id: memberId,
      name: displayName,
      email: displayEmail,
      phone: json['cellphone']?.toString() ?? json['phone']?.toString(),
      zipCode: json['zipcode']?.toString() ?? json['postcode1']?.toString(),
      address1: json['address1']?.toString() ?? json['addr1']?.toString(),
      address2: json['address2']?.toString() ?? json['addr2']?.toString(),
      groupName: json['group_name']?.toString() ?? '수지씨앤엘 정회원',
      points: parsedPoints,
      coupons: coupons ?? (int.tryParse(json['coupons']?.toString() ?? '0') ?? 0),
      orders: orders ?? (int.tryParse(json['orders']?.toString() ?? '0') ?? 0),
      isCafe24Member: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'phone': phone,
        'zipCode': zipCode,
        'address1': address1,
        'address2': address2,
        'profileImageUrl': profileImageUrl,
        'groupName': groupName,
        'points': points,
        'coupons': coupons,
        'orders': orders,
        'isCafe24Member': isCafe24Member,
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString(),
        zipCode: json['zipCode']?.toString(),
        address1: json['address1']?.toString(),
        address2: json['address2']?.toString(),
        profileImageUrl: json['profileImageUrl']?.toString(),
        groupName: json['groupName']?.toString() ?? '수지씨앤엘 정회원',
        points: int.tryParse(json['points']?.toString() ?? '0') ?? 0,
        coupons: int.tryParse(json['coupons']?.toString() ?? '0') ?? 0,
        orders: int.tryParse(json['orders']?.toString() ?? '0') ?? 0,
        isCafe24Member: json['isCafe24Member'] as bool? ?? true,
      );

  User copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    String? zipCode,
    String? address1,
    String? address2,
    String? profileImageUrl,
    String? groupName,
    int? points,
    int? coupons,
    int? orders,
    bool? isCafe24Member,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      zipCode: zipCode ?? this.zipCode,
      address1: address1 ?? this.address1,
      address2: address2 ?? this.address2,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      groupName: groupName ?? this.groupName,
      points: points ?? this.points,
      coupons: coupons ?? this.coupons,
      orders: orders ?? this.orders,
      isCafe24Member: isCafe24Member ?? this.isCafe24Member,
    );
  }
}