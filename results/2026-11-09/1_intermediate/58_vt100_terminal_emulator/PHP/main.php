<?php
declare(strict_types=1);
class Terminal
{
    private const FLAGS = [
        "bold",
        "dim",
        "italic",
        "underline",
        "blink",
        "reverse",
        "hidden",
        "strike",
    ];
    private const INITIAL = [
        "IRM" => false,
        "LNM" => false,
        "DECCKM" => false,
        "DECSCNM" => false,
        "DECOM" => false,
        "DECAWM" => true,
        "DECTCEM" => true,
        "DECKPAM" => false,
        "BRACKETED" => false,
    ];
    private const ANSI = [4 => "IRM", 20 => "LNM"];
    private const DEC = [
        1 => "DECCKM",
        5 => "DECSCNM",
        6 => "DECOM",
        7 => "DECAWM",
        25 => "DECTCEM",
        2004 => "BRACKETED",
    ];
    private const DEFAULT_ATTRS = [0, "default", "default"];
    private int $bytes = 0,
        $printed = 0,
        $sequences = 0,
        $bell = 0,
        $replies = 0,
        $dumps = 0;
    private array $ignored = [
        "unsupported" => 0,
        "malformed" => 0,
        "canceled" => 0,
        "invalid" => 0,
    ];
    private array $screens, $attrs, $modes, $tabs, $saves, $scrollback;
    private int $screen, $row, $col, $top, $bottom, $g0, $g1, $gl, $shape;
    private bool $pending;
    private ?string $title, $last;
    private string $parser, $private, $params, $intermediate, $osc;
    public function __construct(private int $w, private int $h)
    {
        $this->reset();
    }
    private function blankRow(): array
    {
        return array_fill(0, $this->w, [" ", self::DEFAULT_ATTRS]);
    }
    private function blankScreen(): array
    {
        return array_fill(0, $this->h, $this->blankRow());
    }
    private function reset(): void
    {
        $this->screens = [$this->blankScreen(), $this->blankScreen()];
        $this->screen = 0;
        $this->row = $this->col = $this->top = 1;
        $this->bottom = $this->h;
        $this->pending = false;
        $this->attrs = self::DEFAULT_ATTRS;
        $this->g0 = $this->g1 = $this->gl = 0;
        $this->modes = self::INITIAL;
        $this->shape = 1;
        $this->tabs = [];
        for ($i = 9; $i <= $this->w; $i += 8) {
            $this->tabs[] = $i;
        }
        $this->saves = [null, null];
        $this->scrollback = [];
        $this->title = $this->last = null;
        $this->parserStart("ground");
    }
    private function parserStart(string $state): void
    {
        $this->parser = $state;
        $this->private = $this->params = $this->intermediate = $this->osc = "";
    }
    private function rowText(array $cells): string
    {
        return rtrim(implode("", array_column($cells, 0)), " ");
    }
    private function scroll(bool $up, int $count = 1): void
    {
        for ($i = 0; $i < $count; ++$i) {
            if ($up) {
                $removed = array_splice($this->screens[$this->screen], $this->top - 1, 1)[0];
                array_splice($this->screens[$this->screen], $this->bottom - 1, 0, [
                    $this->blankRow(),
                ]);
                if ($this->screen === 0 && $this->top === 1) {
                    $this->scrollback[] = $this->rowText($removed);
                    if (count($this->scrollback) > 100) {
                        array_shift($this->scrollback);
                    }
                }
            } else {
                array_splice($this->screens[$this->screen], $this->bottom - 1, 1);
                array_splice($this->screens[$this->screen], $this->top - 1, 0, [$this->blankRow()]);
            }
        }
    }
    private function lineFeed(): void
    {
        if ($this->row === $this->bottom) {
            $this->scroll(true);
        } elseif ($this->row < $this->h) {
            ++$this->row;
        }
    }
    private function reverseFeed(): void
    {
        if ($this->row === $this->top) {
            $this->scroll(false);
        } elseif ($this->row > 1) {
            --$this->row;
        }
    }
    private function tab(bool $reverse = false): void
    {
        $candidates = array_filter(
            $this->tabs,
            fn(int $stop): bool => $reverse ? $stop < $this->col : $stop > $this->col,
        );
        $this->col = $candidates
            ? ($reverse
                ? max($candidates)
                : min($candidates))
            : ($reverse
                ? 1
                : $this->w);
    }
    private function address(int $value): int
    {
        return $this->modes["DECOM"]
            ? min($this->top + $value - 1, $this->bottom)
            : min($value, $this->h);
    }
    private function home(): void
    {
        $this->row = $this->address(1);
        $this->col = 1;
    }
    private function save(): void
    {
        $this->saves[$this->screen] = [
            $this->row,
            $this->col,
            $this->attrs,
            $this->modes["DECOM"],
            $this->g0,
            $this->g1,
            $this->gl,
        ];
    }
    private function restore(): void
    {
        $saved = $this->saves[$this->screen];
        if ($saved !== null) {
            [
                $this->row,
                $this->col,
                $this->attrs,
                $this->modes["DECOM"],
                $this->g0,
                $this->g1,
                $this->gl,
            ] = $saved;
        } else {
            $this->row = $this->col = 1;
            $this->attrs = self::DEFAULT_ATTRS;
            $this->modes["DECOM"] = false;
            $this->g0 = $this->g1 = $this->gl = 0;
        }
        $this->pending = false;
    }
    private function write(string $char): void
    {
        ++$this->printed;
        $this->last = $char;
        if ($this->pending) {
            $this->pending = false;
            $this->col = 1;
            $this->lineFeed();
        }
        if ($this->modes["IRM"]) {
            array_splice($this->screens[$this->screen][$this->row - 1], $this->col - 1, 0, [
                [" ", self::DEFAULT_ATTRS],
            ]);
            array_pop($this->screens[$this->screen][$this->row - 1]);
        }
        $this->screens[$this->screen][$this->row - 1][$this->col - 1] = [$char, $this->attrs];
        if ($this->col < $this->w) {
            ++$this->col;
        } elseif ($this->modes["DECAWM"]) {
            $this->pending = true;
        }
    }
    private function printChar(string $char): void
    {
        if (($this->gl === 0 ? $this->g0 : $this->g1) === 1) {
            $map = [
                "`" => "*",
                "a" => "#",
                "j" => "+",
                "k" => "+",
                "l" => "+",
                "m" => "+",
                "n" => "+",
                "t" => "+",
                "u" => "+",
                "v" => "+",
                "w" => "+",
                "q" => "-",
                "x" => "|",
                "~" => "o",
            ];
            $char = $map[$char] ?? $char;
        }
        $this->write($char);
    }
    private function control(int $code): void
    {
        if (in_array($code, [8, 9, 10, 11, 12, 13], true)) {
            $this->pending = false;
        }
        switch ($code) {
            case 7:
                ++$this->bell;
                break;
            case 8:
                $this->col = max(1, $this->col - 1);
                break;
            case 9:
                $this->tab();
                break;
            case 10:
            case 11:
            case 12:
                $this->lineFeed();
                if ($this->modes["LNM"]) {
                    $this->col = 1;
                }
                break;
            case 13:
                $this->col = 1;
                break;
            case 14:
                $this->gl = 1;
                break;
            case 15:
                $this->gl = 0;
                break;
        }
    }
    private function escape(string $key): ?string
    {
        $known = ["7", "8", "D", "E", "M", "H", "c", "=", ">", "\\", "(0", "(B", ")0", ")B", "#8"];
        if (!in_array($key, $known, true)) {
            return "unsupported";
        }
        if (in_array($key, ["D", "E", "M", "c", "#8"], true)) {
            $this->pending = false;
        }
        switch ($key) {
            case "7":
                $this->save();
                break;
            case "8":
                $this->restore();
                break;
            case "D":
                $this->lineFeed();
                break;
            case "E":
                $this->col = 1;
                $this->lineFeed();
                break;
            case "M":
                $this->reverseFeed();
                break;
            case "H":
                if (!in_array($this->col, $this->tabs, true)) {
                    $this->tabs[] = $this->col;
                }
                sort($this->tabs, SORT_NUMERIC);
                break;
            case "c":
                $this->reset();
                break;
            case "=":
                $this->modes["DECKPAM"] = true;
                break;
            case ">":
                $this->modes["DECKPAM"] = false;
                break;
            case "(0":
                $this->g0 = 1;
                break;
            case "(B":
                $this->g0 = 0;
                break;
            case ")0":
                $this->g1 = 1;
                break;
            case ")B":
                $this->g1 = 0;
                break;
            case "#8":
                $this->screens[$this->screen] = array_fill(
                    0,
                    $this->h,
                    array_fill(0, $this->w, ["E", self::DEFAULT_ATTRS]),
                );
                $this->top = 1;
                $this->bottom = $this->h;
                $this->modes["DECOM"] = false;
                $this->row = $this->col = 1;
                break;
        }
        return null;
    }
    private function palette(int $number): string
    {
        $colors = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];
        if ($number < 8) {
            return $colors[$number];
        }
        if ($number < 16) {
            return "bright-" . $colors[$number - 8];
        }
        return (string) $number;
    }
    private function sgr(array $params): ?string
    {
        if (!$params) {
            $params = [0];
        }
        $attrs = $this->attrs;
        $on = [1 => 0, 2 => 1, 3 => 2, 4 => 3, 5 => 4, 7 => 5, 8 => 6, 9 => 7];
        $off = [23 => 2, 24 => 3, 25 => 4, 27 => 5, 28 => 6, 29 => 7];
        for ($i = 0; $i < count($params); ++$i) {
            $value = $params[$i];
            if ($value === 0) {
                $attrs = self::DEFAULT_ATTRS;
            } elseif (isset($on[$value])) {
                $attrs[0] |= 1 << $on[$value];
            } elseif ($value === 22) {
                $attrs[0] &= ~3;
            } elseif (isset($off[$value])) {
                $attrs[0] &= ~(1 << $off[$value]);
            } elseif ($value >= 30 && $value <= 37) {
                $attrs[1] = $this->palette($value - 30);
            } elseif ($value >= 90 && $value <= 97) {
                $attrs[1] = $this->palette($value - 82);
            } elseif ($value >= 40 && $value <= 47) {
                $attrs[2] = $this->palette($value - 40);
            } elseif ($value >= 100 && $value <= 107) {
                $attrs[2] = $this->palette($value - 92);
            } elseif ($value === 39 || $value === 49) {
                $attrs[$value === 39 ? 1 : 2] = "default";
            } elseif ($value === 38 || $value === 48) {
                $color = null;
                if (
                    ($params[$i + 1] ?? -1) === 5 &&
                    isset($params[$i + 2]) &&
                    $params[$i + 2] <= 255
                ) {
                    $color = $this->palette($params[$i + 2]);
                    $i += 2;
                } elseif (
                    ($params[$i + 1] ?? -1) === 2 &&
                    isset($params[$i + 4]) &&
                    max(array_slice($params, $i + 2, 3)) <= 255
                ) {
                    $color = sprintf(
                        "#%02x%02x%02x",
                        $params[$i + 2],
                        $params[$i + 3],
                        $params[$i + 4],
                    );
                    $i += 4;
                }
                if ($color === null) {
                    return "unsupported";
                }
                $attrs[$value === 38 ? 1 : 2] = $color;
            } else {
                return "unsupported";
            }
        }
        $this->attrs = $attrs;
        return null;
    }
    private function modes(string $key, array $params): ?string
    {
        if (!$params) {
            $params = [0];
        }
        $private = str_starts_with($key, "?");
        $allowed = $private ? [1, 5, 6, 7, 25, 47, 1047, 1048, 1049, 2004] : [4, 20];
        foreach ($params as $p) {
            if (!in_array($p, $allowed, true)) {
                return "unsupported";
            }
        }
        $setting = str_ends_with($key, "h");
        foreach ($params as $p) {
            if (!$private) {
                $this->modes[self::ANSI[$p]] = $setting;
            } elseif ($p === 6) {
                $this->pending = false;
                $this->modes["DECOM"] = $setting;
                $this->home();
            } elseif (in_array($p, [47, 1047, 1049], true)) {
                $this->pending = false;
                $target = $setting ? 1 : 0;
                if ($this->screen === $target) {
                    continue;
                }
                if ($setting && $p === 1049) {
                    $this->save();
                }
                if (!$setting && $p === 1047) {
                    $this->screens[1] = $this->blankScreen();
                }
                $this->screen = $target;
                if ($setting && $p === 1049) {
                    $this->screens[1] = $this->blankScreen();
                }
                if (!$setting && $p === 1049) {
                    $this->restore();
                }
            } elseif ($p === 1048) {
                if ($setting) {
                    $this->save();
                } else {
                    $this->restore();
                }
            } else {
                if ($p === 7 && !$setting) {
                    $this->pending = false;
                }
                $this->modes[self::DEC[$p]] = $setting;
            }
        }
        return null;
    }
    private function erase(int $row, int $first, int $last): void
    {
        for ($c = $first; $c <= $last; ++$c) {
            $this->screens[$this->screen][$row - 1][$c - 1] = [" ", self::DEFAULT_ATTRS];
        }
    }
    private function reply(string $text): void
    {
        ++$this->replies;
        echo "REPLY $text\n";
    }
    private function csi(string $final): ?string
    {
        $fields = $this->params === "" ? [] : explode(";", $this->params);
        if (count($fields) > 16) {
            return "invalid";
        }
        $params = [];
        foreach ($fields as $field) {
            $value = 0;
            for ($i = 0; $i < strlen($field); ++$i) {
                $value = min(9999, $value * 10 + ord($field[$i]) - 48);
            }
            $params[] = $value;
        }
        $p1 = $params[0] ?? 0;
        $p2 = $params[1] ?? 0;
        $n = max(1, $p1);
        $key = $this->private . $this->intermediate . $final;
        $known = [
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
            '$p',
            '?$p',
        ];
        if (!in_array($key, $known, true)) {
            return "unsupported";
        }
        $bad =
            ($key === "J" && $p1 > 3) ||
            ($key === "K" && $p1 > 2) ||
            ($key === "g" && !in_array($p1, [0, 3], true)) ||
            ($key === " q" && $p1 > 6) ||
            ($key === "n" && !in_array($p1, [5, 6], true)) ||
            ($key === "?n" && $p1 !== 6) ||
            (in_array($key, ["c", ">c"], true) && $p1 !== 0) ||
            ($key === "t" && $p1 !== 18);
        if ($bad) {
            return "unsupported";
        }
        if ($key === "m") {
            return $this->sgr($params);
        }
        if (in_array($key, ["h", "l", "?h", "?l"], true)) {
            return $this->modes($key, $params);
        }
        if ($key === "r") {
            $top = $p1 === 0 ? 1 : $p1;
            $bottom = min($p2 === 0 ? $this->h : $p2, $this->h);
            if ($top >= $bottom) {
                return "invalid";
            }
            $this->pending = false;
            $this->top = $top;
            $this->bottom = $bottom;
            $this->home();
            return null;
        }
        if (
            in_array(
                $key,
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
                ],
                true,
            )
        ) {
            $this->pending = false;
        }
        switch ($key) {
            case "A":
            case "F":
                $this->row = max($this->row - $n, $this->row >= $this->top ? $this->top : 1);
                if ($key === "F") {
                    $this->col = 1;
                }
                break;
            case "B":
            case "e":
            case "E":
                $this->row = min(
                    $this->row + $n,
                    $this->row <= $this->bottom ? $this->bottom : $this->h,
                );
                if ($key === "E") {
                    $this->col = 1;
                }
                break;
            case "C":
            case "a":
                $this->col = min($this->col + $n, $this->w);
                break;
            case "D":
                $this->col = max($this->col - $n, 1);
                break;
            case "G":
            case "`":
                $this->col = min($n, $this->w);
                break;
            case "H":
            case "f":
                $this->row = $this->address($n);
                $this->col = min(max(1, $p2), $this->w);
                break;
            case "d":
                $this->row = $this->address($n);
                break;
            case "I":
            case "Z":
                for ($i = 0; $i < $n; ++$i) {
                    $this->tab($key === "Z");
                }
                break;
            case "J":
                if ($p1 === 3) {
                    $this->scrollback = [];
                } else {
                    for ($r = 1; $r <= $this->h; ++$r) {
                        for ($c = 1; $c <= $this->w; ++$c) {
                            $position = ($r - 1) * $this->w + $c;
                            $cursor = ($this->row - 1) * $this->w + $this->col;
                            if (
                                $p1 === 2 ||
                                ($p1 === 0 && $position >= $cursor) ||
                                ($p1 === 1 && $position <= $cursor)
                            ) {
                                $this->erase($r, $c, $c);
                            }
                        };
                    };
                }
                break;
            case "K":
                $this->erase(
                    $this->row,
                    $p1 === 0 ? $this->col : 1,
                    $p1 === 1 ? $this->col : $this->w,
                );
                break;
            case "X":
                $this->erase($this->row, $this->col, min($this->col + $n - 1, $this->w));
                break;
            case "@":
            case "P":
                $k = min($n, $this->w - $this->col + 1);
                if ($key === "@") {
                    array_splice(
                        $this->screens[$this->screen][$this->row - 1],
                        $this->col - 1,
                        0,
                        array_fill(0, $k, [" ", self::DEFAULT_ATTRS]),
                    );
                    $this->screens[$this->screen][$this->row - 1] = array_slice(
                        $this->screens[$this->screen][$this->row - 1],
                        0,
                        $this->w,
                    );
                } else {
                    array_splice($this->screens[$this->screen][$this->row - 1], $this->col - 1, $k);
                    for ($i = 0; $i < $k; ++$i) {
                        $this->screens[$this->screen][$this->row - 1][] = [
                            " ",
                            self::DEFAULT_ATTRS,
                        ];
                    }
                }
                break;
            case "L":
            case "M":
                if ($this->row >= $this->top && $this->row <= $this->bottom) {
                    $k = min($n, $this->bottom - $this->row + 1);
                    for ($i = 0; $i < $k; ++$i) {
                        if ($key === "L") {
                            array_splice($this->screens[$this->screen], $this->bottom - 1, 1);
                            array_splice($this->screens[$this->screen], $this->row - 1, 0, [
                                $this->blankRow(),
                            ]);
                        } else {
                            array_splice($this->screens[$this->screen], $this->row - 1, 1);
                            array_splice($this->screens[$this->screen], $this->bottom - 1, 0, [
                                $this->blankRow(),
                            ]);
                        }
                    }
                    $this->col = 1;
                }
                break;
            case "S":
            case "T":
                $this->scroll($key === "S", min($n, $this->bottom - $this->top + 1));
                break;
            case "b":
                if ($this->last !== null) {
                    for ($i = 0; $i < $n; ++$i) {
                        $this->write($this->last);
                    };
                }
                break;
            case "g":
                $this->tabs = $p1 === 3 ? [] : array_values(array_diff($this->tabs, [$this->col]));
                break;
            case " q":
                $this->shape = $n;
                break;
            case "s":
                $this->save();
                break;
            case "u":
                $this->restore();
                break;
            case "!p":
                foreach (["IRM", "DECCKM", "DECOM", "DECAWM", "DECTCEM", "DECKPAM"] as $mode) {
                    $this->modes[$mode] = self::INITIAL[$mode];
                }
                $this->top = 1;
                $this->bottom = $this->h;
                $this->attrs = self::DEFAULT_ATTRS;
                $this->g0 = $this->g1 = $this->gl = 0;
                $this->saves[$this->screen] = null;
                break;
            case "n":
                $r = $this->modes["DECOM"] ? max(1, $this->row - $this->top + 1) : $this->row;
                $this->reply($p1 === 5 ? "^[[0n" : "^[[{$r};{$this->col}R");
                break;
            case "?n":
                $r = $this->modes["DECOM"] ? max(1, $this->row - $this->top + 1) : $this->row;
                $this->reply("^[[?{$r};{$this->col};1R");
                break;
            case "c":
                $this->reply("^[[?1;2c");
                break;
            case ">c":
                $this->reply("^[[>0;95;0c");
                break;
            case "t":
                $this->reply("^[[8;{$this->h};{$this->w}t");
                break;
            case '$p':
            case '?$p':
                $mode = $key === '$p' ? self::ANSI[$p1] ?? null : self::DEC[$p1] ?? null;
                $status = $mode !== null ? ($this->modes[$mode] ? 1 : 2) : 0;
                if ($key === '?$p' && in_array($p1, [47, 1047, 1049], true)) {
                    $status = $this->screen === 1 ? 1 : 2;
                }
                $this->reply("^[[" . ($key === '?$p' ? "?" : "") . $p1 . ";" . $status . '$y');
                break;
        }
        return null;
    }
    private function finishSequence(?string $reason): void
    {
        if ($reason !== null) {
            ++$this->ignored[$reason];
        } else {
            ++$this->sequences;
        }
    }
    private function executeOsc(): void
    {
        if (str_starts_with($this->osc, "0;") || str_starts_with($this->osc, "2;")) {
            $this->title = substr($this->osc, 2);
            $this->finishSequence(null);
        } else {
            $this->finishSequence("unsupported");
        }
    }
    private function byte(int $code): void
    {
        ++$this->bytes;
        if ($code === 27) {
            if ($this->parser === "osc") {
                $this->executeOsc();
            } elseif ($this->parser !== "ground") {
                ++$this->ignored["canceled"];
            }
            $this->parserStart("escape");
            return;
        }
        if ($code === 24 || $code === 26) {
            if ($this->parser !== "ground") {
                ++$this->ignored["canceled"];
                $this->parser = "ground";
            }
            return;
        }
        if ($code < 32) {
            if ($this->parser === "osc") {
                if ($code === 7) {
                    $this->executeOsc();
                    $this->parser = "ground";
                }
            } else {
                $this->control($code);
            }
            return;
        }
        $char = chr($code);
        $intermediate = $code >= 32 && $code <= 47;
        $final = $code >= 64;
        switch ($this->parser) {
            case "ground":
                $this->printChar($char);
                break;
            case "escape":
                if ($intermediate) {
                    $this->intermediate .= $char;
                    $this->parser = "escape intermediate";
                } elseif ($char === "[") {
                    $this->parser = "entry";
                } elseif ($char === "]") {
                    $this->parser = "osc";
                } else {
                    $this->finishSequence($this->escape($this->intermediate . $char));
                    $this->parser = "ground";
                }
                break;
            case "escape intermediate":
                if ($intermediate) {
                    $this->intermediate .= $char;
                } else {
                    $this->finishSequence($this->escape($this->intermediate . $char));
                    $this->parser = "ground";
                }
                break;
            case "entry":
            case "param":
                if ($this->parser === "entry" && $code >= 60 && $code <= 63) {
                    $this->private = $char;
                    $this->parser = "param";
                } elseif (($code >= 48 && $code <= 57) || $char === ";") {
                    $this->params .= $char;
                    $this->parser = "param";
                } elseif ($intermediate) {
                    $this->intermediate .= $char;
                    $this->parser = "csi intermediate";
                } elseif ($final) {
                    $this->finishSequence($this->csi($char));
                    $this->parser = "ground";
                } else {
                    $this->parser = "ignore";
                }
                break;
            case "csi intermediate":
                if ($intermediate) {
                    $this->intermediate .= $char;
                } elseif ($final) {
                    $this->finishSequence($this->csi($char));
                    $this->parser = "ground";
                } else {
                    $this->parser = "ignore";
                }
                break;
            case "ignore":
                if ($final) {
                    ++$this->ignored["malformed"];
                    $this->parser = "ground";
                }
                break;
            case "osc":
                $this->osc .= $char;
                break;
        }
    }
    private function dump(string $label): void
    {
        echo $label .
            " " .
            ($this->screen === 0 ? "main" : "alt") .
            " cursor {$this->row},{$this->col} scrollback " .
            count($this->scrollback) .
            ($this->pending ? " pending" : "") .
            "\n";
        foreach ($this->screens[$this->screen] as $cells) {
            echo "|" . $this->rowText($cells) . "\n";
        }
    }
    private function key(string $name): void
    {
        $arrows = [
            "UP" => "A",
            "DOWN" => "B",
            "RIGHT" => "C",
            "LEFT" => "D",
            "HOME" => "H",
            "END" => "F",
        ];
        $fixed = [
            "INSERT" => "^[[2~",
            "DELETE" => "^[[3~",
            "PAGEUP" => "^[[5~",
            "PAGEDOWN" => "^[[6~",
            "F1" => "^[OP",
            "F2" => "^[OQ",
            "F3" => "^[OR",
            "F4" => "^[OS",
            "F5" => "^[[15~",
            "F6" => "^[[17~",
            "F7" => "^[[18~",
            "F8" => "^[[19~",
            "F9" => "^[[20~",
            "F10" => "^[[21~",
            "F11" => "^[[23~",
            "F12" => "^[[24~",
            "TAB" => "^I",
            "BACKSPACE" => "^?",
            "ESCAPE" => "^[",
        ];
        $enter = $this->modes["LNM"] ? "^M^J" : "^M";
        if (isset($arrows[$name])) {
            $text = ($this->modes["DECCKM"] ? "^[O" : "^[[") . $arrows[$name];
        } elseif ($name === "ENTER") {
            $text = $enter;
        } elseif ($name === "KPENTER") {
            $text = $this->modes["DECKPAM"] ? "^[OM" : $enter;
        } elseif (preg_match('/^KP[0-9]$/D', $name)) {
            $text = $this->modes["DECKPAM"] ? "^[O" . chr(112 + (int) $name[2]) : $name[2];
        } else {
            $text = $fixed[$name];
        }
        echo "KEY $name $text\n";
    }
    private function finish(): void
    {
        if ($this->parser !== "ground") {
            ++$this->ignored["canceled"];
        }
        $this->dump("FINAL");
        echo $this->title === null ? "TITLE none\n" : 'TITLE "' . $this->title . "\"\n";
        $modes = [];
        foreach (self::INITIAL as $name => $initial) {
            if ($this->modes[$name] !== $initial) {
                $modes[] = $name . "=" . ($this->modes[$name] ? "on" : "off");
            }
        }
        if ($this->g0 === 1) {
            $modes[] = "G0=graphics";
        }
        if ($this->g1 === 1) {
            $modes[] = "G1=graphics";
        }
        if ($this->gl === 1) {
            $modes[] = "GL=G1";
        }
        if ($this->shape !== 1) {
            $modes[] = "CURSOR=" . $this->shape;
        }
        echo "MODES " . ($modes ? implode(" ", $modes) : "default") . "\n";
        echo "REGION {$this->top}-{$this->bottom}\n";
        sort($this->tabs, SORT_NUMERIC);
        echo "TABS " . ($this->tabs ? implode(",", $this->tabs) : "none") . "\n";
        echo "SCROLLBACK " . count($this->scrollback) . "\n";
        foreach (array_slice($this->scrollback, -5) as $line) {
            echo "|$line\n";
        }
        $runs = [];
        foreach ($this->screens[$this->screen] as $r => $cells) {
            for ($c = 0; $c < $this->w; ) {
                $attrs = $cells[$c][1];
                $last = $c;
                while ($last + 1 < $this->w && $cells[$last + 1][1] === $attrs) {
                    ++$last;
                }
                if ($attrs !== self::DEFAULT_ATTRS) {
                    $names = [];
                    foreach (self::FLAGS as $i => $name) {
                        if (($attrs[0] & (1 << $i)) !== 0) {
                            $names[] = $name;
                        }
                    }
                    if ($attrs[1] !== "default") {
                        $names[] = "fg=" . $attrs[1];
                    }
                    if ($attrs[2] !== "default") {
                        $names[] = "bg=" . $attrs[2];
                    }
                    $runs[] =
                        "row " .
                        ($r + 1) .
                        " col " .
                        ($c + 1) .
                        "-" .
                        ($last + 1) .
                        " " .
                        implode(" ", $names);
                }
                $c = $last + 1;
            }
        }
        echo "ATTRS " . count($runs) . "\n";
        foreach ($runs as $line) {
            echo "$line\n";
        }
        echo "BELL {$this->bell}\nREPLIES {$this->replies}\nSTATS bytes={$this->bytes} printed={$this->printed} sequences={$this->sequences}\n";
        $parts = [];
        foreach ($this->ignored as $name => $value) {
            $parts[] = "$name=$value";
        }
        echo "IGNORED " . array_sum($this->ignored) . " " . implode(" ", $parts) . "\n";
    }
    public function line(string $text): void
    {
        if ($text === "%%END") {
            $this->finish();
        } elseif ($text === "%%DUMP") {
            ++$this->dumps;
            $this->dump("DUMP " . $this->dumps);
        } elseif (str_starts_with($text, "%%KEY ")) {
            $this->key(substr($text, 6));
        } elseif (str_starts_with($text, "%%PASTE ")) {
            $pasted = str_replace("^", "^^", substr($text, 8));
            if ($this->modes["BRACKETED"]) {
                $pasted = "^[[200~" . $pasted . "^[[201~";
            }
            echo "PASTE $pasted\n";
        } else {
            $codes = [
                "@" => 0,
                "G" => 7,
                "H" => 8,
                "I" => 9,
                "J" => 10,
                "K" => 11,
                "L" => 12,
                "M" => 13,
                "N" => 14,
                "O" => 15,
                "X" => 24,
                "Z" => 26,
                "[" => 27,
                "^" => 94,
            ];
            for ($i = 0; $i < strlen($text); ) {
                if ($text[$i] === "^") {
                    $this->byte($codes[$text[$i + 1]]);
                    $i += 2;
                } else {
                    $this->byte(ord($text[$i]));
                    ++$i;
                }
            }
        }
    }
}
[$width, $height] = array_map("intval", explode(" ", trim(fgets(STDIN))));
$terminal = new Terminal($width, $height);
while (($line = fgets(STDIN)) !== false) {
    $terminal->line(rtrim($line, "\r\n"));
}
