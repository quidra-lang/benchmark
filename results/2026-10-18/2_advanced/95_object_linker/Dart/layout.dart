part of 'main.dart';

class Segment {
  final String name;
  final int base, length, fill;
  int physical = 0, fileSize = 0, memorySize = 0, used = 0;
  final List<OutputSection> sections = [];
  List<int> image = [];
  Segment(this.name, this.base, this.length, this.fill);
}

class OutputSection {
  final String name;
  final Segment segment;
  List<Component> components = [];
  int address = 0, size = 0, alignment = 1;
  OutputSection(this.name, this.segment);
}

class Component {
  final String kind;
  int size, alignment, address = 0;
  final Section? section;
  final Resolution? common;
  final String target;
  final List<int> data = [];
  int stringSections = 0, strings = 0, unique = 0, originalSize = 0;
  Component(
    this.kind, {
    this.size = 0,
    this.alignment = 1,
    this.section,
    this.common,
    this.target = '',
  });
}

typedef VeneerPair = (OutputSection, String);
int aligned(int value, int n) => (value + n - 1) ~/ n * n;
OutputSection? outputFor(Section section, List<OutputSection> outputs) {
  for (final output in outputs) {
    if (belongs(section.name, output.name)) return output;
  }
  return null;
}

void placeSegment(Segment segment) {
  var cursor = segment.base;
  segment.fileSize = 0;
  for (final output in segment.sections) {
    var alignment = 1;
    for (final component in output.components)
      alignment = max(alignment, component.alignment);
    cursor = aligned(cursor, alignment);
    output.address = cursor;
    output.alignment = alignment;
    for (final component in output.components) {
      cursor = aligned(cursor, component.alignment);
      component.address = cursor;
      if (component.kind == 'section') component.section!.address = cursor;
      if (component.kind == 'common') component.common!.address = cursor;
      cursor += component.size;
    }
    output.size = cursor - output.address;
    if (!belongs(output.name, '.bss')) segment.fileSize = cursor - segment.base;
  }
  segment.memorySize = cursor - segment.base;
}
