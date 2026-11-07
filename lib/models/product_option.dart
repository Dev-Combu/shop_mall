/// Cafe24 상품 옵션 및 추가 상품 옵션 모델
class ProductOptionValue {
  final String text;
  final int additionalAmount;
  final String? valueNo;

  const ProductOptionValue({
    required this.text,
    this.additionalAmount = 0,
    this.valueNo,
  });

  factory ProductOptionValue.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['additional_amount']?.toString() ??
        json['option_additional_amount']?.toString();
    final doubleAmount = double.tryParse(rawAmount ?? '0') ?? 0.0;

    final text = (json['option_text'] ??
            json['additional_option_value'] ??
            json['value'] ??
            '')
        .toString()
        .trim();

    int amount = doubleAmount.round();
    // 텍스트 내에 (+5,000) 또는 (-26,400) 형태의 금액이 포함되어 있고 API 금액이 0이면 텍스트에서 금액 파싱
    if (amount == 0 && text.contains('(')) {
      final match = RegExp(r'\(([+-]?[\d,]+)\s*원?\)').firstMatch(text);
      if (match != null) {
        final numStr = match.group(1)!.replaceAll(',', '');
        amount = int.tryParse(numStr) ?? 0;
      }
    }

    return ProductOptionValue(
      text: text,
      additionalAmount: amount,
      valueNo: json['value_no']?.toString(),
    );
  }

  String get formattedAdditionalAmount {
    if (additionalAmount > 0) {
      return ' (+${_formatNumber(additionalAmount)}원)';
    } else if (additionalAmount < 0) {
      return ' (-${_formatNumber(additionalAmount.abs())}원)';
    }
    return '';
  }

  static String _formatNumber(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

/// 옵션 그룹 (예: '색상', '사이즈', '추가상품')
class ProductOptionGroup {
  final String name;
  final bool isRequired;
  final bool isAdditional;
  final List<ProductOptionValue> values;

  const ProductOptionGroup({
    required this.name,
    this.isRequired = true,
    this.isAdditional = false,
    required this.values,
  });

  factory ProductOptionGroup.fromJson(
    Map<String, dynamic> json, {
    bool isAdditional = false,
  }) {
    final rawValues = isAdditional
        ? (json['additional_option_value'] as List? ?? const [])
        : (json['option_value'] as List? ?? const []);

    final values = rawValues
        .whereType<Map<String, dynamic>>()
        .map(ProductOptionValue.fromJson)
        .where((v) => v.text.isNotEmpty && v.text != '*' && v.text != '**')
        .toList();

    final name = (json['option_name'] ??
            json['additional_option_name'] ??
            '옵션 선택')
        .toString()
        .trim();

    final rawReq = json['required_option'];
    final bool isReq;
    if (rawReq != null) {
      isReq = rawReq == 'T' || rawReq == true;
    } else {
      isReq = !isAdditional;
    }

    return ProductOptionGroup(
      name: name,
      isRequired: isReq,
      isAdditional: isAdditional,
      values: values,
    );
  }
}

/// 상품의 전체 옵션 데이터
class ProductOptionsData {
  final bool hasOption;
  final List<ProductOptionGroup> requiredGroups;
  final List<ProductOptionGroup> additionalGroups;

  const ProductOptionsData({
    this.hasOption = false,
    this.requiredGroups = const [],
    this.additionalGroups = const [],
  });

  bool get isEmpty => requiredGroups.isEmpty && additionalGroups.isEmpty;
  bool get isNotEmpty => !isEmpty;

  factory ProductOptionsData.fromJson(Map<String, dynamic> json) {
    final optionsObj = json['options'];
    if (optionsObj is! Map<String, dynamic>) {
      return const ProductOptionsData();
    }

    final hasOpt = optionsObj['has_option'] == 'T' ||
        optionsObj['has_option'] == true;
    final useAdditional = optionsObj['use_additional_option'] == 'T' ||
        optionsObj['use_additional_option'] == true;

    final List<ProductOptionGroup> reqGroups = [];
    final rawReq = optionsObj['options'];
    if (rawReq is List) {
      for (final item in rawReq) {
        if (item is Map<String, dynamic>) {
          final group = ProductOptionGroup.fromJson(item, isAdditional: false);
          if (group.values.isNotEmpty) {
            reqGroups.add(group);
          }
        }
      }
    }

    final List<ProductOptionGroup> addGroups = [];
    if (useAdditional) {
      final rawAdd = optionsObj['additional_options'];
      if (rawAdd is List) {
        for (final item in rawAdd) {
          if (item is Map<String, dynamic>) {
            final group = ProductOptionGroup.fromJson(item, isAdditional: true);
            if (group.values.isNotEmpty) {
              addGroups.add(group);
            }
          }
        }
      }
    }

    return ProductOptionsData(
      hasOption: hasOpt || reqGroups.isNotEmpty,
      requiredGroups: reqGroups,
      additionalGroups: addGroups,
    );
  }
}

