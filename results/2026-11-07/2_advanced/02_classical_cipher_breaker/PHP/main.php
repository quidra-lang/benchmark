<?php
declare(strict_types=1);

namespace CipherBenchmark;

require_once __DIR__ . '/scoring.php';
require_once __DIR__ . '/substitution.php';
require_once __DIR__ . '/transposition.php';
require_once __DIR__ . '/playfair.php';
require_once __DIR__ . '/analysis.php';

final class JobFault extends \Exception {}

final class Candidate
{
    public function __construct(
        public string $key,
        public string $plain,
        public int $score,
        public int $order
    ) {}
}

final class BreakOutcome
{
    public function __construct(
        public array $ranked,
        public Candidate $choice,
        public int $length = 0,
        public string $method = '',
        public int $passes = 0,
        public int $changes = 0,
        public ?array $kasiski = null
    ) {}
}

final class Benchmark
{
    private const COMMANDS = [
        'ENCRYPT', 'DECRYPT', 'BREAK', 'ANALYZE', 'COMPARE', 'IDENTIFY',
    ];
    private const CIPHERS = [
        'caesar', 'affine', 'vigenere', 'autokey', 'railfence', 'columnar', 'playfair',
    ];
    private const MULTIPLIERS = [1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25];

    private array $messages = [];
    private array $totals = [];
    private array $results = [];
    private array $candidates = [];
    private array $analysis = [];
    private array $mono;
    private array $bi;

    public function __construct()
    {
        [$this->mono, $this->bi] = readWeights('input/weights.txt');
        foreach (self::COMMANDS as $command) {
            $this->totals[$command] = [0, 0];
        }
        $this->loadMessages('input/messages.txt');
    }

    private function fail(string $reason): never
    {
        throw new JobFault($reason);
    }

    private function name(string $text): bool
    {
        return preg_match('/\A[a-z0-9_]{1,16}\z/', $text) === 1;
    }

    private function digits(string $text, int $max): bool
    {
        return preg_match('/\A[0-9]{1,' . $max . '}\z/', $text) === 1;
    }

    private function body(string $name): string
    {
        return implode("\n", $this->messages[$name]);
    }

    private function letterString(string $name): string
    {
        return letters($this->body($name));
    }

    private function isSubstitution(string $cipher): bool
    {
        return in_array($cipher, ['caesar', 'affine', 'vigenere', 'autokey'], true);
    }

    private function loadMessages(string $path): void
    {
        $name = null;
        $lines = [];
        foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
            if ($name === null) {
                if ($line === '') {
                    continue;
                }
                $name = substr($line, 8);
                $lines = [];
            } elseif ($line === 'END') {
                $this->messages[$name] = $lines;
                $name = null;
            } else {
                $lines[] = $line;
            }
        }
    }

    private function normalizeKey(string $cipher, string $raw): string
    {
        if ($cipher === 'caesar') {
            if (!$this->digits($raw, 2) || (int) $raw > 25) {
                $this->fail("bad key $raw");
            }
            return (string) (int) $raw;
        }
        if ($cipher === 'affine') {
            $parts = explode(',', $raw);
            if (count($parts) !== 2 || !$this->digits($parts[0], 2)
                || !$this->digits($parts[1], 2)
                || !in_array((int) $parts[0], self::MULTIPLIERS, true)
                || (int) $parts[1] > 25) {
                $this->fail("bad key $raw");
            }
            return (int) $parts[0] . ',' . (int) $parts[1];
        }
        if ($cipher === 'railfence') {
            if (!$this->digits($raw, 2) || (int) $raw < 2 || (int) $raw > 20) {
                $this->fail("bad key $raw");
            }
            return (string) (int) $raw;
        }
        $pattern = match ($cipher) {
            'vigenere', 'autokey' => '/\A[A-Za-z]{1,20}\z/',
            'playfair' => '/\A[A-Za-z]{1,25}\z/',
            'columnar' => '/\A[A-Za-z0-9]{2,9}\z/',
            default => '',
        };
        if (preg_match($pattern, $raw) !== 1) {
            $this->fail("bad key $raw");
        }
        $key = strtoupper($raw);
        return $cipher === 'playfair' ? str_replace('J', 'I', $key) : $key;
    }

    private function rules(string $command, string $cipher): array
    {
        $rules = [];
        if ($command === 'ANALYZE') {
            $rules['MAXLEN'] = [2, 20, 10];
        }
        if ($command !== 'BREAK') {
            return $rules;
        }
        $rules['TOP'] = [1, 20, 5];
        if ($cipher === 'vigenere') {
            $rules['MAXLEN'] = [2, 20, 10];
            $rules['IOC'] = [1, 100000, 6000];
            $rules['KASISKI'] = [1, 100, 60];
            $rules['REFINE'] = [0, 10, 5];
        } elseif ($cipher === 'autokey') {
            $rules['MAXLEN'] = [1, 20, 8];
        } elseif ($cipher === 'railfence') {
            $rules['MAXRAILS'] = [2, 20, 10];
        } elseif ($cipher === 'columnar') {
            $rules['MAXLEN'] = [2, 6, 6];
        }
        return $rules;
    }

    private function parseOptions(string $command, string $cipher, array $words): array
    {
        $rules = $this->rules($command, $cipher);
        $values = [];
        foreach ($rules as $name => $bounds) {
            $values[$name] = (string) $bounds[2];
        }
        $seen = [];
        foreach ($words as $word) {
            $separator = strpos($word, '=');
            $name = $separator === false ? '' : substr($word, 0, $separator);
            $value = $separator === false ? '' : substr($word, $separator + 1);
            if ($separator === false || isset($seen[$name])) {
                $this->fail("bad option $word");
            }
            $seen[$name] = true;
            if ($name === 'KEYS' && ($command === 'IDENTIFY'
                || ($command === 'BREAK' && $cipher === 'playfair'))) {
                if (!$this->name($value)) {
                    $this->fail("bad option $word");
                }
                $values[$name] = $value;
                continue;
            }
            if (!isset($rules[$name]) || !$this->digits($value, 6)
                || (int) $value < $rules[$name][0] || (int) $value > $rules[$name][1]) {
                $this->fail("bad option $word");
            }
            $values[$name] = (string) (int) $value;
        }
        if ($command === 'BREAK' && $cipher === 'playfair' && !isset($values['KEYS'])) {
            $this->fail('missing option KEYS');
        }
        return $values;
    }

    private function decrypt(string $text, string $cipher, string $key): string
    {
        if ($this->isSubstitution($cipher)) {
            return letters(applySubstitution($text, $cipher, $key, false));
        }
        return match ($cipher) {
            'railfence' => railFence($text, (int) $key, false),
            'columnar' => columnar($text, $key, false),
            default => playfair($text, $key, false),
        };
    }

    private function transform(string $text, string $cipher, string $key, bool $encrypt): string
    {
        if ($this->isSubstitution($cipher)) {
            return applySubstitution($text, $cipher, $key, $encrypt);
        }
        $text = letters($text);
        return match ($cipher) {
            'railfence' => railFence($text, (int) $key, $encrypt),
            'columnar' => columnar($text, $key, $encrypt),
            default => playfair($text, $key, $encrypt),
        };
    }

    private function keyList(string $name): array
    {
        preg_match_all('/[A-Za-z]+/', $this->body($name), $matches);
        $keys = [];
        $seen = [];
        foreach ($matches[0] as $raw) {
            $key = str_replace('J', 'I', strtoupper($raw));
            if (!isset($seen[$key])) {
                $seen[$key] = true;
                $keys[] = $key;
            }
        }
        return $keys;
    }

    private function permutations(int $length): array
    {
        $digits = array_map('strval', range(1, $length));
        $result = [];
        $visit = function (int $index) use (&$visit, &$digits, &$result): void {
            if ($index === count($digits)) {
                $result[] = implode('', $digits);
                return;
            }
            for ($i = $index; $i < count($digits); $i++) {
                [$digits[$index], $digits[$i]] = [$digits[$i], $digits[$index]];
                $visit($index + 1);
                [$digits[$index], $digits[$i]] = [$digits[$i], $digits[$index]];
            }
        };
        $visit(0);
        sort($result, SORT_STRING);
        return $result;
    }

    private function columnKey(string $text, int $length, bool $autokey): string
    {
        $key = '';
        for ($position = 0; $position < $length; $position++) {
            $part = column($text, $length, $position);
            $high = PHP_INT_MIN;
            $best = 0;
            for ($guess = 0; $guess < 26; $guess++) {
                if (!$autokey) {
                    $score = monogram(applySubstitution($part, 'caesar', (string) $guess, false),
                        $this->mono);
                } else {
                    $previous = $guess;
                    $score = 0;
                    for ($i = 0; $i < strlen($part); $i++) {
                        $previous = modulo(value($part[$i]) - $previous);
                        $score += $this->mono[$previous];
                    }
                }
                if ($score > $high) {
                    $high = $score;
                    $best = $guess;
                }
            }
            $key .= upper($best);
        }
        return $key;
    }

    private function candidateKeys(string $cipher, string $text, array $options, ?array $keys): array
    {
        $result = [];
        if ($cipher === 'caesar') {
            return array_map('strval', range(0, 25));
        }
        if ($cipher === 'affine') {
            foreach (self::MULTIPLIERS as $a) {
                for ($b = 0; $b < 26; $b++) {
                    $result[] = "$a,$b";
                }
            }
        } elseif ($cipher === 'railfence') {
            $result = array_map('strval', range(2, (int) $options['MAXRAILS']));
        } elseif ($cipher === 'columnar') {
            for ($i = 2; $i <= (int) $options['MAXLEN']; $i++) {
                array_push($result, ...$this->permutations($i));
            }
        } elseif ($cipher === 'playfair') {
            $result = $keys;
        } else {
            for ($i = 1; $i <= (int) $options['MAXLEN']; $i++) {
                $result[] = $this->columnKey($text, $i, $cipher === 'autokey');
            }
        }
        return $result;
    }

    private function score(string $cipher, string $text): int
    {
        return $cipher === 'caesar' || $cipher === 'affine'
            ? monogram($text, $this->mono) : bigram($text, $this->bi);
    }

    private function breakCipher(string $cipher, string $text, array $options,
                                 ?array $keys = null): BreakOutcome
    {
        $candidates = [];
        foreach ($this->candidateKeys($cipher, $text, $options, $keys) as $key) {
            $plain = $this->decrypt($text, $cipher, $key);
            $candidates[] = new Candidate($key, $plain, $this->score($cipher, $plain),
                count($candidates));
        }
        $ranked = $candidates;
        usort($ranked, fn(Candidate $a, Candidate $b): int =>
            $b->score <=> $a->score ?: $a->order <=> $b->order);
        if ($cipher !== 'vigenere') {
            return new BreakOutcome($ranked, $ranked[0]);
        }

        $maxlen = (int) $options['MAXLEN'];
        $threshold = (int) $options['IOC'];
        $data = kasiski($text);
        $averages = [];
        for ($i = 1; $i <= $maxlen; $i++) {
            $averages[$i] = averageIoc($text, $i);
        }
        $kasiskiLength = 0;
        for ($length = 2; $length <= $maxlen; $length++) {
            if (count($data['gaps']) >= 1
                && 100 * kasiskiCount($data, $length)
                    >= (int) $options['KASISKI'] * count($data['gaps'])) {
                $kasiskiLength = $length;
            }
        }
        if ($kasiskiLength !== 0 && $averages[$kasiskiLength] >= $threshold) {
            $chosen = $kasiskiLength;
            $method = 'kasiski';
        } else {
            $chosen = 0;
            for ($i = 1; $i <= $maxlen; $i++) {
                if ($averages[$i] >= $threshold) {
                    $chosen = $i;
                    break;
                }
            }
            if ($chosen !== 0) {
                $method = 'ioc';
            } else {
                $chosen = 1;
                for ($i = 2; $i <= $maxlen; $i++) {
                    if ($averages[$i] > $averages[$chosen]) {
                        $chosen = $i;
                    }
                }
                $method = 'maxioc';
            }
        }
        $key = $candidates[$chosen - 1]->key;
        $reference = $this->score($cipher, $this->decrypt($text, $cipher, $key));
        $passes = 0;
        $changes = 0;
        for ($pass = 0; $pass < (int) $options['REFINE']; $pass++) {
            $passes++;
            $changed = 0;
            for ($index = 0; $index < strlen($key); $index++) {
                $best = $key[$index];
                $high = $reference;
                for ($letter = 0; $letter < 26; $letter++) {
                    $trial = substr($key, 0, $index) . upper($letter)
                        . substr($key, $index + 1);
                    $score = $this->score($cipher, $this->decrypt($text, $cipher, $trial));
                    if ($score > $high) {
                        $high = $score;
                        $best = upper($letter);
                    }
                }
                if ($high > $reference) {
                    $key = substr($key, 0, $index) . $best . substr($key, $index + 1);
                    $reference = $high;
                    $changes++;
                    $changed++;
                }
            }
            if ($changed === 0) {
                break;
            }
        }
        return new BreakOutcome($ranked,
            new Candidate($key, $this->decrypt($text, $cipher, $key), $reference, -1),
            $chosen, $method, $passes, $changes, $data);
    }

    private function candidateReport(int $job, string $cipher, string $source,
                                     BreakOutcome $broken, int $top): void
    {
        $count = count($broken->ranked);
        $margin = $count > 1 ? $broken->ranked[0]->score - $broken->ranked[1]->score : 0;
        $this->candidates[] = "JOB $job BREAK $cipher source=$source tried=$count margin=$margin";
        foreach (array_slice($broken->ranked, 0, $top) as $position => $candidate) {
            $rank = $position + 1;
            $this->candidates[] = "$rank $candidate->key $candidate->score "
                . substr($candidate->plain, 0, 40);
        }
    }

    private function breakAnalysis(int $job, string $cipher, string $source,
                                   string $text, array $options, BreakOutcome $broken): void
    {
        if ($cipher === 'vigenere') {
            $this->analysis[] = "JOB $job BREAK vigenere source=$source";
            $this->analysis[] = 'letters=' . strlen($text);
            array_push($this->analysis, ...periodTable($text, (int) $options['MAXLEN'],
                $broken->kasiski));
            array_push($this->analysis, ...kasiskiTable($broken->kasiski));
            $this->analysis[] = "decision length=$broken->length method=$broken->method";
            $this->analysis[] = "refine passes=$broken->passes changes=$broken->changes key="
                . $broken->choice->key;
        } elseif ($cipher === 'playfair') {
            $t = str_replace('J', 'I', $text);
            $pairs = str_split($t, 2);
            $this->analysis[] = "JOB $job BREAK playfair source=$source";
            $this->analysis[] = 'letters=' . strlen($t);
            $this->analysis[] = 'digraphs pairs=' . count($pairs)
                . ' distinct=' . count(array_unique($pairs));
            $this->analysis[] = 'top ' . topPairs($t, true);
            $this->analysis[] = 'square ' . implode(' ', str_split(square($broken->choice->key), 5));
        }
    }

    private function outputText(string $source, string $cipher,
                                string $key, bool $encrypt): array
    {
        $result = $this->transform($source, $cipher, $key, $encrypt);
        return $this->isSubstitution($cipher) ? explode("\n", $result) : grouped($result);
    }

    private function save(?string $name, array $lines): void
    {
        if ($name !== null) {
            $this->messages[$name] = $lines;
        }
    }

    private function cipherJob(int $job, string $command, string $cipher,
                               string $key, string $source, ?string $target): void
    {
        $text = $this->letterString($source);
        if ($text === '') {
            $this->fail('no letters');
        }
        if ($command === 'DECRYPT' && $cipher === 'playfair' && !validPlayfair($text)) {
            $this->fail('bad playfair text');
        }
        $lines = $this->outputText($this->body($source), $cipher, $key,
            $command === 'ENCRYPT');
        $letters = array_sum(array_map(fn(string $line): int => strlen(letters($line)), $lines));
        $suffix = $target !== null ? " as=$target" : '';
        $count = count($lines);
        $this->results[] = "JOB $job $command $cipher key=$key source=$source letters=$letters lines=$count$suffix";
        array_push($this->results, ...$lines);
        $this->save($target, $lines);
    }

    private function breakJob(int $job, string $cipher, string $source,
                              ?string $target, array $options): void
    {
        $text = $this->letterString($source);
        if (strlen($text) < 40) {
            $this->fail('text too short');
        }
        if ($cipher === 'playfair' && !validPlayfair($text)) {
            $this->fail('bad playfair text');
        }
        $keys = $cipher === 'playfair' ? $this->keyList($options['KEYS']) : null;
        if ($cipher === 'playfair' && count($keys) === 0) {
            $this->fail('empty key list');
        }
        $broken = $this->breakCipher($cipher, $text, $options, $keys);
        $lines = $this->outputText($this->body($source), $cipher, $broken->choice->key, false);
        $count = count($lines);
        $suffix = $target !== null ? " as=$target" : '';
        $this->results[] = "JOB $job BREAK $cipher source=$source key="
            . $broken->choice->key . ' score=' . $broken->choice->score . " lines=$count$suffix";
        array_push($this->results, ...$lines);
        $this->candidateReport($job, $cipher, $source, $broken, (int) $options['TOP']);
        $this->breakAnalysis($job, $cipher, $source, $text, $options, $broken);
        $this->save($target, $lines);
    }

    private function analyzeJob(int $job, string $source, array $options): void
    {
        $text = $this->letterString($source);
        if (strlen($text) < 40) {
            $this->fail('text too short');
        }
        $length = strlen($text);
        $this->results[] = "JOB $job ANALYZE source=$source letters=$length";
        $this->analysis[] = "JOB $job ANALYZE source=$source";
        array_push($this->analysis, ...analyze($text, (int) $options['MAXLEN'],
            $this->mono, $this->bi));
    }

    private function compareJob(int $job, string $leftName, string $rightName): void
    {
        $first = $this->letterString($leftName);
        $second = $this->letterString($rightName);
        $n = min(strlen($first), strlen($second));
        $position = $n + 1;
        $mismatches = 0;
        for ($i = 0; $i < $n; $i++) {
            if ($first[$i] !== $second[$i]) {
                if ($mismatches === 0) {
                    $position = $i + 1;
                }
                $mismatches++;
            }
        }
        if ($first === $second) {
            $this->results[] = "JOB $job COMPARE $leftName $rightName equal letters="
                . strlen($first);
        } else {
            $this->results[] = "JOB $job COMPARE $leftName $rightName differ letters="
                . strlen($first) . ',' . strlen($second)
                . " first=$position mismatches=$mismatches";
        }
    }

    private function identifyJob(int $job, string $source, array $options): void
    {
        $text = $this->letterString($source);
        $n = strlen($text);
        if ($n < 40) {
            $this->fail('text too short');
        }
        $ioc = ioc($text);
        $average = intdiv(monogram($text, $this->mono), $n);
        $distinct = count(array_filter(frequency($text), fn(int $v): bool => $v !== 0));
        $shape = strpos($text, 'J') === false && validPlayfair($text);
        $family = $shape ? 'playfair' : ($ioc >= 5500
            ? ($average >= 44 ? 'transposition' : 'monoalphabetic') : 'polyalphabetic');
        $keys = $family === 'playfair' && isset($options['KEYS'])
            ? $this->keyList($options['KEYS']) : null;
        if ($family === 'playfair' && $keys !== null && count($keys) === 0) {
            $this->fail('empty key list');
        }
        $ciphers = match ($family) {
            'transposition' => ['railfence', 'columnar'],
            'monoalphabetic' => ['affine'],
            'polyalphabetic' => ['vigenere', 'autokey'],
            default => $keys === null ? [] : ['playfair'],
        };
        $tested = [];
        $best = null;
        foreach ($ciphers as $cipher) {
            $raw = $cipher === 'playfair' ? ['KEYS=' . $options['KEYS']] : [];
            $defaults = $this->parseOptions('BREAK', $cipher, $raw);
            $result = $this->breakCipher($cipher, $text, $defaults, $keys)->choice;
            $tested[] = [$cipher, $result];
            if ($best === null || $result->score > $best[1]->score) {
                $best = [$cipher, $result];
            }
        }
        $heading = "JOB $job IDENTIFY source=$source family=$family";
        $reported = null;
        if ($best !== null) {
            [$reported, $winner] = $best;
            $key = $winner->key;
            if ($reported === 'affine') {
                [$a, $b] = explode(',', $key);
                if ($a === '1') {
                    $reported = 'caesar';
                    $key = $b;
                }
            }
            $lines = $this->outputText($this->body($source), $reported, $key, false);
            $heading .= " cipher=$reported key=$key score=$winner->score lines=" . count($lines);
            $this->results[] = $heading;
            array_push($this->results, ...$lines);
        } else {
            $this->results[] = $heading;
        }
        $this->analysis[] = "JOB $job IDENTIFY source=$source";
        $this->analysis[] = "letters=$n ioc=$ioc mono_avg=$average distinct=$distinct shape="
            . ($shape ? 'yes' : 'no');
        $this->analysis[] = "family=$family";
        foreach ($tested as [$cipher, $winner]) {
            $this->analysis[] = "try $cipher key=$winner->key score=$winner->score";
        }
        if ($reported !== null) {
            $this->analysis[] = "choice $reported";
        }
    }

    private function checkReferences(array $words, string $command, array $options): void
    {
        $source = in_array($command, ['ENCRYPT', 'DECRYPT', 'BREAK'], true)
            ? $words[$command === 'BREAK' ? 2 : 3] : $words[1];
        if (!array_key_exists($source, $this->messages)) {
            $this->fail("unknown message $source");
        }
        if (isset($options['KEYS']) && !array_key_exists($options['KEYS'], $this->messages)) {
            $this->fail('unknown message ' . $options['KEYS']);
        }
        if ($command === 'COMPARE' && !array_key_exists($words[2], $this->messages)) {
            $this->fail('unknown message ' . $words[2]);
        }
    }

    private function execute(int $job, string $line): void
    {
        $words = explode(' ', $line);
        $command = $words[0];
        if (!in_array($command, self::COMMANDS, true)) {
            $this->fail('unknown command');
        }
        $target = null;
        if (in_array($command, ['ENCRYPT', 'DECRYPT', 'BREAK'], true)
            && count($words) >= 5 && $words[count($words) - 2] === 'AS') {
            $target = array_pop($words);
            array_pop($words);
            if (!$this->name($target)) {
                $this->fail('bad syntax');
            }
        }
        $valid = match ($command) {
            'ENCRYPT', 'DECRYPT' => count($words) === 4,
            'BREAK' => count($words) >= 3,
            'ANALYZE', 'IDENTIFY' => count($words) === 2 || count($words) === 3,
            'COMPARE' => count($words) === 3,
        };
        if (!$valid) {
            $this->fail('bad syntax');
        }
        $cipher = in_array($command, ['ENCRYPT', 'DECRYPT', 'BREAK'], true) ? $words[1] : '';
        if ($cipher !== '' && !in_array($cipher, self::CIPHERS, true)) {
            $this->fail("unknown cipher $cipher");
        }
        $key = in_array($command, ['ENCRYPT', 'DECRYPT'], true)
            ? $this->normalizeKey($cipher, $words[2]) : '';
        $optionWords = match ($command) {
            'BREAK' => array_slice($words, 3),
            'ANALYZE', 'IDENTIFY' => array_slice($words, 2),
            default => [],
        };
        $options = $this->parseOptions($command, $cipher, $optionWords);
        $this->checkReferences($words, $command, $options);
        if ($target !== null && array_key_exists($target, $this->messages)) {
            $this->fail("duplicate message $target");
        }
        match ($command) {
            'ENCRYPT', 'DECRYPT' => $this->cipherJob($job, $command, $cipher, $key,
                $words[3], $target),
            'BREAK' => $this->breakJob($job, $cipher, $words[2], $target, $options),
            'ANALYZE' => $this->analyzeJob($job, $words[1], $options),
            'COMPARE' => $this->compareJob($job, $words[1], $words[2]),
            'IDENTIFY' => $this->identifyJob($job, $words[1], $options),
        };
    }

    private function runJobs(string $path): void
    {
        $count = 0;
        $ok = 0;
        $errors = 0;
        foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
            if ($line === '' || str_starts_with($line, '#')) {
                continue;
            }
            $count++;
            $command = explode(' ', $line)[0];
            try {
                $this->execute($count, $line);
                $ok++;
                if (isset($this->totals[$command])) {
                    $this->totals[$command][0]++;
                }
            } catch (JobFault $error) {
                $errors++;
                if (isset($this->totals[$command])) {
                    $this->totals[$command][1]++;
                }
                $this->results[] = "JOB $count ERROR " . $error->getMessage();
            }
        }
        foreach (self::COMMANDS as $command) {
            [$success, $failures] = $this->totals[$command];
            $this->results[] = "TOTAL $command ok=$success errors=$failures";
        }
        $messages = count($this->messages);
        $this->results[] = "SUMMARY jobs=$count ok=$ok errors=$errors messages=$messages";
    }

    private function write(string $name, array $lines): void
    {
        $text = count($lines) > 0 ? implode("\n", $lines) . "\n" : '';
        file_put_contents('output/' . $name, $text);
    }

    public function run(): void
    {
        $this->runJobs('input/jobs.txt');
        if (!is_dir('output')) {
            mkdir('output', 0777, true);
        }
        $this->write('results.txt', $this->results);
        $this->write('candidates.txt', $this->candidates);
        $this->write('analysis.txt', $this->analysis);
    }
}

(new Benchmark())->run();
