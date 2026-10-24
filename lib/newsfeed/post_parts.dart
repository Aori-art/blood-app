// The building blocks of a post card: the type chip, the event date tile
// and info panel, the urgent band, the milestone band, clamped text, the
// post image, the Donate Now button and the action pills.
//
// Only looks: what happens on a tap is passed in by the card.
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_palette.dart';
import '../skeleton.dart';
import '../widgets/glow_pulse.dart';
import 'feed_chrome.dart' show PulsingDot;
import 'post_content_parser.dart';

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ── Type chip ───────────────────────────────────────────────────────────────

/// A small uppercase label for the kind of post ("EVENT", "URGENT", ...).
class PostTypeChip extends StatelessWidget {
  const PostTypeChip({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: foreground,
        ),
      ),
    );
  }
}

// ── Event: date tile, status, info panel, note ──────────────────────────────

const _months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

final _monthDay = RegExp(
  r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})\b',
  caseSensitive: false,
);

/// "OCT" and "12" from "Mon, October 12, 2026" or "2026-10-12"; null when
/// the text has no recognisable date.
({String month, String day})? dateParts(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final iso = DateTime.tryParse(raw.trim());
  if (iso != null) {
    return (month: _months[iso.month - 1], day: '${iso.day}');
  }
  final m = _monthDay.firstMatch(raw);
  if (m == null) return null;
  return (month: m.group(1)!.toUpperCase(), day: m.group(2)!);
}

/// The calendar tile beside an event's title: month over day.
class EventDateTile extends StatelessWidget {
  const EventDateTile({super.key, required this.date});

  /// The date text; when it can't be read the tile shows an event icon.
  final String? date;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final parts = dateParts(date);
    return ExcludeSemantics(
      child: Container(
        width: 56,
        height: 64,
        decoration: BoxDecoration(
          color: p.accentBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.primaryBorder),
        ),
        child: parts == null
            ? Icon(Icons.event_rounded, color: p.primaryText, size: 26)
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      parts.month,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: p.primaryText,
                      ),
                    ),
                    Text(
                      parts.day,
                      style: TextStyle(
                        fontSize: 24,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        color: p.foreground,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// "Open" in green; anything else ("Closed", "Full") in gray.
class EventStatusChip extends StatelessWidget {
  const EventStatusChip({super.key, required this.status});

  final String status;

  bool get isOpen => status.toLowerCase().contains('open');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = isOpen ? p.successDark : p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: isOpen ? p.successBg : p.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: isOpen ? p.successBorder : p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isOpen ? p.success : p.muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The labelled rows of an event (date, time, place, ...), on a soft panel.
class EventInfoPanel extends StatelessWidget {
  const EventInfoPanel({super.key, required this.rows});

  final List<InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _InfoRowView(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _InfoRowView extends StatelessWidget {
  const _InfoRowView({required this.row});

  final InfoRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (IconData icon, Color bg, Color fg) = switch (row.kind) {
      InfoKind.date => (
        Icons.calendar_today_rounded,
        p.accentBg,
        p.primaryText,
      ),
      InfoKind.time => (Icons.schedule_rounded, p.infoBg, p.infoText),
      InfoKind.location => (Icons.place_rounded, p.successBg, p.successDark),
      InfoKind.address => (Icons.map_outlined, p.successBg, p.successDark),
      InfoKind.capacity => (Icons.groups_rounded, p.warningBg, p.warningText),
      _ => (Icons.info_outline_rounded, p.surface, p.muted),
    };
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: TextStyle(fontSize: 11, color: p.muted, height: 1.2),
                ),
                const SizedBox(height: 1),
                Text(
                  row.value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: p.foreground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The free text under an event's details, set off by a brand bar.
class PostNote extends StatelessWidget {
  const PostNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline_rounded, size: 16, color: p.muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ExpandableText(
              text,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: p.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Long text ───────────────────────────────────────────────────────────────

/// Text that shows [maxLines] lines with "Read more" when it is longer.
class ExpandableText extends StatefulWidget {
  const ExpandableText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 6,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();

        final text = Text(
          widget.text,
          style: style,
          maxLines: long && !_expanded ? widget.maxLines : null,
          overflow: long && !_expanded ? TextOverflow.ellipsis : null,
        );
        if (!long) return text;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: _reduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: text,
            ),
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                foregroundColor: context.palette.primaryText,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(48, 48),
                textStyle: DefaultTextStyle.of(context).style.merge(
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              child: Text(_expanded ? 'Show less' : 'Read more'),
            ),
          ],
        );
      },
    );
  }
}

// ── Urgent ──────────────────────────────────────────────────────────────────

/// The red strip across the top of an urgent post.
class UrgentBand extends StatelessWidget {
  const UrgentBand({super.key, this.level});

  /// "CRITICAL" or "HIGH", shown at the right; null for none.
  final String? level;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
      color: Colors.white,
    );
    return Container(
      width: double.infinity,
      color: AppColors.critical,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const PulsingDot(color: Colors.white, size: 7),
          const SizedBox(width: 6),
          const Expanded(child: Text('URGENT NEED', style: style)),
          if (level != null) Text(level!, style: style),
        ],
      ),
    );
  }
}

/// The blood type an urgent post asks for, and the hospital.
class UrgentNeedRow extends StatelessWidget {
  const UrgentNeedRow({super.key, this.bloodType, this.hospital});

  final String? bloodType;
  final String? hospital;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tint = AppColors.critical.withValues(alpha: p.isDark ? 0.18 : 0.08);
    final type = bloodType;
    final place = hospital;
    return Row(
      children: [
        if (type != null)
          Container(
            constraints: const BoxConstraints(minWidth: 64, minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.critical.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  type,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    color: p.criticalText,
                  ),
                ),
                Text(
                  'NEEDED',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: p.criticalText,
                  ),
                ),
              ],
            ),
          ),
        if (type != null) const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type != null ? 'Blood type needed' : 'Needed at',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
              if (place != null) ...[
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.local_hospital_rounded,
                        size: 16,
                        color: p.primaryText,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        place,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: p.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Milestone ───────────────────────────────────────────────────────────────

/// A gold band with a trophy for milestone posts; [headline] is the post's
/// first line.
class MilestoneBand extends StatelessWidget {
  const MilestoneBand({super.key, required this.headline});

  final String headline;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.warningBorder),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            p.warningBg,
            Color.lerp(p.warningBg, p.warning, p.isDark ? 0.16 : 0.2)!,
          ],
        ),
      ),
      child: CustomPaint(
        painter: const _ConfettiDots(),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.warningBorder),
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  size: 22,
                  color: p.warningText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: p.foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A few still confetti dots in the band's corners.
class _ConfettiDots extends CustomPainter {
  const _ConfettiDots();

  static const _dots = [
    // Along the top and bottom edges, clear of the headline.
    (0.80, 0.09, 3.0, AppColors.warning),
    (0.97, 0.30, 2.0, AppColors.primary),
    (0.72, 0.92, 2.5, AppColors.info),
    (0.93, 0.88, 2.0, AppColors.warning),
    (0.60, 0.07, 2.0, AppColors.primary),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (x, y, r, color) in _dots) {
      canvas.drawCircle(
        Offset(size.width * x, size.height * y),
        r,
        Paint()..color = color.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_ConfettiDots oldDelegate) => false;
}

// ── Image ───────────────────────────────────────────────────────────────────

/// A post's photo: 16:9, rounded, decoded at the size it is shown. A tap
/// opens it; a double tap calls [onDoubleTap] and pops a heart.
class PostImage extends StatefulWidget {
  const PostImage({
    super.key,
    required this.url,
    required this.heroTag,
    required this.onOpen,
    required this.onDoubleTap,
  });

  final String url;
  final String heroTag;
  final VoidCallback onOpen;
  final VoidCallback onDoubleTap;

  @override
  State<PostImage> createState() => _PostImageState();
}

class _PostImageState extends State<PostImage>
    with SingleTickerProviderStateMixin {
  AnimationController? _pop;

  void _doubleTap() {
    widget.onDoubleTap();
    if (_reduceMotion(context)) return;
    if (_pop == null) {
      // Made on the first double tap; only the heart rebuilds while it runs.
      setState(() {
        _pop = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 750),
        );
      });
    }
    _pop!.forward(from: 0);
  }

  @override
  void dispose() {
    _pop?.dispose();
    super.dispose();
  }

  Widget _heart() {
    final pop = _pop;
    if (pop == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: pop,
      builder: (context, child) {
        final t = pop.value;
        if (t == 0 || t == 1) return const SizedBox.shrink();
        final scale = t < 0.3
            ? Curves.easeOutBack.transform(t / 0.3) * 1.15
            : t < 0.45
            ? 1.15 - 0.15 * ((t - 0.3) / 0.15)
            : 1.0;
        final opacity = t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3;
        return Center(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: const Icon(
        Icons.favorite_rounded,
        size: 88,
        color: Colors.white,
        shadows: [Shadow(color: Colors.black38, blurRadius: 16)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round()
            : null;
        return Semantics(
          button: true,
          label: 'Post photo. Opens full screen',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: widget.onOpen,
            onDoubleTap: _doubleTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: widget.heroTag,
                      child: Image.network(
                        widget.url,
                        fit: BoxFit.cover,
                        cacheWidth: cacheWidth,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : SkeletonPulse(
                                child: ColoredBox(color: p.surfaceAlt),
                              ),
                        errorBuilder: (context, _, _) => ColoredBox(
                          color: p.surfaceAlt,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: p.muted,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                    // A soft shade at the bottom so the photo sits on the card.
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 56,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x00000000), Color(0x33000000)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(child: _heart()),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Donate Now ──────────────────────────────────────────────────────────────

/// The full-width brand button. [glow] adds the pulsing halo and sheen.
class DonateNowButton extends StatefulWidget {
  const DonateNowButton({
    super.key,
    required this.onPressed,
    this.glow = false,
  });

  final VoidCallback onPressed;
  final bool glow;

  @override
  State<DonateNowButton> createState() => _DonateNowButtonState();
}

class _DonateNowButtonState extends State<DonateNowButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(16));
    final button = AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: _reduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: const BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.primaryGradient,
            ),
          ),
          child: InkWell(
            onTap: widget.onPressed,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: radius,
            child: const SizedBox(
              width: double.infinity,
              height: 52,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.water_drop, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Donate Now',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!widget.glow) return button;
    return GlowPulse(borderRadius: radius, sheen: true, child: button);
  }
}

// ── Action pills ────────────────────────────────────────────────────────────

/// One of the three equal pills under a post: 44 px tall inside a 48 px
/// touch target, scaling a little while pressed.
class ActionPill extends StatefulWidget {
  const ActionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.active = false,
    this.toggled,
    this.iconScale = 1,
  });

  final IconData icon;

  /// What the pill shows, count included ("Like 2").
  final String label;
  final String semanticLabel;

  /// Gets the pill's own context (the share sheet opens from it).
  final void Function(BuildContext pillContext) onTap;

  /// Filled with the brand tint (a liked post).
  final bool active;
  final bool? toggled;
  final double iconScale;

  @override
  State<ActionPill> createState() => _ActionPillState();
}

class _ActionPillState extends State<ActionPill> {
  bool _pressed = false;

  void _press(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final reduce = _reduceMotion(context);
    final fg = widget.active ? p.primaryText : p.foreground;
    return Semantics(
      button: true,
      toggled: widget.toggled,
      label: widget.semanticLabel,
      onTap: () => widget.onTap(context),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: () => widget.onTap(context),
        child: SizedBox(
          height: 48,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.97 : 1,
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 100),
              child: AnimatedContainer(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: widget.active ? p.accentBg : p.surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedScale(
                          scale: widget.iconScale,
                          duration: const Duration(milliseconds: 125),
                          curve: Curves.easeOut,
                          child: Icon(
                            widget.icon,
                            size: 18,
                            color: widget.active ? p.primaryText : p.muted,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          widget.label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
