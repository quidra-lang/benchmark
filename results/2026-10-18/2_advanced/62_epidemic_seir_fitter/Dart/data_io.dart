part of 'main.dart';

class Group {
  final String name;
  final int population;
  final double fatality;
  Group(this.name, this.population, this.fatality);
}

class Intervention {
  final int day;
  final double multiplier;
  Intervention(this.day, this.multiplier);
}

class Scenario {
  final String name;
  final double multiplier;
  Scenario(this.name, this.multiplier);
}

class ContactChange {
  final String name, group;
  final double factor;
  ContactChange(this.name, this.group, this.factor);
}

class Params {
  double sigma = 0,
      gamma = 0,
      e0 = 0,
      i0 = 0,
      betaMin = 0,
      betaMax = 0,
      rhoMin = 0,
      rhoMax = 0,
      deltaBeta = 0,
      deltaGamma = 0,
      alpha = 0,
      chi = 0,
      psi = 0,
      omega = 0,
      effectWidth = 0,
      outlier = 0,
      threshold = 0;
  int betaCount = 0,
      rhoCount = 0,
      golden = 0,
      rounds = 0,
      nelder = 0,
      holdout = 0,
      deathLag = 0,
      generation = 0,
      horizon = 0;
  final milestones = <int>[],
      scenarios = <Scenario>[],
      changes = <ContactChange>[];
}

class Data {
  final cases = <int>[],
      deaths = <int>[],
      groups = <Group>[],
      contacts = <List<double>>[],
      interventions = <Intervention>[];
  final params = Params();
  int population = 0;
  double fatality = 0;
}

List<String> lines(String path) => File(path).readAsLinesSync();
Data readData() {
  final d = Data();
  for (final line in lines('input/cases.csv').skip(1)) {
    final a = line.split(',');
    d.cases.add(int.parse(a[1]));
    d.deaths.add(int.parse(a[2]));
  }
  for (final line in lines('input/population.txt')) {
    final a = line.split(' ');
    if (a[0] == 'group') {
      final g = Group(a[1], int.parse(a[2]), double.parse(a[3]));
      d.groups.add(g);
      d.population += g.population;
      d.fatality += g.population * g.fatality;
    } else {
      d.contacts.add(a.sublist(1).map(double.parse).toList());
    }
  }
  d.fatality /= d.population;
  for (final line in lines('input/interventions.txt')) {
    final a = line.split(' ');
    d.interventions.add(Intervention(int.parse(a[0]), double.parse(a[1])));
  }
  final p = d.params;
  for (final line in lines('input/params.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'sigma':
        p.sigma = double.parse(a[1]);
      case 'gamma':
        p.gamma = double.parse(a[1]);
      case 'initial':
        p.e0 = double.parse(a[1]);
        p.i0 = double.parse(a[2]);
      case 'beta_grid':
        p.betaMin = double.parse(a[1]);
        p.betaMax = double.parse(a[2]);
        p.betaCount = int.parse(a[3]);
      case 'rho_grid':
        p.rhoMin = double.parse(a[1]);
        p.rhoMax = double.parse(a[2]);
        p.rhoCount = int.parse(a[3]);
      case 'golden':
        p.golden = int.parse(a[1]);
        p.rounds = int.parse(a[2]);
      case 'simplex':
        p.deltaBeta = double.parse(a[1]);
        p.deltaGamma = double.parse(a[2]);
      case 'nelder_mead':
        p.alpha = double.parse(a[1]);
        p.chi = double.parse(a[2]);
        p.psi = double.parse(a[3]);
        p.omega = double.parse(a[4]);
        p.nelder = int.parse(a[5]);
      case 'holdout':
        p.holdout = int.parse(a[1]);
      case 'effect_width':
        p.effectWidth = double.parse(a[1]);
      case 'outlier':
        p.outlier = double.parse(a[1]);
      case 'death_lag':
        p.deathLag = int.parse(a[1]);
      case 'milestones':
        p.milestones.addAll(a.sublist(1).map(int.parse));
      case 'generation':
        p.generation = int.parse(a[1]);
      case 'horizon':
        p.horizon = int.parse(a[1]);
      case 'threshold':
        p.threshold = double.parse(a[1]);
      case 'scenario':
        p.scenarios.add(Scenario(a[1], double.parse(a[2])));
      case 'contact_change':
        p.changes.add(ContactChange(a[1], a[2], double.parse(a[3])));
    }
  }
  return d;
}

void writeLines(String name, List<String> a) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${a.join('\n')}\n');
}
