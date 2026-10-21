import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.EnumSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.NavigableSet;
import java.util.Set;
import java.util.TreeSet;

import static java.util.Map.entry;

public class Main {
    static final char NUL = 0x00;
    static final char BEL = 0x07;
    static final char BS = 0x08;
    static final char HT = 0x09;
    static final char LF = 0x0A;
    static final char VT = 0x0B;
    static final char FF = 0x0C;
    static final char CR = 0x0D;
    static final char SO = 0x0E;
    static final char SI = 0x0F;
    static final char CAN = 0x18;
    static final char SUB = 0x1A;
    static final char ESC = 0x1B;
    static final Map<Character, Character> CARET_BYTES = Map.ofEntries(
            entry('@', NUL), entry('G', BEL), entry('H', BS), entry('I', HT), entry('J', LF),
            entry('K', VT), entry('L', FF), entry('M', CR), entry('N', SO), entry('O', SI),
            entry('X', CAN), entry('Z', SUB), entry('[', ESC), entry('^', '^'));

    static final int MAIN = 0;
    static final int ALTERNATE = 1;
    static final Map<Character, Charset> CHARSETS =
            Map.of('0', Charset.LINE_DRAWING, 'B', Charset.ASCII);

    static final int MAX_PARAMETER = 9999;
    static final int MAX_FIELDS = 16;
    static final int SCROLLBACK_LIMIT = 100;
    static final int SCROLLBACK_SHOWN = 5;
    static final int TAB_WIDTH = 8;

    static final Map<Character, Character> LINE_DRAWING_CHARS = Map.ofEntries(
            entry('`', '*'), entry('a', '#'), entry('j', '+'), entry('k', '+'), entry('l', '+'),
            entry('m', '+'), entry('n', '+'), entry('t', '+'), entry('u', '+'), entry('v', '+'),
            entry('w', '+'), entry('q', '-'), entry('x', '|'), entry('~', 'o'));
    static final List<String> COLOR_NAMES =
            List.of("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white");
    static final List<String> FLAG_NAMES =
            List.of("bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strike");
    static final Map<Integer, Integer> SGR_FLAGS_ON =
            Map.of(1, 0, 2, 1, 3, 2, 4, 3, 5, 4, 7, 5, 8, 6, 9, 7);
    static final Map<Integer, List<Integer>> SGR_FLAGS_OFF = Map.of(
            22, List.of(0, 1), 23, List.of(2), 24, List.of(3), 25, List.of(4),
            27, List.of(5), 28, List.of(6), 29, List.of(7));

    static final EnumSet<Mode> INITIAL_MODES = EnumSet.of(Mode.DECAWM, Mode.DECTCEM);
    static final List<Mode> SOFT_RESET_MODES =
            List.of(Mode.IRM, Mode.DECCKM, Mode.DECOM, Mode.DECAWM, Mode.DECTCEM, Mode.DECKPAM);
    static final Map<Integer, Mode> ANSI_MODES = Map.of(4, Mode.IRM, 20, Mode.LNM);
    static final Map<Integer, Mode> DEC_MODES = Map.of(
            1, Mode.DECCKM, 5, Mode.DECSCNM, 6, Mode.DECOM, 7, Mode.DECAWM, 25, Mode.DECTCEM,
            2004, Mode.BRACKETED);
    static final Set<Integer> SCREEN_MODES = Set.of(47, 1047, 1049);
    static final Set<Integer> DEC_MODE_NUMBERS =
            Set.of(1, 5, 6, 7, 25, 47, 1047, 1048, 1049, 2004);

    static final Map<String, Set<Integer>> CSI_CONDITIONS = Map.of(
            "J", Set.of(0, 1, 2, 3),
            "K", Set.of(0, 1, 2),
            "g", Set.of(0, 3),
            " q", Set.of(0, 1, 2, 3, 4, 5, 6),
            "n", Set.of(5, 6),
            "?n", Set.of(6),
            "c", Set.of(0),
            ">c", Set.of(0),
            "t", Set.of(18));
    static final String WRAP_CLEARING_CSI = "ABCDEFGHIJKLMPSTXZ`adef@";

    static final Map<String, Character> CURSOR_KEYS = Map.of(
            "UP", 'A', "DOWN", 'B', "RIGHT", 'C', "LEFT", 'D', "HOME", 'H', "END", 'F');
    static final Map<String, String> FIXED_KEYS = Map.ofEntries(
            entry("INSERT", "^[[2~"), entry("DELETE", "^[[3~"), entry("PAGEUP", "^[[5~"),
            entry("PAGEDOWN", "^[[6~"), entry("F1", "^[OP"), entry("F2", "^[OQ"),
            entry("F3", "^[OR"), entry("F4", "^[OS"), entry("F5", "^[[15~"),
            entry("F6", "^[[17~"), entry("F7", "^[[18~"), entry("F8", "^[[19~"),
            entry("F9", "^[[20~"), entry("F10", "^[[21~"), entry("F11", "^[[23~"),
            entry("F12", "^[[24~"), entry("TAB", "^I"), entry("BACKSPACE", "^?"),
            entry("ESCAPE", "^["));
    static final String KEY_PREFIX = "%%KEY ";
    static final String PASTE_PREFIX = "%%PASTE ";

    enum State {
        GROUND, ESCAPE, ESCAPE_INTERMEDIATE, CSI_ENTRY, CSI_PARAM, CSI_INTERMEDIATE, CSI_IGNORE,
        OSC_STRING
    }

    enum Reason { UNSUPPORTED, MALFORMED, CANCELED, INVALID }

    enum Charset { ASCII, LINE_DRAWING }

    enum Mode { IRM, LNM, DECCKM, DECSCNM, DECOM, DECAWM, DECTCEM, DECKPAM, BRACKETED }

    static final class SequenceIgnored extends RuntimeException {
        final Reason reason;

        SequenceIgnored(Reason reason) {
            this.reason = reason;
        }
    }

    record Attributes(int flags, String foreground, String background) {
        static final Attributes DEFAULT = new Attributes(0, null, null);

        boolean isDefault() {
            return equals(DEFAULT);
        }

        String describe() {
            List<String> parts = new ArrayList<>();
            for (int index = 0; index < FLAG_NAMES.size(); index++) {
                if ((flags >> index & 1) != 0) {
                    parts.add(FLAG_NAMES.get(index));
                }
            }
            if (foreground != null) {
                parts.add("fg=" + foreground);
            }
            if (background != null) {
                parts.add("bg=" + background);
            }
            return String.join(" ", parts);
        }
    }

    record Cell(char ch, Attributes attributes) {
        static final Cell BLANK = new Cell(' ', Attributes.DEFAULT);
    }

    record SavedCursor(
            int row, int column, Attributes attributes, boolean origin, Charset g0, Charset g1,
            int gl) {
        static final SavedCursor INITIAL =
                new SavedCursor(1, 1, Attributes.DEFAULT, false, Charset.ASCII, Charset.ASCII, 0);
    }

    record ExtendedColor(String name, int length) {
    }

    static void require(boolean condition, Reason reason) {
        if (!condition) {
            throw new SequenceIgnored(reason);
        }
    }

    static void require(boolean condition) {
        require(condition, Reason.UNSUPPORTED);
    }

    static boolean isIntermediate(char ch) {
        return ch >= 0x20 && ch <= 0x2F;
    }

    static boolean isParameter(char ch) {
        return (ch >= '0' && ch <= '9') || ch == ';';
    }

    static boolean isPrivateMarker(char ch) {
        return ch >= 0x3C && ch <= 0x3F;
    }

    static boolean isFinal(char ch) {
        return ch >= 0x40 && ch <= 0x7E;
    }

    static String decodeStream(String line) {
        StringBuilder data = new StringBuilder();
        for (int index = 0; index < line.length(); index++) {
            char ch = line.charAt(index);
            if (ch == '^') {
                index++;
                data.append(CARET_BYTES.get(line.charAt(index)));
            } else {
                data.append(ch);
            }
        }
        return data.toString();
    }

    static int fieldValue(String field) {
        int value = 0;
        for (char digit : field.toCharArray()) {
            value = Math.min(value * 10 + (digit - '0'), MAX_PARAMETER);
        }
        return value;
    }

    static int parameter(int[] params, int index) {
        return index < params.length ? params[index] : 0;
    }

    static int amount(int[] params) {
        return Math.max(parameter(params, 0), 1);
    }

    static String paletteColor(int number) {
        if (number < 8) {
            return COLOR_NAMES.get(number);
        }
        if (number < 16) {
            return "bright-" + COLOR_NAMES.get(number - 8);
        }
        return String.valueOf(number);
    }

    static String rgbColor(int red, int green, int blue) {
        return String.format("#%02x%02x%02x", red, green, blue);
    }

    static ExtendedColor extendedColor(int[] values, int start) {
        int rest = values.length - start;
        if (rest >= 2 && values[start] == 5 && values[start + 1] <= 255) {
            return new ExtendedColor(paletteColor(values[start + 1]), 2);
        }
        if (rest >= 4 && values[start] == 2
                && Arrays.stream(values, start + 1, start + 4).allMatch(value -> value <= 255)) {
            String color = rgbColor(values[start + 1], values[start + 2], values[start + 3]);
            return new ExtendedColor(color, 4);
        }
        throw new SequenceIgnored(Reason.UNSUPPORTED);
    }

    static int modeState(boolean enabled) {
        return enabled ? 1 : 2;
    }

    static String rowText(Cell[] cells) {
        StringBuilder text = new StringBuilder();
        for (Cell cell : cells) {
            text.append(cell.ch());
        }
        return text.toString().stripTrailing();
    }

    static final class Screen {
        final int width;
        final List<Cell[]> rows = new ArrayList<>();

        Screen(int width, int height) {
            this.width = width;
            for (int row = 0; row < height; row++) {
                rows.add(blankRow());
            }
        }

        Cell[] blankRow() {
            Cell[] cells = new Cell[width];
            Arrays.fill(cells, Cell.BLANK);
            return cells;
        }

        void clear() {
            rows.forEach(cells -> Arrays.fill(cells, Cell.BLANK));
        }

        void fill(char ch) {
            Cell cell = new Cell(ch, Attributes.DEFAULT);
            rows.forEach(cells -> Arrays.fill(cells, cell));
        }

        void put(int row, int column, Cell cell) {
            rows.get(row - 1)[column - 1] = cell;
        }

        void erase(int row, int first, int last) {
            Arrays.fill(rows.get(row - 1), first - 1, last, Cell.BLANK);
        }

        void eraseRows(int first, int last) {
            for (int row = first; row <= last; row++) {
                Arrays.fill(rows.get(row - 1), Cell.BLANK);
            }
        }

        Cell[] scrollUp(int top, int bottom) {
            Cell[] removed = rows.remove(top - 1);
            rows.add(bottom - 1, blankRow());
            return removed;
        }

        void scrollDown(int top, int bottom) {
            rows.remove(bottom - 1);
            rows.add(top - 1, blankRow());
        }

        void insertCells(int row, int column, int count) {
            Cell[] cells = rows.get(row - 1);
            int moved = width - column + 1 - count;
            System.arraycopy(cells, column - 1, cells, column - 1 + count, moved);
            Arrays.fill(cells, column - 1, column - 1 + count, Cell.BLANK);
        }

        void deleteCells(int row, int column, int count) {
            Cell[] cells = rows.get(row - 1);
            int moved = width - column + 1 - count;
            System.arraycopy(cells, column - 1 + count, cells, column - 1, moved);
            Arrays.fill(cells, width - count, width, Cell.BLANK);
        }

        String text(int row) {
            return rowText(rows.get(row - 1));
        }
    }

    static final class Terminal {
        private final int width;
        private final int height;
        private final StringBuilder output = new StringBuilder();
        private final int[] ignored = new int[Reason.values().length];
        private int streamBytes;
        private int printed;
        private int sequences;
        private int bells;
        private int replies;
        private int dumps;

        private Screen[] screens;
        private int display;
        private int row;
        private int column;
        private boolean pendingWrap;
        private Attributes attributes;
        private Charset g0;
        private Charset g1;
        private int gl;
        private EnumSet<Mode> modes;
        private int cursorShape;
        private int top;
        private int bottom;
        private NavigableSet<Integer> tabStops;
        private SavedCursor[] saved;
        private List<String> scrollback;
        private String title;
        private Character lastChar;
        private State state;
        private String marker;
        private final StringBuilder parameters = new StringBuilder();
        private final StringBuilder intermediates = new StringBuilder();
        private final StringBuilder osc = new StringBuilder();

        Terminal(int width, int height) {
            this.width = width;
            this.height = height;
            reset();
        }

        String output() {
            return output.toString();
        }

        private void reset() {
            screens = new Screen[] {new Screen(width, height), new Screen(width, height)};
            display = MAIN;
            row = 1;
            column = 1;
            pendingWrap = false;
            attributes = Attributes.DEFAULT;
            g0 = Charset.ASCII;
            g1 = Charset.ASCII;
            gl = 0;
            modes = EnumSet.copyOf(INITIAL_MODES);
            cursorShape = 1;
            top = 1;
            bottom = height;
            tabStops = new TreeSet<>();
            for (int stop = TAB_WIDTH + 1; stop <= width; stop += TAB_WIDTH) {
                tabStops.add(stop);
            }
            saved = new SavedCursor[2];
            scrollback = new ArrayList<>();
            title = null;
            lastChar = null;
            state = State.GROUND;
            clearSequence();
        }

        private void clearSequence() {
            marker = "";
            parameters.setLength(0);
            intermediates.setLength(0);
            osc.setLength(0);
        }

        private void emit(String line) {
            output.append(line).append('\n');
        }

        private void ignore(Reason reason) {
            ignored[reason.ordinal()]++;
        }

        private void setMode(Mode mode, boolean enabled) {
            if (enabled) {
                modes.add(mode);
            } else {
                modes.remove(mode);
            }
        }

        private Screen screen() {
            return screens[display];
        }

        void receive(char ch) {
            streamBytes++;
            if (ch < 0x20) {
                receiveControl(ch);
                return;
            }
            switch (state) {
                case GROUND -> printChar(ch);
                case ESCAPE, ESCAPE_INTERMEDIATE -> escapeByte(ch);
                case OSC_STRING -> osc.append(ch);
                case CSI_IGNORE -> {
                    if (isFinal(ch)) {
                        ignore(Reason.MALFORMED);
                        state = State.GROUND;
                    }
                }
                case CSI_INTERMEDIATE -> csiIntermediateByte(ch);
                case CSI_ENTRY -> {
                    if (isPrivateMarker(ch)) {
                        marker = String.valueOf(ch);
                        state = State.CSI_PARAM;
                    } else {
                        csiParamByte(ch);
                    }
                }
                case CSI_PARAM -> csiParamByte(ch);
            }
        }

        private void receiveControl(char ch) {
            if (ch == ESC) {
                if (state == State.OSC_STRING) {
                    executeOsc();
                } else if (state != State.GROUND) {
                    ignore(Reason.CANCELED);
                }
                clearSequence();
                state = State.ESCAPE;
            } else if (ch == CAN || ch == SUB) {
                if (state != State.GROUND) {
                    ignore(Reason.CANCELED);
                    state = State.GROUND;
                }
            } else if (state == State.OSC_STRING) {
                if (ch == BEL) {
                    executeOsc();
                    state = State.GROUND;
                }
            } else {
                executeControl(ch);
            }
        }

        private void escapeByte(char ch) {
            if (isIntermediate(ch)) {
                intermediates.append(ch);
                state = State.ESCAPE_INTERMEDIATE;
            } else if (state == State.ESCAPE && ch == '[') {
                state = State.CSI_ENTRY;
            } else if (state == State.ESCAPE && ch == ']') {
                state = State.OSC_STRING;
            } else {
                executeEsc(intermediates.toString() + ch);
                state = State.GROUND;
            }
        }

        private void csiParamByte(char ch) {
            if (isParameter(ch)) {
                parameters.append(ch);
                state = State.CSI_PARAM;
            } else if (isIntermediate(ch)) {
                intermediates.append(ch);
                state = State.CSI_INTERMEDIATE;
            } else if (isFinal(ch)) {
                executeCsi(ch);
                state = State.GROUND;
            } else {
                state = State.CSI_IGNORE;
            }
        }

        private void csiIntermediateByte(char ch) {
            if (isIntermediate(ch)) {
                intermediates.append(ch);
            } else if (isFinal(ch)) {
                executeCsi(ch);
                state = State.GROUND;
            } else {
                state = State.CSI_IGNORE;
            }
        }

        private void executeControl(char ch) {
            switch (ch) {
                case BEL -> bells++;
                case BS -> {
                    pendingWrap = false;
                    column = Math.max(column - 1, 1);
                }
                case HT -> {
                    pendingWrap = false;
                    tabMove(1);
                }
                case LF, VT, FF -> {
                    pendingWrap = false;
                    lineFeed();
                    if (modes.contains(Mode.LNM)) {
                        column = 1;
                    }
                }
                case CR -> {
                    pendingWrap = false;
                    column = 1;
                }
                case SO -> gl = 1;
                case SI -> gl = 0;
            }
        }

        private void printChar(char ch) {
            Charset charset = gl == 1 ? g1 : g0;
            if (charset == Charset.LINE_DRAWING) {
                ch = LINE_DRAWING_CHARS.getOrDefault(ch, ch);
            }
            write(ch);
        }

        private void write(char ch) {
            printed++;
            lastChar = ch;
            if (pendingWrap) {
                pendingWrap = false;
                column = 1;
                lineFeed();
            }
            Screen screen = screen();
            if (modes.contains(Mode.IRM)) {
                screen.insertCells(row, column, 1);
            }
            screen.put(row, column, new Cell(ch, attributes));
            if (column < width) {
                column++;
            } else if (modes.contains(Mode.DECAWM)) {
                pendingWrap = true;
            }
        }

        private void scrollRegionUp() {
            Cell[] removed = screen().scrollUp(top, bottom);
            if (display == MAIN && top == 1) {
                scrollback.add(rowText(removed));
                if (scrollback.size() > SCROLLBACK_LIMIT) {
                    scrollback.removeFirst();
                }
            }
        }

        private void scrollRegionDown() {
            screen().scrollDown(top, bottom);
        }

        private void lineFeed() {
            if (row == bottom) {
                scrollRegionUp();
            } else if (row < height) {
                row++;
            }
        }

        private void reverseLineFeed() {
            if (row == top) {
                scrollRegionDown();
            } else if (row > 1) {
                row--;
            }
        }

        private void tabMove(int count) {
            while (count > 0 && column < width) {
                Integer later = tabStops.higher(column);
                column = later != null ? later : width;
                count--;
            }
        }

        private void reverseTabMove(int count) {
            while (count > 0 && column > 1) {
                Integer earlier = tabStops.lower(column);
                column = earlier != null ? earlier : 1;
                count--;
            }
        }

        private int addressRow(int value) {
            if (modes.contains(Mode.DECOM)) {
                return Math.min(top + value - 1, bottom);
            }
            return Math.min(value, height);
        }

        private void home() {
            row = addressRow(1);
            column = 1;
        }

        private void saveCursor() {
            saved[display] = new SavedCursor(
                    row, column, attributes, modes.contains(Mode.DECOM), g0, g1, gl);
        }

        private void restoreCursor() {
            pendingWrap = false;
            SavedCursor cursor = saved[display] != null ? saved[display] : SavedCursor.INITIAL;
            row = cursor.row();
            column = cursor.column();
            attributes = cursor.attributes();
            setMode(Mode.DECOM, cursor.origin());
            g0 = cursor.g0();
            g1 = cursor.g1();
            gl = cursor.gl();
        }

        private void screenAlignment() {
            pendingWrap = false;
            screen().fill('E');
            top = 1;
            bottom = height;
            setMode(Mode.DECOM, false);
            row = 1;
            column = 1;
        }

        private void executeEsc(String key) {
            switch (key) {
                case "7" -> saveCursor();
                case "8" -> restoreCursor();
                case "D" -> {
                    pendingWrap = false;
                    lineFeed();
                }
                case "E" -> {
                    pendingWrap = false;
                    column = 1;
                    lineFeed();
                }
                case "M" -> {
                    pendingWrap = false;
                    reverseLineFeed();
                }
                case "H" -> tabStops.add(column);
                case "c" -> reset();
                case "=", ">" -> setMode(Mode.DECKPAM, key.equals("="));
                case "\\" -> {
                }
                case "(0", "(B" -> g0 = CHARSETS.get(key.charAt(1));
                case ")0", ")B" -> g1 = CHARSETS.get(key.charAt(1));
                case "#8" -> screenAlignment();
                default -> {
                    ignore(Reason.UNSUPPORTED);
                    return;
                }
            }
            sequences++;
        }

        private void executeOsc() {
            String text = osc.toString();
            if (text.startsWith("0;") || text.startsWith("2;")) {
                title = text.substring(2);
                sequences++;
            } else {
                ignore(Reason.UNSUPPORTED);
            }
        }

        private void executeCsi(char finalByte) {
            String key = marker + intermediates + finalByte;
            String text = parameters.toString();
            String[] fields = text.isEmpty() ? new String[0] : text.split(";", -1);
            try {
                require(fields.length <= MAX_FIELDS, Reason.INVALID);
                int[] params = Arrays.stream(fields).mapToInt(Main::fieldValue).toArray();
                Set<Integer> allowed = CSI_CONDITIONS.get(key);
                require(allowed == null || allowed.contains(parameter(params, 0)));
                if (key.length() == 1 && WRAP_CLEARING_CSI.contains(key)) {
                    pendingWrap = false;
                }
                dispatchCsi(key, params);
            } catch (SequenceIgnored sequence) {
                ignore(sequence.reason);
                return;
            }
            sequences++;
        }

        private void dispatchCsi(String key, int[] params) {
            switch (key) {
                case "A" -> moveUp(amount(params));
                case "B", "e" -> moveDown(amount(params));
                case "C", "a" -> column = Math.min(column + amount(params), width);
                case "D" -> column = Math.max(column - amount(params), 1);
                case "E" -> {
                    moveDown(amount(params));
                    column = 1;
                }
                case "F" -> {
                    moveUp(amount(params));
                    column = 1;
                }
                case "G", "`" -> column = Math.min(amount(params), width);
                case "H", "f" -> {
                    row = addressRow(amount(params));
                    column = Math.min(Math.max(parameter(params, 1), 1), width);
                }
                case "d" -> row = addressRow(amount(params));
                case "I" -> tabMove(amount(params));
                case "Z" -> reverseTabMove(amount(params));
                case "J" -> eraseInDisplay(parameter(params, 0));
                case "K" -> eraseInLine(parameter(params, 0));
                case "X" -> eraseCharacters(amount(params));
                case "@" -> insertCharacters(amount(params));
                case "P" -> deleteCharacters(amount(params));
                case "L" -> insertLines(amount(params));
                case "M" -> deleteLines(amount(params));
                case "S" -> scrollUp(amount(params));
                case "T" -> scrollDown(amount(params));
                case "b" -> repeatCharacter(amount(params));
                case "g" -> clearTabStops(parameter(params, 0));
                case "m" -> selectGraphicRendition(params);
                case "h", "l" -> setAnsiModes(params, key.equals("h"));
                case "?h", "?l" -> setDecModes(params, key.equals("?h"));
                case " q" -> cursorShape = amount(params);
                case "r" -> setScrollRegion(params);
                case "s" -> saveCursor();
                case "u" -> restoreCursor();
                case "!p" -> softReset();
                case "n" -> deviceStatusReport(parameter(params, 0));
                case "?n" -> reply("^[[?" + reportedRow() + ";" + column + ";1R");
                case "c" -> reply("^[[?1;2c");
                case ">c" -> reply("^[[>0;95;0c");
                case "t" -> reply("^[[8;" + height + ";" + width + "t");
                case "$p" -> requestAnsiMode(parameter(params, 0));
                case "?$p" -> requestDecMode(parameter(params, 0));
                default -> throw new SequenceIgnored(Reason.UNSUPPORTED);
            }
        }

        private void moveUp(int count) {
            int limit = row >= top ? top : 1;
            row = Math.max(row - count, limit);
        }

        private void moveDown(int count) {
            int limit = row <= bottom ? bottom : height;
            row = Math.min(row + count, limit);
        }

        private void eraseInDisplay(int mode) {
            Screen screen = screen();
            switch (mode) {
                case 0 -> {
                    screen.erase(row, column, width);
                    screen.eraseRows(row + 1, height);
                }
                case 1 -> {
                    screen.eraseRows(1, row - 1);
                    screen.erase(row, 1, column);
                }
                case 2 -> screen.clear();
                default -> scrollback.clear();
            }
        }

        private void eraseInLine(int mode) {
            int first = mode == 0 ? column : 1;
            int last = mode == 1 ? column : width;
            screen().erase(row, first, last);
        }

        private void eraseCharacters(int count) {
            screen().erase(row, column, Math.min(column + count - 1, width));
        }

        private void insertCharacters(int count) {
            screen().insertCells(row, column, Math.min(count, width - column + 1));
        }

        private void deleteCharacters(int count) {
            screen().deleteCells(row, column, Math.min(count, width - column + 1));
        }

        private void insertLines(int count) {
            if (row >= top && row <= bottom) {
                int lines = Math.min(count, bottom - row + 1);
                for (int index = 0; index < lines; index++) {
                    screen().scrollDown(row, bottom);
                }
                column = 1;
            }
        }

        private void deleteLines(int count) {
            if (row >= top && row <= bottom) {
                int lines = Math.min(count, bottom - row + 1);
                for (int index = 0; index < lines; index++) {
                    screen().scrollUp(row, bottom);
                }
                column = 1;
            }
        }

        private void scrollUp(int count) {
            int lines = Math.min(count, bottom - top + 1);
            for (int index = 0; index < lines; index++) {
                scrollRegionUp();
            }
        }

        private void scrollDown(int count) {
            int lines = Math.min(count, bottom - top + 1);
            for (int index = 0; index < lines; index++) {
                scrollRegionDown();
            }
        }

        private void repeatCharacter(int count) {
            if (lastChar != null) {
                for (int index = 0; index < count; index++) {
                    write(lastChar);
                }
            }
        }

        private void clearTabStops(int mode) {
            if (mode == 0) {
                tabStops.remove(column);
            } else {
                tabStops.clear();
            }
        }

        private void selectGraphicRendition(int[] params) {
            int[] values = params.length == 0 ? new int[] {0} : params;
            int flags = attributes.flags();
            String foreground = attributes.foreground();
            String background = attributes.background();
            for (int index = 0; index < values.length; index++) {
                int value = values[index];
                if (value == 0) {
                    flags = 0;
                    foreground = null;
                    background = null;
                } else if (SGR_FLAGS_ON.containsKey(value)) {
                    flags |= 1 << SGR_FLAGS_ON.get(value);
                } else if (SGR_FLAGS_OFF.containsKey(value)) {
                    for (int flag : SGR_FLAGS_OFF.get(value)) {
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
                    ExtendedColor color = extendedColor(values, index + 1);
                    if (value == 38) {
                        foreground = color.name();
                    } else {
                        background = color.name();
                    }
                    index += color.length();
                }
            }
            attributes = new Attributes(flags, foreground, background);
        }

        private void setAnsiModes(int[] params, boolean enabled) {
            int[] values = params.length == 0 ? new int[] {0} : params;
            require(Arrays.stream(values).allMatch(ANSI_MODES::containsKey));
            for (int value : values) {
                setMode(ANSI_MODES.get(value), enabled);
            }
        }

        private void setDecModes(int[] params, boolean enabled) {
            int[] values = params.length == 0 ? new int[] {0} : params;
            require(Arrays.stream(values).allMatch(DEC_MODE_NUMBERS::contains));
            for (int value : values) {
                if (DEC_MODES.containsKey(value)) {
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

        private void setDecFlag(int value, boolean enabled) {
            if (value == 6 || (value == 7 && !enabled)) {
                pendingWrap = false;
            }
            setMode(DEC_MODES.get(value), enabled);
            if (value == 6) {
                home();
            }
        }

        private void switchScreen(int value, boolean enabled) {
            pendingWrap = false;
            if (enabled && display == MAIN) {
                if (value == 1049) {
                    saveCursor();
                }
                display = ALTERNATE;
                if (value == 1049) {
                    screen().clear();
                }
            } else if (!enabled && display == ALTERNATE) {
                if (value == 1047) {
                    screen().clear();
                }
                display = MAIN;
                if (value == 1049) {
                    restoreCursor();
                }
            }
        }

        private void setScrollRegion(int[] params) {
            int newTop = amount(params);
            int requested = parameter(params, 1);
            int newBottom = Math.min(requested == 0 ? height : requested, height);
            require(newTop < newBottom, Reason.INVALID);
            pendingWrap = false;
            top = newTop;
            bottom = newBottom;
            home();
        }

        private void softReset() {
            pendingWrap = false;
            for (Mode mode : SOFT_RESET_MODES) {
                setMode(mode, INITIAL_MODES.contains(mode));
            }
            top = 1;
            bottom = height;
            attributes = Attributes.DEFAULT;
            g0 = Charset.ASCII;
            g1 = Charset.ASCII;
            gl = 0;
            saved[display] = null;
        }

        private void reply(String text) {
            replies++;
            emit("REPLY " + text);
        }

        private int reportedRow() {
            if (modes.contains(Mode.DECOM)) {
                return Math.max(row - top + 1, 1);
            }
            return row;
        }

        private void deviceStatusReport(int mode) {
            if (mode == 5) {
                reply("^[[0n");
            } else {
                reply("^[[" + reportedRow() + ";" + column + "R");
            }
        }

        private void requestAnsiMode(int mode) {
            Mode ansiMode = ANSI_MODES.get(mode);
            int status = ansiMode != null ? modeState(modes.contains(ansiMode)) : 0;
            reply("^[[" + mode + ";" + status + "$y");
        }

        private void requestDecMode(int mode) {
            int status = 0;
            if (DEC_MODES.containsKey(mode)) {
                status = modeState(modes.contains(DEC_MODES.get(mode)));
            } else if (SCREEN_MODES.contains(mode)) {
                status = modeState(display == ALTERNATE);
            }
            reply("^[[?" + mode + ";" + status + "$y");
        }

        private String keyString(String name) {
            Character cursorKey = CURSOR_KEYS.get(name);
            if (cursorKey != null) {
                return (modes.contains(Mode.DECCKM) ? "^[O" : "^[[") + cursorKey;
            }
            String fixedKey = FIXED_KEYS.get(name);
            if (fixedKey != null) {
                return fixedKey;
            }
            String enter = modes.contains(Mode.LNM) ? "^M^J" : "^M";
            if (name.equals("ENTER")) {
                return enter;
            }
            if (name.equals("KPENTER")) {
                return modes.contains(Mode.DECKPAM) ? "^[OM" : enter;
            }
            int digit = Integer.parseInt(name.substring(2));
            if (modes.contains(Mode.DECKPAM)) {
                return "^[O" + (char) (0x70 + digit);
            }
            return String.valueOf(digit);
        }

        void pressKey(String name) {
            emit("KEY " + name + " " + keyString(name));
        }

        void paste(String text) {
            String sent = text.replace("^", "^^");
            if (modes.contains(Mode.BRACKETED)) {
                sent = "^[[200~" + sent + "^[[201~";
            }
            emit("PASTE " + sent);
        }

        private void screenOutput(String label) {
            String name = display == ALTERNATE ? "alt" : "main";
            String header = label + " " + name + " cursor " + row + "," + column + " scrollback "
                    + scrollback.size();
            emit(pendingWrap ? header + " pending" : header);
            Screen screen = screen();
            for (int number = 1; number <= height; number++) {
                emit("|" + screen.text(number));
            }
        }

        void dump() {
            dumps++;
            screenOutput("DUMP " + dumps);
        }

        private List<String> changedModes() {
            List<String> items = new ArrayList<>();
            for (Mode mode : Mode.values()) {
                boolean enabled = modes.contains(mode);
                if (enabled != INITIAL_MODES.contains(mode)) {
                    items.add(mode + (enabled ? "=on" : "=off"));
                }
            }
            if (g0 == Charset.LINE_DRAWING) {
                items.add("G0=graphics");
            }
            if (g1 == Charset.LINE_DRAWING) {
                items.add("G1=graphics");
            }
            if (gl == 1) {
                items.add("GL=G1");
            }
            if (cursorShape != 1) {
                items.add("CURSOR=" + cursorShape);
            }
            return items;
        }

        private List<String> attributeRuns() {
            List<String> runs = new ArrayList<>();
            List<Cell[]> rows = screen().rows;
            for (int number = 1; number <= height; number++) {
                Cell[] cells = rows.get(number - 1);
                int start = 0;
                for (int next = 1; next <= width; next++) {
                    Attributes run = cells[start].attributes();
                    if (next < width && cells[next].attributes().equals(run)) {
                        continue;
                    }
                    if (!run.isDefault()) {
                        runs.add("row " + number + " col " + (start + 1) + "-" + next + " "
                                + run.describe());
                    }
                    start = next;
                }
            }
            return runs;
        }

        void finish() {
            if (state != State.GROUND) {
                ignore(Reason.CANCELED);
                state = State.GROUND;
            }
            screenOutput("FINAL");
            emit("TITLE " + (title == null ? "none" : "\"" + title + "\""));
            List<String> changed = changedModes();
            emit("MODES " + (changed.isEmpty() ? "default" : String.join(" ", changed)));
            emit("REGION " + top + "-" + bottom);
            List<String> stops = tabStops.stream().map(String::valueOf).toList();
            emit("TABS " + (stops.isEmpty() ? "none" : String.join(",", stops)));
            emit("SCROLLBACK " + scrollback.size());
            int first = Math.max(scrollback.size() - SCROLLBACK_SHOWN, 0);
            for (String text : scrollback.subList(first, scrollback.size())) {
                emit("|" + text);
            }
            List<String> runs = attributeRuns();
            emit("ATTRS " + runs.size());
            runs.forEach(this::emit);
            emit("BELL " + bells);
            emit("REPLIES " + replies);
            emit("STATS bytes=" + streamBytes + " printed=" + printed + " sequences=" + sequences);
            List<String> counts = Arrays.stream(Reason.values())
                    .map(reason -> reason.name().toLowerCase(Locale.ROOT) + "="
                            + ignored[reason.ordinal()])
                    .toList();
            emit("IGNORED " + Arrays.stream(ignored).sum() + " " + String.join(" ", counts));
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        String[] size = reader.readLine().split(" ");
        Terminal terminal = new Terminal(Integer.parseInt(size[0]), Integer.parseInt(size[1]));
        String line;
        while ((line = reader.readLine()) != null && !line.equals("%%END")) {
            if (line.equals("%%DUMP")) {
                terminal.dump();
            } else if (line.startsWith(KEY_PREFIX)) {
                terminal.pressKey(line.substring(KEY_PREFIX.length()));
            } else if (line.startsWith(PASTE_PREFIX)) {
                terminal.paste(line.substring(PASTE_PREFIX.length()));
            } else {
                for (char ch : decodeStream(line).toCharArray()) {
                    terminal.receive(ch);
                }
            }
        }
        terminal.finish();
        System.out.print(terminal.output());
    }
}
