import 'package:flutter/material.dart';

import 'detail.dart';
import 'main.dart';
import 'player.dart';
import 'search.dart';
import 'settings.dart';
import 'store.dart';

Future<void> openDetail(BuildContext context, Meta m) => navigatorKey.currentState!.push(fade(DetailPage(meta: m)));

Future<void> openSearch(BuildContext context) {
  final nav = navigatorKey.currentState!;
  return nav.push(fade(const SearchPage()));
}

Future<void> openSettings(BuildContext context) => navigatorKey.currentState!.push(fade(const SettingsPage()));

Future<void> play(BuildContext context, Meta m, String video) async {
  if (video.isEmpty) return openDetail(context, m);
  final store = Store.instance;
  if (store.connection.isEmpty) return openSettings(context);
  store.remember(m);
  store.learn(m);
  await navigatorKey.currentState!.push(fade(PlayerPage(meta: m, video: video)));
}
