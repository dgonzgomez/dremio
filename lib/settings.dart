import 'package:flutter/material.dart';

import 'browse.dart';
import 'letterboxd.dart';
import 'main.dart';
import 'orbit.dart';
import 'store.dart';
import 'streams.dart';
import 'theme.dart';
import 'update.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final store = Store.instance;
  final link = TextEditingController();
  bool checking = false, updating = false;
  String? editing;
  String feedback = '', version = '', updateStatus = '';
  Release? available;
  double? progress;

  final lb = Letterboxd.instance;
  final lbName = TextEditingController();

  /// 'me' while linking your account, 'friend' while adding one.
  String? lbEditing;
  String lbFeedback = '';
  bool lbBusy = false;

  void lbEdit(String? mode) => setState(() {
    lbEditing = mode;
    lbFeedback = '';
    lbName.clear();
  });

  Future<void> lbSubmit() async {
    var name = lbName.text.trim().replaceFirst(RegExp(r'^https?://(www\.)?letterboxd\.com/'), '').replaceFirst('@', '');
    name = name.split('/').first;
    if (!Letterboxd.validUsername(name)) {
      setState(() => lbFeedback = 'That isn’t a Letterboxd username.');
      return;
    }
    setState(() {
      lbBusy = true;
      lbFeedback = 'Checking…';
    });
    try {
      lbEditing == 'me' ? await lb.link(name) : await lb.addFriend(name);
      if (!mounted) return;
      lbBusy = false;
      lbEdit(null);
    } catch (e) {
      if (mounted) {
        setState(() {
          lbBusy = false;
          lbFeedback = e is LetterboxdMissing ? 'No public Letterboxd profile called $name.' : 'Couldn’t reach Letterboxd.';
        });
      }
    }
  }

  Future<void> lbImport() async {
    setState(() {
      lbBusy = true;
      lbFeedback = 'Bringing in who you follow…';
    });
    try {
      final added = await lb.importFollowing();
      if (mounted) setState(() => lbFeedback = added == 0 ? 'No one new to add.' : 'Added $added ${added == 1 ? 'friend' : 'friends'}.');
    } catch (_) {
      if (mounted) setState(() => lbFeedback = 'Couldn’t reach Letterboxd.');
    }
    if (mounted) setState(() => lbBusy = false);
  }

  List<Widget> _letterboxd() {
    final me = lb.me;
    return [
      const SizedBox(height: 34),
      Text('Letterboxd', style: text(13, color: muted)),
      const SizedBox(height: 12),
      if (me != null) ...[
        Row(
          children: [
            Avatar(me, size: 36),
            const SizedBox(width: 12),
            Flexible(child: Text('${me.name}  ·  @${me.username}', style: text(15))),
          ],
        ),
        const SizedBox(height: 14),
      ],
      if (lbEditing != null) ...[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(color: const Color(0xff1b2b20), borderRadius: BorderRadius.circular(14)),
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: lbName,
              autofocus: true,
              autocorrect: false,
              cursorColor: green,
              style: text(14),
              decoration: InputDecoration.collapsed(
                hintText: lbEditing == 'me' ? 'Your Letterboxd username' : 'Friend’s Letterboxd username',
                hintStyle: text(14, color: muted),
              ),
              onSubmitted: (_) => lbSubmit(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Pill(label: lbEditing == 'me' ? 'Link' : 'Add', primary: true, height: 42, onTap: lbBusy ? () {} : lbSubmit),
            const SizedBox(width: 12),
            Pill(label: 'Cancel', height: 42, onTap: () => lbEdit(null)),
          ],
        ),
      ] else
        Row(
          children: [
            if (me == null)
              Pill(label: 'Link account', height: 42, onTap: () => lbEdit('me'))
            else ...[
              Pill(label: 'Add friend', height: 42, onTap: () => lbEdit('friend')),
              const SizedBox(width: 12),
              Pill(label: 'Import who I follow', height: 42, onTap: lbBusy ? () {} : lbImport),
              const SizedBox(width: 12),
              Pill(
                label: 'Unlink',
                height: 42,
                onTap: () async {
                  if (await confirm('Unlink Letterboxd?', 'Unlink')) setState(lb.unlink);
                },
              ),
            ],
          ],
        ),
      if (lbFeedback.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(lbFeedback, style: text(13, color: muted)),
        ),
      if (me != null && lb.friends.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('Friends  ·  select one to remove it', style: text(13, color: muted)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final f in lb.friends)
              Pill(
                label: f.name,
                height: 38,
                onTap: () async {
                  if (await confirm('Remove ${f.name} from your orbit?', 'Remove')) setState(() => lb.removeFriend(f.username));
                },
              ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      Text('Your diary needs to be public. Dremio only reads it; logging and rating happen on Letterboxd.', style: text(12, color: muted)),
    ];
  }

  @override
  void initState() {
    super.initState();
    if (!store.hasSource) editing = sources.first.id;
    currentVersion().then((v) {
      if (mounted) setState(() => version = v);
    });
    lastUpdateFailure().then((reason) {
      if (reason != null && mounted) {
        setState(() => updateStatus = 'The last update didn’t finish ($reason). Try again or download it from GitHub.');
      }
    });
  }

  Future<void> checkForUpdate() async {
    setState(() {
      updating = true;
      available = null;
      updateStatus = 'Checking…';
    });
    try {
      final release = await latestRelease();
      if (!mounted) return;
      setState(() {
        updating = false;
        if (!isNewer(release.version, version)) {
          updateStatus = 'You’re up to date.';
        } else if (release.download == null) {
          updateStatus = 'Version ${release.version} is out, but not for this device yet.';
        } else {
          available = release;
          updateStatus = 'Version ${release.version} is available.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          updating = false;
          updateStatus = 'Couldn’t reach GitHub.';
        });
      }
    }
  }

  Future<void> applyUpdate(Release release) async {
    setState(() {
      updating = true;
      progress = 0;
      updateStatus = 'Downloading ${release.version}…';
    });
    try {
      final file = await download(release.download!, (p) {
        if (mounted) setState(() => progress = p);
      });
      if (mounted) setState(() => progress = null);
      final message = await install(file, release.version);
      if (mounted) {
        setState(() {
          updating = false;
          updateStatus = message ?? 'Restarting…';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          updating = false;
          progress = null;
          updateStatus = e is UpdateError ? e.message : 'The update didn’t finish. Try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    link.dispose();
    lbName.dispose();
    super.dispose();
  }

  void edit(String? id) => setState(() {
    editing = id;
    feedback = '';
    link.clear();
  });

  Future<void> save(Source source) async {
    final value = link.text.trim();
    if (!source.accepts(value)) {
      setState(() => feedback = 'That isn’t a ${source.name} manifest link.');
      return;
    }
    setState(() {
      checking = true;
      feedback = 'Checking…';
    });
    try {
      await checkManifest(source, value);
      await store.saveSource(source.id, value);
      if (!mounted) return;
      checking = false;
      edit(null);
    } catch (_) {
      if (mounted) {
        setState(() {
          checking = false;
          feedback = 'Couldn’t connect.';
        });
      }
    }
  }

  Future<bool> confirm(String title, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title, style: text(18, weight: FontWeight.w500)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: text(14, color: muted)),
            ),
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action, style: text(14, color: green)),
            ),
          ],
        ),
      ) ??
      false;

  List<Widget> _source(Source source) {
    final connected = store.connected(source.id), isDefault = connected && store.defaultSource == source.id;
    return [
      const SizedBox(height: 18),
      Text(
        '${source.name}  ·  ${!connected
            ? 'not connected'
            : isDefault
            ? 'connected, default'
            : 'connected'}',
        style: text(15, color: isDefault ? green : white),
      ),
      const SizedBox(height: 10),
      if (editing == source.id) ...[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(color: const Color(0xff1b2b20), borderRadius: BorderRadius.circular(14)),
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: link,
              autofocus: true,
              obscureText: true,
              cursorColor: green,
              style: text(14),
              decoration: InputDecoration.collapsed(
                hintText: source.hint,
                hintStyle: text(14, color: muted),
              ),
              onSubmitted: (_) => save(source),
            ),
          ),
        ),
        if (feedback.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(feedback, style: text(13, color: muted)),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Pill(label: 'Save', primary: true, height: 42, onTap: checking ? () {} : () => save(source)),
            if (store.hasSource) ...[const SizedBox(width: 12), Pill(label: 'Cancel', height: 42, onTap: () => edit(null))],
          ],
        ),
      ] else
        Row(
          children: [
            if (!connected)
              Pill(label: 'Connect', height: 42, onTap: () => edit(source.id))
            else ...[
              Pill(label: isDefault ? 'Default' : 'Make default', primary: isDefault, height: 42, onTap: () => setState(() => store.defaultSource = source.id)),
              const SizedBox(width: 12),
              Pill(label: 'Replace', height: 42, onTap: () => edit(source.id)),
              const SizedBox(width: 12),
              Pill(
                label: 'Remove',
                height: 42,
                onTap: () async {
                  if (await confirm('Remove ${source.name}?', 'Remove')) {
                    await store.clearSource(source.id);
                    if (mounted) edit(store.hasSource ? null : sources.first.id);
                  }
                },
              ),
            ],
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Screen(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(gutter(context), 110, gutter(context), 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings', style: text(34, weight: FontWeight.w500)),
            const SizedBox(height: 26),
            Text('Sources', style: text(13, color: muted)),
            for (final source in sources) ..._source(source),
            ..._letterboxd(),
            const SizedBox(height: 34),
            Text('Resolution', style: text(13, color: muted)),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final q in ['4K', '1080p', '720p', '480p']) ...[
                  Pill(label: q, primary: store.resolution == q, height: 42, onTap: () => setState(() => store.resolution = q)),
                  const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 34),
            Text('HDR', style: text(13, color: muted)),
            const SizedBox(height: 10),
            Row(
              children: [
                Pill(label: 'On', primary: store.hdr, height: 42, onTap: () => setState(() => store.hdr = true)),
                const SizedBox(width: 12),
                Pill(label: 'Off', primary: !store.hdr, height: 42, onTap: () => setState(() => store.hdr = false)),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(store.hdr ? 'HDR sources are allowed.' : 'HDR sources are skipped.', style: text(13, color: muted)),
                ),
              ],
            ),
            const SizedBox(height: 34),
            Text('Data Saver', style: text(13, color: muted)),
            const SizedBox(height: 10),
            Row(
              children: [
                Pill(label: 'On', primary: store.dataSaver, height: 42, onTap: () => setState(() => store.dataSaver = true)),
                const SizedBox(width: 12),
                Pill(label: 'Off', primary: !store.dataSaver, height: 42, onTap: () => setState(() => store.dataSaver = false)),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    store.dataSaver ? 'Prefers files under ${dataSaverGb.toInt()} GB, so playback starts faster.' : 'Picks the best match regardless of file size.',
                    style: text(13, color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 34),
            Text(version.isEmpty ? 'Updates' : 'Updates  ·  version $version', style: text(13, color: muted)),
            const SizedBox(height: 10),
            Row(
              children: [
                if (available case final release?)
                  Pill(label: 'Update to ${release.version}', primary: true, onTap: updating ? () {} : () => applyUpdate(release))
                else
                  Pill(label: 'Check for updates', onTap: updating ? () {} : checkForUpdate),
                if (updateStatus.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(updateStatus, style: text(13, color: muted)),
                  ),
                ],
              ],
            ),
            if (progress != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: LinearProgressIndicator(value: progress, minHeight: 4, color: green, backgroundColor: const Color(0x40f4f8f1), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            const SizedBox(height: 34),
            Align(
              alignment: Alignment.centerLeft,
              child: Pill(
                label: 'Reset my list',
                onTap: () async {
                  if (await confirm('Reset your list and preferences?', 'Reset')) {
                    await store.reset();
                    currentPage.value = 'Home';
                    navigatorKey.currentState?.popUntil((r) => r.isFirst);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
