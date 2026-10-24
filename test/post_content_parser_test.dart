import 'package:blood/newsfeed/post_content_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sample event post: title, six rows and the note', () {
    const text =
        '🩸 Capstone\n'
        '📅 Date: Mon, October 12, 2026\n'
        '🕒 Time: 2:08 AM – 8:08 PM\n'
        '📍 Location: Barangay Hall\n'
        'Address: 123 Main St, Quezon City\n'
        '👥 Capacity: 90 donors\n'
        'Status: Open\n'
        '\n'
        'Only eligible donors may donate while this event is open and has '
        'capacity.';
    final p = parsePostContent(text);
    expect(p.title, 'Capstone');
    expect(p.rows.map((r) => r.kind), [
      InfoKind.date,
      InfoKind.time,
      InfoKind.location,
      InfoKind.address,
      InfoKind.capacity,
      InfoKind.status,
    ]);
    expect(p.row(InfoKind.date)!.value, 'Mon, October 12, 2026');
    expect(p.row(InfoKind.time)!.value, '2:08 AM – 8:08 PM');
    expect(p.row(InfoKind.location)!.label, 'Location');
    expect(p.row(InfoKind.capacity)!.value, '90 donors');
    expect(p.row(InfoKind.status)!.value, 'Open');
    expect(
      p.body,
      'Only eligible donors may donate while this event is open and has '
      'capacity.',
    );
  });

  test('plain story: no title, body is the cleaned text', () {
    const text = '❤️ Thank you to everyone who came!\n\nSee you next month.';
    final p = parsePostContent(text);
    expect(p.title, isNull);
    expect(p.rows, isEmpty);
    expect(p.body, 'Thank you to everyone who came!\n\nSee you next month.');
  });

  test('only a time row, with a lowercase label', () {
    final p = parsePostContent('Drop by today\n⏰ time : 9 AM - 5 PM');
    expect(p.title, 'Drop by today');
    expect(p.rows.single.kind, InfoKind.time);
    expect(p.rows.single.label, 'Time');
    expect(p.rows.single.value, '9 AM - 5 PM');
    expect(p.body, '');
  });

  test('empty text', () {
    final p = parsePostContent('');
    expect(p.title, isNull);
    expect(p.rows, isEmpty);
    expect(p.body, '');
    expect(parsePostContent('  \n \n').body, '');
  });

  test('several emoji, joiners and variation selectors are stripped', () {
    final p = parsePostContent(
      '🩸🩸 ❤️‍🔥 Big Drive\r\n📅🗓️ Date: Fri\r\n⭐ Status: Full\r\n✅ Bring an ID',
    );
    expect(p.title, 'Big Drive');
    expect(p.row(InfoKind.date)!.value, 'Fri');
    expect(p.row(InfoKind.status)!.value, 'Full');
    expect(p.body, 'Bring an ID');
  });

  test('lines after the first row never become the title', () {
    final p = parsePostContent('Date: Today\nCome early\nThanks');
    expect(p.title, isNull);
    expect(p.body, 'Come early\nThanks');
  });
}
