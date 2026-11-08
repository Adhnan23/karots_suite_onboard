import 'package:flutter/material.dart';

import '../data/models.dart';
import '../sync/push.dart';
import 'shop_product_editor.dart';
import 'shop_products_screen.dart';
import 'shop_screen.dart';

void _go(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

/// The shop screen's actions, in order.
void registerShopActions() {
  if (shopActions.isNotEmpty) return;
  shopActions.addAll([
    (
      icon: Icons.add_box_outlined,
      label: 'New product',
      needsConnection: false,
      open: (c, s) => _go(
        c,
        ShopProductEditor(
          shop: s,
          draft: Draft(product: CatalogProduct(name: '')),
        ),
      ),
    ),
    (icon: Icons.list_alt_rounded, label: 'Products in this shop', needsConnection: false, open: (c, s) => _go(c, ShopProductsScreen(shop: s))),
    (icon: Icons.cloud_upload_outlined, label: 'Waiting to push', needsConnection: false, open: (c, s) => _go(c, PendingScreen(shop: s))),
  ]);
}
