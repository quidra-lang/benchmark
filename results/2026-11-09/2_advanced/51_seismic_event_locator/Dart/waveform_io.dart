part of 'main.dart';

class Params {
  final Map<String, List<String>> values;
  Params(this.values);
  int integer(String key, [int index = 0]) => int.parse(values[key]![index]);
  double real(String key, [int index = 0]) => double.parse(values[key]![index]);
}

class Station {
  final String code;
  final int x, y, elevation, order;
  int start = 0,
      mean = 0,
      peak = 0,
      clippedSamples = 0,
      triggers = 0,
      shortTriggers = 0;
  final samples = <int>[], picks = <Pick>[];
  double noise = 0, timeCorrection = 0, magCorrection = 0;
  final firstResiduals = <double>[],
      finalResiduals = <double>[],
      magResiduals = <double>[];
  Station(this.code, this.x, this.y, this.elevation, this.order);
}

List<String> readLines(String path) => File(path).readAsLinesSync();
(List<Station>, Params) loadInputs() {
  final stations = <Station>[];
  for (final line in readLines('input/stations.csv').skip(1)) {
    final f = line.split(',');
    stations.add(
      Station(
        f[0],
        int.parse(f[1]),
        int.parse(f[2]),
        int.parse(f[3]),
        stations.length,
      ),
    );
  }
  final lines = readLines('input/waveforms.txt');
  var cursor = 0;
  for (final station in stations) {
    final f = lines[cursor++].split(' '), count = int.parse(f[3]);
    station.start = int.parse(f[2]);
    while (station.samples.length < count) {
      station.samples.addAll(lines[cursor++].split(' ').map(int.parse));
    }
  }
  final params = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final f = line.split(' ');
    params[f.first] = f.sublist(1);
  }
  return (stations, Params(params));
}
