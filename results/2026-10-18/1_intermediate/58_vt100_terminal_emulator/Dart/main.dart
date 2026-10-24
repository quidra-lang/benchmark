import 'dart:collection';
import 'dart:io';
import 'dart:math';

const bel = 0x07;
const bs = 0x08;
const ht = 0x09;
const lf = 0x0A;
const vt = 0x0B;
const ff = 0x0C;
const cr = 0x0D;
const so = 0x0E;
const si = 0x0F;
const can = 0x18;
const sub = 0x1A;
const esc = 0x1B;
const caretBytes = {
  '@': 0x00,
  'G': bel,
  'H': bs,
  'I': ht,
  'J': lf,
  'K': vt,
  'L': ff,
  'M': cr,
  'N': so,
  'O': si,
  'X': can,
  'Z': sub,
  '[': esc,
  '^': 0x5E,
};

const charsets = {'0': Charset.lineDrawing, 'B': Charset.ascii};

const maxParameter = 9999;
const maxFields = 16;
const scrollbackLimit = 100;
const scrollbackShown = 5;
const tabWidth = 8;

const lineDrawingChars = {
  '`': '*',
  'a': '#',
  'j': '+',
  'k': '+',
  'l': '+',
  'm': '+',
  'n': '+',
  't': '+',
  'u': '+',
  'v': '+',
  'w': '+',
  'q': '-',
  'x': '|',
  '~': 'o',
};
const colorNames = [
  'black',
  'red',
  'green',
  'yellow',
  'blue',
  'magenta',
  'cyan',
  'white',
];
const flagNames = [
  'bold',
  'dim',
  'italic',
  'underline',
  'blink',
  'reverse',
  'hidden',
  'strike',
];
const sgrFlagsOn = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 7: 5, 8: 6, 9: 7};
const sgrFlagsOff = {
  22: [0, 1],
  23: [2],
  24: [3],
  25: [4],
  27: [5],
  28: [6],
  29: [7],
};

const softResetModes = [
  Mode.irm,
  Mode.decckm,
  Mode.decom,
  Mode.decawm,
  Mode.dectcem,
  Mode.deckpam,
];
const ansiModes = {4: Mode.irm, 20: Mode.lnm};
const decModes = {
  1: Mode.decckm,
  5: Mode.decscnm,
  6: Mode.decom,
  7: Mode.decawm,
  25: Mode.dectcem,
  2004: Mode.bracketed,
};
const screenModes = {47, 1047, 1049};
const decModeNumbers = {1, 5, 6, 7, 25, 47, 1047, 1048, 1049, 2004};

const csiConditions = {
  'J': {0, 1, 2, 3},
  'K': {0, 1, 2},
  'g': {0, 3},
  ' q': {0, 1, 2, 3, 4, 5, 6},
  'n': {5, 6},
  '?n': {6},
  'c': {0},
  '>c': {0},
  't': {18},
};
const wrapClearingCsi = 'ABCDEFGHIJKLMPSTXZ`adef@';

const cursorKeys = {
  'UP': 'A',
  'DOWN': 'B',
  'RIGHT': 'C',
  'LEFT': 'D',
  'HOME': 'H',
  'END': 'F',
};
const fixedKeys = {
  'INSERT': '^[[2~',
  'DELETE': '^[[3~',
  'PAGEUP': '^[[5~',
  'PAGEDOWN': '^[[6~',
  'F1': '^[OP',
  'F2': '^[OQ',
  'F3': '^[OR',
  'F4': '^[OS',
  'F5': '^[[15~',
  'F6': '^[[17~',
  'F7': '^[[18~',
  'F8': '^[[19~',
  'F9': '^[[20~',
  'F10': '^[[21~',
  'F11': '^[[23~',
  'F12': '^[[24~',
  'TAB': '^I',
  'BACKSPACE': '^?',
  'ESCAPE': '^[',
};
const keyPrefix = '%%KEY ';
const pastePrefix = '%%PASTE ';

enum ParserState {
  ground,
  escape,
  escapeIntermediate,
  csiEntry,
  csiParam,
  csiIntermediate,
  csiIgnore,
  oscString,
}

enum Reason { unsupported, malformed, canceled, invalid }

enum Display { main, alternate }

enum Charset { ascii, lineDrawing }

enum Mode {
  irm('IRM', false),
  lnm('LNM', false),
  decckm('DECCKM', false),
  decscnm('DECSCNM', false),
  decom('DECOM', false),
  decawm('DECAWM', true),
  dectcem('DECTCEM', true),
  deckpam('DECKPAM', false),
  bracketed('BRACKETED', false);

  const Mode(this.label, this.initial);

  final String label;
  final bool initial;
}

typedef Attributes = ({int flags, String? foreground, String? background});
typedef Cell = ({String char, Attributes attributes});
typedef SavedCursor = ({
  int row,
  int column,
  Attributes attributes,
  bool origin,
  Charset g0,
  Charset g1,
  int gl,
});

const Attributes defaultAttributes = (
  flags: 0,
  foreground: null,
  background: null,
);
const Cell blankCell = (char: ' ', attributes: defaultAttributes);
const SavedCursor initialCursor = (
  row: 1,
  column: 1,
  attributes: defaultAttributes,
  origin: false,
  g0: Charset.ascii,
  g1: Charset.ascii,
  gl: 0,
);

extension AttributesDescription on Attributes {
  bool get isDefault => this == defaultAttributes;

  String describe() => [
    for (var index = 0; index < flagNames.length; index++)
      if ((flags >> index) & 1 == 1) flagNames[index],
    if (foreground != null) 'fg=$foreground',
    if (background != null) 'bg=$background',
  ].join(' ');
}

class SequenceIgnored implements Exception {
  SequenceIgnored(this.reason);

  final Reason reason;
}

void require(bool condition, [Reason reason = Reason.unsupported]) {
  if (!condition) {
    throw SequenceIgnored(reason);
  }
}

bool isIntermediate(int byte) => byte >= 0x20 && byte <= 0x2F;

bool isParameter(int byte) => (byte >= 0x30 && byte <= 0x39) || byte == 0x3B;

bool isPrivateMarker(int byte) => byte >= 0x3C && byte <= 0x3F;

bool isFinal(int byte) => byte >= 0x40 && byte <= 0x7E;

List<int> decodeStream(String line) {
  final data = <int>[];
  var index = 0;
  while (index < line.length) {
    if (line[index] == '^') {
      data.add(caretBytes[line[index + 1]]!);
      index += 2;
    } else {
      data.add(line.codeUnitAt(index));
      index++;
    }
  }
  return data;
}

int fieldValue(String field) {
  var value = 0;
  for (final digit in field.split('')) {
    value = min(value * 10 + int.parse(digit), maxParameter);
  }
  return value;
}

int parameter(List<int> params, int index) =>
    index < params.length ? params[index] : 0;

int amount(List<int> params) => max(parameter(params, 0), 1);

String paletteColor(int number) {
  if (number < 8) {
    return colorNames[number];
  }
  if (number < 16) {
    return 'bright-${colorNames[number - 8]}';
  }
  return '$number';
}

String rgbColor(int red, int green, int blue) {
  final digits = [
    red,
    green,
    blue,
  ].map((value) => value.toRadixString(16).padLeft(2, '0'));
  return '#${digits.join()}';
}

(String, int) extendedColor(List<int> values, int start) {
  final rest = values.sublist(start);
  if (rest.length >= 2 && rest[0] == 5 && rest[1] <= 255) {
    return (paletteColor(rest[1]), 2);
  }
  if (rest.length >= 4 &&
      rest[0] == 2 &&
      rest.sublist(1, 4).every((value) => value <= 255)) {
    return (rgbColor(rest[1], rest[2], rest[3]), 4);
  }
  throw SequenceIgnored(Reason.unsupported);
}

int modeState(bool enabled) => enabled ? 1 : 2;

String rowText(List<Cell> cells) =>
    cells.map((cell) => cell.char).join().trimRight();

class Screen {
  Screen(this.width, this.height) {
    clear();
  }

  final int width;
  final int height;
  var rows = <List<Cell>>[];

  List<Cell> blankRow() => List.filled(width, blankCell);

  void clear() {
    rows = List.generate(height, (_) => blankRow());
  }

  void fill(String char) {
    final cell = (char: char, attributes: defaultAttributes);
    rows = List.generate(height, (_) => List.filled(width, cell));
  }

  void put(int row, int column, Cell cell) {
    rows[row - 1][column - 1] = cell;
  }

  void erase(int row, int first, int last) {
    rows[row - 1].fillRange(first - 1, last, blankCell);
  }

  void eraseRows(int first, int last) {
    for (var row = first; row <= last; row++) {
      rows[row - 1] = blankRow();
    }
  }

  List<Cell> scrollUp(int top, int bottom) {
    final removed = rows.removeAt(top - 1);
    rows.insert(bottom - 1, blankRow());
    return removed;
  }

  void scrollDown(int top, int bottom) {
    rows.removeAt(bottom - 1);
    rows.insert(top - 1, blankRow());
  }

  void insertCells(int row, int column, int count) {
    final cells = rows[row - 1];
    cells.setRange(column - 1 + count, width, cells, column - 1);
    cells.fillRange(column - 1, column - 1 + count, blankCell);
  }

  void deleteCells(int row, int column, int count) {
    final cells = rows[row - 1];
    cells.setRange(column - 1, width - count, cells, column - 1 + count);
    cells.fillRange(width - count, width, blankCell);
  }

  String text(int row) => rowText(rows[row - 1]);
}

class Terminal {
  Terminal(this.width, this.height) {
    reset();
  }

  final int width;
  final int height;
  final output = StringBuffer();
  final ignored = List.filled(Reason.values.length, 0);
  var streamBytes = 0;
  var printed = 0;
  var sequences = 0;
  var bells = 0;
  var replies = 0;
  var dumps = 0;

  late List<Screen> screens;
  late Display display;
  late int row;
  late int column;
  late bool pendingWrap;
  late Attributes attributes;
  late Charset g0;
  late Charset g1;
  late int gl;
  late Set<Mode> modes;
  late int cursorShape;
  late int top;
  late int bottom;
  late SplayTreeSet<int> tabStops;
  late List<SavedCursor?> saved;
  late List<String> scrollback;
  String? title;
  String? lastChar;
  late ParserState state;
  late String marker;
  late String parameters;
  late String intermediates;
  late String osc;

  Screen get screen => screens[display.index];

  void reset() {
    screens = [Screen(width, height), Screen(width, height)];
    display = Display.main;
    row = 1;
    column = 1;
    pendingWrap = false;
    attributes = defaultAttributes;
    g0 = Charset.ascii;
    g1 = Charset.ascii;
    gl = 0;
    modes = {
      for (final mode in Mode.values)
        if (mode.initial) mode,
    };
    cursorShape = 1;
    top = 1;
    bottom = height;
    tabStops = SplayTreeSet.of([
      for (var stop = tabWidth + 1; stop <= width; stop += tabWidth) stop,
    ]);
    saved = [null, null];
    scrollback = [];
    title = null;
    lastChar = null;
    state = ParserState.ground;
    clearSequence();
  }

  void clearSequence() {
    marker = '';
    parameters = '';
    intermediates = '';
    osc = '';
  }

  void emit(String line) {
    output.writeln(line);
  }

  void ignore(Reason reason) {
    ignored[reason.index]++;
  }

  void setMode(Mode mode, bool enabled) {
    if (enabled) {
      modes.add(mode);
    } else {
      modes.remove(mode);
    }
  }

  void receive(int byte) {
    streamBytes++;
    if (byte < 0x20) {
      receiveControl(byte);
      return;
    }
    switch (state) {
      case ParserState.ground:
        printChar(String.fromCharCode(byte));
      case ParserState.escape || ParserState.escapeIntermediate:
        escapeByte(byte);
      case ParserState.oscString:
        osc += String.fromCharCode(byte);
      case ParserState.csiIgnore:
        if (isFinal(byte)) {
          ignore(Reason.malformed);
          state = ParserState.ground;
        }
      case ParserState.csiIntermediate:
        csiIntermediateByte(byte);
      case ParserState.csiEntry when isPrivateMarker(byte):
        marker = String.fromCharCode(byte);
        state = ParserState.csiParam;
      case ParserState.csiEntry || ParserState.csiParam:
        csiParamByte(byte);
    }
  }

  void receiveControl(int byte) {
    if (byte == esc) {
      if (state == ParserState.oscString) {
        executeOsc();
      } else if (state != ParserState.ground) {
        ignore(Reason.canceled);
      }
      clearSequence();
      state = ParserState.escape;
    } else if (byte == can || byte == sub) {
      if (state != ParserState.ground) {
        ignore(Reason.canceled);
        state = ParserState.ground;
      }
    } else if (state == ParserState.oscString) {
      if (byte == bel) {
        executeOsc();
        state = ParserState.ground;
      }
    } else {
      executeControl(byte);
    }
  }

  void escapeByte(int byte) {
    final char = String.fromCharCode(byte);
    if (isIntermediate(byte)) {
      intermediates += char;
      state = ParserState.escapeIntermediate;
    } else if (state == ParserState.escape && char == '[') {
      state = ParserState.csiEntry;
    } else if (state == ParserState.escape && char == ']') {
      state = ParserState.oscString;
    } else {
      executeEsc(intermediates + char);
      state = ParserState.ground;
    }
  }

  void csiParamByte(int byte) {
    final char = String.fromCharCode(byte);
    if (isParameter(byte)) {
      parameters += char;
      state = ParserState.csiParam;
    } else if (isIntermediate(byte)) {
      intermediates += char;
      state = ParserState.csiIntermediate;
    } else if (isFinal(byte)) {
      executeCsi(char);
      state = ParserState.ground;
    } else {
      state = ParserState.csiIgnore;
    }
  }

  void csiIntermediateByte(int byte) {
    final char = String.fromCharCode(byte);
    if (isIntermediate(byte)) {
      intermediates += char;
    } else if (isFinal(byte)) {
      executeCsi(char);
      state = ParserState.ground;
    } else {
      state = ParserState.csiIgnore;
    }
  }

  void executeControl(int byte) {
    switch (byte) {
      case bel:
        bells++;
      case bs:
        pendingWrap = false;
        column = max(column - 1, 1);
      case ht:
        pendingWrap = false;
        tabMove(1);
      case lf || vt || ff:
        pendingWrap = false;
        lineFeed();
        if (modes.contains(Mode.lnm)) {
          column = 1;
        }
      case cr:
        pendingWrap = false;
        column = 1;
      case so:
        gl = 1;
      case si:
        gl = 0;
    }
  }

  void printChar(String char) {
    final charset = gl == 1 ? g1 : g0;
    if (charset == Charset.lineDrawing) {
      write(lineDrawingChars[char] ?? char);
    } else {
      write(char);
    }
  }

  void write(String char) {
    printed++;
    lastChar = char;
    if (pendingWrap) {
      pendingWrap = false;
      column = 1;
      lineFeed();
    }
    if (modes.contains(Mode.irm)) {
      screen.insertCells(row, column, 1);
    }
    screen.put(row, column, (char: char, attributes: attributes));
    if (column < width) {
      column++;
    } else if (modes.contains(Mode.decawm)) {
      pendingWrap = true;
    }
  }

  void scrollRegionUp() {
    final removed = screen.scrollUp(top, bottom);
    if (display == Display.main && top == 1) {
      scrollback.add(rowText(removed));
      if (scrollback.length > scrollbackLimit) {
        scrollback.removeAt(0);
      }
    }
  }

  void scrollRegionDown() {
    screen.scrollDown(top, bottom);
  }

  void lineFeed() {
    if (row == bottom) {
      scrollRegionUp();
    } else if (row < height) {
      row++;
    }
  }

  void reverseLineFeed() {
    if (row == top) {
      scrollRegionDown();
    } else if (row > 1) {
      row--;
    }
  }

  void tabMove(int count) {
    for (var moves = 0; moves < count && column < width; moves++) {
      column = tabStops.firstWhere(
        (stop) => stop > column,
        orElse: () => width,
      );
    }
  }

  void reverseTabMove(int count) {
    for (var moves = 0; moves < count && column > 1; moves++) {
      column = tabStops.lastWhere((stop) => stop < column, orElse: () => 1);
    }
  }

  int addressRow(int value) {
    if (modes.contains(Mode.decom)) {
      return min(top + value - 1, bottom);
    }
    return min(value, height);
  }

  void home() {
    row = addressRow(1);
    column = 1;
  }

  void saveCursor() {
    saved[display.index] = (
      row: row,
      column: column,
      attributes: attributes,
      origin: modes.contains(Mode.decom),
      g0: g0,
      g1: g1,
      gl: gl,
    );
  }

  void restoreCursor() {
    pendingWrap = false;
    final cursor = saved[display.index] ?? initialCursor;
    row = cursor.row;
    column = cursor.column;
    attributes = cursor.attributes;
    setMode(Mode.decom, cursor.origin);
    g0 = cursor.g0;
    g1 = cursor.g1;
    gl = cursor.gl;
  }

  void screenAlignment() {
    pendingWrap = false;
    screen.fill('E');
    top = 1;
    bottom = height;
    setMode(Mode.decom, false);
    row = 1;
    column = 1;
  }

  void executeEsc(String key) {
    switch (key) {
      case '7':
        saveCursor();
      case '8':
        restoreCursor();
      case 'D':
        pendingWrap = false;
        lineFeed();
      case 'E':
        pendingWrap = false;
        column = 1;
        lineFeed();
      case 'M':
        pendingWrap = false;
        reverseLineFeed();
      case 'H':
        tabStops.add(column);
      case 'c':
        reset();
      case '=' || '>':
        setMode(Mode.deckpam, key == '=');
      case '\\':
        break;
      case '(0' || '(B':
        g0 = charsets[key[1]]!;
      case ')0' || ')B':
        g1 = charsets[key[1]]!;
      case '#8':
        screenAlignment();
      default:
        ignore(Reason.unsupported);
        return;
    }
    sequences++;
  }

  void executeOsc() {
    if (osc.startsWith('0;') || osc.startsWith('2;')) {
      title = osc.substring(2);
      sequences++;
    } else {
      ignore(Reason.unsupported);
    }
  }

  void executeCsi(String finalByte) {
    final key = marker + intermediates + finalByte;
    final fields = parameters.isEmpty ? <String>[] : parameters.split(';');
    try {
      require(fields.length <= maxFields, Reason.invalid);
      final params = fields.map(fieldValue).toList();
      final allowed = csiConditions[key];
      require(allowed == null || allowed.contains(parameter(params, 0)));
      if (key.length == 1 && wrapClearingCsi.contains(key)) {
        pendingWrap = false;
      }
      dispatchCsi(key, params);
    } on SequenceIgnored catch (ignoredSequence) {
      ignore(ignoredSequence.reason);
      return;
    }
    sequences++;
  }

  void dispatchCsi(String key, List<int> params) {
    switch (key) {
      case 'A':
        moveUp(amount(params));
      case 'B' || 'e':
        moveDown(amount(params));
      case 'C' || 'a':
        column = min(column + amount(params), width);
      case 'D':
        column = max(column - amount(params), 1);
      case 'E':
        moveDown(amount(params));
        column = 1;
      case 'F':
        moveUp(amount(params));
        column = 1;
      case 'G' || '`':
        column = min(amount(params), width);
      case 'H' || 'f':
        row = addressRow(amount(params));
        column = min(max(parameter(params, 1), 1), width);
      case 'd':
        row = addressRow(amount(params));
      case 'I':
        tabMove(amount(params));
      case 'Z':
        reverseTabMove(amount(params));
      case 'J':
        eraseInDisplay(parameter(params, 0));
      case 'K':
        eraseInLine(parameter(params, 0));
      case 'X':
        screen.erase(row, column, min(column + amount(params) - 1, width));
      case '@':
        screen.insertCells(
          row,
          column,
          min(amount(params), width - column + 1),
        );
      case 'P':
        screen.deleteCells(
          row,
          column,
          min(amount(params), width - column + 1),
        );
      case 'L':
        insertLines(amount(params));
      case 'M':
        deleteLines(amount(params));
      case 'S':
        scrollUp(amount(params));
      case 'T':
        scrollDown(amount(params));
      case 'b':
        repeatCharacter(amount(params));
      case 'g':
        clearTabStops(parameter(params, 0));
      case 'm':
        selectGraphicRendition(params);
      case 'h' || 'l':
        setAnsiModes(params, key == 'h');
      case '?h' || '?l':
        setDecModes(params, key == '?h');
      case ' q':
        cursorShape = amount(params);
      case 'r':
        setScrollRegion(params);
      case 's':
        saveCursor();
      case 'u':
        restoreCursor();
      case '!p':
        softReset();
      case 'n':
        deviceStatusReport(parameter(params, 0));
      case '?n':
        reply('^[[?${reportedRow()};$column;1R');
      case 'c':
        reply('^[[?1;2c');
      case '>c':
        reply('^[[>0;95;0c');
      case 't':
        reply('^[[8;$height;${width}t');
      case r'$p':
        requestAnsiMode(parameter(params, 0));
      case r'?$p':
        requestDecMode(parameter(params, 0));
      default:
        throw SequenceIgnored(Reason.unsupported);
    }
  }

  void moveUp(int count) {
    final limit = row >= top ? top : 1;
    row = max(row - count, limit);
  }

  void moveDown(int count) {
    final limit = row <= bottom ? bottom : height;
    row = min(row + count, limit);
  }

  void eraseInDisplay(int mode) {
    switch (mode) {
      case 0:
        screen.erase(row, column, width);
        screen.eraseRows(row + 1, height);
      case 1:
        screen.eraseRows(1, row - 1);
        screen.erase(row, 1, column);
      case 2:
        screen.clear();
      default:
        scrollback.clear();
    }
  }

  void eraseInLine(int mode) {
    final first = mode == 0 ? column : 1;
    final last = mode == 1 ? column : width;
    screen.erase(row, first, last);
  }

  void insertLines(int count) {
    if (row >= top && row <= bottom) {
      final lines = min(count, bottom - row + 1);
      for (var index = 0; index < lines; index++) {
        screen.scrollDown(row, bottom);
      }
      column = 1;
    }
  }

  void deleteLines(int count) {
    if (row >= top && row <= bottom) {
      final lines = min(count, bottom - row + 1);
      for (var index = 0; index < lines; index++) {
        screen.scrollUp(row, bottom);
      }
      column = 1;
    }
  }

  void scrollUp(int count) {
    final lines = min(count, bottom - top + 1);
    for (var index = 0; index < lines; index++) {
      scrollRegionUp();
    }
  }

  void scrollDown(int count) {
    final lines = min(count, bottom - top + 1);
    for (var index = 0; index < lines; index++) {
      scrollRegionDown();
    }
  }

  void repeatCharacter(int count) {
    if (lastChar case final char?) {
      for (var index = 0; index < count; index++) {
        write(char);
      }
    }
  }

  void clearTabStops(int mode) {
    if (mode == 0) {
      tabStops.remove(column);
    } else {
      tabStops.clear();
    }
  }

  void selectGraphicRendition(List<int> params) {
    final values = params.isEmpty ? [0] : params;
    var (:flags, :foreground, :background) = attributes;
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      if (value == 0) {
        flags = 0;
        foreground = null;
        background = null;
      } else if (sgrFlagsOn[value] case final flag?) {
        flags |= 1 << flag;
      } else if (sgrFlagsOff[value] case final cleared?) {
        for (final flag in cleared) {
          flags &= ~(1 << flag);
        }
      } else if (value >= 30 && value <= 37) {
        foreground = paletteColor(value - 30);
      } else if (value >= 90 && value <= 97) {
        foreground = paletteColor(value - 82);
      } else if (value >= 40 && value <= 47) {
        background = paletteColor(value - 40);
      } else if (value >= 100 && value <= 107) {
        background = paletteColor(value - 92);
      } else if (value == 39) {
        foreground = null;
      } else if (value == 49) {
        background = null;
      } else {
        require(value == 38 || value == 48);
        final (color, used) = extendedColor(values, index + 1);
        if (value == 38) {
          foreground = color;
        } else {
          background = color;
        }
        index += used;
      }
    }
    attributes = (flags: flags, foreground: foreground, background: background);
  }

  void setAnsiModes(List<int> params, bool enabled) {
    final values = params.isEmpty ? [0] : params;
    require(values.every(ansiModes.containsKey));
    for (final value in values) {
      setMode(ansiModes[value]!, enabled);
    }
  }

  void setDecModes(List<int> params, bool enabled) {
    final values = params.isEmpty ? [0] : params;
    require(values.every(decModeNumbers.contains));
    for (final value in values) {
      if (decModes.containsKey(value)) {
        setDecFlag(value, enabled);
      } else if (value == 1048) {
        if (enabled) {
          saveCursor();
        } else {
          restoreCursor();
        }
      } else {
        switchScreen(value, enabled);
      }
    }
  }

  void setDecFlag(int value, bool enabled) {
    if (value == 6 || (value == 7 && !enabled)) {
      pendingWrap = false;
    }
    setMode(decModes[value]!, enabled);
    if (value == 6) {
      home();
    }
  }

  void switchScreen(int value, bool enabled) {
    pendingWrap = false;
    if (enabled && display == Display.main) {
      if (value == 1049) {
        saveCursor();
      }
      display = Display.alternate;
      if (value == 1049) {
        screen.clear();
      }
    } else if (!enabled && display == Display.alternate) {
      if (value == 1047) {
        screen.clear();
      }
      display = Display.main;
      if (value == 1049) {
        restoreCursor();
      }
    }
  }

  void setScrollRegion(List<int> params) {
    final newTop = amount(params);
    final requested = parameter(params, 1);
    final newBottom = min(requested == 0 ? height : requested, height);
    require(newTop < newBottom, Reason.invalid);
    pendingWrap = false;
    top = newTop;
    bottom = newBottom;
    home();
  }

  void softReset() {
    pendingWrap = false;
    for (final mode in softResetModes) {
      setMode(mode, mode.initial);
    }
    top = 1;
    bottom = height;
    attributes = defaultAttributes;
    g0 = Charset.ascii;
    g1 = Charset.ascii;
    gl = 0;
    saved[display.index] = null;
  }

  void reply(String text) {
    replies++;
    emit('REPLY $text');
  }

  int reportedRow() {
    if (modes.contains(Mode.decom)) {
      return max(row - top + 1, 1);
    }
    return row;
  }

  void deviceStatusReport(int mode) {
    if (mode == 5) {
      reply('^[[0n');
    } else {
      reply('^[[${reportedRow()};${column}R');
    }
  }

  void requestAnsiMode(int mode) {
    final ansiMode = ansiModes[mode];
    final status = ansiMode == null ? 0 : modeState(modes.contains(ansiMode));
    reply('^[[$mode;$status\$y');
  }

  void requestDecMode(int mode) {
    var status = 0;
    if (decModes[mode] case final decMode?) {
      status = modeState(modes.contains(decMode));
    } else if (screenModes.contains(mode)) {
      status = modeState(display == Display.alternate);
    }
    reply('^[[?$mode;$status\$y');
  }

  String keyString(String name) {
    if (cursorKeys[name] case final suffix?) {
      return (modes.contains(Mode.decckm) ? '^[O' : '^[[') + suffix;
    }
    if (fixedKeys[name] case final sequence?) {
      return sequence;
    }
    final enter = modes.contains(Mode.lnm) ? '^M^J' : '^M';
    if (name == 'ENTER') {
      return enter;
    }
    if (name == 'KPENTER') {
      return modes.contains(Mode.deckpam) ? '^[OM' : enter;
    }
    final digit = int.parse(name.substring(2));
    if (modes.contains(Mode.deckpam)) {
      return '^[O${String.fromCharCode(0x70 + digit)}';
    }
    return '$digit';
  }

  void pressKey(String name) {
    emit('KEY $name ${keyString(name)}');
  }

  void paste(String text) {
    var sent = text.replaceAll('^', '^^');
    if (modes.contains(Mode.bracketed)) {
      sent = '^[[200~$sent^[[201~';
    }
    emit('PASTE $sent');
  }

  void screenOutput(String label) {
    final name = display == Display.alternate ? 'alt' : 'main';
    final header =
        '$label $name cursor $row,$column scrollback ${scrollback.length}';
    emit(pendingWrap ? '$header pending' : header);
    for (var number = 1; number <= height; number++) {
      emit('|${screen.text(number)}');
    }
  }

  void dump() {
    dumps++;
    screenOutput('DUMP $dumps');
  }

  List<String> changedModes() => [
    for (final mode in Mode.values)
      if (modes.contains(mode) != mode.initial)
        '${mode.label}=${modes.contains(mode) ? 'on' : 'off'}',
    if (g0 == Charset.lineDrawing) 'G0=graphics',
    if (g1 == Charset.lineDrawing) 'G1=graphics',
    if (gl == 1) 'GL=G1',
    if (cursorShape != 1) 'CURSOR=$cursorShape',
  ];

  List<String> attributeRuns() {
    final runs = <String>[];
    for (var number = 1; number <= height; number++) {
      final cells = screen.rows[number - 1];
      var start = 0;
      for (var next = 1; next <= width; next++) {
        if (next < width && cells[next].attributes == cells[start].attributes) {
          continue;
        }
        final run = cells[start].attributes;
        if (!run.isDefault) {
          runs.add('row $number col ${start + 1}-$next ${run.describe()}');
        }
        start = next;
      }
    }
    return runs;
  }

  void finish() {
    if (state != ParserState.ground) {
      ignore(Reason.canceled);
      state = ParserState.ground;
    }
    screenOutput('FINAL');
    emit('TITLE ${title == null ? 'none' : '"$title"'}');
    final changed = changedModes();
    emit('MODES ${changed.isEmpty ? 'default' : changed.join(' ')}');
    emit('REGION $top-$bottom');
    emit('TABS ${tabStops.isEmpty ? 'none' : tabStops.join(',')}');
    emit('SCROLLBACK ${scrollback.length}');
    final first = max(scrollback.length - scrollbackShown, 0);
    for (final text in scrollback.skip(first)) {
      emit('|$text');
    }
    final runs = attributeRuns();
    emit('ATTRS ${runs.length}');
    for (final run in runs) {
      emit(run);
    }
    emit('BELL $bells');
    emit('REPLIES $replies');
    emit('STATS bytes=$streamBytes printed=$printed sequences=$sequences');
    final counts = [
      for (final reason in Reason.values)
        '${reason.name}=${ignored[reason.index]}',
    ];
    final total = ignored.fold(0, (sum, count) => sum + count);
    emit('IGNORED $total ${counts.join(' ')}');
  }
}

void main() {
  final [width, height] = stdin
      .readLineSync()!
      .split(' ')
      .map(int.parse)
      .toList();
  final terminal = Terminal(width, height);
  while (true) {
    final line = stdin.readLineSync();
    if (line == null || line == '%%END') {
      break;
    }
    if (line == '%%DUMP') {
      terminal.dump();
    } else if (line.startsWith(keyPrefix)) {
      terminal.pressKey(line.substring(keyPrefix.length));
    } else if (line.startsWith(pastePrefix)) {
      terminal.paste(line.substring(pastePrefix.length));
    } else {
      decodeStream(line).forEach(terminal.receive);
    }
  }
  terminal.finish();
  stdout.write(terminal.output);
}
