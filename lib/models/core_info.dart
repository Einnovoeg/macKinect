enum CoreSource { embedded, updated, local, system, missing }

class CoreInfo {
  const CoreInfo({required this.path, required this.source, this.versionLabel});

  final String? path;
  final CoreSource source;
  final String? versionLabel;

  bool get isAvailable => path != null;
}
