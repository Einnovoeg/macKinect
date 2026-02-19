class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.name,
    required this.publishedAt,
    required this.assetName,
    required this.downloadUrl,
  });

  final String tag;
  final String name;
  final DateTime? publishedAt;
  final String assetName;
  final String downloadUrl;
}
