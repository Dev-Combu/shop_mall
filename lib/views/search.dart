import 'package:flutter/material.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('검색'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF212121),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: const Center(
        child: Text('검색 화면', style: TextStyle(fontSize: 16)),
      ),
    );
  }
}
