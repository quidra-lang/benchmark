<?php
declare(strict_types=1);

enum Kind: string
{
    case Text = 'string';
    case Sequence = 'list';
    case Hash = 'hash';
    case Members = 'set';
    case Scores = 'zset';
}
enum Group { case Text; case Sequence; case Hash; case Members; case Scores; case Key; case Control; }
enum PatternKind { case Literal; case Any; case Star; case CharacterClass; }

final readonly class Value
{
    public function __construct(public Kind $kind, public string|array $data) {}
}
final readonly class Entry
{
    public function __construct(public Value $value, public ?int $expiry = null) {}
}
final readonly class CommandSpec
{
    public function __construct(public Group $group, public int $minimum, public int $maximum = -1, public int $parity = -1) {}
}
final readonly class PatternPart
{
    public function __construct(public PatternKind $kind, public string $literal = '', public array $characters = [], public bool $negated = false) {}
}
final readonly class Bound
{
    public function __construct(public int $number = 0, public bool $inclusive = true, public int $infinity = 0) {}
    public function accepts(int $score, bool $lower): bool
    {
        if ($this->infinity !== 0) return $lower === ($this->infinity < 0);
        return $lower ? ($this->inclusive ? $score >= $this->number : $score > $this->number)
            : ($this->inclusive ? $score <= $this->number : $score < $this->number);
    }
}
final class CommandError extends RuntimeException {}

const WRONG_TYPE = 'WRONGTYPE Operation against a key holding the wrong kind of value';
const NOT_INTEGER = 'ERR value is not an integer or out of range';
const OVERFLOW = 'ERR increment or decrement would overflow';
const BAD_SYNTAX = 'ERR syntax error';
const POSITIVE = 'ERR value is out of range, must be positive';
const NO_KEY = 'ERR no such key';

function quoteText(string $value): string { return '"' . str_replace(['\\', '"'], ['\\\\', '\\"'], $value) . '"'; }
function integerReply(int $value): array { return ['(integer) ' . $value]; }
function textReply(?string $value): array { return [$value === null ? '(nil)' : quoteText($value)]; }
function arrayReply(array $values): array
{
    if ($values === []) return ['(empty array)'];
    $width = strlen((string)count($values));
    $output = [];
    foreach (array_values($values) as $i => $value)
        $output[] = str_pad((string)($i + 1), $width, ' ', STR_PAD_LEFT) . ') ' . ($value === null ? '(nil)' : quoteText($value));
    return $output;
}
function parseNumber(string $word, string $error = NOT_INTEGER): int
{
    if ($word === '0') return 0;
    $start = str_starts_with($word, '-') ? 1 : 0;
    $length = strlen($word) - $start;
    if ($length < 1 || $length > 9 || $word[$start] < '1' || $word[$start] > '9') throw new CommandError($error);
    for ($i = $start; $i < strlen($word); $i++)
        if ($word[$i] < '0' || $word[$i] > '9') throw new CommandError($error);
    return (int)$word;
}
function checkedAdd(int $value, int $delta): int
{
    $result = $value + $delta;
    if ($result < -999999999 || $result > 999999999) throw new CommandError(OVERFLOW);
    return $result;
}
function normalizeRange(int $length, int $start, int $stop): array
{
    if ($start < 0) $start += $length;
    if ($stop < 0) $stop += $length;
    $start = max(0, $start);
    $stop = min($length - 1, $stop);
    return $start <= $stop ? [$start, $stop - $start + 1] : [0, 0];
}
function splitArguments(string $line): ?array
{
    $words = [];
    $position = 0;
    $length = strlen($line);
    while ($position < $length) {
        if ($line[$position] === ' ') { $position++; continue; }
        if ($line[$position] !== '"') {
            $start = $position;
            while ($position < $length && $line[$position] !== ' ') $position++;
            $words[] = substr($line, $start, $position - $start);
            continue;
        }
        $position++;
        $value = '';
        $closed = false;
        while ($position < $length) {
            $character = $line[$position++];
            if ($character === '"') { $closed = true; break; }
            if ($character === '\\') {
                if ($position === $length || ($line[$position] !== '"' && $line[$position] !== '\\')) return null;
                $character = $line[$position++];
            }
            $value .= $character;
        }
        if (!$closed || ($position < $length && $line[$position] !== ' ')) return null;
        $words[] = $value;
    }
    return $words;
}
function parsePattern(string $pattern): array
{
    $parts = [];
    for ($i = 0; $i < strlen($pattern); $i++) {
        $character = $pattern[$i];
        if ($character === '\\') {
            if (++$i === strlen($pattern)) throw new CommandError('ERR invalid pattern');
            $parts[] = new PatternPart(PatternKind::Literal, $pattern[$i]);
        } elseif ($character === '[') {
            $end = strpos($pattern, ']', $i + 1);
            if ($end === false) throw new CommandError('ERR invalid pattern');
            $start = $i + 1;
            $negated = $start < $end && $pattern[$start] === '^';
            if ($negated) $start++;
            if ($start === $end) throw new CommandError('ERR invalid pattern');
            $characters = [];
            for ($j = $start; $j < $end;) {
                if ($j + 2 < $end && $pattern[$j + 1] === '-') {
                    $first = min(ord($pattern[$j]), ord($pattern[$j + 2]));
                    $last = max(ord($pattern[$j]), ord($pattern[$j + 2]));
                    for ($code = $first; $code <= $last; $code++) $characters[$code] = true;
                    $j += 3;
                } else $characters[ord($pattern[$j++])] = true;
            }
            $parts[] = new PatternPart(PatternKind::CharacterClass, characters: $characters, negated: $negated);
            $i = $end;
        } else {
            $kind = match ($character) { '*' => PatternKind::Star, '?' => PatternKind::Any, default => PatternKind::Literal };
            $parts[] = new PatternPart($kind, $character);
        }
    }
    return $parts;
}
function matchesPattern(array $parts, string $value): bool
{
    $previous = array_fill(0, strlen($value) + 1, false);
    $previous[0] = true;
    foreach ($parts as $part) {
        $current = array_fill(0, count($previous), false);
        if ($part->kind === PatternKind::Star) {
            $current[0] = $previous[0];
            for ($i = 1; $i < count($current); $i++) $current[$i] = $previous[$i] || $current[$i - 1];
        } else {
            for ($i = 0; $i < strlen($value); $i++) {
                $accepts = match ($part->kind) {
                    PatternKind::Any => true,
                    PatternKind::Literal => $part->literal === $value[$i],
                    default => isset($part->characters[ord($value[$i])]) !== $part->negated,
                };
                $current[$i + 1] = $previous[$i] && $accepts;
            }
        }
        $previous = $current;
    }
    return $previous[strlen($value)];
}
function parseBound(string $word): Bound
{
    if ($word === '-inf') return new Bound(infinity: -1);
    if ($word === '+inf') return new Bound(infinity: 1);
    $inclusive = !str_starts_with($word, '(');
    return new Bound(parseNumber($inclusive ? $word : substr($word, 1), 'ERR min or max is not a float'), $inclusive);
}
function commandSpecs(): array
{
    $specs = [];
    $add = function (Group $group, string $names, int $minimum, int $maximum = -1, int $parity = -1) use (&$specs): void {
        foreach (explode(' ', $names) as $name) $specs[$name] = new CommandSpec($group, $minimum, $maximum, $parity);
    };
    $add(Group::Text, 'SET', 2);
    $add(Group::Text, 'GET INCR DECR STRLEN', 1, 1);
    $add(Group::Text, 'MSET', 2, parity: 0);
    $add(Group::Text, 'MGET', 1);
    $add(Group::Text, 'INCRBY DECRBY APPEND', 2, 2);
    $add(Group::Text, 'GETRANGE', 3, 3);
    $add(Group::Sequence, 'LPUSH RPUSH', 2);
    $add(Group::Sequence, 'LPOP RPOP', 1, 2);
    $add(Group::Sequence, 'LRANGE LSET LREM LTRIM', 3, 3);
    $add(Group::Sequence, 'LLEN', 1, 1);
    $add(Group::Sequence, 'LINDEX', 2, 2);
    $add(Group::Sequence, 'LINSERT', 4, 4);
    $add(Group::Hash, 'HSET', 3, parity: 1);
    $add(Group::Hash, 'HGET HEXISTS', 2, 2);
    $add(Group::Hash, 'HDEL', 2);
    $add(Group::Hash, 'HGETALL HLEN HKEYS HVALS', 1, 1);
    $add(Group::Hash, 'HINCRBY', 3, 3);
    $add(Group::Members, 'SADD SREM SINTERSTORE SUNIONSTORE SDIFFSTORE', 2);
    $add(Group::Members, 'SISMEMBER', 2, 2);
    $add(Group::Members, 'SMEMBERS SCARD', 1, 1);
    $add(Group::Members, 'SINTER SUNION SDIFF', 1);
    $add(Group::Scores, 'ZADD', 3, parity: 1);
    $add(Group::Scores, 'ZSCORE ZRANK', 2, 2);
    $add(Group::Scores, 'ZINCRBY', 3, 3);
    $add(Group::Scores, 'ZREM', 2);
    $add(Group::Scores, 'ZCARD', 1, 1);
    $add(Group::Scores, 'ZRANGE ZRANGEBYSCORE', 3, 4);
    $add(Group::Key, 'DEL EXISTS', 1);
    $add(Group::Key, 'TYPE KEYS TTL PERSIST TICK', 1, 1);
    $add(Group::Key, 'RENAME RENAMENX', 2, 2);
    $add(Group::Key, 'EXPIRE', 2, 3);
    $add(Group::Control, 'TIME DBSIZE FLUSH INFO BEGIN COMMIT ROLLBACK', 0, 0);
    $add(Group::Control, 'SNAPSHOT RESTORE', 1, 1);
    return $specs;
}

final class Store
{
    private array $database = [];
    private array $transactions = [];
    private array $snapshots = [];
    private int $time = 0;

    private function entry(string $key): ?Entry { return $this->database[':' . $key] ?? null; }
    private function value(string $key, Kind $kind): ?Value
    {
        $entry = $this->entry($key);
        if ($entry !== null && $entry->value->kind !== $kind) throw new CommandError(WRONG_TYPE);
        return $entry?->value;
    }
    private function put(string $key, Value $value, ?int $expiry = null): void
    {
        $this->database[':' . $key] = new Entry($value, $expiry);
    }
    private function update(string $key, Kind $kind, string|array $data): void
    {
        if ($kind !== Kind::Text && $data === []) unset($this->database[':' . $key]);
        else $this->put($key, new Value($kind, $data), $this->entry($key)?->expiry);
    }
    private function purge(): int
    {
        $removed = 0;
        foreach ($this->database as $key => $entry)
            if ($entry->expiry !== null && $entry->expiry <= $this->time) { unset($this->database[$key]); $removed++; }
        return $removed;
    }
    public function execute(array $words, array $specs): array
    {
        $command = strtoupper($words[0]);
        $spec = $specs[$command] ?? null;
        if ($spec === null) throw new CommandError("ERR unknown command '" . $words[0] . "'");
        $args = array_slice($words, 1);
        $count = count($args);
        if ($count < $spec->minimum || ($spec->maximum >= 0 && $count > $spec->maximum)
            || ($spec->parity >= 0 && $count % 2 !== $spec->parity))
            throw new CommandError("ERR wrong number of arguments for '" . strtolower($command) . "' command");
        return match ($spec->group) {
            Group::Text => $this->textCommand($command, $args),
            Group::Sequence => $this->listCommand($command, $args),
            Group::Hash => $this->hashCommand($command, $args),
            Group::Members => $this->setCommand($command, $args),
            Group::Scores => $this->sortedSetCommand($command, $args),
            Group::Key => $this->keyCommand($command, $args),
            Group::Control => $this->controlCommand($command, $args),
        };
    }
    private function textCommand(string $command, array $args): array
    {
        $key = $args[0];
        if ($command === 'SET') {
            $options = [];
            $secondsWord = null;
            for ($i = 2; $i < count($args); $i++) {
                $option = strtoupper($args[$i]);
                if (!in_array($option, ['NX', 'XX', 'EX', 'KEEPTTL', 'GET'], true) || isset($options[$option])) throw new CommandError(BAD_SYNTAX);
                $options[$option] = true;
                if ($option === 'EX') {
                    if (++$i === count($args)) throw new CommandError(BAD_SYNTAX);
                    $secondsWord = $args[$i];
                }
            }
            if ((isset($options['NX']) && isset($options['XX'])) || (isset($options['EX']) && isset($options['KEEPTTL'])))
                throw new CommandError(BAD_SYNTAX);
            $seconds = $secondsWord === null ? null : parseNumber($secondsWord);
            if ($seconds !== null && $seconds <= 0) throw new CommandError("ERR invalid expire time in 'set' command");
            $old = $this->entry($key);
            $previous = isset($options['GET']) ? $this->value($key, Kind::Text)?->data : null;
            $changed = !(isset($options['NX']) && $old !== null) && !(isset($options['XX']) && $old === null);
            if ($changed) {
                $expiry = $seconds !== null ? $this->time + $seconds : (isset($options['KEEPTTL']) ? $old?->expiry : null);
                $this->put($key, new Value(Kind::Text, $args[1]), $expiry);
            }
            return isset($options['GET']) ? textReply($previous) : ($changed ? ['OK'] : textReply(null));
        }
        if ($command === 'MSET') {
            for ($i = 0; $i < count($args); $i += 2) $this->put($args[$i], new Value(Kind::Text, $args[$i + 1]));
            return ['OK'];
        }
        if ($command === 'MGET') {
            $result = [];
            foreach ($args as $name) {
                $entry = $this->entry($name);
                $result[] = $entry?->value->kind === Kind::Text ? $entry->value->data : null;
            }
            return arrayReply($result);
        }
        if (in_array($command, ['INCR', 'DECR', 'INCRBY', 'DECRBY'], true)) {
            $delta = count($args) === 2 ? parseNumber($args[1]) : 1;
            if ($command === 'DECR' || $command === 'DECRBY') $delta = -$delta;
            $old = $this->value($key, Kind::Text);
            $result = checkedAdd($old === null ? 0 : parseNumber($old->data), $delta);
            $this->update($key, Kind::Text, (string)$result);
            return integerReply($result);
        }
        $start = $stop = 0;
        if ($command === 'GETRANGE') { $start = parseNumber($args[1]); $stop = parseNumber($args[2]); }
        $old = $this->value($key, Kind::Text);
        if ($command === 'GET') return textReply($old?->data);
        $text = $old?->data ?? '';
        if ($command === 'STRLEN') return integerReply(strlen($text));
        if ($command === 'APPEND') {
            $text .= $args[1];
            $this->update($key, Kind::Text, $text);
            return integerReply(strlen($text));
        }
        [$start, $count] = normalizeRange(strlen($text), $start, $stop);
        return textReply(substr($text, $start, $count));
    }
    private function listCommand(string $command, array $args): array
    {
        $key = $args[0];
        $first = $second = 0;
        if ($command === 'LPOP' || $command === 'RPOP') {
            if (count($args) === 2) {
                $first = parseNumber($args[1], POSITIVE);
                if ($first < 0) throw new CommandError(POSITIVE);
            }
        } elseif (in_array($command, ['LINDEX', 'LSET', 'LREM', 'LRANGE', 'LTRIM'], true)) {
            $first = parseNumber($args[1]);
            if ($command === 'LRANGE' || $command === 'LTRIM') $second = parseNumber($args[2]);
        } elseif ($command === 'LINSERT' && !in_array(strtoupper($args[1]), ['BEFORE', 'AFTER'], true)) {
            throw new CommandError(BAD_SYNTAX);
        }
        $old = $this->value($key, Kind::Sequence);
        $items = $old?->data ?? [];
        if ($command === 'LPUSH' || $command === 'RPUSH') {
            foreach (array_slice($args, 1) as $item)
                if ($command === 'LPUSH') array_unshift($items, $item); else $items[] = $item;
            $this->update($key, Kind::Sequence, $items);
            return integerReply(count($items));
        }
        if ($command === 'LPOP' || $command === 'RPOP') {
            if ($old === null) return textReply(null);
            $count = count($args) === 1 ? 1 : min($first, count($items));
            $removed = [];
            for ($i = 0; $i < $count; $i++) $removed[] = $command === 'LPOP' ? array_shift($items) : array_pop($items);
            $this->update($key, Kind::Sequence, $items);
            return count($args) === 1 ? textReply($removed[0]) : arrayReply($removed);
        }
        if ($command === 'LLEN') return integerReply(count($items));
        if ($command === 'LINDEX' || $command === 'LSET') {
            $index = $first < 0 ? $first + count($items) : $first;
            $valid = $index >= 0 && $index < count($items);
            if ($command === 'LINDEX') return textReply($valid ? $items[$index] : null);
            if ($old === null) throw new CommandError(NO_KEY);
            if (!$valid) throw new CommandError('ERR index out of range');
            $items[$index] = $args[2];
            $this->update($key, Kind::Sequence, $items);
            return ['OK'];
        }
        if ($command === 'LRANGE' || $command === 'LTRIM') {
            [$start, $count] = normalizeRange(count($items), $first, $second);
            $items = array_slice($items, $start, $count);
            if ($command === 'LRANGE') return arrayReply($items);
            $this->update($key, Kind::Sequence, $items);
            return ['OK'];
        }
        if ($command === 'LREM') {
            $removed = 0;
            $indices = array_keys($items);
            if ($first < 0) $indices = array_reverse($indices);
            foreach ($indices as $index)
                if ($items[$index] === $args[2] && ($first === 0 || $removed < abs($first))) {
                    unset($items[$index]);
                    $removed++;
                }
            $this->update($key, Kind::Sequence, array_values($items));
            return integerReply($removed);
        }
        if ($old === null) return integerReply(0);
        $index = array_search($args[2], $items, true);
        if ($index === false) return integerReply(-1);
        if (strtoupper($args[1]) === 'AFTER') $index++;
        array_splice($items, $index, 0, [$args[3]]);
        $this->update($key, Kind::Sequence, $items);
        return integerReply(count($items));
    }
    private function hashCommand(string $command, array $args): array
    {
        $key = $args[0];
        $delta = $command === 'HINCRBY' ? parseNumber($args[2]) : 0;
        $fields = $this->value($key, Kind::Hash)?->data ?? [];
        if ($command === 'HSET') {
            $added = 0;
            for ($i = 1; $i < count($args); $i += 2) {
                $field = ':' . $args[$i];
                if (!isset($fields[$field])) $added++;
                $fields[$field] = $args[$i + 1];
            }
            $this->update($key, Kind::Hash, $fields);
            return integerReply($added);
        }
        if ($command === 'HGET') return textReply($fields[':' . $args[1]] ?? null);
        if ($command === 'HEXISTS') return integerReply(isset($fields[':' . $args[1]]) ? 1 : 0);
        if ($command === 'HLEN') return integerReply(count($fields));
        if ($command === 'HDEL') {
            $removed = 0;
            foreach (array_slice($args, 1) as $name) {
                $field = ':' . $name;
                if (isset($fields[$field])) { unset($fields[$field]); $removed++; }
            }
            $this->update($key, Kind::Hash, $fields);
            return integerReply($removed);
        }
        if ($command === 'HINCRBY') {
            $field = ':' . $args[1];
            $old = isset($fields[$field]) ? parseNumber($fields[$field], 'ERR hash value is not an integer') : 0;
            $result = checkedAdd($old, $delta);
            $fields[$field] = (string)$result;
            $this->update($key, Kind::Hash, $fields);
            return integerReply($result);
        }
        ksort($fields, SORT_STRING);
        $result = [];
        foreach ($fields as $field => $value) {
            if ($command !== 'HVALS') $result[] = substr($field, 1);
            if ($command !== 'HKEYS') $result[] = $value;
        }
        return arrayReply($result);
    }
    private function setCommand(string $command, array $args): array
    {
        $storing = str_ends_with($command, 'STORE');
        if (str_starts_with($command, 'SINTER') || str_starts_with($command, 'SUNION') || str_starts_with($command, 'SDIFF')) {
            $sources = [];
            foreach (array_slice($args, $storing ? 1 : 0) as $key) $sources[] = $this->value($key, Kind::Members)?->data ?? [];
            $members = $sources[0];
            foreach (array_slice($sources, 1) as $source)
                if (str_starts_with($command, 'SINTER')) $members = array_intersect_key($members, $source);
                elseif (str_starts_with($command, 'SUNION')) $members += $source;
                else $members = array_diff_key($members, $source);
            if ($storing) {
                if ($members === []) unset($this->database[':' . $args[0]]);
                else $this->put($args[0], new Value(Kind::Members, $members));
                return integerReply(count($members));
            }
        } else {
            $key = $args[0];
            $members = $this->value($key, Kind::Members)?->data ?? [];
            if ($command === 'SADD' || $command === 'SREM') {
                $changed = 0;
                foreach (array_slice($args, 1) as $name) {
                    $member = ':' . $name;
                    if ($command === 'SADD' && !isset($members[$member])) { $members[$member] = true; $changed++; }
                    elseif ($command === 'SREM' && isset($members[$member])) { unset($members[$member]); $changed++; }
                }
                $this->update($key, Kind::Members, $members);
                return integerReply($changed);
            }
            if ($command === 'SISMEMBER') return integerReply(isset($members[':' . $args[1]]) ? 1 : 0);
            if ($command === 'SCARD') return integerReply(count($members));
        }
        $names = array_keys($members);
        sort($names, SORT_STRING);
        return arrayReply(array_map(static fn(string $name): string => substr($name, 1), $names));
    }
    private function sortedSetCommand(string $command, array $args): array
    {
        $key = $args[0];
        $numbers = [];
        $lower = $upper = null;
        $withScores = count($args) === 4 && ($command === 'ZRANGE' || $command === 'ZRANGEBYSCORE');
        if ($withScores && strtoupper($args[3]) !== 'WITHSCORES') throw new CommandError(BAD_SYNTAX);
        if ($command === 'ZADD')
            for ($i = 1; $i < count($args); $i += 2) $numbers[] = parseNumber($args[$i]);
        elseif ($command === 'ZINCRBY') $numbers[] = parseNumber($args[1]);
        elseif ($command === 'ZRANGE') { $numbers[] = parseNumber($args[1]); $numbers[] = parseNumber($args[2]); }
        elseif ($command === 'ZRANGEBYSCORE') { $lower = parseBound($args[1]); $upper = parseBound($args[2]); }
        $scores = $this->value($key, Kind::Scores)?->data ?? [];
        if ($command === 'ZADD') {
            $added = 0;
            foreach ($numbers as $i => $score) {
                $member = ':' . $args[2 * $i + 2];
                if (!isset($scores[$member])) $added++;
                $scores[$member] = $score;
            }
            $this->update($key, Kind::Scores, $scores);
            return integerReply($added);
        }
        if ($command === 'ZSCORE') {
            $score = $scores[':' . $args[1]] ?? null;
            return textReply($score === null ? null : (string)$score);
        }
        if ($command === 'ZINCRBY') {
            $member = ':' . $args[2];
            $result = checkedAdd($scores[$member] ?? 0, $numbers[0]);
            $scores[$member] = $result;
            $this->update($key, Kind::Scores, $scores);
            return textReply((string)$result);
        }
        if ($command === 'ZREM') {
            $removed = 0;
            foreach (array_slice($args, 1) as $name) {
                $member = ':' . $name;
                if (isset($scores[$member])) { unset($scores[$member]); $removed++; }
            }
            $this->update($key, Kind::Scores, $scores);
            return integerReply($removed);
        }
        if ($command === 'ZCARD') return integerReply(count($scores));
        $members = array_keys($scores);
        usort($members, static fn(string $a, string $b): int => ($scores[$a] <=> $scores[$b]) ?: strcmp($a, $b));
        if ($command === 'ZRANK') {
            $rank = array_search(':' . $args[1], $members, true);
            return $rank === false ? textReply(null) : integerReply($rank);
        }
        if ($command === 'ZRANGE') {
            [$start, $count] = normalizeRange(count($members), $numbers[0], $numbers[1]);
            $members = array_slice($members, $start, $count);
        } else $members = array_values(array_filter($members,
            static fn(string $member): bool => $lower->accepts($scores[$member], true) && $upper->accepts($scores[$member], false)));
        $result = [];
        foreach ($members as $member) {
            $result[] = substr($member, 1);
            if ($withScores) $result[] = (string)$scores[$member];
        }
        return arrayReply($result);
    }
    private function keyCommand(string $command, array $args): array
    {
        if ($command === 'DEL' || $command === 'EXISTS') {
            $count = 0;
            foreach ($args as $key)
                if ($this->entry($key) !== null) {
                    $count++;
                    if ($command === 'DEL') unset($this->database[':' . $key]);
                }
            return integerReply($count);
        }
        if ($command === 'KEYS') {
            $pattern = parsePattern($args[0]);
            $keys = [];
            foreach ($this->database as $name => $entry) {
                $key = substr($name, 1);
                if (matchesPattern($pattern, $key)) $keys[] = $key;
            }
            sort($keys, SORT_STRING);
            return arrayReply($keys);
        }
        if ($command === 'TICK') {
            $amount = parseNumber($args[0]);
            if ($amount <= 0) throw new CommandError(POSITIVE);
            $this->time += $amount;
            return integerReply($this->purge());
        }
        $key = $args[0];
        $entry = $this->entry($key);
        if ($command === 'TYPE') return [$entry?->value->kind->value ?? 'none'];
        if ($command === 'TTL') return integerReply($entry === null ? -2 : ($entry->expiry === null ? -1 : $entry->expiry - $this->time));
        if ($command === 'PERSIST') {
            if ($entry === null || $entry->expiry === null) return integerReply(0);
            $this->put($key, $entry->value);
            return integerReply(1);
        }
        if ($command === 'RENAME' || $command === 'RENAMENX') {
            if ($entry === null) throw new CommandError(NO_KEY);
            $destination = $args[1];
            if ($command === 'RENAMENX' && $this->entry($destination) !== null) return integerReply(0);
            if ($key !== $destination) {
                $this->database[':' . $destination] = $entry;
                unset($this->database[':' . $key]);
            }
            return $command === 'RENAME' ? ['OK'] : integerReply(1);
        }
        $condition = count($args) === 3 ? strtoupper($args[2]) : '';
        if (count($args) === 3 && !in_array($condition, ['NX', 'XX', 'GT', 'LT'], true))
            throw new CommandError('ERR Unsupported option ' . $args[2]);
        $seconds = parseNumber($args[1]);
        if ($entry === null) return integerReply(0);
        $expiry = $this->time + $seconds;
        $old = $entry->expiry;
        $accepted = match ($condition) {
            'NX' => $old === null,
            'XX' => $old !== null,
            'GT' => $old !== null && $expiry > $old,
            'LT' => $old === null || $expiry < $old,
            default => true,
        };
        if (!$accepted) return integerReply(0);
        if ($seconds <= 0) unset($this->database[':' . $key]);
        else $this->put($key, $entry->value, $expiry);
        return integerReply(1);
    }
    private function controlCommand(string $command, array $args): array
    {
        if ($command === 'TIME') return integerReply($this->time);
        if ($command === 'DBSIZE') return integerReply(count($this->database));
        if ($command === 'FLUSH') { $this->database = []; return ['OK']; }
        if ($command === 'INFO') {
            $counts = array_fill_keys(['string', 'list', 'hash', 'set', 'zset'], 0);
            $expires = 0;
            foreach ($this->database as $entry) {
                $counts[$entry->value->kind->value]++;
                if ($entry->expiry !== null) $expires++;
            }
            return ['keys=' . count($this->database) . ',expires=' . $expires . ',string=' . $counts['string']
                . ',list=' . $counts['list'] . ',hash=' . $counts['hash'] . ',set=' . $counts['set'] . ',zset=' . $counts['zset']
                . ',time=' . $this->time . ',depth=' . count($this->transactions) . ',snapshots=' . count($this->snapshots)];
        }
        if ($command === 'BEGIN') { $this->transactions[] = $this->database; return ['OK']; }
        if ($command === 'COMMIT' || $command === 'ROLLBACK') {
            if ($this->transactions === []) throw new CommandError('ERR no transaction');
            $saved = array_pop($this->transactions);
            if ($command === 'ROLLBACK') { $this->database = $saved; $this->purge(); }
            return ['OK'];
        }
        $name = ':' . $args[0];
        if ($command === 'SNAPSHOT') { $this->snapshots[$name] = $this->database; return ['OK']; }
        if (!isset($this->snapshots[$name])) throw new CommandError('ERR no such snapshot');
        $this->database = $this->snapshots[$name];
        $this->purge();
        return ['OK'];
    }
}

$store = new Store();
$specs = commandSpecs();
$commandCount = (int)fgets(STDIN);
for ($i = 0; $i < $commandCount; $i++) {
    $line = rtrim(fgets(STDIN), "\r\n");
    $words = splitArguments($line);
    try {
        $output = $words === null ? ['Invalid argument(s)'] : $store->execute($words, $specs);
    } catch (CommandError $error) {
        $output = ['(error) ' . $error->getMessage()];
    }
    foreach ($output as $row) echo $row, "\n";
}
