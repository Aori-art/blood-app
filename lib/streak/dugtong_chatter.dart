import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dugtong.dart';
import 'streak_controller.dart';
import '../app_palette.dart';

/// What a line can be filled in with.
class _Ctx {
  final int n;
  final int longest;
  final int? remaining;
  final String? label;
  final String stage;
  final bool freeze;
  final bool verified;
  final int hour;

  const _Ctx({
    required this.n,
    required this.longest,
    required this.remaining,
    required this.label,
    required this.stage,
    required this.freeze,
    required this.verified,
    required this.hour,
  });
}

class _Line {
  final String text;
  final bool Function(_Ctx c)? when;
  const _Line(this.text, [this.when]);
}

class _Pool {
  final String name;
  final int weight;
  final List<_Line> lines;
  const _Pool(this.name, this.weight, this.lines);
}

bool _morning(_Ctx c) => c.hour >= 5 && c.hour < 12;
bool _afternoon(_Ctx c) => c.hour >= 12 && c.hour < 18;
bool _evening(_Ctx c) => c.hour >= 18 && c.hour < 22;
bool _lateNight(_Ctx c) => c.hour >= 22 || c.hour < 5;

final List<_Pool> _pools = [
  _Pool('greeting', 1, [
    _Line('Good morning! Ready to save lives today?', _morning),
    _Line('Rise and shine! Today is a great day to be a hero.', _morning),
    _Line('Morning! A healthy breakfast makes a happy donor.', _morning),
    _Line('Hi there! Thanks for dropping by.', _afternoon),
    _Line('Good afternoon! Hope your day is going well.', _afternoon),
    _Line("Afternoon check-in! You're doing great.", _afternoon),
    _Line("Good evening! You're doing great.", _evening),
    _Line('Evening! Thanks for showing up today.', _evening),
    _Line("Winding down? Don't forget to drink some water.", _evening),
    _Line('Still up? Rest well, heroes need sleep too.', _lateNight),
    _Line('Late night! A good sleep keeps heroes strong.', _lateNight),
    _Line("Night owl! Don't forget to rest.", _lateNight),
  ]),
  _Pool('streak', 3, [
    _Line('Day {n}! Keep it going!', (c) => c.n > 0),
    _Line("{n} days in a row. I'm so proud of you!", (c) => c.n > 1),
    _Line(
      'Only {remaining} more days until the {label}!',
      (c) => c.remaining != null && c.remaining! > 1 && c.label != null,
    ),
    _Line(
      'Just 1 more day until the {label}!',
      (c) => c.remaining == 1 && c.label != null,
    ),
    _Line(
      'Your best is {longest} days. Can you beat it?',
      (c) => c.longest > c.n && c.longest > 0,
    ),
    _Line(
      "You're on your best streak ever: {longest} days!",
      (c) => c.longest > 0 && c.longest == c.n,
    ),
    _Line('My Streak Freeze has your back if you miss a day.', (c) => c.freeze),
    _Line('Right now I am {stage}. Keep climbing!', (c) => c.n > 0),
    _Line('Every day you open the app, I get stronger.', (c) => c.n > 0),
    _Line('Open eDonate every day and watch me evolve!'),
    _Line(
      "I'm a little sleepy... let's start a new streak today!",
      (c) => c.n == 0,
    ),
    _Line('A new streak starts with a single day. Today?', (c) => c.n == 0),
  ]),
  _Pool('facts', 2, [
    _Line('One donation can help save up to 3 lives.'),
    _Line('Healthy adults can usually donate about every 3 months.'),
    _Line('Eat a healthy meal and drink water before you donate.'),
    _Line(
      'Your donation center does a final health check before every donation.',
    ),
    _Line('Every drop counts. Every life matters.'),
    _Line("Blood can't be made in a lab. Only donors can give it."),
    _Line('Donated blood is tested before it reaches a patient.'),
    _Line('Your blood type matters. Keep your profile up to date!'),
  ]),
  _Pool('tips', 3, [
    _Line('Tap me to see your streak!'),
    _Line('Drag me anywhere you like.'),
    _Line('Have you checked your eligibility lately? Open the Check tab.'),
    _Line('Need a slot? Try the Book tab.'),
    _Line(
      'Long-press me to hide me. Bring me back in Streak > Streak settings.',
    ),
    _Line('You can change your profile frame from your profile page.'),
    _Line('Frames are cosmetic, but they look great on your profile!'),
    _Line(
      'Verify your ID to unlock the Verified Donor frame!',
      (c) => !c.verified,
    ),
  ]),
];

/// Lines about the screen the donor is on, keyed by StreakScreen id. Screens
/// without an entry (and 'generic') use the everyday pools above.
const Map<String, List<_Line>> _screenPools = {
  'newsfeed': [
    _Line(
      'Scrolling can potentially save lives. Someone may need your blood type '
      'today!',
    ),
    _Line('Spot an urgent request? Share it with a friend.'),
    _Line('Verified donors can tap Donate Now on donation posts.'),
    _Line('Like the posts that inspire you!'),
  ],
  'home': [
    _Line("Welcome back! Here's your donation summary."),
    _Line('Check your next eligible date here.'),
    _Line('Your streak is shown on me. Tap me for the ladder.'),
    _Line('Everything you need to donate is one tap away.'),
  ],
  'book': [
    _Line('Pick a date and time that works for you.'),
    _Line('Arrive a few minutes early at the donation center.'),
    _Line('Eat a healthy meal and drink water first.'),
    _Line('Booked a slot? Your ticket will show up right here.'),
  ],
  'check': [
    _Line('Answer honestly. It keeps donors and patients safe.'),
    _Line("Take your time, there's no rush."),
    _Line("You can retake the check when you're eligible again."),
    _Line('This quick check makes sure donating is safe for you.'),
  ],
  'donation_history': [
    _Line('Every donation here helped someone. Thank you!'),
    _Line('Each donation can help save up to 3 lives.'),
    _Line('Look at all those lifesaving moments!'),
    _Line('Your donation history is a record of heroism.'),
  ],
  'alerts': [
    _Line('Notifications keep you updated on your appointments.'),
    _Line('Swipe a notification to delete it.'),
    _Line('Urgent blood requests near you show up here too.'),
    _Line('All caught up? Great, you are on top of things!'),
  ],
  'profile': [
    _Line('Looking good! Tap Edit Frame to dress up your photo.'),
    _Line('Keep your contact details updated so we can reach you.'),
    _Line('Your profile is your donor identity. Keep it fresh!'),
    _Line('Frames unlock as your streak grows.'),
  ],
  'edit_profile': [
    _Line(
      'Update your address or number here. Edits are limited to once every '
      '7 days.',
    ),
    _Line('Double-check your phone number.'),
    _Line('Accurate details help us reach you when it matters.'),
    _Line('Take a moment to review everything before saving.'),
  ],
  'digital_id': [
    _Line('This is your Digital Donor ID. Show it at the donation center.'),
    _Line('Keep your Digital Donor ID handy on donation day.'),
    _Line('You can save your ID as a PDF for later.'),
    _Line('Your ID makes check-in at the center quick and easy.'),
  ],
  'verify': [
    _Line('Use a clear photo with all four corners visible.'),
    _Line('Verified donors unlock the Verified Donor frame!'),
    _Line('Good lighting helps. Avoid glare and shadows.'),
    _Line('Make sure the name on your ID matches your profile.'),
  ],
  'notification_settings': [
    _Line('Choose which alerts you want to get.'),
    _Line('Turn on notifications so you never miss an appointment.'),
    _Line('You can change these anytime.'),
    _Line('Only the alerts you want, nothing more.'),
  ],
  'privacy_security': [
    _Line('Your privacy matters. You control your data.'),
    _Line('Choose a strong password and keep it to yourself.'),
    _Line('You can change your password here whenever you like.'),
    _Line('Your information is only used to help you donate.'),
  ],
  'help_support': [
    _Line('Need a hand? The eDonate team is here for you.'),
    _Line("Can't find an answer? Reach out to the team."),
    _Line('No question is too small. Just ask!'),
    _Line('We read every message. Thanks for helping us improve!'),
  ],
};

/// On these screens Dugtong only says the screen's own (neutral) lines: no
/// jokes, greetings, tips or celebrations. Privacy & Security hosts the
/// delete-account flow.
const Set<String> _neutralScreens = {'privacy_security'};

/// Picks what Dugtong says. Pure logic (no timers or widgets) so it can be
/// tested on its own; the overlay decides *when* to speak.
class DugtongChatter {
  final math.Random _rand;
  final List<String> _recent = [];
  final List<String> _specials = [];

  DugtongChatter({math.Random? random}) : _rand = random ?? math.Random();

  static const int _recentLimit = 6;

  /// How often a random line comes from the current screen's pool, when it
  /// has one.
  static const double screenChance = 0.6;

  /// Whether [screenId] has lines of its own.
  static bool hasScreenPool(String screenId) =>
      _screenPools.containsKey(screenId);

  /// Whether Dugtong must stay neutral on [screenId].
  static bool isNeutral(String screenId) => _neutralScreens.contains(screenId);

  /// Templates currently excluded because they were said recently.
  List<String> get recent => List.unmodifiable(_recent);

  /// A one-off line to say soon (e.g. after a new check-in or an evolution).
  void queueSpecial(String template) {
    if (!_specials.contains(template)) _specials.add(template);
  }

  bool get hasSpecial => _specials.isNotEmpty;

  /// A line about the screen the donor just opened, or null when the screen
  /// has no pool or everything in it was said recently.
  String? screenLine(StreakData data, String screenId, {DateTime? now}) {
    final lines = _screenPools[screenId];
    if (lines == null) return null;
    final ctx = _ctxFor(data, now ?? DateTime.now());
    final line = _pick(lines, ctx);
    return line == null ? null : _remember(line.text, ctx);
  }

  _Line? _pick(List<_Line> lines, _Ctx ctx) {
    final eligible = [
      for (final line in lines)
        if ((line.when?.call(ctx) ?? true) &&
            _usable(line.text, ctx) &&
            !_recent.contains(line.text))
          line,
    ];
    if (eligible.isEmpty) return null;
    return eligible[_rand.nextInt(eligible.length)];
  }

  /// Next line to speak for [data], or null if nothing is eligible. About 60 %
  /// of the time it comes from [screenId]'s pool (if it has one), the rest
  /// from the everyday pools.
  String? next(StreakData data, {DateTime? now, String screenId = 'generic'}) {
    final ctx = _ctxFor(data, now ?? DateTime.now());
    final neutral = isNeutral(screenId);

    // Special lines go first, once. (Not on neutral screens: they wait.)
    while (!neutral && _specials.isNotEmpty) {
      final template = _specials.removeAt(0);
      if (_usable(template, ctx)) return _remember(template, ctx);
    }

    final screenLines = _screenPools[screenId];
    if (screenLines != null && (neutral || _rand.nextDouble() < screenChance)) {
      final line = _pick(screenLines, ctx);
      if (line != null) return _remember(line.text, ctx);
    }
    if (neutral) return null;

    for (var attempt = 0; attempt < 2; attempt++) {
      final eligible = <_Pool, List<_Line>>{};
      for (final pool in _pools) {
        final lines = [
          for (final line in pool.lines)
            if ((line.when?.call(ctx) ?? true) &&
                _usable(line.text, ctx) &&
                !_recent.contains(line.text))
              line,
        ];
        if (lines.isNotEmpty) eligible[pool] = lines;
      }
      if (eligible.isNotEmpty) {
        var roll = _rand.nextInt(
          eligible.keys.fold<int>(0, (sum, p) => sum + p.weight),
        );
        for (final entry in eligible.entries) {
          roll -= entry.key.weight;
          if (roll < 0) {
            final line = entry.value[_rand.nextInt(entry.value.length)];
            return _remember(line.text, ctx);
          }
        }
      }
      // Everything eligible was said recently: relax the window and retry.
      if (_recent.length > 3) _recent.removeRange(0, _recent.length - 3);
    }
    return null;
  }

  String _remember(String template, _Ctx ctx) {
    _recent.add(template);
    while (_recent.length > _recentLimit) {
      _recent.removeAt(0);
    }
    return _fill(template, ctx);
  }

  _Ctx _ctxFor(StreakData data, DateTime now) {
    final next = data.nextMilestone;
    return _Ctx(
      n: data.current,
      longest: data.longest,
      remaining: next == null
          ? null
          : (next.remaining ?? next.days - data.current),
      label: (next != null && next.label.isNotEmpty) ? next.label : null,
      stage: dugtongStageFor(data.current).stageName,
      freeze: data.freezeAvailable,
      verified: data.isVerified,
      hour: now.hour,
    );
  }

  // A line can only be used when everything it mentions is known.
  bool _usable(String t, _Ctx c) {
    if (t.contains('{remaining}') && c.remaining == null) return false;
    if (t.contains('{label}') && c.label == null) return false;
    if (t.contains('{longest}') && c.longest <= 0) return false;
    return true;
  }

  static String _fill(String t, _Ctx c) => t
      .replaceAll('{n}', '${c.n}')
      .replaceAll('{remaining}', '${c.remaining ?? ''}')
      .replaceAll('{label}', c.label ?? '')
      .replaceAll('{longest}', '${c.longest}')
      .replaceAll('{stage}', c.stage);

  /// Every template (for tests and for counting).
  static List<String> get allTemplates => [
    for (final pool in _pools) ...pool.lines.map((l) => l.text),
  ];

  /// Every screen line, by screen id.
  static Map<String, List<String>> get screenTemplates => {
    for (final e in _screenPools.entries)
      e.key: [for (final l in e.value) l.text],
  };
}

// ─── The speech bubble ─────────────────────────────────────────────────────

/// A rounded white card with a small tail pointing at Dugtong.
class DugtongSpeechBubble extends StatelessWidget {
  static const double maxWidth = 190;
  static const double tailWidth = 8;
  // The metrics only (it also sizes the bubble); the color follows the mode.
  static const TextStyle textStyle = TextStyle(fontSize: 12, height: 1.3);
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 11,
    vertical: 8,
  );

  final String text;

  /// True when Dugtong is on the bubble's right (so the tail is too).
  final bool tailOnRight;

  /// Vertical position of the tail tip, in pixels from the bubble's top.
  final double tailTop;

  const DugtongSpeechBubble({
    super.key,
    required this.text,
    required this.tailOnRight,
    required this.tailTop,
  });

  /// Size the bubble will take, including the tail.
  static Size measure(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth - tailWidth - padding.horizontal);
    return Size(
      painter.width + padding.horizontal + tailWidth,
      painter.height + padding.vertical,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = measure(text);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: tailOnRight ? 0 : tailWidth,
            right: tailOnRight ? tailWidth : 0,
            top: 0,
            bottom: 0,
            child: Container(
              padding: padding,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: context.palette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .1),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: textStyle.copyWith(color: context.palette.foreground),
              ),
            ),
          ),
          Positioned(
            left: tailOnRight ? null : 0,
            right: tailOnRight ? 0 : null,
            top: (tailTop - 7).clamp(8.0, math.max(8.0, size.height - 22)),
            child: CustomPaint(
              size: const Size(tailWidth + 1, 14),
              painter: _TailPainter(
                pointsRight: tailOnRight,
                fill: context.palette.surface,
                border: context.palette.border,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  final bool pointsRight;
  final Color fill;
  final Color border;
  const _TailPainter({
    required this.pointsRight,
    required this.fill,
    required this.border,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // The tail overlaps the card's edge by 1 px so there is no seam.
    final path = pointsRight
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(w, h / 2)
            ..lineTo(0, h)
            ..close())
        : (Path()
            ..moveTo(w, 0)
            ..lineTo(0, h / 2)
            ..lineTo(w, h)
            ..close());
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      Path()
        ..moveTo(pointsRight ? 0 : w, 0)
        ..lineTo(pointsRight ? w : 0, h / 2)
        ..lineTo(pointsRight ? 0 : w, h),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(covariant _TailPainter old) =>
      old.pointsRight != pointsRight ||
      old.fill != fill ||
      old.border != border;
}
