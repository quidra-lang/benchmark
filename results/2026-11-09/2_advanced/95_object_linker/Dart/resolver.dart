part of 'main.dart';

class Resolution {
  final String name;
  String kind = '', definer = '-';
  Symbol? definition;
  final List<Symbol> strong = [], weak = [], common = [], references = [];
  final List<String> referrers = [];
  int size = 0, alignment = 0, address = 0;
  bool live = false;
  Resolution(this.name);
  List<String> strongDefiners(bool script) => [
    if (script) '*script*',
    for (final symbol in strong) symbol.object.name,
  ];
}

Resolution resolveName(String name, List<Symbol> entries, bool script) {
  final result = Resolution(name);
  final seen = <ObjectFile>{};
  for (final symbol in entries) {
    switch (symbol.location) {
      case 'undef':
        result.references.add(symbol);
        if (seen.add(symbol.object)) result.referrers.add(symbol.object.name);
      case 'common':
        result.common.add(symbol);
      case 'section':
        (symbol.binding == 'global' ? result.strong : result.weak).add(symbol);
    }
  }
  if (script) {
    result.kind = 'script';
    result.definer = '*script*';
  } else if (result.strong.isNotEmpty) {
    result.kind = 'global';
    result.definition = result.strong.first;
    result.definer = result.definition!.object.name;
  } else if (result.common.isNotEmpty) {
    result.kind = 'common';
    for (final symbol in result.common) {
      result.size = max(result.size, symbol.size);
      result.alignment = max(result.alignment, symbol.alignment);
    }
    result.definer = result.common
        .firstWhere((s) => s.size == result.size)
        .object
        .name;
  } else if (result.weak.isNotEmpty) {
    result.kind = 'weak';
    result.definition = result.weak.first;
    result.definer = result.definition!.object.name;
  } else {
    result.kind = result.references.any((s) => s.binding == 'global')
        ? 'undefined'
        : 'weakundef';
  }
  return result;
}
