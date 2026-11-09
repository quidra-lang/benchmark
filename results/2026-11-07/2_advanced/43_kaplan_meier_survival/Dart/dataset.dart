part of 'main.dart';

class Subject {
  final int id, time, event, age, stage;
  final String group, sex;
  Subject(
    this.id,
    this.group,
    this.time,
    this.event,
    this.age,
    this.sex,
    this.stage,
  );
  Subject reversed() => Subject(id, group, time, 1 - event, age, sex, stage);
}

class Params {
  final List<String> groups, subgroups, covariates;
  final List<int> times, plot;
  final int tau, width, intervals, landmark, residuals;
  final String strata;
  Params(
    this.groups,
    this.times,
    this.tau,
    this.width,
    this.intervals,
    this.strata,
    this.subgroups,
    this.landmark,
    this.covariates,
    this.residuals,
    this.plot,
  );
}

(List<Subject>, Params) readDataset() {
  final subjects = <Subject>[];
  for (final line in File('input/subjects.csv').readAsLinesSync().skip(1)) {
    final f = line.split(',');
    subjects.add(
      Subject(
        int.parse(f[0]),
        f[1],
        int.parse(f[2]),
        int.parse(f[3]),
        int.parse(f[4]),
        f[5],
        int.parse(f[6]),
      ),
    );
  }
  subjects.sort((a, b) => a.id.compareTo(b.id));
  final v = <String, List<String>>{};
  for (final line in File('input/params.txt').readAsLinesSync()) {
    final f = line.split(' ');
    v[f[0]] = f.sublist(1);
  }
  return (
    subjects,
    Params(
      v['GROUPS']!,
      v['REPORT_TIMES']!.map(int.parse).toList(),
      int.parse(v['TAU']![0]),
      int.parse(v['LIFE_TABLE']![0]),
      int.parse(v['LIFE_TABLE']![1]),
      v['STRATA']![0],
      v['SUBGROUPS']!,
      int.parse(v['LANDMARK']![0]),
      v['COX']!,
      int.parse(v['RESIDUALS']![0]),
      v['PLOT']!.map(int.parse).toList(),
    ),
  );
}
