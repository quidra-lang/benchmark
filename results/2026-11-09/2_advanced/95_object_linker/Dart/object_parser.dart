part of 'main.dart';

class ObjectFile {
  final String name;
  int rank = 0;
  final List<Section> sections = [];
  final List<Symbol> symbols = [];
  final List<ComdatGroup> groups = [];
  final Map<String, Section> sectionNames = {};
  final Map<String, Symbol> symbolNames = {};
  ObjectFile(this.name);
}

class Section {
  final String name;
  final int alignment, size;
  final ObjectFile object;
  int address = 0;
  final List<int> data = [];
  final List<Relocation> relocations = [];
  String reason = '';
  OutputSection? output;
  bool live = false;
  Component? merged;
  final Map<int, int> stringOffsets = {};
  Section(this.name, this.alignment, this.size, this.object);
  bool get nobits => belongs(name, '.bss');
  bool get stringSection => belongs(name, '.rodata.str');
}

class Symbol {
  String name, location;
  final String binding;
  final ObjectFile object;
  Section? section;
  int offset = 0, size = 0, alignment = 0;
  Symbol(this.name, this.binding, this.location, this.object);
}

class Relocation {
  final Section section;
  final int offset, addend;
  final String type;
  final Symbol symbol;
  Relocation(this.section, this.offset, this.type, this.symbol, this.addend);
}

class ComdatGroup {
  final String signature;
  final List<Section> sections;
  ComdatGroup(this.signature, this.sections);
}

bool belongs(String name, String base) =>
    name == base || name.startsWith('$base.');
List<String> readLines(String path) => File(path).readAsLinesSync();
int number(String value) => value.startsWith('0x')
    ? int.parse(value.substring(2), radix: 16)
    : int.parse(value);
ObjectFile parseObject(List<String> lines, String name) {
  final object = ObjectFile(name);
  Section? current;
  for (final line in lines) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'section':
        final section = Section(a[1], number(a[2]), number(a[3]), object);
        current = section;
        object.sections.add(section);
        object.sectionNames[section.name] = section;
      case 'data':
        for (var i = 0; i < a[1].length; i += 2) {
          current!.data.add(int.parse(a[1].substring(i, i + 2), radix: 16));
        }
      case 'comdat':
        object.groups.add(
          ComdatGroup(a[1], [
            for (final name in a.skip(2)) object.sectionNames[name]!,
          ]),
        );
      case 'symbol':
        final symbol = Symbol(a[1], a[2], a[3], object);
        if (a[3] == 'common') {
          symbol.size = number(a[4]);
          symbol.alignment = number(a[5]);
        } else if (a[3] != 'undef') {
          symbol.location = 'section';
          symbol.section = object.sectionNames[a[3]]!;
          symbol.offset = number(a[4]);
        }
        object.symbols.add(symbol);
        object.symbolNames[symbol.name] = symbol;
      case 'reloc':
        final relocationSection = object.sectionNames[a[1]]!;
        relocationSection.relocations.add(
          Relocation(
            relocationSection,
            number(a[2]),
            a[3],
            object.symbolNames[a[4]]!,
            number(a[5]),
          ),
        );
    }
  }
  return object;
}
