import 'package:flutter_test/flutter_test.dart';
import 'package:upispender/data.dart';

void main() {
  test('parses rupees into integer paise, including decimals', () {
    expect(parsePaise('250'), 25000);
    expect(parsePaise('12.75'), 1275);
    expect(parsePaise('0'), isNull);
    expect(parsePaise('-1'), isNull);
    expect(parsePaise('not a number'), isNull);
  });

  test('formats Indian rupees', () {
    expect(rupees(25000), contains('250'));
    expect(rupees(1250), contains('12.50'));
    expect(rupees(1250, hidden: true), contains('••••'));
  });

  test('matches dates without comparing the time', () {
    expect(sameDay(DateTime(2026, 10, 23, 3), DateTime(2026, 10, 23, 23)), true);
    expect(sameDay(DateTime(2026, 10, 23), DateTime(2026, 10, 24)), false);
  });
}
