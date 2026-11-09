part of 'main.dart';

class RiskSet {
  final int time, risk, events, censored;
  RiskSet(this.time, this.risk, this.events, this.censored);
}

List<RiskSet> riskSets(List<Subject> subjects) {
  final counts = <int, int>{}, events = <int, int>{};
  for (final s in subjects) {
    counts[s.time] = (counts[s.time] ?? 0) + 1;
    events[s.time] = (events[s.time] ?? 0) + s.event;
  }
  final times = counts.keys.toList()..sort(), rows = <RiskSet>[];
  var risk = subjects.length;
  for (final t in times) {
    rows.add(RiskSet(t, risk, events[t]!, counts[t]! - events[t]!));
    risk -= counts[t]!;
  }
  return rows;
}

class KMRow {
  final int time, risk, events, censored;
  final double survival, se, lower, upper, hazard, hazardSE;
  KMRow(
    this.time,
    this.risk,
    this.events,
    this.censored,
    this.survival,
    this.se,
    this.lower,
    this.upper,
    this.hazard,
    this.hazardSE,
  );
}

List<KMRow> kaplanMeier(List<Subject> subjects) {
  final times = riskSets(subjects),
      eventTimes = [
        for (final r in times)
          if (r.events > 0) r.time,
      ],
      rows = <KMRow>[];
  var survival = 1.0, greenwood = 0.0, hazard = 0.0, variance = 0.0;
  for (final r in times) {
    final n = r.risk, d = r.events;
    if (d == 0) continue;
    survival *= (n - d) / n;
    if (n == d) {
      greenwood = double.nan;
    } else if (!greenwood.isNaN) {
      greenwood += d / (n * (n - d));
    }
    var se = double.nan, lo = double.nan, hi = double.nan;
    if (survival != 0) {
      final root = math.sqrt(greenwood),
          l = math.log(survival),
          omega = z95 * root / (-l);
      se = survival * root;
      lo = math.exp(l * math.exp(omega));
      hi = math.exp(l * math.exp(-omega));
    }
    hazard += d / n;
    variance += d / (n * n);
    final index = rows.length;
    var censored = 0;
    for (final s in subjects) {
      if (s.event == 0 &&
          s.time >= r.time &&
          (index + 1 == eventTimes.length || s.time < eventTimes[index + 1]))
        censored++;
    }
    rows.add(
      KMRow(
        r.time,
        n,
        d,
        censored,
        survival,
        se,
        lo,
        hi,
        hazard,
        math.sqrt(variance),
      ),
    );
  }
  return rows;
}

KMRow rowAt(List<KMRow> rows, int t) {
  for (var j = rows.length - 1; j >= 0; j--) {
    if (rows[j].time <= t) return rows[j];
  }
  return KMRow(0, 0, 0, 0, 1, 0, double.nan, double.nan, 0, 0);
}

class LifeRow {
  final int start, end, risk, events, withdrawn;
  final double exposed, q, survival, se, hazard;
  LifeRow(
    this.start,
    this.end,
    this.risk,
    this.events,
    this.withdrawn,
    this.exposed,
    this.q,
    this.survival,
    this.se,
    this.hazard,
  );
}

List<LifeRow> lifeTable(List<Subject> subjects, int width, int count) {
  final rows = <LifeRow>[];
  var survival = 1.0, variance = 0.0;
  for (var i = 0; i < count; i++) {
    final a = i * width, b = (i + 1) * width;
    var n = 0, d = 0, c = 0;
    for (final s in subjects) {
      if (s.time >= a) n++;
      if (a <= s.time && s.time < b) {
        if (s.event == 1)
          d++;
        else
          c++;
      }
    }
    final f = 2 * n - c;
    survival *= (f - 2 * d) / f;
    variance += 4 * d / (f * (f - 2 * d));
    rows.add(
      LifeRow(
        a,
        b,
        n,
        d,
        c,
        f / 2,
        2 * d / f,
        survival,
        survival * math.sqrt(variance),
        2000 * d / (width * (f - d)),
      ),
    );
  }
  return rows;
}
