import 'dart:io';

import 'package:libserialport/libserialport.dart';

import '../models/serial_port_info.dart';

class SerialPortService {
  List<SerialPortInfo> listPorts() {
    final result = <SerialPortInfo>[];
    final seen = <String>{};

    try {
      final ports = SerialPort.availablePorts;
      for (final name in ports) {
        final port = SerialPort(name);
        final normalizedName = _normalizeName(name);
        if (seen.add(normalizedName)) {
          result.add(
            SerialPortInfo(
              name: normalizedName,
              description: port.description,
              transport: _transportLabel(port.transport),
              vendorId: port.vendorId,
              productId: port.productId,
              manufacturer: port.manufacturer,
              serialNumber: port.serialNumber,
            ),
          );
        }
        port.dispose();
      }
    } catch (_) {
      // Ignore and try fallback below.
    }

    if (Platform.isMacOS) {
      for (final port in _scanDevPorts()) {
        final normalizedName = _normalizeName(port.name);
        if (seen.add(normalizedName)) {
          result.add(
            SerialPortInfo(
              name: normalizedName,
              description: port.description,
              transport: port.transport,
              vendorId: port.vendorId,
              productId: port.productId,
              manufacturer: port.manufacturer,
              serialNumber: port.serialNumber,
            ),
          );
        }
      }
    }

    result.sort((a, b) => _scorePort(b).compareTo(_scorePort(a)));
    return result;
  }

  int _scorePort(SerialPortInfo info) {
    final name = info.name.toLowerCase();
    final description = (info.description ?? '').toLowerCase();
    final manufacturer = (info.manufacturer ?? '').toLowerCase();
    final haystack = '$name $description $manufacturer';
    var score = 0;
    if (haystack.contains('usbmodemiceman') ||
        haystack.contains('sbmodemiceman') ||
        haystack.contains('iceman')) {
      score += 120;
    }
    if (haystack.contains('proxmark')) {
      score += 100;
    }
    if (name.contains('usbmodem') || name.contains('usbserial')) {
      score += 30;
    }
    if (name.contains('tty')) {
      score += 15;
    }
    if (name.contains('cu.')) {
      score += 5;
    }
    if (name.contains('bluetooth') ||
        name.contains('incoming-port') ||
        name.contains('debug-console')) {
      score -= 40;
    }
    if (info.manufacturer != null && info.manufacturer!.isNotEmpty) {
      score += 6;
    }
    if (info.vendorId != null && info.productId != null) {
      score += 4;
    }
    return score;
  }

  String? _transportLabel(int transport) {
    switch (transport) {
      case SerialPortTransport.usb:
        return 'usb';
      case SerialPortTransport.bluetooth:
        return 'bluetooth';
      case SerialPortTransport.native:
      default:
        return 'native';
    }
  }

  List<SerialPortInfo> _scanDevPorts() {
    final ports = <SerialPortInfo>[];
    try {
      final entries = Directory('/dev').listSync(followLinks: false);
      for (final entry in entries) {
        final name = entry.path;
        final base = name.split('/').last;
        if (base.startsWith('tty.') || base.startsWith('cu.')) {
          ports.add(SerialPortInfo(name: '/dev/$base'));
        }
      }
    } catch (_) {}
    return ports;
  }

  String _normalizeName(String rawName) {
    if (!Platform.isMacOS) return rawName;
    if (rawName.startsWith('/dev/')) return rawName;
    if (rawName.startsWith('tty.') || rawName.startsWith('cu.')) {
      return '/dev/$rawName';
    }
    return rawName;
  }
}
