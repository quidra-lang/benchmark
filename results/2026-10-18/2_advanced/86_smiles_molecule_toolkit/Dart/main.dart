import 'dart:io';
import 'dart:math';
part 'smiles_parser.dart';
part 'molecule.dart';
part 'rings_aromatic.dart';
part 'canonical.dart';
part 'search.dart';

final nameForm = RegExp(r'^[A-Za-z0-9_-]{1,32}$');
ParseError? analyze(Molecule m, Map<String, Element> elements) {
  detectRings(m);
  for (final b in m.bonds) {
    b.type = symbolType(b.symbol);
    if (b.type == 0)
      b.type = b.ring && m.atoms[b.a].aromatic && m.atoms[b.b].aromatic ? 4 : 1;
  }
  final failure = kekulize(m, elements);
  if (failure != null) return failure;
  for (var i = 0; i < m.atoms.length; i++) {
    final a = m.atoms[i];
    if (a.bracket) {
      if (m.multiplicity(i) + a.hydrogens >
          elements[a.symbol]!.valences.last + a.charge.abs())
        return ParseError('bad valence', a.column);
    } else {
      final (hydrogens, ok) = organicHydrogens(m, i, elements);
      if (!ok) return ParseError('bad valence', a.column);
      a.hydrogens = hydrogens;
    }
  }
  return null;
}

void properties(Molecule m, Map<String, Element> elements) {
  final counts = <String, int>{},
      heavyDegree = List.filled(m.atoms.length, 0),
      triple = List.filled(m.atoms.length, false);
  var hydrogens = 0;
  for (var i = 0; i < m.atoms.length; i++) {
    final a = m.atoms[i];
    counts[a.symbol] = (counts[a.symbol] ?? 0) + 1;
    hydrogens += a.hydrogens;
    m.charge += a.charge;
    m.weight += a.mass != 0 ? a.mass * 1000 : elements[a.symbol]!.weight;
    if (a.symbol != 'H') m.heavy++;
    var attached = a.hydrogens;
    for (final e in m.adjacent[i]) {
      final b = m.bonds[e], other = m.atoms[b.other(i)];
      if (other.symbol == 'H') {
        attached++;
      } else {
        heavyDegree[i]++;
      }
      if (b.multiplicity == 3) triple[i] = true;
    }
    if (a.symbol == 'N' || a.symbol == 'O') {
      m.acceptors++;
      if (attached > 0) m.donors++;
    }
  }
  counts['H'] = (counts['H'] ?? 0) + hydrogens;
  m.weight += hydrogens * elements['H']!.weight;
  var symbols = [
    for (final e in counts.entries)
      if (e.value > 0) e.key,
  ]..sort();
  if ((counts['C'] ?? 0) > 0)
    symbols = [
      'C',
      if ((counts['H'] ?? 0) > 0) 'H',
      for (final symbol in symbols)
        if (symbol != 'C' && symbol != 'H') symbol,
    ];
  for (final symbol in symbols) {
    m.formula += symbol;
    if (counts[symbol]! > 1) m.formula += '${counts[symbol]}';
  }
  for (final b in m.bonds) {
    if (b.multiplicity == 1 &&
        !b.ring &&
        heavyDegree[b.a] >= 2 &&
        heavyDegree[b.b] >= 2 &&
        !triple[b.a] &&
        !triple[b.b])
      m.rotatable++;
  }
  final violations =
      (m.weight > 500000 ? 1 : 0) +
      (m.donors > 5 ? 1 : 0) +
      (m.acceptors > 10 ? 1 : 0);
  m.lipinski = violations >= 2 ? 'fail' : 'pass';
}

String scaffold(Molecule m, Map<String, Element> elements) {
  if (m.rings.isEmpty) return '';
  final remaining = List.filled(m.atoms.length, true);
  while (true) {
    var remove = -1;
    for (var a = 0; a < m.atoms.length; a++) {
      if (!remaining[a] || m.ringAtoms[a]) continue;
      final degree = m.adjacent[a]
          .where((e) => remaining[m.bonds[e].other(a)])
          .length;
      if (degree == 1) {
        remove = a;
        break;
      }
    }
    if (remove < 0) break;
    remaining[remove] = false;
  }
  final keep = List<bool>.of(remaining);
  for (final b in m.bonds) {
    if (b.multiplicity == 2) {
      if (remaining[b.a]) keep[b.b] = true;
      if (remaining[b.b]) keep[b.a] = true;
    }
  }
  final s = Molecule(), renumber = List.filled(m.atoms.length, -1);
  for (var i = 0; i < m.atoms.length; i++) {
    if (!keep[i]) continue;
    final a = m.atoms[i];
    var hydrogens = a.hydrogens;
    for (final e in m.adjacent[i]) {
      final b = m.bonds[e];
      if (!keep[b.other(i)]) hydrogens += b.multiplicity;
    }
    renumber[i] = s.atoms.length;
    s.atoms.add(
      Atom(
        symbol: a.symbol,
        aromatic: a.aromatic,
        mass: a.mass,
        charge: a.charge,
        hydrogens: hydrogens,
        column: a.column,
        bracket: a.bracket,
      ),
    );
  }
  for (final b in m.bonds) {
    if (keep[b.a] && keep[b.b])
      s.bonds.add(
        Bond(
          renumber[b.a],
          renumber[b.b],
          symbol: b.symbol,
          type: b.type,
          multiplicity: b.multiplicity,
          ring: b.ring,
        ),
      );
  }
  s.build();
  canonicalRanks(s, elements);
  return canonicalSMILES(s, elements);
}

class RingSystem {
  final List<int> rings;
  final String kind;
  final int atoms;
  RingSystem(this.rings, this.kind, this.atoms);
}

String ringRelation(Molecule m, List<int> first, List<int> second) {
  final common = first.where(second.contains).toList();
  if (common.length == 1) return 'spiro';
  if (common.length == 2 && m.bond(common[0], common[1]) != null)
    return 'fused';
  if (common.length >= 2) return 'bridged';
  return '';
}

List<RingSystem> ringSystems(Molecule m) {
  final adjacent = List.generate(m.rings.length, (_) => <int>[]);
  for (var i = 0; i < m.rings.length; i++) {
    for (var j = i + 1; j < m.rings.length; j++) {
      if (ringRelation(m, m.rings[i], m.rings[j]).isNotEmpty) {
        adjacent[i].add(j);
        adjacent[j].add(i);
      }
    }
  }
  final seen = List.filled(m.rings.length, false), out = <RingSystem>[];
  for (var first = 0; first < m.rings.length; first++) {
    if (seen[first]) continue;
    final queue = [first];
    seen[first] = true;
    for (var h = 0; h < queue.length; h++) {
      for (final r in adjacent[queue[h]]) {
        if (!seen[r]) {
          seen[r] = true;
          queue.add(r);
        }
      }
    }
    queue.sort();
    final atoms = <int>{};
    var kind = queue.length > 1 ? 'spiro' : 'isolated';
    for (var i = 0; i < queue.length; i++) {
      final r = queue[i];
      atoms.addAll(m.rings[r]);
      for (final s in queue.skip(i + 1)) {
        final relation = ringRelation(m, m.rings[r], m.rings[s]);
        if (relation == 'bridged') {
          kind = 'bridged';
        } else if (relation == 'fused' && kind != 'bridged') {
          kind = 'fused';
        }
      }
    }
    out.add(RingSystem(queue, kind, atoms.length));
  }
  return out;
}

bool ringAromatic(Molecule m, List<int> ring) =>
    ring.every((a) => m.atoms[a].aromatic);
String ints(List<int> a, String separator, [int offset = 0]) =>
    a.map((n) => n + offset).join(separator);
String memberNames(List<Molecule> molecules, List<int> indices) =>
    indices.map((i) => molecules[i].name).join(',');
List<List<String>> canonicalParagraphs(List<Molecule> molecules) {
  final canonGroups = <String, List<int>>{},
      formulaGroups = <String, List<int>>{},
      scaffoldGroups = <String, List<int>>{};
  var acyclic = 0;
  for (var i = 0; i < molecules.length; i++) {
    final m = molecules[i];
    canonGroups.putIfAbsent(m.canonical, () => []).add(i);
    formulaGroups.putIfAbsent(m.formula, () => []).add(i);
    if (m.scaffold.isEmpty) {
      acyclic++;
    } else {
      scaffoldGroups.putIfAbsent(m.scaffold, () => []).add(i);
    }
  }
  final canonical = [
    'CANONICAL molecules=${molecules.length} unique=${canonGroups.length}',
  ];
  for (final m in molecules) {
    final charge = m.charge > 0 ? '+${m.charge}' : '${m.charge}';
    canonical.add(
      '${m.name} ${m.canonical} classes=${m.classes} charge=$charge',
    );
  }
  final duplicates = <String>[];
  var duplicateCount = 0, duplicateMolecules = 0;
  for (final e in canonGroups.entries) {
    if (e.value.length < 2) continue;
    duplicateCount++;
    duplicateMolecules += e.value.length;
    duplicates.add(
      'group $duplicateCount ${e.key} members=${memberNames(molecules, e.value)}',
    );
  }
  duplicates.insert(
    0,
    'DUPLICATES groups=$duplicateCount molecules=$duplicateMolecules',
  );
  final isomers = <String>[];
  var isomerCount = 0;
  for (final e in formulaGroups.entries) {
    final forms = {for (final i in e.value) molecules[i].canonical};
    if (forms.length < 2) continue;
    isomerCount++;
    isomers.add(
      'isomer $isomerCount ${e.key} forms=${forms.length} members=${memberNames(molecules, e.value)}',
    );
  }
  isomers.insert(0, 'ISOMERS groups=$isomerCount');
  final scaffolds = [
        'SCAFFOLDS distinct=${scaffoldGroups.length} acyclic=$acyclic',
      ],
      keys = scaffoldGroups.keys.toList()
        ..sort((a, b) {
          final c = scaffoldGroups[b]!.length.compareTo(
            scaffoldGroups[a]!.length,
          );
          return c != 0 ? c : a.compareTo(b);
        });
  for (var i = 0; i < keys.length; i++) {
    final key = keys[i], indices = scaffoldGroups[keys[i]]!;
    scaffolds.add(
      'scaffold ${i + 1} $key count=${indices.length} members=${memberNames(molecules, indices)}',
    );
  }
  return [canonical, duplicates, isomers, scaffolds];
}

List<List<String>> ringParagraphs(List<Molecule> molecules) {
  final out = <List<String>>[], sizes = <int, int>{}, kinds = <String, int>{};
  var cyclic = 0, total = 0, aromatic = 0;
  for (final m in molecules) {
    if (m.rings.isEmpty) continue;
    cyclic++;
    total += m.rings.length;
    final systems = ringSystems(m),
        ringAtoms = m.ringAtoms.where((v) => v).length,
        ringBonds = m.bonds.where((b) => b.ring).length;
    var aromaticCount = 0;
    for (final r in m.rings) {
      sizes[r.length] = (sizes[r.length] ?? 0) + 1;
      if (ringAromatic(m, r)) aromaticCount++;
    }
    aromatic += aromaticCount;
    final paragraph = [
      'MOLECULE ${m.name} atoms=${m.atoms.length} bonds=${m.bonds.length} rings=${m.rings.length} aromatic=$aromaticCount systems=${systems.length} ring_atoms=$ringAtoms ring_bonds=$ringBonds',
    ];
    for (var i = 0; i < m.rings.length; i++) {
      final r = m.rings[i],
          flag = ringAromatic(m, m.rings[i]) ? 'yes' : 'no',
          hetero = m.rings[i].where((a) => m.atoms[a].symbol != 'C').length;
      paragraph.add(
        'ring ${i + 1} size=${r.length} aromatic=$flag hetero=$hetero atoms=${ints(r, '-', 1)}',
      );
    }
    for (var i = 0; i < systems.length; i++) {
      final s = systems[i];
      kinds[s.kind] = (kinds[s.kind] ?? 0) + 1;
      paragraph.add(
        'system ${i + 1} kind=${s.kind} rings=${ints(s.rings, ',', 1)} atoms=${s.atoms}',
      );
    }
    final doubleBonds = [
      for (final b in m.bonds)
        if (b.type == 4 && b.multiplicity == 2) '${b.a + 1}=${b.b + 1}',
    ];
    paragraph.add(
      'kekule ${doubleBonds.isEmpty ? '-' : doubleBonds.join(' ')}',
    );
    out.add(paragraph);
  }
  final sizeValues = sizes.keys.toList()..sort();
  var line = 'sizes';
  for (final size in sizeValues) {
    line += ' $size=${sizes[size]}';
  }
  if (sizeValues.isEmpty) line += ' -';
  out.add([
    'SUMMARY molecules=${molecules.length} cyclic=$cyclic rings=$total aromatic=$aromatic',
    line,
    'systems isolated=${kinds['isolated'] ?? 0} fused=${kinds['fused'] ?? 0} spiro=${kinds['spiro'] ?? 0} bridged=${kinds['bridged'] ?? 0}',
  ]);
  return out;
}

class Query {
  final String kind, id;
  final List<String> arguments;
  Molecule? pattern;
  Fraction threshold = fraction(0, 1);
  int count = 0;
  Query(this.kind, this.id, this.arguments);
}

bool number(String s, int low, int high) {
  if (s.isEmpty ||
      s.length > 2 ||
      (s.length > 1 && s[0] == '0') ||
      !s.split('').every(digit))
    return false;
  final n = int.parse(s);
  return n >= low && n <= high;
}

Fraction? threshold(String s) {
  final a = s.split('/');
  if (a.length != 2 || !number(a[0], 0, 99) || !number(a[1], 1, 99))
    return null;
  final n = int.parse(a[0]), d = int.parse(a[1]);
  return n <= d ? fraction(n, d) : null;
}

(Query?, String) checkQuery(
  List<String> tokens,
  Set<String> seen,
  Map<String, int> byName,
  Map<String, Element> elements,
) {
  final kind = tokens[0];
  if (![
    'MATCH',
    'CONTAINS',
    'MATRIX',
    'NEAREST',
    'WITHIN',
    'COMPARE',
    'CLUSTER',
  ].contains(kind))
    return (null, 'unknown query');
  if (tokens.length == 1 || !nameForm.hasMatch(tokens[1]))
    return (null, 'bad id');
  final id = tokens[1];
  if (seen.contains(id)) return (null, 'duplicate id');
  seen.add(id);
  final args = tokens.sublist(2);
  final validLength = kind == 'MATCH' || kind == 'CLUSTER'
      ? args.length == 1
      : kind == 'MATRIX'
      ? args.length >= 2 && args.length <= 12
      : args.length == 2;
  if (!validLength) return (null, 'bad arguments');
  final q = Query(kind, id, args);
  switch (kind) {
    case 'MATCH':
      {
        final parsed = parseSMILES(args[0], elements, true),
            failure = parsed.$2;
        if (failure != null)
          return (
            null,
            'bad pattern ${failure.reason} at column ${failure.column}',
          );
        q.pattern = parsed.$1;
        break;
      }
    case 'CLUSTER':
      {
        final value = threshold(args[0]);
        if (value == null) return (null, 'bad threshold');
        q.threshold = value;
        break;
      }
    case 'CONTAINS':
    case 'MATRIX':
    case 'COMPARE':
      {
        for (final name in args) {
          if (!byName.containsKey(name))
            return (null, 'unknown molecule $name');
        }
        if (args.toSet().length != args.length)
          return (null, 'repeated molecule');
        break;
      }
    case 'NEAREST':
    case 'WITHIN':
      {
        if (!byName.containsKey(args[0]))
          return (null, 'unknown molecule ${args[0]}');
        if (kind == 'NEAREST') {
          if (!number(args[1], 1, 99)) return (null, 'bad count');
          q.count = int.parse(args[1]);
        } else {
          final value = threshold(args[1]);
          if (value == null) return (null, 'bad threshold');
          q.threshold = value;
        }
        break;
      }
  }
  return (q, '');
}

List<List<String>> substructureParagraphs(
  List<Query> queries,
  List<Molecule> molecules,
  Map<String, int> byName,
) {
  final paragraphs = <List<String>>[];
  var patterns = 0, hits = 0, contains = 0, found = 0;
  for (final q in queries) {
    switch (q.kind) {
      case 'MATCH':
        {
          patterns++;
          final hitLines = <String>[];
          var embeddingsTotal = 0, topCount = 0, top = '';
          for (final m in molecules) {
            final result = embeddings(q.pattern!, m);
            if (result.count == 0) continue;
            hits++;
            embeddingsTotal += result.count;
            hitLines.add(
              '${m.name} count=${result.count} unique=${result.unique} map=${ints(result.first!, ',')}',
            );
            if (result.count > topCount) {
              top = m.name;
              topCount = result.count;
            }
          }
          final paragraph = [
            'MATCH ${q.id} ${q.arguments[0]} atoms=${q.pattern!.atoms.length} bonds=${q.pattern!.bonds.length} hits=${hitLines.length} embeddings=$embeddingsTotal',
            ...hitLines,
          ];
          if (top.isNotEmpty) paragraph.add('top $top count=$topCount');
          paragraphs.add(paragraph);
          break;
        }
      case 'CONTAINS':
        {
          contains++;
          final x = molecules[byName[q.arguments[0]]!],
              y = molecules[byName[q.arguments[1]]!],
              result = embeddings(moleculePattern(x), y);
          var line = 'CONTAINS ${q.id} ${x.name} ${y.name} result=';
          if (result.count > 0) {
            found++;
            line +=
                'yes count=${result.count} unique=${result.unique} map=${ints(result.first!, ',')}';
          } else {
            line += 'no';
          }
          paragraphs.add([line]);
          break;
        }
    }
  }
  paragraphs.add([
    'SUMMARY patterns=$patterns hits=$hits contains=$contains found=$found',
  ]);
  return paragraphs;
}

List<List<String>> similarityParagraphs(
  List<Query> queries,
  List<Molecule> molecules,
  Map<String, int> byName,
) {
  final n = molecules.length,
      matrix = List.generate(
        molecules.length,
        (_) => List<Similarity?>.filled(molecules.length, null),
      );
  for (var i = 0; i < n; i++) {
    for (var j = i; j < n; j++) {
      final record = similarity(molecules[i], molecules[j]);
      matrix[i][j] = record;
      matrix[j][i] = record;
    }
  }
  Similarity get(int a, int b) => matrix[a][b]!;
  final fingerprints = [
        'FINGERPRINTS molecules=$n size=1024 depth=5',
        for (final m in molecules)
          '${m.name} bits=${m.bitCount} paths=${m.paths}',
      ],
      out = <List<String>>[fingerprints];
  for (final q in queries) {
    final args = q.arguments, paragraph = <String>[];
    switch (q.kind) {
      case 'MATRIX':
        {
          final indices = [for (final name in args) byName[name]!];
          paragraph.add('MATRIX ${q.id} size=${args.length}');
          var bestI = 0, bestJ = 1;
          for (var i = 0; i < indices.length; i++) {
            final values = <String>[];
            for (var j = 0; j < indices.length; j++) {
              values.add('${get(indices[i], indices[j]).value}');
              if (i < j &&
                  get(indices[i], indices[j]).value.compare(
                        get(indices[bestI], indices[bestJ]).value,
                      ) >
                      0) {
                bestI = i;
                bestJ = j;
              }
            }
            paragraph.add('row ${args[i]} ${values.join(' ')}');
          }
          paragraph.add(
            'best ${args[bestI]} ${args[bestJ]} ${get(indices[bestI], indices[bestJ]).value}',
          );
          break;
        }
      case 'NEAREST':
      case 'WITHIN':
        {
          final base = byName[args[0]]!;
          var order =
              [
                for (var i = 0; i < n; i++)
                  if (i != base) i,
              ]..sort((a, b) {
                final c = get(base, a).value.compare(get(base, b).value);
                return c != 0 ? -c : a.compareTo(b);
              });
          if (q.kind == 'NEAREST') {
            order = order.take(q.count).toList();
            paragraph.add('NEAREST ${q.id} ${args[0]} count=${order.length}');
          } else {
            order = order
                .where((i) => get(base, i).value.compare(q.threshold) >= 0)
                .toList();
            paragraph.add(
              'WITHIN ${q.id} ${args[0]} threshold=${q.threshold} count=${order.length}',
            );
          }
          for (var k = 0; k < order.length; k++) {
            final i = order[k], value = get(base, order[k]);
            paragraph.add(
              '${k + 1} ${molecules[i].name} ${value.value} common=${value.common}',
            );
          }
          break;
        }
      case 'COMPARE':
        {
          final a = byName[args[0]]!,
              b = byName[args[1]]!,
              record = get(a, b),
              identical = molecules[a].canonical == molecules[b].canonical
                  ? 'yes'
                  : 'no';
          paragraph.add(
            'COMPARE ${q.id} ${args[0]} ${args[1]} bits=${molecules[a].bitCount},${molecules[b].bitCount} common=${record.common} union=${record.union} tanimoto=${record.value} identical=$identical',
          );
          break;
        }
      case 'CLUSTER':
        {
          final neighbors = List.generate(
                n,
                (i) => [
                  for (var j = 0; j < n; j++)
                    if (i != j && get(i, j).value.compare(q.threshold) >= 0) j,
                ],
              ),
              order = List.generate(n, (i) => i)
                ..sort((a, b) {
                  final c = neighbors[b].length.compareTo(neighbors[a].length);
                  return c != 0 ? c : a.compareTo(b);
                });
          final assigned = List.filled(n, false), clusters = <List<int>>[];
          var singletons = 0;
          for (final center in order) {
            if (assigned[center]) continue;
            final members = [center];
            assigned[center] = true;
            for (final neighbor in neighbors[center]) {
              if (!assigned[neighbor]) {
                members.add(neighbor);
                assigned[neighbor] = true;
              }
            }
            if (members.length == 1) singletons++;
            clusters.add(members);
          }
          paragraph.add(
            'CLUSTER ${q.id} threshold=${q.threshold} clusters=${clusters.length} singletons=$singletons',
          );
          var serial = 0;
          for (final members in clusters) {
            if (members.length == 1) continue;
            serial++;
            paragraph.add(
              'cluster $serial centroid=${molecules[members.first].name} size=${members.length} members=${memberNames(molecules, members)}',
            );
          }
          break;
        }
    }
    if (paragraph.isNotEmpty) out.add(paragraph);
  }
  return out;
}

void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void writeParagraphs(String name, List<List<String>> paragraphs) {
  final out = <String>[];
  for (final p in paragraphs) {
    if (p.isEmpty) continue;
    if (out.isNotEmpty) out.add('');
    out.addAll(p);
  }
  writeLines(name, out);
}

void main() {
  final elements = readElements(),
      molecules = <Molecule>[],
      byName = <String, int>{},
      seenNames = <String>{},
      moleculeErrors = <String>[],
      queryErrors = <String>[],
      causes = <String, int>{};
  void cause(String reason) => causes[reason] = (causes[reason] ?? 0) + 1;
  var moleculeLines = 0;
  final moleculeSource = lines('input/molecules.smi');
  for (var index = 0; index < moleculeSource.length; index++) {
    final line = moleculeSource[index];
    if (ignored(line)) continue;
    moleculeLines++;
    final tokens = line.split(' ');
    if (tokens.length != 2 ||
        tokens[0].isEmpty ||
        !nameForm.hasMatch(tokens[1])) {
      moleculeErrors.add('line ${index + 1}: bad line');
      cause('bad line');
      continue;
    }
    final name = tokens[1];
    if (!seenNames.add(name)) {
      moleculeErrors.add('line ${index + 1} $name: duplicate name');
      cause('duplicate name');
      continue;
    }
    final parsed = parseSMILES(tokens[0], elements, false);
    var failure = parsed.$2;
    if (failure == null) failure = analyze(parsed.$1!, elements);
    if (failure != null) {
      moleculeErrors.add(
        'line ${index + 1} $name: ${failure.reason} at column ${failure.column}',
      );
      cause(failure.reason);
      continue;
    }
    final m = parsed.$1!;
    m.name = name;
    properties(m, elements);
    canonicalRanks(m, elements);
    m.canonical = canonicalSMILES(m, elements);
    m.scaffold = scaffold(m, elements);
    fingerprint(m, elements);
    byName[name] = molecules.length;
    molecules.add(m);
  }
  final queries = <Query>[],
      seenIDs = <String>{},
      querySource = lines('input/queries.txt');
  var queryLines = 0;
  for (var index = 0; index < querySource.length; index++) {
    final line = querySource[index];
    if (ignored(line)) continue;
    queryLines++;
    final tokens = line.split(' ');
    final (q, reason) = checkQuery(tokens, seenIDs, byName, elements);
    if (reason.isNotEmpty) {
      var text = 'line ${index + 1}';
      if (reason == 'unknown query') {
        text += ': unknown query';
      } else if (reason == 'bad id') {
        text += ' ${tokens[0]}: bad id';
      } else {
        text += ' ${tokens[0]} ${tokens[1]}: $reason';
      }
      queryErrors.add(text);
      cause(
        reason.startsWith('bad pattern ')
            ? 'bad pattern'
            : reason.startsWith('unknown molecule ')
            ? 'unknown molecule'
            : reason,
      );
      continue;
    }
    queries.add(q!);
  }
  final propertiesLines = [
    'name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski',
  ];
  for (final m in molecules) {
    final weight =
        '${m.weight ~/ 1000}.${(m.weight % 1000).toString().padLeft(3, '0')}';
    propertiesLines.add(
      '${m.name},${m.formula},$weight,${m.heavy},${m.rings.length},${m.rotatable},${m.donors},${m.acceptors},${m.lipinski}',
    );
  }
  final molErrors = [
        'MOLECULES lines=$moleculeLines valid=${molecules.length} errors=${moleculeErrors.length}',
        ...moleculeErrors,
      ],
      queErrors = [
        'QUERIES lines=$queryLines valid=${queries.length} errors=${queryErrors.length}',
        ...queryErrors,
      ],
      causeNames = causes.keys.toList()
        ..sort((a, b) {
          final c = causes[b]!.compareTo(causes[a]!);
          return c != 0 ? c : a.compareTo(b);
        });
  final causeLines = [
    'CAUSES kinds=${causes.length}',
    for (final name in causeNames) '$name=${causes[name]}',
  ];
  Directory('output').createSync(recursive: true);
  writeLines('properties.csv', propertiesLines);
  writeParagraphs('canonical.txt', canonicalParagraphs(molecules));
  writeParagraphs('rings.txt', ringParagraphs(molecules));
  writeParagraphs(
    'substructure.txt',
    substructureParagraphs(queries, molecules, byName),
  );
  writeParagraphs(
    'similarity.txt',
    similarityParagraphs(queries, molecules, byName),
  );
  writeParagraphs('errors.txt', [molErrors, queErrors, causeLines]);
}
