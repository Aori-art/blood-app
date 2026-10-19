import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shared_design.dart';
import '../verify.dart';
import 'avatar_frame.dart';
import 'streak_controller.dart';
import '../app_palette.dart';

const ColorFilter _kGray = ColorFilter.matrix(<double>[
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);

/// Opens the "Profile Frames" bottom sheet: every frame the server knows
/// about, with the ones you can use, the one in use, and what the rest need.
Future<void> showFrameCatalogSheet(
  BuildContext context, {
  required String initials,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: context.palette.surface,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * 0.85,
  ),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => _FrameCatalogSheet(initials: initials),
);

class _FrameCatalogSheet extends StatefulWidget {
  final String initials;
  const _FrameCatalogSheet({required this.initials});

  @override
  State<_FrameCatalogSheet> createState() => _FrameCatalogSheetState();
}

class _FrameCatalogSheetState extends State<_FrameCatalogSheet> {
  final StreakController _c = StreakController.instance;
  bool _failed = false;

  // The sheet's own messenger. Looking it up from this State's context would
  // find the page's, whose SnackBars hide behind the sheet.
  final GlobalKey<ScaffoldMessengerState> _messenger =
      GlobalKey<ScaffoldMessengerState>();
  // Frame key whose request is running ('' while switching to "No frame").
  String? _busyKey;

  // True while the refresh made when the sheet opened is still running: a
  // frame is never shown as locked from cached data alone.
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (_c.data == null) {
      _load();
    } else {
      _checking = true;
      _recheck();
    }
  }

  // Always ask the server when the sheet opens, so the unlock states are
  // current (e.g. the ID was verified since the cache was saved).
  Future<void> _recheck() async {
    final ok = await _c.refresh();
    if (!mounted) return;
    setState(() => _checking = false);
    if (!ok) _snack("Couldn't check for new frames. Showing what we know.");
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    final ok = await _c.refresh();
    if (!mounted) return;
    setState(() => _failed = !ok && _c.data == null);
  }

  void _snack(String message) {
    if (!mounted) return;
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _use(String? key) async {
    if (_busyKey != null) return;
    setState(() => _busyKey = key ?? '');
    final result = await _c.setFrame(key);
    if (!mounted) return;
    setState(() => _busyKey = null);
    if (!result.ok) {
      _snack(result.message ?? "Couldn't change your frame. Please try again.");
    }
  }

  Future<void> _showRequirement(FrameInfo frame, StreakData data) async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => _RequirementDialog(
        frame: frame,
        data: data,
        initials: widget.initials,
      ),
    );
    if (!mounted) return;
    if (action == 'verify') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const VerifyScreen()));
      if (mounted) _c.refresh();
    } else if (action == 'refresh') {
      _c.refresh();
    }
  }

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    key: _messenger,
    // Its own messenger so error SnackBars appear inside the sheet instead of
    // behind it.
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.palette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Profile Frames',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: context.palette.foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Unlocked frames are free to use anytime.',
                style: TextStyle(fontSize: 12, color: context.palette.muted),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListenableBuilder(
                  listenable: _c,
                  builder: (context, _) {
                    final data = _c.data;
                    if (data == null) return _placeholder();
                    return _grid(data);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _placeholder() {
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: context.palette.muted,
            ),
            const SizedBox(height: 10),
            Text(
              "Couldn't load your frames",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: context.palette.foreground,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 160,
              child: PrimaryButton(label: 'Try Again', onTap: _load),
            ),
          ],
        ),
      );
    }
    return Center(
      child: CircularProgressIndicator(color: context.palette.primaryText),
    );
  }

  Widget _grid(StreakData data) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final extent = 176.0 + 40 * math.max(0.0, textScale - 1);
    final frames = data.frames;
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: extent,
      ),
      itemCount: 1 + frames.length,
      itemBuilder: (context, i) {
        if (i == 0) return _noFrameTile(data);
        return _frameTile(frames[i - 1], data);
      },
    );
  }

  Widget _avatar(double radius) => CircleAvatar(
    radius: radius,
    backgroundColor: kCrimson,
    child: Text(
      widget.initials,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: radius * 0.72,
      ),
    ),
  );

  Widget _tile({
    required Widget avatar,
    required String label,
    required Widget state,
    required bool equipped,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      decoration: BoxDecoration(
        color: equipped ? context.palette.accentBg : context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: equipped
              ? context.palette.primaryText
              : context.palette.border,
          width: equipped ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: 70, child: Center(child: avatar)),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: context.palette.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: Center(child: state)),
        ],
      ),
    ),
  );

  Widget _equippedLabel() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.check_circle_rounded,
        size: 14,
        color: context.palette.primaryText,
      ),
      SizedBox(width: 4),
      Text(
        'Equipped',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: context.palette.primaryText,
        ),
      ),
    ],
  );

  Widget _useButton(String keyId, VoidCallback onTap) {
    final busy = _busyKey == keyId;
    return SizedBox(
      height: 30,
      child: OutlinedButton(
        onPressed: _busyKey != null ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: context.palette.primaryText,
          side: BorderSide(color: context.palette.primaryText, width: 1.3),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        child: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.palette.primaryText,
                ),
              )
            : const Text('Use'),
      ),
    );
  }

  Widget _noFrameTile(StreakData data) {
    final equipped = data.equippedFrame == null;
    return _tile(
      avatar: _avatar(26),
      label: 'No frame',
      equipped: equipped,
      state: equipped ? _equippedLabel() : _useButton('', () => _use(null)),
    );
  }

  String _requirement(FrameInfo f) {
    if (f.isVerifiedFrame) return 'Get your ID verified';
    final days = f.unlockDays;
    return days == null ? 'Keep your streak going' : 'Reach a $days-day streak';
  }

  Widget _frameTile(FrameInfo frame, StreakData data) {
    final equipped = data.equippedFrame == frame.key;
    final unlocked = frame.unlocked;
    final preview = StreakAvatarFrame(
      frameKey: frame.key,
      radius: 26,
      child: _avatar(26),
    );

    if (!unlocked) {
      final checking = _checking;
      return _tile(
        avatar: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: 0.75,
              child: ColorFiltered(colorFilter: _kGray, child: preview),
            ),
            Positioned(
              right: -2,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: context.palette.muted,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        label: frame.label.isEmpty ? frame.key : frame.label,
        equipped: false,
        onTap: checking ? null : () => _showRequirement(frame, data),
        state: checking
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: context.palette.muted,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Checking…',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.palette.muted,
                    ),
                  ),
                ],
              )
            : Text(
                _requirement(frame),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  color: context.palette.muted,
                  height: 1.25,
                ),
              ),
      );
    }

    return _tile(
      avatar: preview,
      label: frame.label.isEmpty ? frame.key : frame.label,
      equipped: equipped,
      state: equipped
          ? _equippedLabel()
          : _useButton(frame.key, () => _use(frame.key)),
    );
  }
}

/// What a locked frame needs, with progress for streak frames.
class _RequirementDialog extends StatefulWidget {
  final FrameInfo frame;
  final StreakData data;
  final String initials;

  const _RequirementDialog({
    required this.frame,
    required this.data,
    required this.initials,
  });

  @override
  State<_RequirementDialog> createState() => _RequirementDialogState();
}

class _RequirementDialogState extends State<_RequirementDialog> {
  @override
  Widget build(BuildContext context) {
    final f = widget.frame;
    final d = widget.data;
    final isVerified = f.isVerifiedFrame;
    final days = f.unlockDays ?? 0;
    // Frames unlock with the best streak, so that is the honest progress.
    final progress = math.max(d.current, d.longest);

    Widget body;
    if (isVerified) {
      body = Text(
        d.isVerified
            ? "Your ID is verified. Pull to refresh and this frame will unlock."
            : 'Get your ID verified to unlock the Verified Donor frame.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: context.palette.muted,
          height: 1.45,
        ),
      );
    } else {
      final value = days <= 0 ? 1.0 : (progress / days).clamp(0.0, 1.0);
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Reach a $days-day streak to unlock it.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: context.palette.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 10,
                color: context.palette.primaryText,
                backgroundColor: context.palette.surfaceAlt,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$progress / $days days',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.palette.foreground,
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Opacity(
            opacity: 0.85,
            child: ColorFiltered(
              colorFilter: _kGray,
              child: StreakAvatarFrame(
                frameKey: f.key,
                radius: 30,
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: kCrimson,
                  child: Text(
                    widget.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 21,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            f.label.isEmpty ? f.key : f.label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: context.palette.foreground,
            ),
          ),
          if (f.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              f.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: context.palette.muted,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          body,
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: TextStyle(color: context.palette.muted)),
        ),
        if (isVerified)
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, d.isVerified ? 'refresh' : 'verify'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kCrimson,
              disabledBackgroundColor: context.palette.border,
              disabledForegroundColor: context.palette.muted,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(d.isVerified ? 'Refresh' : 'Verify now'),
          ),
      ],
    );
  }
}
