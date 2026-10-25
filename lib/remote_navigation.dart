import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

/// The hero stays mounted; shelves remain lazy. Offscreen destinations are
/// rebuilt by scrolling to their known extent before requesting remote focus.
class RemoteBrowseList extends StatefulWidget {
  const RemoteBrowseList({
    super.key,
    required this.hero,
    required this.shelves,
    required this.heroExtent,
    required this.shelfExtent,
    this.shelfExtras = const [],
  });
  final Widget hero;
  final List<Widget> shelves;
  final double heroExtent, shelfExtent;
  final List<double> shelfExtras;
  double rowExtent(int index) =>
      shelfExtent + (index < shelfExtras.length ? shelfExtras[index] : 0);
  @override
  State<RemoteBrowseList> createState() => _RemoteBrowseListState();
}

class _RemoteBrowseListState extends State<RemoteBrowseList> {
  final scroll = ScrollController();
  final rows = <FocusNode>[];
  final heroVisible = ValueNotifier(true);
  bool moving = false;

  FocusNode row(int index) {
    while (rows.length <= index) {
      rows.add(
        FocusNode(
          debugLabel: 'Browse row ${rows.length}',
          skipTraversal: true,
          canRequestFocus: false,
        ),
      );
    }
    return rows[index];
  }

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      final visible = scroll.offset < widget.heroExtent;
      if (heroVisible.value != visible) heroVisible.value = visible;
    });
  }

  KeyEventResult step(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!up && event.logicalKey != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    final from = primary == null
        ? -1
        : rows.indexWhere(primary.ancestors.contains);
    if (from < 0) return KeyEventResult.ignored;
    final target = from + (up ? -1 : 1);
    if (target < 0) {
      if (scroll.hasClients && scroll.offset > 0) {
        move(0, primary!.rect.center.dx);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // Hero → top navigation.
    }
    if (target > widget.shelves.length || moving) return KeyEventResult.handled;
    move(target, primary!.rect.center.dx);
    return KeyEventResult.handled;
  }

  Future<void> move(int index, double x) async {
    moving = true;
    try {
      final offset = index == 0
          ? 0.0
          : widget.heroExtent +
                List.generate(
                  index - 1,
                  widget.rowExtent,
                ).fold<double>(0, (sum, h) => sum + h) -
                118;
      await scroll.animateTo(
        offset.clamp(0, scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final width = MediaQuery.sizeOf(context).width;
      final targets = row(index).traversalDescendants
          .where(
            (n) =>
                n.context != null &&
                n.traversalDescendants.isEmpty &&
                n.rect.right > 0 &&
                n.rect.left < width,
          )
          .toList();
      if (index > 0) {
        targets.sort(
          (a, b) => (a.rect.center.dx - x).abs().compareTo(
            (b.rect.center.dx - x).abs(),
          ),
        );
      }
      if (targets.isNotEmpty) targets.first.requestFocus();
    } finally {
      moving = false;
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    heroVisible.dispose();
    for (final node in rows) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (var i = 0; i <= widget.shelves.length; i++) {
      row(i);
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: step,
      child: CustomScrollView(
        controller: scroll,
        scrollCacheExtent: ScrollCacheExtent.pixels(widget.shelfExtent * .75),
        slivers: [
          SliverToBoxAdapter(
            child: Focus(
              focusNode: row(0),
              child: ValueListenableBuilder<bool>(
                valueListenable: heroVisible,
                builder: (_, visible, child) =>
                    TickerMode(enabled: visible, child: child!),
                child: widget.hero,
              ),
            ),
          ),
          SliverVariedExtentList(
            itemExtentBuilder: (index, _) => widget.rowExtent(index),
            delegate: SliverChildBuilderDelegate(
              (context, i) =>
                  Focus(focusNode: row(i + 1), child: widget.shelves[i]),
              childCount: widget.shelves.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}

/// Slider arrows change the value; Up/Down can still reach the other player
/// regions instead of being swallowed by the platform Slider's shortcuts.
KeyEventResult playerControlStep(
  LogicalKeyboardKey key, {
  required FocusNode back,
  required FocusNode play,
  required FocusNode progress,
  required FocusNode video,
  required List<FocusNode> bottom,
  required ValueChanged<FocusNode> request,
}) {
  if (key == LogicalKeyboardKey.arrowUp) {
    request(progress.hasFocus || back.hasFocus ? back : progress);
  } else if (key == LogicalKeyboardKey.arrowDown) {
    if (back.hasFocus) {
      request(progress);
    } else if (progress.hasFocus) {
      request(play);
    } else if (!bottom.any((n) => n.hasFocus)) {
      request(video);
    }
  } else if (key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight) {
    final from = bottom.indexWhere((n) => n.hasFocus);
    if (from >= 0) {
      request(
        bottom[(from + (key == LogicalKeyboardKey.arrowLeft ? -1 : 1)).clamp(
          0,
          bottom.length - 1,
        )],
      );
    }
  } else {
    return KeyEventResult.ignored;
  }
  return KeyEventResult.handled;
}

typedef RemoteVolumeKeys = RemoteSliderKeys;

class RemoteSliderKeys extends StatefulWidget {
  const RemoteSliderKeys({
    super.key,
    required this.focusNode,
    required this.value,
    required this.onChanged,
    required this.child,
    this.step = 5,
    this.maximum = 100,
    this.onActivate,
  });
  final FocusNode focusNode;
  final double value, step, maximum;
  final VoidCallback? onActivate;
  final ValueChanged<double> onChanged;
  final Widget child;
  @override
  State<RemoteSliderKeys> createState() => _RemoteSliderKeysState();
}

class _RemoteSliderKeysState extends State<RemoteSliderKeys> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.focusNode,
    onFocusChange: (value) => setState(() => focused = value),
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          widget.value > 0) {
        widget.onChanged(math.max(0, widget.value - widget.step));
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
          widget.value < widget.maximum) {
        widget.onChanged(math.min(widget.maximum, widget.value + widget.step));
        return KeyEventResult.handled;
      }
      if (widget.onActivate != null &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.space)) {
        widget.onActivate!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: SliderTheme(
      data: SliderTheme.of(context).copyWith(thumbShape: _FocusThumb(focused)),
      child: ExcludeFocus(child: widget.child),
    ),
  );
}

/// Only the thumb shows remote focus: it grows and gains a halo.
class _FocusThumb extends SliderComponentShape {
  const _FocusThumb(this.focused);
  final bool focused;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(14);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas,
        color = sliderTheme.thumbColor ?? Colors.white;
    if (focused) {
      canvas.drawCircle(
        center,
        14,
        Paint()..color = color.withValues(alpha: .3),
      );
    }
    canvas.drawCircle(center, focused ? 8 : 6, Paint()..color = color);
  }
}

/// Detail pages have variable-height episode/cast sections. Keep their hero and
/// body anchors mounted and traverse actual action rows, including those above
/// the viewport, before considering the fixed navigation bar.
class RemoteDetailList extends StatefulWidget {
  const RemoteDetailList({super.key, required this.hero, required this.body});
  final Widget hero, body;
  @override
  State<RemoteDetailList> createState() => _RemoteDetailListState();
}

class _RemoteDetailListState extends State<RemoteDetailList> {
  final scroll = ScrollController();
  final hero = FocusNode(skipTraversal: true, canRequestFocus: false);
  final body = FocusNode(skipTraversal: true, canRequestFocus: false);
  bool moving = false;

  List<FocusNode> targets(FocusNode parent) {
    final width = MediaQuery.sizeOf(context).width;
    return parent.traversalDescendants
        .where(
          (n) =>
              n.context != null &&
              n.traversalDescendants.isEmpty &&
              n.rect.right > 0 &&
              n.rect.left < width,
        )
        .toList();
  }

  KeyEventResult step(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!up && event.logicalKey != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    final inHero = primary.ancestors.contains(hero),
        inBody = primary.ancestors.contains(body);
    if (!inHero && !inBody) return KeyEventResult.ignored;
    if (moving) return KeyEventResult.handled;
    if (inHero && up && scroll.offset <= 0) return KeyEventResult.ignored;
    final x = primary.rect.center.dx, y = primary.rect.top;
    final options = targets(body)
        .where(
          (n) => inHero || (up ? n.rect.top < y - 10 : n.rect.top > y + 10),
        )
        .toList();
    if (inHero && up || options.isEmpty && up) {
      final actions = targets(hero);
      if (actions.isNotEmpty) move(actions.first, toHero: true);
    } else if (options.isNotEmpty) {
      options.sort((a, b) => a.rect.top.compareTo(b.rect.top));
      final rowY = inBody && up
          ? options.last.rect.top
          : options.first.rect.top;
      final row = options.where((n) => (n.rect.top - rowY).abs() < 10).toList()
        ..sort(
          (a, b) => (a.rect.center.dx - x).abs().compareTo(
            (b.rect.center.dx - x).abs(),
          ),
        );
      move(row.first);
    }
    return KeyEventResult.handled;
  }

  Future<void> move(FocusNode target, {bool toHero = false}) async {
    moving = true;
    try {
      final offset = toHero ? 0.0 : scroll.offset + target.rect.top - 128;
      await scroll.animateTo(
        offset.clamp(0, scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
      if (mounted && target.context != null) target.requestFocus();
    } finally {
      moving = false;
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    hero.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: step,
    child: CustomScrollView(
      controller: scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Focus(focusNode: hero, child: widget.hero),
        ),
        SliverToBoxAdapter(
          child: Focus(focusNode: body, child: widget.body),
        ),
      ],
    ),
  );
}
