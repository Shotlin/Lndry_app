import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lndry/features/home/presentation/providers/home_providers.dart';
import 'package:lndry/features/search/presentation/pages/search_page.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/repositories/mock/mock_customer_repository.dart';

/// Regression test for the "Choose a service" grid on the Explore/Search
/// page. Two-word category names ("Blanket Cleaning", "Curtain Cleaning",
/// "Carpet Cleaning") used to truncate to "Blanket Cl..." because the grid
/// cell was too short for the title to wrap — see search_page.dart's
/// GridView.builder gridDelegate (childAspectRatio) and the title Text's
/// maxLines.
class _FakeCategoryRepository extends MockCustomerRepository {
  @override
  Future<List<CategoryModel>> getCategories() async {
    return const [
      CategoryModel(
        id: 'cat_wash_fold',
        name: 'Wash & Fold',
        description: 'Everyday laundry',
        icon: 'washer',
      ),
      CategoryModel(
        id: 'cat_blanket',
        name: 'Blanket Cleaning',
        description: 'Deep cleaning for blankets and quilts',
        icon: 'tag',
      ),
      CategoryModel(
        id: 'cat_curtain',
        name: 'Curtain Cleaning',
        description: 'Gentle care for curtains',
        icon: 'tag',
      ),
      CategoryModel(
        id: 'cat_carpet',
        name: 'Carpet Cleaning',
        description: 'Deep sanitizing for carpets',
        icon: 'tag',
      ),
    ];
  }
}

void main() {
  testWidgets(
      'SearchPage category grid shows full names, no overflow, at 320dp',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerRepositoryProvider
              .overrideWithValue(_FakeCategoryRepository()),
          currentAddressProvider.overrideWith((ref) async => null),
        ],
        child: ScreenUtilInit(
          designSize: const Size(320, 568),
          minTextAdapt: true,
          builder: (context, child) => const MaterialApp(
            home: SearchPage(),
          ),
        ),
      ),
    );

    // Let _loadCategories()'s async fetch resolve and the widget rebuild.
    // (pump() with a bounded duration, not pumpAndSettle() — this page has
    // a speech-to-text controller that keeps a timer alive indefinitely.)
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The full names must render — not "Blanket Cl..." etc.
    expect(find.text('Blanket Cleaning'), findsOneWidget);
    expect(find.text('Curtain Cleaning'), findsOneWidget);
    expect(find.text('Carpet Cleaning'), findsOneWidget);

    // No RenderFlex overflow (or any other) rendering exception.
    expect(tester.takeException(), isNull);
  });
}
