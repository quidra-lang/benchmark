part of 'main.dart';

const circlePi = 3.141592653589793;
typedef Solution = List<double>;

class Observation {
  final Station station;
  final double time;
  Observation(this.station, this.time);
}

class GridResult {
  final Solution solution;
  final double rms;
  final List<double> profile;
  GridResult(this.solution, this.rms, this.profile);
}

class Iteration {
  final int number;
  final Solution solution;
  final double rms;
  Iteration(this.number, this.solution, this.rms);
}

class LocationRun {
  final Solution solution;
  final double rms;
  final List<Iteration> trace;
  final List<double> residuals;
  GridResult? grid;
  LocationRun(this.solution, this.rms, this.trace, this.residuals);
}

class Ellipse {
  final double smaj, smin, az, erz, ert;
  Ellipse(this.smaj, this.smin, this.az, this.erz, this.ert);
}

double distance(Solution solution, Station station) {
  final dx = solution[0] - station.x,
      dy = solution[1] - station.y,
      dz = solution[2] + station.elevation;
  return sqrt(dx * dx + dy * dy + dz * dz);
}

List<double> residuals(
  Solution solution,
  List<Observation> observations,
  double velocity,
) => [
  for (final o in observations)
    o.time - solution[3] - distance(solution, o.station) / velocity,
];
double rms(Solution solution, List<Observation> observations, double velocity) {
  var total = 0.0;
  for (final v in residuals(solution, observations, velocity)) {
    total += v * v;
  }
  return sqrt(total / observations.length);
}

GridResult gridSearch(List<Observation> observations, Params p) {
  final velocity = p.real('velocity'),
      zmin = p.integer('grid_z'),
      zmax = p.integer('grid_z', 1),
      zstep = p.integer('grid_z', 2),
      profile = List.filled(
        (p.integer('grid_z', 1) - p.integer('grid_z')) ~/
                p.integer('grid_z', 2) +
            1,
        double.infinity,
      );
  var best = double.infinity;
  Solution selected = [];
  for (
    var x = p.integer('grid_x');
    x <= p.integer('grid_x', 1);
    x += p.integer('grid_x', 2)
  ) {
    for (
      var y = p.integer('grid_y');
      y <= p.integer('grid_y', 1);
      y += p.integer('grid_y', 2)
    ) {
      for (var z = zmin; z <= zmax; z += zstep) {
        final solution = <double>[x.toDouble(), y.toDouble(), z.toDouble(), 0],
            deltas = [
              for (final o in observations)
                o.time - distance(solution, o.station) / velocity,
            ],
            origin = sum(deltas) / deltas.length;
        var error = 0.0;
        for (final v in deltas) {
          final d = v - origin;
          error += d * d;
        }
        if (error < best) {
          best = error;
          solution[3] = origin;
          selected = solution;
        }
        final index = (z - zmin) ~/ zstep;
        if (error < profile[index]) {
          profile[index] = error;
        }
      }
    }
  }
  return GridResult(selected, sqrt(best / observations.length), [
    for (final v in profile) sqrt(v / observations.length),
  ]);
}

List<List<double>> cholesky(List<List<double>> a) {
  final l = List.generate(4, (_) => List.filled(4, 0.0));
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col <= row; col++) {
      var total = 0.0;
      for (var j = 0; j < col; j++) {
        total += l[row][j] * l[col][j];
      }
      final value = a[row][col] - total;
      l[row][col] = row == col ? sqrt(value) : value / l[col][col];
    }
  }
  return l;
}

List<double> choleskySolve(List<List<double>> l, List<double> b) {
  final u = List.filled(4, 0.0), x = List.filled(4, 0.0);
  for (var row = 0; row < 4; row++) {
    var total = 0.0;
    for (var col = 0; col < row; col++) {
      total += l[row][col] * u[col];
    }
    u[row] = (b[row] - total) / l[row][row];
  }
  for (var row = 3; row >= 0; row--) {
    var total = 0.0;
    for (var col = row + 1; col < 4; col++) {
      total += l[col][row] * x[col];
    }
    x[row] = (u[row] - total) / l[row][row];
  }
  return x;
}

(List<List<double>>, List<double>) normals(
  Solution solution,
  List<Observation> observations,
  double velocity,
) {
  final a = List.generate(4, (_) => List.filled(4, 0.0)),
      b = List.filled(4, 0.0),
      values = residuals(solution, observations, velocity);
  for (var i = 0; i < observations.length; i++) {
    final o = observations[i],
        d = distance(solution, o.station),
        g = <double>[
          (solution[0] - o.station.x) / (velocity * d),
          (solution[1] - o.station.y) / (velocity * d),
          (solution[2] + o.station.elevation) / (velocity * d),
          1,
        ];
    for (var row = 0; row < 4; row++) {
      b[row] += g[row] * values[i];
      for (var col = 0; col < 4; col++) {
        a[row][col] += g[row] * g[col];
      }
    }
  }
  return (a, b);
}

LocationRun geiger(
  Solution initial,
  List<Observation> observations,
  double velocity,
) {
  final solution = List<double>.of(initial), trace = <Iteration>[];
  for (var i = 1; i <= 8; i++) {
    final (a, b) = normals(solution, observations, velocity);
    final delta = choleskySolve(cholesky(a), b);
    for (var axis = 0; axis < 4; axis++) {
      solution[axis] += delta[axis];
    }
    if (solution[2] < 0) {
      solution[2] = 0;
    }
    trace.add(
      Iteration(
        i,
        List<double>.of(solution),
        rms(solution, observations, velocity),
      ),
    );
  }
  return LocationRun(
    solution,
    rms(solution, observations, velocity),
    trace,
    residuals(solution, observations, velocity),
  );
}

LocationRun runLocation(List<Observation> observations, Params p) {
  final grid = gridSearch(observations, p);
  return geiger(grid.solution, observations, p.real('velocity'))..grid = grid;
}

Ellipse errorEllipse(
  Solution solution,
  List<Observation> observations,
  double velocity,
) {
  final (a, _) = normals(solution, observations, velocity);
  final lower = cholesky(a),
      inverse = List.generate(4, (_) => List.filled(4, 0.0));
  for (var col = 0; col < 4; col++) {
    final unit = List.filled(4, 0.0);
    unit[col] = 1;
    final values = choleskySolve(lower, unit);
    for (var row = 0; row < 4; row++) {
      inverse[row][col] = values[row];
    }
  }
  var total = 0.0;
  for (final v in residuals(solution, observations, velocity)) {
    total += v * v;
  }
  final variance = total / (observations.length - 4),
      xx = variance * inverse[0][0],
      yy = variance * inverse[1][1],
      xy = variance * inverse[0][1],
      mu = (xx + yy) / 2,
      d = (xx - yy) / 2,
      rho = sqrt(d * d + xy * xy),
      theta = atan2(2 * xy, xx - yy) / 2 * 180 / circlePi;
  return Ellipse(
    sqrt(mu + rho),
    sqrt(mu - rho),
    90 - theta,
    sqrt(variance * inverse[2][2]),
    sqrt(variance * inverse[3][3]),
  );
}
