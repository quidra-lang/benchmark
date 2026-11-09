import 'road.dart';

class Phase {
  late final int duration;
  late final String token;
  late final Set<String> greens;
  Phase(String text) { final parts = text.split(':'); duration = int.parse(parts.first); token = parts.last; greens = token == '-' ? <String>{} : token.split(',').toSet(); }
}
class Junction {
  final String node;
  final int offset;
  final List<Phase> phases;
  final incoming = <Segment>[];
  late final int cycle;
  Junction(this.node, this.offset, List<String> tokens) : phases = tokens.map(Phase.new).toList() { cycle = phases.fold(0, (sum, phase) => sum + phase.duration); }
  bool green(String segment, int step) {
    if (phases.isEmpty) return true; var position = (step - 1 + offset) % cycle;
    for (final phase in phases) { if (position < phase.duration) return phase.greens.contains(segment); position -= phase.duration; } throw StateError('phase');
  }
  List<String> planLines() {
    if (phases.isEmpty) return ['JUNCTION $node unsignalized']; final lines = ['JUNCTION $node signal cycle $cycle offset $offset']; var begin = 0;
    for (var j = 0; j < phases.length; j++) { final phase = phases[j], end = begin + phases[j].duration - 1; lines.add('  PHASE ${j + 1} $begin-$end ${phase.token}'); begin = end + 1; } return lines;
  }
}
