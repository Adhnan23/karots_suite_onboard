import 'package:flutter/material.dart';

import 'screens/catalog_screen.dart';
import 'screens/review_screen.dart';
import 'screens/shops_screen.dart';

/// The app after unlock: Shops, Catalogue, Review, Duplicates. Phone = bottom bar,
/// wide = side rail.
class AppHome extends StatefulWidget {
  const AppHome({super.key});
  @override
  State<AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<AppHome> {
  int tab = 0;
  static const dests = [
    (Icons.storefront_outlined, Icons.storefront, 'Shops'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Catalogue'),
    (Icons.fact_check_outlined, Icons.fact_check, 'Review'),
    (Icons.merge_type_outlined, Icons.merge_type, 'Duplicates'),
  ];

  Widget page(int i) => switch (i) {
    0 => const ShopsScreen(),
    1 => const CatalogScreen(),
    2 => const ReviewScreen(),
    _ => Center(child: Text(dests[i].$3)),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = page(tab);
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: tab,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [for (final d in dests) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
      ),
    );
  }
}
