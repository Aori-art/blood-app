import 'package:blood/app_palette.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/home_nav_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The glass lens of Home's nav: where it sits for a fractional tab, how it
/// stretches between two tabs, how it fades over the Check slot, and the
/// item colors, in both themes.

const double _slot = 328 / 5; // a 360 px phone: the bar is 328 px wide

void main() {
  group('NavLensGeometry', () {
    test('on a whole tab: centered on the item, the rest size', () {
      for (final i in [0, 1, 3, 4]) {
        final g = NavLensGeometry.at(i.toDouble(), slotWidth: _slot);
        expect(g.centerX, closeTo((i + 0.5) * _slot, 1e-9));
        expect(g.width, NavLensGeometry.restWidth);
        expect(g.height, NavLensGeometry.restHeight);
      }
    });

    test('half way between two tabs: between them and stretched', () {
      final g = NavLensGeometry.at(0.5, slotWidth: _slot);
      expect(g.centerX, greaterThan(0.5 * _slot));
      expect(g.centerX, lessThan(1.5 * _slot));
      expect(g.width, greaterThan(NavLensGeometry.restWidth));
      expect(g.width, lessThanOrEqualTo(_slot - 2));
      expect(g.height, lessThan(NavLensGeometry.restHeight));
      // Never wider than its slot, even on a narrow bar.
      final narrow = NavLensGeometry.at(3.5, slotWidth: 56);
      expect(narrow.width, 54);
    });

    test('a quarter of the way: stretched less than half way', () {
      final quarter = NavLensGeometry.at(0.25, slotWidth: _slot);
      final half = NavLensGeometry.at(0.5, slotWidth: _slot);
      expect(quarter.width, greaterThan(NavLensGeometry.restWidth));
      expect(quarter.width, lessThan(half.width));
    });

    test('it fades out over the Check slot and back in beside it', () {
      expect(NavLensGeometry.at(2, slotWidth: _slot).visibility, 0);
      expect(NavLensGeometry.at(1, slotWidth: _slot).visibility, 1);
      expect(NavLensGeometry.at(3, slotWidth: _slot).visibility, 1);
      expect(NavLensGeometry.at(1.5, slotWidth: _slot).visibility, 0.5);
    });

    test('with animations off it never stretches', () {
      for (final p in [0.25, 0.5, 0.75, 3.4]) {
        final g = NavLensGeometry.at(p, slotWidth: _slot, reduceMotion: true);
        expect(g.width, NavLensGeometry.restWidth);
        expect(g.height, NavLensGeometry.restHeight);
      }
    });
  });

  for (final dark in [false, true]) {
    final palette = dark ? AppPalette.dark : AppPalette.light;
    final mode = dark ? 'dark' : 'light';

    test('item colors blend from muted to the brand red ($mode)', () {
      expect(navItemColor(palette, 1, 1), palette.primaryText);
      expect(navItemColor(palette, 3, 1), palette.muted);
      expect(navItemColor(palette, 2, 1), palette.muted);
      final half = navItemColor(palette, 1.5, 1);
      expect(half, Color.lerp(palette.muted, palette.primaryText, 0.5));
      expect(navCloseness(1.25, 1), 0.75);
    });

    testWidgets('the lens paints at its place, and not over Check ($mode)', (
      tester,
    ) async {
      Future<Rect?> lensAt(double position, {bool reduce = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: _slot * 5,
                  height: 64,
                  child: NavGlassLens(
                    geometry: NavLensGeometry.at(
                      position,
                      slotWidth: _slot,
                      reduceMotion: reduce,
                    ),
                    barHeight: 64,
                    reduceMotion: reduce,
                  ),
                ),
              ),
            ),
          ),
        );
        final lens = find.byKey(const ValueKey('nav-lens'));
        if (lens.evaluate().isEmpty) return null;
        // Relative to the bar.
        final bar = tester.getTopLeft(find.byType(NavGlassLens));
        return tester.getRect(lens).shift(-bar);
      }

      final rest = (await lensAt(1))!;
      expect(rest.center.dx, closeTo(1.5 * _slot, 0.01));
      expect(rest.width, NavLensGeometry.restWidth);

      final mid = (await lensAt(0.5))!;
      expect(mid.center.dx, closeTo(_slot, 0.01));
      expect(mid.width, greaterThan(rest.width));

      expect(await lensAt(2), isNull); // over the Check slot: gone
      final calm = (await lensAt(0.5, reduce: true))!;
      expect(calm.width, NavLensGeometry.restWidth);
    });

    test('the painters repaint only when their colors change ($mode)', () {
      Path path(Size s) => Path()..addRect(Offset.zero & s);
      final colors = NavGlassColors.of(palette, frosted: true);
      final a = NavGlassPainter(path: path, colors: colors);
      final b = NavGlassPainter(
        path: path,
        colors: NavGlassColors.of(palette, frosted: true),
      );
      final solid = NavGlassPainter(
        path: path,
        colors: NavGlassColors.of(palette, frosted: false),
      );
      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(solid), isTrue);
      // The glass is never more transparent than the floor.
      expect(colors.tintTop.a, greaterThanOrEqualTo(dark ? 0.52 : 0.60));
      expect(colors.tintBottom.a, greaterThanOrEqualTo(dark ? 0.68 : 0.76));
      expect(solid.colors.tintTop.a, closeTo(0.94, 0.01));
    });
  }
}
