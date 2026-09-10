import 'package:flutter/material.dart';

class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('마켓'),
        actions: [
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('마켓 검색 기능을 준비하고 있어요.')),
              );
            },
            icon: const Icon(Icons.search_rounded),
            tooltip: '검색',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'LANGGRY 마켓',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '학습 자료와 언어 콘텐츠를 만날 수 있는 공간입니다.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _MarketPlaceholderCard(
            icon: Icons.menu_book_rounded,
            title: '학습 콘텐츠',
            description: '언어별 학습 자료를 준비하고 있어요.',
          ),
          const _MarketPlaceholderCard(
            icon: Icons.style_rounded,
            title: '단어 카드',
            description: '맞춤형 단어 카드 상품을 준비하고 있어요.',
          ),
          const _MarketPlaceholderCard(
            icon: Icons.people_alt_rounded,
            title: '커뮤니티 자료',
            description: '사용자들이 공유하는 자료를 준비하고 있어요.',
          ),
        ],
      ),
    );
  }
}

class _MarketPlaceholderCard extends StatelessWidget {
  const _MarketPlaceholderCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
        trailing: const Chip(label: Text('준비 중')),
      ),
    );
  }
}
