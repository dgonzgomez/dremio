import 'package:flutter/material.dart';

import 'browse.dart';
import 'catalog.dart';
import 'net.dart';
import 'routes.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final input = TextEditingController();
  final inputFocus = FocusNode();
  List<Meta>? results;
  String status = '', query = '';
  bool tucked = false;
  int serial = 0;

  @override
  void initState() {
    super.initState();
    inputFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    input.dispose();
    inputFocus.dispose();
    super.dispose();
  }

  Future<void> search(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    final mine = ++serial;
    setState(() {
      query = q;
      status = 'Searching…';
      results = null;
    });
    final found = <Meta>[];
    var failed = false;
    for (final type in ['movie', 'series']) {
      try {
        final metas = (await getJson('$cinemeta/catalog/$type/top/search=${Uri.encodeComponent(q)}.json'))['metas'];
        for (final m in metas is List ? metas : const []) {
          if (m is Map) found.add(Map<String, dynamic>.from(m));
        }
      } catch (_) {
        failed = true;
      }
    }
    if (found.isEmpty && failed) found.addAll(Catalog.instance.all().where((m) => str(m, 'name').toLowerCase().contains(q.toLowerCase())));
    if (!mounted || mine != serial) return;
    setState(() {
      results = found;
      status = found.isEmpty ? (failed ? 'Search is offline.' : 'No results.') : '';
      tucked = found.isNotEmpty;
    });
  }

  void expand() {
    setState(() => tucked = false);
    inputFocus.requestFocus();
    input.selection = TextSelection(baseOffset: 0, extentOffset: input.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final focused = inputFocus.hasFocus;
    return Screen(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 104, 0, 60),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter(context)),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SizeTransition(sizeFactor: a, alignment: Alignment.topLeft, child: child),
                ),
                child: tucked
                    ? Lift(
                        key: const ValueKey('chip'),
                        onTap: expand,
                        builder: (context, active) => Container(
                          height: 42,
                          padding: const EdgeInsets.fromLTRB(14, 0, 20, 0),
                          decoration: BoxDecoration(color: active ? white : surface, borderRadius: BorderRadius.circular(21)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search, size: 20, color: active ? ink : muted),
                              const SizedBox(width: 10),
                              Text(query, style: text(15, color: active ? ink : white)),
                            ],
                          ),
                        ),
                      )
                    : ConstrainedBox(
                        key: const ValueKey('bar'),
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 58,
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(29),
                            border: Border.all(color: focused ? const Color(0x8096e072) : Colors.transparent),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 20),
                              Icon(Icons.search, color: focused ? white : muted),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: input,
                                  focusNode: inputFocus,
                                  autofocus: true,
                                  cursorColor: green,
                                  style: text(18),
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration.collapsed(
                                    hintText: 'Movies and series',
                                    hintStyle: text(18, color: const Color(0xff5f7464)),
                                  ),
                                  onSubmitted: search,
                                ),
                              ),
                              const SizedBox(width: 22),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (status.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter(context)),
              child: Text(status, style: text(15, color: muted)),
            ),
          if (results != null && results!.isNotEmpty) PosterGrid(items: results!, onOpen: (m) => openDetail(context, m)),
        ],
      ),
    );
  }
}
