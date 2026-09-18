import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../config/env.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/design/premium_type.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../repositories/repositories.dart';
import '../../../../shared/widgets/shared_widgets.dart';
import '../providers/referral_providers.dart';

/// "Refer & Earn" — the customer's own code, live stats, the currently
/// active program's terms in plain language, and a timeline of everyone
/// they've referred. Reachable from Profile → Account Details.
class ReferEarnPage extends ConsumerWidget {
  const ReferEarnPage({super.key});

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    AppSnackBar.showSuccess(
        context, 'Code "$code" copied — share it with a friend!');
  }

  /// The Play Store link carries the code as the install `referrer` value —
  /// Google's own Play Install Referrer mechanism hands that value back to
  /// the app on first launch after a fresh install, so a friend who taps
  /// this link never has to type the code by hand (see
  /// ReferralAttributionService). Manual entry at signup still works too.
  void _share(BuildContext context, String code) {
    SharePlus.instance.share(
      ShareParams(
        text: 'Join me on LNDRY — fresh, doorstep laundry & dry cleaning! '
            'Use my code $code when you sign up and we both earn rewards.\n\n'
            '${Env.playStoreUrl}&referrer=$code',
        subject: 'Get rewards on LNDRY',
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final isDark = theme.brightness == Brightness.dark;
    final summaryAsync = ref.watch(referralSummaryProvider);
    final historyAsync = ref.watch(referralHistoryProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: Padding(
          padding: EdgeInsets.only(left: AppSpacing.sm.w),
          child: _CircleIconButton(
            icon: AppIcons.back,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Image.asset(AssetConstants.logoWordmark, height: 22.h),
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(referralSummaryProvider);
            ref.invalidate(referralHistoryProvider);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(AppSpacing.pagePaddingH.w),
            children: [
              Text(
                'Refer & Earn',
                textAlign: TextAlign.center,
                style: premiumFont(24, weight: FontWeight.w800),
              ),
              Gap(4.h),
              Text(
                'More friends. More laundry, More rewards.',
                textAlign: TextAlign.center,
                style: premiumFont(13,
                    weight: FontWeight.w500, color: AppColors.textSecondary),
              ),
              Gap(AppSpacing.lg.h),
              summaryAsync.when(
                data: (summary) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeroCodeCard(
                      code: summary.referralCode,
                      onCopy: summary.referralCode == null
                          ? null
                          : () => _copyCode(context, summary.referralCode!),
                    ),
                    Gap(AppSpacing.md.h),
                    _StatsStrip(summary: summary),
                    if (summary.activeProgram != null) ...[
                      Gap(AppSpacing.md.h),
                      _TermsCard(program: summary.activeProgram!),
                    ],
                  ],
                ),
                loading: () => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _HeroCodeCard(
                        code: null, onCopy: null, isLoading: true),
                    Gap(AppSpacing.md.h),
                    const _StatsStrip(summary: null),
                  ],
                ),
                error: (_, __) => AppErrorWidget(
                  message: "Couldn't load your referral details.",
                  onRetry: () => ref.invalidate(referralSummaryProvider),
                ),
              ),
              Gap(AppSpacing.sectionGap.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Who You've Referred",
                      style: premiumFont(16, weight: FontWeight.w700)),
                  if (historyAsync.valueOrNull?.isNotEmpty ?? false)
                    Row(
                      children: [
                        Text(
                          'View all',
                          style: premiumFont(13,
                              weight: FontWeight.w700,
                              color: AppColors.primary),
                        ),
                        Icon(AppIcons.forward,
                            size: 13.r, color: AppColors.primary),
                      ],
                    ),
                ],
              ),
              Gap(AppSpacing.cardGap.h),
              historyAsync.when(
                data: (history) => history.isEmpty
                    ? const _EmptyHistoryCard()
                    : Column(
                        children: history
                            .map((item) => Padding(
                                  padding:
                                      EdgeInsets.only(bottom: AppSpacing.sm.h),
                                  child: _ReferralTile(item: item),
                                ))
                            .toList(),
                      ),
                loading: () => Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl.h),
                  child: const Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => AppErrorWidget(
                  message: "Couldn't load your referral history.",
                  onRetry: () => ref.invalidate(referralHistoryProvider),
                ),
              ),
              Gap(AppSpacing.lg.h),
              summaryAsync.maybeWhen(
                data: (summary) => summary.referralCode == null
                    ? const SizedBox.shrink()
                    : _ShareButton(
                        onTap: () => _share(context, summary.referralCode!)),
                orElse: () => const SizedBox.shrink(),
              ),
              Gap(AppSpacing.lg.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _footerLine(isDark),
                  Gap(10.w),
                  Text(
                    'CLEANER CLOTHES. HAPPIER PEOPLE.',
                    style: premiumFont(
                      10,
                      weight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Gap(10.w),
                  _footerLine(isDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerLine(bool isDark) => Container(
        width: 32.w,
        height: 1,
        color: isDark ? AppColors.darkOutlineVariant : AppColors.outlineVariant,
      );
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Material(
      color: isDark ? AppColors.darkSurfaceContainer : AppColors.offerLavender,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(10.r),
          child: Icon(icon, size: 18.r, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _HeroCodeCard extends StatelessWidget {
  const _HeroCodeCard(
      {required this.code, required this.onCopy, this.isLoading = false});

  final String? code;
  final VoidCallback? onCopy;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final cardPad = AppSpacing.cardPadding.w * 1.25;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xxl.r),
        boxShadow: AppElevation.low,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // The illustration is the full card background, edge to edge —
          // not a boxed-in strip beside the text.
          Positioned.fill(
            child: Image.asset(AssetConstants.referEmptyArt, fit: BoxFit.cover),
          ),
          // A soft left-to-right scrim keeps the text legible over the
          // busier parts of the artwork without hiding any of it.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.78),
                    Colors.white.withValues(alpha: 0.15),
                  ],
                  stops: const [0.0, 0.68],
                ),
              ),
            ),
          ),
          Positioned(
            right: 14.w,
            bottom: 14.h,
            child: Text(
              'Good Loads\nTogether',
              textAlign: TextAlign.right,
              style: GoogleFonts.caveat(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.primary.withValues(alpha: 0.8),
                height: 1.05,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(cardPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'INVITE FRIENDS',
                  style: premiumFont(
                    11,
                    weight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 1.4,
                  ),
                ),
                Gap(6.h),
                Text(
                  'Invite friends,\nearn together',
                  style: premiumFont(22, weight: FontWeight.w800, height: 1.15),
                ),
                Gap(8.h),
                Text(
                  'Share LNDRY with your friends and earn exciting rewards!',
                  style: premiumFont(
                    12,
                    weight: FontWeight.w500,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                Gap(AppSpacing.md.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md.w, vertical: AppSpacing.sm.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(AppRadius.lg.r),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Referral Code',
                              style: premiumFont(10.5,
                                  weight: FontWeight.w600,
                                  color: AppColors.textSecondary),
                            ),
                            Gap(2.h),
                            isLoading
                                ? SizedBox(
                                    height: 22.h,
                                    width: 100.w,
                                    child: const LinearProgressIndicator(),
                                  )
                                : Text(
                                    code ?? '—',
                                    style: premiumFont(20,
                                        weight: FontWeight.w800,
                                        letterSpacing: 1.5),
                                  ),
                          ],
                        ),
                      ),
                      if (!isLoading)
                        InkWell(
                          onTap: onCopy,
                          borderRadius: BorderRadius.circular(AppRadius.sm.r),
                          child: Padding(
                            padding: EdgeInsets.all(6.r),
                            child: Icon(AppIcons.copy,
                                size: 20.r, color: AppColors.primary),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isLoading) ...[
                  Gap(8.h),
                  Text(
                    'Tap to copy, then share it with a friend.',
                    style: premiumFont(10.5,
                        weight: FontWeight.w500, color: AppColors.primary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.summary});

  final ReferralSummary? summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.people_alt_rounded,
            label: 'Invited',
            value: summary?.totalReferred,
          ),
        ),
        Gap(AppSpacing.sm.w),
        Expanded(
          child: _StatTile(
            icon: Icons.schedule_rounded,
            label: 'Pending',
            value: summary?.pending,
          ),
        ),
        Gap(AppSpacing.sm.w),
        Expanded(
          child: _StatTile(
            icon: AppIcons.success,
            label: 'Completed',
            value: summary?.completed,
            filled: true,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final int? value;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceContainer : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg.r),
        border: Border.all(
          color:
              isDark ? AppColors.darkOutlineVariant : AppColors.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 36.r,
            height: 36.r,
            decoration: BoxDecoration(
              color: filled ? AppColors.primary : AppColors.offerLavender,
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 18.r, color: filled ? Colors.white : AppColors.primary),
          ),
          Gap(8.h),
          Text(
            value?.toString() ?? '—',
            style: premiumFont(19, weight: FontWeight.w800),
          ),
          Gap(2.h),
          Text(
            label,
            style: premiumFont(11,
                weight: FontWeight.w500, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _TermsCard extends StatelessWidget {
  const _TermsCard({required this.program});

  final ReferralActiveProgram program;

  String _rewardLabel(String type, double? amount, int? count) {
    switch (type) {
      case 'WALLET_CREDIT':
        return '₹${amount?.toStringAsFixed(0) ?? '0'} in your wallet';
      case 'FREE_EXPRESS_DELIVERY':
        return '${count ?? 1} free express ${(count ?? 1) > 1 ? 'deliveries' : 'delivery'}';
      case 'FREE_STANDARD_DELIVERY':
        return '${count ?? 1} free ${(count ?? 1) > 1 ? 'deliveries' : 'delivery'}';
      case 'COUPON_UNLOCK':
        return 'a bonus coupon';
      default:
        return 'a reward';
    }
  }

  @override
  Widget build(BuildContext context) {
    final referrerReward = _rewardLabel(program.referrerRewardType,
        program.referrerRewardAmount, program.referrerRewardCount);
    final refereeReward = _rewardLabel(program.refereeRewardType,
        program.refereeRewardAmount, program.refereeRewardCount);

    return Container(
      padding: EdgeInsets.all(AppSpacing.md.w),
      decoration: BoxDecoration(
        color: AppColors.offerLavender.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.lg.r),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.celebration_rounded,
                  color: AppColors.primary, size: 20.r),
              Gap(AppSpacing.sm.w),
              Expanded(
                child: Text(program.name,
                    style: premiumFont(14, weight: FontWeight.w800)),
              ),
            ],
          ),
          Gap(AppSpacing.sm.h),
          Text(
            'You get $referrerReward — your friend gets $refereeReward, once they complete their first order.',
            style: premiumFont(12,
                weight: FontWeight.w500,
                color: AppColors.textBlack,
                height: 1.4),
          ),
          if (program.termsText != null &&
              program.termsText!.trim().isNotEmpty) ...[
            Gap(AppSpacing.sm.h),
            Text(
              program.termsText!,
              style: premiumFont(10.5,
                  weight: FontWeight.w400, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard();

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceContainer
            : AppColors.offerLavender.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.lg.r),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 700 / 394,
            child: Image.asset(
              AssetConstants.referHeroArt,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
                vertical: AppSpacing.lg.h, horizontal: AppSpacing.lg.w),
            child: Column(
              children: [
                Text('No referrals yet',
                    style: premiumFont(15, weight: FontWeight.w800)),
                Gap(4.h),
                Text(
                  "Share your code above — you'll see everyone you've referred here.",
                  textAlign: TextAlign.center,
                  style: premiumFont(12,
                      weight: FontWeight.w500,
                      color: AppColors.textSecondary,
                      height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(AppRadius.button.r),
          boxShadow: AppElevation.low,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.button.r),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.button.r),
            onTap: onTap,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.share, color: Colors.white, size: 18.r),
                  Gap(10.w),
                  Text(
                    'Share & Earn More',
                    style: premiumFont(15,
                        weight: FontWeight.w700, color: Colors.white),
                  ),
                  Gap(10.w),
                  Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 18.r),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferralTile extends StatelessWidget {
  const _ReferralTile({required this.item});

  final ReferralHistoryItem item;

  ({String label, Color color}) get _timelineStatus {
    if (item.referrerRewardStatus == 'GRANTED') {
      return (label: 'Reward earned', color: AppColors.success);
    }
    if (item.status == 'COMPLETED') {
      return (label: 'Order completed', color: AppColors.textSecondary);
    }
    return (label: 'Waiting for first order', color: AppColors.warning);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final status = _timelineStatus;

    return AppCard.outlined(
      backgroundColor:
          isDark ? AppColors.darkSurfaceContainer : AppColors.surface,
      child: Row(
        children: [
          Container(
            width: 40.r,
            height: 40.r,
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.profile, size: 20.r, color: AppColors.primary),
          ),
          Gap(AppSpacing.cardGap.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.refereeName ?? 'A friend',
                  style: premiumFont(14, weight: FontWeight.w700),
                ),
                if (item.refereePhoneMasked != null) ...[
                  Gap(2.h),
                  Text(
                    item.refereePhoneMasked!,
                    style: premiumFont(11,
                        weight: FontWeight.w400,
                        color: AppColors.textSecondary),
                  ),
                ],
                Gap(2.h),
                Text(
                  'Invited ${item.refereeSignedUpAt.toDayDate}',
                  style: premiumFont(10.5,
                      weight: FontWeight.w400, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          StatusBadge(label: status.label, color: status.color),
        ],
      ),
    );
  }
}
