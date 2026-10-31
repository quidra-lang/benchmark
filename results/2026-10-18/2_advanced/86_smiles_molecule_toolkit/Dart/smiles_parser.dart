part of 'main.dart';

bool digit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
(Atom?, int, bool) organic(String source, int at) {
  if (at + 1 < source.length &&
      (source.substring(at, at + 2) == 'Cl' ||
          source.substring(at, at + 2) == 'Br'))
    return (Atom(symbol: source.substring(at, at + 2)), at + 2, true);
  final c = source[at];
  if ('BCNOPSFI'.contains(c)) return (Atom(symbol: c), at + 1, true);
  if ('bcnops'.contains(c))
    return (Atom(symbol: c.toUpperCase(), aromatic: true), at + 1, true);
  return (null, at, false);
}

(Atom?, String) bracket(String content, Map<String, Element> elements) {
  var i = 0, mass = 0, hydrogens = 0, charge = 0, aromatic = false, symbol = '';
  while (i < content.length && digit(content[i])) {
    i++;
  }
  if (i >= 4 || (i > 0 && content[0] == '0')) return (null, 'bad bracket atom');
  if (i > 0) mass = int.parse(content.substring(0, i));
  if (i == content.length) return (null, 'bad bracket atom');
  final c = content[i];
  if ('bcnops'.contains(c)) {
    symbol = c.toUpperCase();
    aromatic = true;
    i++;
  } else if (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) {
    if (i + 1 < content.length &&
        content[i + 1].compareTo('a') >= 0 &&
        content[i + 1].compareTo('z') <= 0 &&
        elements.containsKey(content.substring(i, i + 2))) {
      symbol = content.substring(i, i + 2);
      i += 2;
    }
    if (symbol.isEmpty) {
      if (!elements.containsKey(c)) return (null, 'unknown element');
      symbol = c;
      i++;
    }
  } else {
    return (null, 'bad bracket atom');
  }
  if (content.substring(i).startsWith('@@')) {
    i += 2;
  } else if (i < content.length && content[i] == '@') {
    i++;
  }
  if (i < content.length && content[i] == 'H') {
    hydrogens = 1;
    i++;
    if (i < content.length && digit(content[i])) {
      hydrogens = int.parse(content[i]);
      i++;
    }
  }
  if (i < content.length && (content[i] == '+' || content[i] == '-')) {
    final sign = content[i] == '-' ? -1 : 1;
    i++;
    var magnitude = 1;
    if (i < content.length && '123456789'.contains(content[i])) {
      magnitude = int.parse(content[i]);
      i++;
    }
    charge = sign * magnitude;
  }
  if (i != content.length) return (null, 'bad bracket atom');
  return (
    Atom(
      symbol: symbol,
      aromatic: aromatic,
      mass: mass,
      charge: charge,
      hydrogens: hydrogens,
      bracket: true,
    ),
    '',
  );
}

int symbolType(String c) => switch (c) {
  '-' || '/' || '\\' => 1,
  '=' => 2,
  '#' => 3,
  ':' => 4,
  '~' => 5,
  _ => 0,
};
bool bondSymbol(String c, bool pattern) =>
    pattern ? '-=#:~'.contains(c) : '-/\\=#:'.contains(c);

class OpenRing {
  final int atom, column;
  final String symbol;
  OpenRing(this.atom, this.column, this.symbol);
}

(Molecule?, ParseError?) parseSMILES(
  String source,
  Map<String, Element> elements,
  bool pattern,
) {
  final m = Molecule(),
      stack = <(int, int)>[],
      open = <int, OpenRing>{},
      existing = <(int, int)>{};
  var current = -1, pending = '', pendingColumn = 0;
  (Molecule?, ParseError?) fail(String reason, int column) =>
      (null, ParseError(reason, column));
  void addBond(int a, int b, String symbol) {
    if (a > b) {
      final t = a;
      a = b;
      b = t;
    }
    var mask = 0;
    if (pattern) {
      final kind = symbolType(symbol);
      mask = kind == 0
          ? (1 << 1) | (1 << 4)
          : kind == 5
          ? (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)
          : 1 << kind;
    }
    m.bonds.add(Bond(a, b, symbol: symbol, match: mask));
    existing.add((a, b));
  }

  for (var i = 0; i < source.length;) {
    final c = source[i], column = i + 1;
    if (bondSymbol(c, pattern)) {
      if (current < 0 || pending.isNotEmpty)
        return fail('misplaced bond', column);
      pending = c;
      pendingColumn = column;
      i++;
    } else if (c == '(') {
      if (current < 0 || pending.isNotEmpty || (i > 0 && source[i - 1] == '('))
        return fail('misplaced branch', column);
      stack.add((current, column));
      i++;
    } else if (c == ')') {
      if (stack.isEmpty) return fail('unmatched parenthesis', column);
      if (pending.isNotEmpty) return fail('dangling bond', pendingColumn);
      if (i > 0 && source[i - 1] == '(') return fail('empty branch', column);
      current = stack.removeLast().$1;
      i++;
    } else if (digit(c) || c == '%') {
      if (current < 0) return fail('misplaced ring closure', column);
      int number;
      if (c == '%') {
        if (i + 2 >= source.length ||
            !digit(source[i + 1]) ||
            !digit(source[i + 2]))
          return fail('bad ring number', column);
        number = int.parse(source.substring(i + 1, i + 3));
        i += 3;
      } else {
        number = int.parse(c);
        i++;
      }
      var symbol = pending;
      pending = '';
      final old = open[number];
      if (old != null) {
        if (old.atom == current) return fail('self bond', column);
        if (old.symbol.isNotEmpty && symbol.isNotEmpty) {
          final same = pattern
              ? old.symbol == symbol
              : symbolType(old.symbol) == symbolType(symbol);
          if (!same) return fail('ring bond mismatch', column);
        }
        final a = min(old.atom, current), b = max(old.atom, current);
        if (existing.contains((a, b))) return fail('duplicate bond', column);
        if (symbol.isEmpty) symbol = old.symbol;
        addBond(old.atom, current, symbol);
        open.remove(number);
      } else {
        open[number] = OpenRing(current, column, symbol);
      }
    } else {
      Atom? atom;
      int next;
      String reason;
      if (pattern) {
        final parsed = patternAtom(source, i);
        atom = parsed.$1;
        next = parsed.$2;
        reason = parsed.$3;
      } else if (c == '[') {
        final end = source.indexOf(']', i + 1);
        if (end < 0) return fail('unclosed bracket', column);
        final parsed = bracket(source.substring(i + 1, end), elements);
        atom = parsed.$1;
        reason = parsed.$2;
        next = end + 1;
      } else {
        final parsed = organic(source, i);
        atom = parsed.$1;
        next = parsed.$2;
        reason = parsed.$3 ? '' : 'unexpected character';
      }
      if (reason.isNotEmpty) return fail(reason, column);
      final a = atom!;
      a.column = column;
      m.atoms.add(a);
      final index = m.atoms.length - 1;
      if (current >= 0) addBond(current, index, pending);
      current = index;
      pending = '';
      i = next;
    }
  }
  if (pending.isNotEmpty) return fail('dangling bond', pendingColumn);
  if (stack.isNotEmpty) return fail('unmatched parenthesis', stack.first.$2);
  if (open.isNotEmpty) {
    var column = source.length + 1;
    for (final r in open.values) {
      column = min(column, r.column);
    }
    return fail('unclosed ring', column);
  }
  m.build();
  return (m, null);
}
