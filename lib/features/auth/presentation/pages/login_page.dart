import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_gate.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/utils/validators.dart';
import '../../../../providers/auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _onSendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final phone = _phoneController.text.trim();
      await ref.read(authProvider.notifier).sendOtp(phone);
      if (!mounted) return;

      final authState = ref.read(authProvider);
      if (authState is AuthError) {
        AppSnackBar.showError(context, authState.message);
        return;
      }
      if (authState is AuthOtpSent) {
        context.push(otpLocation(returnTo: returnToFrom(context)));
      }
    } catch (e) {
      if (mounted) AppSnackBar.showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const AppLoadingPage(message: 'Sending verification code...')
          : Stack(
              children: [
                // Full-bleed background artwork (logo + tagline baked in).
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/onboarding/login_screen.png',
                    fit: BoxFit.cover,
                  ),
                ),

                // Back button, floating over the artwork.
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: 8.w, top: 4.h),
                      child: Material(
                        color: AppColors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(AppRadius.full.r),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.full.r),
                          onTap: () => _onBack(context),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16.w, vertical: 10.h),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(AppIcons.back,
                                    size: 18.r, color: AppColors.primary),
                                Gap(6.w),
                                Text(
                                  'Back',
                                  style: AppTypography.labelLarge
                                      .copyWith(color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom sheet-style form card over the artwork.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.62,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppRadius.sheet.r),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.textBlack.withValues(alpha: 0.1),
                          blurRadius: 24,
                          offset: const Offset(0, -8),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.pagePaddingH.w,
                          28.h,
                          AppSpacing.pagePaddingH.w,
                          20.h,
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text.rich(
                                TextSpan(
                                  style: AppTypography.headlineLarge.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textBlack,
                                  ),
                                  children: const [
                                    TextSpan(text: 'Welcome to '),
                                    TextSpan(
                                      text: 'Lndry',
                                      style:
                                          TextStyle(color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                              Gap(8.h),
                              Text(
                                'Laundry care at your doorstep.',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Gap(28.h),

                              // Phone input
                              AppTextField(
                                hint: 'Enter your number',
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                fillColor: AppColors.white,
                                borderColor: AppColors.outlineVariant,
                                borderRadius: AppRadius.md,
                                prefixIcon: Padding(
                                  padding:
                                      EdgeInsets.only(left: 16.w, right: 12.w),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '+91',
                                        style:
                                            AppTypography.bodyMedium.copyWith(
                                          color: AppColors.textBlack,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(width: 12.w),
                                      Container(
                                        width: 1,
                                        height: 20.h,
                                        color: AppColors.outlineVariant,
                                      ),
                                    ],
                                  ),
                                ),
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(10),
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                validator: Validators.phone,
                              ),
                              Gap(24.h),

                              AppButton(
                                label: 'Continue',
                                onPressed: _onSendOtp,
                              ),
                              Gap(20.h),

                              // Terms notice
                              Text.rich(
                                TextSpan(
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textMuted,
                                    height: 1.5,
                                  ),
                                  children: const [
                                    TextSpan(
                                        text:
                                            'By continuing, you agree to our '),
                                    TextSpan(
                                      text: 'Terms & Conditions',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(text: ' and '),
                                    TextSpan(
                                      text: 'Privacy Policy.',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
