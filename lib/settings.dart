import 'package:flutter/material.dart';

import 'browse.dart';
import 'main.dart';
import 'store.dart';
import 'streams.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final store = Store.instance;
  final link = TextEditingController();
  bool editing = false, checking = false;
  String feedback = '';

  @override
  void initState() {
    super.initState();
    editing = store.connection.isEmpty;
  }

  @override
  void dispose() {
    link.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final value = link.text.trim();
    if (!validDebridioLink(value)) {
      setState(() => feedback = 'Invalid link.');
      return;
    }
    setState(() {
      checking = true;
      feedback = 'Checking…';
    });
    try {
      await checkManifest(value);
      await store.saveConnection(value);
      if (!mounted) return;
      setState(() {
        editing = false;
        checking = false;
        feedback = '';
        link.clear();
      });
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

  @override
  Widget build(BuildContext context) {
    final connected = store.connection.isNotEmpty;
    return Screen(
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter(context), 110, gutter(context), 60),
        children: [
          Text('Settings', style: text(34, weight: FontWeight.w500)),
          const SizedBox(height: 26),
          Text(connected ? 'Debridio connected' : 'Debridio not connected', style: text(15, color: muted)),
          const SizedBox(height: 14),
          if (editing) ...[
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
                    hintText: 'Paste your Debridio manifest link',
                    hintStyle: text(14, color: muted),
                  ),
                  onSubmitted: (_) => save(),
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
                Pill(label: 'Save connection', primary: true, onTap: checking ? () {} : save),
                if (connected) ...[const SizedBox(width: 14), Pill(label: 'Cancel', onTap: () => setState(() => editing = false))],
              ],
            ),
          ] else
            Row(
              children: [
                Pill(label: 'Replace connection', primary: true, onTap: () => setState(() => editing = true)),
                const SizedBox(width: 14),
                Pill(
                  label: 'Disconnect',
                  onTap: () async {
                    if (await confirm('Disconnect Debridio?', 'Disconnect')) {
                      await store.clearConnection();
                      setState(() => editing = true);
                    }
                  },
                ),
              ],
            ),
          const SizedBox(height: 34),
          Text('Resolution', style: text(13, color: muted)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final q in ['4K', '1080p', '720p', '480p']) ...[Pill(label: q, primary: store.resolution == q, height: 42, onTap: () => setState(() => store.resolution = q)), const SizedBox(width: 12)],
            ],
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
    );
  }
}
