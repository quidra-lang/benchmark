<?php
class CubeFault extends Exception {}
class Cube
{
    private const FACES = ["U", "R", "F", "D", "L", "B"];
    private const COLORS = ["W", "R", "G", "Y", "O", "B"];
    private const LETTERS = "UDFBLRMESudfblrxyz";
    private const CORNERS = ["URF", "UFL", "ULB", "UBR", "DFR", "DLF", "DBL", "DRB"];
    private const EDGES = ["UR", "UF", "UL", "UB", "DR", "DF", "DL", "DB", "FR", "FL", "BL", "BR"];
    private const NO_ARGS = [
        "RESET",
        "SHOW",
        "STATE",
        "ISSOLVED",
        "HISTORY",
        "SOLUTION",
        "ANALYZE",
        "STAGE",
        "MACROS",
    ];
    private const WORDS = [
        "CHECK" => 1,
        "LOAD" => 1,
        "UNDO" => 1,
        "REDO" => 1,
        "SEARCH" => 1,
        "WHERE" => 1,
        "SAVE" => 1,
        "RESTORE" => 1,
        "SCRAMBLE" => 2,
    ];
    private const SEQUENCES = [
        "APPLY",
        "INVERT",
        "SIMPLIFY",
        "METRICS",
        "ORDER",
        "CYCLES",
        "UNROTATE",
        "UNTIL",
    ];
    private const HEADS = ["DEFINE", "MIRROR", "ROTATE"];
    private array $identity;
    private array $solved;
    private array $state;
    private array $history = [];
    private array $redo = [];
    private array $macros = [];
    private array $saves = [];
    private array $moves = [];
    private array $rotations = [];
    private array $rotationEffects = [];
    private array $positions;
    private array $names;
    private array $pieceColors;
    public function __construct()
    {
        $this->identity = range(0, 53);
        $this->solved = [];
        foreach (self::COLORS as $color) {
            array_push($this->solved, ...array_fill(0, 9, $color));
        }
        $this->state = $this->solved;
        $this->buildMoves();
        foreach ([[], [["x", 1]], [["x", 2]], [["x", 3]], [["z", 1]], [["z", 3]]] as $prefix) {
            foreach ([[], [["y", 1]], [["y", 2]], [["y", 3]]] as $suffix) {
                $this->rotations[] = [...$prefix, ...$suffix];
            }
        }
        $this->rotationEffects = array_map(
            fn($sequence) => $this->effect($sequence),
            $this->rotations,
        );
        $corners = [
            "U9,R1,F3",
            "U7,F1,L3",
            "U1,L1,B3",
            "U3,B1,R3",
            "D3,F9,R7",
            "D1,L9,F7",
            "D7,B9,L7",
            "D9,R9,B7",
        ];
        $edges = [
            "U6,R2",
            "U8,F2",
            "U4,L2",
            "U2,B2",
            "D6,R8",
            "D2,F8",
            "D4,L8",
            "D8,B8",
            "F6,R4",
            "F4,L6",
            "B6,L4",
            "B4,R6",
        ];
        $parse = fn($groups) => array_map(
            fn($group) => array_map(
                fn($word) => array_search($word[0], self::FACES, true) * 9 + (int) $word[1] - 1,
                explode(",", $group),
            ),
            $groups,
        );
        $this->positions = [
            $parse($corners),
            $parse($edges),
            array_map(fn($face) => [$this->index($face, 2, 2)], self::FACES),
        ];
        $this->names = [self::CORNERS, self::EDGES, self::FACES];
        $this->pieceColors = array_map(
            fn($positions) => array_map(
                fn($stickers) => array_map(fn($i) => $this->solved[$i], $stickers),
                $positions,
            ),
            $this->positions,
        );
    }
    private function fail(string $message): never
    {
        throw new CubeFault("error: " . $message);
    }
    private function index(string $face, int $row, int $col): int
    {
        return array_search($face, self::FACES, true) * 9 + ($row - 1) * 3 + $col - 1;
    }
    private function compose(array $first, array $second): array
    {
        return array_map(fn($destination) => $second[$destination], $first);
    }
    private function inverse(array $sequence): array
    {
        return array_map(fn($move) => [$move[0], 4 - $move[1]], array_reverse($sequence));
    }
    private function permute(array $state, array $permutation): array
    {
        $result = array_fill(0, 54, null);
        foreach ($permutation as $source => $destination) {
            $result[$destination] = $state[$source];
        }
        return $result;
    }
    private function effect(array $sequence): array
    {
        $result = $this->identity;
        foreach ($sequence as [$letter, $amount]) {
            $result = $this->compose($result, $this->moves[$letter][$amount]);
        }
        return $result;
    }
    private function powers(string $letter, array $permutation): void
    {
        $current = $this->identity;
        for ($amount = 1; $amount <= 3; $amount++) {
            $current = $this->compose($current, $permutation);
            $this->moves[$letter][$amount] = $current;
        }
    }
    private function buildMoves(): void
    {
        foreach (["U", "R", "F", "D", "L", "B", "M", "E", "S"] as $letter) {
            $p = $this->identity;
            if (in_array($letter, self::FACES, true)) {
                for ($i = 1; $i <= 3; $i++) {
                    for ($j = 1; $j <= 3; $j++) {
                        $p[$this->index($letter, $i, $j)] = $this->index($letter, $j, 4 - $i);
                    };
                };
            }
            $put = function ($a, $i, $j, $b, $k, $l) use (&$p) {
                $p[$this->index($a, $i, $j)] = $this->index($b, $k, $l);
            };
            for ($i = 1; $i <= 3; $i++) {
                switch ($letter) {
                    case "U":
                        foreach (["F", "L", "B", "R"] as $j => $face) {
                            $put($face, 1, $i, ["L", "B", "R", "F"][$j], 1, $i);
                        }
                        break;
                    case "D":
                        foreach (["F", "R", "B", "L"] as $j => $face) {
                            $put($face, 3, $i, ["R", "B", "L", "F"][$j], 3, $i);
                        }
                        break;
                    case "R":
                        $put("F", $i, 3, "U", $i, 3);
                        $put("U", $i, 3, "B", 4 - $i, 1);
                        $put("B", $i, 1, "D", 4 - $i, 3);
                        $put("D", $i, 3, "F", $i, 3);
                        break;
                    case "L":
                        $put("U", $i, 1, "F", $i, 1);
                        $put("F", $i, 1, "D", $i, 1);
                        $put("D", $i, 1, "B", 4 - $i, 3);
                        $put("B", $i, 3, "U", 4 - $i, 1);
                        break;
                    case "F":
                        $put("U", 3, $i, "R", $i, 1);
                        $put("R", $i, 1, "D", 1, 4 - $i);
                        $put("D", 1, $i, "L", $i, 3);
                        $put("L", $i, 3, "U", 3, 4 - $i);
                        break;
                    case "B":
                        $put("U", 1, $i, "L", 4 - $i, 1);
                        $put("L", $i, 1, "D", 3, $i);
                        $put("D", 3, $i, "R", 4 - $i, 3);
                        $put("R", $i, 3, "U", 1, $i);
                        break;
                    case "M":
                        $put("U", $i, 2, "F", $i, 2);
                        $put("F", $i, 2, "D", $i, 2);
                        $put("D", $i, 2, "B", 4 - $i, 2);
                        $put("B", $i, 2, "U", 4 - $i, 2);
                        break;
                    case "E":
                        foreach (["F", "R", "B", "L"] as $j => $face) {
                            $put($face, 2, $i, ["R", "B", "L", "F"][$j], 2, $i);
                        }
                        break;
                    case "S":
                        $put("U", 2, $i, "R", $i, 2);
                        $put("R", $i, 2, "D", 2, 4 - $i);
                        $put("D", 2, $i, "L", $i, 2);
                        $put("L", $i, 2, "U", 2, 4 - $i);
                        break;
                }
            }
            $this->powers($letter, $p);
        }
        $definitions = [
            "r" => [["R", 1], ["M", 3]],
            "l" => [["L", 1], ["M", 1]],
            "u" => [["U", 1], ["E", 3]],
            "d" => [["D", 1], ["E", 1]],
            "f" => [["F", 1], ["S", 1]],
            "b" => [["B", 1], ["S", 3]],
            "x" => [["R", 1], ["M", 3], ["L", 3]],
            "y" => [["U", 1], ["E", 3], ["D", 3]],
            "z" => [["F", 1], ["S", 1], ["B", 3]],
        ];
        foreach ($definitions as $letter => $sequence) {
            $this->powers($letter, $this->effect($sequence));
        }
    }
    private function parse(string $sequence, int $base, int $lineLength): array
    {
        $position = 0;
        $syntax = function () use (&$position, $base, $lineLength) {
            $this->fail("syntax at " . min($base + $position + 1, $lineLength + 1));
        };
        $spaces = function () use (&$position, $sequence) {
            while (($sequence[$position] ?? "") === " ") {
                $position++;
            }
        };
        $power = function ($moves) use (&$position, $sequence) {
            $count = 1;
            if (preg_match("/[1-9]/", $sequence[$position] ?? "")) {
                $count = (int) $sequence[$position++];
                if (preg_match("/[0-9]/", $sequence[$position] ?? "")) {
                    $count = 10 * $count + (int) $sequence[$position++];
                }
            }
            $output = [];
            for ($i = 0; $i < $count; $i++) {
                array_push($output, ...$moves);
            }
            if (($sequence[$position] ?? "") === "'") {
                $position++;
                $output = $this->inverse($output);
            }
            return $output;
        };
        $read = null;
        $read = function () use (&$read, &$position, $sequence, $spaces, $syntax, $power) {
            $output = [];
            while (true) {
                $spaces();
                $char = $sequence[$position] ?? "";
                if ($char !== "" && str_contains(self::LETTERS, $char)) {
                    $position++;
                    $amount = 1;
                    if (in_array($sequence[$position] ?? "", ["2", "'"], true)) {
                        $amount = $sequence[$position++] === "2" ? 2 : 3;
                    }
                    $output[] = [$char, $amount];
                } elseif ($char === "(") {
                    $position++;
                    $moves = $read();
                    $spaces();
                    if (($sequence[$position] ?? "") !== ")") {
                        $syntax();
                    }
                    $position++;
                    array_push($output, ...$power($moves));
                } elseif ($char === "[") {
                    $position++;
                    $a = $read();
                    $spaces();
                    $delimiter = $sequence[$position] ?? "";
                    if (!in_array($delimiter, [",", ":"], true)) {
                        $syntax();
                    }
                    $position++;
                    $b = $read();
                    $spaces();
                    if (($sequence[$position] ?? "") !== "]") {
                        $syntax();
                    }
                    $position++;
                    $moves = [...$a, ...$b, ...$this->inverse($a)];
                    if ($delimiter === ",") {
                        array_push($moves, ...$this->inverse($b));
                    }
                    array_push($output, ...$power($moves));
                } elseif ($char === "{") {
                    $position++;
                    $start = $position;
                    while (preg_match("/[a-z]/", $sequence[$position] ?? "")) {
                        $position++;
                    }
                    $name = substr($sequence, $start, $position - $start);
                    if ($name === "" || ($sequence[$position] ?? "") !== "}") {
                        $syntax();
                    }
                    if (!array_key_exists($name, $this->macros)) {
                        $this->fail("undefined $name");
                    }
                    $position++;
                    array_push($output, ...$power($this->macros[$name]));
                } else {
                    break;
                }
            }
            return $output;
        };
        $moves = $read();
        $spaces();
        if ($position < strlen($sequence)) {
            $syntax();
        }
        if (count($moves) > 500) {
            $this->fail("too long");
        }
        return $moves;
    }
    private function moveWords(array $sequence): string
    {
        return implode(
            " ",
            array_map(
                fn($move) => $move[0] . ($move[1] === 1 ? "" : ($move[1] === 2 ? "2" : "'")),
                $sequence,
            ),
        );
    }
    private function notation(array $sequence): string
    {
        return count($sequence) . ($sequence === [] ? "" : " " . $this->moveWords($sequence));
    }
    private function axis(string $letter): string
    {
        return str_contains("RLMrlx", $letter)
            ? "x"
            : (str_contains("UDEudy", $letter)
                ? "y"
                : "z");
    }
    private function simplify(array $sequence): array
    {
        while (true) {
            $output = [];
            $position = 0;
            while ($position < count($sequence)) {
                $axis = $this->axis($sequence[$position][0]);
                $amounts = [];
                while (
                    $position < count($sequence) &&
                    $this->axis($sequence[$position][0]) === $axis
                ) {
                    [$letter, $amount] = $sequence[$position++];
                    $amounts[$letter] = (($amounts[$letter] ?? 0) + $amount) % 4;
                }
                foreach ($amounts as $letter => $amount) {
                    if ($amount !== 0) {
                        $output[] = [$letter, $amount];
                    }
                }
            }
            if ($output === $sequence) {
                return $output;
            }
            $sequence = $output;
        }
    }
    private function solved(array $state): bool
    {
        for ($face = 0; $face < 6; $face++) {
            for ($i = 0; $i < 9; $i++) {
                if ($state[$face * 9 + $i] !== $state[$face * 9 + 4]) {
                    return false;
                }
            };
        }
        return true;
    }
    private function normalize(array $state): ?array
    {
        foreach ($this->rotationEffects as $index => $permutation) {
            $rotated = $this->permute($state, $permutation);
            $valid = true;
            for ($face = 0; $face < 6; $face++) {
                if ($rotated[$face * 9 + 4] !== self::COLORS[$face]) {
                    $valid = false;
                }
            }
            if ($valid) {
                return [$index, $rotated];
            }
        }
        return null;
    }
    private function identify(array $state, int $kind): array
    {
        $output = [];
        foreach ($this->positions[$kind] as $stickers) {
            $colors = array_map(fn($i) => $state[$i], $stickers);
            $found = null;
            foreach ($this->pieceColors[$kind] as $index => $piece) {
                for ($twist = 0; $twist < count($piece); $twist++) {
                    $rotated = [
                        ...array_slice($colors, $twist),
                        ...array_slice($colors, 0, $twist),
                    ];
                    if ($rotated === $piece) {
                        $found = [$index, $twist];
                    }
                };
            }
            $output[] = $found;
        }
        return $output;
    }
    private function invalid(array $state): ?string
    {
        if (count($state) !== 54) {
            return "length " . count($state);
        }
        foreach ($state as $index => $color) {
            if (!in_array($color, self::COLORS, true)) {
                return "char " . ($index + 1);
            }
        }
        foreach (self::COLORS as $color) {
            $count = count(array_filter($state, fn($item) => $item === $color));
            if ($count !== 9) {
                return "count $color $count";
            }
        }
        $normalized = $this->normalize($state);
        if ($normalized === null) {
            return "centers";
        }
        $original = [$this->identify($state, 0), $this->identify($state, 1)];
        foreach ($original as $kind => $pieces) {
            foreach ($pieces as $index => $piece) {
                if ($piece === null) {
                    return ($kind === 0 ? "corner " : "edge ") . $this->names[$kind][$index];
                }
            };
        }
        foreach ($original as $kind => $pieces) {
            foreach ($this->names[$kind] as $index => $name) {
                if (!in_array($index, array_column($pieces, 0), true)) {
                    return "missing $name";
                }
            };
        }
        $corners = $this->identify($normalized[1], 0);
        $edges = $this->identify($normalized[1], 1);
        if (array_sum(array_column($corners, 1)) % 3 !== 0) {
            return "twist";
        }
        if (array_sum(array_column($edges, 1)) % 2 !== 0) {
            return "flip";
        }
        $parity = function ($pieces) {
            $inversions = 0;
            for ($i = 0; $i < count($pieces); $i++) {
                for ($j = $i + 1; $j < count($pieces); $j++) {
                    if ($pieces[$i][0] > $pieces[$j][0]) {
                        $inversions++;
                    }
                };
            }
            return $inversions % 2;
        };
        return $parity($corners) !== $parity($edges) ? "parity" : null;
    }
    private function cycles(array $state, int $kind): string
    {
        $pieces = $this->identify($state, $kind);
        $destinations = [];
        $orientations = [];
        foreach ($pieces as $index => [$piece, $twist]) {
            $destinations[$piece] = $index;
            $orientations[$piece] = $twist;
        }
        $seen = [];
        $output = [];
        foreach ($pieces as $start => $piece) {
            if (isset($seen[$start])) {
                continue;
            }
            $cycle = [];
            $current = $start;
            do {
                $cycle[] = $current;
                $seen[$current] = true;
                $current = $destinations[$current];
            } while ($current !== $start);
            $sum = array_sum(array_map(fn($piece) => $orientations[$piece], $cycle));
            $mark =
                $kind === 0 ? ["", "+", "-"][$sum % 3] : ($kind === 1 && $sum % 2 === 1 ? "+" : "");
            if (count($cycle) >= 2 || $mark !== "") {
                $output[] =
                    "(" .
                    implode(" ", array_map(fn($piece) => $this->names[$kind][$piece], $cycle)) .
                    ")" .
                    $mark;
            }
        }
        return $output === [] ? "none" : implode(" ", $output);
    }
    private function order(array $permutation): int
    {
        $seen = [];
        $result = 1;
        foreach ($permutation as $start => $destination) {
            if (isset($seen[$start])) {
                continue;
            }
            $current = $start;
            $length = 0;
            do {
                $seen[$current] = true;
                $length++;
                $current = $permutation[$current];
            } while ($current !== $start);
            $a = $result;
            $b = $length;
            while ($b !== 0) {
                $remainder = $a % $b;
                $a = $b;
                $b = $remainder;
            }
            $result = intdiv($result, $a) * $length;
        }
        return $result;
    }
    private function converted(array $move, array $rotation): array
    {
        $inverse = array_fill(0, 54, 0);
        foreach ($rotation as $source => $destination) {
            $inverse[$destination] = $source;
        }
        $target = $this->compose(
            $this->compose($rotation, $this->moves[$move[0]][$move[1]]),
            $inverse,
        );
        foreach ($this->moves as $letter => $amounts) {
            foreach ($amounts as $amount => $permutation) {
                if ($permutation === $target) {
                    return [$letter, $amount];
                }
            };
        }
        throw new LogicException("No matching move");
    }
    private function unrotate(array $sequence): array
    {
        $replacements = [
            "M" => [["R", 1], ["L", 3], ["x", 3]],
            "E" => [["U", 1], ["D", 3], ["y", 3]],
            "S" => [["F", 3], ["B", 1], ["z", 1]],
            "r" => [["L", 1], ["x", 1]],
            "l" => [["R", 1], ["x", 3]],
            "u" => [["D", 1], ["y", 1]],
            "d" => [["U", 1], ["y", 3]],
            "f" => [["B", 1], ["z", 1]],
            "b" => [["F", 1], ["z", 3]],
        ];
        $expanded = [];
        foreach ($sequence as [$letter, $amount]) {
            if (isset($replacements[$letter])) {
                foreach ($replacements[$letter] as [$name, $count]) {
                    $expanded[] = [$name, ($count * $amount) % 4];
                };
            } else {
                $expanded[] = [$letter, $amount];
            }
        }
        $rotation = $this->identity;
        $output = [];
        foreach ($expanded as $move) {
            if (str_contains("xyz", $move[0])) {
                $rotation = $this->compose($rotation, $this->moves[$move[0]][$move[1]]);
            } else {
                $output[] = $this->converted($move, $rotation);
            }
        }
        foreach ($this->rotationEffects as $index => $permutation) {
            if ($permutation === $rotation) {
                return [...$output, ...$this->rotations[$index]];
            }
        }
        throw new LogicException("No matching rotation");
    }
    private function search(int $depth): ?array
    {
        $candidates = [];
        foreach (self::FACES as $face) {
            for ($amount = 1; $amount <= 3; $amount++) {
                $candidates[] = [$face, $amount];
            };
        }
        $visit = null;
        $visit = function ($state, $left, $previous) use (&$visit, $candidates) {
            if ($this->solved($state)) {
                return [];
            }
            if ($left === 0) {
                return null;
            }
            foreach ($candidates as $move) {
                $face = $move[0];
                if (
                    $face === $previous ||
                    in_array([$previous, $face], [["D", "U"], ["L", "R"], ["B", "F"]], true)
                ) {
                    continue;
                }
                $tail = $visit(
                    $this->permute($state, $this->moves[$face][$move[1]]),
                    $left - 1,
                    $face,
                );
                if ($tail !== null) {
                    return [$move, ...$tail];
                }
            }
            return null;
        };
        for ($limit = 0; $limit <= $depth; $limit++) {
            $found = $visit($this->state, $limit, null);
            if ($found !== null) {
                return $found;
            }
        }
        return null;
    }
    public function command(string $line): void
    {
        [$command, $argument] = array_pad(explode(" ", $line, 2), 2, null);
        try {
            if (
                !in_array(
                    $command,
                    [
                        ...self::NO_ARGS,
                        ...array_keys(self::WORDS),
                        ...self::SEQUENCES,
                        ...self::HEADS,
                    ],
                    true,
                )
            ) {
                $this->fail("unknown command $command");
            }
            $words = $argument === null ? [] : explode(" ", $argument);
            if (in_array($command, self::NO_ARGS, true) && $argument !== null) {
                $this->fail("bad arguments");
            }
            if (isset(self::WORDS[$command]) && count($words) !== self::WORDS[$command]) {
                $this->fail("bad arguments");
            }
            if (in_array($command, ["UNDO", "REDO", "SEARCH", "SCRAMBLE"], true)) {
                foreach ($words as $word) {
                    if (!preg_match("/\A(?:0|[1-9][0-9]{0,9})\z/", $word)) {
                        $this->fail("bad arguments");
                    }
                };
            }
            if (
                in_array($command, ["SAVE", "RESTORE"], true) &&
                !preg_match("/\A[a-z]{1,8}\z/", $words[0])
            ) {
                $this->fail("bad arguments");
            }
            $moves = [];
            if (in_array($command, self::HEADS, true)) {
                if ($argument === null) {
                    $this->fail("bad arguments");
                }
                [$head, $sequence] = array_pad(explode(" ", $argument, 2), 2, "");
                $valid = match ($command) {
                    "DEFINE" => preg_match("/\A[a-z]{1,8}\z/", $head),
                    "MIRROR" => in_array($head, ["LR", "UD", "FB"], true),
                    "ROTATE" => preg_match("/\A[xyz](?:2|')?\z/", $head),
                };
                if (!$valid) {
                    $this->fail("bad arguments");
                }
                $moves = $this->parse(
                    $sequence,
                    strlen($command) + strlen($head) + 2,
                    strlen($line),
                );
            } elseif (in_array($command, self::SEQUENCES, true)) {
                $moves = $this->parse($argument ?? "", strlen($command) + 1, strlen($line));
            }
            if (in_array($command, ["UNDO", "REDO"], true) && (int) $words[0] < 1) {
                $this->fail("bad value");
            }
            if ($command === "SEARCH" && (int) $words[0] > 4) {
                $this->fail("bad value");
            }
            if (
                $command === "SCRAMBLE" &&
                ((int) $words[0] < 1 ||
                    (int) $words[0] > 50 ||
                    (int) $words[1] < 1 ||
                    (int) $words[1] > 2147483646)
            ) {
                $this->fail("bad value");
            }
            if (
                $command === "WHERE" &&
                !in_array($words[0], [...self::CORNERS, ...self::EDGES], true)
            ) {
                $this->fail("unknown piece $words[0]");
            }
            switch ($command) {
                case "RESET":
                    $this->state = $this->solved;
                    $this->history = [];
                    $this->redo = [];
                    echo "reset\n";
                    break;
                case "SHOW":
                    foreach (["U", "LFRB", "D"] as $faces) {
                        for ($row = 1; $row <= 3; $row++) {
                            $colors = [];
                            foreach (str_split($faces) as $face) {
                                for ($col = 1; $col <= 3; $col++) {
                                    $colors[] = $this->state[$this->index($face, $row, $col)];
                                };
                            }
                            echo (strlen($faces) === 1 ? "      " : "") .
                                implode(" ", $colors) .
                                "\n";
                        };
                    }
                    break;
                case "STATE":
                    echo "state " . implode("", $this->state) . "\n";
                    break;
                case "ISSOLVED":
                    $count = 0;
                    foreach ($this->state as $i => $color) {
                        if ($color !== $this->state[intdiv($i, 9) * 9 + 4]) {
                            $count++;
                        }
                    }
                    echo $count === 0 ? "solved\n" : "unsolved $count\n";
                    break;
                case "HISTORY":
                    echo "history " . $this->notation($this->history) . "\n";
                    break;
                case "SOLUTION":
                    echo "solution " .
                        $this->notation($this->simplify($this->inverse($this->history))) .
                        "\n";
                    break;
                case "ANALYZE":
                    [$rotation, $state] = $this->normalize($this->state);
                    echo "rotation " .
                        ($rotation === 0 ? "none" : $this->moveWords($this->rotations[$rotation])) .
                        "\n";
                    echo "corners " .
                        $this->cycles($state, 0) .
                        "\nedges " .
                        $this->cycles($state, 1) .
                        "\n";
                    break;
                case "STAGE":
                    [, $state] = $this->normalize($this->state);
                    $corners = $this->identify($state, 0);
                    $edges = $this->identify($state, 1);
                    $cross = 0;
                    $slots = 0;
                    for ($i = 4; $i <= 7; $i++) {
                        if ($edges[$i] === [$i, 0]) {
                            $cross++;
                        }
                        if ($corners[$i] === [$i, 0] && $edges[$i + 4] === [$i + 4, 0]) {
                            $slots++;
                        }
                    }
                    $top = count(
                        array_filter(array_slice($state, 0, 9), fn($color) => $color === "W"),
                    );
                    $stage = $this->solved($state)
                        ? "solved"
                        : ($cross === 4 && $slots === 4 && $top === 9
                            ? "oll"
                            : ($cross === 4 && $slots === 4
                                ? "f2l"
                                : ($cross === 4
                                    ? "cross"
                                    : "none")));
                    echo "stage $stage cross $cross slots $slots top $top\n";
                    break;
                case "MACROS":
                    echo "macros " . count($this->macros) . "\n";
                    $macros = $this->macros;
                    ksort($macros, SORT_STRING);
                    foreach ($macros as $name => $sequence) {
                        echo "macro $name " . $this->notation($sequence) . "\n";
                    }
                    break;
                case "CHECK":
                case "LOAD":
                    $state = str_split($words[0]);
                    $reason = $this->invalid($state);
                    if ($command === "CHECK") {
                        echo $reason === null ? "valid\n" : "invalid $reason\n";
                    } else {
                        if ($reason !== null) {
                            $this->fail("invalid $reason");
                        }
                        $this->state = $state;
                        $this->history = [];
                        $this->redo = [];
                        echo "loaded\n";
                    }
                    break;
                case "UNDO":
                case "REDO":
                    $source = $command === "UNDO" ? $this->history : $this->redo;
                    if ($source === []) {
                        $this->fail($command === "UNDO" ? "nothing to undo" : "nothing to redo");
                    }
                    $count = min((int) $words[0], count($source));
                    for ($i = 0; $i < $count; $i++) {
                        $move =
                            $command === "UNDO"
                                ? array_pop($this->history)
                                : array_pop($this->redo);
                        $this->state = $this->permute(
                            $this->state,
                            $this->moves[$move[0]][$command === "UNDO" ? 4 - $move[1] : $move[1]],
                        );
                        if ($command === "UNDO") {
                            $this->redo[] = $move;
                        } else {
                            $this->history[] = $move;
                        }
                    }
                    echo ($command === "UNDO" ? "undone " : "redone ") . $count . "\n";
                    break;
                case "SEARCH":
                    $found = $this->search((int) $words[0]);
                    echo $found === null
                        ? "not found\n"
                        : "found " . $this->notation($found) . "\n";
                    break;
                case "WHERE":
                    [, $state] = $this->normalize($this->state);
                    $kind = in_array($words[0], self::CORNERS, true) ? 0 : 1;
                    $wanted = array_search($words[0], $this->names[$kind], true);
                    foreach ($this->identify($state, $kind) as $position => [$piece, $twist]) {
                        if ($piece === $wanted) {
                            echo "$words[0] at " .
                                $this->names[$kind][$position] .
                                ($kind === 0 ? " twist " : " flip ") .
                                $twist .
                                "\n";
                        }
                    }
                    break;
                case "SAVE":
                    $this->saves[$words[0]] = [$this->state, $this->history];
                    echo "saved $words[0]\n";
                    break;
                case "RESTORE":
                    if (!isset($this->saves[$words[0]])) {
                        $this->fail("no save $words[0]");
                    }
                    [$this->state, $this->history] = $this->saves[$words[0]];
                    $this->redo = [];
                    echo "restored $words[0]\n";
                    break;
                case "SCRAMBLE":
                case "APPLY":
                    if ($command === "SCRAMBLE") {
                        $moves = [];
                        $random = (int) $words[1];
                        for ($i = 0; $i < (int) $words[0]; $i++) {
                            $usable = array_values(
                                array_filter(self::FACES, function ($face) use ($moves) {
                                    $n = count($moves);
                                    return !($n >= 1 && $face === $moves[$n - 1][0]) &&
                                        !(
                                            $n >= 2 &&
                                            $this->axis($moves[$n - 1][0]) ===
                                                $this->axis($moves[$n - 2][0]) &&
                                            $this->axis($face) === $this->axis($moves[$n - 1][0])
                                        );
                                }),
                            );
                            $random = ($random * 48271) % 2147483647;
                            $face = $usable[$random % count($usable)];
                            $random = ($random * 48271) % 2147483647;
                            $moves[] = [$face, [1, 3, 2][$random % 3]];
                        }
                    }
                    $this->state = $this->permute($this->state, $this->effect($moves));
                    array_push($this->history, ...$moves);
                    $this->redo = [];
                    echo $command === "APPLY"
                        ? "applied " . count($moves) . "\n"
                        : "scramble " . $this->moveWords($moves) . "\n";
                    break;
                case "INVERT":
                    echo "inverse " . $this->notation($this->inverse($moves)) . "\n";
                    break;
                case "SIMPLIFY":
                    echo "simplified " . $this->notation($this->simplify($moves)) . "\n";
                    break;
                case "METRICS":
                    $htm = $qtm = $stm = 0;
                    foreach ($moves as [$letter, $amount]) {
                        if (str_contains("xyz", $letter)) {
                            continue;
                        }
                        $weight = str_contains("MES", $letter) ? 2 : 1;
                        $htm += $weight;
                        $qtm += $weight * ($amount === 2 ? 2 : 1);
                        $stm++;
                    }
                    echo "metrics htm $htm qtm $qtm stm $stm etm " . count($moves) . "\n";
                    break;
                case "ORDER":
                    echo "order " . $this->order($this->effect($moves)) . "\n";
                    break;
                case "CYCLES":
                    $state = $this->permute($this->solved, $this->effect($moves));
                    foreach (["corners", "edges", "centers"] as $kind => $name) {
                        echo $name . " " . $this->cycles($state, $kind) . "\n";
                    }
                    break;
                case "UNROTATE":
                    echo "unrotated " . $this->notation($this->unrotate($moves)) . "\n";
                    break;
                case "UNTIL":
                    $permutation = $this->effect($moves);
                    $state = $this->state;
                    $found = null;
                    $order = $this->order($permutation);
                    for ($count = 1; $count <= $order; $count++) {
                        $state = $this->permute($state, $permutation);
                        if ($this->solved($state)) {
                            $found = $count;
                            break;
                        }
                    }
                    echo "until " . ($found ?? "never") . "\n";
                    break;
                case "DEFINE":
                    $this->macros[$head] = $moves;
                    echo "defined $head " . count($moves) . "\n";
                    break;
                case "MIRROR":
                    $mirrorAxis = ["LR" => "x", "UD" => "y", "FB" => "z"][$head];
                    $transformed = [];
                    foreach ($moves as [$letter, $amount]) {
                        if ($this->axis($letter) !== $mirrorAxis) {
                            $transformed[] = [$letter, 4 - $amount];
                        } elseif (str_contains("MESxyz", $letter)) {
                            $transformed[] = [$letter, $amount];
                        } else {
                            $transformed[] = [
                                strtr($letter, "RLUDFBrludfb", "LRDUBFlrdubf"),
                                4 - $amount,
                            ];
                        }
                    }
                    echo "mirror " . $this->notation($transformed) . "\n";
                    break;
                case "ROTATE":
                    $amount = strlen($head) === 1 ? 1 : ($head[1] === "2" ? 2 : 3);
                    $rotation = $this->moves[$head[0]][$amount];
                    echo "rotated " .
                        $this->notation(
                            array_map(fn($move) => $this->converted($move, $rotation), $moves),
                        ) .
                        "\n";
                    break;
            }
        } catch (CubeFault $error) {
            echo $error->getMessage() . "\n";
        }
    }
    public function run(): void
    {
        $count = (int) fgets(STDIN);
        for ($i = 0; $i < $count; $i++) {
            $this->command(rtrim(fgets(STDIN), "\r\n"));
        }
    }
}
new Cube()->run();
