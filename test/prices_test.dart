import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/input/prices.dart';

import 'cost_code_test.dart' show example;

void main() {
  test('markup is selling ÷ cost to 2 places, blank without both', () {
    expect(markupOf('100', '115'), '1.15');
    expect(markupOf('23', '30'), '1.3');
    expect(markupOf('', '115'), '');
    expect(markupOf('100', ''), '');
  });

  test('cost or markup set the selling price; selling sets the markup', () {
    var p = editPrice(const PriceInput(cost: '200'), 'markup', '1.15', null);
    expect(p.selling, '230');
    p = editPrice(p, 'selling', '250', null);
    expect(p.markup, '1.25');
    p = editPrice(p, 'cost', '100', null);
    expect((p.selling, p.markup), ('250', '2.5'));
  });

  test('a coded cost drives the markup but stays as typed', () {
    final p = editPrice(const PriceInput(markup: '1.15', markupTyped: true), 'cost', 'ESX', example);
    expect(p.cost, 'ESX');
    expect(p.selling, '264.5');
  });

  test('÷ how many divides cost and selling to 2 places', () {
    var r = resolve(const PriceInput(cost: 'ESX', selling: '300', per: '10'), example);
    expect((r.cost, r.selling, r.error), ('23', '30', null));
    r = resolve(const PriceInput(cost: '100', selling: '150', per: '3'), null);
    expect((r.cost, r.selling), ('33.33', '50'));
    r = resolve(const PriceInput(cost: '100', selling: '100', per: '3'), null);
    expect(r.selling, '33.33');
  });

  test('a blank or zero count leaves the prices alone; a non-number is an error', () {
    expect(resolve(const PriceInput(cost: '23', selling: '30'), null).cost, '23');
    final r = resolve(const PriceInput(cost: '23', selling: '30', per: '0'), null);
    expect((r.cost, r.selling), ('23', '30'));
    expect(resolve(const PriceInput(cost: '23', per: 'abc'), null).error, howManyError);
  });

  test('an untouched product saves exactly what it had', () {
    final r = resolve(const PriceInput(cost: '23', selling: '30'), example);
    expect((r.cost, r.selling, r.error), ('23', '30', null));
  });

  test('a cost the code cannot read is an error', () {
    expect(resolve(const PriceInput(cost: 'ESQ'), example).error, "'q' isn't in this shop's code");
  });

  test('typing a cost key by key never moves a selling price nobody typed a markup for', () {
    var p = const PriceInput(selling: '100');
    p = editPrice(p, 'cost', '3', null);
    p = editPrice(p, 'cost', '30', null);
    expect((p.selling, p.markup), ('100', '3.33'));
    p = editPrice(const PriceInput(cost: '30', selling: '100', markup: '3.33'), 'cost', '3', null);
    p = editPrice(p, 'cost', '30', null);
    expect(p.selling, '100', reason: 'backspace and retype keeps the price');
  });

  test('a typed markup keeps driving the selling price as the cost changes', () {
    var p = editPrice(const PriceInput(cost: '200'), 'markup', '1.15', null);
    p = editPrice(p, 'cost', '300', null);
    expect(p.selling, '345');
    p = editPrice(p, 'selling', '400', null);
    p = editPrice(p, 'cost', '200', null);
    expect(p.selling, '400', reason: 'typing the selling price hands the lead back to it');
  });

  test('markup and selling with no cost work the cost out, both orders, and keep it up to date', () {
    var p = editPrice(const PriceInput(), 'markup', '1.25', null);
    p = editPrice(p, 'selling', '250', null);
    expect((p.cost, p.markup, p.selling), ('200', '1.25', '250'));
    p = editPrice(p, 'selling', '500', null);
    expect(p.cost, '400', reason: 'a worked-out cost follows the selling price');
    p = editPrice(p, 'markup', '2', null);
    expect((p.cost, p.selling), ('250', '500'));
    p = editPrice(p, 'selling', '', null);
    expect(p.cost, '', reason: 'nothing to work it out from');
    var q = editPrice(const PriceInput(), 'selling', '300', null);
    q = editPrice(q, 'markup', '1.5', null);
    expect((q.cost, q.selling), ('200', '300'));
  });

  test('a typed cost is never overwritten by markup and selling', () {
    var p = editPrice(const PriceInput(), 'cost', '100', null);
    p = editPrice(p, 'markup', '1.5', null);
    p = editPrice(p, 'selling', '180', null);
    expect((p.cost, p.markup), ('100', '1.8'));
    p = editPrice(const PriceInput(markup: '2', selling: '50', markupTyped: true), 'cost', '', null);
    p = editPrice(p, 'cost', '30', null);
    expect((p.cost, p.selling), ('30', '60'));
  });

  test('÷ how many must be a count above zero', () {
    for (final bad in ['-3', 'Infinity', 'NaN', '-Infinity']) {
      expect(
        resolve(PriceInput(cost: '100', selling: '150', per: bad), null).error,
        howManyError,
        reason: bad,
      );
    }
  });

  test('commas and spaces are ignored in prices, coded or not', () {
    var r = resolve(const PriceInput(cost: '1,250', selling: '1,500.50', per: '1,0'), null);
    expect((r.cost, r.selling, r.error), ('125', '150.05', null));
    r = resolve(const PriceInput(cost: 'E SX', selling: '1 000'), example);
    expect((r.cost, r.selling, r.error), ('230', '1000', null));
    expect(markupOf('1,000', '1,500'), '1.5');
  });
}
