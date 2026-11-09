<?php
require_once __DIR__ . '/clues.php';
require_once __DIR__ . '/line_solver.php';
require_once __DIR__ . '/propagation.php';
require_once __DIR__ . '/search.php';
require_once __DIR__ . '/render.php';

function readBlocks(string $name): array {
    $blocks = []; $block = null; foreach (file('input/' . $name, FILE_IGNORE_NEW_LINES) as $line) { if ($block === null) { if ($line !== '' && !str_starts_with($line, '#')) $block = [$line]; } elseif ($line === 'END') { $blocks[] = $block; $block = null; } else $block[] = $line; } return $blocks;
}
function joinParagraphs(array $paragraphs): array { $lines = []; foreach ($paragraphs as $paragraph) { if ($lines) $lines[] = ''; array_push($lines, ...$paragraph); } return $lines; }
function writeLines(string $name, array $lines): void { file_put_contents('output/' . $name, implode("\n", $lines) . "\n"); }
function validName(string $name): bool { return (bool)preg_match('/\A[a-z0-9_]{1,20}\z/', $name); }
function numberList(array $numbers): string { return $numbers ? implode(',', $numbers) : '-'; }
function cellText(int $row, int $column): string { return ($row + 1) . ',' . ($column + 1); }
function stateGrid(array $texts): array { return array_map(fn($text) => array_map('charState', str_split($text)), $texts); }
function gridColumns(array $grid): array { $columns = []; for ($c = 0; $c < count($grid[0]); $c++) $columns[] = array_column($grid, $c); return $columns; }
function differingCells(array $first, array $second): array { $cells = []; foreach ($first as $r => $row) foreach ($row as $c => $state) if ($state !== $second[$r][$c]) $cells[] = [$r, $c]; return $cells; }
final class Puzzle {
    public string $name;
    public int $width, $height;
    public array $rowLines, $columnLines = [], $givenLines = [], $rows = [], $columns = [], $givens = [];
    public ?array $answerLines, $answer = null;
    public function __construct(array $lines) {
        $this->name = substr($lines[0], 7); $size = explode(' ', $lines[1]); $this->width = (int)$size[1]; $this->height = (int)$size[2]; $at = array_search('COLUMNS', $lines, true); $this->rowLines = array_slice($lines, 3, $at - 3); $position = $at + 1;
        while ($position < count($lines) && isClueLine($lines[$position])) $this->columnLines[] = $lines[$position++];
        while ($position < count($lines) && str_starts_with($lines[$position], 'GIVEN ')) { $parts = explode(' ', $lines[$position++]); $this->givenLines[] = [(int)$parts[1], (int)$parts[2], $parts[3]]; }
        $this->answerLines = $position < count($lines) ? array_slice($lines, $position + 1) : null;
    }
    public function validate(array $earlier): ?string {
        if (!validName($this->name)) return 'bad name'; if (isset($earlier[$this->name])) return 'duplicate name'; if ($this->width < 1 || $this->width > 30 || $this->height < 1 || $this->height > 30) return 'bad size';
        if (count($this->rowLines) !== $this->height) return 'row count ' . count($this->rowLines) . " expected $this->height";
        if (count($this->columnLines) !== $this->width) return 'column count ' . count($this->columnLines) . " expected $this->width";
        foreach ([['row', $this->rowLines, $this->width], ['column', $this->columnLines, $this->height]] as [$kind, $texts, $length]) foreach ($texts as $j => $text) {
            $number = $j + 1; $clue = parseClue($text); if ($clue === null) return "bad clue $kind $number"; if (!fitsClue($clue, $length)) return "$kind $number too long"; if ($kind === 'row') $this->rows[] = $clue; else $this->columns[] = $clue;
        }
        $a = 0; $b = 0; foreach ($this->rows as $clue) $a += array_sum($clue); foreach ($this->columns as $clue) $b += array_sum($clue); if ($a !== $b) return "total mismatch rows=$a columns=$b";
        $taken = []; foreach ($this->givenLines as $j => [$r, $c, $value]) {
            $number = $j + 1; if ($r < 1 || $r > $this->height || $c < 1 || $c > $this->width || !in_array($value, ['#', '.'], true)) return "bad given $number";
            $key = "$r,$c"; if (isset($taken[$key])) return "duplicate given $number"; $taken[$key] = true; $this->givens[] = [$r - 1, $c - 1, charState($value)];
        }
        if ($this->answerLines !== null) { if (count($this->answerLines) !== $this->height) return 'bad answer'; foreach ($this->answerLines as $line) if (strlen($line) !== $this->width || strspn($line, '#.?') !== strlen($line)) return 'bad answer'; $this->answer = stateGrid($this->answerLines); } return null;
    }
}
function logicalSolve(array $rows, array $columns, array $givens, bool $precise): array {
    $grid = array_fill(0, count($rows), array_fill(0, count($columns), CELL_UNKNOWN)); foreach ($givens as [$r, $c, $state]) $grid[$r][$c] = $state;
    $propagation = propagate($grid, $rows, $columns, $precise, array_fill(0, count($rows), true), array_fill(0, count($columns), true)); return [$grid, $propagation];
}
function solvingResult(array $grid, Propagation $propagation): string { return $propagation->conflict !== null ? 'contradiction at=' . $propagation->conflict->label() : (determinedCount($grid) === count($grid) * count($grid[0]) ? 'solved' : 'stuck'); }
final class Analysis {
    public array $simpleGrid, $logicGrid, $solutions = [];
    public Propagation $simple, $logic;
    public string $simpleResult, $logicResult, $status, $difficulty = '-';
    public ?Search $search = null;
    public int $lineSolves, $guesses = 0, $maxDepth = 0;
    public function __construct(array $rows, array $columns, array $givens) {
        [$this->simpleGrid, $this->simple] = logicalSolve($rows, $columns, $givens, false); [$this->logicGrid, $this->logic] = logicalSolve($rows, $columns, $givens, true);
        $this->simpleResult = solvingResult($this->simpleGrid, $this->simple); $this->logicResult = solvingResult($this->logicGrid, $this->logic);
        if ($this->logic->conflict !== null) $this->status = 'contradiction';
        elseif ($this->logicResult === 'solved') { $this->status = 'unique'; $this->solutions = [$this->logicGrid]; $this->difficulty = $this->simpleResult === 'solved' ? 'easy' : 'medium'; }
        else { $this->search = new Search($rows, $columns); $this->search->run($this->logicGrid); $this->solutions = $this->search->solutions; $this->status = ['none', 'unique', 'multiple'][count($this->solutions)]; if ($this->status === 'unique') $this->difficulty = 'hard'; }
        $this->lineSolves = $this->logic->lineSolves(); if ($this->search !== null) { $this->lineSolves += $this->search->lineSolves(); $this->guesses = $this->search->guessCount(); $this->maxDepth = $this->search->maxDepth(); }
    }
}
function clueStatistics(array $rows, array $columns): string {
    $rowBlocks = $columnBlocks = $filled = $maximum = $fixed = 0;
    foreach ($rows as $clue) { $rowBlocks += count($clue); $filled += array_sum($clue); if (!$clue || clueSpan($clue) === count($columns)) $fixed++; foreach ($clue as $length) $maximum = max($maximum, $length); }
    foreach ($columns as $clue) { $columnBlocks += count($clue); if (!$clue || clueSpan($clue) === count($rows)) $fixed++; foreach ($clue as $length) $maximum = max($maximum, $length); }
    return "row_blocks=$rowBlocks column_blocks=$columnBlocks filled=$filled max_block=$maximum fixed_lines=$fixed";
}
function stepStatistics(Propagation $propagation): string {
    $productive = $idle = $best = 0; $at = '-'; foreach ($propagation->steps as $step) { if ($step->contradiction) continue; if ($step->gain > 0) $productive++; else $idle++; if ($step->gain > $best) { $best = $step->gain; $at = $step->label(); } } return "productive=$productive idle=$idle best=$best at=$at";
}
function featuresText(array $grid): string {
    $height = count($grid); $width = count($grid[0]); $seen = array_fill(0, $height, array_fill(0, $width, false)); $filled = $components = $largest = 0; $minRow = $height; $minColumn = $width; $maxRow = $maxColumn = -1;
    foreach ($grid as $r => $row) foreach ($row as $c => $state) if ($state === CELL_FILLED) {
        $filled++; $minRow = min($minRow, $r); $minColumn = min($minColumn, $c); $maxRow = max($maxRow, $r); $maxColumn = max($maxColumn, $c); if ($seen[$r][$c]) continue;
        $components++; $pending = [[$r, $c]]; $seen[$r][$c] = true; $size = 0;
        while ($pending) { [$rr, $cc] = array_pop($pending); $size++; foreach ([[-1, 0], [1, 0], [0, -1], [0, 1]] as [$dr, $dc]) { $nr = $rr + $dr; $nc = $cc + $dc; if (0 <= $nr && $nr < $height && 0 <= $nc && $nc < $width && $grid[$nr][$nc] === CELL_FILLED && !$seen[$nr][$nc]) { $seen[$nr][$nc] = true; $pending[] = [$nr, $nc]; } } } $largest = max($largest, $size);
    }
    $symmetries = []; foreach ([['lr', false, true], ['ud', true, false], ['rot180', true, true]] as [$name, $flipRows, $flipColumns]) { $matches = true; foreach ($grid as $r => $row) foreach ($row as $c => $state) if ($state !== $grid[$flipRows ? $height - 1 - $r : $r][$flipColumns ? $width - 1 - $c : $c]) $matches = false; if ($matches) $symmetries[] = $name; }
    $bbox = $filled === 0 ? '-' : ($minRow + 1) . ',' . ($minColumn + 1) . ',' . ($maxRow + 1) . ',' . ($maxColumn + 1); return "filled=$filled components=$components largest=$largest bbox=$bbox symmetry=" . ($symmetries ? implode(',', $symmetries) : 'none');
}
function unknownSummary(array $lines): string { $parts = []; foreach ($lines as $j => $cells) { $count = count(array_filter($cells, fn($state) => $state === CELL_UNKNOWN)); if ($count > 0) $parts[] = ($j + 1) . ":$count"; } return implode(' ', $parts); }
function evaluateGivens(Puzzle $puzzle, Analysis $analysis): ?string {
    if (!$puzzle->givens || $analysis->status === 'multiple') return null; $unique = $analysis->status === 'unique'; $numbers = [];
    foreach ($puzzle->givens as $j => $given) { $others = $puzzle->givens; array_splice($others, $j, 1); $status = (new Analysis($puzzle->rows, $puzzle->columns, $others))->status; if ($status === 'unique' || (!$unique && $status === 'multiple')) $numbers[] = $j + 1; } return 'givens ' . ($unique ? 'redundant=' : 'blame=') . numberList($numbers);
}
final class Grading {
    public array $rows = [], $columns = [], $givens = [];
    public int $known;
    public string $result;
    public ?string $extendable = null;
    public ?int $differs = null;
    public function __construct(private Puzzle $puzzle, Analysis $analysis) {
        $answer = $puzzle->answer; foreach ($answer as $r => $row) if (!hasPlacement($row, $puzzle->rows[$r])) $this->rows[] = $r;
        foreach (gridColumns($answer) as $c => $column) if (!hasPlacement($column, $puzzle->columns[$c])) $this->columns[] = $c;
        $givenCells = []; foreach ($puzzle->givens as $j => [$r, $c, $state]) { $givenCells["$r,$c"] = true; if ($answer[$r][$c] !== CELL_UNKNOWN && $answer[$r][$c] !== $state) $this->givens[] = $j + 1; }
        $this->known = determinedCount($answer); $mismatch = (bool)($this->rows || $this->columns || $this->givens);
        if ($this->known < $puzzle->width * $puzzle->height) {
            $this->result = 'partial'; $canExtend = false; if (!$mismatch) { $givens = $puzzle->givens; foreach ($answer as $r => $row) foreach ($row as $c => $state) if ($state !== CELL_UNKNOWN && !isset($givenCells["$r,$c"])) $givens[] = [$r, $c, $state]; $status = (new Analysis($puzzle->rows, $puzzle->columns, $givens))->status; $canExtend = in_array($status, ['unique', 'multiple'], true); } $this->extendable = $canExtend ? 'yes' : 'no';
        } else $this->result = $mismatch ? 'wrong' : 'correct';
        if ($analysis->status === 'unique') { $this->differs = 0; foreach ($answer as $r => $row) foreach ($row as $c => $state) if ($state !== CELL_UNKNOWN && $state !== $analysis->solutions[0][$r][$c]) $this->differs++; }
    }
    public function lines(): array {
        $puzzle = $this->puzzle; $text = "answer result=$this->result known=$this->known rows=" . numberList(array_map(fn($r) => $r + 1, $this->rows)) . ' columns=' . numberList(array_map(fn($c) => $c + 1, $this->columns)) . ' givens=' . numberList($this->givens);
        if ($this->extendable !== null) $text .= " extendable=$this->extendable"; if ($this->differs !== null) $text .= " differs=$this->differs"; $lines = [$text];
        foreach ([[true, $this->rows], [false, $this->columns]] as [$isRow, $indices]) foreach ($indices as $index) { $clue = $isRow ? $puzzle->rows[$index] : $puzzle->columns[$index]; $cells = lineCells($puzzle->answer, $isRow, $index); $lines[] = 'mismatch ' . lineLabel($isRow, $index) . ' expected=' . commaClue($clue) . ($this->result === 'partial' ? ' cells=' . stateString($cells) : ' got=' . commaClue(runClue($cells))); } return $lines;
    }
}
final class PuzzleReport {
    public Analysis $analysis;
    public ?Grading $grading;
    private ?string $evaluation;
    public function __construct(public Puzzle $puzzle) { $this->analysis = new Analysis($puzzle->rows, $puzzle->columns, $puzzle->givens); $this->evaluation = evaluateGivens($puzzle, $this->analysis); $this->grading = $puzzle->answer === null ? null : new Grading($puzzle, $this->analysis); }
    public function score(): int { return $this->analysis->lineSolves + 25 * $this->analysis->guesses; }
    public function paragraph(): array {
        $p = $this->puzzle; $a = $this->analysis;
        $lines = ["PUZZLE $p->name", "size={$p->width}x{$p->height} givens=" . count($p->givens) . " status=$a->status difficulty=$a->difficulty", 'clues ' . clueStatistics($p->rows, $p->columns), 'simple known=' . determinedCount($a->simpleGrid) . ' line_solves=' . $a->simple->lineSolves() . " result=$a->simpleResult", 'logic known=' . determinedCount($a->logicGrid) . ' line_solves=' . $a->logic->lineSolves() . " result=$a->logicResult", 'steps ' . stepStatistics($a->logic)];
        if ($p->width * $p->height <= 49) $lines[] = 'trace ' . $a->logic->record();
        if ($a->logicResult === 'stuck') $lines[] = 'stuck rows=' . unknownSummary($a->logicGrid) . ' columns=' . unknownSummary(gridColumns($a->logicGrid));
        if ($a->status === 'contradiction') { $step = $a->logic->conflict; $clue = $step->isRow ? $p->rows[$step->index] : $p->columns[$step->index]; $lines[] = 'conflict line=' . $step->label() . ' clue=' . commaClue($clue) . ' cells=' . stateString(lineCells($a->logicGrid, $step->isRow, $step->index)); }
        if ($a->search !== null) {
            $search = $a->search; $lines[] = 'search guesses=' . $search->guessCount() . ' max_depth=' . $search->maxDepth() . " backtracks=$search->backtracks solutions=" . count($search->solutions) . ' line_solves=' . $search->lineSolves();
            foreach ($search->guesses as $guess) $lines[] = "guess $guess->number depth=$guess->depth cell=" . cellText($guess->row, $guess->column) . ' value=' . stateChar($guess->value) . " solves=$guess->solves known=$guess->known result=$guess->result";
        }
        if ($a->status === 'multiple') { $cells = differingCells($a->solutions[0], $a->solutions[1]); $lines[] = 'differ count=' . count($cells) . ' cells=' . implode(' ', array_map(fn($cell) => cellText(...$cell), $cells)); }
        $names = []; $grids = [];
        if ($a->status === 'contradiction') { $names[] = 'partial'; $grids[] = $a->logicGrid; }
        else { if ($a->simpleResult === 'stuck') { $names[] = 'simple'; $grids[] = $a->simpleGrid; } if ($a->logicResult === 'stuck') { $names[] = 'logic'; $grids[] = $a->logicGrid; } if ($a->status === 'multiple') { array_push($names, 'first', 'second'); array_push($grids, ...$a->solutions); } }
        if ($names) array_push($lines, ...gridDisplay($names, $grids));
        if ($a->status === 'unique') { $lines[] = 'sheet'; array_push($lines, ...answerSheet($p->rows, $p->columns, $a->solutions[0])); $lines[] = 'picture ' . featuresText($a->solutions[0]); }
        if ($this->evaluation !== null) $lines[] = $this->evaluation; if ($this->grading !== null) array_push($lines, ...$this->grading->lines()); return $lines;
    }
    public function statsRow(): string {
        $p = $this->puzzle; $a = $this->analysis; return implode(',', [$p->name, $a->status, $a->difficulty, $p->width, $p->height, count($p->givens), determinedCount($a->simpleGrid), determinedCount($a->logicGrid), $a->lineSolves, $a->guesses, $a->maxDepth, count($a->solutions), $this->grading?->result ?? '-']);
    }
}
function processPuzzles(array $blocks): array {
    $names = []; $reports = []; $paragraphs = []; $stats = ['puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer'];
    foreach ($blocks as $lines) {
        $puzzle = new Puzzle($lines); $error = $puzzle->validate($names); $names[$puzzle->name] = true;
        if ($error !== null) { $paragraphs[] = ["PUZZLE $puzzle->name", "error $error"]; $stats[] = $puzzle->name . ',invalid' . str_repeat(',-', 11); continue; }
        $report = new PuzzleReport($puzzle); $reports[] = $report; $paragraphs[] = $report->paragraph(); $stats[] = $report->statsRow();
    }
    $ranked = array_values(array_filter($reports, fn($report) => $report->analysis->status === 'unique')); $difficulty = ['easy' => 0, 'medium' => 1, 'hard' => 2];
    usort($ranked, fn($a, $b) => ($difficulty[$a->analysis->difficulty] <=> $difficulty[$b->analysis->difficulty]) ?: (($a->score() <=> $b->score()) ?: strcmp($a->puzzle->name, $b->puzzle->name)));
    $ranking = ['RANKING']; foreach ($ranked as $j => $report) { $p = $report->puzzle; $a = $report->analysis; $ranking[] = 'rank ' . ($j + 1) . " $p->name $a->difficulty score=" . $report->score() . " size={$p->width}x{$p->height}"; } $paragraphs[] = $ranking;
    $statuses = array_fill_keys(['contradiction', 'none', 'unique', 'multiple'], 0); $difficulties = array_fill_keys(['easy', 'medium', 'hard'], 0); $lineSolves = $guesses = 0;
    foreach ($reports as $report) { $a = $report->analysis; $statuses[$a->status]++; if (isset($difficulties[$a->difficulty])) $difficulties[$a->difficulty]++; $lineSolves += $a->lineSolves; $guesses += $a->guesses; }
    $paragraphs[] = ['SUMMARY puzzles=' . count($blocks) . ' invalid=' . (count($blocks) - count($reports)) . " contradiction={$statuses['contradiction']} none={$statuses['none']} unique={$statuses['unique']} multiple={$statuses['multiple']} easy={$difficulties['easy']} medium={$difficulties['medium']} hard={$difficulties['hard']} line_solves=$lineSolves guesses=$guesses"];
    writeLines('solutions.txt', joinParagraphs($paragraphs)); writeLines('stats.csv', $stats); return $reports;
}
final class Picture {
    public string $name;
    public array $rows;
    public function __construct(array $lines) { $this->name = substr($lines[0], 8); $this->rows = array_slice($lines, 1); }
    public function validate(array $earlier): ?string {
        if (!validName($this->name)) return 'bad name'; if (isset($earlier[$this->name])) return 'duplicate name'; if (count($this->rows) < 1 || count($this->rows) > 30) return 'bad height'; $width = strlen($this->rows[0]);
        foreach ($this->rows as $j => $row) if (strlen($row) < 1 || strlen($row) > 30 || strlen($row) !== $width || strspn($row, '#.') !== strlen($row)) return 'bad row ' . ($j + 1); return null;
    }
}
final class Generation {
    public array $rows, $columns, $givens = [], $log = [];
    public Analysis $initial, $final;
    public function __construct(public array $grid) {
        $this->rows = array_map('runClue', $grid); $this->columns = array_map('runClue', gridColumns($grid)); $this->initial = $this->analyze([]); $analysis = $this->initial;
        while ($analysis->status === 'multiple') { [$r, $c] = differingCells($analysis->solutions[0], $analysis->solutions[1])[0]; $added = $this->appendGiven($r, $c); $analysis = $this->analyze($this->givens); $this->log[] = '# hint ' . count($this->givens) . " $added status=$analysis->status"; }
        $original = $this->givens; foreach ($original as $given) { $others = array_values(array_filter($this->givens, fn($other) => $other !== $given)); if ($this->analyze($others)->status === 'unique') { $this->givens = $others; $this->log[] = '# drop cell=' . cellText($given[0], $given[1]); } }
        $this->final = $this->analyze($this->givens); $number = 0;
        while ($this->final->difficulty === 'hard') { [$r, $c] = guessCell($this->final->logicGrid); $added = $this->appendGiven($r, $c); $this->final = $this->analyze($this->givens); $number++; $this->log[] = "# logic hint $number $added difficulty={$this->final->difficulty}"; }
    }
    private function analyze(array $givens): Analysis { return new Analysis($this->rows, $this->columns, $givens); }
    private function appendGiven(int $r, int $c): string { $state = $this->grid[$r][$c]; $this->givens[] = [$r, $c, $state]; return 'cell=' . cellText($r, $c) . ' value=' . stateChar($state); }
    public function puzzleLines(string $name): array {
        $lines = ["PUZZLE $name", 'SIZE ' . count($this->columns) . ' ' . count($this->rows), 'ROWS']; foreach ($this->rows as $clue) $lines[] = spaced($clue); $lines[] = 'COLUMNS'; foreach ($this->columns as $clue) $lines[] = spaced($clue);
        $givens = $this->givens; usort($givens, fn($a, $b) => ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1])); foreach ($givens as [$r, $c, $state]) $lines[] = 'GIVEN ' . ($r + 1) . ' ' . ($c + 1) . ' ' . stateChar($state); $lines[] = 'END'; return $lines;
    }
    public function paragraph(Picture $picture, array $reports): array {
        $duplicate = '-'; foreach ($reports as $report) if ($report->puzzle->rows === $this->rows && $report->puzzle->columns === $this->columns) { $duplicate = $report->puzzle->name; break; }
        $initial = $this->initial; $final = $this->final;
        $lines = ["# picture $picture->name size=" . count($this->columns) . 'x' . count($this->rows) . ' ' . featuresText($this->grid), '# clues ' . clueStatistics($this->rows, $this->columns) . " duplicate_of=$duplicate", "# plain status=$initial->status difficulty=$initial->difficulty line_solves=$initial->lineSolves guesses=$initial->guesses"];
        array_push($lines, ...$this->log); $lines[] = "# final status=$final->status difficulty=$final->difficulty hints=" . count($this->givens) . " line_solves=$final->lineSolves guesses=$final->guesses"; array_push($lines, ...$this->puzzleLines($picture->name)); return $lines;
    }
}
function processPictures(array $blocks, array $reports): void {
    $names = []; $paragraphs = []; $valid = $unique = $lineLogic = $hinted = $hints = 0;
    foreach ($blocks as $lines) { $picture = new Picture($lines); $error = $picture->validate($names); $names[$picture->name] = true; if ($error !== null) { $paragraphs[] = ["# picture $picture->name error $error"]; continue; }
        $generation = new Generation(stateGrid($picture->rows)); $valid++; if ($generation->initial->status === 'unique') $unique++; if (in_array($generation->initial->difficulty, ['easy', 'medium'], true)) $lineLogic++; if ($generation->givens) $hinted++; $hints += count($generation->givens); $paragraphs[] = $generation->paragraph($picture, $reports);
    }
    $paragraphs[] = ['# SUMMARY pictures=' . count($blocks) . ' invalid=' . (count($blocks) - $valid) . " unique=$unique line_logic=$lineLogic hinted=$hinted hints=$hints"]; writeLines('generated.txt', joinParagraphs($paragraphs));
}
if (!is_dir('output')) mkdir('output');
$reports = processPuzzles(readBlocks('puzzles.txt')); processPictures(readBlocks('pictures.txt'), $reports);
