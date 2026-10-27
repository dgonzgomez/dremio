import 'dart:math';

import 'store.dart';

bool familyMovie(Meta movie) => genres(movie).any((g) => const {'family', 'children', 'kids'}.contains(g.toLowerCase()));

/// Keeps family films as occasional discoveries in general Lookback rows.
/// Family's own row remains unrestricted. Animation alone isn't a kids label.
List<Meta> lookbackRow(Iterable<Meta> movies, Set<String> used, {bool family = false, int limit = 20}) {
  final seen = <String>{};
  final candidates = movies.where((m) => seen.add(str(m, 'id'))).toList();
  final fresh = candidates.where((m) => !used.contains(str(m, 'id'))).toList();
  if (fresh.length < 10) fresh.addAll(candidates.where((m) => used.contains(str(m, 'id'))).take(10 - fresh.length));
  if (family) return fresh.take(limit).toList();
  final grownup = fresh.where((m) => !familyMovie(m)).toList();
  final kids = fresh.where(familyMovie).take(2).toList();
  final result = <Meta>[];
  var nextFamily = 0;
  for (final movie in grownup) {
    result.add(movie);
    if (result.length % 8 == 7 && nextFamily < kids.length && result.length < limit) {
      result.add(kids[nextFamily++]);
    }
    if (result.length >= limit) break;
  }
  // Sparse eras still show their available family films, without dominating a row.
  while (result.length < limit && nextFamily < kids.length) {
    result.add(kids[nextFamily++]);
  }
  return result;
}

const _partyComedies = {
  'were the millers', 'due date', 'date night', 'horrible bosses', 'horrible bosses 2',
  'hall pass', 'thats my boy', 'the to do list', 'the changeup', 'the watch',
  'lets be cops', 'walk of shame', 'take me home tonight', 'the package',
  'out cold', 'stealing harvard', 'slackers', 'sorority boys', 'orange county',
  'not another teen movie', 'dorm daze', 'national lampoons dorm daze',
  'senior skip day', 'college', 'miss march', 'still waiting', 'strange wilderness',
  'freddy got fingered', 'without a paddle', 'club dread', 'the new guy', 'balls of fury',
  'superbad', 'project x', 'the hangover', 'the hangover part ii', 'the hangover part iii',
  'old school', 'road trip', 'eurotrip', 'sex drive', 'accepted', 'van wilder',
  'national lampoons van wilder', 'fired up', '21 over', 'neighbors', 'bad neighbours',
  'neighbors 2 sorority rising', 'bad neighbours 2', '21 jump street', '22 jump street',
  'booksmart', 'good boys', 'blockers', 'the inbetweeners movie', 'the inbetweeners 2',
  'mike and dave need wedding dates', 'mike dave need wedding dates', 'dirty grandpa',
  'wedding crashers', 'role models', 'sisters', 'rough night', 'office christmas party',
  'hot tub time machine', 'hot tub time machine 2', 'get him to the greek', 'the sitter',
  'game over man', 'beerfest', 'the house', 'bachelorette', 'ted', 'ted 2',
  'american pie 2', 'american wedding', 'american reunion',
  'american pie presents band camp', 'american pie presents the naked mile',
  'american pie presents beta house', 'american pie presents the book of love',
  'how high', 'harold kumar go to white castle', 'harold kumar escape from guantanamo bay',
  'pineapple express', 'dude wheres my car', 'smiley face', 'grandmas boy',
  'next friday', 'friday after next', 'saving grace', 'tenacious d in the pick of destiny',
  'a very harold kumar christmas', 'a very harold kumar 3d christmas',
  'high school', 'mac devin go to high school', 'this is the end', 'american ultra',
  'the night before', 'the beach bum', 'your highness', 'super troopers', 'super troopers 2',
};

bool partyComedy(Meta movie, int decade) {
  if ((decade != 2000 && decade != 2010) || familyMovie(movie)) return false;
  final title = str(movie, 'name').toLowerCase().replaceAll('&', ' ').replaceAll(RegExp('[^a-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (_partyComedies.contains(title)) return true;
  return genres(movie).any((g) => g.toLowerCase() == 'comedy') &&
      RegExp(r'\b(stoners?|potheads?|marijuana|cannabis|fraternity|frat|bachelor party|house party|wild party|spring break|debauchery)\b', caseSensitive: false).hasMatch(str(movie, 'description'));
}

/// A separate daily shuffle keeps this themed row from inheriting popularity order.
/// Canonical ordering makes it stable even when the surrounding catalog reshuffles.
List<Meta> dailyPartyComedies(Iterable<Meta> movies, int decade, {DateTime? date}) {
  final today = date ?? DateTime.now();
  final day = today.year * 10000 + today.month * 100 + today.day;
  String key(Meta m) => '${str(m, 'id')}:${str(m, 'name')}';
  final seen = <String>{};
  final picks = movies.where((m) => partyComedy(m, decade) && seen.add(key(m))).toList()
    ..sort((a, b) => key(a).compareTo(key(b)));
  picks.shuffle(Random(day * 10007 + decade));
  return picks;
}
