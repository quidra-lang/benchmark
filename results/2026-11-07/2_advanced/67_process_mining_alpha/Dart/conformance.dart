part of 'main.dart';

class Net {
  final List<String> places, transitions;
  final Map<String, List<int>> input = {}, output = {};
  final int initial, finalPlace;
  int arcs = 0;
  Net(this.places, this.transitions, this.initial, this.finalPlace) {
    for (final t in transitions) {
      input[t] = [];
      output[t] = [];
    }
  }
  bool enabled(List<int> mark, String t) => input[t]!.every((p) => mark[p] > 0);
  List<int> fire(List<int> mark, String t) {
    final a = List.of(mark);
    for (final p in input[t]!) {
      a[p]--;
    }
    for (final p in output[t]!) {
      a[p]++;
    }
    return a;
  }
}

class PlaceReplay {
  int missing = 0, remaining = 0, deviating = 0;
  final List<int> waits = [];
  final Map<String, int> routes = {};
}

class Replay {
  int missing = 0,
      remaining = 0,
      consumed = 0,
      produced = 0,
      skipped = 0,
      fitting = 0;
  final List<PlaceReplay> places;
  Replay(Net n) : places = List.generate(n.places.length, (_) => PlaceReplay());
  Ratio get fitness => Ratio(
    2 * consumed * produced - missing * produced - remaining * consumed,
    2 * consumed * produced,
  );
}

Net readModel() {
  final places = <String>[], transitions = <String>[], arcs = <Pair>[];
  var initial = '', finalPlace = '';
  for (final line in File('input/model.txt').readAsLinesSync()) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'PLACE':
        places.add(a[1]);
        break;
      case 'TRANSITION':
        transitions.add(a[1]);
        break;
      case 'ARC':
        arcs.add((a[1], a[2]));
        break;
      case 'INITIAL':
        initial = a[1];
        break;
      case 'FINAL':
        finalPlace = a[1];
        break;
    }
  }
  transitions.sort();
  final index = {for (var i = 0; i < places.length; i++) places[i]: i};
  final n = Net(places, transitions, index[initial]!, index[finalPlace]!);
  for (final (a, b) in arcs) {
    if (index.containsKey(a)) {
      n.input[b]!.add(index[a]!);
    } else {
      n.output[a]!.add(index[b]!);
    }
    n.arcs++;
  }
  for (final t in transitions) {
    n.input[t]!.sort();
    n.output[t]!.sort();
  }
  return n;
}
