import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../repositories/repositories.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../core/network/network.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../config/env.dart';
import '../../../../core/network/friendly_error.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  NotificationPreferences _notificationPrefs = const NotificationPreferences();
  bool _prefsLoaded = false;
  bool _isSavingPrefs = false;

  AccountDeletionRequest? _deletionRequest;
  bool _isSubmittingDeletion = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadDeletionRequest();
  }

  bool get _signedIn => ref.read(authProvider) is AuthAuthenticated || Env.demoMode;

  /// Whether a "Delete Account" request is already waiting for review — the
  /// tile then shows that instead of letting the customer file a second one.
  Future<void> _loadDeletionRequest() async {
    if (!_signedIn) return;
    try {
      final request =
          await ref.read(customerRepositoryProvider).getAccountDeletionRequest();
      if (mounted) setState(() => _deletionRequest = request);
    } catch (_) {
      // Non-critical: the tile just shows its normal state.
    }
  }

  Future<void> _confirmAndRequestDeletion() async {
    final confirmed = await AppDialog.show(
      context,
      title: 'Delete your account?',
      message:
          'This sends a request to permanently delete your LNDRY account. '
          'Our team reviews every request.\n\n'
          'Once approved, your account is closed and you are signed out. '
          'Your personal details, saved addresses and devices are permanently '
          'erased after 30 days, and past orders are kept only in anonymous form. '
          'Any unused wallet balance cannot be recovered afterwards.',
      confirmLabel: 'Request Deletion',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmittingDeletion = true);
    try {
      final request =
          await ref.read(customerRepositoryProvider).requestAccountDeletion();
      if (!mounted) return;
      setState(() => _deletionRequest = request);
      AppSnackBar.showSuccess(context, 'Account deletion request sent.');
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        e is ApiException ? e.message : 'Could not send your request. Please try again.',
      );
      // A duplicate means one already exists — pick it up so the tile reflects it.
      if (e is ApiException && e.code == 'DELETION_ALREADY_REQUESTED') {
        _loadDeletionRequest();
      }
    } finally {
      if (mounted) setState(() => _isSubmittingDeletion = false);
    }
  }

  Future<void> _loadPrefs() async {
    final authState = ref.read(authProvider);
    final signedIn = authState is AuthAuthenticated || Env.demoMode;

    if (!signedIn) {
      try {
        final storage = ref.read(storageServiceProvider);
        final orderUpdates = storage.getBool('guest_pref_order_updates') ?? true;
        final promotions = storage.getBool('guest_pref_promotions') ?? false;
        final newProducts = storage.getBool('guest_pref_new_products') ?? false;
        final deliveryUpdates = storage.getBool('guest_pref_delivery_updates') ?? true;
        final priceDrops = storage.getBool('guest_pref_price_drops') ?? false;

        if (mounted) {
          setState(() {
            _notificationPrefs = NotificationPreferences(
              orderUpdates: orderUpdates,
              promotions: promotions,
              newProducts: newProducts,
              deliveryUpdates: deliveryUpdates,
              priceDrops: priceDrops,
            );
            _prefsLoaded = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _prefsLoaded = true);
      }
      return;
    }

    try {
      final prefs = await ref
          .read(customerRepositoryProvider)
          .getNotificationPreferences();
      if (mounted) {
        setState(() {
          _notificationPrefs = prefs;
          _prefsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _prefsLoaded = true);
    }
  }

  Future<void> _updateNotificationPrefs({
    bool? orderUpdates,
    bool? promotions,
    bool? newProducts,
    bool? deliveryUpdates,
    bool? priceDrops,
  }) async {
    final authState = ref.read(authProvider);
    final signedIn = authState is AuthAuthenticated || Env.demoMode;

    setState(() => _isSavingPrefs = true);
    try {
      if (!signedIn) {
        final storage = ref.read(storageServiceProvider);
        final updated = NotificationPreferences(
          orderUpdates: orderUpdates ?? _notificationPrefs.orderUpdates,
          promotions: promotions ?? _notificationPrefs.promotions,
          newProducts: newProducts ?? _notificationPrefs.newProducts,
          deliveryUpdates: deliveryUpdates ?? _notificationPrefs.deliveryUpdates,
          priceDrops: priceDrops ?? _notificationPrefs.priceDrops,
        );

        if (orderUpdates != null) {
          await storage.saveBool('guest_pref_order_updates', value: orderUpdates);
        }
        if (promotions != null) {
          await storage.saveBool('guest_pref_promotions', value: promotions);
        }
        if (newProducts != null) {
          await storage.saveBool('guest_pref_new_products', value: newProducts);
        }
        if (deliveryUpdates != null) {
          await storage.saveBool('guest_pref_delivery_updates', value: deliveryUpdates);
        }
        if (priceDrops != null) {
          await storage.saveBool('guest_pref_price_drops', value: priceDrops);
        }

        if (mounted) setState(() => _notificationPrefs = updated);
        return;
      }

      final updated = await ref
          .read(customerRepositoryProvider)
          .updateNotificationPreferences(
            orderUpdates: orderUpdates,
            promotions: promotions,
            newProducts: newProducts,
            deliveryUpdates: deliveryUpdates,
            priceDrops: priceDrops,
          );
      if (mounted) setState(() => _notificationPrefs = updated);
    } catch (e) {
      if (mounted) AppSnackBar.showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isSavingPrefs = false);
    }
  }

  Widget _buildThemeSection(bool isDark, ThemeMode themeMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Theme', style: AppTypography.titleMedium),
        Gap(AppSpacing.cardGap.h),
        AppCard.outlined(
          padding: EdgeInsets.zero,
          child: Material(
            color: isDark ? AppColors.darkSurface : AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.card.r),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text('System Default',
                      style: AppTypography.bodyMedium),
                  value: ThemeMode.system,
                  groupValue: themeMode,
                  onChanged: (val) {
                    if (val != null) {
                      ref
                          .read(themeModeProvider.notifier)
                          .setTheme(val);
                    }
                  },
                ),
                Divider(height: 1, color: AppColors.outline),
                RadioListTile<ThemeMode>(
                  title: Text('Light Mode',
                      style: AppTypography.bodyMedium),
                  value: ThemeMode.light,
                  groupValue: themeMode,
                  onChanged: (val) {
                    if (val != null) {
                      ref
                          .read(themeModeProvider.notifier)
                          .setTheme(val);
                    }
                  },
                ),
                Divider(height: 1, color: AppColors.outline),
                RadioListTile<ThemeMode>(
                  title: Text('Dark Mode',
                      style: AppTypography.bodyMedium),
                  value: ThemeMode.dark,
                  groupValue: themeMode,
                  onChanged: (val) {
                    if (val != null) {
                      ref
                          .read(themeModeProvider.notifier)
                          .setTheme(val);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final isDark = theme.brightness == Brightness.dark;
    final themeMode =
        kThemeSwitchingEnabled ? ref.watch(themeModeProvider) : ThemeMode.light;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Settings', style: AppTypography.titleLarge),
        centerTitle: true,
        // Use context.pop() — settings is pushed onto the nav stack.
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          onPressed: () => context.pop(),
        ),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: !_prefsLoaded
            ? const AppLoadingPage()
            : SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.pagePaddingH.w,
                  vertical: AppSpacing.pagePaddingV.h,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Theme Preferences ────────────────────────────────────
                    // Hidden while the app is locked to light mode; see
                    // kThemeSwitchingEnabled in theme_provider.dart.
                    if (kThemeSwitchingEnabled) ...[
                      _buildThemeSection(isDark, themeMode),
                      Gap(AppSpacing.sectionGap.h * 1.5),
                    ],

                    // ── Notifications ────────────────────────────────────────
                    Text('Notifications', style: AppTypography.titleMedium),
                    Gap(AppSpacing.cardGap.h),
                    AppCard.outlined(
                      padding: EdgeInsets.zero,
                      child: Material(
                        color: isDark ? AppColors.darkSurface : AppColors.white,
                        borderRadius: BorderRadius.circular(AppRadius.card.r),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            SwitchListTile.adaptive(
                              title: Text('Order Updates',
                                  style: AppTypography.bodyMedium),
                              subtitle: Text(
                                'Pickup, status and delivery alerts',
                                style: AppTypography.caption,
                              ),
                              value: _notificationPrefs.orderUpdates,
                              activeColor: AppColors.primary,
                              onChanged: _isSavingPrefs
                                  ? null
                                  : (value) => _updateNotificationPrefs(
                                        orderUpdates: value,
                                      ),
                            ),
                            Divider(height: 1, color: AppColors.outline),
                            SwitchListTile.adaptive(
                              title: Text('Promotions',
                                  style: AppTypography.bodyMedium),
                              subtitle: Text(
                                'Offers and campaign updates',
                                style: AppTypography.caption,
                              ),
                              value: _notificationPrefs.promotions,
                              activeColor: AppColors.primary,
                              onChanged: _isSavingPrefs
                                  ? null
                                  : (value) => _updateNotificationPrefs(
                                        promotions: value,
                                      ),
                            ),
                            Divider(height: 1, color: AppColors.outline),
                            SwitchListTile.adaptive(
                              title: Text('New Products',
                                  style: AppTypography.bodyMedium),
                              value: _notificationPrefs.newProducts,
                              activeColor: AppColors.primary,
                              onChanged: _isSavingPrefs
                                  ? null
                                  : (value) => _updateNotificationPrefs(
                                        newProducts: value,
                                      ),
                            ),
                            Divider(height: 1, color: AppColors.outline),
                            SwitchListTile.adaptive(
                              title: Text('Delivery Updates',
                                  style: AppTypography.bodyMedium),
                              value: _notificationPrefs.deliveryUpdates,
                              activeColor: AppColors.primary,
                              onChanged: _isSavingPrefs
                                  ? null
                                  : (value) => _updateNotificationPrefs(
                                        deliveryUpdates: value,
                                      ),
                            ),
                            Divider(height: 1, color: AppColors.outline),
                            SwitchListTile.adaptive(
                              title: Text('Price Drops',
                                  style: AppTypography.bodyMedium),
                              value: _notificationPrefs.priceDrops,
                              activeColor: AppColors.primary,
                              onChanged: _isSavingPrefs
                                  ? null
                                  : (value) => _updateNotificationPrefs(
                                        priceDrops: value,
                                      ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Gap(AppSpacing.sectionGap.h * 1.5),

                    // ── Account ──────────────────────────────────────────────
                    if (_signedIn) ...[
                      Text('Account', style: AppTypography.titleMedium),
                      Gap(AppSpacing.cardGap.h),
                      AppCard.outlined(
                        padding: EdgeInsets.zero,
                        child: Material(
                          color: isDark ? AppColors.darkSurface : AppColors.white,
                          borderRadius: BorderRadius.circular(AppRadius.card.r),
                          clipBehavior: Clip.antiAlias,
                          child: (_deletionRequest?.isPending ?? false)
                              ? ListTile(
                                  leading: Icon(AppIcons.info,
                                      color: AppColors.onSurfaceVariant),
                                  title: Text('Account deletion requested',
                                      style: AppTypography.bodyMedium),
                                  subtitle: Text(
                                    'Our team is reviewing your request.',
                                    style: AppTypography.caption,
                                  ),
                                )
                              : ListTile(
                                  leading: Icon(AppIcons.delete,
                                      color: AppColors.error),
                                  title: Text(
                                    'Delete Account',
                                    style: AppTypography.bodyMedium
                                        .copyWith(color: AppColors.error),
                                  ),
                                  subtitle: Text(
                                    'Request permanent deletion of your account',
                                    style: AppTypography.caption,
                                  ),
                                  trailing: _isSubmittingDeletion
                                      ? SizedBox(
                                          width: 18.r,
                                          height: 18.r,
                                          child: const CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : null,
                                  onTap: _isSubmittingDeletion
                                      ? null
                                      : _confirmAndRequestDeletion,
                                ),
                        ),
                      ),
                      Gap(AppSpacing.sectionGap.h * 1.5),
                    ],

                    // ── App Version ──────────────────────────────────────────
                    Center(
                      child: Text(
                        'LNDRY v1.0.0',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    Gap(AppSpacing.md.h),
                  ],
                ),
              ),
      ),
    );
  }
}
