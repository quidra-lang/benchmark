part of 'main.dart';
const descriptors = {
  'MI': 'shallow',
  'BC': 'patches',
  'PR': 'partial',
  'DR': 'low drifting',
  'BL': 'blowing',
  'SH': 'showers',
  'TS': 'thunderstorm',
  'FZ': 'freezing',
};

const phenomena = {
  'DZ': 'drizzle',
  'RA': 'rain',
  'SN': 'snow',
  'SG': 'snow grains',
  'IC': 'ice crystals',
  'PL': 'ice pellets',
  'GR': 'hail',
  'GS': 'small hail',
  'UP': 'unknown precipitation',
  'BR': 'mist',
  'FG': 'fog',
  'FU': 'smoke',
  'VA': 'volcanic ash',
  'DU': 'dust',
  'SA': 'sand',
  'HZ': 'haze',
  'PY': 'spray',
  'PO': 'dust whirls',
  'SQ': 'squalls',
  'FC': 'funnel cloud',
  'SS': 'sandstorm',
  'DS': 'duststorm',
};

const precipitation = ['DZ', 'RA', 'SN', 'SG', 'IC', 'PL', 'GR', 'GS', 'UP'];

const amounts = {
  'FEW': 'few',
  'SCT': 'scattered',
  'BKN': 'broken',
  'OVC': 'overcast',
};

const clearSkies = {
  'SKC': 'sky clear',
  'CLR': 'clear below 12000 ft',
  'NSC': 'no significant cloud',
};

const intensities = {
  '-': 'light',
  '+': 'heavy',
  'VC': 'nearby',
};

class Reading {
  final String qualifier;
  final int value;
  Reading(this.qualifier, this.value);
}

class Group {
  final String text, kind;
  final String direction;
  final int speed;
  final int? gust;
  final String unit;
  final int firstDirection;
  final int secondDirection;
  final String visibilityKind;
  final String qualifier;
  final int meters;
  final int whole;
  final int numerator;
  final int denominator;
  final bool joined;
  final String runway;
  final List<Reading> readings;
  final bool feet;
  final String trend;
  final String intensity;
  final List<String> codes;
  final String amount;
  final int height;
  final String cloudType;
  final int air;
  final int dewPoint;
  final int pressureValue;
  Group(this.text, this.kind, {
    this.direction = '',
    this.speed = 0,
    this.gust = null,
    this.unit = '',
    this.firstDirection = 0,
    this.secondDirection = 0,
    this.visibilityKind = '',
    this.qualifier = '',
    this.meters = 0,
    this.whole = 0,
    this.numerator = 0,
    this.denominator = 0,
    this.joined = false,
    this.runway = '',
    this.readings = const [],
    this.feet = false,
    this.trend = '',
    this.intensity = '',
    this.codes = const [],
    this.amount = '',
    this.height = 0,
    this.cloudType = '',
    this.air = 0,
    this.dewPoint = 0,
    this.pressureValue = 0,
  });
  bool get calm => kind == 'wind' && direction == '000';
  bool get directed => kind == 'wind' && direction != 'VRB' && !calm;
  int get strength => gust ?? speed;
  String get descriptor => codes.isNotEmpty && descriptors.containsKey(codes.first) ? codes.first : '';
  List<String> get weatherPhenomena => codes.where(phenomena.containsKey).toList();
}

class State {
  Group? wind, visibility;
  List<Group>? weather, cloud;
  State([this.wind, this.visibility, this.weather, this.cloud]);
}

class Section {
  final List<String> runways;
  final bool allowsNsw;
  final state = State();
  Group? modifier, variation, temperature, pressure, noTrend;
  final rvrs = <Group>[];
  Section([this.runways = const [], this.allowsNsw = false]);
  void record(Group g) {
    switch (g.kind) {
      case 'wind':
        state.wind = Group(g.text, g.kind, direction: g.direction, unit: 'KT',
            speed: knots(g.speed, g.unit), gust: g.gust == null ? null : knots(g.gust!, g.unit));
      case 'visibility': state.visibility = g;
      case 'weather': (state.weather ??= []).add(g);
      case 'cloud': (state.cloud ??= []).add(g);
      case 'modifier': modifier = g;
      case 'variation': variation = g;
      case 'temperature': temperature = g;
      case 'pressure': pressure = g;
      case 'no trend': noTrend = g;
      case 'rvr': rvrs.add(g);
    }
  }
}

List<String>? captures(String pattern, String text) {
  final m = RegExp('^(?:$pattern)\$').firstMatch(text);
  return m == null ? null : [for (var i = 1; i <= m.groupCount; i++) m.group(i) ?? ''];
}

bool digits(String text, int a, int b) => text.length >= a && text.length <= b && RegExp(r'^[0-9]+$').hasMatch(text);

Group? parseGroup(String kind, String t) {
  List<String>? m;
  switch (kind) {
    case 'modifier': return ['AUTO', 'COR'].contains(t) ? Group(t, kind) : null;
    case 'no trend': return t == 'NOSIG' ? Group(t, kind) : null;
    case 'wind':
      m = captures(r'(VRB|[0-9]{3})([0-9]{2,3})(?:G([0-9]{2,3}))?(KT|MPS)', t);
      if (m != null) return Group(t, kind, direction: m[0], speed: int.parse(m[1]), gust: int.tryParse(m[2]), unit: m[3]);
    case 'variation':
      m = captures(r'([0-9]{3})V([0-9]{3})', t);
      if (m != null) return Group(t, kind, firstDirection: int.parse(m[0]), secondDirection: int.parse(m[1]));
    case 'visibility':
      if (t == 'CAVOK') return Group(t, kind, visibilityKind: 'CAVOK', qualifier: 'P', meters: 10000);
      if (digits(t, 4, 4)) return Group(t, kind, visibilityKind: 'METERS', qualifier: t == '9999' ? 'P' : '', meters: t == '9999' ? 10000 : int.parse(t));
      m = captures(r'([0-9]) ([0-9])/([0-9]{1,2})SM', t);
      if (m != null) return Group(t, kind, visibilityKind: 'MILES', joined: true, whole: int.parse(m[0]), numerator: int.parse(m[1]), denominator: int.parse(m[2]));
      m = captures(r'([MP]?)(?:([0-9]{1,2})|([0-9])/([0-9]{1,2}))SM', t);
      if (m != null) return Group(t, kind, visibilityKind: 'MILES', qualifier: m[0], whole: int.tryParse(m[1]) ?? 0, numerator: int.tryParse(m[2]) ?? 0, denominator: int.tryParse(m[3]) ?? 0);
    case 'rvr':
      m = captures(r'R([0-9]{2}[LCR]?)/([MP]?)([0-9]{4})(?:V([MP]?)([0-9]{4}))?(FT)?([UDN]?)', t);
      if (m != null) return Group(t, kind, runway: m[0], readings: [Reading(m[1], int.parse(m[2])), if (m[4].isNotEmpty) Reading(m[3], int.parse(m[4]))], feet: m[5] == 'FT', trend: m[6]);
    case 'weather':
      if (t == 'NSW') return Group(t, kind);
      m = captures(r'(-|\+|VC)?([A-Z]+)', t);
      if (m != null && m[1].length.isEven) {
        final codes = [for (var i = 0; i < m[1].length; i += 2) m[1].substring(i, i + 2)];
        if (codes.every((c) => descriptors.containsKey(c) || phenomena.containsKey(c))) return Group(t, kind, intensity: m[0], codes: codes);
      }
    case 'cloud':
      if (clearSkies.containsKey(t)) return Group(t, kind, amount: t);
      m = captures(r'(FEW|SCT|BKN|OVC|VV)([0-9]{3})(CB|TCU)?', t);
      if (m != null && (m[0] != 'VV' || m[2].isEmpty)) return Group(t, kind, amount: m[0], height: int.parse(m[1]) * 100, cloudType: m[2]);
    case 'temperature':
      m = captures(r'(M?[0-9]{2})/(M?[0-9]{2})', t);
      if (m != null) {
        int celsius(String v) => v.startsWith('M') ? -int.parse(v.substring(1)) : int.parse(v);
        return Group(t, kind, air: celsius(m[0]), dewPoint: celsius(m[1]));
      }
    case 'pressure':
      m = captures(r'([AQ])([0-9]{4})', t);
      if (m != null) return Group(t, kind, unit: m[0], pressureValue: int.parse(m[1]));
  }
  return null;
}

bool validGroup(Group g, Section section) {
  final state = section.state;
  switch (g.kind) {
    case 'wind':
      if (g.direction == 'VRB') {
        if (g.speed < 1) return false;
      } else {
        final d = int.parse(g.direction);
        if (d > 360 || d % 10 != 0 || (d == 0) != (g.speed == 0)) return false;
      }
      return g.gust == null || (!g.calm && g.gust! > g.speed);
    case 'variation':
      return [g.firstDirection, g.secondDirection].every((d) => d >= 10 && d <= 360 && d % 10 == 0) && g.firstDirection != g.secondDirection && (state.wind?.directed ?? false);
    case 'visibility':
      if (g.visibilityKind != 'MILES') return true;
      if (g.denominator == 0) return !g.text.contains('/') && g.whole >= 1;
      return (!g.joined || g.whole >= 1) && [2, 4, 8, 16].contains(g.denominator) && g.numerator >= 1 && g.numerator < g.denominator;
    case 'rvr':
      return section.runways.contains(g.runway) && (g.readings.length == 1 || g.readings.first.value < g.readings.last.value);
    case 'weather':
      final accepted = state.weather ?? [], p = g.weatherPhenomena;
      if (accepted.length >= 3 || accepted.any((v) => v.text == 'NSW')) return false;
      if (g.text == 'NSW') return section.allowsNsw && accepted.isEmpty;
      if (g.codes.skip(1).any(descriptors.containsKey) || p.toSet().length != p.length) return false;
      if (p.isEmpty && !['TS', 'SH'].contains(g.descriptor)) return false;
      if (['-', '+'].contains(g.intensity) && !p.any(precipitation.contains)) return false;
      return p.length < 2 || p.every(precipitation.contains);
    case 'cloud':
      final accepted = state.cloud ?? [];
      return accepted.isEmpty || (amounts.containsKey(g.amount) && amounts.containsKey(accepted.last.amount) && g.height > accepted.last.height);
    case 'temperature': return g.dewPoint <= g.air;
    case 'pressure': return g.unit == 'A' ? g.pressureValue >= 2500 && g.pressureValue <= 3150 : g.pressureValue >= 850 && g.pressureValue <= 1070;
    default: return true;
  }
}
