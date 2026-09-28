class User {
  final String id;
  final String email;
  final String name;
  final String? profileImageUrl;
  final int points;
  final int coupons;
  final int orders;

  User({
    required this.id,
    required this.email,
    required this.name,
    this.profileImageUrl,
    this.points = 1500,
    this.coupons = 3,
    this.orders = 2,
  });
}