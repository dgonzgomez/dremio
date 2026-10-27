import 'package:dremio/lookback.dart';
import 'package:dremio/store.dart';
import 'package:flutter_test/flutter_test.dart';

Meta movie(int id, {bool family = false}) => {'id': '$id', 'name': 'Movie $id', 'genres': ['Comedy', if (family) 'Family']};

void main() {
  test('party picks are stable all day, independent of catalog order, and rotate tomorrow', () {
    final pool = [for (var i = 0; i < 50; i++) {'id': '$i', 'name': 'Comedy $i', 'genres': ['Comedy'], 'description': 'Friends throw a house party.'}];
    List<String> ids(List<Meta> rows) => rows.map((m) => str(m, 'id')).toList();
    final morning = dailyPartyComedies(pool, 2000, date: DateTime(2026, 10, 26, 1));
    final evening = dailyPartyComedies(pool.reversed, 2000, date: DateTime(2026, 10, 26, 23));
    final tomorrow = dailyPartyComedies(pool, 2000, date: DateTime(2026, 10, 27));
    expect(ids(morning), ids(evening));
    expect(ids(morning).take(20).toList(), isNot(ids(tomorrow).take(20).toList()));
    expect(ids(tomorrow).toSet(), ids(morning).toSet());
    expect(dailyPartyComedies(pool, 1990), isEmpty);
  });

  test('expanded picks include more adult and college comedies', () {
    for (final title in ["We're the Millers", 'Horrible Bosses', 'Hall Pass', 'Without a Paddle', 'The To Do List', 'Orange County']) {
      expect(partyComedy({'name': title}, 2000), isTrue, reason: title);
    }
  });

  test('family-heavy comedy keeps occasional family picks and fills with other comedies', () {
    final films = [for (var i = 0; i < 30; i++) movie(i, family: true), for (var i = 30; i < 60; i++) movie(i)];
    final row = lookbackRow(films, {});
    expect(row.length, 20);
    expect(row.where(familyMovie).length, 2);
    expect(familyMovie(row.first), isFalse);
    expect(lookbackRow(films.where(familyMovie), {}, family: true).length, 20);
  });

  test('adult animation stays eligible and repeated titles are deduplicated', () {
    final animated = {'id': 'adult', 'genres': ['Animation', 'Comedy']};
    expect(familyMovie(animated), isFalse);
    final row = lookbackRow([animated, animated, movie(1), movie(2)], {'1'});
    expect(row.map((m) => m['id']), ['adult', '2', '1']);
  });

  test('party comedy includes wild-night and stoner titles in the requested decades', () {
    expect(partyComedy({'name': 'Harold & Kumar Go to White Castle'}, 2000), isTrue);
    expect(partyComedy({'name': 'The Beach Bum'}, 2010), isTrue);
    for (final title in ['Superbad', 'Project X', 'The Hangover', '21 & Over', 'Neighbors', 'Booksmart', 'American Reunion', 'EuroTrip']) {
      expect(partyComedy({'name': title}, 2010), isTrue, reason: title);
    }
    expect(partyComedy({'genres': ['Comedy'], 'description': 'Friends throw a wild house party.'}, 2010), isTrue);
    expect(partyComedy({'genres': ['Comedy', 'Family'], 'description': 'A wild party.'}, 2010), isFalse);
    expect(partyComedy({'name': 'Pineapple Express'}, 1990), isFalse);
    expect(partyComedy({'name': 'Unknown', 'genres': ['Comedy'], 'description': 'Two stoners go on a trip.'}, 2010), isTrue);
    expect(partyComedy({'genres': ['Crime'], 'description': 'A marijuana investigation.'}, 2010), isFalse);
    expect(partyComedy({'name': 'Toy Story', 'genres': ['Comedy', 'Family']}, 2010), isFalse);
  });
}
