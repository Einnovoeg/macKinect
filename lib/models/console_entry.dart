class ConsoleEntry {
  ConsoleEntry(this.message, {this.isError = false, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  final String message;
  final bool isError;
  final DateTime timestamp;
}
