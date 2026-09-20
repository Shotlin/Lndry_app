import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import '../../../../core/auth/auth_gate.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_otp_input.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../config/env.dart';
import '../../../../core/network/friendly_error.dart';

class OtpPage extends ConsumerStatefulWidget {
  const OtpPage({super.key});

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage> {
  String _otpCode = '';
  bool _isLoading = false;
  String? _errorText;
  int _timerSeconds = 0;
  bool _canResend = false;
  Timer? _resendTimer;

  // Cached values from the OtpSent state so we can restore after an error.
  String _cachedPhone = '';
  String _cachedChallengeId = '';
  String? _cachedDevOtp;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    if (Env.shouldAutoFillOtp) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          _onVerify();
        }
      });
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _timerSeconds = 30;
      _canResend = false;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _timerSeconds--;
        if (_timerSeconds <= 0) {
          _timerSeconds = 0;
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _onVerify() async {
    if (_otpCode.length != 6) {
      setState(
          () => _errorText = 'Please enter the complete 6-digit verification code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    await ref.read(authProvider.notifier).verifyOtp(_otpCode);

    if (!mounted) return;

    final authState = ref.read(authProvider);
    if (authState is AuthError) {
      // Show error in-place; restore OtpSent so user can retry.
      setState(() {
        _isLoading = false;
        _errorText = authState.message;
      });
      // Restore OTP state so the user doesn't get stuck.
      ref.read(authProvider.notifier).restoreOtpState(
            _cachedPhone,
            _cachedChallengeId,
            devOtp: _cachedDevOtp,
          );
    } else {
      setState(() => _isLoading = false);
      if (authState is AuthNeedsProfileSetup) {
        context.push(AppRoutes.profileSetup);
      }
      // AuthAuthenticated -> the router's global redirect sends the user to
      // Home automatically; no explicit navigation needed here.
    }
  }

  Future<void> _onResend() async {
    if (!_canResend) return;
    final authState = ref.read(authProvider);
    if (authState is! AuthOtpSent) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).sendOtp(authState.phone);
      _startResendTimer();
      if (mounted)
        AppSnackBar.showSuccess(
            context, 'A new verification code has been sent.');
    } catch (e) {
      if (mounted) AppSnackBar.showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onBack(BuildContext context) {
    // Cancel OTP flow and return to login.
    ref.read(authProvider.notifier).clearError();
    if (context.mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        context.go(loginLocation(
          returnTo: returnToFrom(context) ?? AppRoutes.home,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Cache phone/challengeId for error recovery.
    if (authState is AuthOtpSent) {
      _cachedPhone = authState.phone;
      _cachedChallengeId = authState.challengeId;
      _cachedDevOtp = authState.devOtp;
    }

    final phone = _cachedPhone;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const AppLoadingPage(message: 'Verifying code...')
          : Stack(
              children: [
                // Full-bleed background artwork (logo + tagline baked in).
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/onboarding/otp_screen.png',
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
                      maxHeight: MediaQuery.of(context).size.height * 0.68,
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
                          TextSpan(text: 'Verify your '),
                          TextSpan(
                            text: 'number',
                            style: TextStyle(color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                    const Gap(12),
                    Text(
                      phone.isNotEmpty
                          ? 'We sent a verification code to +91 $phone'
                          : 'Enter the verification code sent to your number.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const Gap(32),

                    // Dev-only: the backend echoes back the generated OTP
                    // whenever it's not actually wired to a live SMS
                    // provider (local/dev environments). Surface it here so
                    // the code can be read off-screen and typed in below,
                    // instead of waiting on an SMS that will never arrive.
                    // Disappears automatically once a real SMS provider is
                    // configured server-side, since the backend then stops
                    // sending this field.
                    if (_cachedDevOtp != null && _cachedDevOtp!.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 12.h),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(AppRadius.md.r),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(AppIcons.info,
                                color: AppColors.primary, size: 20.r),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  style: AppTypography.bodyMedium
                                      .copyWith(color: AppColors.textBlack),
                                  children: [
                                    const TextSpan(text: 'Demo OTP: '),
                                    TextSpan(
                                      text: _cachedDevOtp,
                                      style: AppTypography.bodyMedium.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Gap(20),
                    ],

                    AppOtpInput(
                      length: AppConstants.otpLength,
                      initialValue: Env.shouldAutoFillOtp ? _cachedDevOtp : null,
                      errorText: _errorText,
                      onChanged: (val) => setState(() {
                        _otpCode = val;
                        _errorText = null;
                      }),
                      onCompleted: (val) {
                        _otpCode = val;
                        _onVerify();
                      },
                    ),
                    const Gap(40),

                    // Resend row
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          "Didn't receive the code? ",
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (_canResend)
                          GestureDetector(
                            onTap: _onResend,
                            child: Text(
                              'Resend OTP',
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else
                          Text(
                            'Resend in ${_timerSeconds.toString().padLeft(2, '0')}s',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    const Gap(32),

                    AppButton(
                      label: 'Verify OTP',
                      isDisabled: _otpCode.length != 6,
                      onPressed: _onVerify,
                    ),
                    Gap(16.h),
                    Center(
                      child: GestureDetector(
                        onTap: () => _onBack(context),
                        child: Text(
                          'Change number',
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
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
