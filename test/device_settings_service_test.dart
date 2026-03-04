import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adscreen/services/device_settings_service.dart';

void main() {
  setUp(() {
    // Basic mock for SharedPreferences
    SharedPreferences.setMockInitialValues({});
  });

  test('DeviceSettingsService initializes with defaults', () async {
    final service = DeviceSettingsService();
    await service.initialize();

    // Verify some defaults
    expect(service.getSetting<String>('rotationLock', ''), 'landscape');
    expect(service.getSetting<bool>('screenBurnInPrevention', false), true);
    expect(service.getSetting<int>('maxVolumeLimit', 0), 80);
    expect(service.getSetting<bool>('usbPortBlock', true), false);
  });

  test('applySettings merges incoming values and overwrites defaults', () async {
    final service = DeviceSettingsService();
    await service.initialize();

    final incoming = {
      'rotationLock': 'portrait',
      'maxVolumeLimit': 50,
      'usbPortBlock': true,
      'newUnknownKey': 'tested'
    };

    await service.applySettings(incoming);

    // Assert over-written values
    expect(service.getSetting<String>('rotationLock', ''), 'portrait');
    expect(service.getSetting<int>('maxVolumeLimit', 0), 50);
    expect(service.getSetting<bool>('usbPortBlock', false), true);
    
    // Assert untouched defaults remain
    expect(service.getSetting<bool>('screenBurnInPrevention', false), true);
    expect(service.getSetting<String>('autoRebootDay', ''), 'daily');
    
    // Assert new keys are added
    expect(service.getSetting<String>('newUnknownKey', ''), 'tested');
  });

  test('applySettings removes server metadata keys before saving', () async {
    final service = DeviceSettingsService();
    await service.initialize();

    final incoming = {
      'type': 'device_settings_updated',
      'timestamp': '2023-10-27T12:00:00Z',
      'updated_at': '2023-10-27T12:00:00Z',
      'rotationLock': 'auto'
    };

    await service.applySettings(incoming);

    expect(service.currentSettings.containsKey('type'), false);
    expect(service.currentSettings.containsKey('timestamp'), false);
    expect(service.currentSettings.containsKey('updated_at'), false);
    expect(service.getSetting<String>('rotationLock', ''), 'auto');
  });
}
