import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upispender/sms_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannel('com.upispender.upispender/sms');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
  });

  test('SMS capture is off without permission', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
      if (call.method == 'status') {
        return {'permission': false, 'enabled': false, 'pending': 0};
      }
      return null;
    });
    final state = await SmsDetection.instance.status();
    expect(state.active, isFalse);
    expect(state.pending, 0);
  });

  test('pending detection values stay as integer paise', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
      switch (call.method) {
        case 'pending':
          return [
            {'id': 'hash1', 'paise': 25975, 'payee': 'Swiggy', 'at': 1792700000000, 'sender': 'VK-BANK'},
          ];
        case 'status':
          return {'permission': true, 'enabled': true, 'pending': 1};
        default:
          return true;
      }
    });
    final state = await SmsDetection.instance.status();
    final pending = await SmsDetection.instance.pending();
    expect(state.active, isTrue);
    expect(pending.single.paise, 25975);
    expect(pending.single.payee, 'Swiggy');
  });
}
