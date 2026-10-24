import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens the full-screen image viewer: a black backdrop, pinch and
/// double-tap zoom, drag down to close, a close button, a spinner while an
/// image loads and an error state with Retry.
///
/// The image at index i flies in from the Hero tagged
/// '${heroTagPrefix}_i'. [fromCircle]: that Hero is a round avatar, so the
/// photo's corners open up from the circle into the full image on the way.
/// [title] shows as a small pill at the top.
void openImageViewer(
  BuildContext context, {
  required List<String> imageUrls,
  required int initialIndex,
  required String heroTagPrefix,
  String? title,
  bool fromCircle = false,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => _ImageViewerPage(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
        heroTagPrefix: heroTagPrefix,
        title: title,
        fromCircle: fromCircle,
      ),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _ImageViewerPage extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String heroTagPrefix;
  final String? title;
  final bool fromCircle;

  const _ImageViewerPage({
    required this.imageUrls,
    required this.initialIndex,
    required this.heroTagPrefix,
    this.title,
    this.fromCircle = false,
  });

  @override
  State<_ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<_ImageViewerPage> {
  late final PageController _pageController;
  late int _currentIndex;
  final TransformationController _transformController =
      TransformationController();
  bool _isZoomed = false;

  bool _dragging = false;
  double _dragOffset = 0;

  // Bumped by Retry, so a failed image is fetched again.
  final Map<int, int> _attempt = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformController.addListener(_handleTransformChange);
  }

  @override
  void dispose() {
    _transformController.removeListener(_handleTransformChange);
    _transformController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _handleTransformChange() {
    final zoomed = _transformController.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_isZoomed) {
      _transformController.value = Matrix4.identity();
      return;
    }
    final position = details.localPosition;
    const scale = 2.5;
    final x = -position.dx * (scale - 1);
    final y = -position.dy * (scale - 1);
    _transformController.value = Matrix4.identity()
      ..translate(x, y)
      ..scale(scale);
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_isZoomed) return;
    setState(() {
      _dragging = true;
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0, 400);
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_isZoomed) return;
    final flungDown = details.velocity.pixelsPerSecond.dy > 700;
    if (_dragOffset > 120 || flungDown) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _dragging = false;
      _dragOffset = 0;
    });
  }

  void _retry(int index, String url) {
    NetworkImage(url).evict();
    setState(() => _attempt[index] = (_attempt[index] ?? 0) + 1);
  }

  Widget _image(int index) {
    final url = widget.imageUrls[index];
    final image = Image.network(
      url,
      key: ValueKey('$url#${_attempt[index] ?? 0}'),
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
      errorBuilder: (context, error, stackTrace) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              color: Colors.white70,
              size: 40,
            ),
            const SizedBox(height: 8),
            const Text(
              "Couldn't load image",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _retry(index, url),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
    if (!widget.fromCircle) {
      return Hero(tag: '${widget.heroTagPrefix}_$index', child: image);
    }
    // From a round avatar: a square box the size of the screen's width, so
    // the photo has somewhere to grow into before it has loaded.
    final side = MediaQuery.sizeOf(context).shortestSide;
    return Hero(
      tag: '${widget.heroTagPrefix}_$index',
      flightShuttleBuilder: (context, animation, direction, from, to) =>
          _CircleToRectShuttle(animation: animation, url: url),
      child: SizedBox.square(dimension: side, child: image),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (1 - (_dragOffset / 400)).clamp(0.25, 1.0);
    final multiple = widget.imageUrls.length > 1;
    final title = widget.title;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          onVerticalDragUpdate: _handleVerticalDragUpdate,
          onVerticalDragEnd: _handleVerticalDragEnd,
          child: AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: double.infinity,
            height: double.infinity,
            color: Colors.black.withValues(alpha: opacity),
            transform: Matrix4.translationValues(0, _dragOffset, 0),
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  physics: _isZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: widget.imageUrls.length,
                  onPageChanged: (i) => setState(() {
                    _currentIndex = i;
                    _isZoomed = false;
                    _transformController.value = Matrix4.identity();
                  }),
                  itemBuilder: (context, index) => GestureDetector(
                    onDoubleTapDown: _handleDoubleTap,
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 1,
                      maxScale: 4,
                      // Panning is only meaningful once zoomed in — keeping
                      // it off at rest lets our own vertical-drag-to-close
                      // gesture win the arena instead of InteractiveViewer.
                      panEnabled: _isZoomed,
                      child: Center(child: _image(index)),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topLeft,
                          child: Tooltip(
                            message: 'Close',
                            child: InkWell(
                              onTap: () => Navigator.of(context).pop(),
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (title != null || multiple)
                          Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              // Clear of the close button.
                              padding: const EdgeInsets.symmetric(
                                horizontal: 52,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (title != null)
                                    _Pill(
                                      text: title,
                                      color: Colors.black.withValues(
                                        alpha: 0.54,
                                      ),
                                      fontSize: 13,
                                      bold: true,
                                    ),
                                  if (title != null && multiple)
                                    const SizedBox(height: 6),
                                  if (multiple)
                                    _Pill(
                                      text:
                                          '${_currentIndex + 1} / ${widget.imageUrls.length}',
                                      color: Colors.black54,
                                      fontSize: 12,
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final double fontSize;
  final bool bold;
  const _Pill({
    required this.text,
    required this.color,
    required this.fontSize,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
      ),
    ),
  );
}

/// The flight from a round avatar to the full photo: the corners open from
/// a circle to square ones (and back on the way out). With animations
/// removed, a plain fade.
class _CircleToRectShuttle extends StatelessWidget {
  final Animation<double> animation;
  final String url;
  const _CircleToRectShuttle({required this.animation, required this.url});

  @override
  Widget build(BuildContext context) {
    final photo = Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      // A broken link: the page shows its error state once it lands.
      errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: photo);
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => LayoutBuilder(
        builder: (context, box) {
          final t = Curves.easeInOut.transform(animation.value);
          final round = math.min(box.maxWidth, box.maxHeight) / 2;
          return ClipRRect(
            borderRadius: BorderRadius.circular(round * (1 - t)),
            child: child,
          );
        },
      ),
      child: photo,
    );
  }
}
