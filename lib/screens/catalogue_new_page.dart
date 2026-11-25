import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state.dart';
import '../sync/catalogue_online.dart';
import '../ui/kit.dart';

/// Get new from the Karots catalogue: the published version's products Onboard hasn't got, shown first and added
/// only on Add (a product deleted here would come back otherwise: untick it). Nothing Onboard has is changed.
class CatalogueNewPage extends StatefulWidget {
  const CatalogueNewPage({super.key});
  @override
  State<CatalogueNewPage> createState() => _CatalogueNewPageState();
}

class _CatalogueNewPageState extends State<CatalogueNewPage> {
  List<CatalogProduct>? found;
  final skip = <String>{};
  int version = 0;
  String error = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
  }

  Future<void> check() async {
    final db = AppScope.of(context).db;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final online = await fetchCatalogue();
      final have = [for (final p in await db.products()) p.name];
      final fresh = newFromCatalogue(have, online.products);
      if (mounted) {
        setState(() {
          found = fresh;
          version = online.version;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e is CatalogueError ? e.message : 'The catalogue online can\'t be reached: check the internet and try again');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> add() async {
    final take = [
      for (final p in found!)
        if (!skip.contains(p.uid)) p,
    ];
    setState(() => busy = true);
    await AppScope.of(context).db.saveProducts(take, touch: false);
    if (!mounted) return;
    toast(context, '${take.length} new products from the catalogue');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final f = found;
    final n = f == null ? 0 : f.length - skip.length;
    return Scaffold(
      appBar: AppBar(title: const Text('New from the Karots catalogue')),
      bottomNavigationBar: f == null || f.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(onPressed: busy || n == 0 ? null : add, child: Text('Add $n products')),
              ),
            ),
      body: Narrow(
        child: busy && f == null
            ? const Center(child: CircularProgressIndicator())
            : error.isNotEmpty
            ? Empty(icon: Icons.cloud_off_rounded, title: error, sub: null)
            : f!.isEmpty
            ? Empty(icon: Icons.check_circle_outline_rounded, title: 'Nothing new', sub: 'You have every product in catalogue version $version.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    'Catalogue version $version has ${f.length} products you don\'t have. Untick any you don\'t want (one you deleted on purpose). Nothing you have is changed.',
                  ),
                  const SizedBox(height: 8),
                  for (final p in f)
                    CheckboxListTile(
                      value: !skip.contains(p.uid),
                      onChanged: (v) => setState(() => v == true ? skip.remove(p.uid) : skip.add(p.uid)),
                      title: Text(p.name),
                      subtitle: Text([p.unit, ...p.kinds, ...p.fields.values].where((x) => x.isNotEmpty).join(' · ')),
                    ),
                ],
              ),
      ),
    );
  }
}
