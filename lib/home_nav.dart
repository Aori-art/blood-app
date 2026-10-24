// Switch Home's tabs from anywhere in the app.
//
// A "Book an Appointment" button on the eligibility result used to push a
// second Book screen, without the floating nav. HomeNav.goTo closes whatever
// is open above Home and selects the tab instead, the same way a tap on the
// nav does. When Home is not open (the donor came in another way) it returns
// false and the caller pushes the screen as before.
import 'package:flutter/foundation.dart';

/// Home's five tabs, in the nav's order.
enum HomeTab { home, book, check, history, alerts }

/// What Home's state does for HomeNav.
abstract class HomeNavHost {
  bool get mounted;

  /// Close the routes above Home and select the tab at [index].
  void showTab(int index);
}

class HomeNav {
  HomeNav._();

  static HomeNavHost? _host;

  /// A center the Book tab should select next time it looks (from a post's
  /// Donate Now). The Book tab clears it once it has used it.
  static final ValueNotifier<int?> pendingBookFacilityId = ValueNotifier(null);

  static void register(HomeNavHost host) => _host = host;

  /// Only the Home that registered can unregister (a new Home may already
  /// have taken over).
  static void unregister(HomeNavHost host) {
    if (identical(_host, host)) _host = null;
  }

  /// Whether a Home is open to switch tabs on.
  static bool get available => _host?.mounted ?? false;

  /// Shows [tab] on Home, closing every screen above it. False when Home is
  /// not open: the caller falls back to pushing the screen.
  static bool goTo(HomeTab tab, {int? bookFacilityId}) {
    final host = _host;
    if (host == null || !host.mounted) return false;
    if (bookFacilityId != null) pendingBookFacilityId.value = bookFacilityId;
    host.showTab(tab.index);
    return true;
  }
}
