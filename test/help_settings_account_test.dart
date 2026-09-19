import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lndry/core/constants/app_constants.dart';
import 'package:lndry/core/network/network.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:lndry/features/profile/presentation/pages/help_page.dart';
import 'package:lndry/features/profile/presentation/pages/settings_page.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/providers/auth_provider.dart';
import 'package:lndry/providers/theme_provider.dart';
import 'package:lndry/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepo extends MockCustomerRepository {
  _FakeRepo({
    this.faqs = const [],
    this.faqError = false,
    AccountDeletionRequest? existing,
    this.deletionError,
  }) : _existing = existing;

  List<FaqItem> faqs;
  final bool faqError;
  final ApiException? deletionError;
  AccountDeletionRequest? _existing;
  int deletionRequests = 0;

  @override
  Future<List<FaqItem>> getFaqs() async {
    if (faqError) throw ApiException.unknown();
    return faqs;
  }

  @override
  Future<AccountDeletionRequest?> getAccountDeletionRequest() async => _existing;

  @override
  Future<AccountDeletionRequest> requestAccountDeletion({String? reason}) async {
    deletionRequests++;
    if (deletionError != null) throw deletionError!;
    return _existing = AccountDeletionRequest(
      id: 'r1',
      status: 'PENDING',
      requestedAt: DateTime(2026, 9, 19),
    );
  }
}

class _TestStorage extends StorageService {
  _TestStorage({required super.prefs});
  final Map<String, String> _secure = {};
  @override
  Future<void> saveSecure(String key, String value) async => _secure[key] = value;
  @override
  Future<String?> getSecure(String key) async => _secure[key];
  @override
  Future<void> deleteSecure(String key) async => _secure.remove(key);
  @override
  Future<void> deleteAllSecure() async => _secure.clear();
  @override
  Future<Map<String, String>> getAllSecure() async => Map.of(_secure);
}

/// Real notifier (so `authProvider` keeps its type) but pinned to signed-in.
class _SignedInAuth extends AuthNotifier {
  _SignedInAuth(super.repo, super.storage);
  void signIn() => state = const AuthAuthenticated(UserModel(
        id: 'u1',
        name: 'Sayan',
        phone: '9999999999',
        role: UserRole.customer,
      ));
}

Widget _app(Widget home, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: home),
      ),
    );

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Help & FAQs is driven by the backend', () {
    testWidgets('shows whatever the dashboard currently serves', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeRepo(faqs: const [
        FaqItem(id: 'a', question: 'Do you pick up on Sundays?', answer: 'Yes.'),
        FaqItem(id: 'b', question: 'Is there a minimum order?', answer: 'No.'),
      ]);
      await tester.pumpWidget(_app(HelpPage(), [
        customerRepositoryProvider.overrideWithValue(repo),
      ]));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Do you pick up on Sundays?'), findsOneWidget);
      expect(find.text('Is there a minimum order?'), findsOneWidget);
      // The old hardcoded copy must be gone.
      expect(find.text('What is the turnaround time for delivery?'), findsNothing);

      // Expanding reveals the answer served by the backend.
      await tester.tap(find.text('Do you pick up on Sundays?'));
      await tester.pumpAndSettle();
      expect(find.text('Yes.'), findsOneWidget);
    });

    testWidgets('empty list and failed load both render a clear state',
        (tester) async {
      await tester.pumpWidget(_app(HelpPage(), [
        customerRepositoryProvider.overrideWithValue(_FakeRepo()),
      ]));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No FAQs available right now.'), findsOneWidget);

      await tester.pumpWidget(_app(HelpPage(), [
        customerRepositoryProvider.overrideWithValue(_FakeRepo(faqError: true)),
      ]));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("Couldn't load the FAQs right now."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('light mode is locked', () {
    test('a saved dark/system preference is ignored and cannot be changed',
        () async {
      SharedPreferences.setMockInitialValues({AppConstants.keyThemeMode: 'dark'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        storageServiceProvider.overrideWithValue(_TestStorage(prefs: prefs)),
      ]);
      addTearDown(container.dispose);

      expect(kThemeSwitchingEnabled, isFalse);
      expect(container.read(themeModeProvider), ThemeMode.light);

      await container.read(themeModeProvider.notifier).setTheme(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.light);
      await container.read(themeModeProvider.notifier).toggleTheme();
      expect(container.read(themeModeProvider), ThemeMode.light);
      // Nothing was persisted either, so a future re-enable starts clean.
      expect(prefs.getString(AppConstants.keyThemeMode), 'dark');
    });
  });

  group('Settings', () {
    Future<(_FakeRepo, _SignedInAuth)> pumpSettings(
      WidgetTester tester, {
      _FakeRepo? repo,
    }) async {
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fake = repo ?? _FakeRepo();
      SharedPreferences.setMockInitialValues({
        'fresh_install_reset_done_v3': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = _TestStorage(prefs: prefs);
      final auth = _SignedInAuth(fake, storage);
      // Let the notifier's own session-restore settle, then pin signed-in.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      auth.signIn();

      await tester.pumpWidget(_app(const SettingsPage(), [
        customerRepositoryProvider.overrideWithValue(fake),
        storageServiceProvider.overrideWithValue(storage),
        authProvider.overrideWith((ref) => auth),
      ]));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      return (fake, auth);
    }

    testWidgets('has no Theme selector but keeps Notifications', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Theme'), findsNothing);
      expect(find.text('System Default'), findsNothing);
      expect(find.text('Light Mode'), findsNothing);
      expect(find.text('Dark Mode'), findsNothing);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Order Updates'), findsOneWidget);
    });

    testWidgets('Delete Account: warning first, then a real request',
        (tester) async {
      final (repo, _) = await pumpSettings(tester);

      expect(find.text('Delete Account'), findsOneWidget);
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      // Confirmation warning — nothing has been submitted yet.
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(find.textContaining('30 days'), findsOneWidget);
      expect(repo.deletionRequests, 0);

      // Cancelling submits nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.deletionRequests, 0);
      expect(find.text('Delete Account'), findsOneWidget);

      // Confirming creates the request and tells the customer.
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request Deletion'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(repo.deletionRequests, 1);
      expect(find.text('Account deletion request sent.'), findsOneWidget);
      // The tile now reflects the pending request and can't be filed twice.
      expect(find.text('Account deletion requested'), findsOneWidget);
      expect(find.text('Delete Account'), findsNothing);
    });

    testWidgets('an already-pending request is shown on open', (tester) async {
      await pumpSettings(
        tester,
        repo: _FakeRepo(
          existing: AccountDeletionRequest(
            id: 'r0',
            status: 'PENDING',
            requestedAt: DateTime(2026, 9, 1),
          ),
        ),
      );
      expect(find.text('Account deletion requested'), findsOneWidget);
      expect(find.text('Delete Account'), findsNothing);
    });

    testWidgets('a server refusal is shown to the customer', (tester) async {
      final (repo, _) = await pumpSettings(
        tester,
        repo: _FakeRepo(
          deletionError: const ApiException(
            message: 'You have already requested account deletion.',
            statusCode: 409,
            code: 'DELETION_ALREADY_REQUESTED',
          ),
        ),
      );
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request Deletion'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(repo.deletionRequests, 1);
      expect(find.text('You have already requested account deletion.'),
          findsOneWidget);
      expect(find.text('Account deletion request sent.'), findsNothing);
    });
  });
}
