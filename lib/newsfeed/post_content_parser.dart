// Splits a post's text into a title, labelled info rows and a free body.
//
// Event posts arrive as plain text such as:
//
//   🩸 Capstone
//   📅 Date: Mon, October 12, 2026
//   🕒 Time: 2:08 AM – 8:08 PM
//   📍 Location: City Hall
//   Address: 123 Main St
//   👥 Capacity: 90 donors
//   Status: Open
//   Only eligible donors may donate while this event is open ...
//
// The card shows the rows in an info panel, so this only reads the text; it
// never changes what the server sent.

/// What an info row describes.
enum InfoKind { date, time, location, address, capacity, status, other }

class InfoRow {
  const InfoRow({required this.kind, required this.label, required this.value});

  final InfoKind kind;

  /// The label as written ("Date"), without the colon.
  final String label;
  final String value;

  @override
  String toString() => 'InfoRow($kind, $label: $value)';
}

class ParsedPost {
  const ParsedPost({this.title, this.rows = const [], this.body = ''});

  /// The first plain line before any info row, or null when the post has
  /// no info rows.
  final String? title;
  final List<InfoRow> rows;

  /// Everything else, one line per line, with leading emoji removed.
  final String body;

  bool get hasRows => rows.isNotEmpty;

  /// The row of [kind], if there is one.
  InfoRow? row(InfoKind kind) {
    for (final r in rows) {
      if (r.kind == kind) return r;
    }
    return null;
  }
}

final _rowPattern = RegExp(
  r'^(Date|Time|Location|Address|Capacity|Status)\s*:\s*(.+)$',
  caseSensitive: false,
);

bool _isDecoration(int rune) =>
    (rune >= 0x1F300 && rune <= 0x1FAFF) ||
    (rune >= 0x2600 && rune <= 0x27BF) ||
    (rune >= 0x2B00 && rune <= 0x2BFF) ||
    (rune >= 0x2300 && rune <= 0x23FF) ||
    rune == 0xFE0F ||
    rune == 0x200D;

/// [line] without leading emoji (and the spaces between them), trimmed.
String stripLeadingEmoji(String line) {
  final runes = line.trim().runes.toList();
  var i = 0;
  while (i < runes.length) {
    final r = runes[i];
    if (_isDecoration(r) || r == 0x20 || r == 0x09) {
      i++;
    } else {
      break;
    }
  }
  return String.fromCharCodes(runes.sublist(i)).trim();
}

InfoKind _kindOf(String label) => switch (label.toLowerCase()) {
  'date' => InfoKind.date,
  'time' => InfoKind.time,
  'location' => InfoKind.location,
  'address' => InfoKind.address,
  'capacity' => InfoKind.capacity,
  'status' => InfoKind.status,
  _ => InfoKind.other,
};

ParsedPost parsePostContent(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map(stripLeadingEmoji)
      .toList();

  final rows = <InfoRow>[];
  final rest = <String>[];
  String? title;
  for (final line in lines) {
    final m = _rowPattern.firstMatch(line);
    if (m != null) {
      final label = m.group(1)!;
      rows.add(
        InfoRow(
          kind: _kindOf(label),
          // "DATE" or "date" reads as "Date".
          label: label[0].toUpperCase() + label.substring(1).toLowerCase(),
          value: m.group(2)!.trim(),
        ),
      );
    } else if (title == null && rows.isEmpty && line.isNotEmpty) {
      title = line;
    } else {
      rest.add(line);
    }
  }

  String join(List<String> ls) {
    // Drop blank lines at either end; keep the ones in between.
    var start = 0, end = ls.length;
    while (start < end && ls[start].isEmpty) {
      start++;
    }
    while (end > start && ls[end - 1].isEmpty) {
      end--;
    }
    return ls.sublist(start, end).join('\n');
  }

  if (rows.isEmpty) {
    return ParsedPost(body: join(lines));
  }
  return ParsedPost(title: title, rows: rows, body: join(rest));
}
