import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lndry/core/constants/app_constants.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:lndry/features/address/location_capture_service.dart';
import 'package:lndry/features/home/presentation/providers/home_providers.dart';
import 'package:lndry/main.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testAddress = AddressModel(
  id: 'addr_test',
  userId: 'usr_test',
  line1: 'Test St',
  city: 'Bengaluru',
  state: 'Karnataka',
  pincode: '560001',
  type: AddressType.home,
  isDefault: true,
);

class _FakeLocationCaptureService extends LocationCaptureService {
  const _FakeLocationCaptureService({required this.enabled});
  final bool enabled;

  @override
  Future<bool> isDeviceLocationEnabled() async => enabled;
}

Future<_TestStorageService> _authenticatedStorage({
  bool locationRepromptShown = false,
}) async {
  SharedPreferences.setMockInitialValues({
    AppConstants.keyOnboardingDone: true,
    'fresh_install_reset_done_v3': true,
    AppConstants.keyLocationRepromptShown: locationRepromptShown,
  });
  final prefs = await SharedPreferences.getInstance();
  final storage = _TestStorageService(prefs: prefs);
  await storage.saveSecure(AppConstants.keyAccessToken, 'mock_access_token');
  await storage.saveSecure(AppConstants.keyRefreshToken, 'mock_refresh_token');
  await storage.saveBool('user_has_address', value: true);
  return storage;
}

void main() {
  testWidgets(
      'Home shows the location capture sheet on first load when the user has no default address',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.resetStatic();
    final storage = await _authenticatedStorage();
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          storageServiceProvider.overrideWithValue(storage),
          customerRepositoryProvider.overrideWithValue(MockCustomerRepository()),
          currentAddressProvider.overrideWith((ref) async => null),
          homeCategoriesProvider.overrideWith((ref) async => const []),
          homeVendorsProvider.overrideWith((ref) async => const []),
          activeOrdersProvider.overrideWith((ref) async => const []),
        ],
        child: const LndryApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.text('Set Your Delivery Location'), findsOneWidget);
  });

  testWidgets(
      'Home does not show the sheet when a default address exists and location is enabled',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.resetStatic();
    final storage = await _authenticatedStorage();
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          storageServiceProvider.overrideWithValue(storage),
          customerRepositoryProvider.overrideWithValue(MockCustomerRepository()),
          currentAddressProvider.overrideWith((ref) async => _testAddress),
          locationCaptureServiceProvider
              .overrideWithValue(const _FakeLocationCaptureService(enabled: true)),
          homeCategoriesProvider.overrideWith((ref) async => const []),
          homeVendorsProvider.overrideWith((ref) async => const []),
          activeOrdersProvider.overrideWith((ref) async => const []),
        ],
        child: const LndryApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.text('Set Your Delivery Location'), findsNothing);
    expect(find.text('Location Access Turned Off'), findsNothing);
    expect(
        find.text('What would you like us to care for today?'), findsOneWidget);
  });

  testWidgets(
      'Home shows the reprompt sheet once when location is off, and not again on a second cold start within the same off-state',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.resetStatic();
    final storage = await _authenticatedStorage();
    final prefs = await SharedPreferences.getInstance();

    final overrides = [
      sharedPreferencesProvider.overrideWithValue(prefs),
      storageServiceProvider.overrideWithValue(storage),
      customerRepositoryProvider.overrideWithValue(MockCustomerRepository()),
      currentAddressProvider.overrideWith((ref) async => _testAddress),
      locationCaptureServiceProvider
          .overrideWithValue(const _FakeLocationCaptureService(enabled: false)),
      homeCategoriesProvider.overrideWith((ref) async => const []),
      homeVendorsProvider.overrideWith((ref) async => const []),
      activeOrdersProvider.overrideWith((ref) async => const []),
    ];

    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const LndryApp()),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.text('Location Access Turned Off'), findsOneWidget);

    // Simulate a fresh cold start: force a full teardown of the previous
    // widget tree (pumpWidget with a matching root type otherwise performs
    // an in-place *update*, not a dispose+rebuild, which would leave the
    // still-open sheet from pump 1 mounted) before rebuilding LndryApp,
    // reusing the same underlying SharedPreferences instance so the
    // persisted re-prompt flag (now true) carries over.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final storage2 = _TestStorageService(prefs: prefs);
    await storage2.saveSecure(AppConstants.keyAccessToken, 'mock_access_token');
    await storage2.saveSecure(AppConstants.keyRefreshToken, 'mock_refresh_token');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          storageServiceProvider.overrideWithValue(storage2),
          customerRepositoryProvider.overrideWithValue(MockCustomerRepository()),
          currentAddressProvider.overrideWith((ref) async => _testAddress),
          locationCaptureServiceProvider
              .overrideWithValue(const _FakeLocationCaptureService(enabled: false)),
          homeCategoriesProvider.overrideWith((ref) async => const []),
          homeVendorsProvider.overrideWith((ref) async => const []),
          activeOrdersProvider.overrideWith((ref) async => const []),
        ],
        child: const LndryApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.text('Location Access Turned Off'), findsNothing);
  });
}

class _TestStorageService extends StorageService {
  _TestStorageService({required super.prefs});

  final Map<String, String> _secureValues = {};

  @override
  Future<void> saveSecure(String key, String value) async {
    _secureValues[key] = value;
  }

  @override
  Future<String?> getSecure(String key) async => _secureValues[key];

  @override
  Future<void> deleteSecure(String key) async {
    _secureValues.remove(key);
  }

  @override
  Future<void> deleteAllSecure() async {
    _secureValues.clear();
  }

  @override
  Future<Map<String, String>> getAllSecure() async =>
      Map<String, String>.from(_secureValues);
}
