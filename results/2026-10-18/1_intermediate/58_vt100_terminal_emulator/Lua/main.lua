local flags = {"bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strike"}
local modeOrder = {
    "IRM",
    "LNM",
    "DECCKM",
    "DECSCNM",
    "DECOM",
    "DECAWM",
    "DECTCEM",
    "DECKPAM",
    "BRACKETED"
}
local initial = {
    IRM = false,
    LNM = false,
    DECCKM = false,
    DECSCNM = false,
    DECOM = false,
    DECAWM = true,
    DECTCEM = true,
    DECKPAM = false,
    BRACKETED = false
}
local ansi = {[4] = "IRM", [20] = "LNM"}
local dec = {
    [1] = "DECCKM",
    [5] = "DECSCNM",
    [6] = "DECOM",
    [7] = "DECAWM",
    [25] = "DECTCEM",
    [2004] = "BRACKETED"
}
local default = {0, "default", "default"}
local function clone(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = clone(item)
    end
    return result
end
local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end
local function output(text)
    io.write(text, "\n")
end
local function attrsEqual(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
local Terminal = {}
Terminal.__index = Terminal
function Terminal.new(width, height)
    local self =
        setmetatable(
        {
            w = width,
            h = height,
            bytes = 0,
            printed = 0,
            sequences = 0,
            bell = 0,
            replies = 0,
            dumps = 0,
            ignored = {unsupported = 0, malformed = 0, canceled = 0, invalid = 0}
        },
        Terminal
    )
    self:reset()
    return self
end
function Terminal:blankRow()
    local row = {}
    for c = 1, self.w do
        row[c] = {" ", default}
    end
    return row
end
function Terminal:blankScreen()
    local screen = {}
    for r = 1, self.h do
        screen[r] = self:blankRow()
    end
    return screen
end
function Terminal:parserStart(state)
    self.parser = state
    self.private, self.params, self.intermediate, self.osc = "", "", "", ""
end
function Terminal:reset()
    self.screens = {self:blankScreen(), self:blankScreen()}
    self.screen = 1
    self.row, self.col, self.top, self.bottom = 1, 1, 1, self.h
    self.pending = false
    self.attrs = clone(default)
    self.g0, self.g1, self.gl = 0, 0, 0
    self.modes = clone(initial)
    self.shape = 1
    self.tabs = {}
    for c = 9, self.w, 8 do
        self.tabs[c] = true
    end
    self.saves = {}
    self.scrollback = {}
    self.title, self.last = nil, nil
    self:parserStart("ground")
end
function Terminal:grid()
    return self.screens[self.screen]
end
function Terminal:rowText(cells)
    local result = {}
    for c = 1, self.w do
        result[c] = cells[c][1]
    end
    return (table.concat(result):gsub(" +$", ""))
end
function Terminal:scroll(up, count)
    local grid = self:grid()
    for _ = 1, count or 1 do
        if up then
            local removed = table.remove(grid, self.top)
            table.insert(grid, self.bottom, self:blankRow())
            if self.screen == 1 and self.top == 1 then
                self.scrollback[#self.scrollback + 1] = self:rowText(removed)
                if #self.scrollback > 100 then
                    table.remove(self.scrollback, 1)
                end
            end
        else
            table.remove(grid, self.bottom)
            table.insert(grid, self.top, self:blankRow())
        end
    end
end
function Terminal:lineFeed()
    if self.row == self.bottom then
        self:scroll(true)
    elseif self.row < self.h then
        self.row = self.row + 1
    end
end
function Terminal:reverseFeed()
    if self.row == self.top then
        self:scroll(false)
    elseif self.row > 1 then
        self.row = self.row - 1
    end
end
function Terminal:tab(reverse)
    local result = reverse and 1 or self.w
    if reverse then
        for c = 1, self.col - 1 do
            if self.tabs[c] then
                result = c
            end
        end
    else
        for c = self.col + 1, self.w do
            if self.tabs[c] then
                result = c
                break
            end
        end
    end
    self.col = result
end
function Terminal:address(value)
    if self.modes.DECOM then
        return math.min(self.top + value - 1, self.bottom)
    end
    return math.min(value, self.h)
end
function Terminal:home()
    self.row, self.col = self:address(1), 1
end
function Terminal:save()
    self.saves[self.screen] = {
        self.row,
        self.col,
        clone(self.attrs),
        self.modes.DECOM,
        self.g0,
        self.g1,
        self.gl
    }
end
function Terminal:restore()
    local saved = self.saves[self.screen]
    if saved then
        self.row, self.col, self.attrs, self.modes.DECOM, self.g0, self.g1, self.gl =
            saved[1],
            saved[2],
            clone(saved[3]),
            saved[4],
            saved[5],
            saved[6],
            saved[7]
    else
        self.row, self.col = 1, 1
        self.attrs = clone(default)
        self.modes.DECOM = false
        self.g0, self.g1, self.gl = 0, 0, 0
    end
    self.pending = false
end
function Terminal:write(char)
    self.printed = self.printed + 1
    self.last = char
    if self.pending then
        self.pending = false
        self.col = 1
        self:lineFeed()
    end
    local cells = self:grid()[self.row]
    if self.modes.IRM then
        table.insert(cells, self.col, {" ", default})
        table.remove(cells)
    end
    cells[self.col] = {char, clone(self.attrs)}
    if self.col < self.w then
        self.col = self.col + 1
    elseif self.modes.DECAWM then
        self.pending = true
    end
end
function Terminal:printChar(char)
    if (self.gl == 0 and self.g0 or self.g1) == 1 then
        local map = {
            ["`"] = "*",
            a = "#",
            j = "+",
            k = "+",
            l = "+",
            m = "+",
            n = "+",
            t = "+",
            u = "+",
            v = "+",
            w = "+",
            q = "-",
            x = "|",
            ["~"] = "o"
        }
        char = map[char] or char
    end
    self:write(char)
end
function Terminal:control(code)
    if contains({8, 9, 10, 11, 12, 13}, code) then
        self.pending = false
    end
    if code == 7 then
        self.bell = self.bell + 1
    elseif code == 8 then
        self.col = math.max(1, self.col - 1)
    elseif code == 9 then
        self:tab()
    elseif code == 10 or code == 11 or code == 12 then
        self:lineFeed()
        if self.modes.LNM then
            self.col = 1
        end
    elseif code == 13 then
        self.col = 1
    elseif code == 14 then
        self.gl = 1
    elseif code == 15 then
        self.gl = 0
    end
end
function Terminal:escape(key)
    local known = {"7", "8", "D", "E", "M", "H", "c", "=", ">", "\\", "(0", "(B", ")0", ")B", "#8"}
    if not contains(known, key) then
        return "unsupported"
    end
    if contains({"D", "E", "M", "c", "#8"}, key) then
        self.pending = false
    end
    if key == "7" then
        self:save()
    elseif key == "8" then
        self:restore()
    elseif key == "D" then
        self:lineFeed()
    elseif key == "E" then
        self.col = 1
        self:lineFeed()
    elseif key == "M" then
        self:reverseFeed()
    elseif key == "H" then
        self.tabs[self.col] = true
    elseif key == "c" then
        self:reset()
    elseif key == "=" then
        self.modes.DECKPAM = true
    elseif key == ">" then
        self.modes.DECKPAM = false
    elseif key == "(0" then
        self.g0 = 1
    elseif key == "(B" then
        self.g0 = 0
    elseif key == ")0" then
        self.g1 = 1
    elseif key == ")B" then
        self.g1 = 0
    elseif key == "#8" then
        local grid = {}
        for r = 1, self.h do
            grid[r] = {}
            for c = 1, self.w do
                grid[r][c] = {"E", default}
            end
        end
        self.screens[self.screen] = grid
        self.top, self.bottom = 1, self.h
        self.modes.DECOM = false
        self.row, self.col = 1, 1
    end
end
function Terminal:palette(number)
    local colors = {"black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"}
    if number < 8 then
        return colors[number + 1]
    end
    if number < 16 then
        return "bright-" .. colors[number - 7]
    end
    return tostring(number)
end
function Terminal:sgr(params)
    if #params == 0 then
        params = {0}
    end
    local attrs = clone(self.attrs)
    local on = {[1] = 0, [2] = 1, [3] = 2, [4] = 3, [5] = 4, [7] = 5, [8] = 6, [9] = 7}
    local off = {[23] = 2, [24] = 3, [25] = 4, [27] = 5, [28] = 6, [29] = 7}
    local i = 1
    while i <= #params do
        local value = params[i]
        if value == 0 then
            attrs = clone(default)
        elseif on[value] ~= nil then
            attrs[1] = attrs[1] | (1 << on[value])
        elseif value == 22 then
            attrs[1] = attrs[1] & (~3)
        elseif off[value] ~= nil then
            attrs[1] = attrs[1] & (~(1 << off[value]))
        elseif value >= 30 and value <= 37 then
            attrs[2] = self:palette(value - 30)
        elseif value >= 90 and value <= 97 then
            attrs[2] = self:palette(value - 82)
        elseif value >= 40 and value <= 47 then
            attrs[3] = self:palette(value - 40)
        elseif value >= 100 and value <= 107 then
            attrs[3] = self:palette(value - 92)
        elseif value == 39 or value == 49 then
            attrs[value == 39 and 2 or 3] = "default"
        elseif value == 38 or value == 48 then
            local color
            if params[i + 1] == 5 and params[i + 2] and params[i + 2] <= 255 then
                color = self:palette(params[i + 2])
                i = i + 2
            elseif
                params[i + 1] == 2 and params[i + 4] and params[i + 2] <= 255 and
                    params[i + 3] <= 255 and
                    params[i + 4] <= 255
             then
                color = string.format("#%02x%02x%02x", params[i + 2], params[i + 3], params[i + 4])
                i = i + 4
            end
            if not color then
                return "unsupported"
            end
            attrs[value == 38 and 2 or 3] = color
        else
            return "unsupported"
        end
        i = i + 1
    end
    self.attrs = attrs
end
function Terminal:setModes(key, params)
    if #params == 0 then
        params = {0}
    end
    local private = key:sub(1, 1) == "?"
    local allowed = private and {1, 5, 6, 7, 25, 47, 1047, 1048, 1049, 2004} or {4, 20}
    for _, p in ipairs(params) do
        if not contains(allowed, p) then
            return "unsupported"
        end
    end
    local setting = key:sub(-1) == "h"
    for _, p in ipairs(params) do
        if not private then
            self.modes[ansi[p]] = setting
        elseif p == 6 then
            self.pending = false
            self.modes.DECOM = setting
            self:home()
        elseif p == 47 or p == 1047 or p == 1049 then
            self.pending = false
            local target = setting and 2 or 1
            if self.screen ~= target then
                if setting and p == 1049 then
                    self:save()
                end
                if not setting and p == 1047 then
                    self.screens[2] = self:blankScreen()
                end
                self.screen = target
                if setting and p == 1049 then
                    self.screens[2] = self:blankScreen()
                end
                if not setting and p == 1049 then
                    self:restore()
                end
            end
        elseif p == 1048 then
            if setting then
                self:save()
            else
                self:restore()
            end
        else
            if p == 7 and not setting then
                self.pending = false
            end
            self.modes[dec[p]] = setting
        end
    end
end
function Terminal:erase(row, first, last)
    for c = first, last do
        self:grid()[row][c] = {" ", default}
    end
end
function Terminal:reply(text)
    self.replies = self.replies + 1
    output("REPLY " .. text)
end
function Terminal:csi(final)
    local params = {}
    if self.params ~= "" then
        for field in (self.params .. ";"):gmatch("(.-);") do
            local value = 0
            for i = 1, #field do
                value = math.min(9999, value * 10 + field:byte(i) - 48)
            end
            params[#params + 1] = value
        end
    end
    if #params > 16 then
        return "invalid"
    end
    local p1, p2 = params[1] or 0, params[2] or 0
    local n = math.max(p1, 1)
    local key = self.private .. self.intermediate .. final
    local known = {
        "A",
        "B",
        "e",
        "C",
        "a",
        "D",
        "E",
        "F",
        "G",
        "`",
        "H",
        "f",
        "d",
        "I",
        "Z",
        "J",
        "K",
        "X",
        "@",
        "P",
        "L",
        "M",
        "S",
        "T",
        "b",
        "g",
        "m",
        "h",
        "l",
        "?h",
        "?l",
        " q",
        "r",
        "s",
        "u",
        "!p",
        "n",
        "?n",
        "c",
        ">c",
        "t",
        "$p",
        "?$p"
    }
    if not contains(known, key) then
        return "unsupported"
    end
    local bad =
        (key == "J" and p1 > 3) or (key == "K" and p1 > 2) or (key == "g" and p1 ~= 0 and p1 ~= 3) or
        (key == " q" and p1 > 6) or
        (key == "n" and p1 ~= 5 and p1 ~= 6) or
        (key == "?n" and p1 ~= 6) or
        ((key == "c" or key == ">c") and p1 ~= 0) or
        (key == "t" and p1 ~= 18)
    if bad then
        return "unsupported"
    end
    if key == "m" then
        return self:sgr(params)
    end
    if contains({"h", "l", "?h", "?l"}, key) then
        return self:setModes(key, params)
    end
    if key == "r" then
        local top = p1 == 0 and 1 or p1
        local bottom = math.min(p2 == 0 and self.h or p2, self.h)
        if top >= bottom then
            return "invalid"
        end
        self.pending = false
        self.top, self.bottom = top, bottom
        self:home()
        return
    end
    if
        contains(
            {
                "A",
                "B",
                "C",
                "D",
                "E",
                "F",
                "G",
                "H",
                "I",
                "J",
                "K",
                "L",
                "M",
                "P",
                "S",
                "T",
                "X",
                "Z",
                "`",
                "a",
                "d",
                "e",
                "f",
                "@",
                "!p"
            },
            key
        )
     then
        self.pending = false
    end
    if key == "A" or key == "F" then
        self.row = math.max(self.row - n, self.row >= self.top and self.top or 1)
        if key == "F" then
            self.col = 1
        end
    elseif key == "B" or key == "e" or key == "E" then
        self.row = math.min(self.row + n, self.row <= self.bottom and self.bottom or self.h)
        if key == "E" then
            self.col = 1
        end
    elseif key == "C" or key == "a" then
        self.col = math.min(self.col + n, self.w)
    elseif key == "D" then
        self.col = math.max(1, self.col - n)
    elseif key == "G" or key == "`" then
        self.col = math.min(n, self.w)
    elseif key == "H" or key == "f" then
        self.row, self.col = self:address(n), math.min(math.max(p2, 1), self.w)
    elseif key == "d" then
        self.row = self:address(n)
    elseif key == "I" or key == "Z" then
        for _ = 1, n do
            self:tab(key == "Z")
        end
    elseif key == "J" then
        if p1 == 3 then
            self.scrollback = {}
        else
            for r = 1, self.h do
                for c = 1, self.w do
                    local position = (r - 1) * self.w + c
                    local cursor = (self.row - 1) * self.w + self.col
                    if p1 == 2 or p1 == 0 and position >= cursor or p1 == 1 and position <= cursor then
                        self:erase(r, c, c)
                    end
                end
            end
        end
    elseif key == "K" then
        self:erase(self.row, p1 == 0 and self.col or 1, p1 == 1 and self.col or self.w)
    elseif key == "X" then
        self:erase(self.row, self.col, math.min(self.col + n - 1, self.w))
    elseif key == "@" or key == "P" then
        local cells = self:grid()[self.row]
        local k = math.min(n, self.w - self.col + 1)
        for _ = 1, k do
            if key == "@" then
                table.insert(cells, self.col, {" ", default})
                table.remove(cells)
            else
                table.remove(cells, self.col)
                cells[#cells + 1] = {" ", default}
            end
        end
    elseif key == "L" or key == "M" then
        if self.row >= self.top and self.row <= self.bottom then
            local grid = self:grid()
            for _ = 1, math.min(n, self.bottom - self.row + 1) do
                if key == "L" then
                    table.remove(grid, self.bottom)
                    table.insert(grid, self.row, self:blankRow())
                else
                    table.remove(grid, self.row)
                    table.insert(grid, self.bottom, self:blankRow())
                end
            end
            self.col = 1
        end
    elseif key == "S" or key == "T" then
        self:scroll(key == "S", math.min(n, self.bottom - self.top + 1))
    elseif key == "b" then
        if self.last then
            for _ = 1, n do
                self:write(self.last)
            end
        end
    elseif key == "g" then
        if p1 == 3 then
            self.tabs = {}
        else
            self.tabs[self.col] = nil
        end
    elseif key == " q" then
        self.shape = n
    elseif key == "s" then
        self:save()
    elseif key == "u" then
        self:restore()
    elseif key == "!p" then
        for _, mode in ipairs({"IRM", "DECCKM", "DECOM", "DECAWM", "DECTCEM", "DECKPAM"}) do
            self.modes[mode] = initial[mode]
        end
        self.top, self.bottom = 1, self.h
        self.attrs = clone(default)
        self.g0, self.g1, self.gl = 0, 0, 0
        self.saves[self.screen] = nil
    elseif key == "n" then
        local r = self.modes.DECOM and math.max(1, self.row - self.top + 1) or self.row
        self:reply(p1 == 5 and "^[[0n" or "^[[" .. r .. ";" .. self.col .. "R")
    elseif key == "?n" then
        local r = self.modes.DECOM and math.max(1, self.row - self.top + 1) or self.row
        self:reply("^[[?" .. r .. ";" .. self.col .. ";1R")
    elseif key == "c" then
        self:reply("^[[?1;2c")
    elseif key == ">c" then
        self:reply("^[[>0;95;0c")
    elseif key == "t" then
        self:reply("^[[8;" .. self.h .. ";" .. self.w .. "t")
    elseif key == "$p" or key == "?$p" then
        local mode
        if key == "$p" then
            mode = ansi[p1]
        else
            mode = dec[p1]
        end
        local status = mode and (self.modes[mode] and 1 or 2) or 0
        if key == "?$p" and contains({47, 1047, 1049}, p1) then
            status = self.screen == 2 and 1 or 2
        end
        self:reply("^[[" .. (key == "?$p" and "?" or "") .. p1 .. ";" .. status .. "$y")
    end
end
function Terminal:finishSequence(reason)
    if reason then
        self.ignored[reason] = self.ignored[reason] + 1
    else
        self.sequences = self.sequences + 1
    end
end
function Terminal:executeOsc()
    if self.osc:sub(1, 2) == "0;" or self.osc:sub(1, 2) == "2;" then
        self.title = self.osc:sub(3)
        self:finishSequence()
    else
        self:finishSequence("unsupported")
    end
end
function Terminal:byte(code)
    self.bytes = self.bytes + 1
    if code == 27 then
        if self.parser == "osc" then
            self:executeOsc()
        elseif self.parser ~= "ground" then
            self.ignored.canceled = self.ignored.canceled + 1
        end
        self:parserStart("escape")
        return
    end
    if code == 24 or code == 26 then
        if self.parser ~= "ground" then
            self.ignored.canceled = self.ignored.canceled + 1
            self.parser = "ground"
        end
        return
    end
    if code < 32 then
        if self.parser == "osc" then
            if code == 7 then
                self:executeOsc()
                self.parser = "ground"
            end
        else
            self:control(code)
        end
        return
    end
    local char = string.char(code)
    local intermediate = code >= 32 and code <= 47
    local final = code >= 64
    if self.parser == "ground" then
        self:printChar(char)
    elseif self.parser == "escape" then
        if intermediate then
            self.intermediate = self.intermediate .. char
            self.parser = "escape intermediate"
        elseif char == "[" then
            self.parser = "entry"
        elseif char == "]" then
            self.parser = "osc"
        else
            self:finishSequence(self:escape(self.intermediate .. char))
            self.parser = "ground"
        end
    elseif self.parser == "escape intermediate" then
        if intermediate then
            self.intermediate = self.intermediate .. char
        else
            self:finishSequence(self:escape(self.intermediate .. char))
            self.parser = "ground"
        end
    elseif self.parser == "entry" or self.parser == "param" then
        if self.parser == "entry" and code >= 60 and code <= 63 then
            self.private = char
            self.parser = "param"
        elseif code >= 48 and code <= 57 or char == ";" then
            self.params = self.params .. char
            self.parser = "param"
        elseif intermediate then
            self.intermediate = self.intermediate .. char
            self.parser = "csi intermediate"
        elseif final then
            self:finishSequence(self:csi(char))
            self.parser = "ground"
        else
            self.parser = "ignore"
        end
    elseif self.parser == "csi intermediate" then
        if intermediate then
            self.intermediate = self.intermediate .. char
        elseif final then
            self:finishSequence(self:csi(char))
            self.parser = "ground"
        else
            self.parser = "ignore"
        end
    elseif self.parser == "ignore" then
        if final then
            self.ignored.malformed = self.ignored.malformed + 1
            self.parser = "ground"
        end
    elseif self.parser == "osc" then
        self.osc = self.osc .. char
    end
end
function Terminal:dump(label)
    output(
        label ..
            " " ..
                (self.screen == 1 and "main" or "alt") ..
                    " cursor " ..
                        self.row ..
                            "," ..
                                self.col ..
                                    " scrollback " ..
                                        #self.scrollback .. (self.pending and " pending" or "")
    )
    for _, cells in ipairs(self:grid()) do
        output("|" .. self:rowText(cells))
    end
end
function Terminal:key(name)
    local arrows = {UP = "A", DOWN = "B", RIGHT = "C", LEFT = "D", HOME = "H", END = "F"}
    local fixed = {
        INSERT = "^[[2~",
        DELETE = "^[[3~",
        PAGEUP = "^[[5~",
        PAGEDOWN = "^[[6~",
        F1 = "^[OP",
        F2 = "^[OQ",
        F3 = "^[OR",
        F4 = "^[OS",
        F5 = "^[[15~",
        F6 = "^[[17~",
        F7 = "^[[18~",
        F8 = "^[[19~",
        F9 = "^[[20~",
        F10 = "^[[21~",
        F11 = "^[[23~",
        F12 = "^[[24~",
        TAB = "^I",
        BACKSPACE = "^?",
        ESCAPE = "^["
    }
    local enter = self.modes.LNM and "^M^J" or "^M"
    local text
    if arrows[name] then
        text = (self.modes.DECCKM and "^[O" or "^[[") .. arrows[name]
    elseif name == "ENTER" then
        text = enter
    elseif name == "KPENTER" then
        text = self.modes.DECKPAM and "^[OM" or enter
    elseif name:match("^KP%d$") then
        text =
            self.modes.DECKPAM and "^[O" .. string.char(112 + tonumber(name:sub(3))) or name:sub(3)
    else
        text = fixed[name]
    end
    output("KEY " .. name .. " " .. text)
end
function Terminal:finish()
    if self.parser ~= "ground" then
        self.ignored.canceled = self.ignored.canceled + 1
    end
    self:dump("FINAL")
    output(self.title ~= nil and 'TITLE "' .. self.title .. '"' or "TITLE none")
    local modes = {}
    for _, name in ipairs(modeOrder) do
        if self.modes[name] ~= initial[name] then
            modes[#modes + 1] = name .. "=" .. (self.modes[name] and "on" or "off")
        end
    end
    if self.g0 == 1 then
        modes[#modes + 1] = "G0=graphics"
    end
    if self.g1 == 1 then
        modes[#modes + 1] = "G1=graphics"
    end
    if self.gl == 1 then
        modes[#modes + 1] = "GL=G1"
    end
    if self.shape ~= 1 then
        modes[#modes + 1] = "CURSOR=" .. self.shape
    end
    output("MODES " .. (#modes == 0 and "default" or table.concat(modes, " ")))
    output("REGION " .. self.top .. "-" .. self.bottom)
    local tabs = {}
    for c = 1, self.w do
        if self.tabs[c] then
            tabs[#tabs + 1] = tostring(c)
        end
    end
    output("TABS " .. (#tabs == 0 and "none" or table.concat(tabs, ",")))
    output("SCROLLBACK " .. #self.scrollback)
    for i = math.max(1, #self.scrollback - 4), #self.scrollback do
        output("|" .. self.scrollback[i])
    end
    local runs = {}
    for r, cells in ipairs(self:grid()) do
        local c = 1
        while c <= self.w do
            local attrs = cells[c][2]
            local last = c
            while last + 1 <= self.w and attrsEqual(cells[last + 1][2], attrs) do
                last = last + 1
            end
            if not attrsEqual(attrs, default) then
                local names = {}
                for i, name in ipairs(flags) do
                    if (attrs[1] & (1 << (i - 1))) ~= 0 then
                        names[#names + 1] = name
                    end
                end
                if attrs[2] ~= "default" then
                    names[#names + 1] = "fg=" .. attrs[2]
                end
                if attrs[3] ~= "default" then
                    names[#names + 1] = "bg=" .. attrs[3]
                end
                runs[#runs + 1] =
                    "row " .. r .. " col " .. c .. "-" .. last .. " " .. table.concat(names, " ")
            end
            c = last + 1
        end
    end
    output("ATTRS " .. #runs)
    for _, line in ipairs(runs) do
        output(line)
    end
    output("BELL " .. self.bell)
    output("REPLIES " .. self.replies)
    output(
        "STATS bytes=" ..
            self.bytes .. " printed=" .. self.printed .. " sequences=" .. self.sequences
    )
    local total, parts = 0, {}
    for _, name in ipairs({"unsupported", "malformed", "canceled", "invalid"}) do
        total = total + self.ignored[name]
        parts[#parts + 1] = name .. "=" .. self.ignored[name]
    end
    output("IGNORED " .. total .. " " .. table.concat(parts, " "))
end
function Terminal:line(text)
    if text == "%%END" then
        self:finish()
    elseif text == "%%DUMP" then
        self.dumps = self.dumps + 1
        self:dump("DUMP " .. self.dumps)
    elseif text:sub(1, 6) == "%%KEY " then
        self:key(text:sub(7))
    elseif text:sub(1, 8) == "%%PASTE " then
        local pasted = text:sub(9):gsub("%^", "^^")
        if self.modes.BRACKETED then
            pasted = "^[[200~" .. pasted .. "^[[201~"
        end
        output("PASTE " .. pasted)
    else
        local codes = {
            ["@"] = 0,
            G = 7,
            H = 8,
            I = 9,
            J = 10,
            K = 11,
            L = 12,
            M = 13,
            N = 14,
            O = 15,
            X = 24,
            Z = 26,
            ["["] = 27,
            ["^"] = 94
        }
        local i = 1
        while i <= #text do
            if text:sub(i, i) == "^" then
                self:byte(codes[text:sub(i + 1, i + 1)])
                i = i + 2
            else
                self:byte(text:byte(i))
                i = i + 1
            end
        end
    end
end
local width, height = io.read():match("^(%d+) (%d+)$")
local terminal = Terminal.new(tonumber(width), tonumber(height))
for line in io.lines() do
    terminal:line((line:gsub("\r$", "")))
end
