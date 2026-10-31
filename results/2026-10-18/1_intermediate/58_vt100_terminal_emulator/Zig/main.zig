const std = @import("std");

const max_width = 80;
const max_height = 30;
const max_parameter = 9999;
const max_fields = 16;
const scrollback_limit = 100;
const scrollback_shown = 5;
const tab_width = 8;

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

const color_names = [_][]const u8{
    "black",
    "red",
    "green",
    "yellow",
    "blue",
    "magenta",
    "cyan",
    "white",
};

const Error = std.mem.Allocator.Error || std.Io.Writer.Error;
const Ignored = error{ Unsupported, Invalid };

const State = enum {
    ground,
    escape,
    escape_intermediate,
    csi_entry,
    csi_param,
    csi_intermediate,
    csi_ignore,
    osc_string,
};

const Display = enum { main, alternate };
const Charset = enum { ascii, line_drawing };
const Slot = enum { g0, g1 };

const Mode = enum { irm, lnm, decckm, decscnm, decom, decawm, dectcem, deckpam, bracketed };
const initial_modes = std.EnumArray(Mode, bool).init(.{
    .irm = false,
    .lnm = false,
    .decckm = false,
    .decscnm = false,
    .decom = false,
    .decawm = true,
    .dectcem = true,
    .deckpam = false,
    .bracketed = false,
});
const soft_reset_modes = [_]Mode{ .irm, .decckm, .decom, .decawm, .dectcem, .deckpam };

const EscCommand = enum {
    save,
    restore,
    index,
    next_line,
    reverse_index,
    set_tab_stop,
    full_reset,
    keypad_application,
    keypad_numeric,
    string_terminator,
    g0_line_drawing,
    g0_ascii,
    g1_line_drawing,
    g1_ascii,
    screen_alignment,
};

const esc_commands = std.StaticStringMap(EscCommand).initComptime(.{
    .{ "7", .save },
    .{ "8", .restore },
    .{ "D", .index },
    .{ "E", .next_line },
    .{ "M", .reverse_index },
    .{ "H", .set_tab_stop },
    .{ "c", .full_reset },
    .{ "=", .keypad_application },
    .{ ">", .keypad_numeric },
    .{ "\\", .string_terminator },
    .{ "(0", .g0_line_drawing },
    .{ "(B", .g0_ascii },
    .{ ")0", .g1_line_drawing },
    .{ ")B", .g1_ascii },
    .{ "#8", .screen_alignment },
});

const CsiCommand = enum {
    cursor_up,
    cursor_down,
    cursor_forward,
    cursor_backward,
    cursor_next_line,
    cursor_previous_line,
    cursor_column,
    cursor_position,
    cursor_row,
    forward_tabulation,
    backward_tabulation,
    erase_in_display,
    erase_in_line,
    erase_characters,
    insert_characters,
    delete_characters,
    insert_lines,
    delete_lines,
    scroll_up,
    scroll_down,
    repeat_character,
    clear_tab_stops,
    select_graphic_rendition,
    set_ansi_modes,
    reset_ansi_modes,
    set_dec_modes,
    reset_dec_modes,
    set_cursor_shape,
    set_scroll_region,
    save_cursor,
    restore_cursor,
    soft_reset,
    device_status_report,
    extended_cursor_report,
    device_attributes,
    secondary_device_attributes,
    window_report,
    request_ansi_mode,
    request_dec_mode,

    fn accepts(command: CsiCommand, first: usize) bool {
        return switch (command) {
            .erase_in_display => first <= 3,
            .erase_in_line => first <= 2,
            .clear_tab_stops => first == 0 or first == 3,
            .set_cursor_shape => first <= 6,
            .device_status_report => first == 5 or first == 6,
            .extended_cursor_report => first == 6,
            .device_attributes, .secondary_device_attributes => first == 0,
            .window_report => first == 18,
            else => true,
        };
    }

    fn clearsPendingWrap(command: CsiCommand) bool {
        return switch (command) {
            .cursor_up,
            .cursor_down,
            .cursor_forward,
            .cursor_backward,
            .cursor_next_line,
            .cursor_previous_line,
            .cursor_column,
            .cursor_position,
            .cursor_row,
            .forward_tabulation,
            .backward_tabulation,
            .erase_in_display,
            .erase_in_line,
            .erase_characters,
            .insert_characters,
            .delete_characters,
            .insert_lines,
            .delete_lines,
            .scroll_up,
            .scroll_down,
            => true,
            else => false,
        };
    }
};

const csi_commands = std.StaticStringMap(CsiCommand).initComptime(.{
    .{ "A", .cursor_up },
    .{ "B", .cursor_down },
    .{ "e", .cursor_down },
    .{ "C", .cursor_forward },
    .{ "a", .cursor_forward },
    .{ "D", .cursor_backward },
    .{ "E", .cursor_next_line },
    .{ "F", .cursor_previous_line },
    .{ "G", .cursor_column },
    .{ "`", .cursor_column },
    .{ "H", .cursor_position },
    .{ "f", .cursor_position },
    .{ "d", .cursor_row },
    .{ "I", .forward_tabulation },
    .{ "Z", .backward_tabulation },
    .{ "J", .erase_in_display },
    .{ "K", .erase_in_line },
    .{ "X", .erase_characters },
    .{ "@", .insert_characters },
    .{ "P", .delete_characters },
    .{ "L", .insert_lines },
    .{ "M", .delete_lines },
    .{ "S", .scroll_up },
    .{ "T", .scroll_down },
    .{ "b", .repeat_character },
    .{ "g", .clear_tab_stops },
    .{ "m", .select_graphic_rendition },
    .{ "h", .set_ansi_modes },
    .{ "l", .reset_ansi_modes },
    .{ "?h", .set_dec_modes },
    .{ "?l", .reset_dec_modes },
    .{ " q", .set_cursor_shape },
    .{ "r", .set_scroll_region },
    .{ "s", .save_cursor },
    .{ "u", .restore_cursor },
    .{ "!p", .soft_reset },
    .{ "n", .device_status_report },
    .{ "?n", .extended_cursor_report },
    .{ "c", .device_attributes },
    .{ ">c", .secondary_device_attributes },
    .{ "t", .window_report },
    .{ "$p", .request_ansi_mode },
    .{ "?$p", .request_dec_mode },
});

const cursor_keys = std.StaticStringMap(u8).initComptime(.{
    .{ "UP", 'A' },
    .{ "DOWN", 'B' },
    .{ "RIGHT", 'C' },
    .{ "LEFT", 'D' },
    .{ "HOME", 'H' },
    .{ "END", 'F' },
});

const fixed_keys = std.StaticStringMap([]const u8).initComptime(.{
    .{ "INSERT", "^[[2~" },
    .{ "DELETE", "^[[3~" },
    .{ "PAGEUP", "^[[5~" },
    .{ "PAGEDOWN", "^[[6~" },
    .{ "F1", "^[OP" },
    .{ "F2", "^[OQ" },
    .{ "F3", "^[OR" },
    .{ "F4", "^[OS" },
    .{ "F5", "^[[15~" },
    .{ "F6", "^[[17~" },
    .{ "F7", "^[[18~" },
    .{ "F8", "^[[19~" },
    .{ "F9", "^[[20~" },
    .{ "F10", "^[[21~" },
    .{ "F11", "^[[23~" },
    .{ "F12", "^[[24~" },
    .{ "TAB", "^I" },
    .{ "BACKSPACE", "^?" },
    .{ "ESCAPE", "^[" },
});

fn isIntermediate(byte: u8) bool {
    return 0x20 <= byte and byte <= 0x2F;
}

fn isParameter(byte: u8) bool {
    return (0x30 <= byte and byte <= 0x39) or byte == 0x3B;
}

fn isPrivateMarker(byte: u8) bool {
    return 0x3C <= byte and byte <= 0x3F;
}

fn isFinal(byte: u8) bool {
    return 0x40 <= byte and byte <= 0x7E;
}

fn caretByte(char: u8) u8 {
    return if (char == '^') '^' else char - '@';
}

fn lineDrawing(char: u8) u8 {
    return switch (char) {
        '`' => '*',
        'a' => '#',
        'j', 'k', 'l', 'm', 'n', 't', 'u', 'v', 'w' => '+',
        'q' => '-',
        'x' => '|',
        '~' => 'o',
        else => char,
    };
}

fn fieldValue(field: []const u8) usize {
    var value: usize = 0;
    for (field) |digit| value = @min(value * 10 + (digit - '0'), max_parameter);
    return value;
}

fn parameter(params: []const usize, index: usize) usize {
    return if (index < params.len) params[index] else 0;
}

fn amount(params: []const usize) usize {
    return @max(parameter(params, 0), 1);
}

fn paramsOrZero(params: []const usize) []const usize {
    return if (params.len == 0) &[_]usize{0} else params;
}

fn ansiMode(number: usize) ?Mode {
    return switch (number) {
        4 => .irm,
        20 => .lnm,
        else => null,
    };
}

fn decMode(number: usize) ?Mode {
    return switch (number) {
        1 => .decckm,
        5 => .decscnm,
        6 => .decom,
        7 => .decawm,
        25 => .dectcem,
        2004 => .bracketed,
        else => null,
    };
}

fn isDecModeNumber(number: usize) bool {
    return switch (number) {
        1, 5, 6, 7, 25, 47, 1047, 1048, 1049, 2004 => true,
        else => false,
    };
}

fn modeState(enabled: bool) usize {
    return if (enabled) 1 else 2;
}

const Color = union(enum) {
    palette: u8,
    rgb: [3]u8,

    pub fn format(self: Color, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .palette => |number| {
                if (number < 8) {
                    try writer.writeAll(color_names[number]);
                } else if (number < 16) {
                    try writer.print("bright-{s}", .{color_names[number - 8]});
                } else {
                    try writer.print("{d}", .{number});
                }
            },
            .rgb => |components| try writer.print("#{x:0>2}{x:0>2}{x:0>2}", .{
                components[0],
                components[1],
                components[2],
            }),
        }
    }
};

fn extendedColor(rest: []const usize) Ignored!struct { Color, usize } {
    if (rest.len >= 2 and rest[0] == 5 and rest[1] <= 255) {
        return .{ Color{ .palette = @intCast(rest[1]) }, 2 };
    }
    if (rest.len >= 4 and rest[0] == 2 and std.mem.max(usize, rest[1..4]) <= 255) {
        return .{ Color{ .rgb = .{ @intCast(rest[1]), @intCast(rest[2]), @intCast(rest[3]) } }, 4 };
    }
    return error.Unsupported;
}

const Flags = struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    reverse: bool = false,
    hidden: bool = false,
    strike: bool = false,
};

const Attributes = struct {
    flags: Flags = .{},
    foreground: ?Color = null,
    background: ?Color = null,

    fn isDefault(self: Attributes) bool {
        return std.meta.eql(self, Attributes{});
    }

    pub fn format(self: Attributes, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        inline for (comptime std.meta.fieldNames(Flags)) |name| {
            if (@field(self.flags, name)) try writer.writeAll(" " ++ name);
        }
        if (self.foreground) |color| try writer.print(" fg={f}", .{color});
        if (self.background) |color| try writer.print(" bg={f}", .{color});
    }
};

const Cell = struct {
    char: u8 = ' ',
    attributes: Attributes = .{},
};

const Row = [max_width]Cell;
const blank_row: Row = @splat(.{});

const Line = struct {
    chars: [max_width]u8 = undefined,
    len: usize = 0,

    fn text(self: *const Line) []const u8 {
        return self.chars[0..self.len];
    }
};

fn rowText(cells: []const Cell) Line {
    var line = Line{};
    for (cells, 0..) |cell, index| {
        line.chars[index] = cell.char;
        if (cell.char != ' ') line.len = index + 1;
    }
    return line;
}

const SavedCursor = struct {
    row: usize = 1,
    column: usize = 1,
    attributes: Attributes = .{},
    origin: bool = false,
    g0: Charset = .ascii,
    g1: Charset = .ascii,
    gl: Slot = .g0,
};

const IgnoredCounts = struct {
    unsupported: usize = 0,
    malformed: usize = 0,
    canceled: usize = 0,
    invalid: usize = 0,
};

const Run = struct {
    row: usize,
    first: usize,
    last: usize,
    attributes: Attributes,
};

const Screen = struct {
    width: usize,
    height: usize,
    rows: [max_height]Row = @splat(blank_row),

    fn clear(self: *Screen) void {
        @memset(self.rows[0..self.height], blank_row);
    }

    fn fill(self: *Screen, char: u8) void {
        for (self.rows[0..self.height]) |*row| @memset(row, Cell{ .char = char });
    }

    fn put(self: *Screen, row: usize, column: usize, cell: Cell) void {
        self.rows[row - 1][column - 1] = cell;
    }

    fn erase(self: *Screen, row: usize, first: usize, last: usize) void {
        @memset(self.rows[row - 1][first - 1 .. last], Cell{});
    }

    fn eraseRows(self: *Screen, first: usize, last: usize) void {
        @memset(self.rows[first - 1 .. last], blank_row);
    }

    fn scrollUp(self: *Screen, top: usize, bottom: usize) Row {
        const removed = self.rows[top - 1];
        std.mem.copyForwards(Row, self.rows[top - 1 .. bottom - 1], self.rows[top..bottom]);
        self.rows[bottom - 1] = blank_row;
        return removed;
    }

    fn scrollDown(self: *Screen, top: usize, bottom: usize) void {
        std.mem.copyBackwards(Row, self.rows[top..bottom], self.rows[top - 1 .. bottom - 1]);
        self.rows[top - 1] = blank_row;
    }

    fn insertCells(self: *Screen, row: usize, column: usize, count: usize) void {
        const cells = self.rows[row - 1][0..self.width];
        const start = column - 1;
        std.mem.copyBackwards(Cell, cells[start + count ..], cells[start .. self.width - count]);
        @memset(cells[start .. start + count], Cell{});
    }

    fn deleteCells(self: *Screen, row: usize, column: usize, count: usize) void {
        const cells = self.rows[row - 1][0..self.width];
        const start = column - 1;
        std.mem.copyForwards(Cell, cells[start .. self.width - count], cells[start + count ..]);
        @memset(cells[self.width - count ..], Cell{});
    }
};

const Terminal = struct {
    gpa: std.mem.Allocator,
    out: *std.Io.Writer,
    width: usize,
    height: usize,
    stream_bytes: usize = 0,
    printed: usize = 0,
    sequences: usize = 0,
    bells: usize = 0,
    replies: usize = 0,
    dumps: usize = 0,
    ignored: IgnoredCounts = .{},
    screens: [2]Screen = undefined,
    display: Display = undefined,
    row: usize = undefined,
    column: usize = undefined,
    pending_wrap: bool = undefined,
    attributes: Attributes = undefined,
    g0: Charset = undefined,
    g1: Charset = undefined,
    gl: Slot = undefined,
    modes: std.EnumArray(Mode, bool) = undefined,
    cursor_shape: usize = undefined,
    top: usize = undefined,
    bottom: usize = undefined,
    tab_stops: [max_width + 1]bool = undefined,
    saved: [2]?SavedCursor = undefined,
    scrollback: [scrollback_limit]Line = undefined,
    scrollback_len: usize = undefined,
    title: ?[]u8 = null,
    last_char: ?u8 = undefined,
    state: State = undefined,
    marker: ?u8 = undefined,
    parameters: std.ArrayList(u8) = .empty,
    intermediates: std.ArrayList(u8) = .empty,
    osc: std.ArrayList(u8) = .empty,

    fn init(gpa: std.mem.Allocator, out: *std.Io.Writer, width: usize, height: usize) Terminal {
        var terminal = Terminal{ .gpa = gpa, .out = out, .width = width, .height = height };
        terminal.reset();
        return terminal;
    }

    fn deinit(self: *Terminal) void {
        self.parameters.deinit(self.gpa);
        self.intermediates.deinit(self.gpa);
        self.osc.deinit(self.gpa);
        if (self.title) |title| self.gpa.free(title);
    }

    fn reset(self: *Terminal) void {
        const blank = Screen{ .width = self.width, .height = self.height };
        self.screens = .{ blank, blank };
        self.display = .main;
        self.row = 1;
        self.column = 1;
        self.pending_wrap = false;
        self.attributes = .{};
        self.g0 = .ascii;
        self.g1 = .ascii;
        self.gl = .g0;
        self.modes = initial_modes;
        self.cursor_shape = 1;
        self.top = 1;
        self.bottom = self.height;
        @memset(&self.tab_stops, false);
        var stop: usize = tab_width + 1;
        while (stop <= self.width) : (stop += tab_width) self.tab_stops[stop] = true;
        self.saved = .{ null, null };
        self.scrollback_len = 0;
        if (self.title) |title| self.gpa.free(title);
        self.title = null;
        self.last_char = null;
        self.state = .ground;
        self.clearSequence();
    }

    fn clearSequence(self: *Terminal) void {
        self.marker = null;
        self.parameters.clearRetainingCapacity();
        self.intermediates.clearRetainingCapacity();
        self.osc.clearRetainingCapacity();
    }

    fn displayedScreen(self: *Terminal) *Screen {
        return &self.screens[@backingInt(self.display)];
    }

    fn receive(self: *Terminal, byte: u8) Error!void {
        self.stream_bytes += 1;
        if (byte < 0x20) return self.receiveControl(byte);
        switch (self.state) {
            .ground => self.printChar(byte),
            .escape, .escape_intermediate => try self.escapeByte(byte),
            .osc_string => try self.osc.append(self.gpa, byte),
            .csi_ignore => if (isFinal(byte)) {
                self.ignored.malformed += 1;
                self.state = .ground;
            },
            .csi_intermediate => try self.csiIntermediateByte(byte),
            .csi_entry => if (isPrivateMarker(byte)) {
                self.marker = byte;
                self.state = .csi_param;
            } else {
                try self.csiParamByte(byte);
            },
            .csi_param => try self.csiParamByte(byte),
        }
    }

    fn receiveControl(self: *Terminal, byte: u8) Error!void {
        if (byte == esc) {
            if (self.state == .osc_string) {
                try self.executeOsc();
            } else if (self.state != .ground) {
                self.ignored.canceled += 1;
            }
            self.clearSequence();
            self.state = .escape;
        } else if (byte == can or byte == sub) {
            if (self.state != .ground) {
                self.ignored.canceled += 1;
                self.state = .ground;
            }
        } else if (self.state == .osc_string) {
            if (byte == bel) {
                try self.executeOsc();
                self.state = .ground;
            }
        } else {
            self.executeControl(byte);
        }
    }

    fn escapeByte(self: *Terminal, byte: u8) Error!void {
        if (isIntermediate(byte)) {
            try self.intermediates.append(self.gpa, byte);
            self.state = .escape_intermediate;
        } else if (self.state == .escape and byte == '[') {
            self.state = .csi_entry;
        } else if (self.state == .escape and byte == ']') {
            self.state = .osc_string;
        } else {
            const key = try self.sequenceKey(byte);
            defer self.gpa.free(key);
            self.executeEsc(key);
            self.state = .ground;
        }
    }

    fn csiParamByte(self: *Terminal, byte: u8) Error!void {
        if (isParameter(byte)) {
            try self.parameters.append(self.gpa, byte);
            self.state = .csi_param;
        } else if (isIntermediate(byte)) {
            try self.intermediates.append(self.gpa, byte);
            self.state = .csi_intermediate;
        } else if (isFinal(byte)) {
            try self.executeCsi(byte);
            self.state = .ground;
        } else {
            self.state = .csi_ignore;
        }
    }

    fn csiIntermediateByte(self: *Terminal, byte: u8) Error!void {
        if (isIntermediate(byte)) {
            try self.intermediates.append(self.gpa, byte);
        } else if (isFinal(byte)) {
            try self.executeCsi(byte);
            self.state = .ground;
        } else {
            self.state = .csi_ignore;
        }
    }

    fn sequenceKey(self: *Terminal, final: u8) std.mem.Allocator.Error![]u8 {
        var key: std.ArrayList(u8) = .empty;
        errdefer key.deinit(self.gpa);
        if (self.marker) |marker| try key.append(self.gpa, marker);
        try key.appendSlice(self.gpa, self.intermediates.items);
        try key.append(self.gpa, final);
        return key.toOwnedSlice(self.gpa);
    }

    fn executeControl(self: *Terminal, byte: u8) void {
        switch (byte) {
            bel => self.bells += 1,
            bs => {
                self.pending_wrap = false;
                self.column = @max(self.column - 1, 1);
            },
            ht => {
                self.pending_wrap = false;
                self.tabMove(1);
            },
            lf, vt, ff => {
                self.pending_wrap = false;
                self.lineFeed();
                if (self.modes.get(.lnm)) self.column = 1;
            },
            cr => {
                self.pending_wrap = false;
                self.column = 1;
            },
            so => self.gl = .g1,
            si => self.gl = .g0,
            else => {},
        }
    }

    fn printChar(self: *Terminal, char: u8) void {
        const charset = if (self.gl == .g1) self.g1 else self.g0;
        self.write(if (charset == .line_drawing) lineDrawing(char) else char);
    }

    fn write(self: *Terminal, char: u8) void {
        self.printed += 1;
        self.last_char = char;
        if (self.pending_wrap) {
            self.pending_wrap = false;
            self.column = 1;
            self.lineFeed();
        }
        const screen = self.displayedScreen();
        if (self.modes.get(.irm)) screen.insertCells(self.row, self.column, 1);
        screen.put(self.row, self.column, .{ .char = char, .attributes = self.attributes });
        if (self.column < self.width) {
            self.column += 1;
        } else if (self.modes.get(.decawm)) {
            self.pending_wrap = true;
        }
    }

    fn scrollRegionUp(self: *Terminal) void {
        const removed = self.displayedScreen().scrollUp(self.top, self.bottom);
        if (self.display == .main and self.top == 1) {
            if (self.scrollback_len == scrollback_limit) {
                std.mem.copyForwards(
                    Line,
                    self.scrollback[0 .. scrollback_limit - 1],
                    self.scrollback[1..],
                );
                self.scrollback_len -= 1;
            }
            self.scrollback[self.scrollback_len] = rowText(removed[0..self.width]);
            self.scrollback_len += 1;
        }
    }

    fn scrollRegionDown(self: *Terminal) void {
        self.displayedScreen().scrollDown(self.top, self.bottom);
    }

    fn lineFeed(self: *Terminal) void {
        if (self.row == self.bottom) {
            self.scrollRegionUp();
        } else if (self.row < self.height) {
            self.row += 1;
        }
    }

    fn reverseLineFeed(self: *Terminal) void {
        if (self.row == self.top) {
            self.scrollRegionDown();
        } else if (self.row > 1) {
            self.row -= 1;
        }
    }

    fn tabMove(self: *Terminal, count: usize) void {
        var remaining = count;
        while (remaining > 0 and self.column < self.width) : (remaining -= 1) {
            var next = self.column + 1;
            while (next < self.width and !self.tab_stops[next]) next += 1;
            self.column = next;
        }
    }

    fn reverseTabMove(self: *Terminal, count: usize) void {
        var remaining = count;
        while (remaining > 0 and self.column > 1) : (remaining -= 1) {
            var previous = self.column - 1;
            while (previous > 1 and !self.tab_stops[previous]) previous -= 1;
            self.column = previous;
        }
    }

    fn addressRow(self: *const Terminal, value: usize) usize {
        if (self.modes.get(.decom)) return @min(self.top + value - 1, self.bottom);
        return @min(value, self.height);
    }

    fn home(self: *Terminal) void {
        self.row = self.addressRow(1);
        self.column = 1;
    }

    fn saveCursor(self: *Terminal) void {
        self.saved[@backingInt(self.display)] = SavedCursor{
            .row = self.row,
            .column = self.column,
            .attributes = self.attributes,
            .origin = self.modes.get(.decom),
            .g0 = self.g0,
            .g1 = self.g1,
            .gl = self.gl,
        };
    }

    fn restoreCursor(self: *Terminal) void {
        self.pending_wrap = false;
        const saved = self.saved[@backingInt(self.display)] orelse SavedCursor{};
        self.row = saved.row;
        self.column = saved.column;
        self.attributes = saved.attributes;
        self.modes.set(.decom, saved.origin);
        self.g0 = saved.g0;
        self.g1 = saved.g1;
        self.gl = saved.gl;
    }

    fn screenAlignment(self: *Terminal) void {
        self.pending_wrap = false;
        self.displayedScreen().fill('E');
        self.top = 1;
        self.bottom = self.height;
        self.modes.set(.decom, false);
        self.row = 1;
        self.column = 1;
    }

    fn executeEsc(self: *Terminal, key: []const u8) void {
        const command = esc_commands.get(key) orelse {
            self.ignored.unsupported += 1;
            return;
        };
        switch (command) {
            .save => self.saveCursor(),
            .restore => self.restoreCursor(),
            .index => {
                self.pending_wrap = false;
                self.lineFeed();
            },
            .next_line => {
                self.pending_wrap = false;
                self.column = 1;
                self.lineFeed();
            },
            .reverse_index => {
                self.pending_wrap = false;
                self.reverseLineFeed();
            },
            .set_tab_stop => self.tab_stops[self.column] = true,
            .full_reset => self.reset(),
            .keypad_application => self.modes.set(.deckpam, true),
            .keypad_numeric => self.modes.set(.deckpam, false),
            .string_terminator => {},
            .g0_line_drawing => self.g0 = .line_drawing,
            .g0_ascii => self.g0 = .ascii,
            .g1_line_drawing => self.g1 = .line_drawing,
            .g1_ascii => self.g1 = .ascii,
            .screen_alignment => self.screenAlignment(),
        }
        self.sequences += 1;
    }

    fn executeOsc(self: *Terminal) Error!void {
        const osc = self.osc.items;
        if (std.mem.startsWith(u8, osc, "0;") or std.mem.startsWith(u8, osc, "2;")) {
            const title = try self.gpa.dupe(u8, osc[2..]);
            if (self.title) |old| self.gpa.free(old);
            self.title = title;
            self.sequences += 1;
        } else {
            self.ignored.unsupported += 1;
        }
    }

    fn executeCsi(self: *Terminal, final: u8) Error!void {
        const key = try self.sequenceKey(final);
        defer self.gpa.free(key);
        self.runCsi(key) catch |err| switch (err) {
            error.Unsupported => {
                self.ignored.unsupported += 1;
                return;
            },
            error.Invalid => {
                self.ignored.invalid += 1;
                return;
            },
            else => |other| return other,
        };
        self.sequences += 1;
    }

    fn runCsi(self: *Terminal, key: []const u8) (Ignored || Error)!void {
        var values: [max_fields]usize = undefined;
        var field_count: usize = 0;
        if (self.parameters.items.len > 0) {
            var fields = std.mem.splitScalar(u8, self.parameters.items, ';');
            while (fields.next()) |field| : (field_count += 1) {
                if (field_count == max_fields) return error.Invalid;
                values[field_count] = fieldValue(field);
            }
        }
        const params = values[0..field_count];
        const command = csi_commands.get(key) orelse return error.Unsupported;
        if (!command.accepts(parameter(params, 0))) return error.Unsupported;
        if (command.clearsPendingWrap()) self.pending_wrap = false;
        switch (command) {
            .cursor_up => self.moveUp(amount(params)),
            .cursor_down => self.moveDown(amount(params)),
            .cursor_forward => self.column = @min(self.column + amount(params), self.width),
            .cursor_backward => self.column = @max(self.column -| amount(params), 1),
            .cursor_next_line => {
                self.moveDown(amount(params));
                self.column = 1;
            },
            .cursor_previous_line => {
                self.moveUp(amount(params));
                self.column = 1;
            },
            .cursor_column => self.column = @min(amount(params), self.width),
            .cursor_position => {
                self.row = self.addressRow(amount(params));
                self.column = @min(@max(parameter(params, 1), 1), self.width);
            },
            .cursor_row => self.row = self.addressRow(amount(params)),
            .forward_tabulation => self.tabMove(amount(params)),
            .backward_tabulation => self.reverseTabMove(amount(params)),
            .erase_in_display => self.eraseInDisplay(parameter(params, 0)),
            .erase_in_line => self.eraseInLine(parameter(params, 0)),
            .erase_characters => {
                const last = @min(self.column + amount(params) - 1, self.width);
                self.displayedScreen().erase(self.row, self.column, last);
            },
            .insert_characters => {
                const count = @min(amount(params), self.width - self.column + 1);
                self.displayedScreen().insertCells(self.row, self.column, count);
            },
            .delete_characters => {
                const count = @min(amount(params), self.width - self.column + 1);
                self.displayedScreen().deleteCells(self.row, self.column, count);
            },
            .insert_lines => self.insertLines(amount(params)),
            .delete_lines => self.deleteLines(amount(params)),
            .scroll_up => {
                const count = @min(amount(params), self.bottom - self.top + 1);
                for (0..count) |_| self.scrollRegionUp();
            },
            .scroll_down => {
                const count = @min(amount(params), self.bottom - self.top + 1);
                for (0..count) |_| self.scrollRegionDown();
            },
            .repeat_character => if (self.last_char) |char| {
                for (0..amount(params)) |_| self.write(char);
            },
            .clear_tab_stops => if (parameter(params, 0) == 0) {
                self.tab_stops[self.column] = false;
            } else {
                @memset(&self.tab_stops, false);
            },
            .select_graphic_rendition => try self.selectGraphicRendition(params),
            .set_ansi_modes => try self.setAnsiModes(params, true),
            .reset_ansi_modes => try self.setAnsiModes(params, false),
            .set_dec_modes => try self.setDecModes(params, true),
            .reset_dec_modes => try self.setDecModes(params, false),
            .set_cursor_shape => self.cursor_shape = amount(params),
            .set_scroll_region => try self.setScrollRegion(params),
            .save_cursor => self.saveCursor(),
            .restore_cursor => self.restoreCursor(),
            .soft_reset => self.softReset(),
            .device_status_report => if (parameter(params, 0) == 5) {
                try self.reply("^[[0n", .{});
            } else {
                try self.reply("^[[{d};{d}R", .{ self.reportedRow(), self.column });
            },
            .extended_cursor_report => {
                try self.reply("^[[?{d};{d};1R", .{ self.reportedRow(), self.column });
            },
            .device_attributes => try self.reply("^[[?1;2c", .{}),
            .secondary_device_attributes => try self.reply("^[[>0;95;0c", .{}),
            .window_report => try self.reply("^[[8;{d};{d}t", .{ self.height, self.width }),
            .request_ansi_mode => try self.requestAnsiMode(parameter(params, 0)),
            .request_dec_mode => try self.requestDecMode(parameter(params, 0)),
        }
    }

    fn moveUp(self: *Terminal, count: usize) void {
        const limit = if (self.row >= self.top) self.top else 1;
        self.row = @max(self.row -| count, limit);
    }

    fn moveDown(self: *Terminal, count: usize) void {
        const limit = if (self.row <= self.bottom) self.bottom else self.height;
        self.row = @min(self.row + count, limit);
    }

    fn eraseInDisplay(self: *Terminal, mode: usize) void {
        const screen = self.displayedScreen();
        switch (mode) {
            0 => {
                screen.erase(self.row, self.column, self.width);
                screen.eraseRows(self.row + 1, self.height);
            },
            1 => {
                screen.eraseRows(1, self.row - 1);
                screen.erase(self.row, 1, self.column);
            },
            2 => screen.clear(),
            else => self.scrollback_len = 0,
        }
    }

    fn eraseInLine(self: *Terminal, mode: usize) void {
        const first = if (mode == 0) self.column else 1;
        const last = if (mode == 1) self.column else self.width;
        self.displayedScreen().erase(self.row, first, last);
    }

    fn insertLines(self: *Terminal, count: usize) void {
        if (self.row < self.top or self.row > self.bottom) return;
        for (0..@min(count, self.bottom - self.row + 1)) |_| {
            self.displayedScreen().scrollDown(self.row, self.bottom);
        }
        self.column = 1;
    }

    fn deleteLines(self: *Terminal, count: usize) void {
        if (self.row < self.top or self.row > self.bottom) return;
        for (0..@min(count, self.bottom - self.row + 1)) |_| {
            _ = self.displayedScreen().scrollUp(self.row, self.bottom);
        }
        self.column = 1;
    }

    fn selectGraphicRendition(self: *Terminal, params: []const usize) Ignored!void {
        const values = paramsOrZero(params);
        var attributes = self.attributes;
        var index: usize = 0;
        while (index < values.len) : (index += 1) {
            const value = values[index];
            switch (value) {
                0 => attributes = .{},
                1 => attributes.flags.bold = true,
                2 => attributes.flags.dim = true,
                3 => attributes.flags.italic = true,
                4 => attributes.flags.underline = true,
                5 => attributes.flags.blink = true,
                7 => attributes.flags.reverse = true,
                8 => attributes.flags.hidden = true,
                9 => attributes.flags.strike = true,
                22 => {
                    attributes.flags.bold = false;
                    attributes.flags.dim = false;
                },
                23 => attributes.flags.italic = false,
                24 => attributes.flags.underline = false,
                25 => attributes.flags.blink = false,
                27 => attributes.flags.reverse = false,
                28 => attributes.flags.hidden = false,
                29 => attributes.flags.strike = false,
                30...37 => attributes.foreground = Color{ .palette = @intCast(value - 30) },
                90...97 => attributes.foreground = Color{ .palette = @intCast(value - 82) },
                40...47 => attributes.background = Color{ .palette = @intCast(value - 40) },
                100...107 => attributes.background = Color{ .palette = @intCast(value - 92) },
                39 => attributes.foreground = null,
                49 => attributes.background = null,
                38, 48 => {
                    const color, const used = try extendedColor(values[index + 1 ..]);
                    if (value == 38) {
                        attributes.foreground = color;
                    } else {
                        attributes.background = color;
                    }
                    index += used;
                },
                else => return error.Unsupported,
            }
        }
        self.attributes = attributes;
    }

    fn setAnsiModes(self: *Terminal, params: []const usize, enabled: bool) Ignored!void {
        const values = paramsOrZero(params);
        for (values) |value| {
            if (ansiMode(value) == null) return error.Unsupported;
        }
        for (values) |value| self.modes.set(ansiMode(value).?, enabled);
    }

    fn setDecModes(self: *Terminal, params: []const usize, enabled: bool) Ignored!void {
        const values = paramsOrZero(params);
        for (values) |value| {
            if (!isDecModeNumber(value)) return error.Unsupported;
        }
        for (values) |value| {
            if (decMode(value)) |mode| {
                self.setDecFlag(mode, enabled);
            } else if (value == 1048) {
                if (enabled) self.saveCursor() else self.restoreCursor();
            } else {
                self.switchScreen(value, enabled);
            }
        }
    }

    fn setDecFlag(self: *Terminal, mode: Mode, enabled: bool) void {
        if (mode == .decom or (mode == .decawm and !enabled)) self.pending_wrap = false;
        self.modes.set(mode, enabled);
        if (mode == .decom) self.home();
    }

    fn switchScreen(self: *Terminal, value: usize, enabled: bool) void {
        self.pending_wrap = false;
        if (enabled and self.display == .main) {
            if (value == 1049) self.saveCursor();
            self.display = .alternate;
            if (value == 1049) self.displayedScreen().clear();
        } else if (!enabled and self.display == .alternate) {
            if (value == 1047) self.displayedScreen().clear();
            self.display = .main;
            if (value == 1049) self.restoreCursor();
        }
    }

    fn setScrollRegion(self: *Terminal, params: []const usize) Ignored!void {
        const top = amount(params);
        const second = parameter(params, 1);
        const bottom = @min(if (second == 0) self.height else second, self.height);
        if (top >= bottom) return error.Invalid;
        self.pending_wrap = false;
        self.top = top;
        self.bottom = bottom;
        self.home();
    }

    fn softReset(self: *Terminal) void {
        self.pending_wrap = false;
        for (soft_reset_modes) |mode| self.modes.set(mode, initial_modes.get(mode));
        self.top = 1;
        self.bottom = self.height;
        self.attributes = .{};
        self.g0 = .ascii;
        self.g1 = .ascii;
        self.gl = .g0;
        self.saved[@backingInt(self.display)] = null;
    }

    fn reply(self: *Terminal, comptime format: []const u8, args: anytype) std.Io.Writer.Error!void {
        self.replies += 1;
        try self.out.print("REPLY " ++ format ++ "\n", args);
    }

    fn reportedRow(self: *const Terminal) usize {
        if (self.modes.get(.decom)) return @max((self.row + 1) -| self.top, 1);
        return self.row;
    }

    fn requestAnsiMode(self: *Terminal, number: usize) std.Io.Writer.Error!void {
        const state: usize = if (ansiMode(number)) |mode| modeState(self.modes.get(mode)) else 0;
        try self.reply("^[[{d};{d}$y", .{ number, state });
    }

    fn requestDecMode(self: *Terminal, number: usize) std.Io.Writer.Error!void {
        const state: usize = if (decMode(number)) |mode|
            modeState(self.modes.get(mode))
        else if (number == 47 or number == 1047 or number == 1049)
            modeState(self.display == .alternate)
        else
            0;
        try self.reply("^[[?{d};{d}$y", .{ number, state });
    }

    fn pressKey(self: *Terminal, name: []const u8) std.Io.Writer.Error!void {
        const out = self.out;
        try out.print("KEY {s} ", .{name});
        const enter: []const u8 = if (self.modes.get(.lnm)) "^M^J" else "^M";
        if (cursor_keys.get(name)) |final| {
            const prefix: []const u8 = if (self.modes.get(.decckm)) "^[O" else "^[[";
            try out.print("{s}{c}", .{ prefix, final });
        } else if (fixed_keys.get(name)) |sequence| {
            try out.writeAll(sequence);
        } else if (std.mem.eql(u8, name, "ENTER")) {
            try out.writeAll(enter);
        } else if (std.mem.eql(u8, name, "KPENTER")) {
            try out.writeAll(if (self.modes.get(.deckpam)) "^[OM" else enter);
        } else if (self.modes.get(.deckpam)) {
            try out.print("^[O{c}", .{0x70 + (name[2] - '0')});
        } else {
            try out.writeByte(name[2]);
        }
        try out.writeByte('\n');
    }

    fn paste(self: *Terminal, text: []const u8) std.Io.Writer.Error!void {
        const out = self.out;
        const bracketed = self.modes.get(.bracketed);
        try out.writeAll("PASTE ");
        if (bracketed) try out.writeAll("^[[200~");
        for (text) |char| {
            if (char == '^') {
                try out.writeAll("^^");
            } else {
                try out.writeByte(char);
            }
        }
        if (bracketed) try out.writeAll("^[[201~");
        try out.writeByte('\n');
    }

    fn writeScreen(self: *Terminal) std.Io.Writer.Error!void {
        const out = self.out;
        const name: []const u8 = if (self.display == .alternate) "alt" else "main";
        try out.print(" {s} cursor {d},{d} scrollback {d}", .{
            name,
            self.row,
            self.column,
            self.scrollback_len,
        });
        if (self.pending_wrap) try out.writeAll(" pending");
        try out.writeByte('\n');
        for (self.displayedScreen().rows[0..self.height]) |*row| {
            const line = rowText(row[0..self.width]);
            try out.print("|{s}\n", .{line.text()});
        }
    }

    fn dump(self: *Terminal) std.Io.Writer.Error!void {
        self.dumps += 1;
        try self.out.print("DUMP {d}", .{self.dumps});
        try self.writeScreen();
    }

    fn writeChangedModes(self: *const Terminal, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (std.enums.values(Mode)) |mode| {
            const enabled = self.modes.get(mode);
            if (enabled == initial_modes.get(mode)) continue;
            var name: [16]u8 = undefined;
            const state: []const u8 = if (enabled) "on" else "off";
            try writer.print(" {s}={s}", .{ std.ascii.upperString(&name, @tagName(mode)), state });
        }
        if (self.g0 == .line_drawing) try writer.writeAll(" G0=graphics");
        if (self.g1 == .line_drawing) try writer.writeAll(" G1=graphics");
        if (self.gl == .g1) try writer.writeAll(" GL=G1");
        if (self.cursor_shape != 1) try writer.print(" CURSOR={d}", .{self.cursor_shape});
    }

    fn attributeRuns(self: *Terminal) std.mem.Allocator.Error!std.ArrayList(Run) {
        var runs: std.ArrayList(Run) = .empty;
        errdefer runs.deinit(self.gpa);
        for (self.displayedScreen().rows[0..self.height], 1..) |*cells, row| {
            var start: usize = 0;
            for (1..self.width + 1) |column| {
                const current = cells[start].attributes;
                const same = column < self.width and std.meta.eql(cells[column].attributes, current);
                if (same) continue;
                if (!current.isDefault()) {
                    try runs.append(self.gpa, .{
                        .row = row,
                        .first = start + 1,
                        .last = column,
                        .attributes = current,
                    });
                }
                start = column;
            }
        }
        return runs;
    }

    fn finish(self: *Terminal) Error!void {
        if (self.state != .ground) {
            self.ignored.canceled += 1;
            self.state = .ground;
        }
        const out = self.out;
        try out.writeAll("FINAL");
        try self.writeScreen();
        if (self.title) |title| {
            try out.print("TITLE \"{s}\"\n", .{title});
        } else {
            try out.writeAll("TITLE none\n");
        }
        var buffer: [256]u8 = undefined;
        var changed: std.Io.Writer = .fixed(&buffer);
        try self.writeChangedModes(&changed);
        const modes: []const u8 = if (changed.end == 0) " default" else changed.buffered();
        try out.print("MODES{s}\n", .{modes});
        try out.print("REGION {d}-{d}\nTABS", .{ self.top, self.bottom });
        var separator: u8 = ' ';
        for (1..self.width + 1) |column| {
            if (self.tab_stops[column]) {
                try out.print("{c}{d}", .{ separator, column });
                separator = ',';
            }
        }
        if (separator == ' ') try out.writeAll(" none");
        try out.print("\nSCROLLBACK {d}\n", .{self.scrollback_len});
        const first_shown = self.scrollback_len -| scrollback_shown;
        for (self.scrollback[first_shown..self.scrollback_len]) |*line| {
            try out.print("|{s}\n", .{line.text()});
        }
        var runs = try self.attributeRuns();
        defer runs.deinit(self.gpa);
        try out.print("ATTRS {d}\n", .{runs.items.len});
        for (runs.items) |run| {
            try out.print("row {d} col {d}-{d}{f}\n", .{
                run.row,
                run.first,
                run.last,
                run.attributes,
            });
        }
        try out.print("BELL {d}\nREPLIES {d}\n", .{ self.bells, self.replies });
        try out.print("STATS bytes={d} printed={d} sequences={d}\n", .{
            self.stream_bytes,
            self.printed,
            self.sequences,
        });
        const ignored = self.ignored;
        try out.print("IGNORED {d} unsupported={d} malformed={d} canceled={d} invalid={d}\n", .{
            ignored.unsupported + ignored.malformed + ignored.canceled + ignored.invalid,
            ignored.unsupported,
            ignored.malformed,
            ignored.canceled,
            ignored.invalid,
        });
    }
};

pub fn main(init: std.process.Init) !void {
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const reader = &input.interface;
    const first = (try reader.takeDelimiter('\n')).?;
    var sizes = std.mem.splitScalar(u8, first, ' ');
    const width = try std.fmt.parseInt(usize, sizes.next().?, 10);
    const height = try std.fmt.parseInt(usize, sizes.next().?, 10);
    var terminal = Terminal.init(init.gpa, &output.interface, width, height);
    defer terminal.deinit();
    while (try reader.takeDelimiter('\n')) |line| {
        if (std.mem.eql(u8, line, "%%END")) break;
        if (std.mem.eql(u8, line, "%%DUMP")) {
            try terminal.dump();
        } else if (std.mem.startsWith(u8, line, "%%KEY ")) {
            try terminal.pressKey(line["%%KEY ".len..]);
        } else if (std.mem.startsWith(u8, line, "%%PASTE ")) {
            try terminal.paste(line["%%PASTE ".len..]);
        } else {
            var index: usize = 0;
            while (index < line.len) : (index += 1) {
                if (line[index] == '^') {
                    index += 1;
                    try terminal.receive(caretByte(line[index]));
                } else {
                    try terminal.receive(line[index]);
                }
            }
        }
    }
    try terminal.finish();
    try output.interface.flush();
}
