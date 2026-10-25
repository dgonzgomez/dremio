/// Playback identity is the exact movie/episode ID, independent of catalog IDs.
class WatchProgress {
  const WatchProgress({
    required this.videoId,
    required this.positionMs,
    required this.durationMs,
    this.episode,
  });
  final String videoId;
  final int positionMs, durationMs;
  final Map<String, dynamic>? episode;
  bool get hasProgress => positionMs > 0 && durationMs > 0;
  double get fraction =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0, 1) : 0;

  int? _number(String key, int group) {
    final value = episode?[key];
    if (value is num) return value.toInt();
    if (value != null && int.tryParse('$value') != null) {
      return int.parse('$value');
    }
    final parsed = RegExp(r':(\d+):(\d+)$').firstMatch(videoId);
    return parsed == null ? null : int.tryParse(parsed.group(group)!);
  }

  int? get season => _number('season', 1);
  int? get episodeNumber => _number('episode', 2);
  String get episodeCode => episodeNumber == null
      ? 'Episode'
      : season == null
      ? 'Episode $episodeNumber'
      : 'S$season · E$episodeNumber';
  String get episodeTitle {
    for (final key in ['name', 'title']) {
      final value = '${episode?[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return episodeNumber == null
        ? 'Continue watching'
        : 'Episode $episodeNumber';
  }

  String get episodeLabel =>
      episodeTitle == 'Episode $episodeNumber' ||
          episodeTitle == 'Continue watching'
      ? episodeCode
      : '$episodeCode · $episodeTitle';

  Map<String, dynamic> heroFor(Map<String, dynamic> show) {
    final overview = '${episode?['overview'] ?? episode?['description'] ?? ''}'
        .trim();
    final thumb = '${episode?['thumbnail'] ?? ''}';
    return {
      ...show,
      'id': '${show['id']}:resume:$videoId',
      'name': episodeTitle,
      'description': overview.isNotEmpty
          ? overview
          : 'Resume $episodeCode from where you left off.',
      'background': thumb.startsWith('https://') ? thumb : show['background'],
    };
  }
}
