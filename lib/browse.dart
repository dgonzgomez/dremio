import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'artwork_cache.dart';
import 'catalog.dart';
import 'remote_navigation.dart';
import 'main.dart';
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
          const Positioned(left: 0, right: 0, top: 0, child: NavBar()),
        ],
      ),
    ),
  );
}

class NavBar extends StatelessWidget {
  const NavBar({super.key});

  void _tab(BuildContext context, String tab) {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    currentPage.value = tab;
  }

  @override
  Widget build(BuildContext context) {
    final mac = Platform.isMacOS;
    final bar = Container(
      height: 124,
      padding: EdgeInsets.fromLTRB(
        mac ? 92 : gutter(context),
        mac ? 18 : 14,
        gutter(context),
        0,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.55, 1],
          colors: [Color(0xf5070c09), Color(0xd9070c09), Color(0x00070c09)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (Navigator.of(context).canPop()) ...[
                    Pill(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back  (Esc)',
                      height: 40,
                      onTap: goBack,
                    ),
                    const SizedBox(width: 18),
                  ],
                  GestureDetector(
                    onTap: () => _tab(context, 'Home'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Logo(size: 27),
                        const SizedBox(width: 9),
                        Text(
                          'dremio',
                          style: text(24, weight: FontWeight.w500, spacing: -1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ValueListenableBuilder<String>(
            valueListenable: currentPage,
            builder: (context, page, _) {
              final onBrowse = !(navigatorKey.currentState?.canPop() ?? false);
              return Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xb51b251e),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: const Color(0x354d6851)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final tab in ['Home', 'Movies', 'Series', 'My List'])
                      Lift(
                        scale: 1.03,
                        onTap: () => _tab(context, tab),
                        builder: (context, active) {
                          final selected = page == tab && onBrowse;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: active
                                  ? white
                                  : (selected ? green : Colors.transparent),
                              borderRadius: BorderRadius.circular(21),
                            ),
                            child: Text(
                              tab,
                              style: text(
                                13,
                                weight: FontWeight.w500,
                                color: active || selected
                                    ? ink
                                    : const Color(0xffb9c5ba),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Pill(
                    icon: Icons.search,
                    tooltip: 'Search  (⌘F)',
                    height: 40,
                    onTap: () => openSearch(context),
                  ),
                  const SizedBox(width: 10),
                  Pill(
                    icon: Icons.settings_outlined,
                    tooltip: 'Settings',
                    height: 40,
                    onTap: () => openSettings(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return mac ? DragToMoveArea(child: bar) : bar;
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
            Pill(
              label: 'Try again',
              primary: true,
              onTap: () =>
                  catalog.refresh(force: true).then((_) => setState(() {})),
            ),
          ],
        ),
      );
    }
    final heroes = catalog.heroes(type);
    if (heroes.isEmpty) heroes.add(pool.first);
    final lead = heroes.map((m) => str(m, 'id')).toSet();
    final recommended = catalog
        .ranked(pool, 'picks${widget.page}')
        .where((m) => !lead.contains(str(m, 'id')))
        .toList();
    final fresh = '/year/genre=${catalog.year}';
    final c = catalog.catalog;
    final mix = Catalog.mix;
    final decent = Catalog.decent;
    Future<void> open(Meta m) async {
      await openDetail(context, m);
      if (mounted) setState(() {});
    }

    Widget shelf(
      String title,
      List<Meta> items, {
      bool filter = true,
      bool continueWatching = false,
    }) {
      final visible = (filter ? catalog.playable(items) : items)
          .take(20)
          .toList();
      return visible.isEmpty
          ? const SizedBox.shrink()
          : Shelf(
              title: title,
              items: visible,
              filter: false,
              continueWatching: continueWatching,
              onOpen: continueWatching
                  ? (m) async {
                      await openDetail(
                        context,
                        m,
                        resumeVideo: Store.instance.progress(m).videoId,
                      );
                      if (mounted) setState(() {});
                    }
                  : open,
            );
    }

    final rows = <Widget>[
      if (type == null)
        shelf(
          'Continue Watching',
          catalog.continueWatching(),
          filter: false,
          continueWatching: true,
        ),
      shelf(type == null ? 'Recommended for You' : 'Recommended', recommended),
      if (type == null) ...[
        shelf(
          'Trending Today',
          decent(mix(c('movie/x-trending'), c('series/x-trending'))),
        ),
        shelf('Popular Movies', c('movie/top')),
        shelf('Popular Series', c('series/top')),
        shelf('This Week', mix(c('movie/x-week'), c('series/x-week'))),
        shelf('New Releases', mix(c('movie$fresh'), c('series$fresh'))),
        shelf(
          'Fresh Picks',
          decent(mix(c('movie/x-fresh'), c('series/x-fresh'))),
        ),
        shelf('Top Rated', mix(c('movie/imdbRating'), c('series/imdbRating'))),
        for (final s in services)
          shelf(
            'On ${s[1]}',
            decent(mix(c('movie/x-${s[0]}'), c('series/x-${s[0]}'))),
          ),
      ] else ...[
        shelf('Trending Today', decent(c('$type/x-trending'))),
        shelf('Popular Now', c('$type/top')),
        shelf(
          type == 'movie' ? 'Most Watched This Week' : 'Popular This Week',
          c('$type/x-week'),
        ),
        shelf('New Releases', c('$type$fresh')),
        shelf(
          type == 'movie' ? 'Certified Fresh' : 'Best New Shows',
          decent(c('$type/x-fresh')),
        ),
        shelf('Top Rated', c('$type/imdbRating')),
        for (final s in services)
          shelf('On ${s[1]}', decent(c('$type/x-${s[0]}'))),
      ],
      for (final g in catalog.genreRows(type, type == null ? 2 : 4))
        shelf(
          g,
          type == null
              ? mix(c('movie/top/genre=$g'), c('series/top/genre=$g'))
              : c('$type/top/genre=$g'),
        ),
      const SizedBox(height: 60),
    ];

    return RemoteBrowseList(
      hero: HeroBanner(items: heroes, key: ValueKey('hero${widget.page}')),
      shelves: rows.whereType<Shelf>().toList(),
      shelfExtras: rows
          .whereType<Shelf>()
          .map((row) => row.continueWatching ? 20.0 : 0.0)
          .toList(),
      heroExtent: (MediaQuery.sizeOf(context).height * .64).clamp(440.0, 720.0),
      shelfExtent:
          posterWidth(context) * 1.48 +
          94 +
          MediaQuery.textScalerOf(context).scale(20) * 1.3,
    );
  }
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
          PosterGrid(
            items: list,
            onOpen: (m) => openDetail(context, m).then((_) => setState(() {})),
          ),
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
      if (mounted &&
          TickerMode.getValuesNotifier(context).value.enabled &&
          !hovering &&
          Activity.idleFor(8000) &&
          widget.items.length > 1) {
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
    final size = MediaQuery.sizeOf(context),
        ratio = MediaQuery.devicePixelRatioOf(context);
    for (final offset in [0, 1]) {
      final m = widget.items[(index + offset) % widget.items.length];
      final url = str(m, 'background');
      if (url.startsWith('https://')) {
        precacheImage(
          artworkProvider(url, size.width, ratio),
          context,
        ).catchError((_) {});
      }
    }
  }

  void show(int i) {
    setState(
      () => index =
          (i % widget.items.length + widget.items.length) % widget.items.length,
    );
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
            onTap: () => str(m, 'type') == 'series'
                ? openDetail(context, m)
                : play(context, m, str(m, 'id')),
          ),
          const SizedBox(width: 14),
          Pill(
            icon: Icons.info_outline_rounded,
            tooltip: 'More info',
            onKey: (e) => _edge(e, LogicalKeyboardKey.arrowRight, 1),
            onTap: () => openDetail(context, m),
          ),
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
                            decoration: BoxDecoration(
                              color: i == index
                                  ? green
                                  : const Color(0x59f4f8f1),
                              borderRadius: BorderRadius.circular(3),
                            ),
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
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeroArrow(
                      icon: Icons.chevron_left,
                      onTap: () => show(index - 1),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeroArrow(
                      icon: Icons.chevron_right,
                      onTap: () => show(index + 1),
                    ),
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
        decoration: BoxDecoration(
          color: active ? white : const Color(0x99121c15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 30, color: active ? ink : white),
      ),
    ),
  );
}

/// Backdrop, title, metadata and actions shared by the browse carousel and the details page.
class HeroFrame extends StatelessWidget {
  const HeroFrame({
    super.key,
    required this.meta,
    required this.actions,
    this.footer,
    this.overlay = const [],
    this.details = false,
    this.eyebrow,
    this.infoOverride,
    this.descriptionLines,
  });
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
    final genre = g.isNotEmpty
        ? g.first
        : (str(meta, 'type') == 'series' ? 'Series' : 'Movie');
    final rating = str(meta, 'imdbRating');
    final info = [
      str(meta, 'releaseInfo').isEmpty
          ? str(meta, 'year')
          : str(meta, 'releaseInfo'),
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
              gradient: LinearGradient(
                colors: [Color(0xff142d19), ink],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Artwork(
              str(meta, 'background'),
              key: ValueKey(str(meta, 'background')),
              width: size.width,
              radius: 0,
              alignment: Alignment.topCenter,
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xff070c09),
                  Color(0xee070c09),
                  Color(0x80070c09),
                  Color(0x10070c09),
                ],
                stops: [0, .3, .62, 1],
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 300,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00070c09), Color(0x70070c09), ink],
                ),
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
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.bottomLeft,
                    children: [...previous, ?current],
                  ),
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
                          style: text(
                            12,
                            color: green,
                            weight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      SizedBox(
                        height: 58,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            str(meta, 'name'),
                            maxLines: 1,
                            style: text(
                              46,
                              weight: FontWeight.w500,
                              spacing: -1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        infoOverride ?? info,
                        style: text(13, color: const Color(0xffcad5c9)),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: details ? null : 70,
                        child: Text(
                          str(meta, 'description'),
                          maxLines: descriptionLines ?? (details ? 5 : 3),
                          overflow: TextOverflow.ellipsis,
                          style: text(
                            15,
                            color: const Color(0xffbcc8bc),
                            height: 1.5,
                          ),
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
