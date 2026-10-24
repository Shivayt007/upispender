import 'package:flutter_test/flutter_test.dart';
import 'package:flux_player/main.dart';

void main() {
  test('readable download sizes', () {
    expect(humanSize(0), '0 B');
    expect(humanSize(1024), '1.0 KB');
    expect(humanSize(1048576), '1.0 MB');
  });
}
