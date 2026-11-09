import { readFileSync, writeFileSync } from "node:fs";

const flagNames = ["bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strike"];
const modeNames = [
    "IRM",
    "LNM",
    "DECCKM",
    "DECSCNM",
    "DECOM",
    "DECAWM",
    "DECTCEM",
    "DECKPAM",
    "BRACKETED",
];
const defaultModes = () => ({
    IRM: false,
    LNM: false,
    DECCKM: false,
    DECSCNM: false,
    DECOM: false,
    DECAWM: true,
    DECTCEM: true,
    DECKPAM: false,
    BRACKETED: false,
});
const defaultAttrs = () => ({ flags: Array(8).fill(false), fg: "default", bg: "default" });
const copyAttrs = (a) => ({ flags: a.flags.slice(), fg: a.fg, bg: a.bg });
const equalAttrs = (a, b) =>
    a.fg === b.fg && a.bg === b.bg && a.flags.every((v, i) => v === b.flags[i]);
const emit = (s) => writeFileSync(1, s + "\n");
function palette(n) {
    const colors = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];
    return n < 8 ? colors[n] : n < 16 ? "bright-" + colors[n - 8] : String(n);
}
class Terminal {
    screens = [];
    alt = 0;
    row = 1;
    col = 1;
    pending = false;
    attrs = defaultAttrs();
    modes = defaultModes();
    g0 = false;
    g1 = false;
    gl = 0;
    shape = 1;
    top = 1;
    bottom;
    tabs = new Set();
    saved = [null, null];
    scrollback = [];
    title = null;
    last = null;
    state = "ground";
    privateMarker = "";
    params = "";
    intermediate = "";
    osc = "";
    bytes = 0;
    printed = 0;
    sequences = 0;
    bell = 0;
    replies = 0;
    dumps = 0;
    ignored = { unsupported: 0, malformed: 0, canceled: 0, invalid: 0 };
    constructor(width, height) {
        this.width = width;
        this.height = height;
        this.bottom = height;
        this.reset();
    }
    blank() {
        return { char: " ", attrs: defaultAttrs() };
    }
    blankRow() {
        return Array.from({ length: this.width }, () => this.blank());
    }
    blankScreen() {
        return Array.from({ length: this.height }, () => this.blankRow());
    }
    screen() {
        return this.screens[this.alt];
    }
    rowText(row) {
        return row
            .map((c) => c.char)
            .join("")
            .replace(/ +$/, "");
    }
    reset() {
        this.screens = [this.blankScreen(), this.blankScreen()];
        this.alt = 0;
        this.row = this.col = 1;
        this.pending = false;
        this.attrs = defaultAttrs();
        this.modes = defaultModes();
        this.g0 = this.g1 = false;
        this.gl = 0;
        this.shape = 1;
        this.top = 1;
        this.bottom = this.height;
        this.tabs = new Set();
        for (let c = 9; c <= this.width; c += 8) this.tabs.add(c);
        this.saved = [null, null];
        this.scrollback = [];
        this.title = null;
        this.last = null;
        this.state = "ground";
        this.privateMarker = this.params = this.intermediate = this.osc = "";
    }
    scroll(up, count = 1) {
        const screen = this.screen();
        for (let k = 0; k < count; k++) {
            if (up) {
                const removed = screen.splice(this.top - 1, 1)[0];
                screen.splice(this.bottom - 1, 0, this.blankRow());
                if (!this.alt && this.top === 1) {
                    this.scrollback.push(this.rowText(removed));
                    if (this.scrollback.length > 100) this.scrollback.shift();
                }
            } else {
                screen.splice(this.bottom - 1, 1);
                screen.splice(this.top - 1, 0, this.blankRow());
            }
        }
    }
    lineFeed() {
        if (this.row === this.bottom) this.scroll(true);
        else if (this.row < this.height) this.row++;
    }
    reverseFeed() {
        if (this.row === this.top) this.scroll(false);
        else if (this.row > 1) this.row--;
    }
    tab(reverse = false) {
        const stops = Array.from(this.tabs).sort((a, b) => a - b);
        if (reverse) this.col = stops.filter((c) => c < this.col).pop() ?? 1;
        else this.col = stops.find((c) => c > this.col) ?? this.width;
    }
    addressed(v) {
        return this.modes.DECOM
            ? Math.min(this.top + v - 1, this.bottom)
            : Math.min(v, this.height);
    }
    home() {
        this.row = this.addressed(1);
        this.col = 1;
    }
    save() {
        this.saved[this.alt] = {
            row: this.row,
            col: this.col,
            attrs: copyAttrs(this.attrs),
            origin: this.modes.DECOM,
            g0: this.g0,
            g1: this.g1,
            gl: this.gl,
        };
    }
    restore() {
        this.pending = false;
        const s = this.saved[this.alt];
        if (s) {
            this.row = s.row;
            this.col = s.col;
            this.attrs = copyAttrs(s.attrs);
            this.modes.DECOM = s.origin;
            this.g0 = s.g0;
            this.g1 = s.g1;
            this.gl = s.gl;
        } else {
            this.row = this.col = 1;
            this.attrs = defaultAttrs();
            this.modes.DECOM = false;
            this.g0 = this.g1 = false;
            this.gl = 0;
        }
    }
    write(char) {
        this.printed++;
        this.last = char;
        if (this.pending) {
            this.pending = false;
            this.col = 1;
            this.lineFeed();
        }
        const row = this.screen()[this.row - 1];
        if (this.modes.IRM) {
            row.splice(this.col - 1, 0, this.blank());
            row.pop();
        }
        row[this.col - 1] = { char, attrs: copyAttrs(this.attrs) };
        if (this.col < this.width) this.col++;
        else if (this.modes.DECAWM) this.pending = true;
    }
    print(char) {
        if (this.gl === 0 ? this.g0 : this.g1) {
            if (char === "`") char = "*";
            else if (char === "a") char = "#";
            else if ("jklmntuvw".includes(char)) char = "+";
            else if (char === "q") char = "-";
            else if (char === "x") char = "|";
            else if (char === "~") char = "o";
        }
        this.write(char);
    }
    control(n) {
        if ([8, 9, 10, 11, 12, 13].includes(n)) this.pending = false;
        if (n === 7) this.bell++;
        else if (n === 8) this.col = Math.max(this.col - 1, 1);
        else if (n === 9) this.tab();
        else if (n >= 10 && n <= 12) {
            this.lineFeed();
            if (this.modes.LNM) this.col = 1;
        } else if (n === 13) this.col = 1;
        else if (n === 14) this.gl = 1;
        else if (n === 15) this.gl = 0;
    }
    esc(key) {
        const known = [
            "7",
            "8",
            "D",
            "E",
            "M",
            "H",
            "c",
            "=",
            ">",
            "\\",
            "(0",
            "(B",
            ")0",
            ")B",
            "#8",
        ];
        if (!known.includes(key)) return false;
        if (["D", "E", "M", "c", "#8"].includes(key)) this.pending = false;
        switch (key) {
            case "7":
                this.save();
                break;
            case "8":
                this.restore();
                break;
            case "D":
                this.lineFeed();
                break;
            case "E":
                this.col = 1;
                this.lineFeed();
                break;
            case "M":
                this.reverseFeed();
                break;
            case "H":
                this.tabs.add(this.col);
                break;
            case "c":
                this.reset();
                break;
            case "=":
                this.modes.DECKPAM = true;
                break;
            case ">":
                this.modes.DECKPAM = false;
                break;
            case "(0":
                this.g0 = true;
                break;
            case "(B":
                this.g0 = false;
                break;
            case ")0":
                this.g1 = true;
                break;
            case ")B":
                this.g1 = false;
                break;
            case "#8":
                this.screens[this.alt] = Array.from({ length: this.height }, () =>
                    Array.from({ length: this.width }, () => ({
                        char: "E",
                        attrs: defaultAttrs(),
                    })),
                );
                this.top = 1;
                this.bottom = this.height;
                this.modes.DECOM = false;
                this.row = this.col = 1;
                break;
        }
        return true;
    }
    executeOsc() {
        if (this.osc.startsWith("0;") || this.osc.startsWith("2;")) {
            this.title = this.osc.slice(2);
            this.sequences++;
        } else this.ignored.unsupported++;
    }
    sgr(parameters) {
        let attrs = copyAttrs(this.attrs);
        const ps = parameters.length ? parameters : [0];
        const on = [1, 2, 3, 4, 5, 7, 8, 9],
            off = [22, 23, 24, 25, 27, 28, 29];
        for (let i = 0; i < ps.length; i++) {
            const v = ps[i];
            if (v === 0) attrs = defaultAttrs();
            else if (on.includes(v)) attrs.flags[on.indexOf(v)] = true;
            else if (off.includes(v)) {
                if (v === 22) {
                    attrs.flags[0] = false;
                    attrs.flags[1] = false;
                } else attrs.flags[off.indexOf(v) + 1] = false;
            } else if (v >= 30 && v <= 37) attrs.fg = palette(v - 30);
            else if (v >= 90 && v <= 97) attrs.fg = palette(v - 82);
            else if (v >= 40 && v <= 47) attrs.bg = palette(v - 40);
            else if (v >= 100 && v <= 107) attrs.bg = palette(v - 92);
            else if (v === 39) attrs.fg = "default";
            else if (v === 49) attrs.bg = "default";
            else if (v === 38 || v === 48) {
                let color;
                if (ps[i + 1] === 5 && i + 2 < ps.length && ps[i + 2] <= 255) {
                    color = palette(ps[i + 2]);
                    i += 2;
                } else if (
                    ps[i + 1] === 2 &&
                    i + 4 < ps.length &&
                    ps.slice(i + 2, i + 5).every((n) => n <= 255)
                ) {
                    color =
                        "#" +
                        ps
                            .slice(i + 2, i + 5)
                            .map((n) => n.toString(16).padStart(2, "0"))
                            .join("");
                    i += 4;
                } else return false;
                if (v === 38) attrs.fg = color;
                else attrs.bg = color;
            } else return false;
        }
        this.attrs = attrs;
        return true;
    }
    setModes(key, parameters) {
        const dec = key.startsWith("?"),
            setting = key.endsWith("h"),
            ps = parameters.length ? parameters : [0];
        const allowed = dec ? [1, 5, 6, 7, 25, 47, 1047, 1048, 1049, 2004] : [4, 20];
        if (ps.some((p) => !allowed.includes(p))) return false;
        const ansi = { 4: "IRM", 20: "LNM" };
        const mapping = {
            1: "DECCKM",
            5: "DECSCNM",
            7: "DECAWM",
            25: "DECTCEM",
            2004: "BRACKETED",
        };
        for (const p of ps) {
            if (!dec) this.modes[ansi[p]] = setting;
            else if (Object.hasOwn(mapping, p)) {
                this.modes[mapping[p]] = setting;
                if (p === 7 && !setting) this.pending = false;
            } else if (p === 6) {
                this.pending = false;
                this.modes.DECOM = setting;
                this.home();
            } else if (p === 1048) {
                if (setting) this.save();
                else this.restore();
            } else {
                this.pending = false;
                if (setting && this.alt === 0) {
                    if (p === 1049) this.save();
                    this.alt = 1;
                    if (p === 1049) this.screens[1] = this.blankScreen();
                } else if (!setting && this.alt === 1) {
                    if (p === 1047) this.screens[1] = this.blankScreen();
                    this.alt = 0;
                    if (p === 1049) this.restore();
                }
            }
        }
        return true;
    }
    reply(s) {
        this.replies++;
        emit("REPLY " + s);
    }
    csi(key, ps) {
        const p = ps[0] ?? 0,
            p2 = ps[1] ?? 0,
            n = Math.max(p, 1);
        const known = [
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
            "?$p",
        ];
        if (!known.includes(key)) return "unsupported";
        if (
            (key === "J" && p > 3) ||
            (key === "K" && p > 2) ||
            (key === "g" && p !== 0 && p !== 3) ||
            (key === " q" && p > 6) ||
            (key === "n" && p !== 5 && p !== 6) ||
            (key === "?n" && p !== 6) ||
            (["c", ">c"].includes(key) && p !== 0) ||
            (key === "t" && p !== 18)
        )
            return "unsupported";
        if (key === "m") return this.sgr(ps) ? "executed" : "unsupported";
        if (["h", "l", "?h", "?l"].includes(key))
            return this.setModes(key, ps) ? "executed" : "unsupported";
        if (key === "r") {
            const top = p || 1,
                bottom = Math.min(p2 || this.height, this.height);
            if (top >= bottom) return "invalid";
            this.pending = false;
            this.top = top;
            this.bottom = bottom;
            this.home();
            return "executed";
        }
        if (
            [
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
                "!p",
            ].includes(key)
        )
            this.pending = false;
        const up = () => {
            this.row = Math.max(this.row - n, this.row >= this.top ? this.top : 1);
        };
        const down = () => {
            this.row = Math.min(this.row + n, this.row <= this.bottom ? this.bottom : this.height);
        };
        const erase = (r, first, last) => {
            for (let c = first; c <= last; c++) this.screen()[r - 1][c - 1] = this.blank();
        };
        switch (key) {
            case "A":
                up();
                break;
            case "B":
            case "e":
                down();
                break;
            case "C":
            case "a":
                this.col = Math.min(this.col + n, this.width);
                break;
            case "D":
                this.col = Math.max(this.col - n, 1);
                break;
            case "E":
                down();
                this.col = 1;
                break;
            case "F":
                up();
                this.col = 1;
                break;
            case "G":
            case "`":
                this.col = Math.min(n, this.width);
                break;
            case "H":
            case "f":
                this.row = this.addressed(n);
                this.col = Math.min(Math.max(p2, 1), this.width);
                break;
            case "d":
                this.row = this.addressed(n);
                break;
            case "I":
            case "Z":
                for (let i = 0; i < n; i++) this.tab(key === "Z");
                break;
            case "J":
                if (p === 3) this.scrollback = [];
                else
                    for (let r = 1; r <= this.height; r++) {
                        if (p === 2 || (p === 0 && r > this.row) || (p === 1 && r < this.row))
                            erase(r, 1, this.width);
                        else if (r === this.row)
                            erase(r, p === 0 ? this.col : 1, p === 1 ? this.col : this.width);
                    }
                break;
            case "K":
                erase(this.row, p === 0 ? this.col : 1, p === 1 ? this.col : this.width);
                break;
            case "X":
                erase(this.row, this.col, Math.min(this.col + n - 1, this.width));
                break;
            case "@":
            case "P": {
                const row = this.screen()[this.row - 1],
                    k = Math.min(n, this.width - this.col + 1);
                if (key === "@") {
                    for (let c = this.width - 1; c >= this.col - 1 + k; c--) row[c] = row[c - k];
                    for (let c = this.col - 1; c < this.col - 1 + k; c++) row[c] = this.blank();
                } else {
                    row.splice(this.col - 1, k);
                    for (let i = 0; i < k; i++) row.push(this.blank());
                }
                break;
            }
            case "L":
            case "M":
                if (this.row >= this.top && this.row <= this.bottom) {
                    const screen = this.screen(),
                        k = Math.min(n, this.bottom - this.row + 1);
                    for (let i = 0; i < k; i++) {
                        if (key === "L") {
                            screen.splice(this.bottom - 1, 1);
                            screen.splice(this.row - 1, 0, this.blankRow());
                        } else {
                            screen.splice(this.row - 1, 1);
                            screen.splice(this.bottom - 1, 0, this.blankRow());
                        }
                    }
                    this.col = 1;
                }
                break;
            case "S":
            case "T":
                this.scroll(key === "S", Math.min(n, this.bottom - this.top + 1));
                break;
            case "b":
                if (this.last !== null) {
                    const c = this.last;
                    for (let i = 0; i < n; i++) this.write(c);
                }
                break;
            case "g":
                if (p === 3) this.tabs.clear();
                else this.tabs.delete(this.col);
                break;
            case " q":
                this.shape = n;
                break;
            case "s":
                this.save();
                break;
            case "u":
                this.restore();
                break;
            case "!p":
                for (const m of ["IRM", "DECCKM", "DECOM", "DECKPAM"]) this.modes[m] = false;
                this.modes.DECAWM = this.modes.DECTCEM = true;
                this.top = 1;
                this.bottom = this.height;
                this.attrs = defaultAttrs();
                this.g0 = this.g1 = false;
                this.gl = 0;
                this.saved[this.alt] = null;
                break;
            case "n":
                this.reply(p === 5 ? "^[[0n" : `^[[${this.reportedRow()};${this.col}R`);
                break;
            case "?n":
                this.reply(`^[[?${this.reportedRow()};${this.col};1R`);
                break;
            case "c":
                this.reply("^[[?1;2c");
                break;
            case ">c":
                this.reply("^[[>0;95;0c");
                break;
            case "t":
                this.reply(`^[[8;${this.height};${this.width}t`);
                break;
            case "$p":
            case "?$p": {
                const dec = key[0] === "?";
                const mapping = dec
                    ? {
                          1: "DECCKM",
                          5: "DECSCNM",
                          6: "DECOM",
                          7: "DECAWM",
                          25: "DECTCEM",
                          2004: "BRACKETED",
                      }
                    : { 4: "IRM", 20: "LNM" };
                let status = Object.hasOwn(mapping, p) ? (this.modes[mapping[p]] ? 1 : 2) : 0;
                if (dec && [47, 1047, 1049].includes(p)) status = this.alt ? 1 : 2;
                this.reply(`^[[${dec ? "?" : ""}${p};${status}$y`);
                break;
            }
        }
        return "executed";
    }
    reportedRow() {
        return this.modes.DECOM ? Math.max(this.row - this.top + 1, 1) : this.row;
    }
    finishCsi(final) {
        const fields = this.params === "" ? [] : this.params.split(";");
        if (fields.length >= 17) this.ignored.invalid++;
        else {
            const ps = fields.map((s) => {
                let value = 0;
                for (const c of s) value = Math.min(9999, value * 10 + Number(c));
                return value;
            });
            const result = this.csi(this.privateMarker + this.intermediate + final, ps);
            if (result === "executed") this.sequences++;
            else this.ignored[result]++;
        }
    }
    feed(n) {
        this.bytes++;
        if (n === 27) {
            if (this.state === "osc") this.executeOsc();
            else if (this.state !== "ground") this.ignored.canceled++;
            this.privateMarker = this.params = this.intermediate = this.osc = "";
            this.state = "escape";
            return;
        }
        if (n === 24 || n === 26) {
            if (this.state !== "ground") {
                this.ignored.canceled++;
                this.state = "ground";
            }
            return;
        }
        if (n < 32) {
            if (this.state === "osc") {
                if (n === 7) {
                    this.executeOsc();
                    this.state = "ground";
                }
            } else this.control(n);
            return;
        }
        const c = String.fromCharCode(n),
            intermediate = n <= 47,
            final = n >= 64;
        if (this.state === "ground") this.print(c);
        else if (this.state === "osc") this.osc += c;
        else if (this.state === "escape") {
            if (intermediate) {
                this.intermediate += c;
                this.state = "escape-intermediate";
            } else if (c === "[") this.state = "entry";
            else if (c === "]") this.state = "osc";
            else {
                if (this.esc(this.intermediate + c)) this.sequences++;
                else this.ignored.unsupported++;
                this.state = "ground";
            }
        } else if (this.state === "escape-intermediate") {
            if (intermediate) this.intermediate += c;
            else {
                if (this.esc(this.intermediate + c)) this.sequences++;
                else this.ignored.unsupported++;
                this.state = "ground";
            }
        } else if (this.state === "ignore") {
            if (final) {
                this.ignored.malformed++;
                this.state = "ground";
            }
        } else {
            if (this.state === "entry" && n >= 60 && n <= 63) {
                this.privateMarker = c;
                this.state = "param";
                return;
            }
            if (this.state === "entry") this.state = "param";
            if (this.state === "param") {
                if ((n >= 48 && n <= 57) || c === ";") this.params += c;
                else if (intermediate) {
                    this.intermediate += c;
                    this.state = "intermediate";
                } else if (final) {
                    this.finishCsi(c);
                    this.state = "ground";
                } else this.state = "ignore";
            } else if (this.state === "intermediate") {
                if (intermediate) this.intermediate += c;
                else if (final) {
                    this.finishCsi(c);
                    this.state = "ground";
                } else this.state = "ignore";
            }
        }
    }
    dump(label) {
        emit(
            `${label} ${this.alt ? "alt" : "main"} cursor ${this.row},${this.col} scrollback ${this.scrollback.length}${this.pending ? " pending" : ""}`,
        );
        for (const row of this.screen()) emit("|" + this.rowText(row));
    }
    key(name) {
        const arrows = { UP: "A", DOWN: "B", RIGHT: "C", LEFT: "D", HOME: "H", END: "F" };
        const fixed = {
            INSERT: "^[[2~",
            DELETE: "^[[3~",
            PAGEUP: "^[[5~",
            PAGEDOWN: "^[[6~",
            F1: "^[OP",
            F2: "^[OQ",
            F3: "^[OR",
            F4: "^[OS",
            F5: "^[[15~",
            F6: "^[[17~",
            F7: "^[[18~",
            F8: "^[[19~",
            F9: "^[[20~",
            F10: "^[[21~",
            F11: "^[[23~",
            F12: "^[[24~",
            TAB: "^I",
            BACKSPACE: "^?",
            ESCAPE: "^[",
        };
        const enter = this.modes.LNM ? "^M^J" : "^M";
        let sent;
        if (Object.hasOwn(arrows, name)) sent = (this.modes.DECCKM ? "^[O" : "^[[") + arrows[name];
        else if (name === "ENTER") sent = enter;
        else if (name === "KPENTER") sent = this.modes.DECKPAM ? "^[OM" : enter;
        else if (/^KP[0-9]$/.test(name))
            sent = this.modes.DECKPAM
                ? "^[O" + String.fromCharCode(0x70 + Number(name[2]))
                : name[2];
        else sent = fixed[name];
        emit(`KEY ${name} ${sent}`);
    }
    finish() {
        if (this.state !== "ground") {
            this.ignored.canceled++;
            this.state = "ground";
        }
        this.dump("FINAL");
        emit(this.title === null ? "TITLE none" : `TITLE "${this.title}"`);
        const initial = defaultModes(),
            modes = [];
        for (const name of modeNames)
            if (this.modes[name] !== initial[name])
                modes.push(`${name}=${this.modes[name] ? "on" : "off"}`);
        if (this.g0) modes.push("G0=graphics");
        if (this.g1) modes.push("G1=graphics");
        if (this.gl) modes.push("GL=G1");
        if (this.shape !== 1) modes.push(`CURSOR=${this.shape}`);
        emit("MODES " + (modes.join(" ") || "default"));
        emit(`REGION ${this.top}-${this.bottom}`);
        emit(
            "TABS " +
                (Array.from(this.tabs)
                    .sort((a, b) => a - b)
                    .join(",") || "none"),
        );
        emit(`SCROLLBACK ${this.scrollback.length}`);
        for (const s of this.scrollback.slice(-5)) emit("|" + s);
        const runs = [],
            blank = defaultAttrs();
        this.screen().forEach((row, r) => {
            let c = 0;
            while (c < this.width) {
                const start = c,
                    attrs = row[c].attrs;
                while (c < this.width && equalAttrs(row[c].attrs, attrs)) c++;
                if (equalAttrs(attrs, blank)) continue;
                const names = flagNames.filter((_, i) => attrs.flags[i]);
                if (attrs.fg !== "default") names.push("fg=" + attrs.fg);
                if (attrs.bg !== "default") names.push("bg=" + attrs.bg);
                runs.push(`row ${r + 1} col ${start + 1}-${c} ${names.join(" ")}`);
            }
        });
        emit(`ATTRS ${runs.length}`);
        for (const run of runs) emit(run);
        emit(`BELL ${this.bell}`);
        emit(`REPLIES ${this.replies}`);
        emit(`STATS bytes=${this.bytes} printed=${this.printed} sequences=${this.sequences}`);
        const i = this.ignored;
        emit(
            `IGNORED ${i.unsupported + i.malformed + i.canceled + i.invalid} unsupported=${i.unsupported} malformed=${i.malformed} canceled=${i.canceled} invalid=${i.invalid}`,
        );
    }
}
const lines = readFileSync(0, "utf8").split(/\r?\n/),
    [width, height] = lines[0].split(" ").map(Number);
const terminal = new Terminal(width, height);
const caret = {
    "@": 0,
    G: 7,
    H: 8,
    I: 9,
    J: 10,
    K: 11,
    L: 12,
    M: 13,
    N: 14,
    O: 15,
    X: 24,
    Z: 26,
    "[": 27,
    "^": 94,
};
for (const line of lines.slice(1)) {
    if (line === "%%END") {
        terminal.finish();
        break;
    }
    if (line === "%%DUMP") terminal.dump(`DUMP ${++terminal.dumps}`);
    else if (line.startsWith("%%KEY ")) terminal.key(line.slice(6));
    else if (line.startsWith("%%PASTE ")) {
        const text = line.slice(8).replace(/\^/g, "^^");
        emit("PASTE " + (terminal.modes.BRACKETED ? "^[[200~" + text + "^[[201~" : text));
    } else
        for (let i = 0; i < line.length; i++)
            terminal.feed(line[i] === "^" ? caret[line[++i]] : line.charCodeAt(i));
}
