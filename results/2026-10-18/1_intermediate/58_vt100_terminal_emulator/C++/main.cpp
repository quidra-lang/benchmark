#include <algorithm>
#include <array>
#include <cstdio>
#include <deque>
#include <functional>
#include <iostream>
#include <iterator>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

const std::map<char, char> CARET_BYTES = {
    {'@', 0x00}, {'G', 0x07}, {'H', 0x08}, {'I', 0x09}, {'J', 0x0A}, {'K', 0x0B}, {'L', 0x0C},
    {'M', 0x0D}, {'N', 0x0E}, {'O', 0x0F}, {'X', 0x18}, {'Z', 0x1A}, {'[', 0x1B}, {'^', 0x5E},
};
constexpr char BEL = 0x07;
constexpr char BS = 0x08;
constexpr char HT = 0x09;
constexpr char LF = 0x0A;
constexpr char VT = 0x0B;
constexpr char FF = 0x0C;
constexpr char CR = 0x0D;
constexpr char SO = 0x0E;
constexpr char SI = 0x0F;
constexpr char CAN = 0x18;
constexpr char SUB = 0x1A;
constexpr char ESC = 0x1B;

enum class State {
    Ground,
    Escape,
    EscapeIntermediate,
    CsiEntry,
    CsiParam,
    CsiIntermediate,
    CsiIgnore,
    OscString,
};

enum Reason { UNSUPPORTED, MALFORMED, CANCELED, INVALID, REASON_COUNT };
const std::array<std::string, REASON_COUNT> REASON_NAMES = {
    "unsupported", "malformed", "canceled", "invalid",
};

enum Display { MAIN, ALTERNATE };
enum class Charset { Ascii, LineDrawing };

constexpr int MAX_PARAMETER = 9999;
constexpr std::size_t MAX_FIELDS = 16;
constexpr std::size_t SCROLLBACK_LIMIT = 100;
constexpr std::size_t SCROLLBACK_SHOWN = 5;
constexpr int TAB_WIDTH = 8;

const std::map<char, char> LINE_DRAWING_CHARS = {
    {'`', '*'}, {'a', '#'}, {'j', '+'}, {'k', '+'}, {'l', '+'}, {'m', '+'}, {'n', '+'},
    {'t', '+'}, {'u', '+'}, {'v', '+'}, {'w', '+'}, {'q', '-'}, {'x', '|'}, {'~', 'o'},
};
const std::array<std::string, 8> COLOR_NAMES = {
    "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
};
const std::array<std::string, 8> FLAG_NAMES = {
    "bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strike",
};
enum Flag : unsigned {
    BOLD = 1 << 0,
    DIM = 1 << 1,
    ITALIC = 1 << 2,
    UNDERLINE = 1 << 3,
    BLINK = 1 << 4,
    REVERSE = 1 << 5,
    HIDDEN = 1 << 6,
    STRIKE = 1 << 7,
};
const std::map<int, unsigned> SGR_FLAGS_ON = {
    {1, BOLD}, {2, DIM}, {3, ITALIC}, {4, UNDERLINE},
    {5, BLINK}, {7, REVERSE}, {8, HIDDEN}, {9, STRIKE},
};
const std::map<int, unsigned> SGR_FLAGS_OFF = {
    {22, BOLD | DIM}, {23, ITALIC}, {24, UNDERLINE}, {25, BLINK},
    {27, REVERSE}, {28, HIDDEN}, {29, STRIKE},
};

enum Mode { IRM, LNM, DECCKM, DECSCNM, DECOM, DECAWM, DECTCEM, DECKPAM, BRACKETED, MODE_COUNT };
const std::array<std::string, MODE_COUNT> MODE_NAMES = {
    "IRM", "LNM", "DECCKM", "DECSCNM", "DECOM", "DECAWM", "DECTCEM", "DECKPAM", "BRACKETED",
};
const std::array<bool, MODE_COUNT> INITIAL_MODES = {
    false, false, false, false, false, true, true, false, false,
};
const std::array<Mode, 6> SOFT_RESET_MODES = {IRM, DECCKM, DECOM, DECAWM, DECTCEM, DECKPAM};
const std::map<int, Mode> ANSI_MODES = {{4, IRM}, {20, LNM}};
const std::map<int, Mode> DEC_MODES = {
    {1, DECCKM}, {5, DECSCNM}, {6, DECOM}, {7, DECAWM}, {25, DECTCEM}, {2004, BRACKETED},
};
const std::set<int> SCREEN_MODES = {47, 1047, 1049};
const std::set<int> DEC_MODE_NUMBERS = {1, 5, 6, 7, 25, 47, 1047, 1048, 1049, 2004};

const std::map<std::string, std::set<int>> CSI_CONDITIONS = {
    {"J", {0, 1, 2, 3}},
    {"K", {0, 1, 2}},
    {"g", {0, 3}},
    {" q", {0, 1, 2, 3, 4, 5, 6}},
    {"n", {5, 6}},
    {"?n", {6}},
    {"c", {0}},
    {">c", {0}},
    {"t", {18}},
};
const std::string WRAP_CLEARING_CSI = "ABCDEFGHIJKLMPSTXZ`adef@";

const std::map<std::string, char> CURSOR_KEYS = {
    {"UP", 'A'}, {"DOWN", 'B'}, {"RIGHT", 'C'}, {"LEFT", 'D'}, {"HOME", 'H'}, {"END", 'F'},
};
const std::map<std::string, std::string> FIXED_KEYS = {
    {"INSERT", "^[[2~"}, {"DELETE", "^[[3~"}, {"PAGEUP", "^[[5~"}, {"PAGEDOWN", "^[[6~"},
    {"F1", "^[OP"}, {"F2", "^[OQ"}, {"F3", "^[OR"}, {"F4", "^[OS"},
    {"F5", "^[[15~"}, {"F6", "^[[17~"}, {"F7", "^[[18~"}, {"F8", "^[[19~"},
    {"F9", "^[[20~"}, {"F10", "^[[21~"}, {"F11", "^[[23~"}, {"F12", "^[[24~"},
    {"TAB", "^I"}, {"BACKSPACE", "^?"}, {"ESCAPE", "^["},
};

using Params = std::vector<int>;

struct SequenceIgnored {
    Reason reason;
};

void require(bool condition, Reason reason = UNSUPPORTED) {
    if (!condition) {
        throw SequenceIgnored{reason};
    }
}

bool isIntermediate(char byte) { return byte >= 0x20 && byte <= 0x2F; }

bool isParameter(char byte) { return (byte >= '0' && byte <= '9') || byte == ';'; }

bool isPrivateMarker(char byte) { return byte >= 0x3C && byte <= 0x3F; }

bool isFinal(char byte) { return byte >= 0x40 && byte <= 0x7E; }

std::string join(const std::vector<std::string> &items, const std::string &separator) {
    std::string result;
    for (std::size_t index = 0; index < items.size(); ++index) {
        if (index > 0) {
            result += separator;
        }
        result += items[index];
    }
    return result;
}

std::string decodeStream(const std::string &line) {
    std::string data;
    for (std::size_t index = 0; index < line.size(); ++index) {
        if (line[index] == '^') {
            data += CARET_BYTES.at(line[++index]);
        } else {
            data += line[index];
        }
    }
    return data;
}

Params parseParameters(const std::string &text) {
    Params params;
    if (text.empty()) {
        return params;
    }
    params.push_back(0);
    for (char ch : text) {
        if (ch == ';') {
            params.push_back(0);
        } else {
            params.back() = std::min(params.back() * 10 + (ch - '0'), MAX_PARAMETER);
        }
    }
    return params;
}

int parameter(const Params &params, std::size_t index) {
    return index < params.size() ? params[index] : 0;
}

int amount(const Params &params) { return std::max(parameter(params, 0), 1); }

std::string paletteColor(int number) {
    if (number < 8) {
        return COLOR_NAMES[number];
    }
    if (number < 16) {
        return "bright-" + COLOR_NAMES[number - 8];
    }
    return std::to_string(number);
}

std::string rgbColor(int red, int green, int blue) {
    char buffer[8];
    std::snprintf(buffer, sizeof buffer, "#%02x%02x%02x", red, green, blue);
    return buffer;
}

std::pair<std::string, std::size_t> extendedColor(const Params &values, std::size_t start) {
    std::size_t rest = values.size() - start;
    if (rest >= 2 && values[start] == 5 && values[start + 1] <= 255) {
        return {paletteColor(values[start + 1]), 2};
    }
    if (rest >= 4 && values[start] == 2 &&
        std::max({values[start + 1], values[start + 2], values[start + 3]}) <= 255) {
        return {rgbColor(values[start + 1], values[start + 2], values[start + 3]), 4};
    }
    throw SequenceIgnored{UNSUPPORTED};
}

int modeState(bool enabled) { return enabled ? 1 : 2; }

struct Attributes {
    unsigned flags = 0;
    std::optional<std::string> foreground;
    std::optional<std::string> background;

    bool operator==(const Attributes &other) const {
        return flags == other.flags && foreground == other.foreground &&
               background == other.background;
    }

    bool isDefault() const { return flags == 0 && !foreground && !background; }

    std::string describe() const {
        std::vector<std::string> parts;
        for (std::size_t index = 0; index < FLAG_NAMES.size(); ++index) {
            if (flags >> index & 1) {
                parts.push_back(FLAG_NAMES[index]);
            }
        }
        if (foreground) {
            parts.push_back("fg=" + *foreground);
        }
        if (background) {
            parts.push_back("bg=" + *background);
        }
        return join(parts, " ");
    }
};

struct Cell {
    char ch = ' ';
    Attributes attributes;
};

using Row = std::vector<Cell>;

std::string rowText(const Row &cells) {
    std::string text;
    for (const Cell &cell : cells) {
        text += cell.ch;
    }
    return text.substr(0, text.find_last_not_of(' ') + 1);
}

struct SavedCursor {
    int row = 1;
    int column = 1;
    Attributes attributes;
    bool origin = false;
    Charset g0 = Charset::Ascii;
    Charset g1 = Charset::Ascii;
    int gl = 0;
};

struct Screen {
    int width;
    int height;
    std::vector<Row> rows;

    Screen(int width, int height) : width(width), height(height) { clear(); }

    Row blankRow() const { return Row(width); }

    void clear() { rows.assign(height, blankRow()); }

    void fill(char ch) { rows.assign(height, Row(width, Cell{ch, Attributes{}})); }

    void put(int row, int column, const Cell &cell) { rows[row - 1][column - 1] = cell; }

    void erase(int row, int first, int last) {
        Row &cells = rows[row - 1];
        std::fill(cells.begin() + first - 1, cells.begin() + last, Cell{});
    }

    void eraseRows(int first, int last) {
        for (int row = first; row <= last; ++row) {
            rows[row - 1] = blankRow();
        }
    }

    Row scrollUp(int top, int bottom) {
        Row removed = std::move(rows[top - 1]);
        rows.erase(rows.begin() + top - 1);
        rows.insert(rows.begin() + bottom - 1, blankRow());
        return removed;
    }

    void scrollDown(int top, int bottom) {
        rows.erase(rows.begin() + bottom - 1);
        rows.insert(rows.begin() + top - 1, blankRow());
    }

    void insertCells(int row, int column, int count) {
        Row &cells = rows[row - 1];
        cells.insert(cells.begin() + column - 1, count, Cell{});
        cells.resize(width);
    }

    void deleteCells(int row, int column, int count) {
        Row &cells = rows[row - 1];
        cells.erase(cells.begin() + column - 1, cells.begin() + column - 1 + count);
        cells.resize(width);
    }

    std::string text(int row) const { return rowText(rows[row - 1]); }
};

class Terminal {
public:
    Terminal(int width, int height) : width(width), height(height) { reset(); }

    void receive(char byte) {
        ++streamBytes;
        if (byte < 0x20) {
            receiveControl(byte);
        } else if (state == State::Ground) {
            printChar(byte);
        } else if (state == State::Escape || state == State::EscapeIntermediate) {
            escapeByte(byte);
        } else if (state == State::OscString) {
            osc += byte;
        } else if (state == State::CsiIgnore) {
            if (isFinal(byte)) {
                ++ignored[MALFORMED];
                state = State::Ground;
            }
        } else if (state == State::CsiIntermediate) {
            csiIntermediateByte(byte);
        } else if (state == State::CsiEntry && isPrivateMarker(byte)) {
            marker = std::string(1, byte);
            state = State::CsiParam;
        } else {
            csiParamByte(byte);
        }
    }

    void pressKey(const std::string &name) { emit("KEY " + name + " " + keyString(name)); }

    void paste(const std::string &text) {
        std::string sent;
        for (char ch : text) {
            sent += ch == '^' ? "^^" : std::string(1, ch);
        }
        if (modes[BRACKETED]) {
            sent = "^[[200~" + sent + "^[[201~";
        }
        emit("PASTE " + sent);
    }

    void dump() {
        ++dumps;
        screenOutput("DUMP " + std::to_string(dumps));
    }

    void finish() {
        if (state != State::Ground) {
            ++ignored[CANCELED];
        }
        screenOutput("FINAL");
        emit("TITLE " + (title ? "\"" + *title + "\"" : std::string("none")));
        std::vector<std::string> changed = changedModes();
        emit("MODES " + (changed.empty() ? std::string("default") : join(changed, " ")));
        emit("REGION " + std::to_string(top) + "-" + std::to_string(bottom));
        std::vector<std::string> stops;
        for (int stop : tabStops) {
            stops.push_back(std::to_string(stop));
        }
        emit("TABS " + (stops.empty() ? std::string("none") : join(stops, ",")));
        emit("SCROLLBACK " + std::to_string(scrollback.size()));
        std::size_t shown = std::min(scrollback.size(), SCROLLBACK_SHOWN);
        for (std::size_t index = scrollback.size() - shown; index < scrollback.size(); ++index) {
            emit("|" + scrollback[index]);
        }
        std::vector<std::string> runs = attributeRuns();
        emit("ATTRS " + std::to_string(runs.size()));
        for (const std::string &run : runs) {
            emit(run);
        }
        emit("BELL " + std::to_string(bells));
        emit("REPLIES " + std::to_string(replies));
        emit("STATS bytes=" + std::to_string(streamBytes) + " printed=" + std::to_string(printed) +
             " sequences=" + std::to_string(sequences));
        std::string counts;
        for (int reason = 0; reason < REASON_COUNT; ++reason) {
            counts += " " + REASON_NAMES[reason] + "=" + std::to_string(ignored[reason]);
        }
        int total = std::accumulate(ignored.begin(), ignored.end(), 0);
        emit("IGNORED " + std::to_string(total) + counts);
    }

private:
    using Handler = std::function<void(Terminal &, const Params &)>;
    static const std::map<std::string, Handler> CSI_HANDLERS;

    int width;
    int height;
    int streamBytes = 0;
    int printed = 0;
    int sequences = 0;
    int bells = 0;
    int replies = 0;
    int dumps = 0;
    std::array<int, REASON_COUNT> ignored{};

    std::vector<Screen> screens;
    Display display = MAIN;
    int row = 1;
    int column = 1;
    bool pendingWrap = false;
    Attributes attributes;
    Charset g0 = Charset::Ascii;
    Charset g1 = Charset::Ascii;
    int gl = 0;
    std::array<bool, MODE_COUNT> modes = INITIAL_MODES;
    int cursorShape = 1;
    int top = 1;
    int bottom = 1;
    std::set<int> tabStops;
    std::array<std::optional<SavedCursor>, 2> saved;
    std::deque<std::string> scrollback;
    std::optional<std::string> title;
    std::optional<char> lastChar;
    State state = State::Ground;
    std::string marker;
    std::string parameters;
    std::string intermediates;
    std::string osc;

    void reset() {
        screens.assign(2, Screen(width, height));
        display = MAIN;
        row = 1;
        column = 1;
        pendingWrap = false;
        attributes = Attributes{};
        g0 = Charset::Ascii;
        g1 = Charset::Ascii;
        gl = 0;
        modes = INITIAL_MODES;
        cursorShape = 1;
        top = 1;
        bottom = height;
        tabStops.clear();
        for (int stop = TAB_WIDTH + 1; stop <= width; stop += TAB_WIDTH) {
            tabStops.insert(stop);
        }
        saved.fill(std::nullopt);
        scrollback.clear();
        title.reset();
        lastChar.reset();
        state = State::Ground;
        clearSequence();
    }

    void clearSequence() {
        marker.clear();
        parameters.clear();
        intermediates.clear();
        osc.clear();
    }

    void emit(const std::string &line) { std::cout << line << '\n'; }

    Screen &screen() { return screens[display]; }

    void receiveControl(char byte) {
        if (byte == ESC) {
            if (state == State::OscString) {
                executeOsc();
            } else if (state != State::Ground) {
                ++ignored[CANCELED];
            }
            clearSequence();
            state = State::Escape;
        } else if (byte == CAN || byte == SUB) {
            if (state != State::Ground) {
                ++ignored[CANCELED];
                state = State::Ground;
            }
        } else if (state == State::OscString) {
            if (byte == BEL) {
                executeOsc();
                state = State::Ground;
            }
        } else {
            executeControl(byte);
        }
    }

    void escapeByte(char byte) {
        if (isIntermediate(byte)) {
            intermediates += byte;
            state = State::EscapeIntermediate;
        } else if (state == State::Escape && byte == '[') {
            state = State::CsiEntry;
        } else if (state == State::Escape && byte == ']') {
            state = State::OscString;
        } else {
            executeEsc(intermediates + byte);
            state = State::Ground;
        }
    }

    void csiParamByte(char byte) {
        if (isParameter(byte)) {
            parameters += byte;
            state = State::CsiParam;
        } else if (isIntermediate(byte)) {
            intermediates += byte;
            state = State::CsiIntermediate;
        } else if (isFinal(byte)) {
            executeCsi(byte);
            state = State::Ground;
        } else {
            state = State::CsiIgnore;
        }
    }

    void csiIntermediateByte(char byte) {
        if (isIntermediate(byte)) {
            intermediates += byte;
        } else if (isFinal(byte)) {
            executeCsi(byte);
            state = State::Ground;
        } else {
            state = State::CsiIgnore;
        }
    }

    void executeControl(char byte) {
        switch (byte) {
        case BEL:
            ++bells;
            break;
        case BS:
            pendingWrap = false;
            column = std::max(column - 1, 1);
            break;
        case HT:
            pendingWrap = false;
            tabMove(1);
            break;
        case LF:
        case VT:
        case FF:
            pendingWrap = false;
            lineFeed();
            if (modes[LNM]) {
                column = 1;
            }
            break;
        case CR:
            pendingWrap = false;
            column = 1;
            break;
        case SO:
            gl = 1;
            break;
        case SI:
            gl = 0;
            break;
        }
    }

    void printChar(char ch) {
        Charset charset = gl == 1 ? g1 : g0;
        if (charset == Charset::LineDrawing) {
            auto replacement = LINE_DRAWING_CHARS.find(ch);
            if (replacement != LINE_DRAWING_CHARS.end()) {
                ch = replacement->second;
            }
        }
        write(ch);
    }

    void write(char ch) {
        ++printed;
        lastChar = ch;
        if (pendingWrap) {
            pendingWrap = false;
            column = 1;
            lineFeed();
        }
        if (modes[IRM]) {
            screen().insertCells(row, column, 1);
        }
        screen().put(row, column, Cell{ch, attributes});
        if (column < width) {
            ++column;
        } else if (modes[DECAWM]) {
            pendingWrap = true;
        }
    }

    void scrollRegionUp() {
        Row removed = screen().scrollUp(top, bottom);
        if (display == MAIN && top == 1) {
            scrollback.push_back(rowText(removed));
            if (scrollback.size() > SCROLLBACK_LIMIT) {
                scrollback.pop_front();
            }
        }
    }

    void scrollRegionDown() { screen().scrollDown(top, bottom); }

    void lineFeed() {
        if (row == bottom) {
            scrollRegionUp();
        } else if (row < height) {
            ++row;
        }
    }

    void reverseLineFeed() {
        if (row == top) {
            scrollRegionDown();
        } else if (row > 1) {
            --row;
        }
    }

    void tabMove(int count) {
        for (; count > 0 && column < width; --count) {
            auto later = tabStops.upper_bound(column);
            column = later != tabStops.end() ? *later : width;
        }
    }

    void reverseTabMove(int count) {
        for (; count > 0 && column > 1; --count) {
            auto notEarlier = tabStops.lower_bound(column);
            column = notEarlier != tabStops.begin() ? *std::prev(notEarlier) : 1;
        }
    }

    int addressRow(int value) const {
        if (modes[DECOM]) {
            return std::min(top + value - 1, bottom);
        }
        return std::min(value, height);
    }

    void home() {
        row = addressRow(1);
        column = 1;
    }

    void saveCursor() {
        saved[display] = SavedCursor{row, column, attributes, modes[DECOM], g0, g1, gl};
    }

    void restoreCursor() {
        pendingWrap = false;
        SavedCursor record = saved[display].value_or(SavedCursor{});
        row = record.row;
        column = record.column;
        attributes = record.attributes;
        modes[DECOM] = record.origin;
        g0 = record.g0;
        g1 = record.g1;
        gl = record.gl;
    }

    void screenAlignment() {
        pendingWrap = false;
        screen().fill('E');
        top = 1;
        bottom = height;
        modes[DECOM] = false;
        row = 1;
        column = 1;
    }

    void executeEsc(const std::string &key) {
        if (key == "7") {
            saveCursor();
        } else if (key == "8") {
            restoreCursor();
        } else if (key == "D") {
            pendingWrap = false;
            lineFeed();
        } else if (key == "E") {
            pendingWrap = false;
            column = 1;
            lineFeed();
        } else if (key == "M") {
            pendingWrap = false;
            reverseLineFeed();
        } else if (key == "H") {
            tabStops.insert(column);
        } else if (key == "c") {
            reset();
        } else if (key == "=" || key == ">") {
            modes[DECKPAM] = key == "=";
        } else if (key == "\\") {
        } else if (key == "(0" || key == "(B") {
            g0 = key[1] == '0' ? Charset::LineDrawing : Charset::Ascii;
        } else if (key == ")0" || key == ")B") {
            g1 = key[1] == '0' ? Charset::LineDrawing : Charset::Ascii;
        } else if (key == "#8") {
            screenAlignment();
        } else {
            ++ignored[UNSUPPORTED];
            return;
        }
        ++sequences;
    }

    void executeOsc() {
        if (osc.rfind("0;", 0) == 0 || osc.rfind("2;", 0) == 0) {
            title = osc.substr(2);
            ++sequences;
        } else {
            ++ignored[UNSUPPORTED];
        }
    }

    void executeCsi(char finalByte) {
        std::string key = marker + intermediates + finalByte;
        Params params = parseParameters(parameters);
        try {
            require(params.size() <= MAX_FIELDS, INVALID);
            auto handler = CSI_HANDLERS.find(key);
            require(handler != CSI_HANDLERS.end());
            auto condition = CSI_CONDITIONS.find(key);
            if (condition != CSI_CONDITIONS.end()) {
                require(condition->second.count(parameter(params, 0)) > 0);
            }
            if (key.size() == 1 && WRAP_CLEARING_CSI.find(key) != std::string::npos) {
                pendingWrap = false;
            }
            handler->second(*this, params);
        } catch (const SequenceIgnored &ignoredSequence) {
            ++ignored[ignoredSequence.reason];
            return;
        }
        ++sequences;
    }

    void moveUp(int count) {
        int limit = row >= top ? top : 1;
        row = std::max(row - count, limit);
    }

    void moveDown(int count) {
        int limit = row <= bottom ? bottom : height;
        row = std::min(row + count, limit);
    }

    void cursorUp(const Params &params) { moveUp(amount(params)); }

    void cursorDown(const Params &params) { moveDown(amount(params)); }

    void cursorForward(const Params &params) { column = std::min(column + amount(params), width); }

    void cursorBackward(const Params &params) { column = std::max(column - amount(params), 1); }

    void cursorNextLine(const Params &params) {
        moveDown(amount(params));
        column = 1;
    }

    void cursorPreviousLine(const Params &params) {
        moveUp(amount(params));
        column = 1;
    }

    void cursorColumn(const Params &params) { column = std::min(amount(params), width); }

    void cursorPosition(const Params &params) {
        row = addressRow(amount(params));
        column = std::min(std::max(parameter(params, 1), 1), width);
    }

    void cursorRow(const Params &params) { row = addressRow(amount(params)); }

    void forwardTabulation(const Params &params) { tabMove(amount(params)); }

    void backwardTabulation(const Params &params) { reverseTabMove(amount(params)); }

    void eraseInDisplay(const Params &params) {
        int mode = parameter(params, 0);
        if (mode == 0) {
            screen().erase(row, column, width);
            screen().eraseRows(row + 1, height);
        } else if (mode == 1) {
            screen().eraseRows(1, row - 1);
            screen().erase(row, 1, column);
        } else if (mode == 2) {
            screen().clear();
        } else {
            scrollback.clear();
        }
    }

    void eraseInLine(const Params &params) {
        int mode = parameter(params, 0);
        int first = mode == 1 || mode == 2 ? 1 : column;
        int last = mode == 1 ? column : width;
        screen().erase(row, first, last);
    }

    void eraseCharacters(const Params &params) {
        int last = std::min(column + amount(params) - 1, width);
        screen().erase(row, column, last);
    }

    void insertCharacters(const Params &params) {
        int count = std::min(amount(params), width - column + 1);
        screen().insertCells(row, column, count);
    }

    void deleteCharacters(const Params &params) {
        int count = std::min(amount(params), width - column + 1);
        screen().deleteCells(row, column, count);
    }

    void insertLines(const Params &params) {
        if (row >= top && row <= bottom) {
            int count = std::min(amount(params), bottom - row + 1);
            for (int index = 0; index < count; ++index) {
                screen().scrollDown(row, bottom);
            }
            column = 1;
        }
    }

    void deleteLines(const Params &params) {
        if (row >= top && row <= bottom) {
            int count = std::min(amount(params), bottom - row + 1);
            for (int index = 0; index < count; ++index) {
                screen().scrollUp(row, bottom);
            }
            column = 1;
        }
    }

    void scrollUp(const Params &params) {
        int count = std::min(amount(params), bottom - top + 1);
        for (int index = 0; index < count; ++index) {
            scrollRegionUp();
        }
    }

    void scrollDown(const Params &params) {
        int count = std::min(amount(params), bottom - top + 1);
        for (int index = 0; index < count; ++index) {
            scrollRegionDown();
        }
    }

    void repeatCharacter(const Params &params) {
        if (lastChar) {
            int count = amount(params);
            for (int index = 0; index < count; ++index) {
                write(*lastChar);
            }
        }
    }

    void clearTabStops(const Params &params) {
        if (parameter(params, 0) == 0) {
            tabStops.erase(column);
        } else {
            tabStops.clear();
        }
    }

    void selectGraphicRendition(const Params &params) {
        Params values = params.empty() ? Params{0} : params;
        Attributes updated = attributes;
        for (std::size_t index = 0; index < values.size(); ++index) {
            int value = values[index];
            if (value == 0) {
                updated = Attributes{};
            } else if (SGR_FLAGS_ON.count(value) > 0) {
                updated.flags |= SGR_FLAGS_ON.at(value);
            } else if (SGR_FLAGS_OFF.count(value) > 0) {
                updated.flags &= ~SGR_FLAGS_OFF.at(value);
            } else if (value >= 30 && value <= 37) {
                updated.foreground = paletteColor(value - 30);
            } else if (value >= 90 && value <= 97) {
                updated.foreground = paletteColor(value - 82);
            } else if (value >= 40 && value <= 47) {
                updated.background = paletteColor(value - 40);
            } else if (value >= 100 && value <= 107) {
                updated.background = paletteColor(value - 92);
            } else if (value == 39) {
                updated.foreground.reset();
            } else if (value == 49) {
                updated.background.reset();
            } else {
                require(value == 38 || value == 48);
                auto [color, used] = extendedColor(values, index + 1);
                if (value == 38) {
                    updated.foreground = color;
                } else {
                    updated.background = color;
                }
                index += used;
            }
        }
        attributes = updated;
    }

    void setAnsiModes(const Params &params, bool enabled) {
        Params values = params.empty() ? Params{0} : params;
        require(std::all_of(values.begin(), values.end(),
                            [](int value) { return ANSI_MODES.count(value) > 0; }));
        for (int value : values) {
            modes[ANSI_MODES.at(value)] = enabled;
        }
    }

    void setDecModes(const Params &params, bool enabled) {
        Params values = params.empty() ? Params{0} : params;
        require(std::all_of(values.begin(), values.end(),
                            [](int value) { return DEC_MODE_NUMBERS.count(value) > 0; }));
        for (int value : values) {
            if (DEC_MODES.count(value) > 0) {
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
        modes[DEC_MODES.at(value)] = enabled;
        if (value == 6) {
            home();
        }
    }

    void switchScreen(int value, bool enabled) {
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

    void setCursorShape(const Params &params) { cursorShape = amount(params); }

    void setScrollRegion(const Params &params) {
        int newTop = amount(params);
        int newBottom = std::min(parameter(params, 1) == 0 ? height : parameter(params, 1), height);
        require(newTop < newBottom, INVALID);
        pendingWrap = false;
        top = newTop;
        bottom = newBottom;
        home();
    }

    void softReset(const Params &) {
        pendingWrap = false;
        for (Mode mode : SOFT_RESET_MODES) {
            modes[mode] = INITIAL_MODES[mode];
        }
        top = 1;
        bottom = height;
        attributes = Attributes{};
        g0 = Charset::Ascii;
        g1 = Charset::Ascii;
        gl = 0;
        saved[display].reset();
    }

    void reply(const std::string &text) {
        ++replies;
        emit("REPLY " + text);
    }

    int reportedRow() const {
        if (modes[DECOM]) {
            return std::max(row - top + 1, 1);
        }
        return row;
    }

    void deviceStatusReport(const Params &params) {
        if (parameter(params, 0) == 5) {
            reply("^[[0n");
        } else {
            reply("^[[" + std::to_string(reportedRow()) + ";" + std::to_string(column) + "R");
        }
    }

    void extendedCursorReport(const Params &) {
        reply("^[[?" + std::to_string(reportedRow()) + ";" + std::to_string(column) + ";1R");
    }

    void deviceAttributes(const Params &) { reply("^[[?1;2c"); }

    void secondaryDeviceAttributes(const Params &) { reply("^[[>0;95;0c"); }

    void windowReport(const Params &) {
        reply("^[[8;" + std::to_string(height) + ";" + std::to_string(width) + "t");
    }

    void requestAnsiMode(const Params &params) {
        int mode = parameter(params, 0);
        auto ansiMode = ANSI_MODES.find(mode);
        int status = ansiMode != ANSI_MODES.end() ? modeState(modes[ansiMode->second]) : 0;
        reply("^[[" + std::to_string(mode) + ";" + std::to_string(status) + "$y");
    }

    void requestDecMode(const Params &params) {
        int mode = parameter(params, 0);
        int status = 0;
        if (DEC_MODES.count(mode) > 0) {
            status = modeState(modes[DEC_MODES.at(mode)]);
        } else if (SCREEN_MODES.count(mode) > 0) {
            status = modeState(display == ALTERNATE);
        }
        reply("^[[?" + std::to_string(mode) + ";" + std::to_string(status) + "$y");
    }

    std::string keyString(const std::string &name) const {
        auto cursorKey = CURSOR_KEYS.find(name);
        if (cursorKey != CURSOR_KEYS.end()) {
            return std::string(modes[DECCKM] ? "^[O" : "^[[") + cursorKey->second;
        }
        auto fixedKey = FIXED_KEYS.find(name);
        if (fixedKey != FIXED_KEYS.end()) {
            return fixedKey->second;
        }
        std::string enter = modes[LNM] ? "^M^J" : "^M";
        if (name == "ENTER") {
            return enter;
        }
        if (name == "KPENTER") {
            return modes[DECKPAM] ? "^[OM" : enter;
        }
        int digit = name[2] - '0';
        if (modes[DECKPAM]) {
            return std::string("^[O") + static_cast<char>(0x70 + digit);
        }
        return std::to_string(digit);
    }

    void screenOutput(const std::string &label) {
        std::string header = label + (display == ALTERNATE ? " alt" : " main") + " cursor " +
                             std::to_string(row) + "," + std::to_string(column) + " scrollback " +
                             std::to_string(scrollback.size());
        if (pendingWrap) {
            header += " pending";
        }
        emit(header);
        for (int number = 1; number <= height; ++number) {
            emit("|" + screen().text(number));
        }
    }

    std::vector<std::string> changedModes() const {
        std::vector<std::string> items;
        for (int mode = 0; mode < MODE_COUNT; ++mode) {
            if (modes[mode] != INITIAL_MODES[mode]) {
                items.push_back(MODE_NAMES[mode] + (modes[mode] ? "=on" : "=off"));
            }
        }
        if (g0 == Charset::LineDrawing) {
            items.push_back("G0=graphics");
        }
        if (g1 == Charset::LineDrawing) {
            items.push_back("G1=graphics");
        }
        if (gl == 1) {
            items.push_back("GL=G1");
        }
        if (cursorShape != 1) {
            items.push_back("CURSOR=" + std::to_string(cursorShape));
        }
        return items;
    }

    std::vector<std::string> attributeRuns() {
        std::vector<std::string> runs;
        for (int number = 1; number <= height; ++number) {
            const Row &cells = screen().rows[number - 1];
            int start = 0;
            for (int next = 1; next <= width; ++next) {
                if (next < width && cells[next].attributes == cells[start].attributes) {
                    continue;
                }
                const Attributes &run = cells[start].attributes;
                if (!run.isDefault()) {
                    runs.push_back("row " + std::to_string(number) + " col " +
                                   std::to_string(start + 1) + "-" + std::to_string(next) + " " +
                                   run.describe());
                }
                start = next;
            }
        }
        return runs;
    }
};

const std::map<std::string, Terminal::Handler> Terminal::CSI_HANDLERS = {
    {"A", &Terminal::cursorUp},
    {"B", &Terminal::cursorDown},
    {"e", &Terminal::cursorDown},
    {"C", &Terminal::cursorForward},
    {"a", &Terminal::cursorForward},
    {"D", &Terminal::cursorBackward},
    {"E", &Terminal::cursorNextLine},
    {"F", &Terminal::cursorPreviousLine},
    {"G", &Terminal::cursorColumn},
    {"`", &Terminal::cursorColumn},
    {"H", &Terminal::cursorPosition},
    {"f", &Terminal::cursorPosition},
    {"d", &Terminal::cursorRow},
    {"I", &Terminal::forwardTabulation},
    {"Z", &Terminal::backwardTabulation},
    {"J", &Terminal::eraseInDisplay},
    {"K", &Terminal::eraseInLine},
    {"X", &Terminal::eraseCharacters},
    {"@", &Terminal::insertCharacters},
    {"P", &Terminal::deleteCharacters},
    {"L", &Terminal::insertLines},
    {"M", &Terminal::deleteLines},
    {"S", &Terminal::scrollUp},
    {"T", &Terminal::scrollDown},
    {"b", &Terminal::repeatCharacter},
    {"g", &Terminal::clearTabStops},
    {"m", &Terminal::selectGraphicRendition},
    {"h", [](Terminal &terminal, const Params &params) { terminal.setAnsiModes(params, true); }},
    {"l", [](Terminal &terminal, const Params &params) { terminal.setAnsiModes(params, false); }},
    {"?h", [](Terminal &terminal, const Params &params) { terminal.setDecModes(params, true); }},
    {"?l", [](Terminal &terminal, const Params &params) { terminal.setDecModes(params, false); }},
    {" q", &Terminal::setCursorShape},
    {"r", &Terminal::setScrollRegion},
    {"s", [](Terminal &terminal, const Params &) { terminal.saveCursor(); }},
    {"u", [](Terminal &terminal, const Params &) { terminal.restoreCursor(); }},
    {"!p", &Terminal::softReset},
    {"n", &Terminal::deviceStatusReport},
    {"?n", &Terminal::extendedCursorReport},
    {"c", &Terminal::deviceAttributes},
    {">c", &Terminal::secondaryDeviceAttributes},
    {"t", &Terminal::windowReport},
    {"$p", &Terminal::requestAnsiMode},
    {"?$p", &Terminal::requestDecMode},
};

int main() {
    std::ios::sync_with_stdio(false);
    std::string line;
    std::getline(std::cin, line);
    int width = 0;
    int height = 0;
    std::istringstream(line) >> width >> height;
    Terminal terminal(width, height);
    const std::string keyPrefix = "%%KEY ";
    const std::string pastePrefix = "%%PASTE ";
    while (std::getline(std::cin, line) && line != "%%END") {
        if (line == "%%DUMP") {
            terminal.dump();
        } else if (line.rfind(keyPrefix, 0) == 0) {
            terminal.pressKey(line.substr(keyPrefix.size()));
        } else if (line.rfind(pastePrefix, 0) == 0) {
            terminal.paste(line.substr(pastePrefix.size()));
        } else {
            for (char byte : decodeStream(line)) {
                terminal.receive(byte);
            }
        }
    }
    terminal.finish();
    return 0;
}
