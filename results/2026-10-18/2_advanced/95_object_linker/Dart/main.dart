import 'dart:io';
import 'dart:math';
part 'object_parser.dart';
part 'archive.dart';
part 'resolver.dart';
part 'layout.dart';
part 'relocator.dart';

class ScriptDefinition {
  final String name, expression;
  ScriptDefinition(this.name, this.expression);
}

class LinkInput {
  final String kind;
  final List<String> names;
  LinkInput(this.kind, this.names);
}

class Script {
  String entry = '', checksumSegment = '', checksumSymbol = '';
  bool gc = false;
  final List<Segment> segments = [];
  final List<OutputSection> outputs = [];
  final Map<String, Segment> segmentNames = {};
  final Map<String, OutputSection> outputNames = {};
  final List<(String, String)> loads = [];
  final Set<String> keep = {}, sort = {}, wrap = {}, scriptNames = {};
  final List<ScriptDefinition> definitions = [];
  final List<LinkInput> inputs = [];
}

Script readScript() {
  final script = Script();
  for (final line in readLines('input/link.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'entry':
        script.entry = a[1];
      case 'gc':
        script.gc = a[1] == 'on';
      case 'segment':
        final segment = Segment(a[1], number(a[2]), number(a[3]), number(a[4]));
        script.segments.add(segment);
        script.segmentNames[segment.name] = segment;
        for (final name in a.skip(5)) {
          final output = OutputSection(name, segment);
          segment.sections.add(output);
          script.outputs.add(output);
          script.outputNames[name] = output;
        }
      case 'load':
        script.loads.add((a[1], a[2]));
      case 'keep':
        script.keep.add(a[1]);
      case 'sort':
        script.sort.add(a[1]);
      case 'wrap':
        script.wrap.add(a[1]);
      case 'define':
        script.definitions.add(
          ScriptDefinition(a[1], line.substring(line.indexOf(' = ') + 3)),
        );
        script.scriptNames.add(a[1]);
      case 'checksum':
        script.checksumSegment = a[1];
        script.checksumSymbol = a[2];
      default:
        script.inputs.add(LinkInput(a[0], a.skip(1).toList()));
    }
  }
  return script;
}

class ComdatRecord {
  final ObjectFile keeper;
  final List<String> discarders = [];
  ComdatRecord(this.keeper);
}

class MapSymbol {
  final int address;
  final String name, kind, definer;
  MapSymbol(this.address, this.name, this.kind, this.definer);
}

List<String> sortedKeys<V>(Map<String, V> map) => map.keys.toList()..sort();
void stableSort<T>(List<T> values, int Function(T, T) compare) {
  final indexed = values.indexed.toList();
  indexed.sort((a, b) {
    final order = compare(a.$2, b.$2);
    return order == 0 ? a.$1.compareTo(b.$1) : order;
  });
  for (var i = 0; i < values.length; i++) values[i] = indexed[i].$2;
}

String hex(int value, [int digits = 8]) =>
    value.toRadixString(16).padLeft(digits, '0');
String relocationLocation(Relocation r) =>
    '${r.section.object.name} ${r.section.name}+${r.offset}';

class Linker {
  final Script script;
  final List<ObjectFile> objects = [];
  final Map<String, List<Symbol>> entries = {};
  final Map<String, Archive> archives = {};
  final List<Extraction> extractions = [];
  final Map<String, ComdatRecord> comdat = {};
  final List<String> comdatOrder = [];
  final Map<String, Resolution> names = {};
  List<String> orderedNames = [];
  final Map<String, int> orphans = {};
  final Set<VeneerPair> veneers = {};
  final Map<VeneerPair, Component> veneerComponents = {};
  final Map<String, int> scriptValues = {};
  final List<String> relocationLines = [], relocationDiagnostics = [];
  final Map<String, Map<String, int>> relocationCounts = {};
  Linker(this.script);
  void load(ObjectFile object) {
    object.rank = objects.length;
    for (final group in object.groups) {
      final previous = comdat[group.signature];
      if (previous != null) {
        for (final section in group.sections) section.reason = 'comdat';
        previous.discarders.add(object.name);
      } else {
        comdat[group.signature] = ComdatRecord(object);
        comdatOrder.add(group.signature);
      }
    }
    for (final symbol in object.symbols) {
      if (symbol.binding == 'local') continue;
      if (symbol.location == 'section' && symbol.section!.reason == 'comdat') {
        symbol.location = 'undef';
        symbol.section = null;
      }
      if (symbol.location == 'undef') {
        if (script.wrap.contains(symbol.name)) {
          symbol.name = '__wrap_${symbol.name}';
        } else if (symbol.name.startsWith('__real_') &&
            script.wrap.contains(symbol.name.substring(7))) {
          symbol.name = symbol.name.substring(7);
        }
      }
      entries.putIfAbsent(symbol.name, () => []).add(symbol);
    }
    objects.add(object);
  }

  bool defined(String name) =>
      script.scriptNames.contains(name) ||
      (entries[name] ?? []).any((s) => s.location != 'undef');
  bool undefined(String name) =>
      !defined(name) &&
      (name == script.entry ||
          (entries[name] ?? []).any(
            (s) => s.binding == 'global' && s.location == 'undef',
          ));
  String referrer(String name) {
    for (final symbol in entries[name] ?? <Symbol>[]) {
      if (symbol.binding == 'global' && symbol.location == 'undef')
        return symbol.object.name;
    }
    return '*entry*';
  }

  int scan(String name) => scanArchive(
    archives.putIfAbsent(name, () => readArchive(name)),
    undefined,
    referrer,
    load,
    extractions.add,
  );
  void loadInputs() {
    for (final input in script.inputs) {
      switch (input.kind) {
        case 'object':
          final name = input.names.first;
          load(parseObject(readLines('input/$name'), name));
        case 'library':
          scan(input.names.first);
        case 'group':
          while (true) {
            var count = 0;
            for (final name in input.names) count += scan(name);
            if (count == 0) break;
          }
      }
    }
  }

  void resolve() {
    orderedNames = {...entries.keys, ...script.scriptNames}.toList()..sort();
    for (final name in orderedNames)
      names[name] = resolveName(
        name,
        entries[name] ?? [],
        script.scriptNames.contains(name),
      );
  }

  void collect() {
    for (final object in objects) {
      for (final section in object.sections) {
        if (section.reason == 'comdat') continue;
        section.output = outputFor(section, script.outputs);
        if (section.output == null) {
          section.reason = 'orphan';
          orphans.update(section.name, (n) => n + 1, ifAbsent: () => 1);
        } else if (!script.gc) {
          section.live = true;
        }
      }
    }
    if (!script.gc) {
      for (final result in names.values) {
        if (result.kind == 'common') result.live = true;
      }
      return;
    }
    final queue = <Section>[];
    void mark(Section? section) {
      if (section != null &&
          section.reason.isEmpty &&
          section.output != null &&
          !section.live) {
        section.live = true;
        queue.add(section);
      }
    }

    for (final object in objects) {
      for (final section in object.sections) {
        if (section.output != null &&
            script.keep.contains(section.output!.name))
          mark(section);
      }
    }
    final entry = names[script.entry];
    if (entry != null) {
      if (entry.kind == 'global' || entry.kind == 'weak')
        mark(entry.definition!.section);
      if (entry.kind == 'common') entry.live = true;
    }
    for (var head = 0; head < queue.length; head++) {
      for (final relocation in queue[head].relocations) {
        final symbol = relocation.symbol;
        if (symbol.binding == 'local') {
          mark(symbol.section);
        } else {
          final result = names[symbol.name]!;
          if (result.kind == 'global' || result.kind == 'weak')
            mark(result.definition!.section);
          if (result.kind == 'common') result.live = true;
        }
      }
    }
    for (final object in objects) {
      for (final section in object.sections) {
        if (section.output != null && section.reason.isEmpty && !section.live)
          section.reason = 'gc';
      }
    }
  }

  int priority(Section section, OutputSection output) =>
      section.name == output.name
      ? 65536
      : number(section.name.substring(output.name.length + 1));
  List<Component> components(OutputSection output) {
    final sections = [
      for (final object in objects)
        for (final section in object.sections)
          if (section.live && identical(section.output, output)) section,
    ];
    if (script.sort.contains(output.name))
      stableSort(
        sections,
        (a, b) => priority(a, output).compareTo(priority(b, output)),
      );
    final stringSections = sections.where((s) => s.stringSection).toList();
    Component? merged;
    if (stringSections.isNotEmpty) {
      final block = Component('merged');
      merged = block;
      block.stringSections = stringSections.length;
      final seen = <String, int>{};
      for (final section in stringSections) {
        section.merged = block;
        section.stringOffsets.clear();
        block.originalSize += section.size;
        for (var start = 0; start < section.data.length;) {
          var end = start;
          while (section.data[end] != 0) end++;
          end++;
          final bytes = section.data.sublist(start, end);
          final value = String.fromCharCodes(bytes);
          var offset = seen[value];
          if (offset == null) {
            offset = block.data.length;
            seen[value] = offset;
            block.data.addAll(bytes);
            block.unique++;
          }
          section.stringOffsets[start] = offset;
          block.strings++;
          start = end;
        }
      }
      block.size = block.data.length;
    }
    final result = <Component>[];
    var inserted = false;
    for (final section in sections) {
      if (section.stringSection) {
        if (!inserted) {
          result.add(merged!);
          inserted = true;
        }
      } else {
        result.add(
          Component(
            'section',
            size: section.size,
            alignment: section.alignment,
            section: section,
          ),
        );
      }
    }
    if (output.name == '.bss') {
      final common = [
        for (final name in orderedNames)
          if (names[name]!.kind == 'common' && names[name]!.live) names[name]!,
      ];
      common.sort(
        (a, b) => a.alignment != b.alignment
            ? b.alignment.compareTo(a.alignment)
            : a.name.compareTo(b.name),
      );
      for (final r in common)
        result.add(
          Component('common', size: r.size, alignment: r.alignment, common: r),
        );
    }
    final targets = [
      for (final pair in veneers)
        if (identical(pair.$1, output)) pair.$2,
    ]..sort();
    for (final target in targets)
      result.add(Component('veneer', size: 8, alignment: 4, target: target));
    return result;
  }

  int? nameValue(String name) {
    final result = names[name]!;
    return switch (result.kind) {
      'global' || 'weak' => sectionValue(
        result.definition!.section!,
        result.definition!.offset,
      ),
      'common' => result.address,
      'script' => scriptValues[name] ?? 0,
      'weakundef' => 0,
      _ => null,
    };
  }

  int? symbolValue(Symbol symbol) => symbol.binding == 'local'
      ? sectionValue(symbol.section!, symbol.offset)
      : nameValue(symbol.name);
  bool farCall(Relocation relocation) {
    if (relocation.type != 'CALL24' || relocation.symbol.binding == 'local')
      return false;
    final result = names[relocation.symbol.name]!;
    if (result.kind != 'global' && result.kind != 'weak') return false;
    final value =
        nameValue(relocation.symbol.name)! +
        relocation.addend -
        (relocation.section.address + relocation.offset);
    return value < -(1 << 25) || value >= 1 << 25;
  }

  void layout() {
    while (true) {
      veneerComponents.clear();
      for (final segment in script.segments) {
        for (final output in segment.sections)
          output.components = components(output);
        placeSegment(segment);
        for (final output in segment.sections) {
          for (final component in output.components) {
            if (component.kind == 'veneer')
              veneerComponents[(output, component.target)] = component;
          }
        }
      }
      var changed = false;
      for (final object in objects) {
        for (final section in object.sections) {
          if (!section.live) continue;
          for (final relocation in section.relocations) {
            if (farCall(relocation) &&
                veneers.add((section.output!, relocation.symbol.name)))
              changed = true;
          }
        }
      }
      if (!changed) return;
    }
  }

  void loadAddresses() {
    final positions = <String, int>{};
    for (final segment in script.segments) {
      segment.physical = segment.base;
      positions[segment.name] = segment.base + segment.memorySize;
    }
    for (final load in script.loads) {
      final a = script.segmentNames[load.$1]!,
          b = script.segmentNames[load.$2]!;
      a.physical = aligned(positions[b.name]!, 4);
      positions[b.name] = a.physical + a.fileSize;
    }
    for (final segment in script.segments)
      segment.used = positions[segment.name]! - segment.base;
  }

  void defineScriptSymbols() {
    for (final definition in script.definitions)
      scriptValues[definition.name] = ScriptExpression(
        expressionTokens(definition.expression),
        this,
      ).expression();
  }

  void relocate() {
    for (final kind in relocationTypes) relocationCounts[kind] = {};
    for (final segment in script.segments) {
      for (final output in segment.sections) {
        for (final component in output.components) {
          if (component.kind != 'section') continue;
          final section = component.section!;
          for (var i = 0; i < section.relocations.length; i++) {
            final relocation = section.relocations[i];
            if (unpaired(section.relocations, i))
              relocationDiagnostics.add(
                'error: unpaired HI16 at ${relocationLocation(relocation)} against ${relocation.symbol.name}',
              );
            final p = section.address + relocation.offset;
            var symbol = symbolValue(relocation.symbol);
            var status = 'undefined',
                value = '-',
                field = '-',
                shownSymbol = '-';
            if (symbol != null) {
              status = 'ok';
              if (farCall(relocation)) {
                symbol =
                    veneerComponents[(output, relocation.symbol.name)]!.address;
                status = 'veneer';
              }
              final (v, f, valid) = relocationField(
                relocation.type,
                symbol,
                relocation.addend,
                p,
                scriptValues['_gp'] ?? 0,
              );
              if (!valid) {
                status = 'overflow';
                relocationDiagnostics.add(
                  'error: relocation overflow at ${relocationLocation(relocation)}: ${relocation.type} value $v against ${relocation.symbol.name}',
                );
              }
              littleEndian(
                section.data,
                relocation.offset,
                f,
                width(relocation.type),
              );
              shownSymbol = hex(symbol);
              value = '$v';
              field = hex(f, 2 * width(relocation.type));
            }
            final counts = relocationCounts[relocation.type]!;
            counts.update(status, (n) => n + 1, ifAbsent: () => 1);
            counts.update('total', (n) => n + 1, ifAbsent: () => 1);
            relocationLines.add(
              '${hex(p)} ${section.object.name} ${section.name}+${relocation.offset} ${relocation.type} ${relocation.symbol.name} ${relocation.addend} $shownSymbol $value $field $status',
            );
          }
        }
      }
    }
    for (final kind in relocationTypes) {
      final counts = relocationCounts[kind]!;
      relocationLines.add(
        'summary $kind total ${counts['total'] ?? 0} ok ${counts['ok'] ?? 0} veneer ${counts['veneer'] ?? 0} overflow ${counts['overflow'] ?? 0} undefined ${counts['undefined'] ?? 0}',
      );
    }
  }

  void buildImages() {
    for (final segment in script.segments) {
      segment.image = List.filled(segment.fileSize, segment.fill);
      for (final output in segment.sections) {
        if (belongs(output.name, '.bss')) continue;
        for (final component in output.components) {
          List<int> data = [];
          switch (component.kind) {
            case 'section':
              data = component.section!.data;
            case 'merged':
              data = component.data;
            case 'veneer':
              data = [4, 240, 31, 229, 0, 0, 0, 0];
              littleEndian(data, 4, nameValue(component.target)!, 4);
          }
          final offset = component.address - segment.base;
          segment.image.setRange(offset, offset + data.length, data);
        }
      }
    }
    if (script.checksumSegment.isNotEmpty) {
      final segment = script.segmentNames[script.checksumSegment]!;
      final target = names[script.checksumSymbol]!.definition!;
      final offset =
          sectionValue(target.section!, target.offset) - segment.base;
      littleEndian(segment.image, offset, 0, 4);
      var sum = 0;
      for (var i = 0; i < segment.image.length; i += 4) {
        var word = 0;
        for (var j = 0; j < 4 && i + j < segment.image.length; j++)
          word += segment.image[i + j] << (8 * j);
        sum += word;
      }
      littleEndian(segment.image, offset, modulo(-sum, 1 << 32), 4);
    }
  }

  int entryAddress() {
    final entry = names[script.entry];
    return entry != null && {'global', 'weak', 'common'}.contains(entry.kind)
        ? nameValue(script.entry)!
        : 0;
  }

  List<String> imageHex() {
    final result = ['entry ${hex(entryAddress())} ${script.entry}'];
    for (final segment in script.segments) {
      result.add(
        'segment ${segment.name} vaddr ${hex(segment.base)} paddr ${hex(segment.physical)} filesz ${segment.fileSize} memsz ${segment.memorySize}',
      );
      for (var i = 0; i < segment.image.length; i += 16) {
        result.add(
          [
            hex(segment.base + i),
            for (final value in segment.image.sublist(
              i,
              min(i + 16, segment.image.length),
            ))
              hex(value, 2),
          ].join(' '),
        );
      }
    }
    return result;
  }

  List<String> intelHex() {
    final segments = script.segments.where((s) => s.fileSize > 0).toList();
    stableSort(segments, (a, b) => a.physical.compareTo(b.physical));
    var upper = 0;
    final result = <String>[];
    for (final segment in segments) {
      for (var k = 0; k < segment.fileSize;) {
        final address = segment.physical + k;
        final n = min(16, min(segment.fileSize - k, 65536 - address % 65536));
        if (address ~/ 65536 != upper) {
          upper = address ~/ 65536;
          result.add(hexRecord(0, 4, [upper ~/ 256, upper % 256]));
        }
        result.add(
          hexRecord(address % 65536, 0, segment.image.sublist(k, k + n)),
        );
        k += n;
      }
    }
    final entry = entryAddress();
    result.add(
      hexRecord(0, 5, [
        entry >> 24 & 255,
        entry >> 16 & 255,
        entry >> 8 & 255,
        entry & 255,
      ]),
    );
    result.add(hexRecord(0, 1, []));
    return result;
  }

  String status(Resolution result) => switch (result.kind) {
    'global' ||
    'weak' => result.definition!.section!.live ? 'kept' : 'discarded',
    'common' => result.live ? 'kept' : 'discarded',
    'script' => 'kept',
    _ => '-',
  };
  List<String> crossReferences() => [
    for (final name in orderedNames)
      '$name ${names[name]!.kind} ${status(names[name]!)} ${names[name]!.definer} ${names[name]!.referrers.isEmpty ? '-' : names[name]!.referrers.join(',')}',
  ];
  List<String> linkMap() {
    final result = <String>[];
    for (final extraction in extractions)
      result.add(
        'member ${extraction.object} ${extraction.referrer} ${extraction.reason}',
      );
    for (final signature in comdatOrder) {
      final record = comdat[signature]!;
      result.add(
        'comdat $signature ${record.keeper.name} ${record.discarders.isEmpty ? '-' : record.discarders.join(',')}',
      );
    }
    final veneerSymbols = <MapSymbol>[];
    for (final segment in script.segments) {
      result.add(
        'segment ${segment.name} vaddr ${hex(segment.base)} paddr ${hex(segment.physical)} filesz ${segment.fileSize} memsz ${segment.memorySize} used ${segment.used} length ${segment.length} ${100 * segment.used ~/ segment.length}%',
      );
      for (final output in segment.sections) {
        result.add(
          'section ${output.name} ${hex(output.address)} ${output.size} ${output.alignment}',
        );
        for (final component in output.components) {
          switch (component.kind) {
            case 'section':
              result.add(
                'input ${hex(component.address)} ${component.size} ${component.alignment} ${component.section!.object.name} ${component.section!.name}',
              );
            case 'merged':
              result.add(
                'merged ${hex(component.address)} ${component.size} sections ${component.stringSections} strings ${component.strings} unique ${component.unique} saved ${component.originalSize - component.size}',
              );
            case 'common':
              result.add(
                'common ${hex(component.address)} ${component.size} ${component.alignment} ${component.common!.definer} ${component.common!.name}',
              );
            case 'veneer':
              result.add(
                'veneer ${hex(component.address)} 8 ${component.target}',
              );
              veneerSymbols.add(
                MapSymbol(
                  component.address,
                  '__veneer_${component.target}',
                  'veneer',
                  '*linker*',
                ),
              );
          }
        }
      }
    }
    for (final object in objects) {
      for (final section in object.sections) {
        if (section.reason.isNotEmpty)
          result.add(
            'discard ${object.name} ${section.name} ${section.size} ${section.reason}',
          );
      }
    }
    final symbols = <MapSymbol>[];
    for (final name in orderedNames) {
      final resolution = names[name]!;
      if (resolution.kind == 'common' && !resolution.live)
        result.add(
          'discard ${resolution.definer} COMMON($name) ${resolution.size} gc',
        );
      if (status(resolution) == 'kept')
        symbols.add(
          MapSymbol(
            nameValue(name)!,
            name,
            resolution.kind,
            resolution.definer,
          ),
        );
    }
    symbols.addAll(veneerSymbols);
    stableSort(
      symbols,
      (a, b) => a.address != b.address
          ? a.address.compareTo(b.address)
          : a.name.compareTo(b.name),
    );
    for (final symbol in symbols)
      result.add(
        'symbol ${hex(symbol.address)} ${symbol.name} ${symbol.kind} ${symbol.definer}',
      );
    return result;
  }

  List<String> unresolvedReferrers(String name) => [
    for (final object in objects)
      if (object.sections.any(
        (s) =>
            s.live &&
            s.relocations.any(
              (r) => r.symbol.binding != 'local' && r.symbol.name == name,
            ),
      ))
        object.name,
  ];
  List<String> diagnostics() {
    final result = <String>[];
    for (final name in sortedKeys(orphans))
      result.add(
        'warning: orphan section $name discarded from ${orphans[name]} object(s)',
      );
    for (final name in orderedNames) {
      final resolution = names[name]!;
      final definers = resolution.strongDefiners(
        script.scriptNames.contains(name),
      );
      if (definers.length >= 2)
        result.add(
          'error: multiple definition of $name: ${definers.join(' ')}',
        );
      if (resolution.common.isNotEmpty &&
          (resolution.kind == 'global' || resolution.kind == 'script'))
        result.add(
          'warning: common symbol $name overridden by ${resolution.definer}',
        );
      if (resolution.kind == 'common') {
        final pairs = {
          for (final symbol in resolution.common)
            (symbol.size, symbol.alignment),
        };
        if (pairs.length > 1)
          result.add(
            'warning: common symbol $name merged to size ${resolution.size} align ${resolution.alignment}',
          );
      }
    }
    final entry = names[script.entry];
    if (entry == null || entry.kind == 'undefined' || entry.kind == 'weakundef')
      result.add('error: entry symbol ${script.entry} is undefined');
    for (final name in orderedNames) {
      if (names[name]!.kind == 'undefined') {
        final referrers = unresolvedReferrers(name);
        if (referrers.isNotEmpty)
          result.add(
            'error: undefined symbol $name referenced by ${referrers.join(' ')}',
          );
      }
    }
    for (final segment in script.segments) {
      if (segment.used > segment.length)
        result.add(
          'error: segment ${segment.name} overflows its length by ${segment.used - segment.length} bytes',
        );
    }
    for (var i = 0; i < script.segments.length; i++) {
      final a = script.segments[i];
      for (final b in script.segments.skip(i + 1)) {
        if (a.memorySize > 0 &&
            b.memorySize > 0 &&
            a.base < b.base + b.memorySize &&
            b.base < a.base + a.memorySize)
          result.add('error: segments ${a.name} and ${b.name} overlap');
      }
    }
    result.addAll(relocationDiagnostics);
    final errors = result.where((s) => s.startsWith('error:')).length;
    final warnings = result.where((s) => s.startsWith('warning:')).length;
    result.add('errors $errors warnings $warnings');
    return result;
  }
}

int sectionValue(Section section, int offset) => section.stringSection
    ? section.merged!.address + section.stringOffsets[offset]!
    : section.address + offset;
List<String> expressionTokens(String source) {
  final result = <String>[];
  var i = 0;
  while (i < source.length) {
    if (source[i] == ' ') {
      i++;
      continue;
    }
    if ('(),+-'.contains(source[i])) {
      result.add(source[i++]);
      continue;
    }
    final start = i;
    while (i < source.length &&
        source[i] != ' ' &&
        !'(),+-'.contains(source[i]))
      i++;
    result.add(source.substring(start, i));
  }
  return result;
}

class ScriptExpression {
  final List<String> tokens;
  final Linker linker;
  int index = 0;
  ScriptExpression(this.tokens, this.linker);
  String get peek => index == tokens.length ? '' : tokens[index];
  int expression() {
    var value = term();
    while (peek == '+' || peek == '-') {
      final op = tokens[index++];
      final right = term();
      value = op == '+' ? value + right : value - right;
    }
    return value;
  }

  int term() {
    final token = tokens[index++];
    if (token == '(') {
      final value = expression();
      index++;
      return value;
    }
    if (token.codeUnitAt(0) >= 48 && token.codeUnitAt(0) <= 57)
      return number(token);
    if (peek == '(' &&
        {'start', 'end', 'size', 'loadaddr', 'align'}.contains(token)) {
      index++;
      if (token == 'align') {
        final value = expression();
        index++;
        final n = expression();
        index++;
        return aligned(value, n);
      }
      final output = linker.script.outputNames[tokens[index]]!;
      index += 2;
      return switch (token) {
        'start' => output.address,
        'end' => output.address + output.size,
        'size' => output.size,
        _ => output.segment.physical + output.address - output.segment.base,
      };
    }
    return linker.scriptValues[token]!;
  }
}

String hexRecord(int address, int kind, List<int> data) {
  final record = [
    data.length,
    address >> 8 & 255,
    address & 255,
    kind,
    ...data,
  ];
  final sum = record.fold(0, (a, b) => a + b);
  record.add(modulo(-sum, 256));
  return ':${record.map((v) => hex(v, 2).toUpperCase()).join()}';
}

void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final linker = Linker(readScript());
  linker.loadInputs();
  linker.resolve();
  linker.collect();
  linker.layout();
  linker.loadAddresses();
  linker.defineScriptSymbols();
  linker.relocate();
  linker.buildImages();
  Directory('output').createSync(recursive: true);
  writeLines('image.hex', linker.imageHex());
  writeLines('flash.ihex', linker.intelHex());
  writeLines('link.map', linker.linkMap());
  writeLines('xref.txt', linker.crossReferences());
  writeLines('relocations.txt', linker.relocationLines);
  writeLines('diagnostics.txt', linker.diagnostics());
}
