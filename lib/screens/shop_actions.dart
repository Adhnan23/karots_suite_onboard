import 'package:flutter/material.dart';

import '../flavor.dart';

import 'alternatives_screen.dart';
import 'export_screen.dart';
import 'quick_add_screen.dart';
import 'identify_sheet.dart';
import 'shop_product_editor.dart';
import 'shop_products_screen.dart';
import 'shop_screen.dart';
import 'suppliers_screen.dart';

void _go(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

/// The shop screen's actions, in order.
void registerShopActions() {
  if (shopActions.isNotEmpty) return;
  editorTools.add(identifyButton);
  shopActions.addAll([
    (icon: Icons.bolt_rounded, label: 'Quick add: scan, price, quantity', needsConnection: false, open: (c, s) => _go(c, QuickAddScreen(shop: s))),
    (icon: Icons.add_box_outlined, label: 'New product', needsConnection: false, open: (c, s) => _go(c, ShopProductEditor.newProduct(s))),
    (icon: Icons.list_alt_rounded, label: 'Products in this shop', needsConnection: false, open: (c, s) => _go(c, ShopProductsScreen(shop: s))),
    (icon: Icons.local_shipping_outlined, label: 'Suppliers in this shop', needsConnection: false, open: (c, s) => _go(c, ShopSuppliersScreen(shop: s))),
    (icon: Icons.cloud_upload_outlined, label: 'Waiting to push', needsConnection: false, open: (c, s) => _go(c, PendingScreen(shop: s))),
    if (!isShelf) (icon: Icons.swap_horiz_rounded, label: 'Alternatives', needsConnection: false, open: (c, s) => _go(c, AlternativesScreen(shop: s))),
    (icon: Icons.table_view_rounded, label: 'Export sheets (CSV)', needsConnection: false, open: (c, s) => _go(c, ExportScreen(shop: s))),
  ]);
}
