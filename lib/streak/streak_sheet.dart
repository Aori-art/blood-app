import 'package:flutter/material.dart';

import '../app_palette.dart';

/// Opens one of the streak home's bottom sheets: palette.surface with a
/// 28 px top radius and a grab handle, at most 85 % of the screen tall (its
/// content scrolls inside when it is longer).
Future<void> showStreakSheet(
  BuildContext context, {
  required Widget header,
  required List<Widget> children,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (context) => StreakSheetFrame(header: header, children: children),
);

class StreakSheetFrame extends StatelessWidget {
  final Widget header;
  final List<Widget> children;
  const StreakSheetFrame({
    super.key,
    required this.header,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            20 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: p.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              header,
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet's title row: an optional leading picture and a bold title.
class StreakSheetHeader extends StatelessWidget {
  final String title;
  final Widget? leading;
  const StreakSheetHeader({super.key, required this.title, this.leading});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (leading != null) ...[leading!, const SizedBox(width: 12)],
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: context.palette.foreground,
          ),
        ),
      ),
    ],
  );
}

/// A tinted 36 px icon tile (menu rows, settings rows).
class StreakIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  const StreakIconTile({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 18, color: color),
  );
}
