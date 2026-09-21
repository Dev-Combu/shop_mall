import 'package:flutter/material.dart';

class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('마이페이지'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF212121),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: const Center(
        child: Text('마이페이지 화면', style: TextStyle(fontSize: 16)),
      ),
    );
  }
}
