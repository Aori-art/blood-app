import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'post_comments_api.dart';
import 'shared_design.dart' show kCrimson;

/// What the donor picked in the comment options menu.
enum CommentMenuAction { hide, delete, reported }

class CommentMenuResult {
  final CommentMenuAction action;

  /// For [CommentMenuAction.reported]: 'REPORTED' or 'ALREADY_REPORTED'.
  final String? reportCode;
  const CommentMenuResult(this.action, {this.reportCode});
}

/// The small menu behind the "more" button of a comment: Hide and Report for
/// other donors' comments, Delete for your own. Reporting opens its own sheet
/// on top; when that succeeds both close and the result says so.
Future<CommentMenuResult?> showCommentMenu(
  BuildContext context, {
  required PostComment comment,
  required String donorId,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<CommentMenuResult>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _CommentMenu(comment: comment, donorId: donorId),
  );
}

class _CommentMenu extends StatelessWidget {
  final PostComment comment;
  final String donorId;
  const _CommentMenu({required this.comment, required this.donorId});

  Future<void> _report(BuildContext context) async {
    final code = await showReportSheet(
      context,
      commentId: comment.id,
      donorId: donorId,
    );
    if (code != null && context.mounted) {
      Navigator.of(
        context,
      ).pop(CommentMenuResult(CommentMenuAction.reported, reportCode: code));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),
              if (comment.isMine)
                _item(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete comment',
                  color: kCrimson,
                  onTap: () => Navigator.of(
                    context,
                  ).pop(const CommentMenuResult(CommentMenuAction.delete)),
                )
              else ...[
                _item(
                  icon: Icons.visibility_off_outlined,
                  label: 'Hide comment',
                  color: AppColors.foreground,
                  onTap: () => Navigator.of(
                    context,
                  ).pop(const CommentMenuResult(CommentMenuAction.hide)),
                ),
                _item(
                  icon: Icons.flag_outlined,
                  label: 'Report comment',
                  color: kCrimson,
                  onTap: () => _report(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) => ListTile(
    onTap: onTap,
    leading: Icon(icon, color: color),
    title: Text(
      label,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

// ─── Report ────────────────────────────────────────────────────────────────

const List<(String, String)> _reasons = [
  ('spam', 'Spam'),
  ('harassment', 'Harassment or hate'),
  ('inappropriate', 'Inappropriate content'),
  ('false_information', 'False information'),
  ('other', 'Other'),
];

/// The "Report comment" sheet. Returns 'REPORTED' or 'ALREADY_REPORTED' once
/// the server has taken the report, or null if the donor closed it. Errors
/// show in a SnackBar and leave the sheet open.
Future<String?> showReportSheet(
  BuildContext context, {
  required int commentId,
  required String donorId,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(commentId: commentId, donorId: donorId),
  );
}

class _ReportSheet extends StatefulWidget {
  final int commentId;
  final String donorId;
  const _ReportSheet({required this.commentId, required this.donorId});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final TextEditingController _details = TextEditingController();

  // The sheet's own messenger, so SnackBars appear inside the sheet.
  final GlobalKey<ScaffoldMessengerState> _messenger =
      GlobalKey<ScaffoldMessengerState>();

  String? _reason;
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  void _snack(String message) {
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 13)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(12),
        ),
      );
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() => _sending = true);
    final result = await PostCommentsApi.report(
      commentId: widget.commentId,
      donorId: widget.donorId,
      reason: reason,
      details: _details.text,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (result.ok &&
        (result.code == 'REPORTED' || result.code == 'ALREADY_REPORTED')) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(result.code);
      return;
    }
    if (result.ok) {
      // Accepted, with a code this version doesn't know.
      HapticFeedback.lightImpact();
      Navigator.of(context).pop('REPORTED');
      return;
    }
    _snack(switch (result.code) {
      'CANNOT_REPORT_OWN' =>
        result.message ?? "You can't report your own comment.",
      'COMMENT_NOT_FOUND' =>
        result.message ?? 'This comment is no longer available.',
      _ => result.message ?? "Couldn't send your report. Please try again.",
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final free = constraints.maxHeight - mq.viewInsets.bottom;
        final height = math.min(math.min(mq.size.height * 0.9, 640.0), free);
        return Padding(
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: height,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: ScaffoldMessenger(
                  key: _messenger,
                  child: Scaffold(
                    backgroundColor: Colors.white,
                    resizeToAvoidBottomInset: false,
                    body: _body(),
                    bottomNavigationBar: _footer(mq),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Report comment',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: _sending ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: AppColors.muted),
            ),
          ],
        ),
        const Text(
          'Why are you reporting this comment?',
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        RadioGroup<String>(
          groupValue: _reason,
          onChanged: (v) {
            if (!_sending) setState(() => _reason = v);
          },
          child: Column(
            children: [
              for (final (value, label) in _reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _reason == value
                          ? AppColors.accentBg
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _reason == value ? kCrimson : AppColors.border,
                      ),
                    ),
                    child: RadioListTile<String>(
                      value: value,
                      activeColor: kCrimson,
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      title: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _details,
          enabled: !_sending,
          maxLength: 200,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 14, color: AppColors.foreground),
          decoration: InputDecoration(
            hintText: 'Add details (optional)',
            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
            filled: true,
            fillColor: AppColors.mutedBg,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _footer(MediaQueryData mq) => Material(
    color: Colors.white,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: mq.viewInsets.bottom > 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (_reason == null || _sending) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kCrimson,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.hint,
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit report',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
