import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../repositories/repositories.dart';

class HelpPage extends ConsumerWidget {
  const HelpPage({super.key});

  Future<void> _callSupport(BuildContext context, WidgetRef ref) async {
    try {
      final contact = await ref.read(customerRepositoryProvider).getSupportContact();
      final phone = contact.phone;
      if (phone == null || phone.isEmpty) {
        if (context.mounted) AppSnackBar.showInfo(context, 'Support number unavailable right now.');
        return;
      }
      final uri = Uri(scheme: 'tel', path: phone);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        AppSnackBar.showInfo(context, 'Could not open the phone dialer.');
      }
    } catch (_) {
      if (context.mounted) AppSnackBar.showInfo(context, 'Failed to fetch support contact.');
    }
  }

  Future<void> _emailSupport(BuildContext context, WidgetRef ref) async {
    try {
      final contact = await ref.read(customerRepositoryProvider).getSupportContact();
      final email = contact.email;
      if (email == null || email.isEmpty) {
        if (context.mounted) AppSnackBar.showInfo(context, 'Support email unavailable right now.');
        return;
      }
      final uri = Uri(scheme: 'mailto', path: email);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        AppSnackBar.showInfo(context, 'Could not open an email app.');
      }
    } catch (_) {
      if (context.mounted) AppSnackBar.showInfo(context, 'Failed to fetch support contact.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final List<_FaqItem> faqs = const [
      _FaqItem(
        q: 'What is the turnaround time for delivery?',
        a: 'Most of our laundry vendors return clothes clean, folded, and ironed within 24 to 48 hours. Estimated delivery dates are shown on your order tracking timeline.',
      ),
      _FaqItem(
        q: 'How do I pay for my order?',
        a: 'LNDRY supports completely secure cashless payments using our built-in Razorpay gateway. You can pay via UPI (GPay, Paytm), Cards, Net Banking, or choose Cash on Delivery.',
      ),
      _FaqItem(
        q: 'Can I cancel my scheduled pickup?',
        a: 'Yes. Pickups can be cancelled free of charge at any time before the delivery partner is dispatched. Tap on your order details and click Cancel.',
      ),
      _FaqItem(
        q: 'What if my clothes are damaged?',
        a: 'We select only certified laundry partners. In case of any dispute or rare garment damage, contact our help support details below, and we will compensate you.',
      ),
    ];

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text('Help & FAQs', style: AppTypography.titleLarge),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          onPressed: () => context.go(AppRoutes.profile),
        ),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.pagePaddingH.w,
            vertical: AppSpacing.pagePaddingV.h,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Contact details header
              AppCard.outlined(
                backgroundColor: AppColors.primaryContainer.withOpacity(0.12),
                borderColor: AppColors.primary.withOpacity(0.3),
                child: Column(
                  children: [
                    Icon(AppIcons.info, color: AppColors.primary, size: 28.r),
                    const Gap(12),
                    Text('Need immediate help?',
                        style: AppTypography.titleMedium),
                    const Gap(6),
                    Text(
                      'Contact LNDRY Support via Phone or Email. Operating 9:00 AM to 8:00 PM daily.',
                      style: AppTypography.caption,
                      textAlign: TextAlign.center,
                    ),
                    const Gap(16),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton.outlined(
                            label: 'Call Us',
                            icon: const Icon(AppIcons.phone, size: 16),
                            onPressed: () => _callSupport(context, ref),
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: AppButton.outlined(
                            label: 'Email Support',
                            icon: const Icon(AppIcons.email, size: 16),
                            onPressed: () => _emailSupport(context, ref),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(24),

              Text('Frequently Asked Questions',
                  style: AppTypography.titleMedium),
              const Gap(12),

              // FAQ Accordions
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: faqs.length,
                separatorBuilder: (_, __) => const Gap(10),
                itemBuilder: (context, idx) {
                  final faq = faqs[idx];

                  return AppCard.outlined(
                    padding: EdgeInsets.zero,
                    child: Material(
                      color: isDark ? AppColors.darkSurface : AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.card.r),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(faq.q, style: AppTypography.labelLarge),
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.h),
                              child: Text(
                                faq.a,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqItem {
  const _FaqItem({required this.q, required this.a});
  final String q;
  final String a;
}
