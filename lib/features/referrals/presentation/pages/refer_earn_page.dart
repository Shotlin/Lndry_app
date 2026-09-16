import 'package:flutter/services.dart';

import '../../../../core/design/design_system.dart';
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
    AppSnackBar.showSuccess(context, 'Code "$code" copied — share it with a friend!');
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
        title: Text('Refer & Earn', style: AppTypography.titleLarge),
        centerTitle: true,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
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
                    const _HeroCodeCard(code: null, onCopy: null, isLoading: true),
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
              Text('Who You\'ve Referred', style: AppTypography.titleMedium),
              Gap(AppSpacing.cardGap.h),
              historyAsync.when(
                data: (history) => history.isEmpty
                    ? const AppEmptyState(
                        icon: AppIcons.gift,
                        title: 'No referrals yet',
                        subtitle: 'Share your code above — you\'ll see everyone you\'ve referred here.',
                      )
                    : Column(
                        children: history
                            .map((item) => Padding(
                                  padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCodeCard extends StatelessWidget {
  const _HeroCodeCard({required this.code, required this.onCopy, this.isLoading = false});

  final String? code;
  final VoidCallback? onCopy;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.cardPadding.w * 1.25),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.card.r),
        boxShadow: AppElevation.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.gift, color: Colors.white, size: 20.r),
              Gap(8.w),
              Text(
                'Invite friends, earn together',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Gap(16.h),
          Text(
            'Your Referral Code',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          Gap(6.h),
          isLoading
              ? SizedBox(
                  height: 34.h,
                  width: 140.w,
                  child: const LinearProgressIndicator(color: Colors.white24),
                )
              : GestureDetector(
                  onTap: onCopy,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadius.input.r),
                      border: Border.all(color: Colors.white38),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          code ?? '—',
                          style: AppTypography.headlineSmall.copyWith(
                            color: Colors.white,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Gap(10.w),
                        Icon(AppIcons.copy, size: 18.r, color: Colors.white),
                      ],
                    ),
                  ),
                ),
          Gap(10.h),
          Text(
            'Tap to copy, then share it with a friend.',
            style: AppTypography.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
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
        Expanded(child: _StatTile(label: 'Invited', value: summary?.totalReferred)),
        Gap(AppSpacing.sm.w),
        Expanded(child: _StatTile(label: 'Pending', value: summary?.pending)),
        Gap(AppSpacing.sm.w),
        Expanded(child: _StatTile(label: 'Completed', value: summary?.completed)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    return AppCard.outlined(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm.h, horizontal: AppSpacing.sm.w),
      child: Column(
        children: [
          Text(
            value?.toString() ?? '—',
            style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
          ),
          Gap(2.h),
          Text(
            label,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
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
    final referrerReward =
        _rewardLabel(program.referrerRewardType, program.referrerRewardAmount, program.referrerRewardCount);
    final refereeReward =
        _rewardLabel(program.refereeRewardType, program.refereeRewardAmount, program.refereeRewardCount);

    return AppCard.outlined(
      backgroundColor: AppColors.offerLavender.withValues(alpha: 0.5),
      borderColor: AppColors.primary.withValues(alpha: 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.celebration_rounded, color: AppColors.primary, size: 22.r),
              Gap(AppSpacing.sm.w),
              Expanded(
                child: Text(
                  program.name,
                  style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Gap(AppSpacing.sm.h),
          Text(
            'You get $referrerReward — your friend gets $refereeReward, once they complete their first order.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textBlack, height: 1.4),
          ),
          if (program.termsText != null && program.termsText!.trim().isNotEmpty) ...[
            Gap(AppSpacing.sm.h),
            Text(
              program.termsText!,
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
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
      backgroundColor: isDark ? AppColors.darkSurfaceContainer : AppColors.surface,
      child: Row(
        children: [
          Container(
            width: 40.r,
            height: 40.r,
            decoration: BoxDecoration(
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
                  style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                if (item.refereePhoneMasked != null) ...[
                  Gap(2.h),
                  Text(
                    item.refereePhoneMasked!,
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ],
                Gap(2.h),
                Text(
                  'Invited ${item.refereeSignedUpAt.toDayDate}',
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
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
