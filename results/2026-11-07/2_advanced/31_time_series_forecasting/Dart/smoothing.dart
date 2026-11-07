part of 'main.dart';

class SmoothParameters {
  final double alpha, beta, gamma, phi;
  SmoothParameters({
    this.alpha = 0,
    this.beta = 0,
    this.gamma = 0,
    this.phi = 1,
  });
  SmoothParameters withValue(String key, double value) => SmoothParameters(
    alpha: key == 'alpha' ? value : alpha,
    beta: key == 'beta' ? value : beta,
    gamma: key == 'gamma' ? value : gamma,
    phi: key == 'phi' ? value : phi,
  );
  double value(String key) => switch (key) {
    'alpha' => alpha,
    'beta' => beta,
    'gamma' => gamma,
    _ => phi,
  };
}

class SmoothState {
  final double level, slope;
  final List<double>? seasonal;
  SmoothState(this.level, this.slope, this.seasonal);
}

(List<double>, List<SmoothState>) smoothRecurse(
  String name,
  List<double> values,
  int season,
  SmoothParameters p,
) {
  final seasonal = name == 'hw_add' || name == 'hw_mult',
      errors = <double>[],
      states = <SmoothState>[];
  var level = values.first, slope = 0.0;
  List<double>? components;
  if (seasonal) {
    level = mean(values.take(season).toList());
    slope = (mean(values.sublist(season, 2 * season)) - level) / season;
    components = values
        .take(season)
        .map((value) => name == 'hw_add' ? value - level : value / level)
        .toList();
  } else if (name != 'ses') {
    slope = (values[season] - values[0]) / season;
  }
  for (var t = 0; t < values.length; t++) {
    states.add(
      SmoothState(
        level,
        slope,
        components == null ? null : List<double>.of(components),
      ),
    );
    final observed = values[t];
    double predicted, nextLevel, nextSlope;
    if (name == 'ses') {
      predicted = level;
      nextLevel = p.alpha * observed + (1 - p.alpha) * level;
      nextSlope = slope;
    } else if (seasonal) {
      final current = components!;
      final j = t % season,
          previous = current[t % season],
          base = level + slope;
      if (name == 'hw_add') {
        predicted = base + previous;
        nextLevel = p.alpha * (observed - previous) + (1 - p.alpha) * base;
        current[j] = p.gamma * (observed - base) + (1 - p.gamma) * previous;
      } else {
        predicted = base * previous;
        nextLevel = p.alpha * (observed / previous) + (1 - p.alpha) * base;
        current[j] = p.gamma * (observed / base) + (1 - p.gamma) * previous;
      }
      nextSlope = p.beta * (nextLevel - level) + (1 - p.beta) * slope;
    } else {
      predicted = level + p.phi * slope;
      nextLevel = p.alpha * observed + (1 - p.alpha) * predicted;
      nextSlope = p.beta * (nextLevel - level) + (1 - p.beta) * p.phi * slope;
    }
    errors.add(observed - predicted);
    level = nextLevel;
    slope = nextSlope;
  }
  states.add(
    SmoothState(
      level,
      slope,
      components == null ? null : List<double>.of(components),
    ),
  );
  return (errors, states);
}

List<double> smoothForecast(
  String name,
  SmoothState state,
  SmoothParameters p,
  int origin,
  int steps,
  int season,
) {
  final result = <double>[];
  var power = p.phi, accumulated = 0.0;
  for (var k = 1; k <= steps; k++) {
    var value = state.level;
    if (name == 'holt' || name == 'damped') {
      accumulated += power;
      value += accumulated * state.slope;
      power *= p.phi;
    } else if (name == 'hw_add' || name == 'hw_mult') {
      final component = state.seasonal![(origin + k - 1) % season],
          base = state.level + k * state.slope;
      value = name == 'hw_add' ? base + component : base * component;
    }
    result.add(value);
  }
  return result;
}
