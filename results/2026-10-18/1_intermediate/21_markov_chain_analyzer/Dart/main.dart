import 'dart:io';

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

Never fail(String message) => throw CommandError(message);

class Fraction implements Comparable<Fraction> {
  final int numerator;
  final int denominator;
  const Fraction._(this.numerator, this.denominator);
  static const zero = Fraction._(0, 1);
  static const one = Fraction._(1, 1);
  static const two = Fraction._(2, 1);

  factory Fraction(int numerator, [int denominator = 1]) {
    if (denominator < 0) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final divisor = numerator.abs().gcd(denominator);
    return Fraction._(numerator ~/ divisor, denominator ~/ divisor);
  }

  Fraction operator +(Fraction other) => Fraction(
      numerator * other.denominator + other.numerator * denominator,
      denominator * other.denominator);
  Fraction operator -(Fraction other) => Fraction(
      numerator * other.denominator - other.numerator * denominator,
      denominator * other.denominator);
  Fraction operator *(Fraction other) =>
      Fraction(numerator * other.numerator, denominator * other.denominator);
  Fraction operator /(Fraction other) =>
      Fraction(numerator * other.denominator, denominator * other.numerator);
  Fraction get absolute => Fraction(numerator.abs(), denominator);
  bool get isZero => numerator == 0;

  @override
  int compareTo(Fraction other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);
  @override
  bool operator ==(Object other) => other is Fraction &&
      numerator == other.numerator && denominator == other.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
  @override
  String toString() => '$numerator/$denominator';

  String get value => '$this(${numerator ~/ denominator}.'
      '${(numerator % denominator * 1000000 ~/ denominator).toString().padLeft(6, '0')})';
}

Fraction probability(String text) {
  final parts = text.split('/');
  final numerator = int.parse(parts[0]);
  final denominator = parts.length == 1 ? 1 : int.parse(parts[1]);
  if (denominator == 0 || numerator > denominator) fail('BAD PROBABILITY');
  return Fraction(numerator, denominator);
}

typedef Matrix = List<List<Fraction>>;

Fraction total(Iterable<Fraction> values) =>
    values.fold(Fraction.zero, (sum, value) => sum + value);

Matrix matrix(int rows, int columns) =>
    List.generate(rows, (_) => List.filled(columns, Fraction.zero));

Fraction delta(int i, int j) => i == j ? Fraction.one : Fraction.zero;

Matrix identity(int size) => List.generate(size,
    (i) => List.generate(size, (j) => delta(i, j)));

List<Fraction> advance(List<Fraction> distribution, Matrix transitions) =>
    List.generate(distribution.length, (j) => total(List.generate(
        distribution.length, (i) => distribution[i] * transitions[i][j])));

Matrix multiply(Matrix a, Matrix b) => a.map((row) => advance(row, b)).toList();

Matrix solve(Matrix augmented) {
  final size = augmented.length;
  if (size == 0) return [];
  final width = augmented[0].length;
  for (var column = 0; column < size; column++) {
    var pivotRow = column;
    while (augmented[pivotRow][column].isZero) {
      pivotRow++;
    }
    final swap = augmented[column];
    augmented[column] = augmented[pivotRow];
    augmented[pivotRow] = swap;
    final pivot = augmented[column][column];
    for (var j = 0; j < width; j++) {
      augmented[column][j] = augmented[column][j] / pivot;
    }
    for (var row = 0; row < size; row++) {
      if (row == column) continue;
      final factor = augmented[row][column];
      if (factor.isZero) continue;
      for (var j = 0; j < width; j++) {
        augmented[row][j] = augmented[row][j] - factor * augmented[column][j];
      }
    }
  }
  return augmented.map((row) => row.sublist(size)).toList();
}

class Component {
  final List<int> states;
  final bool closed;
  final int period;
  final List<int> levels;
  Component(this.states, this.closed, this.period, this.levels);
}

class Graph {
  final List<List<bool>> reach;
  final List<Component> classes;
  Graph(this.reach, this.classes);
}

class Hitting {
  final List<Fraction> probability;
  final List<Fraction?> time;
  Hitting(this.probability, this.time);
}

class Absorption {
  final List<int> transient;
  final List<int> absorbing;
  final Matrix fundamental;
  final Matrix probability;
  final List<Fraction> mean;
  final List<Fraction> variance;
  Absorption(this.transient, this.absorbing, this.fundamental,
      this.probability, this.mean, this.variance);
}

class Chain {
  final List<String> names;
  final Matrix p;
  Chain(this.names, this.p);
  int get size => names.length;
  List<int> get indices => List.generate(size, (i) => i);
  String labels(Iterable<int> states, [String separator = ' ']) =>
      states.map((i) => names[i]).join(separator);

  int state(String name) {
    final index = names.indexOf(name);
    if (index < 0) fail('UNKNOWN STATE $name');
    return index;
  }

  List<int> stateSet(Iterable<String> words) {
    final states = <int>{};
    for (final word in words) {
      final index = state(word);
      if (!states.add(index)) fail('DUPLICATE STATE $word');
    }
    return states.toList()..sort();
  }

  void stochastic() {
    for (var i = 0; i < size; i++) {
      if (total(p[i]) != Fraction.one) fail('NOT STOCHASTIC ${names[i]}');
    }
  }

  Graph graph() {
    final reach = List.generate(size,
        (i) => List.generate(size, (j) => i == j || !p[i][j].isZero));
    for (var k = 0; k < size; k++) {
      for (var i = 0; i < size; i++) {
        for (var j = 0; j < size; j++) {
          reach[i][j] = reach[i][j] || reach[i][k] && reach[k][j];
        }
      }
    }
    final assigned = <int>{};
    final classes = <Component>[];
    for (var first = 0; first < size; first++) {
      if (assigned.contains(first)) continue;
      final states = indices.where((j) => reach[first][j] && reach[j][first]).toList();
      final members = states.toSet();
      assigned.addAll(states);
      final closed = states.every((i) => indices.every(
          (j) => members.contains(j) || p[i][j].isZero));
      final levels = List<int>.filled(size, -1);
      levels[first] = 0;
      final queue = [first];
      for (var head = 0; head < queue.length; head++) {
        final i = queue[head];
        for (final j in states) {
          if (levels[j] < 0 && !p[i][j].isZero) {
            levels[j] = levels[i] + 1;
            queue.add(j);
          }
        }
      }
      var period = 0;
      for (final i in states) {
        for (final j in states) {
          if (!p[i][j].isZero) period = period.gcd((levels[i] + 1 - levels[j]).abs());
        }
      }
      classes.add(Component(states, closed, period, levels));
    }
    return Graph(reach, classes);
  }

  List<Fraction> stationary(List<int> states) {
    final count = states.length;
    final equations = matrix(count, count + 1);
    for (var row = 0; row < count - 1; row++) {
      for (var col = 0; col < count; col++) {
        equations[row][col] = p[states[col]][states[row]] - delta(col, row);
      }
    }
    equations[count - 1] = List.filled(count + 1, Fraction.one);
    final solution = solve(equations);
    final distribution = List.filled(size, Fraction.zero);
    for (var i = 0; i < count; i++) {
      distribution[states[i]] = solution[i][0];
    }
    return distribution;
  }

  List<Fraction> uniqueStationary() {
    final classes = graph().classes;
    if (classes.length != 1) fail('NOT IRREDUCIBLE');
    return stationary(classes.single.states);
  }

  Hitting hitting(List<int> targets, {bool withTimes = true}) {
    final reach = graph().reach;
    final targetSet = targets.toSet();
    final unknown = indices.where((i) => !targetSet.contains(i) &&
        targets.any((j) => reach[i][j])).toList();
    final probability = List.filled(size, Fraction.zero);
    final time = List<Fraction?>.filled(size, null);
    for (final target in targets) {
      probability[target] = Fraction.one;
      time[target] = Fraction.zero;
    }
    if (unknown.isNotEmpty) {
      final equations = List.generate(unknown.length, (row) => [
        for (var col = 0; col < unknown.length; col++)
          delta(row, col) - p[unknown[row]][unknown[col]],
        total(targets.map((j) => p[unknown[row]][j])),
      ]);
      final solution = solve(equations);
      for (var i = 0; i < unknown.length; i++) {
        probability[unknown[i]] = solution[i][0];
      }
    }
    final certain = unknown.where((i) => probability[i] == Fraction.one).toList();
    if (withTimes && certain.isNotEmpty) {
      final equations = List.generate(certain.length, (row) => [
        for (var col = 0; col < certain.length; col++)
          delta(row, col) - p[certain[row]][certain[col]],
        Fraction.one,
      ]);
      final solution = solve(equations);
      for (var i = 0; i < certain.length; i++) {
        time[certain[i]] = solution[i][0];
      }
    }
    return Hitting(probability, time);
  }

  Absorption absorption() {
    final absorbing = indices.where((i) => p[i][i] == Fraction.one).toList();
    if (absorbing.isEmpty) fail('NO ABSORBING STATE');
    final transient = indices.where((i) => !absorbing.contains(i)).toList();
    final reach = graph().reach;
    for (final i in transient) {
      if (!absorbing.any((j) => reach[i][j])) fail('NOT ABSORBING ${names[i]}');
    }
    final count = transient.length;
    final equations = List.generate(count, (row) => [
      for (var col = 0; col < count; col++) delta(row, col) - p[transient[row]][transient[col]],
      for (var col = 0; col < count; col++) delta(row, col),
    ]);
    final fundamental = solve(equations);
    final mean = fundamental.map(total).toList();
    final variance = List.generate(count, (i) => total(List.generate(count,
        (j) => (Fraction.two * fundamental[i][j] - delta(i, j)) * mean[j])) - mean[i] * mean[i]);
    final chances = List.generate(count, (i) => List.generate(absorbing.length,
        (j) => total(List.generate(count, (k) => fundamental[i][k] * p[transient[k]][absorbing[j]]))));
    return Absorption(transient, absorbing, fundamental, chances, mean, variance);
  }
}

class Analyzer {
  final Map<String, Chain> chains = {};
  final output = StringBuffer();
  void emit(String line) => output.writeln(line);

  void showMatrix(List<String> names, Matrix values, [String label = 'ROW']) {
    emit('STATES ${names.join(' ')}');
    for (var i = 0; i < names.length; i++) {
      emit('$label ${names[i]} ${values[i].join(' ')}');
    }
  }

  void create(List<String> words) {
    final name = words[1];
    final states = words.sublist(2);
    if (states.length > 10) fail('TOO MANY STATES');
    final seen = <String>{};
    for (final state in states) {
      if (!seen.add(state)) fail('DUPLICATE STATE $state');
    }
    chains[name] = Chain(states, matrix(states.length, states.length));
    emit('CHAIN $name states=${states.length}');
  }

  void build(List<String> words) {
    final name = words[1];
    final order = int.parse(words[2]);
    if (order != 1 && order != 2) fail('BAD ORDER');
    final tokens = words.sublist(3);
    if (tokens.length <= order) fail('TOO FEW TOKENS');
    final observations = order == 1 ? tokens : List.generate(tokens.length - 1,
        (i) => '${tokens[i]}.${tokens[i + 1]}');
    final names = <String>[];
    final seen = <String>{};
    for (final observation in observations) {
      if (seen.add(observation)) names.add(observation);
    }
    if (names.length > 10) fail('TOO MANY STATES');
    final count = names.length;
    final counts = List.generate(count, (_) => List<int>.filled(count, 0));
    for (var i = 0; i + 1 < observations.length; i++) {
      counts[names.indexOf(observations[i])][names.indexOf(observations[i + 1])]++;
    }
    final totals = counts.map((row) => row.fold(0, (sum, value) => sum + value)).toList();
    final p = List.generate(count, (i) => List.generate(count,
        (j) => totals[i] == 0 ? delta(i, j) : Fraction(counts[i][j], totals[i])));
    chains[name] = Chain(names, p);
    emit('BUILD $name order=$order states=$count transitions=${observations.length - 1}');
    for (var i = 0; i < count; i++) {
      final transitions = [for (var j = 0; j < count; j++)
        if (counts[i][j] > 0) '${names[j]}:${counts[i][j]}'];
      emit('FROM ${names[i]} total=${totals[i]} ${totals[i] == 0 ? 'absorbing' : transitions.join(' ')}');
    }
  }

  void gambler(List<String> words) {
    final name = words[1];
    final goal = int.parse(words[2]);
    final start = int.parse(words[3]);
    if (goal == 0 || goal > 9) fail('BAD SIZE');
    if (start > goal) fail('BAD START');
    final chance = probability(words[4]);
    if (chance == Fraction.zero || chance == Fraction.one) fail('BAD PROBABILITY');
    final p = matrix(goal + 1, goal + 1);
    p[0][0] = p[goal][goal] = Fraction.one;
    for (var i = 1; i < goal; i++) {
      p[i][i + 1] = chance;
      p[i][i - 1] = Fraction.one - chance;
    }
    final chain = Chain(List.generate(goal + 1, (i) => 's$i'), p);
    final absorption = chain.absorption();
    final ruin = List.filled(goal + 1, Fraction.zero);
    final duration = List.filled(goal + 1, Fraction.zero);
    ruin[0] = Fraction.one;
    for (var i = 0; i < absorption.transient.length; i++) {
      ruin[absorption.transient[i]] = absorption.probability[i][0];
      duration[absorption.transient[i]] = absorption.mean[i];
    }
    chains[name] = chain;
    emit('GAMBLER $name g=$goal p=$chance start=s$start ruin=${ruin[start].value} duration=${duration[start].value}');
    for (var i = 0; i <= goal; i++) {
      emit('CAPITAL s$i ruin=${ruin[i].value} win=${(Fraction.one - ruin[i]).value} duration=${duration[i].value}');
    }
  }

  void classes(String name, Chain chain) {
    final components = chain.graph().classes;
    emit('CLASSES $name count=${components.length}');
    for (var i = 0; i < components.length; i++) {
      final component = components[i];
      emit('CLASS ${i + 1} ${component.closed ? 'RECURRENT' : 'TRANSIENT'} '
          'period=${component.period} size=${component.states.length} ${chain.labels(component.states)}');
      if (component.period >= 2) {
        for (var r = 0; r < component.period; r++) {
          emit('CYCLIC $r ${chain.labels(component.states.where((j) => component.levels[j] % component.period == r))}');
        }
      }
    }
  }

  void classify(String name, Chain chain) {
    final graph = chain.graph();
    final absorbing = chain.indices.where((i) => chain.p[i][i] == Fraction.one).toList();
    final isAbsorbing = absorbing.isNotEmpty && chain.indices.every(
        (i) => absorbing.any((j) => graph.reach[i][j]));
    final edges = List.generate(chain.size,
        (i) => List.generate(chain.size, (j) => !chain.p[i][j].isZero));
    var power = edges;
    int? exponent;
    final bound = (chain.size - 1) * (chain.size - 1) + 1;
    for (var t = 1; t <= bound; t++) {
      if (power.every((row) => row.every((value) => value))) {
        exponent = t;
        break;
      }
      power = List.generate(chain.size, (i) => List.generate(chain.size,
          (j) => chain.indices.any((k) => power[i][k] && edges[k][j])));
    }
    emit('CLASSIFY $name absorbing_states=${absorbing.length} absorbing=${isAbsorbing ? 'yes' : 'no'} '
        'ergodic=${graph.classes.length == 1 ? 'yes' : 'no'} regular=${exponent == null ? 'no' : 'yes'} exponent=${exponent ?? '-'}');
  }

  void step(String name, Chain chain, String initial, int steps) {
    List<Fraction> distribution;
    if (initial.codeUnitAt(0) >= 48 && initial.codeUnitAt(0) <= 57) {
      final values = initial.split(',');
      if (values.length != chain.size) fail('BAD LENGTH');
      distribution = values.map(probability).toList();
      if (total(distribution) != Fraction.one) fail('BAD DISTRIBUTION');
    } else {
      final state = chain.state(initial);
      distribution = List.filled(chain.size, Fraction.zero);
      distribution[state] = Fraction.one;
    }
    for (var t = 0; t < steps; t++) {
      distribution = advance(distribution, chain.p);
    }
    emit('STEP $name k=$steps');
    for (var i = 0; i < chain.size; i++) {
      emit('PROB ${chain.names[i]} ${distribution[i].value}');
    }
  }

  void stationary(String name, Chain chain) {
    final components = chain.graph().classes;
    emit('STATIONARY $name count=${components.where((component) => component.closed).length}');
    var number = 0;
    for (var i = 0; i < components.length; i++) {
      final component = components[i];
      if (!component.closed) continue;
      final distribution = chain.stationary(component.states);
      emit('DIST ${++number} class=${i + 1} size=${component.states.length}');
      for (final state in component.states) {
        emit('PI ${chain.names[state]} ${distribution[state].value}');
      }
    }
  }

  void absorb(String name, Chain chain) {
    final a = chain.absorption();
    emit('ABSORB $name transient=${a.transient.length} absorbing=${a.absorbing.length}');
    if (a.transient.isEmpty) return;
    emit('TRANSIENT ${chain.labels(a.transient)}');
    emit('ABSORBING ${chain.labels(a.absorbing)}');
    for (var i = 0; i < a.transient.length; i++) {
      emit('N ${chain.names[a.transient[i]]} ${a.fundamental[i].join(' ')}');
    }
    for (var i = 0; i < a.transient.length; i++) {
      emit('STEPS ${chain.names[a.transient[i]]} mean=${a.mean[i].value} var=${a.variance[i].value}');
    }
    for (var i = 0; i < a.transient.length; i++) {
      emit('B ${chain.names[a.transient[i]]} ${a.probability[i].join(' ')}');
    }
  }

  void passage(String name, Chain chain) {
    final pi = chain.uniqueStationary();
    final passage = matrix(chain.size, chain.size);
    for (var j = 0; j < chain.size; j++) {
      final hitting = chain.hitting([j]);
      for (var i = 0; i < chain.size; i++) {
        passage[i][j] = i == j ? Fraction.one / pi[j] : hitting.time[i]!;
      }
    }
    final kemeny = total(chain.indices.skip(1).map((j) => pi[j] * passage[0][j]));
    emit('PASSAGE $name kemeny=${kemeny.value}');
    showMatrix(chain.names, passage, 'M');
  }

  void firstPassage(String name, Chain chain, String from, String to, int steps) {
    final x = chain.state(from);
    final y = chain.state(to);
    if (steps == 0) fail('BAD STEPS');
    var previous = chain.indices.map((i) => chain.p[i][y]).toList();
    final values = <Fraction>[];
    final cumulative = <Fraction>[];
    var sum = Fraction.zero;
    for (var t = 1; t <= steps; t++) {
      if (t > 1) {
        previous = List.generate(chain.size, (i) => total(chain.indices
            .where((j) => j != y).map((j) => chain.p[i][j] * previous[j])));
      }
      values.add(previous[x]);
      sum = sum + previous[x];
      cumulative.add(sum);
    }
    emit('FIRSTPASSAGE $name $from $to k=$steps total=${sum.value}');
    for (var t = 0; t < steps; t++) {
      emit('FP ${t + 1} ${values[t].value} cum=${cumulative[t].value}');
    }
  }

  void mostLikely(String name, Chain chain, String from, int steps) {
    final start = chain.state(from);
    if (steps == 0) fail('BAD STEPS');
    final best = matrix(steps + 1, chain.size);
    best[steps] = List.filled(chain.size, Fraction.one);
    for (var t = steps - 1; t >= 0; t--) {
      for (var i = 0; i < chain.size; i++) {
        for (var j = 0; j < chain.size; j++) {
          final candidate = chain.p[i][j] * best[t + 1][j];
          if (candidate.compareTo(best[t][i]) > 0) best[t][i] = candidate;
        }
      }
    }
    final path = [start];
    for (var t = 0; t < steps; t++) {
      final current = path.last;
      path.add(chain.indices.firstWhere(
          (j) => chain.p[current][j] * best[t + 1][j] == best[t][current]));
    }
    emit('MOSTLIKELY $name $from k=$steps prob=${best[0][start].value}');
    emit('PATH ${chain.labels(path)}');
  }

  void reversible(String name, Chain chain) {
    final pi = chain.uniqueStationary();
    final violations = <({int i, int j, Fraction a, Fraction b})>[];
    for (var i = 0; i < chain.size; i++) {
      for (var j = i + 1; j < chain.size; j++) {
        final a = pi[i] * chain.p[i][j];
        final b = pi[j] * chain.p[j][i];
        if (a != b) violations.add((i: i, j: j, a: a, b: b));
      }
    }
    emit('REVERSIBLE $name ${violations.isEmpty ? 'yes' : 'no violations=${violations.length}'}');
    for (final v in violations) {
      emit('VIOLATION ${chain.names[v.i]} ${chain.names[v.j]} ${v.a.value} ${v.b.value}');
    }
  }

  void reverse(String name, Chain chain, String destination) {
    final pi = chain.uniqueStationary();
    final reversed = List.generate(chain.size, (i) => List.generate(chain.size,
        (j) => pi[j] * chain.p[j][i] / pi[i]));
    final same = chain.indices.every((i) => chain.indices.every((j) => reversed[i][j] == chain.p[i][j]));
    chains[destination] = Chain(chain.names.toList(), reversed);
    emit('REVERSE $name $destination reversible=${same ? 'yes' : 'no'}');
    showMatrix(chain.names, reversed);
  }

  void mixing(String name, Chain chain, int steps, String epsilon) {
    if (steps == 0) fail('BAD STEPS');
    final eps = probability(epsilon);
    final pi = chain.uniqueStationary();
    var power = identity(chain.size);
    final rows = <({Fraction distance, int state})>[];
    int? time;
    for (var t = 1; t <= steps; t++) {
      power = multiply(power, chain.p);
      var distance = Fraction.zero;
      var worst = 0;
      for (var i = 0; i < chain.size; i++) {
        final value = total(chain.indices.map((j) => (power[i][j] - pi[j]).absolute)) / Fraction.two;
        if (value.compareTo(distance) > 0) {
          distance = value;
          worst = i;
        }
      }
      if (time == null && distance.compareTo(eps) <= 0) time = t;
      rows.add((distance: distance, state: worst));
    }
    emit('MIXING $name k=$steps eps=$eps time=${time ?? 'none'}');
    for (var t = 0; t < rows.length; t++) {
      emit('TV ${t + 1} ${rows[t].distance.value} from=${chain.names[rows[t].state]}');
    }
  }

  void lump(String name, Chain chain, String destination, String partition) {
    final seen = <int>{};
    final blocks = <List<int>>[];
    for (final block in partition.split('|')) {
      final states = <int>[];
      for (final text in block.split(',')) {
        final state = chain.state(text);
        if (!seen.add(state)) fail('BAD PARTITION');
        states.add(state);
      }
      states.sort();
      blocks.add(states);
    }
    if (seen.length != chain.size) fail('BAD PARTITION');
    blocks.sort((a, b) => a.first.compareTo(b.first));
    final p = matrix(blocks.length, blocks.length);
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final representative = block.first;
      for (var j = 0; j < blocks.length; j++) {
        final baseline = total(blocks[j].map((target) => chain.p[representative][target]));
        for (final state in block) {
          final value = total(blocks[j].map((target) => chain.p[state][target]));
          if (value == baseline) continue;
          emit('LUMP $name not lumpable block=${chain.names[representative]} '
              'target=${chain.names[blocks[j].first]} ${chain.names[representative]}=${baseline.value} '
              '${chain.names[state]}=${value.value}');
          return;
        }
        p[i][j] = baseline;
      }
    }
    final names = blocks.map((block) => chain.names[block.first]).toList();
    chains[destination] = Chain(names, p);
    emit('LUMP $name $destination blocks=${blocks.length}');
    showMatrix(names, p);
  }

  void reward(String name, Chain chain, String discount, List<String> words) {
    if (words.length != chain.size) fail('BAD LENGTH');
    final gamma = probability(discount);
    if (gamma == Fraction.one) fail('BAD DISCOUNT');
    final rewards = words.map((word) => Fraction(int.parse(word))).toList();
    final equations = List.generate(chain.size, (i) => [
      for (var j = 0; j < chain.size; j++) delta(i, j) - gamma * chain.p[i][j],
      rewards[i],
    ]);
    final discounted = solve(equations);
    final gain = List.filled(chain.size, Fraction.zero);
    for (final component in chain.graph().classes) {
      if (!component.closed) continue;
      final pi = chain.stationary(component.states);
      final average = total(component.states.map((i) => pi[i] * rewards[i]));
      final h = chain.hitting(component.states, withTimes: false).probability;
      for (var i = 0; i < chain.size; i++) {
        gain[i] = gain[i] + h[i] * average;
      }
    }
    emit('REWARD $name gamma=$gamma');
    for (var i = 0; i < chain.size; i++) {
      emit('VALUE ${chain.names[i]} discounted=${discounted[i][0].value} gain=${gain[i].value}');
    }
  }

  void restrict(String name, Chain chain, String destination, List<String> words) {
    final states = chain.stateSet(words);
    for (final i in states) {
      if (chain.indices.any((j) => !states.contains(j) && !chain.p[i][j].isZero)) {
        fail('NOT CLOSED ${chain.names[i]}');
      }
    }
    final names = states.map((i) => chain.names[i]).toList();
    final p = states.map((i) => states.map((j) => chain.p[i][j]).toList()).toList();
    chains[destination] = Chain(names, p);
    emit('RESTRICT $name $destination states=${states.length}');
    showMatrix(names, p);
  }

  void simulate(String name, Chain chain, String from, int steps, int seed) {
    final start = chain.state(from);
    if (steps == 0) fail('BAD STEPS');
    if (seed == 0 || seed >= 2147483647) fail('BAD SEED');
    var random = seed;
    final path = [start];
    final visits = List<int>.filled(chain.size, 0);
    visits[start]++;
    for (var t = 0; t < steps; t++) {
      final row = chain.p[path.last];
      var denominator = 1;
      for (final value in row) {
        denominator = denominator ~/ denominator.gcd(value.denominator) * value.denominator;
      }
      random = 48271 * random % 2147483647;
      final target = random % denominator;
      var cumulative = Fraction.zero;
      for (var j = 0; j < chain.size; j++) {
        cumulative = cumulative + row[j];
        if (cumulative.numerator * denominator ~/ cumulative.denominator > target) {
          path.add(j);
          visits[j]++;
          break;
        }
      }
    }
    emit('SIMULATE $name $from steps=$steps seed=$seed end=${chain.names[path.last]}');
    emit('PATH ${chain.labels(path)}');
    for (var i = 0; i < chain.size; i++) {
      emit('VISIT ${chain.names[i]} ${visits[i]}');
    }
  }

  void command(List<String> words) {
    final op = words[0];
    final name = words[1];
    switch (op) {
      case 'CHAIN': create(words); return;
      case 'BUILD': build(words); return;
      case 'GAMBLER': gambler(words); return;
    }
    final chain = chains[name] ?? (fail('UNKNOWN CHAIN $name'));
    if (!const {'P', 'ROW', 'SHOW', 'CHECK'}.contains(op)) chain.stochastic();
    switch (op) {
      case 'P': {
        final x = chain.state(words[2]);
        final y = chain.state(words[3]);
        final value = probability(words[4]);
        chain.p[x][y] = value;
        emit('P $name ${words[2]} ${words[3]} $value rowsum=${total(chain.p[x])}');
        break;
      }
      case 'ROW': {
        final x = chain.state(words[2]);
        if (words.length - 3 != chain.size) fail('BAD LENGTH');
        final values = words.skip(3).map(probability).toList();
        chain.p[x] = values;
        emit('ROW $name ${words[2]} rowsum=${total(values)}');
        break;
      }
      case 'SHOW':
        emit('MATRIX $name states=${chain.size}');
        showMatrix(chain.names, chain.p);
        break;
      case 'CHECK': {
        final sums = chain.p.map(total).toList();
        final bad = chain.indices.where((i) => sums[i] != Fraction.one).toList();
        emit('CHECK $name ${bad.isEmpty ? 'ok' : 'bad=${bad.length}'}');
        for (final i in bad) {
          emit('BADROW ${chain.names[i]} sum=${sums[i]}');
        }
        break;
      }
      case 'CLASSES': classes(name, chain); break;
      case 'CLASSIFY': classify(name, chain); break;
      case 'STEP': step(name, chain, words[2], int.parse(words[3])); break;
      case 'POWER': {
        final steps = int.parse(words[2]);
        var power = identity(chain.size);
        for (var t = 0; t < steps; t++) {
          power = multiply(power, chain.p);
        }
        emit('POWER $name k=$steps');
        showMatrix(chain.names, power);
        break;
      }
      case 'STATIONARY': stationary(name, chain); break;
      case 'RECURRENCE': {
        final x = chain.state(words[2]);
        final component = chain.graph().classes.firstWhere((component) => component.states.contains(x));
        if (!component.closed) fail('TRANSIENT STATE ${words[2]}');
        final pi = chain.stationary(component.states)[x];
        emit('RECURRENCE $name ${words[2]} pi=${pi.value} mean=${(Fraction.one / pi).value} period=${component.period}');
        break;
      }
      case 'ABSORB': absorb(name, chain); break;
      case 'HITTING': {
        final targets = chain.stateSet(words.skip(2));
        final result = chain.hitting(targets);
        emit('HITTING $name targets=${chain.labels(targets, ',')}');
        for (var i = 0; i < chain.size; i++) {
          emit('HIT ${chain.names[i]} prob=${result.probability[i].value} time=${result.time[i]?.value ?? 'inf'}');
        }
        break;
      }
      case 'PASSAGE': passage(name, chain); break;
      case 'FIRSTPASSAGE': firstPassage(name, chain, words[2], words[3], int.parse(words[4])); break;
      case 'PATHPROB': {
        final path = words.skip(2).map(chain.state).toList();
        var chance = Fraction.one;
        int? zeroAt;
        for (var i = 1; i < path.length; i++) {
          chance = chance * chain.p[path[i - 1]][path[i]];
          if (chance.isZero) zeroAt ??= i;
        }
        emit('PATHPROB $name steps=${path.length - 1} prob=${chance.value}${zeroAt == null ? '' : ' zero_at=$zeroAt'}');
        break;
      }
      case 'MOSTLIKELY': mostLikely(name, chain, words[2], int.parse(words[3])); break;
      case 'REVERSIBLE': reversible(name, chain); break;
      case 'REVERSE': reverse(name, chain, words[2]); break;
      case 'MIXING': mixing(name, chain, int.parse(words[2]), words[3]); break;
      case 'LUMP': lump(name, chain, words[2], words[3]); break;
      case 'REWARD': reward(name, chain, words[2], words.sublist(3)); break;
      case 'RESTRICT': restrict(name, chain, words[2], words.sublist(3)); break;
      case 'SIMULATE': simulate(name, chain, words[2], int.parse(words[3]), int.parse(words[4])); break;
    }
  }

  void execute(String line) {
    try {
      command(line.split(' '));
    } on CommandError catch (error) {
      emit('ERROR ${error.message}');
    }
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final analyzer = Analyzer();
  for (var i = 0; i < count; i++) {
    analyzer.execute(stdin.readLineSync()!);
  }
  stdout.write(analyzer.output);
}
