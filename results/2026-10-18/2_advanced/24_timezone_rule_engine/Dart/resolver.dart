import 'day_rules.dart';

class Period {
  final int start;
  final int offset;
  final bool dst;
  final String abbreviation;
  Period(this.start, this.offset, this.dst, this.abbreviation);
  bool sameState(Period other) => offset == other.offset && dst == other.dst && abbreviation == other.abbreviation;
}
class Timeline {
  final List<Period> periods;
  Timeline(this.periods);
  int indexAt(int time) {
    var low = 0;
    var high = periods.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (periods[middle].start <= time) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }
  Period periodAt(int time) => periods[indexAt(time)];
  int endOf(int index) => index + 1 < periods.length ? periods[index + 1].start : posInfinity;
  Iterable<int> nearby(int first, int last) sync* {
    final low = indexAt(first - 57600);
    final high = indexAt(last + 57600);
    for (var i = low; i <= high; i++) { yield i; }
  }
  List<int> candidates(int local) {
    final found = <int>[];
    for (final index in nearby(local, local)) {
      final time = local - periods[index].offset;
      if (periods[index].start <= time && time < endOf(index)) found.add(index);
    }
    return found;
  }
  int skippingTransition(int local) {
    for (final index in nearby(local, local)) {
      if (index > 0) {
        final start = periods[index].start;
        if (start + periods[index - 1].offset <= local && local < start + periods[index].offset) return index;
      }
    }
    return -1;
  }
}
