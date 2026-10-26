import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'artwork_cache.dart';
import 'catalog.dart';
import 'letterboxd.dart';
import 'remote_navigation.dart';
import 'main.dart';
import 'orbit.dart';
import 'routes.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

class Shell extends StatelessWidget {
  const Shell({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: currentPage,
    builder: (context, page, _) => PopScope(
      canPop: page == 'Home',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) currentPage.value = 'Home';
      },
      child: Screen(
        child: page == 'My List'
            ? const LibraryView()
            : page == 'Orbit'
            ? const OrbitView()
            : page == 'History'
            ? const HistoryView()
            : page.startsWith('Lookback:')
            ? LookbackView(key: ValueKey(page), decade: int.parse(page.substring(9)))
            : BrowseView(key: ValueKey(page), page: page),
      ),
    ),
  );
}

/// Page frame: scrolling content under a fading top bar.
class Screen extends StatelessWidget {
  const Screen({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ink,
    body: FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Stack(
        children: [
          Positioned.fill(child: child),
          if (Platform.isMacOS)
            const Positioned(
              left: railWidth,
              right: 0,
              top: 0,
              height: 28,
              child: DragToMoveArea(child: SizedBox.expand()),
            ),
          const Positioned(left: 0, top: 0, bottom: 0, child: SideRail()),
        ],
      ),
    ),
  );
}

/// Navigation: a slim rail on the left (logo, tabs, settings) that slides out over the page on hover or remote focus.
class SideRail extends StatefulWidget {
  const SideRail({super.key});
  @override
  State<SideRail> createState() => _SideRailState();
}

class _SideRailState extends State<SideRail> {
  bool hovered = false, focused = false;

  /// Showing the Lookback decades instead of the main tabs.
  bool decades = false;
  final lookbackFocus = FocusNode(debugLabel: 'Lookback'), decadeFocus = FocusNode(debugLabel: 'First decade');

  @override
  void dispose() {
    lookbackFocus.dispose();
    decadeFocus.dispose();
    super.dispose();
  }

  /// Swaps panels; on the remote, focus follows into the panel that slid in.
  void _showDecades(bool show) {
    final follow = focused;
    setState(() => decades = show);
    if (follow) WidgetsBinding.instance.addPostFrameCallback((_) => (show ? decadeFocus : lookbackFocus).requestFocus());
  }

  void _tab(String tab) {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    currentPage.value = tab;
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return ValueListenableBuilder<String>(
      valueListenable: currentPage,
      builder: (context, page, _) {
        bool selected(String tab) => page == tab && !canPop;
        final open = hovered || focused || decades;
        final main = Column(
          key: const ValueKey('main'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (canPop) _RailItem(open: open, icon: const Icon(Icons.arrow_back_rounded), label: 'Back', onTap: goBack),
            _RailItem(open: open, icon: const Icon(Icons.search), label: 'Search', onTap: () => openSearch(context)),
            for (final (tab, icon) in const [('Home', Icons.home_rounded), ('Orbit', Icons.public_rounded), ('Movies', Icons.movie_outlined), ('Series', Icons.tv_rounded)])
              _RailItem(open: open, icon: Icon(icon), label: tab, selected: selected(tab), onTap: () => _tab(tab)),
            _RailItem(
              open: open,
              icon: const Icon(Icons.history_rounded),
              label: 'Lookback',
              selected: page.startsWith('Lookback:') && !canPop,
              focusNode: lookbackFocus,
              onTap: () {
                Catalog.instance.warmLookback();
                _showDecades(true);
              },
            ),
            _RailItem(open: open, icon: const Icon(Icons.bookmark_border_rounded), label: 'My List', selected: selected('My List'), onTap: () => _tab('My List')),
          ],
        );
        final eras = Column(
          key: const ValueKey('decades'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RailItem(open: open, icon: const Icon(Icons.arrow_back_rounded), label: 'Lookback', onTap: () => _showDecades(false)),
            const SizedBox(height: 8),
            for (final d in Catalog.decades)
              _RailItem(
                open: open,
                focusNode: d == Catalog.decades.first ? decadeFocus : null,
                badge: "'${(d % 100).toString().padLeft(2, '0')}s",
                label: '${d}s',
                selected: selected('Lookback:$d'),
                onTap: () {
                  _showDecades(false);
                  _tab('Lookback:$d');
                },
              ),
          ],
        );
        return MouseRegion(
          onEnter: (_) => setState(() => hovered = true),
          onExit: (_) => setState(() => hovered = false),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (f) => setState(() => focused = f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: open ? 212 : railWidth,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: open ? const [Color(0xfa0b140e), Color(0xf00b140e)] : const [Color(0xd9070c09), Color(0x99070c09)]),
                border: const Border(right: BorderSide(color: Color(0x264d6851))),
                boxShadow: open ? const [BoxShadow(color: Color(0x99000000), blurRadius: 40)] : const [],
              ),
              child: Column(
                children: [
                  SizedBox(height: Platform.isMacOS ? 44 : 20),
                  _RailItem(
                    open: open,
                    icon: const Logo(size: 30),
                    label: 'dremio',
                    labelStyle: text(22, weight: FontWeight.w500, spacing: -1),
                    onTap: () {
                      setState(() => decades = false);
                      _tab('Home');
                    },
                  ),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<int>(
                    valueListenable: Letterboxd.instance.changes,
                    builder: (context, _, _) {
                      final me = Letterboxd.instance.me;
                      return _RailItem(
                        open: open,
                        icon: me == null ? const Icon(Icons.account_circle_outlined) : Avatar(me, size: 30),
                        label: me?.name ?? 'Link Letterboxd',
                        selected: selected('History'),
                        onTap: me == null ? () => openSettings(context) : () => _tab('History'),
                      );
                    },
                  ),
                  Expanded(
                    child: ClipRect(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => SlideTransition(
                          position: Tween(begin: Offset(child.key == const ValueKey('decades') ? 1 : -1, 0), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                        child: decades ? eras : main,
                      ),
                    ),
                  ),
                  _RailItem(open: open, icon: const Icon(Icons.settings_outlined), label: 'Settings', onTap: () => openSettings(context)),
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({required this.open, this.icon, this.badge, required this.label, required this.onTap, this.selected = false, this.labelStyle, this.focusNode});
  final FocusNode? focusNode;
  final bool open, selected;
  final Widget? icon;

  /// Short text shown in place of an icon, e.g. the decade "'80s".
  final String? badge;
  final String label;
  final VoidCallback onTap;
  final TextStyle? labelStyle;
  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool hovered = false, focused = false;

  @override
  Widget build(BuildContext context) {
    final lit = hovered || focused;
    final color = widget.selected ? green : (lit ? white : const Color(0xffb9c5ba));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => hovered = v),
        onShowFocusHighlight: (v) => setState(() => focused = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap())},
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 48,
            decoration: BoxDecoration(color: widget.selected ? const Color(0x24bdff59) : (lit ? const Color(0x14f4f8f1) : Colors.transparent), borderRadius: BorderRadius.circular(14)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: lit ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: const CustomPaint(painter: UfoSpotlight()),
                      ),
                    ),
                  ),
                  OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: 188,
                    child: Row(
                      children: [
                        SizedBox(
                          width: railWidth - 24,
                          child: Center(
                            child: widget.badge != null
                                ? Text(
                                    widget.badge!,
                                    style: text(14, weight: FontWeight.w600, color: color),
                                  )
                                : IconTheme(
                                    data: IconThemeData(color: color, size: 24),
                                    child: widget.icon!,
                                  ),
                          ),
                        ),
                        Expanded(
                          child: AnimatedOpacity(
                            opacity: widget.open ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: widget.labelStyle ?? text(15, weight: FontWeight.w500, color: color),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BrowseView extends StatefulWidget {
  const BrowseView({super.key, required this.page});
  final String page;
  @override
  State<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<BrowseView> {
  final catalog = Catalog.instance;

  @override
  void initState() {
    super.initState();
    catalog.addListener(_changed);
  }

  @override
  void dispose() {
    catalog.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted && !Activity.interacted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.page == 'Movies'
        ? 'movie'
        : widget.page == 'Series'
        ? 'series'
        : null;
    final pool = catalog.pool(type);
    if (pool.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter(context), 140, 0, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Couldn’t load the catalog.', style: text(16, color: muted)),
            const SizedBox(height: 20),
            Pill(label: 'Try again', primary: true, onTap: () => catalog.refresh(force: true).then((_) => setState(() {}))),
          ],
        ),
      );
    }
    final heroes = catalog.heroes(type);
    if (heroes.isEmpty) heroes.add(pool.first);
    final lead = heroes.map((m) => str(m, 'id')).toSet();
    final recommended = catalog.ranked(pool, 'picks${widget.page}').where((m) => !lead.contains(str(m, 'id'))).toList();
    final fresh = '/year/genre=${catalog.year}';
    final c = catalog.catalog;
    final mix = Catalog.mix;
    final decent = Catalog.decent;
    Future<void> open(Meta m) async {
      await openDetail(context, m);
      if (mounted) setState(() {});
    }

    Widget shelf(String title, List<Meta> items, {bool filter = true, bool continueWatching = false}) {
      final visible = (filter ? catalog.playable(items) : items).take(20).toList();
      return visible.isEmpty
          ? const SizedBox.shrink()
          : Shelf(
              title: title,
              items: visible,
              filter: false,
              continueWatching: continueWatching,
              onOpen: continueWatching
                  ? (m) async {
                      await openDetail(context, m, resumeVideo: Store.instance.progress(m).videoId);
                      if (mounted) setState(() {});
                    }
                  : open,
            );
    }

    final rows = <Widget>[
      if (type == null) shelf('Continue Watching', catalog.continueWatching(), filter: false, continueWatching: true),
      shelf(type == null ? 'Recommended for You' : 'Recommended', recommended),
      if (type == null) ...[
        shelf('Trending Today', decent(mix(c('movie/x-trending'), c('series/x-trending')))),
        shelf('Popular Movies', c('movie/top')),
        shelf('Popular Series', c('series/top')),
        shelf('This Week', mix(c('movie/x-week'), c('series/x-week'))),
        shelf('New Releases', mix(c('movie$fresh'), c('series$fresh'))),
        shelf('Fresh Picks', decent(mix(c('movie/x-fresh'), c('series/x-fresh')))),
        shelf('Top Rated', mix(c('movie/imdbRating'), c('series/imdbRating'))),
        for (final s in services) shelf('On ${s[1]}', decent(mix(c('movie/x-${s[0]}'), c('series/x-${s[0]}')))),
      ] else ...[
        shelf('Trending Today', decent(c('$type/x-trending'))),
        shelf('Popular Now', c('$type/top')),
        shelf(type == 'movie' ? 'Most Watched This Week' : 'Popular This Week', c('$type/x-week')),
        shelf('New Releases', c('$type$fresh')),
        shelf(type == 'movie' ? 'Certified Fresh' : 'Best New Shows', decent(c('$type/x-fresh'))),
        shelf('Top Rated', c('$type/imdbRating')),
        for (final s in services) shelf('On ${s[1]}', decent(c('$type/x-${s[0]}'))),
      ],
      for (final g in catalog.genreRows(type, type == null ? 2 : 4)) shelf(g, type == null ? mix(c('movie/top/genre=$g'), c('series/top/genre=$g')) : c('$type/top/genre=$g')),
      const SizedBox(height: 60),
    ];

    return RemoteBrowseList(
      hero: HeroBanner(items: heroes, key: ValueKey('hero${widget.page}')),
      shelves: rows.whereType<Shelf>().toList(),
      shelfExtras: rows.whereType<Shelf>().map((row) => row.continueWatching ? 20.0 : 0.0).toList(),
      heroExtent: (MediaQuery.sizeOf(context).height * .64).clamp(440.0, 720.0),
      shelfExtent: posterWidth(context) * 1.48 + 94 + MediaQuery.textScalerOf(context).scale(20) * 1.3,
    );
  }
}

/// A decade's own home page: its biggest movies up top, then the best, top genres and each year.
class LookbackView extends StatefulWidget {
  const LookbackView({super.key, required this.decade});
  final int decade;
  @override
  State<LookbackView> createState() => _LookbackViewState();
}

class _LookbackViewState extends State<LookbackView> {
  final catalog = Catalog.instance;
  late Future<void> loading = catalog.loadDecade(widget.decade);

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: loading,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: Swirl());
      }
      final d = widget.decade;
      final all = catalog.playable(catalog.decade(d));
      if (all.isEmpty) {
        return Padding(
          padding: EdgeInsets.fromLTRB(gutter(context), 140, 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Couldn’t load the ${d}s.', style: text(16, color: muted)),
              const SizedBox(height: 20),
              Pill(label: 'Try again', primary: true, onTap: () => setState(() => loading = catalog.loadDecade(d))),
            ],
          ),
        );
      }
      final heroes = Catalog.wide(all, const {}, 5);
      if (heroes.isEmpty) heroes.add(all.first);
      final lead = heroes.map((m) => str(m, 'id')).toSet();
      final counts = <String, int>{};
      for (final m in all) {
        for (final g in genres(m)) {
          counts[g] = (counts[g] ?? 0) + 1;
        }
      }
      final topGenres = (counts.entries.where((e) => e.value >= 8).toList()..sort((a, b) => b.value.compareTo(a.value))).take(6).map((e) => e.key);
      Future<void> open(Meta m) async {
        await openDetail(context, m);
        if (mounted) setState(() {});
      }

      // Each row prefers titles no earlier row has shown, topping up with repeats only when short.
      final used = <String>{...lead};
      Shelf shelf(String title, Iterable<Meta> items) {
        final fresh = items.where((m) => !used.contains(str(m, 'id'))).take(20).toList();
        if (fresh.length < 10) fresh.addAll(items.where((m) => !fresh.contains(m)).take(10 - fresh.length));
        used.addAll(fresh.map((m) => str(m, 'id')));
        return Shelf(title: title, items: fresh, filter: false, onOpen: open);
      }

      final rng = Catalog.daily(d + 1);
      final ratedScore = {for (final m in all) str(m, 'id'): Catalog.rating(m) + rng.nextDouble() * .8};
      final rated = all.where((m) => Catalog.rating(m) >= 7.5).toList()..sort((a, b) => ratedScore[str(b, 'id')]!.compareTo(ratedScore[str(a, 'id')]!));
      final order = {for (var i = 0; i < all.length; i++) str(all[i], 'id'): i};
      List<Meta> year(int y) => catalog.playable(catalog.releasedIn(y))..sort((a, b) => (order[str(a, 'id')] ?? all.length).compareTo(order[str(b, 'id')] ?? all.length));
      final shelves = [
        shelf('Best of the ${d}s', all.where((m) => !lead.contains(str(m, 'id')))),
        shelf('Highest Rated', rated),
        for (final g in topGenres) shelf(g, all.where((m) => genres(m).contains(g))),
        for (var y = d; y < d + 10; y++) shelf('$y', year(y)),
      ].where((s) => s.items.isNotEmpty).toList();
      return RemoteBrowseList(
        hero: HeroBanner(items: heroes, key: ValueKey('hero-lookback-$d')),
        shelves: shelves,
        shelfExtras: [for (final _ in shelves) 0.0],
        heroExtent: (MediaQuery.sizeOf(context).height * .64).clamp(440.0, 720.0),
        shelfExtent: posterWidth(context) * 1.48 + 94 + MediaQuery.textScalerOf(context).scale(20) * 1.3,
      );
    },
  );
}

class LibraryView extends StatefulWidget {
  const LibraryView({super.key});
  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  @override
  Widget build(BuildContext context) {
    final list = Catalog.instance.library();
    return ListView(
      padding: EdgeInsets.fromLTRB(0, 110, 0, 60),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter(context)),
          child: Text('My List', style: text(34, weight: FontWeight.w500)),
        ),
        const SizedBox(height: 18),
        if (list.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter(context)),
            child: Text('Nothing saved yet.', style: text(16, color: muted)),
          )
        else
          PosterGrid(items: list, onOpen: (m) => openDetail(context, m).then((_) => setState(() {}))),
      ],
    );
  }
}

/// Featured titles: up to five, swipeable with arrows, dots, keyboard, or automatically when idle.
class HeroBanner extends StatefulWidget {
  const HeroBanner({super.key, required this.items});
  final List<Meta> items;
  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  int index = 0;
  bool hovering = false;
  Timer? timer;
  final playFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 9), (_) {
      if (mounted && TickerMode.getValuesNotifier(context).value.enabled && !hovering && Activity.idleFor(8000) && widget.items.length > 1) {
        show(index + 1);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prefetch();
  }

  @override
  void dispose() {
    timer?.cancel();
    playFocus.dispose();
    super.dispose();
  }

  void _prefetch() {
    final size = MediaQuery.sizeOf(context), ratio = MediaQuery.devicePixelRatioOf(context);
    for (final offset in [0, 1]) {
      final m = widget.items[(index + offset) % widget.items.length];
      final url = str(m, 'background');
      if (url.startsWith('https://')) {
        precacheImage(artworkProvider(url, size.width, ratio), context).catchError((_) {});
      }
    }
  }

  void show(int i) {
    setState(() => index = (i % widget.items.length + widget.items.length) % widget.items.length);
    _prefetch();
  }

  KeyEventResult _edge(KeyEvent e, LogicalKeyboardKey key, int step) {
    if (e.logicalKey != key || widget.items.length < 2) {
      return KeyEventResult.ignored;
    }
    if (e is KeyDownEvent || e is KeyRepeatEvent) show(index + step);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.items[index];
    final many = widget.items.length > 1;
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: HeroFrame(
        meta: m,
        actions: [
          Pill(
            icon: Icons.play_arrow_rounded,
            primary: true,
            focusNode: playFocus,
            autofocus: true,
            tooltip: 'Play',
            onKey: (e) => _edge(e, LogicalKeyboardKey.arrowLeft, -1),
            onTap: () => str(m, 'type') == 'series' ? openDetail(context, m) : play(context, m, str(m, 'id')),
          ),
          const SizedBox(width: 14),
          Pill(icon: Icons.info_outline_rounded, tooltip: 'More info', onKey: (e) => _edge(e, LogicalKeyboardKey.arrowRight, 1), onTap: () => openDetail(context, m)),
        ],
        footer: many
            ? Row(
                children: [
                  for (var i = 0; i < widget.items.length; i++)
                    GestureDetector(
                      onTap: () => show(i),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.only(right: 6),
                            width: i == index ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(color: i == index ? green : const Color(0x59f4f8f1), borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : null,
        overlay: many && hovering
            ? [
                Positioned(
                  left: railWidth + 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeroArrow(icon: Icons.chevron_left, onTap: () => show(index - 1)),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeroArrow(icon: Icons.chevron_right, onTap: () => show(index + 1)),
                  ),
                ),
              ]
            : const [],
      ),
    );
  }
}

class _HeroArrow extends StatelessWidget {
  const _HeroArrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ExcludeFocus(
    child: Lift(
      onTap: onTap,
      builder: (context, active) => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: active ? white : const Color(0x99121c15), shape: BoxShape.circle),
        child: Icon(icon, size: 30, color: active ? ink : white),
      ),
    ),
  );
}

/// Backdrop, title, metadata and actions shared by the browse carousel and the details page.
class HeroFrame extends StatelessWidget {
  const HeroFrame({super.key, required this.meta, required this.actions, this.footer, this.overlay = const [], this.details = false, this.eyebrow, this.infoOverride, this.descriptionLines});
  final String? eyebrow, infoOverride;
  final int? descriptionLines;
  final Meta meta;
  final List<Widget> actions;
  final Widget? footer;
  final List<Widget> overlay;
  final bool details;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = (size.height * (details ? .66 : .64)).clamp(440.0, 720.0);
    final g = genres(meta);
    final genre = g.isNotEmpty ? g.first : (str(meta, 'type') == 'series' ? 'Series' : 'Movie');
    final rating = str(meta, 'imdbRating');
    final info = [
      str(meta, 'releaseInfo').isEmpty ? str(meta, 'year') : str(meta, 'releaseInfo'),
      genre,
      if (rating.isNotEmpty) 'IMDb $rating',
      if (details && str(meta, 'runtime').isNotEmpty) str(meta, 'runtime'),
    ].where((s) => s.isNotEmpty).join('   •   ');
    final copyWidth = (size.width * .42).clamp(380.0, 620.0);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xff142d19), ink], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Artwork(str(meta, 'background'), key: ValueKey(str(meta, 'background')), width: size.width, radius: 0, alignment: Alignment.topCenter),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xff070c09), Color(0xee070c09), Color(0x80070c09), Color(0x10070c09)], stops: [0, .3, .62, 1]),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 300,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00070c09), Color(0x70070c09), ink]),
              ),
            ),
          ),
          Positioned(
            left: gutter(context),
            bottom: details ? 48 : 40,
            width: copyWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Only the copy cross-fades; the actions stay mounted so a remote's focus survives the carousel turning.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
                  child: Column(
                    key: ValueKey(str(meta, 'id')),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (eyebrow != null) ...[
                        Text(
                          eyebrow!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text(12, color: green, weight: FontWeight.w500),
                        ),
                        const SizedBox(height: 10),
                      ],
                      SizedBox(
                        height: 58,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(str(meta, 'name'), maxLines: 1, style: text(46, weight: FontWeight.w500, spacing: -1.4)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(infoOverride ?? info, style: text(13, color: const Color(0xffcad5c9))),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: details ? null : 70,
                        child: Text(
                          str(meta, 'description'),
                          maxLines: descriptionLines ?? (details ? 5 : 3),
                          overflow: TextOverflow.ellipsis,
                          style: text(15, color: const Color(0xffbcc8bc), height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                FocusTraversalGroup(child: Row(children: actions)),
                if (footer != null) ...[const SizedBox(height: 14), footer!],
              ],
            ),
          ),
          ...overlay,
        ],
      ),
    );
  }
}
