<?php
const RALLY_SPORTS = ['TENNIS', 'TABLETENNIS', 'BADMINTON', 'VOLLEYBALL'];
const OPTION_RULES = [
    'TENNIS' => ['SETS' => ['3', '5'], 'DEUCE' => ['AD', 'NOAD'], 'FINAL' => ['TB7', 'TB10', 'ADV', 'SUPER'], 'FIRST' => ['A', 'B']],
    'TABLETENNIS' => ['GAMES' => ['5', '7'], 'FIRST' => ['A', 'B']],
    'BADMINTON' => ['FIRST' => ['A', 'B']], 'VOLLEYBALL' => ['FIRST' => ['A', 'B']],
    'DARTS' => ['START' => ['501', '301', '701'], 'SETS' => ['1', '2', '3', '4', '5'], 'LEGS' => ['1', '2', '3', '4', '5'], 'FIRST' => ['A', 'B']],
    'BOWLING' => []
];

function score_error(string $message): never
{
    throw new InvalidArgumentException($message);
}

function pair(int $a = 0, int $b = 0): array
{
    return [1 => $a, 2 => $b];
}

function side(string $text): int
{
    return $text === 'A' ? 1 : 2;
}

function other(int $player): int
{
    return 3 - $player;
}

function pair_text(array $values): string
{
    return "$values[1]-$values[2]";
}

function average_text(int $value): string
{
    return sprintf('%d.%02d', intdiv($value, 100), $value % 100);
}

function checkout_tables(): array
{
    $candidates = [];
    $doubles = [];
    $darts = ['25' => [25, false], 'BULL' => [50, true], 'MISS' => [0, false]];
    foreach (['S' => 1, 'T' => 3, 'D' => 2] as $prefix => $multiplier) {
        for ($value = 20; $value >= 1; --$value) {
            $code = $prefix . $value;
            $candidates[] = [$code, $value * $multiplier];
            $darts[$code] = [$value * $multiplier, $prefix === 'D'];
            if ($prefix === 'D') {
                $doubles[] = [$code, $value * $multiplier];
            }
        }
    }
    $candidates[] = ['25', 25];
    $candidates[] = ['BULL', 50];
    $doubles[] = ['BULL', 50];
    $tables = [1 => [], 2 => [], 3 => []];
    foreach ($doubles as [$last, $value]) {
        $tables[1][$value] ??= [$last];
    }
    foreach ($candidates as [$first, $a]) {
        foreach ($doubles as [$last, $b]) {
            $tables[2][$a + $b] ??= [$first, $last];
        }
    }
    foreach ($candidates as [$first, $a]) {
        foreach ($candidates as [$second, $b]) {
            foreach ($doubles as [$last, $c]) {
                $tables[3][$a + $b + $c] ??= [$first, $second, $last];
            }
        }
    }
    return [$darts, $tables];
}
[$dartData, $checkoutData] = checkout_tables();

function checkout(int $score, int $maximum = 3): array
{
    global $checkoutData;
    for ($count = 1; $count <= $maximum; ++$count) {
        if (isset($checkoutData[$count][$score])) {
            return $checkoutData[$count][$score];
        }
    }
    return [];
}

function create_match(array $tokens): array
{
    [$id, $sport] = array_slice($tokens, 1, 2);
    $names = [1 => $tokens[3]];
    if ($sport !== 'BOWLING') {
        $names[2] = $tokens[4];
    }
    $initial = [];
    if ($sport === 'VOLLEYBALL') {
        $initial = [1 => array_map('intval', explode(',', $tokens[5])), 2 => array_map('intval', explode(',', $tokens[6]))];
        $firstOption = 7;
    } elseif ($sport === 'BOWLING') {
        $firstOption = 4;
    } else {
        $firstOption = 5;
    }
    $options = [];
    foreach (OPTION_RULES[$sport] as $key => $values) {
        $options[$key] = $values[0];
    }
    $seen = [];
    foreach (array_slice($tokens, $firstOption) as $token) {
        $parts = explode('=', $token);
        if (count($parts) !== 2) {
            score_error('invalid option');
        }
        [$key, $value] = $parts;
        if (!isset(OPTION_RULES[$sport][$key]) || !in_array($value, OPTION_RULES[$sport][$key], true) || isset($seen[$key])) {
            score_error('invalid option');
        }
        $seen[$key] = true;
        $options[$key] = $value;
    }
    $first = isset($options['FIRST']) ? side($options['FIRST']) : 1;
    $stats = [];
    foreach (['points', 'served', 'servewins', 'runmax', 'holds', 'games', 'breaks', 'opportunities', 'converted',
        'darts', 'scored', 'busts', 'high', 'tons', 'maximums', 'attempts', 'hits'] as $key) {
        $stats[$key] = pair();
    }
    $state = ['p' => pair(), 'g' => pair(), 'won' => pair(), 'server' => $first, 'winner' => 0,
        'completed' => [], 'stats' => $stats, 'last' => 0, 'run' => 0];
    if ($sport === 'VOLLEYBALL') {
        $state['lineups'] = $initial;
        $state['subs'] = pair();
        $state['timeouts'] = pair();
    } elseif ($sport === 'BOWLING') {
        $state['frames'] = array_fill(1, 10, []);
        $state['marks'] = array_fill(1, 10, []);
        $state['frame'] = 1;
        $state['standing'] = 10;
        $state['fresh'] = true;
    } elseif ($sport === 'DARTS') {
        $start = (int) $options['START'];
        $state['legs'] = pair();
        $state['remaining'] = pair($start, $start);
        $state['turn'] = [];
        $state['turnscore'] = 0;
        $state['turnstart'] = $start;
        $state['legnumber'] = 0;
    }
    return ['id' => $id, 'sport' => $sport, 'names' => $names, 'options' => $options, 'initial' => $initial, 'state' => $state, 'history' => []];
}

function tennis_mode(array $m): string
{
    $s = $m['state'];
    $final = $s['won'][1] === intdiv((int) $m['options']['SETS'], 2) && $s['won'][1] === $s['won'][2];
    if ($final && $m['options']['FINAL'] === 'SUPER') {
        return 'SUPER';
    }
    if ($s['g'] === pair(6, 6) && !($final && $m['options']['FINAL'] === 'ADV')) {
        return 'TB';
    }
    return 'NORMAL';
}

function rally_server(array $m): int
{
    $s = $m['state'];
    if ($m['sport'] === 'TENNIS') {
        if (tennis_mode($m) !== 'NORMAL' && intdiv(array_sum($s['p']) + 1, 2) % 2 === 1) {
            return other($s['server']);
        }
    } elseif ($m['sport'] === 'TABLETENNIS') {
        $first = side($m['options']['FIRST']);
        if (count($s['completed']) % 2 === 1) {
            $first = other($first);
        }
        $total = array_sum($s['p']);
        $flip = $total < 20 ? intdiv($total, 2) % 2 === 1 : $total % 2 === 1;
        return $flip ? other($first) : $first;
    }
    return $s['server'];
}

function rally_outcome(array $m, int $winner): array
{
    $s = $m['state'];
    $points = $s['p'];
    ++$points[$winner];
    $loser = other($winner);
    $game = false;
    $unit = false;
    if ($m['sport'] === 'TENNIS') {
        $mode = tennis_mode($m);
        if ($mode === 'NORMAL') {
            $game = $points[$winner] >= 4 && ($m['options']['DEUCE'] === 'NOAD' || $points[$winner] - $points[$loser] >= 2);
            $games = $s['g'][$winner] + 1;
            $unit = $game && $games >= 6 && $games - $s['g'][$loser] >= 2;
        } else {
            $final = $s['won'][1] === $s['won'][2] && $s['won'][1] === intdiv((int) $m['options']['SETS'], 2);
            $target = $mode === 'SUPER' || ($final && $m['options']['FINAL'] === 'TB10') ? 10 : 7;
            $unit = $points[$winner] >= $target && $points[$winner] - $points[$loser] >= 2;
        }
        $needed = intdiv((int) $m['options']['SETS'], 2) + 1;
    } elseif ($m['sport'] === 'TABLETENNIS') {
        $unit = $points[$winner] >= 11 && $points[$winner] - $points[$loser] >= 2;
        $needed = intdiv((int) $m['options']['GAMES'], 2) + 1;
    } elseif ($m['sport'] === 'BADMINTON') {
        $unit = $points[$winner] === 30 || ($points[$winner] >= 21 && $points[$winner] - $points[$loser] >= 2);
        $needed = 2;
    } else {
        $target = count($s['completed']) === 4 ? 15 : 25;
        $unit = $points[$winner] >= $target && $points[$winner] - $points[$loser] >= 2;
        $needed = 3;
    }
    return [$game, $unit, $unit && $s['won'][$winner] + 1 === $needed];
}

function point_event(array &$m, int $winner): void
{
    $server = rally_server($m);
    [$game, $unit, $finished] = rally_outcome($m, $winner);
    $mode = $m['sport'] === 'TENNIS' ? tennis_mode($m) : '';
    $opportunity = $mode === 'NORMAL' && rally_outcome($m, other($server))[0];
    $s = $m['state'];
    $record = [1, $winner, $server, (int) $opportunity, (int) $game, $s['p'][1], $s['p'][2], $s['g'][1], $s['g'][2],
        $s['won'][1], $s['won'][2], $s['server'], count($s['completed']), $s['last'], $s['run'], $s['stats']['runmax'][$winner], 0, 0];
    ++$s['stats']['points'][$winner];
    ++$s['stats']['served'][$server];
    if ($winner === $server) {
        ++$s['stats']['servewins'][$server];
    }
    $s['run'] = $s['last'] === $winner ? $s['run'] + 1 : 1;
    $s['last'] = $winner;
    $s['stats']['runmax'][$winner] = max($s['stats']['runmax'][$winner], $s['run']);
    if ($opportunity) {
        ++$s['stats']['opportunities'][other($server)];
        if ($winner !== $server) {
            ++$s['stats']['converted'][$winner];
        }
    }
    ++$s['p'][$winner];
    if ($m['sport'] === 'TENNIS') {
        if ($game) {
            ++$s['stats']['games'][$server];
            if ($winner === $server) {
                ++$s['stats']['holds'][$winner];
            } else {
                ++$s['stats']['breaks'][$winner];
            }
            ++$s['g'][$winner];
            $s['server'] = other($s['server']);
        } elseif ($unit) {
            $s['server'] = other($s['server']);
        }
        if ($unit) {
            if ($mode === 'SUPER') {
                $s['completed'][] = [$s['p'][1], $s['p'][2], 2, 0];
            } elseif ($mode === 'TB') {
                ++$s['g'][$winner];
                $s['completed'][] = [$s['g'][1], $s['g'][2], 1, $s['p'][other($winner)]];
            } else {
                $s['completed'][] = [$s['g'][1], $s['g'][2], 0, 0];
            }
        }
    } elseif ($m['sport'] === 'BADMINTON') {
        $s['server'] = $winner;
    } elseif ($m['sport'] === 'VOLLEYBALL' && $winner !== $server) {
        $s['server'] = $winner;
        $lineup = $s['lineups'][$winner];
        $s['lineups'][$winner] = [...array_slice($lineup, 1), $lineup[0]];
        $record[17] = 1;
    }
    if ($unit) {
        if ($m['sport'] !== 'TENNIS') {
            $s['completed'][] = [$s['p'][1], $s['p'][2], 0, 0];
        }
        ++$s['won'][$winner];
        if ($finished) {
            $s['winner'] = $winner;
        } else {
            if ($m['sport'] === 'VOLLEYBALL') {
                $record[16] = 1;
                $record = [...$record, ...$s['lineups'][1], ...$s['lineups'][2], ...array_values($s['subs']), ...array_values($s['timeouts'])];
                $s['lineups'] = $m['initial'];
                $s['subs'] = pair();
                $s['timeouts'] = pair();
                $first = side($m['options']['FIRST']);
                $s['server'] = count($s['completed']) % 2 === 0 ? $first : other($first);
            }
            $s['p'] = pair();
            $s['g'] = pair();
        }
    } elseif ($game) {
        $s['p'] = pair();
    }
    $m['state'] = $s;
    $m['history'][] = pack('l*', ...$record);
}

function roll_event(array &$s, int $pins): void
{
    if ($pins > $s['standing']) {
        score_error('too many pins');
    }
    $frame = $s['frame'];
    if ($s['fresh'] && $pins === 10) {
        $mark = 'X';
    } elseif ($pins === $s['standing']) {
        $mark = '/';
    } else {
        $mark = $pins === 0 ? '-' : (string) $pins;
    }
    $s['frames'][$frame][] = $pins;
    $s['marks'][$frame][] = $mark;
    $s['standing'] -= $pins;
    $s['fresh'] = false;
    $rolls = $s['frames'][$frame];
    if ($frame < 10) {
        if ((count($rolls) === 1 && $pins === 10) || count($rolls) === 2) {
            ++$s['frame'];
            $s['standing'] = 10;
            $s['fresh'] = true;
        }
    } else {
        $complete = count($rolls) === 3 || (count($rolls) === 2 && $rolls[0] !== 10 && array_sum($rolls) < 10);
        if ($complete) {
            $s['winner'] = 1;
        } elseif ($s['standing'] === 0) {
            $s['standing'] = 10;
            $s['fresh'] = true;
        }
    }
}

function bowling_scores(array $s): array
{
    $scores = array_fill(1, 10, null);
    for ($frame = 1; $frame <= 10; ++$frame) {
        $rolls = $s['frames'][$frame];
        if ($rolls === []) {
            continue;
        }
        $later = [];
        for ($i = $frame + 1; $i <= 10; ++$i) {
            $later = [...$later, ...$s['frames'][$i]];
        }
        if ($frame === 10) {
            if ($s['winner'] !== 0) {
                $scores[$frame] = array_sum($rolls);
            }
        } elseif ($rolls[0] === 10) {
            if (count($later) >= 2) {
                $scores[$frame] = 10 + $later[0] + $later[1];
            }
        } elseif (count($rolls) === 2) {
            if (array_sum($rolls) === 10) {
                if ($later !== []) {
                    $scores[$frame] = 10 + $later[0];
                }
            } else {
                $scores[$frame] = array_sum($rolls);
            }
        }
    }
    return $scores;
}

function complete_turn(array &$s, int $player): void
{
    $score = $s['turnscore'];
    $s['stats']['high'][$player] = max($s['stats']['high'][$player], $score);
    if ($score >= 100) {
        ++$s['stats']['tons'][$player];
    }
    if ($score === 180) {
        ++$s['stats']['maximums'][$player];
    }
}

function next_turn(array &$s): void
{
    $s['server'] = other($s['server']);
    $s['turn'] = [];
    $s['turnscore'] = 0;
    $s['turnstart'] = $s['remaining'][$s['server']];
}

function dart_event(array &$m, string $code): void
{
    global $dartData;
    if (!isset($dartData[$code])) {
        score_error('invalid dart');
    }
    $s = $m['state'];
    $player = $s['server'];
    [$value, $double] = $dartData[$code];
    $before = $s['remaining'][$player];
    ++$s['stats']['darts'][$player];
    if ($before === 50 || ($before <= 40 && $before % 2 === 0)) {
        ++$s['stats']['attempts'][$player];
    }
    $remaining = $before - $value;
    if ($remaining < 0 || $remaining === 1 || ($remaining === 0 && !$double)) {
        ++$s['stats']['busts'][$player];
        $s['stats']['scored'][$player] -= $s['turnscore'];
        $s['remaining'][$player] = $s['turnstart'];
        next_turn($s);
        $m['state'] = $s;
        return;
    }
    $s['stats']['scored'][$player] += $value;
    $s['remaining'][$player] = $remaining;
    $s['turnscore'] += $value;
    $s['turn'][] = $code;
    if ($remaining === 0) {
        ++$s['stats']['hits'][$player];
        complete_turn($s, $player);
        ++$s['legs'][$player];
        $setOver = $s['legs'][$player] === (int) $m['options']['LEGS'];
        if ($setOver) {
            $s['completed'][] = [$s['legs'][1], $s['legs'][2], 0, 0];
            ++$s['won'][$player];
        }
        if ($setOver && $s['won'][$player] === (int) $m['options']['SETS']) {
            $s['winner'] = $player;
            $m['state'] = $s;
            return;
        }
        if ($setOver) {
            $s['legs'] = pair();
        }
        ++$s['legnumber'];
        $first = side($m['options']['FIRST']);
        $s['server'] = $s['legnumber'] % 2 === 0 ? $first : other($first);
        $start = (int) $m['options']['START'];
        $s['remaining'] = pair($start, $start);
        $s['turn'] = [];
        $s['turnscore'] = 0;
        $s['turnstart'] = $start;
    } elseif (count($s['turn']) === 3) {
        complete_turn($s, $player);
        next_turn($s);
    }
    $m['state'] = $s;
}

function undo_event(array &$m): void
{
    if ($m['history'] === []) {
        score_error('nothing to undo');
    }
    $record = array_pop($m['history']);
    if (is_array($record)) {
        $m['state'] = $record;
        return;
    }
    $data = array_values(unpack('l*', $record));
    $s = $m['state'];
    if ($data[0] === 2) {
        $s['lineups'][$data[1]][$data[2]] = $data[3];
        --$s['subs'][$data[1]];
    } elseif ($data[0] === 3) {
        --$s['timeouts'][$data[1]];
    } else {
        [$winner, $server] = array_slice($data, 1, 2);
        --$s['stats']['points'][$winner];
        --$s['stats']['served'][$server];
        if ($winner === $server) {
            --$s['stats']['servewins'][$server];
        }
        if ($data[3] === 1) {
            --$s['stats']['opportunities'][other($server)];
            if ($winner !== $server) {
                --$s['stats']['converted'][$winner];
            }
        }
        if ($data[4] === 1) {
            --$s['stats']['games'][$server];
            if ($winner === $server) {
                --$s['stats']['holds'][$winner];
            } else {
                --$s['stats']['breaks'][$winner];
            }
        }
        if ($data[16] === 1) {
            $s['lineups'] = [1 => array_slice($data, 18, 6), 2 => array_slice($data, 24, 6)];
            $s['subs'] = pair($data[30], $data[31]);
            $s['timeouts'] = pair($data[32], $data[33]);
        }
        if ($data[17] === 1) {
            $lineup = $s['lineups'][$winner];
            $s['lineups'][$winner] = [$lineup[5], ...array_slice($lineup, 0, 5)];
        }
        $s['p'] = pair($data[5], $data[6]);
        $s['g'] = pair($data[7], $data[8]);
        $s['won'] = pair($data[9], $data[10]);
        $s['server'] = $data[11];
        $s['winner'] = 0;
        $s['completed'] = array_slice($s['completed'], 0, $data[12]);
        $s['last'] = $data[13];
        $s['run'] = $data[14];
        $s['stats']['runmax'][$winner] = $data[15];
    }
    $m['state'] = $s;
}

function event(array &$m, string $command, array $args): void
{
    $correct = ($command === 'POINT' && in_array($m['sport'], RALLY_SPORTS, true)) ||
        ($command === 'ROLL' && $m['sport'] === 'BOWLING') || ($command === 'THROW' && $m['sport'] === 'DARTS') ||
        (in_array($command, ['SUB', 'TIMEOUT'], true) && $m['sport'] === 'VOLLEYBALL');
    if (!$correct) {
        score_error('wrong event');
    }
    if ($command === 'POINT') {
        $events = str_split($args[0]);
    } elseif ($command === 'SUB' || $command === 'TIMEOUT') {
        $events = [''];
    } else {
        $events = $args;
    }
    foreach ($events as $value) {
        if ($m['state']['winner'] !== 0) {
            score_error('match over');
        }
        if ($command === 'POINT') {
            point_event($m, side($value));
        } elseif ($command === 'ROLL') {
            $old = $m['state'];
            $next = $old;
            roll_event($next, (int) $value);
            $m['state'] = $next;
            $m['history'][] = $old;
        } elseif ($command === 'THROW') {
            $old = $m['state'];
            dart_event($m, $value);
            $m['history'][] = $old;
        } elseif ($command === 'SUB') {
            $player = side($args[0]);
            [$outgoing, $incoming] = array_map('intval', array_slice($args, 1, 2));
            $lineup = $m['state']['lineups'][$player];
            $position = array_search($outgoing, $lineup, true);
            if ($position === false) {
                score_error('player not on court');
            }
            if (in_array($incoming, $lineup, true)) {
                score_error('player already on court');
            }
            if ($m['state']['subs'][$player] >= 6) {
                score_error('no substitutions left');
            }
            $m['history'][] = pack('l*', 2, $player, $position, $outgoing);
            $m['state']['lineups'][$player][$position] = $incoming;
            ++$m['state']['subs'][$player];
        } else {
            $player = side($args[0]);
            if ($m['state']['timeouts'][$player] >= 2) {
                score_error('no timeouts left');
            }
            $m['history'][] = pack('l*', 3, $player);
            ++$m['state']['timeouts'][$player];
        }
    }
}

function completed_text(array $record, int $winner = 1): string
{
    [$a, $b, $kind, $extra] = $record;
    if ($winner === 2) {
        [$a, $b] = [$b, $a];
    }
    $text = "$a-$b";
    if ($kind === 2) {
        return "[$text]";
    }
    return $kind === 1 ? "$text($extra)" : $text;
}

function situation(array $m, int $player): string
{
    [$game, $unit, $finished] = rally_outcome($m, $player);
    if ($finished) {
        return 'match point';
    }
    if ($unit) {
        return in_array($m['sport'], ['TENNIS', 'VOLLEYBALL'], true) ? 'set point' : 'game point';
    }
    if ($game) {
        return $player === rally_server($m) ? 'game point' : 'break point';
    }
    return '';
}

function score_line(array $m): string
{
    $s = $m['state'];
    if ($m['sport'] === 'BOWLING') {
        $parts = ["$m[id]: " . $m['names'][1]];
        $scores = bowling_scores($s);
        $cumulative = 0;
        for ($frame = 1; $frame <= 10; ++$frame) {
            if ($s['frames'][$frame] === []) {
                break;
            }
            $text = implode('', $s['marks'][$frame]);
            if ($scores[$frame] !== null) {
                $cumulative += $scores[$frame];
                $text .= "($cumulative)";
            }
            $parts[] = $text;
        }
        return implode(' ', $parts);
    }
    $names = $m['names'];
    if ($s['winner'] === 0) {
        $player = in_array($m['sport'], RALLY_SPORTS, true) ? rally_server($m) : $s['server'];
        $names[$player] .= '*';
    }
    $parts = ["$m[id]: $names[1] vs $names[2]"];
    if ($m['sport'] === 'DARTS') {
        $parts = [...$parts, 'sets', pair_text($s['won']), 'legs', pair_text($s['legs']), 'score', pair_text($s['remaining'])];
        if ($s['winner'] === 0) {
            if ($s['turn'] !== []) {
                $parts = [...$parts, 'turn', ...$s['turn']];
            }
            $answer = checkout($s['remaining'][$s['server']], 3 - count($s['turn']));
            if ($answer !== []) {
                $parts = [...$parts, 'checkout', ...$answer];
            }
        }
    } else {
        $parts = [...$parts, ...array_map('completed_text', $s['completed'])];
        if ($s['winner'] === 0) {
            if ($m['sport'] === 'TENNIS') {
                $mode = tennis_mode($m);
                if ($mode === 'SUPER') {
                    $parts[] = '[' . pair_text($s['p']) . ']';
                } else {
                    $parts[] = pair_text($s['g']);
                    if ($mode === 'TB') {
                        $parts[] = pair_text($s['p']);
                    } elseif ($m['options']['DEUCE'] === 'AD' && min($s['p']) >= 3) {
                        if ($s['p'][1] === $s['p'][2]) {
                            $parts[] = '40-40';
                        } elseif ($s['p'][1] > $s['p'][2]) {
                            $parts[] = 'AD-40';
                        } else {
                            $parts[] = '40-AD';
                        }
                    } else {
                        $labels = ['0', '15', '30', '40'];
                        $parts[] = $labels[$s['p'][1]] . '-' . $labels[$s['p'][2]];
                    }
                }
            } else {
                $parts[] = pair_text($s['p']);
                if ($m['sport'] === 'VOLLEYBALL') {
                    $parts = [...$parts, 'server', (string) $s['lineups'][$s['server']][0]];
                }
            }
            for ($player = 1; $player <= 2; ++$player) {
                $label = situation($m, $player);
                if ($label !== '') {
                    $parts[] = "($label " . $m['names'][$player] . ')';
                }
            }
        }
    }
    return implode(' ', $parts);
}

function stats_lines(array $m): array
{
    $s = $m['state'];
    $stats = $s['stats'];
    if ($m['sport'] === 'BOWLING') {
        $marks = [];
        $open = 0;
        foreach ($s['frames'] as $frame => $rolls) {
            $marks = [...$marks, ...$s['marks'][$frame]];
            if (count($rolls) >= 2 && $rolls[0] !== 10 && $rolls[0] + $rolls[1] < 10) {
                ++$open;
            }
        }
        $future = $s;
        while ($future['winner'] === 0) {
            roll_event($future, $future['standing']);
        }
        $maximum = array_sum(bowling_scores($future));
        return ["$m[id] " . $m['names'][1] . ': strikes ' . count(array_filter($marks, fn($mark) => $mark === 'X')) . ' spares ' . count(array_filter($marks, fn($mark) => $mark === '/')) . " open $open max $maximum"];
    }
    $output = [];
    for ($player = 1; $player <= 2; ++$player) {
        if ($m['sport'] === 'DARTS') {
            $darts = $stats['darts'][$player];
            $average = $darts === 0 ? 0 : intdiv($stats['scored'][$player] * 300, $darts);
            $text = "darts $darts average " . average_text($average) . ' busts ' . $stats['busts'][$player] . ' high ' . $stats['high'][$player] . ' tons ' . $stats['tons'][$player] . ' 180s ' . $stats['maximums'][$player] . ' doubles ' . $stats['hits'][$player] . '/' . $stats['attempts'][$player];
        } else {
            $text = 'points ' . $stats['points'][$player] . ' serve ' . $stats['servewins'][$player] . '/' . $stats['served'][$player] . ' run ' . $stats['runmax'][$player];
            if ($m['sport'] === 'TENNIS') {
                $text .= ' holds ' . $stats['holds'][$player] . '/' . $stats['games'][$player] . ' breaks ' . $stats['breaks'][$player] . ' break points ' . $stats['converted'][$player] . '/' . $stats['opportunities'][$player];
            } elseif ($m['sport'] === 'VOLLEYBALL') {
                $text .= ' subs ' . $s['subs'][$player] . ' timeouts ' . $s['timeouts'][$player] . ' lineup ' . implode(',', $s['lineups'][$player]);
            }
        }
        $output[] = "$m[id] " . $m['names'][$player] . ': ' . $text;
    }
    return $output;
}

function result_line(array $m): string
{
    $s = $m['state'];
    if ($s['winner'] === 0) {
        score_error('match not finished');
    }
    if ($m['sport'] === 'BOWLING') {
        return "$m[id]: " . $m['names'][1] . ' ' . array_sum(bowling_scores($s));
    }
    $winner = $s['winner'];
    return "$m[id]: " . $m['names'][$winner] . ' def. ' . $m['names'][other($winner)] . ' ' . implode(' ', array_map(fn($record) => completed_text($record, $winner), $s['completed']));
}

function execute(string $line, array &$matches): array
{
    $tokens = explode(' ', $line);
    $command = $tokens[0];
    if ($command === 'MATCH') {
        if (isset($matches[$tokens[1]])) {
            score_error('duplicate match');
        }
        $m = create_match($tokens);
        $matches[$m['id']] = $m;
        return [];
    }
    if ($command === 'CHECKOUT') {
        $answer = checkout((int) $tokens[1]);
        return ["checkout $tokens[1]: " . ($answer === [] ? 'none' : implode(' ', $answer))];
    }
    if ($command === 'STANDINGS') {
        $totals = [];
        foreach ($matches as $m) {
            if ($m['sport'] !== 'BOWLING' && $m['state']['winner'] !== 0) {
                for ($player = 1; $player <= 2; ++$player) {
                    $name = $m['names'][$player];
                    $totals[$name] ??= [0, 0];
                    ++$totals[$name][$player === $m['state']['winner'] ? 0 : 1];
                }
            }
        }
        $names = array_keys($totals);
        usort($names, fn($a, $b) => [-$totals[$a][0], $totals[$a][1], $a] <=> [-$totals[$b][0], $totals[$b][1], $b]);
        return ['standings: ' . ($names === [] ? 'none' : implode(', ', array_map(fn($name) => "$name " . $totals[$name][0] . '-' . $totals[$name][1], $names)))];
    }
    if (!isset($matches[$tokens[1]])) {
        score_error('unknown match');
    }
    $id = $tokens[1];
    if (in_array($command, ['POINT', 'ROLL', 'THROW', 'SUB', 'TIMEOUT'], true)) {
        event($matches[$id], $command, array_slice($tokens, 2));
    } elseif ($command === 'UNDO') {
        undo_event($matches[$id]);
    } elseif ($command === 'SCORE') {
        return [score_line($matches[$id])];
    } elseif ($command === 'STATS') {
        return stats_lines($matches[$id]);
    } elseif ($command === 'RESULT') {
        return [result_line($matches[$id])];
    }
    return [];
}

$matches = [];
$count = (int) fgets(STDIN);
for ($i = 0; $i < $count; ++$i) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try {
        foreach (execute($line, $matches) as $output) {
            echo $output, "\n";
        }
    } catch (InvalidArgumentException $exception) {
        echo 'ERROR ', $exception->getMessage(), "\n";
    }
}
