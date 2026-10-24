part of 'main.dart';
const categories = ['VFR', 'MVFR', 'IFR', 'LIFR'];

bool covers(Forecast f, int t) => f.issue <= t && f.start <= t-t%60 && t-t%60<f.end;

Forecast? chosenForecast(List<Forecast> fs, int t) {
  Forecast? chosen;
  for (final f in fs) {
    if (covers(f, t) && (chosen == null || f.issue >= chosen.issue)) chosen = f;
  }
  return chosen;
}

class Contingency {
  final table = List.generate(4, (_) => List.filled(4, 0));
  int temporaryHits = 0;
  void add(String expected, String observed, bool hit) {
    table[categories.indexOf(expected)][categories.indexOf(observed)]++;
    if (hit) temporaryHits++;
  }
  int row(int i) => table[i].fold(0, (a, b) => a + b);
  int column(int i) => table.fold(0, (a, b) => a + b[i]);
  int get total => List.generate(4, row).fold(0, (a, b) => a + b);
  int get hits => List.generate(4, (i) => table[i][i]).fold(0, (a, b) => a + b);
  (int, int) get skill {
    final e = List.generate(4, (i) => row(i)*column(i)).fold(0, (a, b) => a + b);
    return(total*hits-e, total*total-e);
  }
  (int, int) detection(int i) => (table[i][i], column(i));
  (int, int) falseAlarm(int i) => (row(i)-table[i][i], row(i));
}
