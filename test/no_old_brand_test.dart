import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app is called Dugtong. No quoted string in lib/ may still say
/// "eDonate", except the things that must keep that spelling: the server and
/// Firebase names, the support mailbox, the notification channel id and icon
/// name, and the import paths of files whose names users never see.

/// What is allowed inside a quoted string (removed before the check).
final _allowed = <RegExp>[
  // The support mailbox is a real address.
  RegExp(r'oedonate@gmail\.com', caseSensitive: false),
  // The server (every URL and path).
  RegExp(r'[\w.-]*edonate\.online[\w./-]*', caseSensitive: false),
  // Firebase project, app and bucket ids.
  RegExp(r'edonate-e75ee[\w.-]*', caseSensitive: false),
  // The notification channel id and the small icon's drawable name.
  RegExp(r'\bedonate_notifications\b'),
  RegExp(r'\bic_stat_edonate\b'),
];

/// Every quoted string on [line] that still says "edonate".
List<String> oldBrandStrings(String line) {
  final trimmed = line.trimLeft();
  // Comments are not shown to anyone; imports only name files.
  if (trimmed.startsWith('//') ||
      trimmed.startsWith('import ') ||
      trimmed.startsWith('export ')) {
    return const [];
  }
  final strings = RegExp(
    r"""'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)" """.trim(),
  );
  final found = <String>[];
  for (final m in strings.allMatches(line)) {
    var s = m.group(1) ?? m.group(2) ?? '';
    for (final ok in _allowed) {
      s = s.replaceAll(ok, '');
    }
    if (s.toLowerCase().contains('edonate')) {
      found.add(m.group(0)!);
    }
  }
  return found;
}

void main() {
  test('the scanner catches the old name and lets the protected ones by', () {
    expect(oldBrandStrings("Text('Welcome to eDonate')"), isNotEmpty);
    expect(oldBrandStrings('Text("EDONATE")'), isNotEmpty);
    expect(oldBrandStrings("'#eDonate'"), isNotEmpty);
    expect(oldBrandStrings("'Dugtong'"), isEmpty);
    expect(oldBrandStrings("'oedonate@gmail.com'"), isEmpty);
    expect(oldBrandStrings('"https://edonate.online/api"'), isEmpty);
    expect(oldBrandStrings("projectId: 'edonate-e75ee'"), isEmpty);
    expect(oldBrandStrings("'edonate_notifications'"), isEmpty);
    expect(oldBrandStrings("Init('ic_stat_edonate')"), isEmpty);
    expect(oldBrandStrings("import 'widgets/edonate_logo.dart';"), isEmpty);
    expect(oldBrandStrings('/// to the "eDonate" wordmark.'), isEmpty);
    // The email address is fine, the words around it are not.
    expect(
      oldBrandStrings("'contact eDonate at oedonate@gmail.com'"),
      isNotEmpty,
    );
  });

  test('no quoted string in lib/ says eDonate', () {
    final failures = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final s in oldBrandStrings(lines[i])) {
          failures.add('${file.path.replaceAll(r'\', '/')}:${i + 1}: $s');
        }
      }
    }
    // Printed so each hit can be opened: file:line.
    if (failures.isNotEmpty) {
      // ignore: avoid_print
      print(failures.join('\n'));
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
