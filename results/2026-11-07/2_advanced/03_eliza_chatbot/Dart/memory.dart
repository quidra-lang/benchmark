class MemoryQueue {
  final int capacity;
  final List<String> texts, log;
  MemoryQueue(this.capacity, [List<String>? texts, List<String>? log]) : texts = texts ?? [], log = log ?? [];
  MemoryQueue copy() => MemoryQueue(capacity, List.of(texts), List.of(log));
  bool store(String prefix, String keyword, String text) {
    if (texts.contains(text)) { log.add('$prefix SKIP $keyword $text'); return false; }
    if (texts.length == capacity) log.add('$prefix DROP ${texts.removeAt(0)}');
    texts.add(text);
    log.add('$prefix STORE $keyword $text');
    return true;
  }
  String recall(String prefix) {
    final text = texts.removeAt(0);
    log.add('$prefix RECALL $text');
    return text;
  }
  int clear(String prefix) {
    final count = texts.length;
    if (count > 0) { log.add('$prefix CLEAR $count'); texts.clear(); }
    return count;
  }
}
