part of 'main.dart';

Route? clearedRoute(Signal g, List<Route> routes) {
  for (final r in routes) {
    if (r.start != g || r.state != 'LOCKED') continue;
    final clear =
        r.requirements().every(
          (requirement) =>
              requirement.point.detected &&
              requirement.point.position == requirement.position,
        ) &&
        [...r.sections, ...r.overlap].every((section) => !section.occupied);
    if (clear) return r;
  }
  return null;
}

Map<Signal, String> signalAspects(Layout layout, List<Route> routes) {
  final cleared = {
        for (final signal in layout.signals)
          signal: clearedRoute(signal, routes),
      },
      aspects = <Signal, String>{};
  for (final signal in layout.signals) {
    final route = cleared[signal];
    var aspect = 'RED';
    if (route != null) {
      final finish = layout.signalByName[route.finish];
      if (finish != null) {
        aspect = cleared[finish] != null ? 'GREEN' : 'YELLOW';
      } else {
        aspect = layout.bufferByName.containsKey(route.finish)
            ? 'YELLOW'
            : 'GREEN';
      }
    }
    aspects[signal] = aspect;
  }
  return aspects;
}
