import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/input/category_tree.dart';

void main() {
  final paths = ['Medicine > Pain', 'Medicine > Antibiotics', 'Medicine', 'Cleaning', 'Medicine > Pain > Children'];

  test('a tree from paths: parents made even when only children are listed, sorted', () {
    final t = CategoryTree(paths.where((p) => p != 'Medicine'));
    expect([for (final n in t.rows(expanded: {})) n.path], ['Cleaning', 'Medicine']);
    expect(
      [
        for (final n in t.rows(expanded: {'Medicine'})) '${'  ' * n.depth}${n.name}',
      ],
      ['Cleaning', 'Medicine', '  Antibiotics', '  Pain'],
    );
    expect(t.node('Medicine > Pain')!.hasChildren, isTrue);
    expect(t.node('Cleaning')!.hasChildren, isFalse);
  });

  test('a search shows matches with their parents, opened', () {
    final t = CategoryTree(paths);
    expect([for (final n in t.rows(expanded: {}, query: 'child')) n.path], ['Medicine', 'Medicine > Pain', 'Medicine > Pain > Children']);
    expect(t.rows(expanded: {}, query: 'zzz'), isEmpty);
  });

  test('adding under a category, or at the top', () {
    final t = CategoryTree(paths);
    expect(t.add('Medicine > Pain', ' Fever '), 'Medicine > Pain > Fever');
    expect(t.add(null, 'Toys'), 'Toys');
    expect(t.node('Medicine > Pain > Fever'), isNotNull);
    expect(t.add('Medicine', 'pain'), 'Medicine > Pain', reason: 'an existing name is picked, not doubled');
  });
}
