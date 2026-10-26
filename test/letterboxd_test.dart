import 'package:dremio/letterboxd.dart';
import 'package:flutter_test/flutter_test.dart';

String item(String tmdb, String title, String date, {String rating = '', String like = 'No'}) =>
    '<item> <title>$title</title> <letterboxd:watchedDate>$date</letterboxd:watchedDate> <letterboxd:rewatch>No</letterboxd:rewatch> '
    '<letterboxd:filmTitle>$title</letterboxd:filmTitle> <letterboxd:filmYear>1985</letterboxd:filmYear> '
    '${rating.isEmpty ? '' : '<letterboxd:memberRating>$rating</letterboxd:memberRating> '}<letterboxd:memberLike>$like</letterboxd:memberLike> '
    '<tmdb:movieId>$tmdb</tmdb:movieId> <description><![CDATA[ <p><img src="https://a.ltrbxd.com/p/$tmdb.jpg"/></p> ]]></description> </item>';

DiaryEntry entry(String tmdb, double? rating, {bool liked = false}) => DiaryEntry(user: 'x', tmdb: tmdb, title: tmdb, year: '', watched: DateTime(2026), rating: rating, liked: liked);

void main() {
  test('RSS diary entries parse, newest first, skipping non-film items', () {
    final xml =
        '<rss><channel><title>Letterboxd - Dave Vis</title>'
        '${item('105', 'Back to the Future', '2026-10-01', rating: '4.5', like: 'Yes')}'
        '<item><title>A list</title><link>https://letterboxd.com/dave/list/x/</link></item>'
        '${item('9340', 'The Goonies', '2026-10-20')}'
        '</channel></rss>';
    final diary = Letterboxd.parseRss('dave', xml);
    expect(diary.map((e) => e.title), ['The Goonies', 'Back to the Future']);
    expect(diary.last.rating, 4.5);
    expect(diary.last.liked, isTrue);
    expect(diary.last.poster, 'https://a.ltrbxd.com/p/105.jpg');
    expect(diary.first.rating, isNull);
  });

  test('following page gives the owner and the people they follow', () {
    const html =
        '<a class="avatar -a24" href="/dave/" > <img src="https://secure.gravatar.com/avatar/b7?rating=PG&amp;size=48" alt="Dave Vis" width="24" /> </a>'
        '<a class="avatar -a40" href="/laurenlamagna/" > <img src="https://a.ltrbxd.com/avatar/l-0-80-0-80-crop.png" alt="Lauren" width="40" /> </a>'
        '<a class="avatar -a40" href="/Thomas_O/" > <img src="https://a.ltrbxd.com/avatar/t-0-80-0-80-crop.png" alt="Tom &amp; Co" width="40" /> </a>';
    final page = Letterboxd.parseFollowing('dave', html);
    expect(page.owner?.name, 'Dave Vis');
    expect(page.owner?.avatar, contains('size=160'));
    expect(page.following.map((m) => m.username), ['laurenlamagna', 'thomas_o']);
    expect(page.following.last.name, 'Tom & Co');
  });

  test('blend scores agreement and suggests what the friend loved that you have not seen', () {
    const friend = Member('lauren', 'Lauren', '');
    final mine = [entry('1', 5), entry('2', 4), entry('3', 2), entry('9', 4.5)];
    final theirs = [entry('1', 4.5), entry('2', 4), entry('3', 2.5), entry('9', 4, liked: true), entry('7', 5), entry('8', 2), entry('6', null, liked: true)];
    final b = Letterboxd.blend(friend, mine, theirs, {'6'});
    expect(b.shared, 4);
    expect(b.match, 92);
    expect(b.forYou.map((e) => e.tmdb), ['7']);
    expect(b.bothLoved.map((e) => e.tmdb), ['1', '2', '9']);
  });

  test('blends only compare the last 50 diary entries on each side', () {
    const friend = Member('lauren', 'Lauren', '');
    final mine = [for (var i = 0; i < 50; i++) entry('m$i', 3), entry('old', 5)];
    final theirs = [entry('old', 5)];
    expect(Letterboxd.blend(friend, mine, theirs, {}).shared, 0);
  });

  test('usernames are checked before any request', () {
    expect(Letterboxd.validUsername('dave'), isTrue);
    expect(Letterboxd.validUsername('../etc'), isFalse);
    expect(Letterboxd.validUsername('a b'), isFalse);
  });
}
