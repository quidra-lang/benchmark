<?php

require_once __DIR__ . '/board.php';
require_once __DIR__ . '/dictionary_trie.php';
require_once __DIR__ . '/scoring.php';
require_once __DIR__ . '/move_generator.php';
require_once __DIR__ . '/game.php';

const STRATEGIES = ['score', 'tiles', 'equity'];
const VOWELS = 'AEIOU';

function sortedTiles($tiles)
{
    $letters = str_split($tiles);
    sort($letters, SORT_STRING);
    return implode('', $letters);
}

function collection($tiles)
{
    $result = sortedTiles($tiles);
    return $result === '' ? '-' : $result;
}

function nameValid($name)
{
    return (bool)preg_match('/^[a-z0-9_]{1,20}$/D', $name);
}

function rackValid($rack)
{
    return (bool)preg_match('/^[A-Z?]{1,7}$/D', $rack);
}

function numberValid($text, $low, $high)
{
    return (bool)preg_match('/^(0|[1-9][0-9]*)$/D', $text) && (int)$text >= $low && (int)$text <= $high;
}

function notation($move)
{
    return position($move['row'], $move['column'], $move['direction']) . ' ' . $move['word'];
}

function wordList($move)
{
    return implode(',', array_map(fn($word) => $word['word'] . ':' . $word['score'], $move['words']));
}

function frequencies($tiles)
{
    return array_count_values(is_array($tiles) ? $tiles : str_split($tiles));
}

function readInput()
{
    $table = [];
    foreach (file('input/tiles.txt', FILE_IGNORE_NEW_LINES) as $line) {
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        [$letter, $value, $count, $weight] = explode(' ', $line);
        $table[$letter] = ['value' => (int)$value, 'count' => (int)$count, 'weight' => (int)$weight];
    }
    $trie = new Trie();
    $stats = ['lines' => 0, 'skipped' => 0, 'duplicates' => 0, 'lengths' => []];
    foreach (file('input/dictionary.txt', FILE_IGNORE_NEW_LINES) as $line) {
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        $stats['lines']++;
        if (!preg_match('/^[A-Z]{2,15}$/D', $line)) {
            $stats['skipped']++;
        } elseif (!$trie->add($line)) {
            $stats['duplicates']++;
        } else {
            $length = strlen($line);
            $stats['lengths'][$length] = ($stats['lengths'][$length] ?? 0) + 1;
        }
    }
    $lines = file('input/jobs.txt', FILE_IGNORE_NEW_LINES);
    $jobs = [];
    for ($i = 0; $i < count($lines); $i++) {
        if ($lines[$i] === '' || $lines[$i][0] === '#') {
            continue;
        }
        $fields = explode(' ', $lines[$i]);
        $kind = array_shift($fields);
        $name = array_shift($fields);
        $body = [];
        while ($lines[++$i] !== 'END') {
            $body[] = $lines[$i];
        }
        $jobs[] = ['kind' => $kind, 'name' => $name, 'args' => $fields, 'body' => $body];
    }
    return [$table, $trie, $stats, $jobs];
}

function usedTiles($grid, $rack)
{
    $tiles = '';
    foreach (boardTiles($grid) as $tile) {
        $tiles .= tileKind($tile['letter']);
    }
    return frequencies($tiles . $rack);
}

function tileCountError($grid, $rack, $table)
{
    $used = usedTiles($grid, $rack);
    foreach ($table as $letter => $tile) {
        if (($used[$letter] ?? 0) > $tile['count']) {
            return 'too many ' . $letter;
        }
    }
    return null;
}

function unseenTiles($grid, $rack, $table)
{
    $used = usedTiles($grid, $rack);
    $unseen = '';
    foreach ($table as $letter => $tile) {
        $unseen .= str_repeat($letter, $tile['count'] - ($used[$letter] ?? 0));
    }
    return $unseen;
}

function checkBoard($lines, $rack, $table, $trie)
{
    if (count($lines) !== BOARD_SIZE) {
        return ['error' => 'board rows ' . count($lines)];
    }
    foreach ($lines as $i => $line) {
        if (!preg_match('/^[.A-Za-z]{15}$/D', $line)) {
            return ['error' => 'bad board row ' . ($i + 1)];
        }
    }
    $grid = array_map('str_split', $lines);
    $countError = tileCountError($grid, $rack, $table);
    if ($countError !== null) {
        return ['error' => $countError];
    }
    if (boardTiles($grid) && $grid[CENTER][CENTER] === '.') {
        return ['error' => 'center empty'];
    }
    if (!connected($grid)) {
        return ['error' => 'disconnected'];
    }
    foreach (boardWords($grid) as $word) {
        if (!$trie->has(strtoupper($word['word']))) {
            return ['error' => 'unknown word ' . $word['word'] . ' at ' . position($word['row'], $word['column'], $word['direction'])];
        }
    }
    return ['grid' => $grid];
}

function checkJob($job, $duplicate, $table, $trie)
{
    if (!nameValid($job['name'])) {
        return ['error' => 'bad name'];
    }
    if ($duplicate) {
        return ['error' => 'duplicate name'];
    }
    if ($job['kind'] === 'TOPN') {
        if (!numberValid($job['args'][0], 1, 99)) {
            return ['error' => 'bad count'];
        }
        if (!in_array($job['args'][1], STRATEGIES, true)) {
            return ['error' => 'bad order'];
        }
        $rack = explode(' ', $job['body'][0])[1];
        if (!rackValid($rack)) {
            return ['error' => 'bad rack'];
        }
        return array_merge(checkBoard(array_slice($job['body'], 2), $rack, $table, $trie),
            ['rack' => $rack, 'count' => (int)$job['args'][0], 'strategy' => $job['args'][1]]);
    }
    if ($job['kind'] === 'VALIDATE') {
        $at = 1;
        while ($at < count($job['body']) && !str_starts_with($job['body'][$at], 'MOVE')) {
            $at++;
        }
        return array_merge(checkBoard(array_slice($job['body'], 1, $at - 1), '', $table, $trie), ['records' => array_slice($job['body'], $at)]);
    }
    if (!numberValid($job['args'][0], 1, 2147483646)) {
        return ['error' => 'bad seed'];
    }
    if (count($job['body']) < 2 || count($job['body']) > 4) {
        return ['error' => 'bad player count ' . count($job['body'])];
    }
    $players = $names = [];
    foreach ($job['body'] as $i => $line) {
        $fields = explode(' ', $line);
        $name = $fields[1];
        $strategy = $fields[2];
        $threshold = $fields[3] ?? null;
        if (!nameValid($name) || !in_array($strategy, STRATEGIES, true) ||
            ($job['kind'] === 'GAME' && !numberValid($threshold, 0, 99))) {
            return ['error' => 'bad player ' . ($i + 1)];
        }
        if (isset($names[$name])) {
            return ['error' => 'duplicate player ' . ($i + 1)];
        }
        $names[$name] = true;
        $players[] = ['name' => $name, 'strategy' => $strategy, 'threshold' => $job['kind'] === 'GAME' ? (int)$threshold : 0, 'index' => $i];
    }
    return ['players' => $players, 'seed' => (int)$job['args'][0]];
}

function leaveValue($tiles, $table)
{
    $counts = frequencies($tiles);
    $value = $duplicates = $vowels = $consonants = 0;
    foreach (str_split($tiles) as $tile) {
        $value += $table[$tile]['weight'];
        if (str_contains(VOWELS, $tile)) {
            $vowels++;
        } elseif ($tile !== '?') {
            $consonants++;
        }
    }
    foreach ($counts as $tile => $count) {
        if ($tile !== '?') {
            $duplicates += $count - 1;
        }
    }
    return $value - 4 * $duplicates - 3 * max(0, abs($vowels - $consonants) - 1);
}

function bestLeave($rack, $table)
{
    $counts = frequencies($rack);
    $letters = array_keys($counts);
    sort($letters, SORT_STRING);
    $best = ['tiles' => '', 'value' => 0];
    $visit = function ($index, $tiles) use (&$visit, $rack, $table, $counts, $letters, &$best) {
        if (strlen($tiles) >= strlen($rack)) {
            return;
        }
        if ($index === count($letters)) {
            $value = leaveValue($tiles, $table);
            if ($value > $best['value'] || ($value === $best['value'] && (strlen($tiles) > strlen($best['tiles']) ||
                (strlen($tiles) === strlen($best['tiles']) && strcmp($tiles, $best['tiles']) < 0)))) {
                $best = ['tiles' => $tiles, 'value' => $value];
            }
            return;
        }
        $letter = $letters[$index];
        for ($count = 0; $count <= $counts[$letter]; $count++) {
            $visit($index + 1, $tiles . str_repeat($letter, $count));
        }
    };
    $visit(0, '');
    return $best;
}

function removeTiles($rack, $used)
{
    foreach ($used as $tile) {
        $index = strpos($rack, $tile);
        $rack = substr_replace($rack, '', $index, 1);
    }
    return $rack;
}

function standardOrder($a, $b)
{
    return ($b['score'] <=> $a['score']) ?: (($a['row'] <=> $b['row']) ?: (($a['column'] <=> $b['column']) ?:
        (($a['direction'] === $b['direction'] ? 0 : ($a['direction'] === 'across' ? -1 : 1)) ?: strcmp($a['word'], $b['word']))));
}

function strategyOrder($moves, $strategy)
{
    usort($moves, function ($a, $b) use ($strategy) {
        $order = $strategy === 'tiles' ? count($b['tiles']) - count($a['tiles']) :
            ($strategy === 'equity' ? ($b['score'] + $b['leaveValue']) - ($a['score'] + $a['leaveValue']) : 0);
        return $order ?: standardOrder($a, $b);
    });
    return $moves;
}

function legalMoves($grid, $rack, $trie, $table)
{
    $generated = generateMoves($grid, $rack, $trie);
    $moves = [];
    foreach ($generated['moves'] as $move) {
        $result = scoreMove($grid, $move, $table);
        $used = array_map(fn($tile) => tileKind($tile['letter']), $result['tiles']);
        $result['leave'] = removeTiles($rack, $used);
        $result['leaveValue'] = leaveValue($result['leave'], $table);
        $moves[] = $result;
    }
    usort($moves, 'standardOrder');
    foreach ($moves as $i => &$move) {
        $move['rank'] = $i + 1;
    }
    unset($move);
    $generated['moves'] = $moves;
    return $generated;
}

function place(&$grid, $move)
{
    foreach ($move['tiles'] as $tile) {
        $grid[$tile['row']][$tile['column']] = $tile['letter'];
    }
}

function placementKey($move)
{
    $tiles = $move['tiles'];
    usort($tiles, fn($a, $b) => ($a['row'] <=> $b['row']) ?: ($a['column'] <=> $b['column']));
    return implode(',', array_map(fn($tile) => ($tile['row'] * BOARD_SIZE + $tile['column']) . ':' . $tile['letter'], $tiles));
}

function positionSummary($grid)
{
    $tiles = boardTiles($grid);
    $words = boardWords($grid);
    $longest = '-';
    foreach ($words as $word) {
        if ($longest === '-' || strlen($word['word']) > strlen($longest)) {
            $longest = $word['word'];
        }
    }
    $blanks = 0;
    $premiums = ['#' => 0, '*' => 0, '^' => 0, '+' => 0];
    foreach ($tiles as $tile) {
        if (tileKind($tile['letter']) === '?') {
            $blanks++;
        }
        $symbol = premium($tile['row'], $tile['column']);
        if (isset($premiums[$symbol])) {
            $premiums[$symbol]++;
        }
    }
    return 'position tiles=' . count($tiles) . ' words=' . count($words) . ' longest=' . $longest . ' blanks=' . $blanks .
        ' premiums=TW:' . $premiums['#'] . ',DW:' . $premiums['*'] . ',TL:' . $premiums['^'] . ',DL:' . $premiums['+'];
}

function topJob($job, $settings, $trie, $table)
{
    $grid = $settings['grid'];
    $rack = $settings['rack'];
    $generated = legalMoves($grid, $rack, $trie, $table);
    $moves = $generated['moves'];
    $unseen = unseenTiles($grid, $rack, $table);
    $vowels = $consonants = $blanks = 0;
    foreach (str_split($rack) as $tile) {
        if (str_contains(VOWELS, $tile)) {
            $vowels++;
        } elseif ($tile === '?') {
            $blanks++;
        } else {
            $consonants++;
        }
    }
    $across = $bingos = $withBlank = 0;
    $bestByTiles = array_fill(0, 8, null);
    foreach ($moves as $move) {
        if ($move['direction'] === 'across') {
            $across++;
        }
        $size = count($move['tiles']);
        if ($size === RACK_SIZE) {
            $bingos++;
        }
        foreach ($move['tiles'] as $tile) {
            if (tileKind($tile['letter']) === '?') {
                $withBlank++;
                break;
            }
        }
        if ($bestByTiles[$size] === null || $move['score'] > $bestByTiles[$size]) {
            $bestByTiles[$size] = $move['score'];
        }
    }
    $keep = bestLeave($rack, $table);
    $anagrams = $trie->anagrams($rack);
    usort($anagrams, fn($a, $b) => (strlen($b) <=> strlen($a)) ?: strcmp($a, $b));
    $bestFields = [];
    for ($i = 1; $i <= RACK_SIZE; $i++) {
        $bestFields[] = $i . '=' . ($bestByTiles[$i] ?? '-');
    }
    $lines = [
        'TOPN ' . $job['name'] . ' n=' . $settings['count'] . ' order=' . $settings['strategy'] . ' rack=' . collection($rack),
        'board tiles=' . count(boardTiles($grid)) . ' anchors=' . $generated['anchors'],
        'unseen count=' . strlen($unseen) . ' tiles=' . collection($unseen),
        'rack vowels=' . $vowels . ' consonants=' . $consonants . ' blanks=' . $blanks . ' value=' . tileValue($rack, $table),
        'checks across=' . implode(',', $generated['across']) . ' down=' . implode(',', $generated['down']),
        'moves total=' . count($moves) . ' across=' . $across . ' down=' . (count($moves) - $across) . ' bingos=' . $bingos . ' blanks=' . $withBlank,
        'best_by_tiles ' . implode(' ', $bestFields),
        'exchange keep=' . collection($keep['tiles']) . ' value=' . $keep['value'],
        'anagrams total=' . count($anagrams) . ' top=' . ($anagrams ? implode(',', array_slice($anagrams, 0, 10)) : '-')
    ];
    foreach (boardWords($grid) as $word) {
        if (strlen($word['word']) < 3) {
            continue;
        }
        $upper = strtoupper($word['word']);
        $front = $back = '';
        foreach (str_split(ALPHABET) as $letter) {
            if ($trie->has($letter . $upper)) {
                $front .= $letter;
            }
            if ($trie->has($upper . $letter)) {
                $back .= $letter;
            }
        }
        if ($front !== '' || $back !== '') {
            $lines[] = 'hook ' . position($word['row'], $word['column'], $word['direction']) . ' ' . $word['word'] .
                ' front=' . ($front === '' ? '-' : $front) . ' back=' . ($back === '' ? '-' : $back);
        }
    }
    $shown = array_slice(strategyOrder($moves, $settings['strategy']), 0, $settings['count']);
    $endgame = strlen($unseen) >= 1 && strlen($unseen) <= 7 && count($shown) > 0;
    if ($endgame) {
        $best = 0;
        foreach ($shown as $i => $move) {
            $after = $grid;
            place($after, $move);
            $replies = legalMoves($after, $unseen, $trie, $table)['moves'];
            $shown[$i]['net'] = $move['score'] - ($replies ? $replies[0]['score'] : 0);
            if ($shown[$i]['net'] > $shown[$best]['net']) {
                $best = $i;
            }
        }
        $lines[] = 'endgame opponent=' . collection($unseen) . ' best=' . ($best + 1) . ' net=' . $shown[$best]['net'];
    }
    foreach ($shown as $i => $move) {
        $lines[] = ($i + 1) . ' ' . notation($move) . ' score=' . $move['score'] . ' tiles=' . count($move['tiles']) .
            ' leave=' . collection($move['leave']) . ' value=' . $move['leaveValue'] .
            ($endgame ? ' net=' . $move['net'] : '') . ' words=' . wordList($move);
    }
    return ['lines' => $lines, 'moves' => count($moves), 'bingos' => $bingos];
}

function checkRecord($grid, $fields, $trie, $table)
{
    $player = $fields[1];
    $rack = $fields[2];
    $action = array_slice($fields, 3);
    if (!nameValid($player)) {
        return ['error' => 'bad player'];
    }
    if (!rackValid($rack)) {
        return ['error' => 'bad rack'];
    }
    $countError = tileCountError($grid, $rack, $table);
    if ($countError !== null) {
        return ['error' => $countError];
    }
    if (count($action) === 1 && $action[0] === 'PASS') {
        return ['kind' => 'pass'];
    }
    if ($action[0] === 'EXCHANGE') {
        if (!rackValid($action[1])) {
            return ['error' => 'bad exchange'];
        }
        $returned = frequencies($action[1]);
        $available = frequencies($rack);
        foreach (str_split($action[1]) as $tile) {
            if ($returned[$tile] > ($available[$tile] ?? 0)) {
                return ['error' => 'rack lacks ' . $tile];
            }
        }
        return ['kind' => 'exchange'];
    }
    $move = parsePosition($action[0]);
    if ($move === null) {
        return ['error' => 'bad position'];
    }
    if (!preg_match('/^[A-Za-z]{2,15}$/D', $action[1])) {
        return ['error' => 'bad word'];
    }
    $move['word'] = $action[1];
    $squares = moveSquares($move);
    foreach ($squares as $tile) {
        if (!inside($tile['row'], $tile['column'])) {
            return ['error' => 'off board'];
        }
    }
    foreach ($squares as $tile) {
        if (occupied($grid, $tile['row'], $tile['column']) && $grid[$tile['row']][$tile['column']] !== $tile['letter']) {
            return ['error' => 'mismatch at ' . squareName($tile['row'], $tile['column'])];
        }
    }
    $dr = $move['direction'] === 'down' ? 1 : 0;
    $dc = $move['direction'] === 'across' ? 1 : 0;
    if (occupied($grid, $move['row'] - $dr, $move['column'] - $dc) ||
        occupied($grid, $move['row'] + $dr * strlen($move['word']), $move['column'] + $dc * strlen($move['word']))) {
        return ['error' => 'not whole word'];
    }
    $newTiles = array_values(array_filter($squares, fn($tile) => !occupied($grid, $tile['row'], $tile['column'])));
    if (!$newTiles) {
        return ['error' => 'no new tiles'];
    }
    $available = frequencies($rack);
    foreach ($newTiles as $tile) {
        $letter = tileKind($tile['letter']);
        if (($available[$letter] ?? 0) === 0) {
            return ['error' => 'rack lacks ' . $letter];
        }
        $available[$letter]--;
    }
    if (!boardTiles($grid)) {
        $covered = false;
        foreach ($newTiles as $tile) {
            if ($tile['row'] === CENTER && $tile['column'] === CENTER) {
                $covered = true;
                break;
            }
        }
        if (!$covered) {
            return ['error' => 'center not covered'];
        }
    } else {
        $touches = false;
        foreach ($newTiles as $tile) {
            if (adjacent($grid, $tile['row'], $tile['column'])) {
                $touches = true;
                break;
            }
        }
        if (!$touches) {
            return ['error' => 'not connected'];
        }
    }
    $result = scoreMove($grid, $move, $table);
    foreach ($result['words'] as $word) {
        if (!$trie->has(strtoupper($word['word']))) {
            return ['error' => 'unknown word ' . $word['word'] . ' at ' . position($word['row'], $word['column'], $word['direction'])];
        }
    }
    return ['kind' => 'play', 'move' => $result];
}

function validationJob($job, $settings, $trie, $table)
{
    $grid = $settings['grid'];
    $players = [];
    $total = ['valid' => 0, 'invalid' => 0, 'score' => 0, 'best' => 0, 'loss' => 0];
    $lines = ['VALIDATE ' . $job['name']];
    foreach ($settings['records'] as $i => $record) {
        $fields = explode(' ', $record);
        $name = $fields[1];
        $rack = $fields[2];
        $prefix = 'move ' . ($i + 1) . ' ' . $name . ' ' . implode(' ', array_slice($fields, 3));
        $checked = checkRecord($grid, $fields, $trie, $table);
        if (($checked['error'] ?? null) !== 'bad player') {
            if (!isset($players[$name])) {
                $players[$name] = ['moves' => 0, 'valid' => 0, 'score' => 0, 'loss' => 0];
            }
            $players[$name]['moves']++;
        }
        if (isset($checked['error'])) {
            $total['invalid']++;
            $lines[] = $prefix . ' invalid ' . $checked['error'];
            continue;
        }
        $moves = legalMoves($grid, $rack, $trie, $table)['moves'];
        $best = $moves ? $moves[0]['score'] : 0;
        $score = $checked['kind'] === 'play' ? $checked['move']['score'] : 0;
        $loss = $best - $score;
        $players[$name]['valid']++;
        $players[$name]['score'] += $score;
        $players[$name]['loss'] += $loss;
        $total['valid']++;
        $total['score'] += $score;
        $total['best'] += $best;
        $total['loss'] += $loss;
        if ($checked['kind'] === 'play') {
            $key = placementKey($checked['move']);
            foreach ($moves as $move) {
                if (placementKey($move) === $key) {
                    $equivalent = $move;
                    break;
                }
            }
            $lines[] = $prefix . ' score=' . $score . ' total=' . $players[$name]['score'] . ' tiles=' . count($checked['move']['tiles']) .
                ' rank=' . $equivalent['rank'] . '/' . count($moves) . ' best=' . $best . ' words=' . wordList($checked['move']);
            place($grid, $checked['move']);
        } else {
            $lines[] = $prefix . ' score=0 total=' . $players[$name]['score'] . ' moves=' . count($moves) . ' best=' . $best;
        }
    }
    foreach ($players as $name => $player) {
        $lines[] = 'player ' . $name . ' moves=' . $player['moves'] . ' valid=' . $player['valid'] . ' score=' . $player['score'] . ' loss=' . $player['loss'];
    }
    $lines[] = 'total valid=' . $total['valid'] . ' invalid=' . $total['invalid'] . ' score=' . $total['score'] . ' best=' . $total['best'] . ' loss=' . $total['loss'];
    $lines[] = positionSummary($grid);
    array_push($lines, ...displayBoard($grid));
    return array_merge(['lines' => $lines, 'moves' => count($settings['records'])], $total);
}

function gameJob($job, $settings, $trie, $table)
{
    $random = new Minstd($settings['seed']);
    $bag = makeBag($table, $random);
    $grid = emptyBoard();
    $players = [];
    foreach ($settings['players'] as $config) {
        $player = (object)$config;
        $player->rack = draw($bag, RACK_SIZE);
        $player->score = $player->plays = $player->bingos = $player->exchanges = $player->passes = $player->top = $player->loss = 0;
        $players[] = $player;
    }
    $lines = ['GAME ' . $job['name'] . ' seed=' . $settings['seed'] . ' players=' . count($players)];
    foreach ($players as $i => $player) {
        $lines[] = 'player ' . ($i + 1) . ' ' . $player->name . ' strategy=' . $player->strategy . ' threshold=' . $player->threshold;
    }
    $turns = $scoreless = 0;
    $reason = $wentOut = $highlight = null;
    while ($reason === null) {
        $player = $players[$turns % count($players)];
        $turns++;
        $moves = legalMoves($grid, $player->rack, $trie, $table)['moves'];
        $ordered = strategyOrder($moves, $player->strategy);
        $candidate = $ordered[0] ?? null;
        $prefix = 'turn ' . $turns . ' ' . $player->name . ' rack=' . collection($player->rack) . ' moves=' . count($moves);
        if ($candidate !== null && !($candidate['score'] < $player->threshold && count($bag) >= RACK_SIZE)) {
            place($grid, $candidate);
            $player->score += $candidate['score'];
            $player->plays++;
            if (count($candidate['tiles']) === RACK_SIZE) {
                $player->bingos++;
            }
            $player->top = max($player->top, $candidate['score']);
            $player->loss += $moves[0]['score'] - $candidate['score'];
            $player->rack = $candidate['leave'];
            $drawn = draw($bag, RACK_SIZE - strlen($player->rack));
            $player->rack .= $drawn;
            $scoreless = 0;
            $lines[] = $prefix . ' best=' . $moves[0]['score'] . ' play ' . notation($candidate) . ' score=' . $candidate['score'] .
                ' total=' . $player->score . ' draw=' . collection($drawn) . ' bag=' . count($bag);
            if ($highlight === null || $candidate['score'] > $highlight['move']['score']) {
                $highlight = ['turn' => $turns, 'player' => $player->name, 'move' => $candidate];
            }
            if ($player->rack === '' && !$bag) {
                $reason = 'out';
                $wentOut = $player;
            }
        } elseif (count($bag) >= RACK_SIZE) {
            $keep = bestLeave($player->rack, $table)['tiles'];
            $returned = removeTiles($player->rack, str_split($keep));
            $drawn = exchange($bag, $returned, $random);
            $player->rack = $keep . $drawn;
            $player->exchanges++;
            $scoreless++;
            $lines[] = $prefix . ' exchange keep=' . collection($keep) . ' draw=' . collection($drawn) . ' bag=' . count($bag);
        } else {
            $player->passes++;
            $scoreless++;
            $lines[] = $prefix . ' pass bag=' . count($bag);
        }
        if ($reason === null && $scoreless === 6) {
            $reason = 'scoreless';
        }
    }
    $lines[] = $reason === 'out' ? 'end reason=out player=' . $wentOut->name . ' turns=' . $turns : 'end reason=scoreless turns=' . $turns;
    $transferred = 0;
    foreach ($players as $player) {
        $player->adjustment = -tileValue($player->rack, $table);
        if ($player !== $wentOut) {
            $transferred -= $player->adjustment;
        }
    }
    if ($wentOut !== null) {
        $wentOut->adjustment = $transferred;
    }
    foreach ($players as $player) {
        $player->total = $player->score + $player->adjustment;
        $adjustment = $player->adjustment > 0 ? '+' . $player->adjustment : (string)$player->adjustment;
        $lines[] = 'final ' . $player->name . ' score=' . $player->score . ' rack=' . collection($player->rack) .
            ' adjust=' . $adjustment . ' total=' . $player->total;
    }
    $standings = $players;
    usort($standings, fn($a, $b) => ($b->total <=> $a->total) ?: ($a->index <=> $b->index));
    foreach ($standings as $i => $player) {
        $lines[] = 'standing ' . ($i + 1) . ' ' . $player->name . ' total=' . $player->total . ' plays=' . $player->plays .
            ' bingos=' . $player->bingos . ' exchanges=' . $player->exchanges . ' passes=' . $player->passes .
            ' top=' . $player->top . ' loss=' . $player->loss;
    }
    $winners = [];
    foreach ($players as $player) {
        if ($player->total === $standings[0]->total) {
            $winners[] = $player->name;
        }
    }
    $lines[] = 'winner ' . implode(',', $winners);
    if ($highlight !== null) {
        $lines[] = 'highlight turn=' . $highlight['turn'] . ' player=' . $highlight['player'] . ' play ' . notation($highlight['move']) . ' score=' . $highlight['move']['score'];
    }
    $lines[] = positionSummary($grid);
    array_push($lines, ...displayBoard($grid));
    $totals = ['lines' => $lines, 'turns' => $turns, 'plays' => 0, 'exchanges' => 0, 'passes' => 0, 'bingos' => 0];
    foreach ($players as $player) {
        foreach (['plays', 'exchanges', 'passes', 'bingos'] as $key) {
            $totals[$key] += $player->$key;
        }
    }
    return $totals;
}

function duplicateJob($job, $settings, $trie, $table)
{
    $random = new Minstd($settings['seed']);
    $bag = makeBag($table, $random);
    $grid = emptyBoard();
    $players = [];
    foreach ($settings['players'] as $config) {
        $player = (object)$config;
        $player->total = 0;
        $players[] = $player;
    }
    $rack = draw($bag, RACK_SIZE);
    $masterTotal = $rounds = 0;
    $lines = ['DUPLICATE ' . $job['name'] . ' seed=' . $settings['seed'] . ' players=' . count($players)];
    foreach ($players as $i => $player) {
        $lines[] = 'player ' . ($i + 1) . ' ' . $player->name . ' strategy=' . $player->strategy;
    }
    while (true) {
        $moves = legalMoves($grid, $rack, $trie, $table)['moves'];
        if (!$moves) {
            $reason = 'stuck';
            break;
        }
        $rounds++;
        $master = $moves[0];
        $picks = [];
        foreach ($players as $player) {
            $chosen = strategyOrder($moves, $player->strategy)[0];
            $player->total += $chosen['score'];
            $picks[] = $chosen['score'];
        }
        $masterTotal += $master['score'];
        $lines[] = 'round ' . $rounds . ' rack=' . collection($rack) . ' moves=' . count($moves) . ' master ' . notation($master) .
            ' score=' . $master['score'] . ' picks=' . implode(',', $picks);
        place($grid, $master);
        $rack = $master['leave'];
        $rack .= draw($bag, RACK_SIZE - strlen($rack));
        if ($rack === '') {
            $reason = 'out';
            break;
        }
    }
    $lines[] = $reason === 'out' ? 'end reason=out rounds=' . $rounds : 'end reason=stuck rounds=' . $rounds . ' rack=' . collection($rack);
    $lines[] = 'master total=' . $masterTotal;
    $maximum = null;
    foreach ($players as $player) {
        $percent = $masterTotal > 0 ? intdiv(100 * $player->total, $masterTotal) : 0;
        $lines[] = 'final ' . $player->name . ' total=' . $player->total . ' percent=' . $percent;
        $maximum = $maximum === null ? $player->total : max($maximum, $player->total);
    }
    $winners = [];
    foreach ($players as $player) {
        if ($player->total === $maximum) {
            $winners[] = $player->name;
        }
    }
    $lines[] = 'winner ' . implode(',', $winners);
    $lines[] = positionSummary($grid);
    array_push($lines, ...displayBoard($grid));
    return ['lines' => $lines, 'rounds' => $rounds];
}

function writeParagraphs($name, $paragraphs)
{
    $contents = array_map(fn($lines) => implode("\n", $lines), $paragraphs);
    file_put_contents('output/' . $name, implode("\n\n", $contents) . "\n");
}

function main()
{
    [$table, $trie, $stats, $jobs] = readInput();
    $lengths = $stats['lengths'];
    ksort($lengths, SORT_NUMERIC);
    $fields = [];
    foreach ($lengths as $length => $count) {
        $fields[] = $length . '=' . $count;
    }
    $moves = [['DICTIONARY lines=' . $stats['lines'] . ' words=' . $trie->words . ' skipped=' . $stats['skipped'] .
        ' duplicates=' . $stats['duplicates'] . ' nodes=' . $trie->nodes, 'lengths ' . implode(' ', $fields)]];
    $validation = $games = [];
    $topTotal = ['jobs' => 0, 'errors' => 0, 'moves' => 0, 'bingos' => 0];
    $validationTotal = ['jobs' => 0, 'errors' => 0, 'moves' => 0, 'valid' => 0, 'invalid' => 0, 'loss' => 0];
    $gameTotal = ['games' => 0, 'duplicates' => 0, 'errors' => 0, 'turns' => 0, 'rounds' => 0, 'plays' => 0, 'exchanges' => 0, 'passes' => 0, 'bingos' => 0];
    $seen = [];
    foreach ($jobs as $job) {
        $duplicate = isset($seen[$job['name']]);
        $seen[$job['name']] = true;
        $settings = checkJob($job, $duplicate, $table, $trie);
        if ($job['kind'] === 'GAME') {
            $gameTotal['games']++;
        } elseif ($job['kind'] === 'DUPLICATE') {
            $gameTotal['duplicates']++;
        } elseif ($job['kind'] === 'TOPN') {
            $topTotal['jobs']++;
        } else {
            $validationTotal['jobs']++;
        }
        if (isset($settings['error'])) {
            $paragraph = [$job['kind'] . ' ' . $job['name'], 'error ' . $settings['error']];
            if ($job['kind'] === 'TOPN') {
                $topTotal['errors']++;
                $moves[] = $paragraph;
            } elseif ($job['kind'] === 'VALIDATE') {
                $validationTotal['errors']++;
                $validation[] = $paragraph;
            } else {
                $gameTotal['errors']++;
                $games[] = $paragraph;
            }
            continue;
        }
        if ($job['kind'] === 'TOPN') {
            $result = topJob($job, $settings, $trie, $table);
            $moves[] = $result['lines'];
            $topTotal['moves'] += $result['moves'];
            $topTotal['bingos'] += $result['bingos'];
        } elseif ($job['kind'] === 'VALIDATE') {
            $result = validationJob($job, $settings, $trie, $table);
            $validation[] = $result['lines'];
            foreach (['moves', 'valid', 'invalid', 'loss'] as $key) {
                $validationTotal[$key] += $result[$key];
            }
        } elseif ($job['kind'] === 'GAME') {
            $result = gameJob($job, $settings, $trie, $table);
            $games[] = $result['lines'];
            foreach (['turns', 'plays', 'exchanges', 'passes', 'bingos'] as $key) {
                $gameTotal[$key] += $result[$key];
            }
        } else {
            $result = duplicateJob($job, $settings, $trie, $table);
            $games[] = $result['lines'];
            $gameTotal['rounds'] += $result['rounds'];
        }
    }
    $moves[] = ['SUMMARY jobs=' . $topTotal['jobs'] . ' errors=' . $topTotal['errors'] . ' moves=' . $topTotal['moves'] . ' bingos=' . $topTotal['bingos']];
    $validation[] = ['SUMMARY jobs=' . $validationTotal['jobs'] . ' errors=' . $validationTotal['errors'] . ' moves=' . $validationTotal['moves'] .
        ' valid=' . $validationTotal['valid'] . ' invalid=' . $validationTotal['invalid'] . ' loss=' . $validationTotal['loss']];
    $games[] = ['SUMMARY games=' . $gameTotal['games'] . ' duplicates=' . $gameTotal['duplicates'] . ' errors=' . $gameTotal['errors'] .
        ' turns=' . $gameTotal['turns'] . ' rounds=' . $gameTotal['rounds'] . ' plays=' . $gameTotal['plays'] .
        ' exchanges=' . $gameTotal['exchanges'] . ' passes=' . $gameTotal['passes'] . ' bingos=' . $gameTotal['bingos']];
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    writeParagraphs('moves.txt', $moves);
    writeParagraphs('validation.txt', $validation);
    writeParagraphs('game.txt', $games);
}

main();
