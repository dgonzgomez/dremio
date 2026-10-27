import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'browse.dart';
import 'catalog.dart';
import 'letterboxd.dart';
import 'remote_navigation.dart';
import 'routes.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

Meta _note(Meta m, String note, [String avatar = '']) => {...m, posterNoteKey: note, posterAvatarKey: avatar};

/// Drops poster notes before a title is opened, so they're never remembered with it.
Meta _clean(Meta m) => Map.of(m)
  ..remove(posterNoteKey)
  ..remove(posterAvatarKey);

String _day(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}';
}

/// Opens a Letterboxd page: in the browser on desktop, as a QR code to scan with a phone on the TV.
Future<void> openLetterboxd(BuildContext context, Uri uri, {String? title}) async {
  if (!Platform.isAndroid) {
    try {
      if (await launchUrl(uri)) return;
    } catch (_) {}
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xff101a13),
      title: Text(title ?? 'Open on Letterboxd', style: text(18, weight: FontWeight.w500)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: white, borderRadius: BorderRadius.circular(14)),
            child: QrImageView(data: uri.toString(), size: 210, padding: EdgeInsets.zero),
          ),
          const SizedBox(height: 14),
          Text('Scan with your phone to open it in Letterboxd.', style: text(13, color: muted)),
        ],
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: Text('Done', style: text(14, color: green)),
        ),
      ],
    ),
  );
}

/// After a movie plays to the end: offer to log and rate it on Letterboxd.
Future<void> promptLog(BuildContext context, Meta meta) async {
  final lb = Letterboxd.instance;
  if (!lb.linked || str(meta, 'type') != 'movie') return;
  final title = str(meta, 'name');
  final log = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xff101a13),
      title: Text('You finished $title', style: text(18, weight: FontWeight.w500)),
      content: Text('Log it and give it a rating on Letterboxd?', style: text(14, color: muted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Not now', style: text(14, color: muted)),
        ),
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, true),
          child: Text('Log it', style: text(14, color: green)),
        ),
      ],
    ),
  );
  if (log == true && context.mounted) await openLetterboxd(context, Letterboxd.film(str(meta, 'id')), title: 'Log $title');
}

class Avatar extends StatelessWidget {
  const Avatar(this.member, {super.key, this.size = 30});
  final Member? member;
  final double size;
  @override
  Widget build(BuildContext context) {
    final url = member?.avatar ?? '';
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Color(0xff1b2b20), shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url.isEmpty
          ? Text(
              (member?.name.isNotEmpty ?? false) ? member!.name.characters.first.toUpperCase() : '?',
              style: text(size * .45, weight: FontWeight.w600, color: green),
            )
          : Artwork(url, width: size, radius: size / 2),
    );
  }
}

Shelf _shelf(BuildContext context, String title, List<Meta> items, Future<void> Function(Meta) open) => Shelf(title: title, items: items.take(20).toList(), filter: false, onOpen: open);

double _shelfExtent(BuildContext context) => shelfRowExtent(context, extra: true);

/// A page header in place of a hero: big title, a line under it, and optional buttons.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle, this.leading, this.actions = const []});
  final String title, subtitle;
  final Widget? leading;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(gutter(context), 96, gutter(context), 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 24)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text(34, weight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: text(14, color: muted)),
              if (actions.isNotEmpty) ...[const SizedBox(height: 18), Row(children: actions)],
            ],
          ),
        ),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.title, this.body, [this.actions = const []]);
  final String title, body;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(gutter(context), 120, gutter(context), 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text(34, weight: FontWeight.w500)),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(body, style: text(15, color: muted)),
        ),
        const SizedBox(height: 24),
        Row(children: actions),
      ],
    ),
  );
}

class _OrbitData {
  _OrbitData(this.recent, this.blends);
  final List<Meta> recent;
  final List<(Blend, List<Meta>)> blends;
}

/// What your Letterboxd friends have been watching, and how your taste blends with each of them.
class OrbitView extends StatefulWidget {
  const OrbitView({super.key});
  @override
  State<OrbitView> createState() => _OrbitViewState();
}

class _OrbitViewState extends State<OrbitView> {
  final lb = Letterboxd.instance;
  late Future<_OrbitData?> loading = _load();
  bool importing = false;

  /// TMDB ids of films played in Dremio, so blends don't suggest them.
  Set<String> _played() {
    final store = Store.instance;
    return {
      for (final k in store.keys())
        if (k.startsWith('lb:tmdb:') && store.getInt('played:${store.getString(k)}') > 0) k.substring(8),
    };
  }

  Future<_OrbitData?> _load({bool fresh = false}) async {
    if (!lb.linked || lb.friends.isEmpty) return null;
    Future<List<DiaryEntry>> feed(String user) => lb.diary(user, fresh: fresh).catchError((Object _) => <DiaryEntry>[]);
    final friends = lb.friends;
    final mine = await feed(lb.user);
    final feeds = await Future.wait(friends.map((f) => feed(f.username)));
    final byUser = {for (final f in friends) f.username: f};

    final seen = <String>{};
    final recent = (feeds.expand((f) => f).toList()..sort((a, b) => b.watched.compareTo(a.watched))).where((e) => seen.add(e.tmdb)).take(30).toList();
    final recentMetas = [
      for (final (e, m) in await lb.metas(recent)) _note(m, '${byUser[e.user]?.name ?? e.user}${e.rating != null ? '  ${stars(e.rating!)}' : ''}${e.liked ? '  ♥' : ''}', byUser[e.user]?.avatar ?? ''),
    ];

    final played = _played();
    final blends = <(Blend, List<Meta>)>[];
    for (var i = 0; i < friends.length; i++) {
      if (feeds[i].isEmpty) continue;
      final b = Letterboxd.blend(friends[i], mine, feeds[i], played);
      final picks = [
        for (final (e, m) in await lb.metas(b.forYou.take(16).toList())) _note(m, '${friends[i].name} ${e.rating != null ? stars(e.rating!) : '♥'}', friends[i].avatar),
        for (final (_, m) in await lb.metas(b.bothLoved.take(8).toList())) _note(m, 'You both loved it', friends[i].avatar),
      ];
      if (picks.isNotEmpty) blends.add((b, picks));
    }
    blends.sort((a, b) => (b.$1.match ?? -1).compareTo(a.$1.match ?? -1));
    return _OrbitData(recentMetas, blends);
  }

  Future<void> _open(Meta m) async {
    await openDetail(context, _clean(m));
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    setState(() => importing = true);
    try {
      await lb.importFollowing();
    } catch (_) {}
    if (mounted) {
      setState(() {
        importing = false;
        loading = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!lb.linked) {
      return _Message('Orbit', 'Link your Letterboxd account to see what your friends are watching and how your taste blends with theirs.', [
        Pill(label: 'Link Letterboxd', primary: true, autofocus: true, onTap: () => openSettings(context)),
      ]);
    }
    if (lb.friends.isEmpty) {
      return _Message('Orbit', importing ? 'Bringing in who you follow…' : 'Add friends to fill your orbit: bring in who you follow on Letterboxd, or add people by username in Settings.', [
        Pill(label: importing ? 'Importing…' : 'Import who I follow', primary: true, autofocus: true, onTap: importing ? () {} : _import),
        const SizedBox(width: 12),
        Pill(label: 'Settings', onTap: () => openSettings(context)),
      ]);
    }
    return FutureBuilder<_OrbitData?>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: Swirl());
        final data = snapshot.data;
        if (data == null || (data.recent.isEmpty && data.blends.isEmpty)) {
          return _Message('Orbit', 'Nothing from your friends yet. Their diaries need to be public on Letterboxd.', [
            Pill(label: 'Refresh', primary: true, autofocus: true, onTap: () => setState(() => loading = _load(fresh: true))),
          ]);
        }
        final heroes = Catalog.wide(data.recent.map(_clean).toList(), const {}, 5);
        final shelves = [
          if (data.recent.isNotEmpty) _shelf(context, 'Friends are watching', data.recent, _open),
          for (final (b, picks) in data.blends) _shelf(context, 'Blend with ${b.friend.name}  ·  ${b.match != null ? '${b.match}% match' : '${b.shared} in common'}', picks, _open),
        ];
        return RemoteBrowseList(
          hero: heroes.isEmpty ? _Header(title: 'Orbit', subtitle: 'What ${lb.friends.length} friends are watching') : HeroBanner(items: heroes, key: const ValueKey('hero-orbit')),
          shelves: shelves,
          shelfExtras: [for (final _ in shelves) 0.0],
          heroExtent: heroes.isEmpty ? 220 : (MediaQuery.sizeOf(context).height * .64).clamp(440.0, 720.0),
          shelfExtent: _shelfExtent(context),
        );
      },
    );
  }
}

/// Your profile: everything played in Dremio and your Letterboxd diary.
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});
  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final lb = Letterboxd.instance;
  late Future<List<(DiaryEntry, Meta)>> diary = lb.linked ? lb.diary(lb.user).then(lb.metas).catchError((Object _) => <(DiaryEntry, Meta)>[]) : Future.value(const []);

  List<Meta> _played() {
    final store = Store.instance;
    final ids = [
      for (final k in store.keys())
        if (k.startsWith('played:') && store.getInt(k) > 0) k.substring(7),
    ]..sort((a, b) => store.getInt('played:$b').compareTo(store.getInt('played:$a')));
    return [
      for (final id in ids)
        if (store.recalled(id) case final m?) _note(m, _day(DateTime.fromMillisecondsSinceEpoch(store.getInt('played:$id')))),
    ];
  }

  Future<void> _open(Meta m) async {
    await openDetail(context, _clean(m));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<(DiaryEntry, Meta)>>(
    future: diary,
    builder: (context, snapshot) {
      final me = lb.me;
      final played = _played();
      final logged = snapshot.data ?? const [];
      final loading = snapshot.connectionState != ConnectionState.done;
      final shelves = [
        if (played.isNotEmpty) _shelf(context, 'Played in Dremio', played, _open),
        if (logged.isNotEmpty)
          _shelf(context, 'Letterboxd diary', [for (final (e, m) in logged) _note(m, '${_day(e.watched)}${e.rating != null ? '  ${stars(e.rating!)}' : ''}${e.liked ? '  ♥' : ''}')], _open),
        if (logged.any((p) => p.$1.loved)) _shelf(context, 'Favorites', [for (final (e, m) in logged.where((p) => p.$1.loved)) _note(m, e.rating != null ? stars(e.rating!) : '♥')], _open),
      ];
      final header = _Header(
        title: me?.name ?? 'History',
        subtitle: [if (me != null) '@${me.username}', '${played.length} played in Dremio', if (lb.linked) loading ? 'loading your diary…' : '${logged.length} recent diary entries'].join('  ·  '),
        leading: me == null ? null : Avatar(me, size: 84),
        actions: [
          if (me != null)
            Pill(
              label: 'Open on Letterboxd',
              onTap: () => openLetterboxd(context, Letterboxd.profileUrl(me.username), title: me.name),
            )
          else
            Pill(label: 'Link Letterboxd', primary: true, onTap: () => openSettings(context)),
        ],
      );
      if (shelves.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter(context)),
              child: loading ? const Swirl() : Text('Nothing here yet. Movies you play show up here.', style: text(15, color: muted)),
            ),
          ],
        );
      }
      return RemoteBrowseList(hero: header, shelves: shelves, shelfExtras: [for (final _ in shelves) 0.0], heroExtent: 300, shelfExtent: _shelfExtent(context));
    },
  );
}
