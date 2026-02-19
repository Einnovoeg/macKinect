class SerialPortInfo {
  const SerialPortInfo({
    required this.name,
    this.description,
    this.transport,
    this.vendorId,
    this.productId,
    this.manufacturer,
    this.serialNumber,
  });

  final String name;
  final String? description;
  final String? transport;
  final int? vendorId;
  final int? productId;
  final String? manufacturer;
  final String? serialNumber;

  String get displayName {
    final details = <String>[];
    if (description != null && description!.isNotEmpty) {
      details.add(description!);
    }
    if (manufacturer != null && manufacturer!.isNotEmpty) {
      details.add(manufacturer!);
    }
    return details.isEmpty ? name : '$name • ${details.join(" • ")}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SerialPortInfo &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
}
