import 'package:flutter/material.dart';

class CategoryPage extends StatelessWidget {
  const CategoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('카테고리'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF212121),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: const Center(
        child: Text('카테고리 화면', style: TextStyle(fontSize: 16)),
      ),
    );
  }
}
