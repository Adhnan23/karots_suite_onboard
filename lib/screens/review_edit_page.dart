import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state.dart';
import '../sync/review.dart';
import '../ui/kit.dart';
import 'identify_sheet.dart';
import 'product_form.dart';

/// "Fix and accept": the whole product, Identify to tidy a supplier's name, then
/// into the catalogue.
class ReviewEditPage extends StatelessWidget {
  ReviewEditPage({super.key, required this.item});
  final ReviewItem item;
  final form = GlobalKey<ProductFormState>();

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    final p = CatalogProduct.fromJson(item.data);
    return Scaffold(
      appBar: AppBar(title: const Text('Fix and accept')),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: identifyButton(context, Shop(name: 'the catalogue'), form),
            ),
            const SizedBox(height: 8),
            FutureBuilder(
              future: Future.wait([db.knownUnits(), db.suppliers()]),
              builder: (context, snap) => snap.data == null
                  ? const LinearProgressIndicator()
                  : ProductForm(
                      key: form,
                      product: p,
                      units: snap.data![0] as List<String>,
                      suppliers: [for (final x in snap.data![1] as List<CatalogSupplier>) (uid: x.uid, name: x.name)],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.check_rounded),
        label: const Text('Accept'),
        onPressed: () async {
          final problem = form.currentState?.problem();
          if (problem != null) return toast(context, problem, error: true);
          final x = form.currentState?.read();
          if (x == null || x.name.isEmpty) return toast(context, 'Give it a name', error: true);
          await acceptReview(db, item.uid, edited: x.toJson().cast<String, dynamic>());
          if (context.mounted) Navigator.pop(context, true);
        },
      ),
    );
  }
}
