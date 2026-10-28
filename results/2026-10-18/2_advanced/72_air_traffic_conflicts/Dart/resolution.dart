part of 'main.dart';

class Manoeuvre {
  final String name, kind;
  final int amount;
  Manoeuvre(this.name, this.kind, this.amount);
}

List<Manoeuvre> manoeuvres(Settings settings) => [
  Manoeuvre('level_up', 'level', 10),
  Manoeuvre('level_down', 'level', -10),
  Manoeuvre('speed_down', 'speed', 0),
  for (var delay = 60; delay <= settings.maxDelay; delay += 60)
    Manoeuvre('delay_$delay', 'delay', delay),
];
FlightPlan? apply(
  FlightPlan current,
  Manoeuvre move,
  AircraftType aircraft,
  Settings settings,
) {
  final p = current.copy();
  switch (move.kind) {
    case 'level':
      p.offset += move.amount;
      for (final level in flightLevels(p)) {
        if (level < settings.minLevel || level > settings.maxLevel) return null;
      }
      break;
    case 'speed':
      p.speed = p.speed * 9 ~/ 10;
      if (p.speed < aircraft.minSpeed) return null;
      break;
    case 'delay':
      p.delay += move.amount;
      break;
  }
  return p;
}

bool lowerPriority(FlightPlan a, FlightPlan b) {
  final ta = a.departure + a.delay, tb = b.departure + b.delay;
  return ta > tb || (ta == tb && a.callsign.compareTo(b.callsign) > 0);
}
