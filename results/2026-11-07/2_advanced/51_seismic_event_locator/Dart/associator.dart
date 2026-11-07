part of 'main.dart';

class Drop {
  final Pick pick;
  final double residual;
  Drop(this.pick, this.residual);
}

class LocationPass {
  final List<Pick> picks;
  final LocationRun run;
  LocationPass(this.picks, this.run);
}

class Candidate {
  final int number;
  final Pick first;
  final List<Pick> picks;
  final passes = <LocationPass>[], dropped = <Drop>[];
  int event = 0;
  bool rejected = false;
  Candidate(this.number, this.first, this.picks);
}

List<Candidate> associate(List<Pick> picks, int window, int minimum) {
  final result = <Candidate>[];
  for (var i = 0; i < picks.length; i++) {
    final first = picks[i];
    if (first.assigned) {
      continue;
    }
    final chosen = <Pick>[], seen = <int>{};
    for (final pick in picks.skip(i)) {
      if (pick.sample > first.sample + window) {
        break;
      }
      if (pick.assigned || seen.contains(pick.station.order)) {
        continue;
      }
      chosen.add(pick);
      seen.add(pick.station.order);
    }
    if (chosen.length < minimum) {
      continue;
    }
    for (final pick in chosen) {
      pick.assigned = true;
    }
    result.add(Candidate(result.length + 1, first, chosen));
  }
  return result;
}
