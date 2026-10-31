part of 'main.dart';

class Settings {
  late DateTime epoch;
  String reference = '', plot = '';
  int flat = 0,
      w = 0,
      c = 0,
      top = 0,
      surgeHours = 0,
      start = 0,
      hours = 0,
      grid = 0,
      lag = 0,
      plotWidth = 0,
      zt = 0,
      zb = 0,
      zs = 0;
  double ks = 0, d = 0, rayleigh = 0, snr = 0, surge = 0, minRange = 0;
}

class Constituent {
  final String name;
  final double speed;
  Constituent(this.name, this.speed);
}

class Station {
  final String code, name;
  int rows = 0;
  final Map<int, double> values = {};
  final Set<int> na = {};
  Station(this.code, this.name);
}

DateTime parseDate(String s) =>
    DateTime.parse('${s.replaceFirst(' ', 'T')}:00Z');
String datetime(Settings p, int minutes) {
  final t = p.epoch.add(Duration(minutes: minutes));
  return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String date(Settings p, int hour) => datetime(p, 60 * hour).substring(0, 10);
(Settings, List<Constituent>, List<Station>) readInput() {
  final p = Settings(), stations = <Station>[];
  for (final line in File('input/params.txt').readAsLinesSync()) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'epoch':
        p.epoch = parseDate('${a[1]} ${a[2]}');
        break;
      case 'station':
        stations.add(Station(a[1], a.skip(2).join(' ')));
        break;
      case 'reference':
        p.reference = a[1];
        break;
      case 'flat_run':
        p.flat = int.parse(a[1]);
        break;
      case 'spike':
        p.w = int.parse(a[1]);
        p.c = int.parse(a[2]);
        p.ks = double.parse(a[3]);
        p.d = double.parse(a[4]);
        break;
      case 'rayleigh':
        p.rayleigh = double.parse(a[1]);
        break;
      case 'snr_min':
        p.snr = double.parse(a[1]);
        break;
      case 'top_residuals':
        p.top = int.parse(a[1]);
        break;
      case 'surge':
        p.surge = double.parse(a[1]);
        p.surgeHours = int.parse(a[2]);
        break;
      case 'predict':
        p.start = parseDate('${a[1]} ${a[2]}').difference(p.epoch).inHours;
        p.hours = int.parse(a[3]);
        break;
      case 'grid_minutes':
        p.grid = int.parse(a[1]);
        break;
      case 'min_range':
        p.minRange = double.parse(a[1]);
        break;
      case 'correlation_lag':
        p.lag = int.parse(a[1]);
        break;
      case 'plot':
        p.plot = a[1];
        p.plotWidth = int.parse(a[2]);
        p.zt = int.parse(a[3]);
        p.zb = int.parse(a[4]);
        p.zs = int.parse(a[5]);
        break;
    }
  }
  final constituents = <Constituent>[];
  for (final line in File('input/constituents.txt').readAsLinesSync().skip(1)) {
    final a = line.split(' ');
    constituents.add(Constituent(a[0], double.parse(a[1])));
  }
  final byCode = {for (final s in stations) s.code: s};
  for (final line in File('input/observations.csv').readAsLinesSync().skip(1)) {
    final a = line.split(','), s = byCode[line.split(',')[0]]!;
    final t = parseDate(a[1]).difference(p.epoch).inHours;
    s.rows++;
    if (a[2] == 'NA') {
      s.na.add(t);
    } else {
      s.values[t] = double.parse(a[2]);
    }
  }
  return (p, constituents, stations);
}
