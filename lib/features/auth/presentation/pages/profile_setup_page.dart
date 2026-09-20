import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/referral_attribution_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/utils/validators.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../core/network/friendly_error.dart';

class ProfileSetupPage extends ConsumerStatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  ConsumerState<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends ConsumerState<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _referralCodeController = TextEditingController();
  bool _isLoading = false;
  bool _referralAutoApplied = false;

  @override
  void initState() {
    super.initState();
    final pendingCode =
        ReferralAttributionService.consumePendingCode(ref.read(storageServiceProvider));
    if (pendingCode != null) {
      _referralCodeController.text = pendingCode;
      _referralAutoApplied = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final referralOutcome =
          await ref.read(authProvider.notifier).completeProfile(
                name: _nameController.text.trim(),
                email: _emailController.text.trim(),
                referralCode: _referralCodeController.text.trim(),
              );
      // AuthAuthenticated -> the router's global redirect sends the user to
      // Home automatically; no explicit navigation needed here. An invalid
      // referral code never blocks that — just a friendly heads-up on top.
      if (mounted && referralOutcome != null && !referralOutcome.success) {
        AppSnackBar.showError(
          context,
          referralOutcome.message ?? "That referral code didn't work.",
        );
      }
    } catch (e) {
      if (mounted) AppSnackBar.showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const AppLoadingPage(message: 'Saving profile...')
            : SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.pagePaddingH.w,
                  vertical: AppSpacing.pagePaddingV.h,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Gap(20),
                      Text('Setup Your Profile',
                          style: AppTypography.headlineLarge),
                      const Gap(12),
                      Text(
                        'Tell us a bit about yourself to personalise your experience.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const Gap(40),

                      // Avatar with tappable camera icon
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 56.r,
                              backgroundColor: AppColors.primaryContainer,
                              child: Icon(AppIcons.profile,
                                  size: 48.r, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                      const Gap(48),

                      AppTextField(
                        label: 'Full Name',
                        hint: 'Enter your full name',
                        controller: _nameController,
                        keyboardType: TextInputType.name,
                        prefixIcon: const Icon(AppIcons.profile),
                        validator: Validators.name,
                        textCapitalization: TextCapitalization.words,
                      ),
                      const Gap(24),
                      AppTextField(
                        label: 'Email Address',
                        hint: 'Enter your email (optional)',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(AppIcons.email),
                        validator: Validators.emailOptional,
                      ),
                      const Gap(24),
                      AppTextField(
                        label: 'Referral Code',
                        hint: 'Have a friend\'s code? Enter it here (optional)',
                        controller: _referralCodeController,
                        textCapitalization: TextCapitalization.characters,
                        prefixIcon: const Icon(AppIcons.gift),
                        suffixIcon: _referralAutoApplied
                            ? Icon(AppIcons.success, color: AppColors.success)
                            : null,
                        helperText: _referralAutoApplied
                            ? 'Applied automatically from your invite link — you can still change it.'
                            : null,
                        onChanged: (_) {
                          if (_referralAutoApplied) {
                            setState(() => _referralAutoApplied = false);
                          }
                        },
                      ),
                      const Gap(48),
                      AppButton(
                        label: 'Save & Continue',
                        onPressed: _onSave,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
