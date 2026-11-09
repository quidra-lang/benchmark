part of 'main.dart';

class Option {
  final String name, value;
  Option(this.name, this.value);
}

class Operand {
  final String kind, name, value;
  int records = 0;
  Operand(this.kind, this.name, [this.value = '']);
}

bool validName(String name) =>
    name.isNotEmpty &&
    (letter(name.codeUnitAt(0)) || name[0] == '_') &&
    name.codeUnits.every((c) => letter(c) || digit(c) || c == 95);
bool validFilename(String name) =>
    name.isNotEmpty &&
    !name.startsWith('.') &&
    name.codeUnits.every(
      (c) => letter(c) || digit(c) || {46, 95, 45}.contains(c),
    );
(List<Option>, List<Operand>) parseArguments(List<String> lines) {
  final options = <Option>[];
  final operands = <Operand>[];
  for (final line in lines) {
    if (line.startsWith('-F ')) {
      options.add(Option('FS', line.substring(3)));
      continue;
    }
    if (line.startsWith('-v ')) {
      final equal = line.indexOf('=', 3);
      options.add(Option(line.substring(3, equal), line.substring(equal + 1)));
      continue;
    }
    final equal = line.indexOf('=');
    if (equal >= 0 && validName(line.substring(0, equal))) {
      operands.add(
        Operand(
          'assignment',
          line.substring(0, equal),
          line.substring(equal + 1),
        ),
      );
    } else {
      operands.add(Operand('file', line));
    }
  }
  return (options, operands);
}

String readText(String path) => File(path).readAsStringSync();
List<String> textLines(String text) => text.isEmpty
    ? []
    : (text.endsWith('\n') ? text.substring(0, text.length - 1) : text).split(
        '\n',
      );
List<String> readRecords(String name) => textLines(readText('input/$name'));

class OutputStream {
  final List<String> parts = [];
  bool open = false;
  int writes = 0;
  String get content => parts.join();
  void append(String text) {
    parts.add(text);
    writes++;
  }
}

class GetlineInput {
  bool open = false, everOpened = false;
  List<String> lines = [];
  int position = 0, reads = 0;
}

class Streams {
  final OutputStream stdout = OutputStream();
  final Map<String, OutputStream> outputs = {};
  final Map<String, GetlineInput> inputs = {};
  void write(
    String text, [
    String name = '',
    String mode = '',
    Position position = const Position(0, 0),
  ]) {
    if (name.isEmpty && mode.isEmpty) {
      stdout.append(text);
      return;
    }
    if (!validFilename(name) || name == 'stdout.txt' || name == 'stats.txt')
      runtimeError(position, 'invalid output file name');
    final stream = outputs.putIfAbsent(name, OutputStream.new);
    if (!stream.open) {
      stream.open = true;
      if (mode == '>') stream.parts.clear();
    }
    stream.append(text);
  }

  (int, String) getline(String name) {
    final source = inputs.putIfAbsent(name, GetlineInput.new);
    if (!source.open) {
      if (!validFilename(name) || !File('input/$name').existsSync())
        return (-1, '');
      source.lines = readRecords(name);
      source.position = 0;
      source.open = source.everOpened = true;
    }
    if (source.position == source.lines.length) return (0, '');
    source.reads++;
    return (1, source.lines[source.position++]);
  }

  int close(String name) {
    var closed = false;
    final output = outputs[name];
    final input = inputs[name];
    if (output != null && output.open) {
      output.open = false;
      closed = true;
    }
    if (input != null && input.open) {
      input.open = false;
      closed = true;
    }
    return closed ? 0 : -1;
  }

  void save() {
    Directory('output').createSync(recursive: true);
    File('output/stdout.txt').writeAsStringSync(stdout.content);
    for (final entry in outputs.entries)
      File('output/${entry.key}').writeAsStringSync(entry.value.content);
  }
}
