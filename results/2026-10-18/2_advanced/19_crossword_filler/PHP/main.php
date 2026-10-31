<?php
declare(strict_types=1);

namespace Crossword;

require_once __DIR__ . '/grid.php';
require_once __DIR__ . '/slots.php';
require_once __DIR__ . '/word_index.php';
require_once __DIR__ . '/filler.php';
require_once __DIR__ . '/render.php';

const SYMMETRIES = ['rot180', 'mirror', 'none'];
const CHECKED_SYMMETRIES = ['rot180', 'mirror'];
const LETTER_POINTS = [
    'A' => 1, 'B' => 3, 'C' => 3, 'D' => 2, 'E' => 1, 'F' => 4, 'G' => 2, 'H' => 4, 'I' => 1,
    'J' => 8, 'K' => 5, 'L' => 1, 'M' => 3, 'N' => 1, 'O' => 1, 'P' => 3, 'Q' => 10, 'R' => 1,
    'S' => 1, 'T' => 1, 'U' => 1, 'V' => 4, 'W' => 4, 'X' => 8, 'Y' => 4, 'Z' => 10,
];

function readLines(string $name): array { return file('input/' . $name, FILE_IGNORE_NEW_LINES); }
function isIgnored(string $line): bool { return $line === '' || $line[0] === '#'; }
function joined(array $items, string $separator): string { return $items === [] ? '-' : implode($separator, $items); }
function cellText(Grid $grid, int $cell): string { return implode(',', $grid->location($cell)); }

function readSettings(array $lines): array
{
    $settings = [];
    foreach ($lines as $line) {
        if (!isIgnored($line)) {
            [$key, $value] = explode(' ', $line);
            $settings[$key] = $key === 'symmetry' ? $value : (int)$value;
        }
    }
    return $settings;
}

final class WordList
{
    public int $lineCount;
    public array $scores = [];
    public array $firstLines = [];
    public array $invalid = [];
    public array $duplicates = [];
    public WordIndex $index;

    public function __construct(array $lines)
    {
        $this->lineCount = count($lines);
        foreach ($lines as $index => $line) {
            $number = $index + 1;
            $reason = wordLineError($line);
            if ($reason !== null) {
                $this->invalid[] = [$number, $reason];
                continue;
            }
            [$word, $score] = explode(' ', $line);
            if (isset($this->scores[$word])) {
                $this->duplicates[] = [$number, $word, $this->firstLines[$word]];
            } else {
                $this->scores[$word] = (int)$score;
                $this->firstLines[$word] = $number;
            }
        }
        $this->index = new WordIndex($this->scores);
    }

    public function reportLines(): array
    {
        $lines = ['WORDLIST lines=' . $this->lineCount . ' valid=' . count($this->scores)
            . ' invalid=' . count($this->invalid) . ' duplicates=' . count($this->duplicates)];
        foreach ($this->invalid as [$number, $reason]) {
            $lines[] = "invalid {$number} {$reason}";
        }
        foreach ($this->duplicates as [$number, $word, $first]) {
            $lines[] = "duplicate {$number} {$word} first={$first}";
        }
        $lengths = array_keys($this->index->byLength);
        sort($lengths, SORT_NUMERIC);
        foreach ($lengths as $length) {
            $words = $this->index->byLength[$length];
            $total = 0;
            foreach ($words as $word) {
                $total += $this->scores[$word];
            }
            $best = $words[0];
            $lines[] = "length {$length} words=" . count($words) . ' average=' . decimal($total, count($words), 2)
                . " best={$best}:{$this->scores[$best]}";
        }
        $bands = [];
        for ($low = 1; $low <= 81; $low += 20) {
            $high = $low + 19;
            $count = 0;
            foreach ($this->scores as $score) {
                $count += (int)($score >= $low && $score <= $high);
            }
            $bands[] = "{$low}-{$high}={$count}";
        }
        $lines[] = 'bands ' . implode(' ', $bands);
        $top = [];
        foreach (array_slice($this->index->ranked, 0, 5) as $word) {
            $top[] = $word . ':' . $this->scores[$word];
        }
        $lines[] = 'top ' . implode(' ', $top);
        $letters = [];
        foreach (str_split(UPPERCASE) as $letter) {
            $count = 0;
            foreach ($this->scores as $word => $_) {
                $count += (int)str_contains($word, $letter);
            }
            $letters[] = [$letter, $count];
        }
        usort($letters, static fn(array $a, array $b): int => ($a[1] <=> $b[1]) ?: strcmp($a[0], $b[0]));
        $rare = [];
        foreach (array_slice($letters, 0, 5) as [$letter, $count]) {
            $rare[] = $letter . ':' . $count;
        }
        $lines[] = 'rare_letters ' . implode(' ', $rare);
        return $lines;
    }
}

final class Clue
{
    public int $uses = 0;
    public function __construct(public string $word, public int $number, public string $text) {}
}

final class ClueBook
{
    public int $entries = 0;
    public int $added = 0;
    public array $invalid = [];
    public array $unknown = [];
    public array $clues = [];

    public function __construct(array $lines, array $scores)
    {
        foreach ($lines as $index => $line) {
            if (isIgnored($line)) {
                continue;
            }
            $number = $index + 1;
            $this->entries++;
            $reason = clueLineError($line);
            if ($reason !== null) {
                $this->invalid[] = [$number, $reason];
                continue;
            }
            [$word, $text] = explode('|', $line);
            if (!isset($scores[$word])) {
                $this->unknown[] = [$number, $word];
                continue;
            }
            $this->clues[$word] ??= [];
            $this->clues[$word][] = new Clue($word, count($this->clues[$word]) + 1, $text);
            $this->added++;
        }
    }

    public function choose(string $word): ?string
    {
        if (!isset($this->clues[$word])) {
            return null;
        }
        $chosen = $this->clues[$word][0];
        foreach ($this->clues[$word] as $clue) {
            if ($clue->uses < $chosen->uses) {
                $chosen = $clue;
            }
        }
        $chosen->uses++;
        return $chosen->text;
    }

    public function reportLines(): array
    {
        $lines = ["CLUES entries={$this->entries} valid={$this->added} invalid=" . count($this->invalid)
            . ' unknown=' . count($this->unknown) . ' words=' . count($this->clues)];
        foreach ($this->invalid as [$number, $reason]) {
            $lines[] = "clue_invalid {$number} {$reason}";
        }
        foreach ($this->unknown as [$number, $word]) {
            $lines[] = "clue_unknown {$number} {$word}";
        }
        $words = array_keys($this->clues);
        usort($words, 'strcmp');
        $used = 0;
        $repeated = [];
        foreach ($words as $word) {
            foreach ($this->clues[$word] as $clue) {
                $used += (int)($clue->uses >= 1);
                if ($clue->uses >= 2) {
                    $repeated[] = $clue;
                }
            }
        }
        $lines[] = "CLUE_USE used={$used} unused=" . ($this->added - $used) . ' repeated=' . count($repeated);
        foreach ($repeated as $clue) {
            $lines[] = "repeated {$clue->word} clue={$clue->number} uses={$clue->uses}";
        }
        return $lines;
    }
}

final class Block
{
    public array $options = [];
    public array $rows = [];
    public function __construct(public string $name) {}
}

function splitBlocks(array $lines): array
{
    $blocks = [];
    $block = null;
    foreach ($lines as $line) {
        if ($block === null) {
            if (str_starts_with($line, 'TEMPLATE ')) {
                $block = new Block(substr($line, 9));
            }
        } elseif ($line === 'END') {
            $blocks[] = $block;
            $block = null;
        } elseif (str_contains($line, ' ')) {
            $block->options[] = $line;
        } else {
            $block->rows[] = $line;
        }
    }
    return $blocks;
}

final class Template
{
    public string $name;
    public array $options;
    public array $rows;
    public int $nodeBudget;
    public int $minScore;
    public string $symmetry;
    public array $themes = [];
    public ?string $error = null;
    public Grid $grid;
    public Layout $layout;
    public GridState $initial;
    public array $themeSlots = [];
    public array $attempts = [];
    public Attempt $final;
    public GridState $state;
    public array $chosen = [];

    public function __construct(Block $block, array $settings)
    {
        $this->name = $block->name;
        $this->options = $block->options;
        $this->rows = $block->rows;
        $this->nodeBudget = $settings['node_budget'];
        $this->minScore = $settings['min_score'];
        $this->symmetry = $settings['symmetry'];
    }

    private function readOptions(): ?int
    {
        $seen = $themes = [];
        foreach ($this->options as $index => $line) {
            [$key, $value] = explode(' ', $line, 2);
            if ($key === 'theme') {
                if (!isValidWord($value) || isset($themes[$value])) {
                    return $index + 1;
                }
                $themes[$value] = true;
                $this->themes[] = $value;
            } else {
                if (isset($seen['#' . $key])) {
                    return $index + 1;
                }
                if ($key === 'node_budget' && isValidInteger($value, 1, 100000)) {
                    $this->nodeBudget = (int)$value;
                } elseif ($key === 'min_score' && isValidInteger($value, 1, 100)) {
                    $this->minScore = (int)$value;
                } elseif ($key === 'symmetry' && in_array($value, SYMMETRIES, true)) {
                    $this->symmetry = $value;
                } else {
                    return $index + 1;
                }
            }
            $seen['#' . $key] = true;
        }
        return null;
    }

    private function check(array $earlierNames, WordIndex $index): ?string
    {
        if (preg_match('/\A[a-z0-9_]{1,20}\z/', $this->name) !== 1) {
            return 'bad name';
        }
        if (isset($earlierNames['#' . $this->name])) {
            return 'duplicate name';
        }
        $badOption = $this->readOptions();
        if ($badOption !== null) {
            return 'bad option ' . $badOption;
        }
        if (count($this->rows) < 3 || count($this->rows) > 15) {
            return 'bad height';
        }
        foreach ($this->rows as $number => $row) {
            if (strlen($row) !== strlen($this->rows[0]) || preg_match('/\A[.#A-Z]{3,15}\z/', $row) !== 1) {
                return 'bad row ' . ($number + 1);
            }
        }
        $this->grid = new Grid($this->rows);
        if ($this->symmetry !== 'none') {
            $cell = $this->grid->asymmetricCell($this->symmetry);
            if ($cell !== null) {
                return 'asymmetric at ' . cellText($this->grid, $cell);
            }
        }
        $components = $this->grid->componentCount();
        if ($components !== 1) {
            return 'disconnected components=' . $components;
        }
        $shortRun = findShortRun($this->grid);
        if ($shortRun !== null) {
            return 'short slot at ' . cellText($this->grid, $shortRun[0]) . ' ' . $shortRun[1];
        }
        $this->layout = new Layout($this->grid);
        $orphan = $this->layout->orphanCell();
        if ($orphan !== null) {
            return 'orphan cell ' . cellText($this->grid, $orphan);
        }
        $state = new GridState(str_split($this->grid->cells), array_fill(0, count($this->layout->slots), null));
        foreach ($this->themes as $number => $theme) {
            if (!isset($index->scores[$theme])) {
                return 'unknown theme ' . ($number + 1);
            }
            $chosen = null;
            foreach ($this->layout->slots as $slot) {
                if ($state->words[$slot->index] === null && $slot->length === strlen($theme) && wordMatches($theme, $state->pattern($slot))) {
                    $chosen = $slot;
                    break;
                }
            }
            if ($chosen === null) {
                return 'theme ' . ($number + 1) . ' does not fit';
            }
            $state->assign($chosen, $theme);
            $this->themeSlots[$chosen->index] = true;
        }
        $this->initial = $state;
        return null;
    }

    public function process(array $earlierNames, WordIndex $index, ClueBook $clueBook, int $relaxStep): void
    {
        $this->error = $this->check($earlierNames, $index);
        if ($this->error !== null) {
            return;
        }
        $minimum = $this->minScore;
        while (true) {
            $attempt = new Attempt($this->layout, $index, $this->initial, $minimum, $this->nodeBudget);
            $attempt->run();
            $this->attempts[] = $attempt;
            $this->final = $attempt;
            if ($attempt->outcome === 'filled' || $relaxStep < 1 || $minimum <= 1) {
                break;
            }
            $minimum = max($minimum - $relaxStep, 1);
        }
        $this->state = $this->final->finalState();
        $this->chosen = array_fill(0, count($this->layout->slots), null);
        foreach ([true, false] as $across) {
            foreach ($this->layout->slots as $slot) {
                $word = $this->state->words[$slot->index];
                if ($slot->across === $across && $word !== null) {
                    $this->chosen[$slot->index] = $clueBook->choose($word);
                }
            }
        }
    }

    public function isFilled(): bool { return $this->error === null && $this->final->outcome === 'filled'; }
    public function slotCount(): int { return count($this->layout->slots); }

    public function totalScore(array $scores): int
    {
        $total = 0;
        foreach ($this->state->words as $word) {
            $total += $scores[$word];
        }
        return $total;
    }

    private function entry(Slot $slot, array $scores): string
    {
        $word = $this->state->words[$slot->index];
        return $slot->label . ':' . $word . ':' . $scores[$word];
    }

    public function gridParagraph(): array
    {
        $lines = ['TEMPLATE ' . $this->name];
        if ($this->error !== null) {
            $lines[] = 'error ' . $this->error;
            return $lines;
        }
        $lines[] = 'outcome=' . $this->final->outcome . ' attempts=' . count($this->attempts) . ' min_score=' . $this->final->minScore;
        array_push($lines, ...gridLines($this->grid, $this->state->letters));
        $lines[] = 'numbers';
        array_push($lines, ...numberLines($this->layout));
        return $lines;
    }

    public function clueParagraph(array $scores): array
    {
        $lines = ['TEMPLATE ' . $this->name];
        $clued = $missing = $unfilled = 0;
        foreach ([true, false] as $across) {
            $started = false;
            foreach ($this->layout->slots as $slot) {
                if ($slot->across !== $across) {
                    continue;
                }
                if (!$started) {
                    $lines[] = $across ? 'ACROSS' : 'DOWN';
                    $started = true;
                }
                $word = $this->state->words[$slot->index];
                if ($word === null) {
                    $unfilled++;
                    $lines[] = listLine($slot, '(unfilled)', $this->state->pattern($slot), '-', false);
                    continue;
                }
                $clue = $this->chosen[$slot->index];
                if ($clue === null) {
                    $missing++;
                    $clue = '(no clue)';
                } else {
                    $clued++;
                }
                $lines[] = listLine($slot, $clue, $word, $scores[$word], isset($this->themeSlots[$slot->index]));
            }
        }
        $lines[] = "clued={$clued} missing={$missing} unfilled={$unfilled}";
        return $lines;
    }

    private function gridSummary(): string
    {
        $whites = $this->grid->whiteCells();
        $blacks = $this->grid->size() - count($whites);
        $givens = 0;
        foreach ($whites as $cell) {
            $givens += (int)$this->grid->isGiven($cell);
        }
        $holding = [];
        foreach (CHECKED_SYMMETRIES as $name) {
            if ($this->grid->asymmetricCell($name) === null) {
                $holding[] = $name;
            }
        }
        if ($holding === []) {
            $holding[] = 'none';
        }
        return "grid size={$this->grid->width}x{$this->grid->height} blocks={$blacks} white=" . count($whites)
            . ' density=' . decimal(100 * $blacks, $this->grid->size(), 1) . " givens={$givens} required={$this->symmetry} symmetry=" . implode(',', $holding);
    }

    private function lengthCounts(): array
    {
        $counts = [];
        foreach ($this->layout->slots as $slot) {
            $counts[$slot->length] = ($counts[$slot->length] ?? 0) + 1;
        }
        ksort($counts, SORT_NUMERIC);
        return $counts;
    }

    private function slotSummary(): string
    {
        $counts = [];
        foreach ($this->lengthCounts() as $length => $count) {
            $counts[] = $length . ':' . $count;
        }
        $total = $across = $longest = $unchecked = 0;
        foreach ($this->layout->slots as $slot) {
            $total += $slot->length;
            $longest = max($longest, $slot->length);
            $across += (int)$slot->across;
        }
        foreach ($this->grid->whiteCells() as $cell) {
            $unchecked += (int)($this->layout->ownerCount($cell) === 1);
        }
        $count = $this->slotCount();
        return "slots across={$across} down=" . ($count - $across) . " total={$count} lengths=" . implode(',', $counts)
            . ' avg_length=' . decimal($total, $count, 2) . " longest={$longest} unchecked={$unchecked}";
    }

    private function coverageLine(WordIndex $index): string
    {
        $parts = [];
        foreach ($this->lengthCounts() as $length => $_) {
            $supply = 0;
            foreach ($index->byLength[$length] ?? [] as $word) {
                $supply += (int)($index->scores[$word] >= $this->minScore);
            }
            $parts[] = $length . ':' . $supply;
        }
        return 'coverage ' . implode(' ', $parts);
    }

    private function tightestLine(WordIndex $index): string
    {
        $counts = [];
        foreach ($this->layout->slots as $slot) {
            if (!isset($this->themeSlots[$slot->index])) {
                $words = $index->candidates($this->initial->pattern($slot), $this->minScore, $this->initial->used);
                $counts[] = [count($words), $slot->index];
            }
        }
        usort($counts, static fn(array $a, array $b): int => ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1]));
        $parts = [];
        foreach (array_slice($counts, 0, 3) as [$count, $slot]) {
            $parts[] = $this->layout->slots[$slot]->label . ':' . $count;
        }
        return 'tightest ' . joined($parts, ' ');
    }

    private function hotspotsLine(): string
    {
        $failed = [];
        foreach ($this->layout->slots as $slot) {
            if ($this->final->failures[$slot->index] >= 1) {
                $failed[] = $slot;
            }
        }
        usort($failed, fn(Slot $a, Slot $b): int => ($this->final->failures[$b->index] <=> $this->final->failures[$a->index]) ?: ($a->index <=> $b->index));
        $parts = [];
        foreach (array_slice($failed, 0, 3) as $slot) {
            $parts[] = $slot->label . ':' . $this->final->failures[$slot->index];
        }
        return 'hotspots ' . joined($parts, ' ');
    }

    private function worstCrossing(array $scores): string
    {
        $worst = null;
        $worstSum = 0;
        foreach ($this->grid->whiteCells() as $cell) {
            $across = $this->layout->acrossSlot[$cell];
            $down = $this->layout->downSlot[$cell];
            if ($across === null || $down === null) {
                continue;
            }
            $total = $scores[$this->state->words[$across]] + $scores[$this->state->words[$down]];
            if ($worst === null || $total < $worstSum) {
                $worst = $cell;
                $worstSum = $total;
            }
        }
        if ($worst === null) {
            return '-';
        }
        $across = $this->layout->slots[$this->layout->acrossSlot[$worst]];
        $down = $this->layout->slots[$this->layout->downSlot[$worst]];
        return cellText($this->grid, $worst) . ' ' . $across->label . ':' . $this->state->words[$across->index]
            . '+' . $down->label . ':' . $this->state->words[$down->index] . '=' . $worstSum;
    }

    private function qualityLines(array $scores, int $weakScore): array
    {
        $weakest = $this->layout->slots[0];
        $weak = [];
        foreach ($this->layout->slots as $slot) {
            if ($scores[$this->state->words[$slot->index]] < $scores[$this->state->words[$weakest->index]]) {
                $weakest = $slot;
            }
            if ($scores[$this->state->words[$slot->index]] < $weakScore) {
                $weak[] = $this->entry($slot, $scores);
            }
        }
        $whites = $this->grid->whiteCells();
        $distinct = [];
        $points = 0;
        foreach ($whites as $cell) {
            $letter = $this->state->letters[$cell];
            $distinct[$letter] = true;
            $points += LETTER_POINTS[$letter];
        }
        $missing = '';
        foreach (str_split(UPPERCASE) as $letter) {
            if (!isset($distinct[$letter])) {
                $missing .= $letter;
            }
        }
        $total = $this->totalScore($scores);
        $pangram = $missing === '' ? 'yes' : 'no';
        return [
            "quality total={$total} average=" . decimal($total, $this->slotCount(), 2)
                . ' weakest=' . $this->entry($weakest, $scores) . ' weak=' . joined($weak, ','),
            'letters distinct=' . count($distinct) . " pangram={$pangram} missing=" . ($missing === '' ? '-' : $missing)
                . ' scrabble=' . decimal($points, count($whites), 2) . ' worst_crossing=' . $this->worstCrossing($scores),
        ];
    }

    private function partialLine(WordIndex $index): string
    {
        $assigned = $lettered = 0;
        foreach ($this->state->words as $word) {
            $assigned += (int)($word !== null);
        }
        $whites = $this->grid->whiteCells();
        foreach ($whites as $cell) {
            $lettered += (int)($this->state->letters[$cell] !== '.');
        }
        $blocked = [];
        foreach ($this->layout->slots as $slot) {
            if ($this->state->words[$slot->index] === null
                && $index->candidates($this->state->pattern($slot), $this->final->minScore, $this->state->used) === []) {
                $blocked[] = $slot->label;
            }
        }
        return "partial assigned={$assigned}/" . $this->slotCount() . " letters={$lettered}/" . count($whites) . ' blocked=' . joined($blocked, ',');
    }

    public function statsParagraph(WordIndex $index, int $weakScore): array
    {
        $lines = ['TEMPLATE ' . $this->name, $this->gridSummary(), $this->slotSummary()];
        $themes = [];
        foreach ($this->layout->slots as $slot) {
            if (isset($this->themeSlots[$slot->index])) {
                $themes[] = $this->entry($slot, $index->scores);
            }
        }
        if ($themes !== []) {
            $lines[] = 'themes ' . implode(' ', $themes);
        }
        $lines[] = $this->coverageLine($index);
        $lines[] = $this->tightestLine($index);
        foreach ($this->attempts as $number => $attempt) {
            $lines[] = 'attempt ' . ($number + 1) . " min_score={$attempt->minScore} budget={$attempt->budget} outcome={$attempt->outcome}"
                . " nodes={$attempt->nodes} backtracks={$attempt->backtracks} prunes={$attempt->prunes} dead_ends={$attempt->deadEnds} max_depth={$attempt->maxDepth}";
        }
        $lines[] = 'trace ' . joined($this->final->trace, ' ');
        $lines[] = $this->hotspotsLine();
        if ($this->isFilled()) {
            $order = array_map(static fn(Slot $slot): string => $slot->label, $this->final->sequence);
            $lines[] = 'order ' . joined($order, ' ');
            array_push($lines, ...$this->qualityLines($index->scores, $weakScore));
        } else {
            $lines[] = $this->partialLine($index);
        }
        return $lines;
    }
}

function rankingParagraph(array $filled, array $scores): array
{
    usort($filled, static function (Template $a, Template $b) use ($scores): int {
        $left = $a->totalScore($scores) * $b->slotCount();
        $right = $b->totalScore($scores) * $a->slotCount();
        return ($right <=> $left) ?: strcmp($a->name, $b->name);
    });
    $lines = ['RANKING'];
    foreach ($filled as $position => $template) {
        $total = $template->totalScore($scores);
        $entries = $template->slotCount();
        $lines[] = 'rank ' . ($position + 1) . ' ' . $template->name . ' average=' . decimal($total, $entries, 2) . " total={$total} entries={$entries}";
    }
    return $lines;
}

function reuseParagraph(array $filled): array
{
    $appearances = [];
    foreach ($filled as $template) {
        foreach ($template->state->words as $word) {
            $appearances[$word][] = $template->name;
        }
    }
    $reused = [];
    foreach ($appearances as $word => $names) {
        if (count($names) >= 2) {
            $reused[] = $word;
        }
    }
    usort($reused, static fn(string $a, string $b): int => (count($appearances[$b]) <=> count($appearances[$a])) ?: strcmp($a, $b));
    $lines = ['REUSE'];
    foreach ($reused as $word) {
        $lines[] = 'reused ' . $word . ' ' . count($appearances[$word]) . ' ' . implode(',', $appearances[$word]);
    }
    return $lines;
}

function summaryParagraph(array $templates): array
{
    $invalid = $attempts = $nodes = 0;
    $counts = ['filled' => 0, 'unfillable' => 0, 'budget' => 0];
    foreach ($templates as $template) {
        if ($template->error !== null) {
            $invalid++;
        } else {
            $counts[$template->final->outcome]++;
            $attempts += count($template->attempts);
            foreach ($template->attempts as $attempt) {
                $nodes += $attempt->nodes;
            }
        }
    }
    return ['SUMMARY templates=' . count($templates) . " invalid={$invalid} filled={$counts['filled']} unfillable={$counts['unfillable']}"
        . " budget={$counts['budget']} attempts={$attempts} nodes={$nodes}"];
}

function writeLines(string $name, array $lines): void
{
    file_put_contents('output/' . $name, $lines === [] ? '' : implode("\n", $lines) . "\n");
}

function writeParagraphs(string $name, array $paragraphs): void
{
    $lines = [];
    foreach ($paragraphs as $paragraph) {
        if ($lines !== []) {
            $lines[] = '';
        }
        array_push($lines, ...$paragraph);
    }
    writeLines($name, $lines);
}

function main(): void
{
    $settings = readSettings(readLines('params.txt'));
    $wordList = new WordList(readLines('words.txt'));
    $index = $wordList->index;
    $clueBook = new ClueBook(readLines('clues.txt'), $wordList->scores);
    $templates = $valid = $filled = $names = [];
    foreach (splitBlocks(readLines('templates.txt')) as $block) {
        $template = new Template($block, $settings);
        $template->process($names, $index, $clueBook, $settings['relax_step']);
        $names['#' . $block->name] = true;
        $templates[] = $template;
        if ($template->error === null) {
            $valid[] = $template;
            if ($template->isFilled()) {
                $filled[] = $template;
            }
        }
    }
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    $grids = $clues = $stats = [];
    foreach ($templates as $template) {
        $grids[] = $template->gridParagraph();
    }
    foreach ($valid as $template) {
        $clues[] = $template->clueParagraph($index->scores);
        $stats[] = $template->statsParagraph($index, $settings['weak_score']);
    }
    $stats[] = rankingParagraph($filled, $index->scores);
    $stats[] = reuseParagraph($filled);
    $stats[] = summaryParagraph($templates);
    writeParagraphs('grid.txt', $grids);
    writeParagraphs('clues.txt', $clues);
    writeParagraphs('search_stats.txt', $stats);
    writeLines('wordlist.txt', array_merge($wordList->reportLines(), $clueBook->reportLines()));
}

main();
