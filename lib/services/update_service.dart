import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/update_info.dart';

class UpdateService {
  UpdateService({this.owner = 'RfidResearchGroup', this.repo = 'proxmark3'});

  final String owner;
  final String repo;

  Future<UpdateInfo?> fetchLatestStable() async {
    for (final source in _candidateSources()) {
      final release = await _fetchLatestStableReleaseFromRepo(
        owner: source.key,
        repo: source.value,
      );
      if (release != null) {
        return release;
      }
    }
    return null;
  }

  Future<UpdateInfo?> fetchLatestExperimental() async {
    for (final source in _candidateSources()) {
      final release = await _fetchExperimentalReleaseFromRepo(
        owner: source.key,
        repo: source.value,
      );
      if (release != null) {
        return release;
      }
    }
    return null;
  }

  Future<String?> install(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (info.downloadUrl.isEmpty) {
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    final downloadFile = File('${tempDir.path}/${info.assetName}');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      request.headers['User-Agent'] = 'macKinect';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final total = response.contentLength ?? -1;
      var received = 0;
      final sink = downloadFile.openWrite();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }

    final supportDir = await getApplicationSupportDirectory();
    final releaseDir = Directory(
      '${supportDir.path}/core/releases/${info.tag}',
    );
    if (await releaseDir.exists()) {
      await releaseDir.delete(recursive: true);
    }
    await releaseDir.create(recursive: true);

    final extractedDir = await _extract(downloadFile, releaseDir);
    if (extractedDir == null) {
      return null;
    }

    final executable = _findExecutable(extractedDir);
    if (executable == null) {
      return null;
    }

    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', executable.path]);
    }

    return executable.path;
  }

  List<MapEntry<String, String>> _candidateSources() {
    final candidates = <MapEntry<String, String>>[
      MapEntry(owner, repo),
      const MapEntry('RfidResearchGroup', 'proxmark3'),
      const MapEntry('iceman1001', 'proxmark3'),
    ];
    final seen = <String>{};
    final unique = <MapEntry<String, String>>[];
    for (final candidate in candidates) {
      final key = '${candidate.key}/${candidate.value}'.toLowerCase();
      if (seen.add(key)) {
        unique.add(candidate);
      }
    }
    return unique;
  }

  Future<UpdateInfo?> _fetchLatestStableReleaseFromRepo({
    required String owner,
    required String repo,
  }) async {
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$owner/$repo/releases?per_page=25',
      );
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'macKinect',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;

      final releases = (jsonDecode(response.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>();
      for (final release in releases) {
        final isPrerelease = release['prerelease'] == true;
        final isDraft = release['draft'] == true;
        if (isPrerelease || isDraft) continue;

        final assets = (release['assets'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        final asset = _pickAsset(assets);
        if (asset == null) continue;

        final tag = release['tag_name'] as String? ?? 'latest';
        final name = release['name'] as String? ?? tag;
        final publishedAt = DateTime.tryParse(
          release['published_at'] as String? ?? '',
        );
        return UpdateInfo(
          tag: '${owner}_${repo}_$tag'.replaceAll('/', '_'),
          name: '$name ($owner/$repo)',
          publishedAt: publishedAt,
          assetName: asset['name'] as String? ?? 'release',
          downloadUrl: asset['browser_download_url'] as String? ?? '',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<UpdateInfo?> _fetchExperimentalReleaseFromRepo({
    required String owner,
    required String repo,
  }) async {
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$owner/$repo/releases?per_page=20',
      );
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'macKinect',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;

      final releases = (jsonDecode(response.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>();
      for (final release in releases) {
        final isPrerelease = release['prerelease'] == true;
        final isDraft = release['draft'] == true;
        if (!isPrerelease || isDraft) continue;

        final assets = (release['assets'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        final asset = _pickAsset(assets);
        if (asset == null) continue;

        final tag = release['tag_name'] as String? ?? 'experimental';
        final name = release['name'] as String? ?? tag;
        final publishedAt = DateTime.tryParse(
          release['published_at'] as String? ?? '',
        );
        return UpdateInfo(
          tag: '${owner}_${repo}_${tag}_experimental'.replaceAll('/', '_'),
          name: '$name ($owner/$repo experimental)',
          publishedAt: publishedAt,
          assetName: asset['name'] as String? ?? 'release',
          downloadUrl: asset['browser_download_url'] as String? ?? '',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _pickAsset(List<Map<String, dynamic>> assets) {
    if (assets.isEmpty) return null;

    final platform = _platformSlug();
    final arch = _archSlug();

    final platformMatchers = <RegExp>[
      RegExp(platform, caseSensitive: false),
      if (platform == 'macos') RegExp('darwin|osx', caseSensitive: false),
      if (platform == 'windows') RegExp('win', caseSensitive: false),
    ];

    final archMatchers = <RegExp>[
      RegExp(arch, caseSensitive: false),
      if (arch == 'x64') RegExp('x86_64|amd64', caseSensitive: false),
      if (arch == 'arm64') RegExp('aarch64', caseSensitive: false),
    ];

    final sorted =
        assets
            .where((asset) => _isReleaseAsset((asset['name'] as String? ?? '')))
            .toList()
          ..sort((a, b) {
            final scoreA = _assetScore(
              name: (a['name'] as String? ?? '').toLowerCase(),
              platformMatchers: platformMatchers,
              archMatchers: archMatchers,
            );
            final scoreB = _assetScore(
              name: (b['name'] as String? ?? '').toLowerCase(),
              platformMatchers: platformMatchers,
              archMatchers: archMatchers,
            );
            return scoreB.compareTo(scoreA);
          });

    if (sorted.isEmpty) return null;
    final topName = (sorted.first['name'] as String? ?? '').toLowerCase();
    final topScore = _assetScore(
      name: topName,
      platformMatchers: platformMatchers,
      archMatchers: archMatchers,
    );
    if (topScore < 45) return null;
    return sorted.first;
  }

  Future<Directory?> _extract(File archiveFile, Directory releaseDir) async {
    final name = archiveFile.path.toLowerCase();
    if (name.endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
      extractArchiveToDisk(archive, releaseDir.path);
      return releaseDir;
    }

    if (name.endsWith('.tar.gz') || name.endsWith('.tgz')) {
      final bytes = await archiveFile.readAsBytes();
      final tarData = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(tarData);
      extractArchiveToDisk(archive, releaseDir.path);
      return releaseDir;
    }

    if (name.endsWith('.tar')) {
      final bytes = await archiveFile.readAsBytes();
      final archive = TarDecoder().decodeBytes(bytes);
      extractArchiveToDisk(archive, releaseDir.path);
      return releaseDir;
    }

    final target = File('${releaseDir.path}/${_executableName()}');
    await archiveFile.copy(target.path);
    return releaseDir;
  }

  File? _findExecutable(Directory releaseDir) {
    final executableNames = _candidateExecutableNames();
    final matches = releaseDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) {
          final base = file.uri.pathSegments.isEmpty
              ? file.path
              : file.uri.pathSegments.last;
          return executableNames.contains(base);
        })
        .toList();
    if (matches.isEmpty) return null;
    for (final name in executableNames) {
      for (final match in matches) {
        final base = match.uri.pathSegments.isEmpty
            ? match.path
            : match.uri.pathSegments.last;
        if (base == name) {
          return match;
        }
      }
    }
    return matches.first;
  }

  String _platformSlug() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  String _archSlug() {
    switch (Abi.current()) {
      case Abi.macosArm64:
      case Abi.linuxArm64:
        return 'arm64';
      case Abi.macosX64:
      case Abi.linuxX64:
      case Abi.windowsX64:
        return 'x64';
      default:
        return 'unknown';
    }
  }

  String _executableName() => Platform.isWindows ? 'pm3.exe' : 'pm3';

  List<String> _candidateExecutableNames() {
    if (Platform.isWindows) {
      return const ['pm3.exe', 'proxmark3.exe'];
    }
    return const ['pm3', 'proxmark3'];
  }

  bool _isReleaseAsset(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.zip') ||
        lower.endsWith('.tar.gz') ||
        lower.endsWith('.tgz') ||
        lower.endsWith('.tar') ||
        lower.contains('pm3') ||
        lower.contains('proxmark3');
  }

  int _assetScore({
    required String name,
    required List<RegExp> platformMatchers,
    required List<RegExp> archMatchers,
  }) {
    var score = 0;
    if (name.contains('pm3') || name.contains('proxmark')) {
      score += 40;
    }
    if (platformMatchers.any((rx) => rx.hasMatch(name))) {
      score += 30;
    }
    if (archMatchers.any((rx) => rx.hasMatch(name))) {
      score += 20;
    }
    if (name.contains('client')) {
      score += 10;
    }
    return score;
  }
}
