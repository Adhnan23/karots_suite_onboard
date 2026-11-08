import '../suite/client.dart';

/// One lot (batch) of a product in the shop.
class Lot {
  Lot({required this.id, required this.qty, this.expiry = '', this.cost = '', this.price = '', this.source = ''});
  final int id;
  final String qty, expiry, cost, price, source; // price "" = follows the product
}

class ProductStock {
  ProductStock(this.total, this.lots);
  final String total;
  final List<Lot> lots;
}

/// The product's live lots, as the Suite's Stock page shows them.
Future<ProductStock> productStock(SuiteClient c, int productId) async {
  final m = await c.get('/admin/stock/lots/$productId') as Map;
  return ProductStock('${m['stockQty'] ?? '0'}', [
    for (final l in (m['lots'] as List? ?? []))
      Lot(
        id: ((l as Map)['id'] as num).toInt(),
        qty: '${l['qtyRemaining'] ?? '0'}',
        expiry: '${l['expiryDate'] ?? ''}',
        cost: '${l['costPrice'] ?? ''}',
        price: '${l['sellingPrice'] ?? ''}',
        source: '${l['source'] ?? ''}',
      ),
  ]);
}

// Quantities to 3 places, exactly (no doubles).
BigInt _q(String s) {
  final t = s.trim().isEmpty ? '0' : s.trim();
  final neg = t.startsWith('-');
  final parts = (neg ? t.substring(1) : t).split('.');
  final frac = (parts.length > 1 ? parts[1] : '').padRight(3, '0').substring(0, 3);
  final v = BigInt.parse(parts[0].isEmpty ? '0' : parts[0]) * BigInt.from(1000) + BigInt.parse(frac);
  return neg ? -v : v;
}

String _s(BigInt v) {
  final neg = v.isNegative;
  final a = v.abs();
  final whole = a ~/ BigInt.from(1000), frac = (a % BigInt.from(1000)).toString().padLeft(3, '0').replaceAll(RegExp(r'0+$'), '');
  return '${neg ? '-' : ''}$whole${frac.isEmpty ? '' : '.$frac'}';
}

/// Changes one lot: its count (booked as a stock correction on that lot, like
/// the Suite's Set count), its expiry and its price. Only what changed is sent.
Future<void> editLot(SuiteClient c, int productId, ProductStock s, Lot lot, {String? count, String? expiry, String? price}) async {
  if (count != null && _q(count) != _q(lot.qty)) {
    final total = _q(s.total) - _q(lot.qty) + _q(count);
    await c.post('/admin/stock/adjust', {'productId': productId, 'newQuantity': _s(total), 'batchId': lot.id, 'note': 'Set in Karots Onboard'});
  }
  if (expiry != null && expiry.trim() != lot.expiry) {
    await c.post('/admin/stock/batches/${lot.id}/expiry', {'expiry': expiry.trim()});
  }
  if (price != null && price.trim() != lot.price) {
    await c.post('/admin/stock/batches/${lot.id}/price', {'sellingPrice': price.trim()});
  }
}
