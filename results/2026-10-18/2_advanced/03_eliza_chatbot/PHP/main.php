<?php
require __DIR__ . '/script_loader.php';
require __DIR__ . '/matcher.php';
require __DIR__ . '/linter.php';
require __DIR__ . '/responder.php';
require __DIR__ . '/memory.php';

const SOURCES = ['keyword', 'memory', 'question', 'default', 'repeat'];
const NO_ARGUMENT = [':keys', ':why', ':history', ':memory', ':forget', ':reset', ':unused', ':stats', ':undo'];
const TEXT_ARGUMENT = [':prepare', ':reflect', ':say', ':explain'];
const ONE_ARGUMENT = [':groups', ':find', ':script', ':cycles', ':coverage'];

function normalize(string $text): array {
    $clauses = [];
    foreach (preg_split('/[,.?!;]/', strtolower($text)) as $part) {
        preg_match_all("/[a-z0-9']+/", $part, $matches);
        $words = array_values(array_filter(array_map(fn($word) => trim($word, "'"), $matches[0]), fn($word) => $word !== ''));
        if ($words) $clauses[] = $words;
    }
    return $clauses;
}

function count_line(array $session): string {
    $parts = ['turns=' . $session['turns']];
    foreach (SOURCES as $source) $parts[] = "$source=" . $session['sources'][$source];
    return implode(' ', $parts);
}

function leaders(array $counts): string {
    uksort($counts, fn($a, $b) => ($counts[$b] <=> $counts[$a]) ?: strcmp((string)$a, (string)$b));
    $parts = [];
    foreach (array_slice($counts, 0, 5, true) as $word => $count) if ($count > 0) $parts[] = "$word $count";
    return $parts ? implode(', ', $parts) : 'none';
}

function grouped_lines(array $values, int $size): array {
    return array_map(fn($chunk) => implode(' ', $chunk), array_chunk($values, $size));
}

function rule_entries(array $keyword): array {
    $entries = [];
    foreach (['memories' => 'memory', 'decomps' => 'decomp'] as $field => $label) foreach ($keyword[$field] as $index => $id) $entries[] = [$label, $index + 1, $id];
    return $entries;
}

class Chatbot {
    public array $state;
    public array $transcript = [];
    private int $sessions = 0;
    private array $totals;

    public function __construct(private array $script) {
        $this->state = ['positions' => array_fill(0, count($script['rules']), 0), 'hits' => array_fill(0, count($script['rules']), 0),
            'item_uses' => array_fill(0, count($script['items']), 0), 'keyword_uses' => array_fill(0, count($script['keywords']), 0),
            'keyword_replies' => array_fill(0, count($script['keywords']), 0), 'cycles' => array_fill_keys(['DEFAULT', 'QUESTION', 'REPEAT'], 0),
            'memory' => ['texts' => [], 'log' => []], 'session' => []];
        $this->totals = ['turns' => 0, 'sources' => array_fill_keys(SOURCES, 0)];
    }

    private function prefix(): string { return $this->state['session']['name'] . ' ' . $this->state['session']['turns']; }
    private function resetCycles(): void {
        $this->state['positions'] = array_fill(0, count($this->script['rules']), 0);
        $this->state['cycles'] = array_fill_keys(['DEFAULT', 'QUESTION', 'REPEAT'], 0);
    }
    private function takeText(string $name): string {
        $position = $this->state['cycles'][$name];
        $this->state['cycles'][$name] = ($position + 1) % count($this->script['texts'][$name]);
        return $this->script['texts'][$name][$position];
    }
    private function takeItem(int $rule): array {
        $position = $this->state['positions'][$rule];
        $item = $this->script['rules'][$rule]['items'][$position];
        $this->state['positions'][$rule] = ($position + 1) % count($this->script['rules'][$rule]['items']);
        $this->state['item_uses'][$item]++;
        return [$position + 1, $item];
    }
    private function prepared(array $clauses): array {
        $result = [];
        foreach ($clauses as $clause) {
            $words = [];
            foreach ($clause as $word) array_push($words, ...($this->script['pre'][$word] ?? [$word]));
            $result[] = $words;
        }
        return $result;
    }
    private function isQuit(array $clauses): bool {
        $words = array_merge([], ...$clauses);
        return count($words) === 1 && isset($this->script['quit'][$words[0]]);
    }
    private function selectClause(array $clauses): ?array {
        foreach ($clauses as $index => $words) {
            $ids = [];
            foreach ($words as $word) if (isset($this->script['keyword_map'][$word])) {
                $id = $this->script['keyword_map'][$word];
                if (!in_array($id, $ids, true)) $ids[] = $id;
            }
            if (!$ids) continue;
            usort($ids, fn($a, $b) => $this->script['keywords'][$b]['rank'] <=> $this->script['keywords'][$a]['rank']);
            return [$index + 1, $words, $ids];
        }
        return null;
    }
    private function findRule(array $rules, array $words): ?array {
        foreach ($rules as $index => $id) {
            $bindings = match_pattern($this->script['rules'][$id]['pattern'], $words, $this->script['group_words']);
            if ($bindings !== null) return [$index + 1, $id, $bindings];
        }
        return null;
    }
    private function applyMemory(int $keyword, array $words, array &$trace): void {
        $found = $this->findRule($this->script['keywords'][$keyword]['memories'], $words);
        if ($found === null) return;
        [$number, $rule, $bindings] = $found;
        $word = $this->script['keywords'][$keyword]['word'];
        $trace[] = "MEMORY $word $number";
        $this->state['hits'][$rule]++;
        if (!$this->script['rules'][$rule]['items']) return;
        [, $item] = $this->takeItem($rule);
        $text = build_reply($this->script['items'][$item]['text'], $bindings, $this->script['post']);
        $memory = $this->state['memory'];
        if (memory_store($memory, $this->script['capacity'], $this->prefix(), $word, $text)) $this->state['session']['stored']++;
        $this->state['memory'] = $memory;
    }
    private function keywordReply(array $clauses, array &$trace): ?string {
        $selected = $this->selectClause($clauses);
        if ($selected === null) { $trace[] = 'CLAUSE none'; return null; }
        [$number, $words, $keywords] = $selected;
        $trace[] = "CLAUSE $number " . implode(' ', $words);
        $trace[] = 'KEYS ' . implode(' ', array_map(fn($id) => $this->script['keywords'][$id]['word'], $keywords));
        $this->applyMemory($keywords[0], $words, $trace);
        $entered = [];
        foreach ($keywords as $initial) {
            if (isset($entered[$initial])) continue;
            $trace[] = 'ENTER ' . $this->script['keywords'][$initial]['word'];
            $keyword = $initial;
            $current = $words;
            while (true) {
                $entered[$keyword] = true;
                $this->state['keyword_uses'][$keyword]++;
                $word = $this->script['keywords'][$keyword]['word'];
                $found = $this->findRule($this->script['keywords'][$keyword]['decomps'], $current);
                if ($found === null) { $trace[] = "NOMATCH $word"; break; }
                [$number, $rule, $bindings] = $found;
                $this->state['hits'][$rule]++;
                if (!$this->script['rules'][$rule]['items']) { $trace[] = "DECOMP $word $number 0"; break; }
                [$itemNumber, $itemId] = $this->takeItem($rule);
                $item = $this->script['items'][$itemId];
                $trace[] = "DECOMP $word $number $itemNumber";
                if ($item['kind'] === 'REASM') {
                    $this->state['keyword_replies'][$keyword]++;
                    $this->state['session']['topics'][$word] = ($this->state['session']['topics'][$word] ?? 0) + 1;
                    return build_reply($item['text'], $bindings, $this->script['post']);
                }
                if ($item['kind'] === 'NEWKEY') break;
                $target = $item['arguments'][0];
                $next = $this->script['keyword_map'][$target] ?? null;
                if ($next === null || isset($entered[$next])) { $trace[] = "BLOCKED $target"; break; }
                if ($item['kind'] === 'RESTATE') {
                    $current = restated_words(array_slice($item['arguments'], 1), $bindings);
                    $trace[] = "RESTATE $target" . ($current ? ' ' . implode(' ', $current) : '');
                } else $trace[] = "GOTO $target";
                $keyword = $next;
            }
        }
        return null;
    }
    private function decide(string $text): array {
        $clauses = normalize($text);
        $trace = [];
        if ($this->script['texts']['REPEAT'] && $clauses && $clauses === $this->state['session']['previous']) {
            $trace[] = 'REPEAT';
            $reply = $this->takeText('REPEAT');
            $source = 'repeat';
        } else {
            $reply = $this->keywordReply($this->prepared($clauses), $trace);
            if ($reply !== null) $source = 'keyword';
            elseif ($this->state['memory']['texts']) {
                $memory = $this->state['memory'];
                $reply = memory_recall($memory, $this->prefix());
                $this->state['memory'] = $memory;
                $this->state['session']['recalled']++;
                $source = 'memory';
            } elseif (str_ends_with($text, '?') && $this->script['texts']['QUESTION']) { $reply = $this->takeText('QUESTION'); $source = 'question'; }
            else { $reply = $this->takeText('DEFAULT'); $source = 'default'; }
        }
        $trace[] = "REPLY $source";
        $this->state['session']['previous'] = $clauses;
        $this->state['session']['sources'][$source]++;
        if ($source === 'question' || $source === 'default') $this->state['session']['unrecognized'][] = $this->state['session']['turns'];
        return [$reply, $trace];
    }
    private function respond(string $text): void {
        $snapshot = $this->state;
        $snapshot['session']['undo'] = null;
        $this->state['session']['undo'] = $snapshot;
        $this->state['session']['turns']++;
        foreach (normalize($text) as $clause) foreach ($clause as $word) if (!isset($this->script['stop'][$word])) $this->state['session']['words'][$word] = ($this->state['session']['words'][$word] ?? 0) + 1;
        $this->state['session']['history'][] = $this->state['session']['turns'] . ": $text";
        [$reply, $trace] = $this->decide($text);
        array_push($this->transcript, ...eliza_lines($reply));
        $this->state['session']['last_trace'] = $trace;
        if ($this->state['session']['trace_on']) foreach ($trace as $line) $this->transcript[] = "  $line";
    }
    private function prepare(string $text): array {
        $clauses = $this->prepared(normalize($text));
        $lines = [];
        foreach ($clauses as $index => $clause) $lines[] = 'clause ' . ($index + 1) . ': ' . implode(' ', $clause);
        if (!$clauses) $lines[] = 'no words';
        $selected = $this->selectClause($clauses);
        if ($selected === null) $lines[] = 'selected none';
        else {
            $lines[] = 'selected ' . $selected[0];
            $lines[] = 'keys ' . implode(' ', array_map(fn($id) => $this->script['keywords'][$id]['word'] . '/' . $this->script['keywords'][$id]['rank'], $selected[2]));
        }
        return $lines;
    }
    private function findWord(string $word): array {
        $lines = [];
        if (isset($this->script['keyword_map'][$word])) $lines[] = 'keyword rank ' . $this->script['keywords'][$this->script['keyword_map'][$word]]['rank'];
        foreach (['pre' => 'pres', 'post' => 'posts'] as $label => $field) foreach ($this->script[$field] as $entry) if ($entry['source'] === $word || in_array($word, $entry['replacement'], true)) $lines[] = "$label " . $entry['line'] . ': ' . $entry['source'] . ' -> ' . implode(' ', $entry['replacement']);
        foreach ($this->script['groups'] as $group) if (isset($group['members'][$word])) $lines[] = 'group ' . $group['name'] . ' line ' . $group['line'];
        foreach ($this->script['keywords'] as $keyword) foreach (rule_entries($keyword) as [$label, $number, $id]) if (in_array($word, $this->script['rules'][$id]['pattern'], true)) $lines[] = 'pattern ' . $keyword['word'] . " $label $number";
        if (isset($this->script['stop'][$word])) $lines[] = 'stop word';
        if (isset($this->script['quit'][$word])) $lines[] = 'quit word';
        return $lines ?: ['not found'];
    }
    private function command(string $line): array {
        $parts = explode(' ', $line, 2);
        $name = $parts[0]; $text = $parts[1] ?? ''; $args = $text === '' ? [] : explode(' ', $text);
        if (!in_array($name, [...NO_ARGUMENT, ...TEXT_ARGUMENT, ...ONE_ARGUMENT, ':trace', ':test'], true)) return ["unknown command $name"];
        if ((in_array($name, NO_ARGUMENT, true) && $args) || (in_array($name, TEXT_ARGUMENT, true) && $text === '')
            || (in_array($name, ONE_ARGUMENT, true) && count($args) !== 1) || ($name === ':trace' && (count($args) !== 1 || !in_array($args[0], ['on', 'off'], true)))
            || ($name === ':test' && count($args) < 2)) return ['bad arguments'];
        $keyword = $this->script['keyword_map'][$args[0] ?? ''] ?? null;
        if (in_array($name, [':script', ':cycles', ':coverage', ':test'], true) && $keyword === null) return ["unknown keyword $args[0]"];
        if ($name === ':prepare') return $this->prepare($text);
        if ($name === ':reflect') {
            $clauses = $this->prepared(normalize($text));
            return $clauses ? array_map(fn($clause) => implode(' ', reflect_words($clause, $this->script['post'])), $clauses) : ['no words'];
        }
        if ($name === ':test') {
            $words = array_merge([], ...$this->prepared(normalize(explode(' ', $text, 2)[1])));
            $lines = [];
            foreach (rule_entries($this->script['keywords'][$keyword]) as [$label, $number, $id]) {
                $bindings = match_pattern($this->script['rules'][$id]['pattern'], $words, $this->script['group_words']);
                $result = $bindings === null ? 'no match' : ($bindings ? implode(' ', array_map(fn($binding) => '[' . implode(' ', $binding) . ']', $bindings)) : 'match');
                $lines[] = "$label $number: $result";
            }
            return $lines ?: ['no rules'];
        }
        if ($name === ':keys') {
            $keys = $this->script['keywords'];
            usort($keys, fn($a, $b) => ($b['rank'] <=> $a['rank']) ?: strcmp($a['word'], $b['word']));
            return grouped_lines(array_map(fn($key) => $key['word'] . '/' . $key['rank'], $keys), 8);
        }
        if ($name === ':groups') {
            $groups = [];
            foreach ($this->script['groups'] as $group) if (isset($group['members'][$text])) $groups[] = $group['name'];
            usort($groups, 'strcmp');
            return [$groups ? implode(' ', $groups) : 'none'];
        }
        if ($name === ':find') return $this->findWord($text);
        if ($name === ':script') {
            $numbers = [$this->script['keywords'][$keyword]['line']];
            foreach (rule_entries($this->script['keywords'][$keyword]) as [, , $id]) {
                $numbers[] = $this->script['rules'][$id]['line'];
                foreach ($this->script['rules'][$id]['items'] as $item) $numbers[] = $this->script['items'][$item]['line'];
            }
            sort($numbers, SORT_NUMERIC);
            return array_map(fn($number) => "$number " . $this->script['lines'][$number - 1], $numbers);
        }
        if ($name === ':why') return $this->state['session']['last_trace'] ?? ['no reply yet'];
        if ($name === ':trace') { $this->state['session']['trace_on'] = $text === 'on'; return ["trace $text"]; }
        if ($name === ':history') return $this->state['session']['history'] ? array_slice($this->state['session']['history'], -5) : ['no turns yet'];
        if ($name === ':memory') {
            $lines = ['memory ' . count($this->state['memory']['texts']) . '/' . $this->script['capacity']];
            foreach ($this->state['memory']['texts'] as $index => $text) $lines[] = ($index + 1) . ": $text";
            return $lines;
        }
        if ($name === ':forget') {
            $memory = $this->state['memory']; $count = memory_clear($memory, $this->prefix()); $this->state['memory'] = $memory;
            return ["forgot $count"];
        }
        if ($name === ':cycles' || $name === ':coverage') {
            $lines = [];
            foreach (rule_entries($this->script['keywords'][$keyword]) as [$label, $number, $id]) {
                $items = $this->script['rules'][$id]['items'];
                if ($name === ':cycles') $detail = $items ? 'next ' . ($this->state['positions'][$id] + 1) . '/' . count($items) : 'empty';
                else $detail = 'hits ' . $this->state['hits'][$id] . ' entries ' . ($items ? implode(' ', array_map(fn($item) => $this->state['item_uses'][$item], $items)) : '-');
                $lines[] = "$label $number: $detail";
            }
            return $lines ?: ['no rules'];
        }
        if ($name === ':reset') { $this->resetCycles(); return ['cycles reset']; }
        if ($name === ':unused') {
            $numbers = [];
            foreach ($this->script['items'] as $id => $item) if ($this->state['item_uses'][$id] === 0) $numbers[] = $item['line'];
            sort($numbers, SORT_NUMERIC);
            return ['unused ' . count($numbers), ...grouped_lines($numbers, 12)];
        }
        if ($name === ':stats') return [count_line($this->state['session'])];
        if ($name === ':say' || $name === ':explain') {
            if ($this->isQuit(normalize($text))) return ['would quit'];
            $saved = $this->state;
            [$reply, $trace] = $this->decide($text);
            $this->state = $saved;
            return $name === ':say' ? [$reply] : $trace;
        }
        $snapshot = $this->state['session']['undo'];
        if ($snapshot === null) return ['nothing to undo'];
        $this->state = $snapshot;
        return ['undone turn ' . ($this->state['session']['turns'] + 1)];
    }
    private function notes(): void {
        $session = $this->state['session'];
        array_push($this->transcript, 'NOTES ' . $session['name'], '  ' . count_line($session), '  topics: ' . leaders($session['topics']),
            '  words: ' . leaders($session['words']), '  memory: stored=' . $session['stored'] . ' recalled=' . $session['recalled'] . ' pending=' . count($this->state['memory']['texts']),
            '  unrecognized: ' . ($session['unrecognized'] ? implode(' ', $session['unrecognized']) : 'none'));
        $this->totals['turns'] += $session['turns'];
        foreach (SOURCES as $source) $this->totals['sources'][$source] += $session['sources'][$source];
    }
    public function run(array $lines): void {
        foreach ($lines as $line) {
            if (str_starts_with($line, 'SESSION ')) {
                $name = substr($line, 8);
                if ($this->sessions > 0) {
                    $this->transcript[] = '';
                    if (!isset($this->script['persist']['cycles'])) $this->resetCycles();
                    if (!isset($this->script['persist']['memory'])) {
                        $memory = $this->state['memory']; memory_clear($memory, "$name 0"); $this->state['memory'] = $memory;
                    }
                }
                $this->sessions++;
                $this->state['session'] = ['name' => $name, 'turns' => 0, 'sources' => array_fill_keys(SOURCES, 0), 'previous' => null,
                    'history' => [], 'last_trace' => null, 'trace_on' => false, 'topics' => [], 'words' => [], 'stored' => 0, 'recalled' => 0, 'unrecognized' => [], 'undo' => null];
                $this->transcript[] = $line;
                $texts = $this->script['texts']['INITIAL'];
                array_push($this->transcript, ...eliza_lines($texts[($this->sessions - 1) % count($texts)]));
            } elseif ($line[0] === ':') {
                $this->transcript[] = $line;
                foreach ($this->command($line) as $text) $this->transcript[] = "  $text";
            } else {
                $this->transcript[] = "YOU: $line";
                if ($this->isQuit(normalize($line))) {
                    $texts = $this->script['texts']['FINAL'];
                    array_push($this->transcript, ...eliza_lines($texts[($this->sessions - 1) % count($texts)]));
                    $this->notes();
                } else $this->respond($line);
            }
        }
        $this->transcript[] = '';
        $this->transcript[] = "SUMMARY sessions=$this->sessions " . count_line($this->totals);
    }
    public function keywordStats(): array {
        $ids = array_keys($this->script['keywords']);
        usort($ids, fn($a, $b) => ($this->state['keyword_uses'][$b] <=> $this->state['keyword_uses'][$a]) ?: strcmp($this->script['keywords'][$a]['word'], $this->script['keywords'][$b]['word']));
        $lines = ['keyword,rank,uses,replies,decomposition_hits'];
        foreach ($ids as $id) {
            $key = $this->script['keywords'][$id];
            $hits = $key['decomps'] ? implode('/', array_map(fn($rule) => $this->state['hits'][$rule], $key['decomps'])) : '-';
            $lines[] = implode(',', [$key['word'], $key['rank'], $this->state['keyword_uses'][$id], $this->state['keyword_replies'][$id], $hits]);
        }
        return $lines;
    }
}

function write_lines(string $name, array $lines): void {
    file_put_contents("output/$name", $lines ? implode("\n", $lines) . "\n" : '');
}

$script = load_script('input/script.txt');
if (!is_dir('output')) mkdir('output', 0777, true);
write_lines('lint.txt', lint_script($script));
$chatbot = new Chatbot($script);
$chatbot->run(read_lines('input/dialogue.txt'));
write_lines('transcript.txt', $chatbot->transcript);
write_lines('keyword_stats.csv', $chatbot->keywordStats());
write_lines('memory_log.txt', $chatbot->state['memory']['log']);
