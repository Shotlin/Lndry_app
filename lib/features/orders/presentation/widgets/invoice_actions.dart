import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/network/network.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../repositories/repositories.dart';

enum _InvoiceAction { view, download }

/// "View Invoice" / "Download Invoice" for a delivered order.
///
/// This widget contains no invoice logic at all: it asks the backend for the
/// order's invoice (which the backend issues on first request) and opens the
/// link the backend returns. The invoice's numbers, layout and PDF live
/// entirely on the server, so a new invoice design needs no app update.
///
/// [compact] renders two small text links for order-list tiles; otherwise two
/// outlined buttons for the order-details screen.
class InvoiceActions extends ConsumerStatefulWidget {
  const InvoiceActions({required this.orderId, this.compact = false, super.key});

  final String orderId;
  final bool compact;

  @override
  ConsumerState<InvoiceActions> createState() => _InvoiceActionsState();
}

class _InvoiceActionsState extends ConsumerState<InvoiceActions> {
  _InvoiceAction? _busy;

  Future<void> _open(_InvoiceAction action) async {
    if (_busy != null) return;
    setState(() => _busy = action);
    try {
      // Fresh info every time: the links are short-lived and signed.
      final info =
          await ref.read(customerRepositoryProvider).getOrderInvoice(widget.orderId);
      final link =
          action == _InvoiceAction.download ? info.downloadUrl : info.viewUrl;
      final opened = link.isNotEmpty &&
          await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        AppSnackBar.showError(context, 'Could not open the invoice.');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          e is ApiException
              ? e.message
              : 'Could not load the invoice. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      Widget link(String label, _InvoiceAction action) {
        final loading = _busy == action;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _busy == null ? () => _open(action) : null,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 4.h),
            child: loading
                ? SizedBox(
                    width: 14.r,
                    height: 14.r,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    label,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        );
      }

      // Wrap, not Row: on a narrow screen or a large text size the second
      // link drops to the next line instead of overflowing.
      return Wrap(
        spacing: AppSpacing.md.w,
        children: [
          link('View Invoice', _InvoiceAction.view),
          link('Download Invoice', _InvoiceAction.download),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: AppButton.outlined(
            label: 'View Invoice',
            icon: const Icon(AppIcons.document, size: 16),
            isLoading: _busy == _InvoiceAction.view,
            onPressed: _busy == null ? () => _open(_InvoiceAction.view) : null,
          ),
        ),
        Gap(AppSpacing.sm.w),
        Expanded(
          child: AppButton.outlined(
            label: 'Download Invoice',
            icon: const Icon(AppIcons.download, size: 16),
            isLoading: _busy == _InvoiceAction.download,
            onPressed:
                _busy == null ? () => _open(_InvoiceAction.download) : null,
          ),
        ),
      ],
    );
  }
}
