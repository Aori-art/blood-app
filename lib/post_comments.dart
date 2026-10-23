import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'comment_options.dart';
import 'commenter_profile_sheet.dart';
import 'config.dart';
import 'donor_avatar.dart';
import 'my_avatar_controller.dart';
import 'login.dart';
import 'post_comments_api.dart';
import 'shared_design.dart' show kCrimson;
import 'skeleton.dart';
import 'streak/streak_controller.dart';
import 'verify.dart';
import 'app_palette.dart';

// ── The sheet ────────────────────────────────────────────────────────────────

/// Opens the comments of one post. Everyone can read; only verified donors can
/// write. [onTotalChanged] reports the post's comment count every time it
/// changes, so the card updates without reloading the feed.
Future<void> showPostComments(
  BuildContext context, {
  required int postId,
  required bool isLoggedIn,
  required String verificationStatus,
  required int total,
  required ValueChanged<int> onTotalChanged,
  VoidCallback? onVerificationChanged,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _CommentsSheet(
    postId: postId,
    isLoggedIn: isLoggedIn,
    verificationStatus: verificationStatus,
    total: total,
    onTotalChanged: onTotalChanged,
    onVerificationChanged: onVerificationChanged,
  ),
);

class _CommentsSheet extends StatefulWidget {
  final int postId;
  final bool isLoggedIn;
  final String verificationStatus;
  final int total;
  final ValueChanged<int> onTotalChanged;
  final VoidCallback? onVerificationChanged;

  const _CommentsSheet({
    required this.postId,
    required this.isLoggedIn,
    required this.verificationStatus,
    required this.total,
    required this.onTotalChanged,
    this.onVerificationChanged,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  static const int _maxLength = 500;

  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  // The sheet's own messenger (a lookup from this State's context would find the
  // page's, whose SnackBars hide behind the sheet).
  final GlobalKey<ScaffoldMessengerState> _messenger =
      GlobalKey<ScaffoldMessengerState>();

  final List<PostComment> _comments = [];
  late int _total = widget.total;
  late String _status = widget.verificationStatus;
  String? _donorId;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _sending = false;
  int? _deleting;

  // Comments sliding away (hidden or reported) and comments just put back.
  final Set<int> _hiding = {};
  final Set<int> _restored = {};

  bool get _loggedIn =>
      widget.isLoggedIn && _donorId != null && _donorId!.isNotEmpty;
  bool get _verified => _status == 'verified';
  bool get _canSend => !_sending && _text.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    unawaited(_start());
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _donorId = prefs.getString('donorId');
    if (_loggedIn) {
      unawaited(_refreshStatus());
      // The composer shows the donor's own photo and frame.
      unawaited(MyAvatarController.instance.load());
    }
    await _load();
  }

  // ─── Data ───────────────────────────────────────────────────────────────

  void _setTotal(int total) {
    if (total == _total) return;
    _total = total;
    widget.onTotalChanged(total);
  }

  Future<void> _load({bool refresh = false}) async {
    if (!refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await PostCommentsApi.fetch(
        postId: widget.postId,
        donorId: _loggedIn ? _donorId : null,
      );
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(page.comments);
        _hasMore = page.hasMore;
        _loading = false;
        _error = null;
        _setTotal(page.total);
      });
    } on CommentsException catch (e) {
      if (!mounted) return;
      if (refresh && _comments.isNotEmpty) {
        _snack(e.message);
      } else {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingMore || _comments.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await PostCommentsApi.fetch(
        postId: widget.postId,
        donorId: _loggedIn ? _donorId : null,
        beforeId: _comments.last.id,
      );
      if (!mounted) return;
      setState(() {
        final known = _comments.map((c) => c.id).toSet();
        _comments.addAll(page.comments.where((c) => !known.contains(c.id)));
        _hasMore = page.hasMore;
        _loadingMore = false;
        _setTotal(page.total);
      });
    } on CommentsException catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _snack(e.message);
    }
  }

  // The status the donor sees can be out of date (verified in the database, or
  // after coming back from the verify screen), so ask the server.
  Future<void> _refreshStatus() async {
    final id = _donorId;
    if (id == null || id.isEmpty) return;
    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/get_verification_status.php?donor_id=$id',
            ),
          )
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(response.body);
      if (body is Map && body['status'] == 'success') {
        final s = body['verification_status']?.toString();
        if (s != null && s.isNotEmpty && mounted && s != _status) {
          setState(() => _status = s);
        }
        if (s == 'verified') unawaited(StreakController.instance.refresh());
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final id = _donorId;
    final content = _text.text.trim();
    if (!_canSend || id == null || id.isEmpty) return;
    setState(() => _sending = true);
    final result = await PostCommentsApi.add(
      postId: widget.postId,
      donorId: id,
      content: content,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (result.ok) {
      final comment = result.comment;
      if (comment == null) {
        // Posted, but the server did not send it back: reload the list.
        _text.clear();
        unawaited(_load(refresh: true));
        return;
      }
      setState(() {
        _comments.removeWhere((c) => c.id == comment.id);
        _comments.insert(0, comment);
        _text.clear();
        _setTotal(result.total ?? _total + 1);
      });
      return;
    }

    switch (result.code) {
      case 'NOT_VERIFIED':
        // The donor is not verified (any more): show the verify card and
        // find out whether the review is still pending.
        setState(() => _status = 'unverified');
        unawaited(_refreshStatus());
        widget.onVerificationChanged?.call();
        _snack(result.message ?? 'Only verified donors can comment.');
      case 'TOO_FAST':
        _snack("You're commenting too fast. Please wait a moment.");
      case 'INVALID_INPUT':
        _snack(result.message ?? 'Please write a valid comment.');
      case 'POST_NOT_FOUND':
        _snack(result.message ?? 'This post is no longer available.');
      default:
        _snack(
          result.message ?? "Couldn't post your comment. Please try again.",
        );
    }
  }

  Future<void> _confirmDelete(PostComment comment) async {
    final id = _donorId;
    if (id == null || _deleting != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete comment?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'This comment will be removed for everyone.',
          style: TextStyle(
            fontSize: 13,
            color: context.palette.muted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kCrimson,
              disabledBackgroundColor: context.palette.border,
              disabledForegroundColor: context.palette.muted,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = comment.id);
    final result = await PostCommentsApi.delete(
      commentId: comment.id,
      donorId: id,
    );
    if (!mounted) return;
    setState(() => _deleting = null);
    if (result.ok) {
      setState(() {
        _comments.removeWhere((c) => c.id == comment.id);
        _setTotal(result.total ?? math.max(0, _total - 1));
      });
    } else {
      _snack(result.message ?? "Couldn't delete the comment. Try again.");
    }
  }

  // ─── Profile and options ────────────────────────────────────────────────

  void _openProfile(PostComment c) =>
      unawaited(showCommenterProfile(context, comment: c));

  Future<void> _openMenu(PostComment c) async {
    final id = _donorId;
    if (id == null || id.isEmpty) return;
    final result = await showCommentMenu(context, comment: c, donorId: id);
    if (result == null || !mounted) return;
    switch (result.action) {
      case CommentMenuAction.hide:
        await _hide(c);
      case CommentMenuAction.delete:
        await _confirmDelete(c);
      case CommentMenuAction.reported:
        _afterReport(c, result.reportCode);
    }
  }

  // Takes the tile out with a short fade and collapse, and lowers the total.
  void _slideAway(PostComment c) {
    setState(() {
      if (_hiding.add(c.id)) _setTotal(math.max(0, _total - 1));
    });
    // A tile that is not on screen has nothing to animate: finish regardless.
    Timer(const Duration(milliseconds: 700), () {
      if (mounted && _hiding.contains(c.id)) _finishRemoval(c.id);
    });
  }

  void _finishRemoval(int id) {
    if (!mounted || !_hiding.contains(id)) return;
    setState(() {
      _comments.removeWhere((c) => c.id == id);
      _hiding.remove(id);
    });
  }

  Future<void> _hide(PostComment c) async {
    final id = _donorId;
    if (id == null || id.isEmpty) return;
    final index = _comments.indexWhere((e) => e.id == c.id);
    final result = await PostCommentsApi.setHidden(
      commentId: c.id,
      donorId: id,
      hide: true,
    );
    if (!mounted) return;
    if (!result.ok) {
      if (result.code == 'COMMENT_NOT_FOUND') {
        _slideAway(c);
        _snack(result.message ?? 'This comment is no longer available.');
      } else {
        _snack(
          result.message ?? "Couldn't hide the comment. Please try again.",
        );
      }
      return;
    }
    HapticFeedback.lightImpact();
    _slideAway(c);
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            "Comment hidden. Only you can't see it.",
            style: TextStyle(fontSize: 13),
          ),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(12),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.white,
            onPressed: () => unawaited(_undoHide(c, index)),
          ),
        ),
      );
  }

  // Brings a hidden comment back to where it was.
  Future<void> _undoHide(PostComment c, int index) async {
    final id = _donorId;
    if (id == null || id.isEmpty) return;
    final result = await PostCommentsApi.setHidden(
      commentId: c.id,
      donorId: id,
      hide: false,
    );
    if (!mounted) return;
    if (!result.ok) {
      _snack(result.message ?? "Couldn't undo that. Please try again.");
      return;
    }
    setState(() {
      if (!_comments.any((e) => e.id == c.id)) {
        // Gone already: put it back in its place, growing in.
        _restored.add(c.id);
        _comments.insert(math.min(math.max(index, 0), _comments.length), c);
      }
      // Still sliding away: it simply slides back.
      _hiding.remove(c.id);
      _setTotal(_total + 1);
    });
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _restored.remove(c.id));
    });
  }

  // A report was taken: the server hides the comment for this donor too.
  void _afterReport(PostComment c, String? code) {
    _slideAway(c);
    _snack(
      code == 'ALREADY_REPORTED'
          ? 'You already reported this comment.'
          : 'Thanks for your report. Our team will review it.',
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 13)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(12),
        ),
      );
  }

  Future<void> _signIn() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
  }

  Future<void> _verifyNow() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const VerifyScreen()));
    if (!mounted) return;
    await _refreshStatus();
    widget.onVerificationChanged?.call();
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Up to 85 % of the screen, and never taller than what the keyboard
        // leaves free.
        final free = constraints.maxHeight - mq.viewInsets.bottom;
        final height = math.min(mq.size.height * 0.85, free);
        return Padding(
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: height,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                // Its own messenger: SnackBars appear inside the sheet instead
                // of behind it.
                child: ScaffoldMessenger(
                  key: _messenger,
                  child: Scaffold(
                    backgroundColor: context.palette.surface,
                    resizeToAvoidBottomInset: false,
                    body: Column(
                      children: [
                        _header(),
                        Divider(height: 1, color: context.palette.border),
                        Expanded(child: _body()),
                      ],
                    ),
                    bottomNavigationBar: _composer(mq),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
    child: Column(
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.palette.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'Comments',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.palette.foreground,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$_total',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.palette.muted,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.close_rounded, color: context.palette.muted),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _body() {
    return RefreshIndicator(
      color: context.palette.primaryText,
      onRefresh: () => _load(refresh: true),
      child: _bodyList(),
    );
  }

  Widget _bodyList() {
    const physics = AlwaysScrollableScrollPhysics();
    if (_loading) {
      return ListView(
        physics: physics,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        children: [_skeletonRows()],
      );
    }
    if (_error != null && _comments.isEmpty) {
      return ListView(
        physics: physics,
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 24),
          Icon(Icons.wifi_off_rounded, color: context.palette.muted, size: 32),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.palette.muted),
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.palette.primaryText,
                side: BorderSide(color: context.palette.primaryText),
              ),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    if (_comments.isEmpty) {
      return ListView(
        physics: physics,
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 40),
          Icon(
            Icons.mode_comment_outlined,
            color: context.palette.muted,
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            _loggedIn && _verified
                ? 'No comments yet. Be the first!'
                : 'No comments yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: context.palette.muted),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: physics,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _comments.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _comments.length) return _loadOlderButton();
        return _tile(_comments[i]);
      },
    );
  }

  Widget _loadOlderButton() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Center(
      child: TextButton(
        onPressed: _loadingMore ? null : _loadOlder,
        style: TextButton.styleFrom(
          foregroundColor: context.palette.primaryText,
        ),
        child: _loadingMore
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.palette.primaryText,
                ),
              )
            : const Text(
                'Load older comments',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
      ),
    ),
  );

  // What the viewer's own comments show: their current frame (so equipping a
  // new one is reflected at once), and their cached photo if the server sent
  // none.
  Widget _avatar(PostComment c) {
    Widget avatar(BuildContext context) {
      final streak = StreakController.instance;
      final frame = c.isMine && streak.data != null
          ? streak.equippedFrame
          : c.frame;
      final me = MyAvatarController.instance;
      final hidden = _photoHiddenFor(c);
      final String? photo;
      if (hidden) {
        photo = null;
      } else if (c.isMine && c.avatar.isEmpty) {
        photo = me.avatarPath;
      } else {
        photo = c.avatar;
      }
      return DonorAvatar(
        photoUrl: photo,
        name: c.authorName,
        frame: frame,
        radius: 18,
        reserveFrameSpace: true,
        hiddenBadge: hidden,
      );
    }

    if (!c.isMine) return avatar(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        StreakController.instance,
        MyAvatarController.instance,
      ]),
      builder: (context, _) => avatar(context),
    );
  }

  // The viewer's own comments follow their current choice (once it is known,
  // so changing it shows at once); otherwise what the server said.
  bool _photoHiddenFor(PostComment c) {
    if (!c.isMine) return false;
    final me = MyAvatarController.instance;
    return me.hideKnown ? me.hidePhotoInComments : c.photoHidden;
  }

  // The avatar as a button that opens the brief profile.
  Widget _avatarButton(PostComment c) {
    Widget button(BuildContext context) => Semantics(
      label:
          "Open ${c.authorName}'s profile"
          '${_photoHiddenFor(c) ? '. Your photo is hidden' : ''}',
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openProfile(c),
        child: _avatar(c),
      ),
    );
    if (!c.isMine) return button(context);
    return ListenableBuilder(
      listenable: MyAvatarController.instance,
      builder: (context, _) => button(context),
    );
  }

  Widget _tile(PostComment c) {
    final deleting = _deleting == c.id;
    return _Collapsible(
      key: ValueKey(c.id),
      collapsed: _hiding.contains(c.id),
      growIn: _restored.contains(c.id),
      onCollapsed: () => _finishRemoval(c.id),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tapping the photo or the name opens the brief profile.
            _avatarButton(c),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: BoxDecoration(
                  color: context.palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Semantics(
                            label: "Open ${c.authorName}'s profile",
                            button: true,
                            excludeSemantics: true,
                            child: GestureDetector(
                              onTap: () => _openProfile(c),
                              child: Text(
                                c.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: context.palette.foreground,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          c.timeAgo,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.palette.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      c.content,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: context.palette.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The options button: for signed-in donors only.
            if (_loggedIn)
              SizedBox(
                width: 36,
                height: 36,
                child: deleting
                    ? Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.palette.muted,
                          ),
                        ),
                      )
                    : Semantics(
                        label: 'More options for this comment',
                        button: true,
                        excludeSemantics: true,
                        child: IconButton(
                          tooltip: 'More options',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: () => _openMenu(c),
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            size: 20,
                            color: context.palette.muted,
                          ),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  // Four grey rows while the first page loads.
  Widget _skeletonRows() => const SkeletonPulse(
    child: Column(
      children: [
        _SkeletonRow(lines: [0.55, 0.9]),
        _SkeletonRow(lines: [0.4, 0.75]),
        _SkeletonRow(lines: [0.5, 0.95, 0.6]),
        _SkeletonRow(lines: [0.45, 0.8]),
      ],
    ),
  );

  // ─── Composer ───────────────────────────────────────────────────────────

  Widget _composer(MediaQueryData mq) {
    final Widget child;
    if (!_loggedIn) {
      child = _infoCard(
        icon: Icons.lock_outline_rounded,
        text: 'Sign in to join the conversation',
        button: 'Sign In',
        onTap: _signIn,
      );
    } else if (!_verified) {
      child = _status == 'pending'
          ? _infoCard(
              icon: Icons.shield_outlined,
              text:
                  "Your ID is being reviewed. You'll be able to comment once "
                  "it's verified.",
            )
          : _infoCard(
              icon: Icons.shield_outlined,
              text:
                  'Verify your ID to comment. You can still read and share '
                  'posts.',
              button: 'Verify now',
              onTap: _verifyNow,
            );
    } else {
      child = _textBox();
    }
    return Material(
      color: context.palette.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.palette.border)),
        ),
        // The keyboard's inset is already added around the whole sheet, so the
        // bottom safe area only counts when no keyboard is up.
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: mq.viewInsets.bottom > 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String text,
    String? button,
    VoidCallback? onTap,
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.palette.accentBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kCrimson.withValues(alpha: 0.15)),
    ),
    child: Row(
      children: [
        Icon(icon, color: context.palette.primaryText, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: context.palette.foreground,
            ),
          ),
        ),
        if (button != null) ...[
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: kCrimson,
              disabledBackgroundColor: context.palette.border,
              disabledForegroundColor: context.palette.muted,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              button,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    ),
  );

  // ─── Hide my photo ───────────────────────────────────────────────────────

  bool _photoBusy = false;

  Future<void> _togglePhoto() async {
    if (_photoBusy) return;
    final me = MyAvatarController.instance;
    final hide = !me.hidePhotoInComments;
    _photoBusy = true;
    final ok = await me.setHidePhotoInComments(hide);
    _photoBusy = false;
    if (!mounted) return;
    _snack(
      !ok
          ? "Couldn't save your choice. Please try again."
          : hide
          ? 'Others will see your initials instead of your photo in comments.'
          : 'Your photo is visible in comments again.',
    );
  }

  /// "Photo visible" / "Photo hidden": a compact switch under the text field.
  Widget _photoChip() => ListenableBuilder(
    listenable: MyAvatarController.instance,
    builder: (context, _) {
      final p = context.palette;
      final hidden = MyAvatarController.instance.hidePhotoInComments;
      return Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          toggled: hidden,
          label: hidden
              ? 'Photo hidden. Tap to show your photo in comments'
              : 'Photo visible. Tap to hide your photo in comments',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _togglePhoto,
            child: ConstrainedBox(
              // A 36 px pill with a 48 px touch target.
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                widthFactor: 1,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: p.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 16,
                        color: p.muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hidden ? 'Photo hidden' : 'Photo visible',
                        style: TextStyle(fontSize: 12, color: p.foreground),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _textBox() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [_textRow(), _photoChip()],
  );

  Widget _textRow() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      // The donor's own photo and frame, as everyone else sees them.
      const Padding(
        padding: EdgeInsets.only(bottom: 1),
        child: ViewerAvatar(radius: 15, reserveFrameSpace: true),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: TextField(
          controller: _text,
          focusNode: _focus,
          minLines: 1,
          maxLines: 4,
          maxLength: _maxLength,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          style: TextStyle(fontSize: 14, color: context.palette.foreground),
          // The counter only shows when the limit is getting close.
          buildCounter:
              (
                context, {
                required currentLength,
                required isFocused,
                required maxLength,
              }) => currentLength > 400
              ? Text(
                  '$currentLength/$maxLength',
                  style: TextStyle(
                    fontSize: 11,
                    color: currentLength >= (maxLength ?? _maxLength)
                        ? context.palette.primaryText
                        : context.palette.muted,
                  ),
                )
              : null,
          decoration: InputDecoration(
            hintText: 'Write a comment...',
            hintStyle: TextStyle(color: context.palette.muted, fontSize: 14),
            filled: true,
            fillColor: context.palette.surfaceAlt,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: IconButton(
          tooltip: 'Send',
          onPressed: _canSend ? _send : null,
          color: context.palette.primaryText,
          disabledColor: context.palette.border,
          icon: _sending
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: context.palette.primaryText,
                  ),
                )
              : const Icon(Icons.send_rounded),
        ),
      ),
    ],
  );
}

/// Lets a comment slide away (fade and collapse) when [collapsed], and grow in
/// when it comes back. [onCollapsed] fires once it has finished disappearing.
class _Collapsible extends StatefulWidget {
  final bool collapsed;
  final bool growIn;
  final VoidCallback onCollapsed;
  final Widget child;

  const _Collapsible({
    super.key,
    required this.collapsed,
    required this.growIn,
    required this.onCollapsed,
    required this.child,
  });

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.growIn ? 0 : 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && widget.collapsed) {
        widget.onCollapsed();
      }
    });
    if (widget.collapsed) {
      _c.reverse();
    } else if (widget.growIn) {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _Collapsible old) {
    super.didUpdateWidget(old);
    if (widget.collapsed && !old.collapsed) {
      _c.reverse();
    } else if (!widget.collapsed && old.collapsed) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: _curve,
    axisAlignment: -1,
    child: FadeTransition(opacity: _curve, child: widget.child),
  );
}

/// One grey placeholder comment: a circle and a bubble with a few bars.
class _SkeletonRow extends StatelessWidget {
  /// The width of each text bar as a fraction of the bubble.
  final List<double> lines;
  const _SkeletonRow({required this.lines});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 5),
          child: SkeletonBox.circle(36),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: context.palette.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  FractionallySizedBox(
                    widthFactor: lines[i],
                    child: SkeletonBox(height: i == 0 ? 11 : 10, radius: 5),
                  ),
                  if (i != lines.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 36),
      ],
    ),
  );
}
