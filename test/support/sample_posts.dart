// Posts of every kind, as get_posts.php sends them. Shared by the post card
// tests and the theme audits.

const sampleEventText =
    '🩸 Capstone\n'
    '📅 Date: Mon, October 12, 2026\n'
    '🕒 Time: 2:08 AM – 8:08 PM\n'
    '📍 Location: Quezon City Hall\n'
    'Address: Elliptical Road, Diliman, Quezon City\n'
    '👥 Capacity: 90 donors\n'
    'Status: Open\n'
    'Only eligible donors may donate while this event is open and has '
    'capacity.';

const longStoryText =
    'Last Saturday our volunteers welcomed more than eighty donors.\n'
    'Thank you to every first-timer who came in nervous and left smiling.\n'
    'Thank you to the nurses who stayed past closing.\n'
    'Thank you to the barangay for the chairs, the tents and the snacks.\n'
    'Every bag collected goes to patients in our partner hospitals.\n'
    'We will post the next schedule here soon.\n'
    'See you at the next drive!';

Map<String, dynamic> eventPostJson({
  int id = 101,
  String? image,
  bool liked = false,
  bool donationOpen = true,
}) => {
  'id': id,
  'type': 'event',
  'author': 'Dugtong',
  'authorAvatar': '',
  'authorBadge': 'Official',
  'authorType': 'admin',
  'isDonation': true,
  'donationOpen': donationOpen,
  'eventId': 9,
  'donationFacilityId': 3,
  'timeAgo': '1 week ago',
  'content': sampleEventText,
  if (image != null) 'image': image,
  'likes': 2,
  'comments': 3,
  'liked': liked,
};

Map<String, dynamic> urgentPostJson({int id = 102}) => {
  'id': id,
  'type': 'urgent',
  'author': 'City Blood Bank',
  'authorAvatar': '',
  'authorType': 'facility',
  'authorBadge': 'Blood bank',
  'isDonation': true,
  'donationFacilityId': 4,
  'timeAgo': '2h ago',
  'content': 'We urgently need O+ donors for a patient in surgery tonight.',
  'bloodType': 'O+',
  'hospital': 'East Avenue Medical Center',
  'urgency': 'critical',
  'likes': 12,
  'comments': 4,
};

Map<String, dynamic> milestonePostJson({int id = 103}) => {
  'id': id,
  'type': 'milestone',
  'author': 'Dugtong',
  'authorAvatar': '',
  'authorType': 'admin',
  'timeAgo': '3 days ago',
  'content':
      '1,000 donations this year!\nThank you for making this possible, '
      'one bag at a time.',
  'likes': 40,
  'comments': 8,
};

Map<String, dynamic> storyPostJson({int id = 104, String? content}) => {
  'id': id,
  'type': 'story',
  'author': 'Maria Santos',
  'authorAvatar': '',
  'timeAgo': '5h ago',
  'content': content ?? longStoryText,
  'likes': 0,
  'comments': 0,
};

Map<String, dynamic> plainPostJson({int id = 105}) => {
  'id': id,
  'author': 'Red Cell Volunteers',
  'authorAvatar': '',
  'timeAgo': 'Just now',
  'content': 'Drop by our booth at the mall this weekend!',
  'likes': 1,
  'comments': 0,
};

List<Map<String, dynamic>> samplePostsJson() => [
  urgentPostJson(),
  eventPostJson(),
  milestonePostJson(),
  storyPostJson(),
  eventPostJson(id: 106, image: 'https://example.com/poster.jpg'),
  plainPostJson(),
];
