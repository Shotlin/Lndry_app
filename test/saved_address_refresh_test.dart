import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:lndry/features/address/address_serviceability_validator.dart';
import 'package:lndry/features/home/presentation/providers/home_providers.dart';
import 'package:lndry/features/profile/presentation/pages/saved_addresses_page.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/providers/auth_provider.dart';
import 'package:lndry/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

AddressModel _addr(String id, String line1, {bool isDefault = false}) => AddressModel(
      id: id,
      userId: 'u1',
      line1: line1,
      city: 'Kolkata',
      state: 'WB',
      pincode: '700001',
      type: AddressType.home,
      isDefault: isDefault,
    );

class _Repo extends MockCustomerRepository {
  _Repo({this.failSetDefault = false});
  final bool failSetDefault;
  final List<AddressModel> list = [_addr('a', '12 Old Street', isDefault: true), _addr('b', '99 New Street')];

  @override
  Future<List<AddressModel>> getAddresses() async => List.of(list);

  @override
  Future<void> setDefaultAddress(String addressId) async {
    if (failSetDefault) throw Exception('network down');
    for (var i = 0; i < list.length; i++) {
      list[i] = list[i].copyWith(isDefault: list[i].id == addressId);
    }
  }
}

class _AlwaysServiceable implements AddressServiceabilityValidator {
  @override
  Future<String?> validate({required double lat, required double lng, required String pincode}) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Real notifier (so `authProvider` keeps its type); signed in after its own
/// start-up check (which finds no tokens and would otherwise sign it out).
class _SignedIn extends AuthNotifier {
  _SignedIn(super.repo, super.storage);
  void signIn() => state = const AuthAuthenticated(
      UserModel(id: 'u1', name: 'Sayan', phone: '9999999999', role: UserRole.customer));
}

class _Storage extends StorageService {
  _Storage({required super.prefs});
  final Map<String, String> _secure = {};
  @override
  Future<void> saveSecure(String key, String value) async => _secure[key] = value;
  @override
  Future<String?> getSecure(String key) async => _secure[key];
  @override
  Future<void> deleteSecure(String key) async => _secure.remove(key);
}

Future<(Widget, ProviderContainer Function(WidgetTester), _SignedIn Function())> _harness(_Repo repo) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = _Storage(prefs: prefs);
  late _SignedIn auth;
  final app = ProviderScope(
    overrides: [
      customerRepositoryProvider.overrideWithValue(repo),
      storageServiceProvider.overrideWithValue(storage),
      addressServiceabilityValidatorProvider.overrideWithValue(_AlwaysServiceable()),
      authProvider.overrideWith((ref) => auth = _SignedIn(repo, storage)),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => const MaterialApp(home: SavedAddressesPage()),
    ),
  );
  return (app, (WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(SavedAddressesPage))), () => auth);
}

void main() {
  testWidgets(
    'REGRESSION: choosing a different default address refreshes Home (it used to keep the old address & laundries)',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _Repo();
      final (app, containerOf, _) = await _harness(repo);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      final notifier = containerOf(tester).read(authProvider.notifier) as _SignedIn;
    for (var i = 0; i < 4; i++) { await tester.pump(const Duration(milliseconds: 50)); } // let its own start-up check finish
    notifier.signIn();
      await tester.pumpAndSettle();

      final container = containerOf(tester);
      // Home has already loaded for the OLD default address and caches it.
      expect((await container.read(currentAddressProvider.future))?.id, 'a');

      await tester.tap(find.byTooltip('Set as default'));
      await tester.pumpAndSettle();

      // After the change, the provider Home watches must report the NEW address.
      expect((await container.read(currentAddressProvider.future))?.id, 'b');
    },
  );

  testWidgets('a failed "set default" tells the customer instead of failing silently', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final (app, containerOf, _) = await _harness(_Repo(failSetDefault: true));
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    final notifier = containerOf(tester).read(authProvider.notifier) as _SignedIn;
    for (var i = 0; i < 4; i++) { await tester.pump(const Duration(milliseconds: 50)); } // let its own start-up check finish
    notifier.signIn();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Set as default'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining("Couldn't change your default address"), findsOneWidget);
    // the list is still there to try again
    expect(find.text('12 Old Street, Kolkata'), findsOneWidget);
  });
}
