import sys


CARET_BYTES = {
    "@": 0x00, "G": 0x07, "H": 0x08, "I": 0x09, "J": 0x0A, "K": 0x0B, "L": 0x0C,
    "M": 0x0D, "N": 0x0E, "O": 0x0F, "X": 0x18, "Z": 0x1A, "[": 0x1B, "^": 0x5E,
}
BEL = 0x07
BS = 0x08
HT = 0x09
LF = 0x0A
VT = 0x0B
FF = 0x0C
CR = 0x0D
SO = 0x0E
SI = 0x0F
CAN = 0x18
SUB = 0x1A
ESC = 0x1B

GROUND = "ground"
ESCAPE = "escape"
ESCAPE_INTERMEDIATE = "escape intermediate"
CSI_ENTRY = "csi entry"
CSI_PARAM = "csi param"
CSI_INTERMEDIATE = "csi intermediate"
CSI_IGNORE = "csi ignore"
OSC_STRING = "osc string"

UNSUPPORTED = "unsupported"
MALFORMED = "malformed"
CANCELED = "canceled"
INVALID = "invalid"

MAIN = 0
ALTERNATE = 1
ASCII = "ascii"
LINE_DRAWING = "line drawing"
CHARSETS = {"0": LINE_DRAWING, "B": ASCII}

MAX_PARAMETER = 9999
MAX_FIELDS = 16
SCROLLBACK_LIMIT = 100
SCROLLBACK_SHOWN = 5
TAB_WIDTH = 8

LINE_DRAWING_CHARS = {
    "`": "*", "a": "#", "j": "+", "k": "+", "l": "+", "m": "+", "n": "+",
    "t": "+", "u": "+", "v": "+", "w": "+", "q": "-", "x": "|", "~": "o",
}
COLOR_NAMES = ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")
FLAG_NAMES = ("bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strike")
SGR_FLAGS_ON = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 7: 5, 8: 6, 9: 7}
SGR_FLAGS_OFF = {22: (0, 1), 23: (2,), 24: (3,), 25: (4,), 27: (5,), 28: (6,), 29: (7,)}

INITIAL_MODES = {
    "IRM": False, "LNM": False, "DECCKM": False, "DECSCNM": False, "DECOM": False,
    "DECAWM": True, "DECTCEM": True, "DECKPAM": False, "BRACKETED": False,
}
SOFT_RESET_MODES = ("IRM", "DECCKM", "DECOM", "DECAWM", "DECTCEM", "DECKPAM")
ANSI_MODES = {4: "IRM", 20: "LNM"}
DEC_MODES = {1: "DECCKM", 5: "DECSCNM", 6: "DECOM", 7: "DECAWM", 25: "DECTCEM", 2004: "BRACKETED"}
SCREEN_MODES = (47, 1047, 1049)
DEC_MODE_NUMBERS = (1, 5, 6, 7, 25, 47, 1047, 1048, 1049, 2004)

CSI_CONDITIONS = {
    "J": (0, 1, 2, 3),
    "K": (0, 1, 2),
    "g": (0, 3),
    " q": (0, 1, 2, 3, 4, 5, 6),
    "n": (5, 6),
    "?n": (6,),
    "c": (0,),
    ">c": (0,),
    "t": (18,),
}
WRAP_CLEARING_CSI = set("ABCDEFGHIJKLMPSTXZ`adef@")

CURSOR_KEYS = {"UP": "A", "DOWN": "B", "RIGHT": "C", "LEFT": "D", "HOME": "H", "END": "F"}
FIXED_KEYS = {
    "INSERT": "^[[2~", "DELETE": "^[[3~", "PAGEUP": "^[[5~", "PAGEDOWN": "^[[6~",
    "F1": "^[OP", "F2": "^[OQ", "F3": "^[OR", "F4": "^[OS",
    "F5": "^[[15~", "F6": "^[[17~", "F7": "^[[18~", "F8": "^[[19~",
    "F9": "^[[20~", "F10": "^[[21~", "F11": "^[[23~", "F12": "^[[24~",
    "TAB": "^I", "BACKSPACE": "^?", "ESCAPE": "^[",
}


class SequenceIgnored(Exception):
    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


def require(condition, reason=UNSUPPORTED):
    if not condition:
        raise SequenceIgnored(reason)


def is_intermediate(byte):
    return 0x20 <= byte <= 0x2F


def is_parameter(byte):
    return 0x30 <= byte <= 0x39 or byte == 0x3B


def is_private_marker(byte):
    return 0x3C <= byte <= 0x3F


def is_final(byte):
    return 0x40 <= byte <= 0x7E


def decode_stream(line):
    data = []
    index = 0
    while index < len(line):
        if line[index] == "^":
            data.append(CARET_BYTES[line[index + 1]])
            index += 2
        else:
            data.append(ord(line[index]))
            index += 1
    return data


def field_value(field):
    value = 0
    for digit in field:
        value = min(value * 10 + int(digit), MAX_PARAMETER)
    return value


def parameter(params, index):
    return params[index] if index < len(params) else 0


def amount(params):
    return max(parameter(params, 0), 1)


def palette_color(number):
    if number < 8:
        return COLOR_NAMES[number]
    if number < 16:
        return "bright-" + COLOR_NAMES[number - 8]
    return str(number)


def rgb_color(red, green, blue):
    return f"#{red:02x}{green:02x}{blue:02x}"


def extended_color(values, start):
    rest = values[start:]
    if len(rest) >= 2 and rest[0] == 5 and rest[1] <= 255:
        return palette_color(rest[1]), 2
    if len(rest) >= 4 and rest[0] == 2 and max(rest[1:4]) <= 255:
        return rgb_color(rest[1], rest[2], rest[3]), 4
    raise SequenceIgnored(UNSUPPORTED)


def mode_state(enabled):
    return 1 if enabled else 2


def row_text(cells):
    return "".join(cell.char for cell in cells).rstrip(" ")


class Attributes:
    def __init__(self, flags=0, foreground=None, background=None):
        self.flags = flags
        self.foreground = foreground
        self.background = background

    def copy(self):
        return Attributes(self.flags, self.foreground, self.background)

    def __eq__(self, other):
        return (
            self.flags == other.flags
            and self.foreground == other.foreground
            and self.background == other.background
        )

    def is_default(self):
        return self.flags == 0 and self.foreground is None and self.background is None

    def describe(self):
        parts = [name for index, name in enumerate(FLAG_NAMES) if self.flags >> index & 1]
        if self.foreground is not None:
            parts.append("fg=" + self.foreground)
        if self.background is not None:
            parts.append("bg=" + self.background)
        return " ".join(parts)


DEFAULT_ATTRIBUTES = Attributes()


class Cell:
    def __init__(self, char, attributes):
        self.char = char
        self.attributes = attributes


BLANK_CELL = Cell(" ", DEFAULT_ATTRIBUTES)


class SavedCursor:
    def __init__(self, row, column, attributes, origin, g0, g1, gl):
        self.row = row
        self.column = column
        self.attributes = attributes
        self.origin = origin
        self.g0 = g0
        self.g1 = g1
        self.gl = gl


class Screen:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.rows = []
        self.clear()

    def blank_row(self):
        return [BLANK_CELL] * self.width

    def clear(self):
        self.rows = [self.blank_row() for _ in range(self.height)]

    def fill(self, char):
        cell = Cell(char, DEFAULT_ATTRIBUTES)
        self.rows = [[cell] * self.width for _ in range(self.height)]

    def put(self, row, column, cell):
        self.rows[row - 1][column - 1] = cell

    def erase(self, row, first, last):
        cells = self.rows[row - 1]
        for column in range(first, last + 1):
            cells[column - 1] = BLANK_CELL

    def erase_rows(self, first, last):
        for row in range(first, last + 1):
            self.rows[row - 1] = self.blank_row()

    def scroll_up(self, top, bottom):
        removed = self.rows.pop(top - 1)
        self.rows.insert(bottom - 1, self.blank_row())
        return removed

    def scroll_down(self, top, bottom):
        self.rows.pop(bottom - 1)
        self.rows.insert(top - 1, self.blank_row())

    def insert_cells(self, row, column, count):
        cells = self.rows[row - 1]
        cells[column - 1:column - 1] = [BLANK_CELL] * count
        del cells[self.width:]

    def delete_cells(self, row, column, count):
        cells = self.rows[row - 1]
        del cells[column - 1:column - 1 + count]
        cells.extend([BLANK_CELL] * count)

    def text(self, row):
        return row_text(self.rows[row - 1])


class Terminal:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.stream_bytes = 0
        self.printed = 0
        self.sequences = 0
        self.bells = 0
        self.replies = 0
        self.dumps = 0
        self.ignored = {UNSUPPORTED: 0, MALFORMED: 0, CANCELED: 0, INVALID: 0}
        self.output = []
        self.csi_handlers = {
            "A": self.cursor_up,
            "B": self.cursor_down,
            "e": self.cursor_down,
            "C": self.cursor_forward,
            "a": self.cursor_forward,
            "D": self.cursor_backward,
            "E": self.cursor_next_line,
            "F": self.cursor_previous_line,
            "G": self.cursor_column,
            "`": self.cursor_column,
            "H": self.cursor_position,
            "f": self.cursor_position,
            "d": self.cursor_row,
            "I": self.forward_tabulation,
            "Z": self.backward_tabulation,
            "J": self.erase_in_display,
            "K": self.erase_in_line,
            "X": self.erase_characters,
            "@": self.insert_characters,
            "P": self.delete_characters,
            "L": self.insert_lines,
            "M": self.delete_lines,
            "S": self.scroll_up,
            "T": self.scroll_down,
            "b": self.repeat_character,
            "g": self.clear_tab_stops,
            "m": self.select_graphic_rendition,
            "h": lambda params: self.set_ansi_modes(params, True),
            "l": lambda params: self.set_ansi_modes(params, False),
            "?h": lambda params: self.set_dec_modes(params, True),
            "?l": lambda params: self.set_dec_modes(params, False),
            " q": self.set_cursor_shape,
            "r": self.set_scroll_region,
            "s": lambda params: self.save_cursor(),
            "u": lambda params: self.restore_cursor(),
            "!p": self.soft_reset,
            "n": self.device_status_report,
            "?n": self.extended_cursor_report,
            "c": self.device_attributes,
            ">c": self.secondary_device_attributes,
            "t": self.window_report,
            "$p": self.request_ansi_mode,
            "?$p": self.request_dec_mode,
        }
        self.reset()

    def reset(self):
        self.screens = [Screen(self.width, self.height), Screen(self.width, self.height)]
        self.display = MAIN
        self.row = 1
        self.column = 1
        self.pending_wrap = False
        self.attributes = DEFAULT_ATTRIBUTES
        self.g0 = ASCII
        self.g1 = ASCII
        self.gl = "G0"
        self.modes = dict(INITIAL_MODES)
        self.cursor_shape = 1
        self.top = 1
        self.bottom = self.height
        self.tab_stops = set(range(TAB_WIDTH + 1, self.width + 1, TAB_WIDTH))
        self.saved = [None, None]
        self.scrollback = []
        self.title = None
        self.last_char = None
        self.state = GROUND
        self.clear_sequence()

    def clear_sequence(self):
        self.marker = ""
        self.parameters = ""
        self.intermediates = ""
        self.osc = ""

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def screen(self):
        return self.screens[self.display]

    def receive(self, byte):
        self.stream_bytes += 1
        if byte < 0x20:
            self.receive_control(byte)
        elif self.state == GROUND:
            self.print_char(chr(byte))
        elif self.state in (ESCAPE, ESCAPE_INTERMEDIATE):
            self.escape_byte(byte)
        elif self.state == OSC_STRING:
            self.osc += chr(byte)
        elif self.state == CSI_IGNORE:
            if is_final(byte):
                self.ignored[MALFORMED] += 1
                self.state = GROUND
        elif self.state == CSI_INTERMEDIATE:
            self.csi_intermediate_byte(byte)
        elif self.state == CSI_ENTRY and is_private_marker(byte):
            self.marker = chr(byte)
            self.state = CSI_PARAM
        else:
            self.csi_param_byte(byte)

    def receive_control(self, byte):
        if byte == ESC:
            if self.state == OSC_STRING:
                self.execute_osc()
            elif self.state != GROUND:
                self.ignored[CANCELED] += 1
            self.clear_sequence()
            self.state = ESCAPE
        elif byte in (CAN, SUB):
            if self.state != GROUND:
                self.ignored[CANCELED] += 1
                self.state = GROUND
        elif self.state == OSC_STRING:
            if byte == BEL:
                self.execute_osc()
                self.state = GROUND
        else:
            self.execute_control(byte)

    def escape_byte(self, byte):
        char = chr(byte)
        if is_intermediate(byte):
            self.intermediates += char
            self.state = ESCAPE_INTERMEDIATE
        elif self.state == ESCAPE and char == "[":
            self.state = CSI_ENTRY
        elif self.state == ESCAPE and char == "]":
            self.state = OSC_STRING
        else:
            self.execute_esc(self.intermediates + char)
            self.state = GROUND

    def csi_param_byte(self, byte):
        char = chr(byte)
        if is_parameter(byte):
            self.parameters += char
            self.state = CSI_PARAM
        elif is_intermediate(byte):
            self.intermediates += char
            self.state = CSI_INTERMEDIATE
        elif is_final(byte):
            self.execute_csi(char)
            self.state = GROUND
        else:
            self.state = CSI_IGNORE

    def csi_intermediate_byte(self, byte):
        char = chr(byte)
        if is_intermediate(byte):
            self.intermediates += char
        elif is_final(byte):
            self.execute_csi(char)
            self.state = GROUND
        else:
            self.state = CSI_IGNORE

    def execute_control(self, byte):
        if byte == BEL:
            self.bells += 1
        elif byte == BS:
            self.pending_wrap = False
            self.column = max(self.column - 1, 1)
        elif byte == HT:
            self.pending_wrap = False
            self.tab_move(1)
        elif byte in (LF, VT, FF):
            self.pending_wrap = False
            self.line_feed()
            if self.modes["LNM"]:
                self.column = 1
        elif byte == CR:
            self.pending_wrap = False
            self.column = 1
        elif byte == SO:
            self.gl = "G1"
        elif byte == SI:
            self.gl = "G0"

    def print_char(self, char):
        charset = self.g1 if self.gl == "G1" else self.g0
        if charset == LINE_DRAWING:
            char = LINE_DRAWING_CHARS.get(char, char)
        self.write(char)

    def write(self, char):
        self.printed += 1
        self.last_char = char
        if self.pending_wrap:
            self.pending_wrap = False
            self.column = 1
            self.line_feed()
        screen = self.screen()
        if self.modes["IRM"]:
            screen.insert_cells(self.row, self.column, 1)
        screen.put(self.row, self.column, Cell(char, self.attributes))
        if self.column < self.width:
            self.column += 1
        elif self.modes["DECAWM"]:
            self.pending_wrap = True

    def scroll_region_up(self):
        removed = self.screen().scroll_up(self.top, self.bottom)
        if self.display == MAIN and self.top == 1:
            self.scrollback.append(row_text(removed))
            if len(self.scrollback) > SCROLLBACK_LIMIT:
                del self.scrollback[0]

    def scroll_region_down(self):
        self.screen().scroll_down(self.top, self.bottom)

    def line_feed(self):
        if self.row == self.bottom:
            self.scroll_region_up()
        elif self.row < self.height:
            self.row += 1

    def reverse_line_feed(self):
        if self.row == self.top:
            self.scroll_region_down()
        elif self.row > 1:
            self.row -= 1

    def tab_move(self, count):
        while count > 0 and self.column < self.width:
            later = [stop for stop in self.tab_stops if stop > self.column]
            self.column = min(later) if later else self.width
            count -= 1

    def reverse_tab_move(self, count):
        while count > 0 and self.column > 1:
            earlier = [stop for stop in self.tab_stops if stop < self.column]
            self.column = max(earlier) if earlier else 1
            count -= 1

    def address_row(self, value):
        if self.modes["DECOM"]:
            return min(self.top + value - 1, self.bottom)
        return min(value, self.height)

    def home(self):
        self.row = self.address_row(1)
        self.column = 1

    def save_cursor(self):
        self.saved[self.display] = SavedCursor(
            self.row, self.column, self.attributes, self.modes["DECOM"],
            self.g0, self.g1, self.gl,
        )

    def restore_cursor(self):
        self.pending_wrap = False
        saved = self.saved[self.display]
        if saved is None:
            saved = SavedCursor(1, 1, DEFAULT_ATTRIBUTES, False, ASCII, ASCII, "G0")
        self.row = saved.row
        self.column = saved.column
        self.attributes = saved.attributes
        self.modes["DECOM"] = saved.origin
        self.g0 = saved.g0
        self.g1 = saved.g1
        self.gl = saved.gl

    def screen_alignment(self):
        self.pending_wrap = False
        self.screen().fill("E")
        self.top = 1
        self.bottom = self.height
        self.modes["DECOM"] = False
        self.row = 1
        self.column = 1

    def execute_esc(self, key):
        if key == "7":
            self.save_cursor()
        elif key == "8":
            self.restore_cursor()
        elif key == "D":
            self.pending_wrap = False
            self.line_feed()
        elif key == "E":
            self.pending_wrap = False
            self.column = 1
            self.line_feed()
        elif key == "M":
            self.pending_wrap = False
            self.reverse_line_feed()
        elif key == "H":
            self.tab_stops.add(self.column)
        elif key == "c":
            self.reset()
        elif key in ("=", ">"):
            self.modes["DECKPAM"] = key == "="
        elif key == "\\":
            pass
        elif key in ("(0", "(B"):
            self.g0 = CHARSETS[key[1]]
        elif key in (")0", ")B"):
            self.g1 = CHARSETS[key[1]]
        elif key == "#8":
            self.screen_alignment()
        else:
            self.ignored[UNSUPPORTED] += 1
            return
        self.sequences += 1

    def execute_osc(self):
        if self.osc.startswith(("0;", "2;")):
            self.title = self.osc[2:]
            self.sequences += 1
        else:
            self.ignored[UNSUPPORTED] += 1

    def execute_csi(self, final):
        key = self.marker + self.intermediates + final
        fields = self.parameters.split(";") if self.parameters else []
        try:
            require(len(fields) <= MAX_FIELDS, INVALID)
            require(key in self.csi_handlers)
            params = [field_value(field) for field in fields]
            if key in CSI_CONDITIONS:
                require(parameter(params, 0) in CSI_CONDITIONS[key])
            if key in WRAP_CLEARING_CSI:
                self.pending_wrap = False
            self.csi_handlers[key](params)
        except SequenceIgnored as ignored:
            self.ignored[ignored.reason] += 1
        else:
            self.sequences += 1

    def move_up(self, count):
        limit = self.top if self.row >= self.top else 1
        self.row = max(self.row - count, limit)

    def move_down(self, count):
        limit = self.bottom if self.row <= self.bottom else self.height
        self.row = min(self.row + count, limit)

    def cursor_up(self, params):
        self.move_up(amount(params))

    def cursor_down(self, params):
        self.move_down(amount(params))

    def cursor_forward(self, params):
        self.column = min(self.column + amount(params), self.width)

    def cursor_backward(self, params):
        self.column = max(self.column - amount(params), 1)

    def cursor_next_line(self, params):
        self.move_down(amount(params))
        self.column = 1

    def cursor_previous_line(self, params):
        self.move_up(amount(params))
        self.column = 1

    def cursor_column(self, params):
        self.column = min(amount(params), self.width)

    def cursor_position(self, params):
        self.row = self.address_row(amount(params))
        self.column = min(max(parameter(params, 1), 1), self.width)

    def cursor_row(self, params):
        self.row = self.address_row(amount(params))

    def forward_tabulation(self, params):
        self.tab_move(amount(params))

    def backward_tabulation(self, params):
        self.reverse_tab_move(amount(params))

    def erase_in_display(self, params):
        mode = parameter(params, 0)
        screen = self.screen()
        if mode == 0:
            screen.erase(self.row, self.column, self.width)
            screen.erase_rows(self.row + 1, self.height)
        elif mode == 1:
            screen.erase_rows(1, self.row - 1)
            screen.erase(self.row, 1, self.column)
        elif mode == 2:
            screen.clear()
        else:
            self.scrollback.clear()

    def erase_in_line(self, params):
        mode = parameter(params, 0)
        first = 1 if mode in (1, 2) else self.column
        last = self.column if mode == 1 else self.width
        self.screen().erase(self.row, first, last)

    def erase_characters(self, params):
        last = min(self.column + amount(params) - 1, self.width)
        self.screen().erase(self.row, self.column, last)

    def insert_characters(self, params):
        count = min(amount(params), self.width - self.column + 1)
        self.screen().insert_cells(self.row, self.column, count)

    def delete_characters(self, params):
        count = min(amount(params), self.width - self.column + 1)
        self.screen().delete_cells(self.row, self.column, count)

    def insert_lines(self, params):
        if self.top <= self.row <= self.bottom:
            count = min(amount(params), self.bottom - self.row + 1)
            for _ in range(count):
                self.screen().scroll_down(self.row, self.bottom)
            self.column = 1

    def delete_lines(self, params):
        if self.top <= self.row <= self.bottom:
            count = min(amount(params), self.bottom - self.row + 1)
            for _ in range(count):
                self.screen().scroll_up(self.row, self.bottom)
            self.column = 1

    def scroll_up(self, params):
        for _ in range(min(amount(params), self.bottom - self.top + 1)):
            self.scroll_region_up()

    def scroll_down(self, params):
        for _ in range(min(amount(params), self.bottom - self.top + 1)):
            self.scroll_region_down()

    def repeat_character(self, params):
        if self.last_char is not None:
            for _ in range(amount(params)):
                self.write(self.last_char)

    def clear_tab_stops(self, params):
        if parameter(params, 0) == 0:
            self.tab_stops.discard(self.column)
        else:
            self.tab_stops.clear()

    def select_graphic_rendition(self, params):
        values = params or [0]
        attributes = self.attributes.copy()
        index = 0
        while index < len(values):
            value = values[index]
            if value == 0:
                attributes = Attributes()
            elif value in SGR_FLAGS_ON:
                attributes.flags |= 1 << SGR_FLAGS_ON[value]
            elif value in SGR_FLAGS_OFF:
                for flag in SGR_FLAGS_OFF[value]:
                    attributes.flags &= ~(1 << flag)
            elif 30 <= value <= 37:
                attributes.foreground = palette_color(value - 30)
            elif 90 <= value <= 97:
                attributes.foreground = palette_color(value - 82)
            elif 40 <= value <= 47:
                attributes.background = palette_color(value - 40)
            elif 100 <= value <= 107:
                attributes.background = palette_color(value - 92)
            elif value == 39:
                attributes.foreground = None
            elif value == 49:
                attributes.background = None
            else:
                require(value in (38, 48))
                color, used = extended_color(values, index + 1)
                if value == 38:
                    attributes.foreground = color
                else:
                    attributes.background = color
                index += used
            index += 1
        self.attributes = attributes

    def set_ansi_modes(self, params, enabled):
        values = params or [0]
        require(all(value in ANSI_MODES for value in values))
        for value in values:
            self.modes[ANSI_MODES[value]] = enabled

    def set_dec_modes(self, params, enabled):
        values = params or [0]
        require(all(value in DEC_MODE_NUMBERS for value in values))
        for value in values:
            if value in DEC_MODES:
                self.set_dec_flag(value, enabled)
            elif value == 1048:
                if enabled:
                    self.save_cursor()
                else:
                    self.restore_cursor()
            else:
                self.switch_screen(value, enabled)

    def set_dec_flag(self, value, enabled):
        if value == 6 or (value == 7 and not enabled):
            self.pending_wrap = False
        self.modes[DEC_MODES[value]] = enabled
        if value == 6:
            self.home()

    def switch_screen(self, value, enabled):
        self.pending_wrap = False
        if enabled and self.display == MAIN:
            if value == 1049:
                self.save_cursor()
            self.display = ALTERNATE
            if value == 1049:
                self.screen().clear()
        elif not enabled and self.display == ALTERNATE:
            if value == 1047:
                self.screen().clear()
            self.display = MAIN
            if value == 1049:
                self.restore_cursor()

    def set_cursor_shape(self, params):
        self.cursor_shape = amount(params)

    def set_scroll_region(self, params):
        top = amount(params)
        bottom = min(parameter(params, 1) or self.height, self.height)
        require(top < bottom, INVALID)
        self.pending_wrap = False
        self.top = top
        self.bottom = bottom
        self.home()

    def soft_reset(self, params):
        self.pending_wrap = False
        for name in SOFT_RESET_MODES:
            self.modes[name] = INITIAL_MODES[name]
        self.top = 1
        self.bottom = self.height
        self.attributes = DEFAULT_ATTRIBUTES
        self.g0 = ASCII
        self.g1 = ASCII
        self.gl = "G0"
        self.saved[self.display] = None

    def reply(self, text):
        self.replies += 1
        self.emit("REPLY", text)

    def reported_row(self):
        if self.modes["DECOM"]:
            return max(self.row - self.top + 1, 1)
        return self.row

    def device_status_report(self, params):
        if parameter(params, 0) == 5:
            self.reply("^[[0n")
        else:
            self.reply(f"^[[{self.reported_row()};{self.column}R")

    def extended_cursor_report(self, params):
        self.reply(f"^[[?{self.reported_row()};{self.column};1R")

    def device_attributes(self, params):
        self.reply("^[[?1;2c")

    def secondary_device_attributes(self, params):
        self.reply("^[[>0;95;0c")

    def window_report(self, params):
        self.reply(f"^[[8;{self.height};{self.width}t")

    def request_ansi_mode(self, params):
        mode = parameter(params, 0)
        state = mode_state(self.modes[ANSI_MODES[mode]]) if mode in ANSI_MODES else 0
        self.reply(f"^[[{mode};{state}$y")

    def request_dec_mode(self, params):
        mode = parameter(params, 0)
        if mode in DEC_MODES:
            state = mode_state(self.modes[DEC_MODES[mode]])
        elif mode in SCREEN_MODES:
            state = mode_state(self.display == ALTERNATE)
        else:
            state = 0
        self.reply(f"^[[?{mode};{state}$y")

    def key_string(self, name):
        if name in CURSOR_KEYS:
            prefix = "^[O" if self.modes["DECCKM"] else "^[["
            return prefix + CURSOR_KEYS[name]
        if name in FIXED_KEYS:
            return FIXED_KEYS[name]
        enter = "^M^J" if self.modes["LNM"] else "^M"
        if name == "ENTER":
            return enter
        if name == "KPENTER":
            return "^[OM" if self.modes["DECKPAM"] else enter
        digit = int(name[2:])
        if self.modes["DECKPAM"]:
            return "^[O" + chr(0x70 + digit)
        return str(digit)

    def press_key(self, name):
        self.emit("KEY", name, self.key_string(name))

    def paste(self, text):
        sent = text.replace("^", "^^")
        if self.modes["BRACKETED"]:
            sent = "^[[200~" + sent + "^[[201~"
        self.emit("PASTE", sent)

    def screen_output(self, label):
        name = "alt" if self.display == ALTERNATE else "main"
        parts = [label, name, "cursor", f"{self.row},{self.column}", "scrollback", len(self.scrollback)]
        if self.pending_wrap:
            parts.append("pending")
        self.emit(*parts)
        screen = self.screen()
        for row in range(1, self.height + 1):
            self.output.append("|" + screen.text(row))

    def dump(self):
        self.dumps += 1
        self.screen_output(f"DUMP {self.dumps}")

    def changed_modes(self):
        items = [
            f"{name}={'on' if enabled else 'off'}"
            for name, enabled in self.modes.items()
            if enabled != INITIAL_MODES[name]
        ]
        if self.g0 == LINE_DRAWING:
            items.append("G0=graphics")
        if self.g1 == LINE_DRAWING:
            items.append("G1=graphics")
        if self.gl == "G1":
            items.append("GL=G1")
        if self.cursor_shape != 1:
            items.append(f"CURSOR={self.cursor_shape}")
        return items

    def attribute_runs(self):
        runs = []
        for row, cells in enumerate(self.screen().rows, 1):
            start = 0
            for column in range(1, self.width + 1):
                if column < self.width and cells[column].attributes == cells[start].attributes:
                    continue
                attributes = cells[start].attributes
                if not attributes.is_default():
                    runs.append(f"row {row} col {start + 1}-{column} {attributes.describe()}")
                start = column
        return runs

    def finish(self):
        if self.state != GROUND:
            self.ignored[CANCELED] += 1
            self.state = GROUND
        self.screen_output("FINAL")
        self.emit("TITLE", "none" if self.title is None else f'"{self.title}"')
        self.emit("MODES", *(self.changed_modes() or ["default"]))
        self.emit("REGION", f"{self.top}-{self.bottom}")
        stops = sorted(self.tab_stops)
        self.emit("TABS", ",".join(str(stop) for stop in stops) if stops else "none")
        self.emit("SCROLLBACK", len(self.scrollback))
        for text in self.scrollback[-SCROLLBACK_SHOWN:]:
            self.output.append("|" + text)
        runs = self.attribute_runs()
        self.emit("ATTRS", len(runs))
        self.output.extend(runs)
        self.emit("BELL", self.bells)
        self.emit("REPLIES", self.replies)
        self.emit(
            "STATS", f"bytes={self.stream_bytes}", f"printed={self.printed}",
            f"sequences={self.sequences}",
        )
        counts = [f"{reason}={count}" for reason, count in self.ignored.items()]
        self.emit("IGNORED", sum(self.ignored.values()), *counts)


def main():
    lines = sys.stdin.read().splitlines()
    width, height = (int(value) for value in lines[0].split())
    terminal = Terminal(width, height)
    for line in lines[1:]:
        if line == "%%END":
            break
        if line == "%%DUMP":
            terminal.dump()
        elif line.startswith("%%KEY "):
            terminal.press_key(line[len("%%KEY "):])
        elif line.startswith("%%PASTE "):
            terminal.paste(line[len("%%PASTE "):])
        else:
            for byte in decode_stream(line):
                terminal.receive(byte)
    terminal.finish()
    sys.stdout.write("\n".join(terminal.output) + "\n")


if __name__ == "__main__":
    main()
