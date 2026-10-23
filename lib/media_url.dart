import 'config.dart';

/// Builds a full URL for a server-relative media path (e.g. a profile
/// picture path like "uploads/profile/741.jpg"), leaving already-absolute
/// URLs untouched — the same convention as the ready-made image and avatar
/// URLs from get_posts.php.
String? resolveMediaUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final origin = AppConfig.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
  final cleanPath = path.startsWith('/') ? path.substring(1) : path;
  return '$origin/$cleanPath';
}
