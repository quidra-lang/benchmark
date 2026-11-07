'use strict';

const fs = require('node:fs');
const board = require('./board');
const { Trie } = require('./dictionary_trie');
const generator = require('./move_generator');
const scoring = require('./scoring');
const game = require('./game');

const STRATEGIES = ['score', 'tiles', 'equity'];
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const VOWELS = 'AEIOU';
const ascii = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const sorted = tiles => Array.from(tiles).sort().join('');
const collection = tiles => sorted(tiles) || '-';
const nameValid = name => /^[a-z0-9_]{1,20}$/.test(name);
const rackValid = rack => /^[A-Z?]{1,7}$/.test(rack);
const numberValid = (text, low, high) => /^(0|[1-9][0-9]*)$/.test(text) && Number(text) >= low && Number(text) <= high;
const readLines = path => fs.readFileSync(path, 'ascii').split('\n').slice(0, -1);
const notation = move => board.position(move.row, move.column, move.direction) + ' ' + move.word;
const wordList = move => move.words.map(word => `${word.word}:${word.score}`).join(',');

function frequencies(tiles) {
    const counts = new Map();
    for (const tile of tiles) counts.set(tile, (counts.get(tile) || 0) + 1);
    return counts;
}

function readInput() {
    const table = new Map();
    for (const line of readLines('input/tiles.txt')) {
        if (line === '' || line.startsWith('#')) continue;
        const [letter, value, count, weight] = line.split(' ');
        table.set(letter, { value: Number(value), count: Number(count), weight: Number(weight) });
    }
    const trie = new Trie();
    const stats = { lines: 0, skipped: 0, duplicates: 0, lengths: new Map() };
    for (const line of readLines('input/dictionary.txt')) {
        if (line === '' || line.startsWith('#')) continue;
        stats.lines++;
        if (!/^[A-Z]{2,15}$/.test(line)) stats.skipped++;
        else if (!trie.add(line)) stats.duplicates++;
        else stats.lengths.set(line.length, (stats.lengths.get(line.length) || 0) + 1);
    }
    const lines = readLines('input/jobs.txt');
    const jobs = [];
    for (let i = 0; i < lines.length; i++) {
        if (lines[i] === '' || lines[i].startsWith('#')) continue;
        const [kind, name, ...args] = lines[i].split(' ');
        const body = [];
        while (lines[++i] !== 'END') body.push(lines[i]);
        jobs.push({ kind, name, args, body });
    }
    return { table, trie, stats, jobs };
}

function usedTiles(grid, rack) {
    return frequencies(board.tiles(grid).map(tile => scoring.tileKind(tile.letter)).join('') + rack);
}

function tileCountError(grid, rack, table) {
    const used = usedTiles(grid, rack);
    for (const [letter, tile] of table) if ((used.get(letter) || 0) > tile.count) return `too many ${letter}`;
    return null;
}

function unseenTiles(grid, rack, table) {
    const used = usedTiles(grid, rack);
    let unseen = '';
    for (const [letter, tile] of table) unseen += letter.repeat(tile.count - (used.get(letter) || 0));
    return unseen;
}

function checkBoard(lines, rack, table, trie) {
    if (lines.length !== board.SIZE) return { error: `board rows ${lines.length}` };
    for (let i = 0; i < lines.length; i++) {
        if (!/^[.A-Za-z]{15}$/.test(lines[i])) return { error: `bad board row ${i + 1}` };
    }
    const grid = lines.map(line => Array.from(line));
    const countError = tileCountError(grid, rack, table);
    if (countError) return { error: countError };
    if (board.tiles(grid).length > 0 && grid[board.CENTER][board.CENTER] === '.') return { error: 'center empty' };
    if (!board.connected(grid)) return { error: 'disconnected' };
    for (const word of board.words(grid)) {
        if (!trie.has(word.word.toUpperCase())) return { error: `unknown word ${word.word} at ${board.position(word.row, word.column, word.direction)}` };
    }
    return { grid };
}

function checkJob(job, duplicate, table, trie) {
    if (!nameValid(job.name)) return { error: 'bad name' };
    if (duplicate) return { error: 'duplicate name' };
    if (job.kind === 'TOPN') {
        if (!numberValid(job.args[0], 1, 99)) return { error: 'bad count' };
        if (!STRATEGIES.includes(job.args[1])) return { error: 'bad order' };
        const rack = job.body[0].split(' ')[1];
        if (!rackValid(rack)) return { error: 'bad rack' };
        return { ...checkBoard(job.body.slice(2), rack, table, trie), rack,
            count: Number(job.args[0]), strategy: job.args[1] };
    }
    if (job.kind === 'VALIDATE') {
        let at = 1;
        while (at < job.body.length && !job.body[at].startsWith('MOVE')) at++;
        return { ...checkBoard(job.body.slice(1, at), '', table, trie), records: job.body.slice(at) };
    }
    if (!numberValid(job.args[0], 1, 2147483646)) return { error: 'bad seed' };
    if (job.body.length < 2 || job.body.length > 4) return { error: `bad player count ${job.body.length}` };
    const players = [];
    const names = new Set();
    for (let i = 0; i < job.body.length; i++) {
        const [, name, strategy, threshold] = job.body[i].split(' ');
        if (!nameValid(name) || !STRATEGIES.includes(strategy) ||
            (job.kind === 'GAME' && !numberValid(threshold, 0, 99))) return { error: `bad player ${i + 1}` };
        if (names.has(name)) return { error: `duplicate player ${i + 1}` };
        names.add(name);
        players.push({ name, strategy, threshold: job.kind === 'GAME' ? Number(threshold) : 0, index: i });
    }
    return { players, seed: Number(job.args[0]) };
}

function leaveValue(tiles, table) {
    const counts = frequencies(tiles);
    let value = 0;
    let duplicates = 0;
    let vowels = 0;
    let consonants = 0;
    for (const tile of tiles) {
        value += table.get(tile).weight;
        if (VOWELS.includes(tile)) vowels++;
        else if (tile !== '?') consonants++;
    }
    for (const [tile, count] of counts) if (tile !== '?') duplicates += count - 1;
    return value - 4 * duplicates - 3 * Math.max(0, Math.abs(vowels - consonants) - 1);
}

function bestLeave(rack, table) {
    const counts = frequencies(rack);
    const letters = Array.from(counts.keys()).sort();
    let best = { tiles: '', value: 0 };
    function visit(index, tiles) {
        if (tiles.length >= rack.length) return;
        if (index === letters.length) {
            const value = leaveValue(tiles, table);
            if (value > best.value || (value === best.value && (tiles.length > best.tiles.length ||
                (tiles.length === best.tiles.length && tiles < best.tiles)))) best = { tiles, value };
            return;
        }
        const letter = letters[index];
        for (let count = 0; count <= counts.get(letter); count++) visit(index + 1, tiles + letter.repeat(count));
    }
    visit(0, '');
    return best;
}

function removeTiles(rack, used) {
    const remaining = Array.from(rack);
    for (const tile of used) remaining.splice(remaining.indexOf(tile), 1);
    return remaining.join('');
}

function standardOrder(a, b) {
    return b.score - a.score || a.row - b.row || a.column - b.column ||
        (a.direction === b.direction ? 0 : a.direction === 'across' ? -1 : 1) || ascii(a.word, b.word);
}

function strategyOrder(moves, strategy) {
    return moves.slice().sort((a, b) => (strategy === 'tiles' ? b.tiles.length - a.tiles.length :
        strategy === 'equity' ? (b.score + b.leaveValue) - (a.score + a.leaveValue) : 0) || standardOrder(a, b));
}

function legalMoves(grid, rack, trie, table) {
    const generated = generator.generate(grid, rack, trie);
    const moves = generated.moves.map(move => {
        const result = scoring.score(grid, move, table);
        const leave = removeTiles(rack, result.tiles.map(tile => scoring.tileKind(tile.letter)));
        return { ...result, leave, leaveValue: leaveValue(leave, table) };
    }).sort(standardOrder);
    moves.forEach((move, i) => { move.rank = i + 1; });
    return { ...generated, moves };
}

function place(grid, move) {
    for (const tile of move.tiles) grid[tile.row][tile.column] = tile.letter;
}

function placementKey(move) {
    return move.tiles.slice().sort((a, b) => a.row - b.row || a.column - b.column)
        .map(tile => `${tile.row * board.SIZE + tile.column}:${tile.letter}`).join(',');
}

function positionSummary(grid) {
    const tiles = board.tiles(grid);
    const words = board.words(grid);
    let longest = '-';
    for (const word of words) if (longest === '-' || word.word.length > longest.length) longest = word.word;
    let blanks = 0;
    const premiums = new Map([['#', 0], ['*', 0], ['^', 0], ['+', 0]]);
    for (const tile of tiles) {
        if (scoring.tileKind(tile.letter) === '?') blanks++;
        const premium = board.PREMIUMS[tile.row][tile.column];
        if (premiums.has(premium)) premiums.set(premium, premiums.get(premium) + 1);
    }
    return `position tiles=${tiles.length} words=${words.length} longest=${longest} blanks=${blanks} premiums=TW:${premiums.get('#')},DW:${premiums.get('*')},TL:${premiums.get('^')},DL:${premiums.get('+')}`;
}

function topJob(job, settings, trie, table) {
    const { grid, rack, count, strategy } = settings;
    const generated = legalMoves(grid, rack, trie, table);
    const { moves } = generated;
    const unseen = unseenTiles(grid, rack, table);
    let vowels = 0;
    let consonants = 0;
    let blanks = 0;
    for (const tile of rack) {
        if (VOWELS.includes(tile)) vowels++;
        else if (tile === '?') blanks++;
        else consonants++;
    }
    const across = moves.filter(move => move.direction === 'across').length;
    const bingos = moves.filter(move => move.tiles.length === scoring.RACK_SIZE).length;
    const withBlank = moves.filter(move => move.tiles.some(tile => scoring.tileKind(tile.letter) === '?')).length;
    const bestByTiles = Array(8).fill(null);
    for (const move of moves) {
        const size = move.tiles.length;
        if (bestByTiles[size] === null || move.score > bestByTiles[size]) bestByTiles[size] = move.score;
    }
    const keep = bestLeave(rack, table);
    const anagrams = trie.anagrams(rack).sort((a, b) => b.length - a.length || ascii(a, b));
    const lines = [`TOPN ${job.name} n=${count} order=${strategy} rack=${collection(rack)}`,
        `board tiles=${board.tiles(grid).length} anchors=${generated.anchors}`,
        `unseen count=${unseen.length} tiles=${collection(unseen)}`,
        `rack vowels=${vowels} consonants=${consonants} blanks=${blanks} value=${game.value(rack, table)}`,
        `checks across=${generated.across.join(',')} down=${generated.down.join(',')}`,
        `moves total=${moves.length} across=${across} down=${moves.length - across} bingos=${bingos} blanks=${withBlank}`,
        'best_by_tiles ' + Array.from({ length: 7 }, (_, i) => `${i + 1}=${bestByTiles[i + 1] ?? '-'}`).join(' '),
        `exchange keep=${collection(keep.tiles)} value=${keep.value}`,
        `anagrams total=${anagrams.length} top=${anagrams.slice(0, 10).join(',') || '-'}`];
    for (const word of board.words(grid)) if (word.word.length >= 3) {
        const upper = word.word.toUpperCase();
        let front = '';
        let back = '';
        for (const letter of ALPHABET) {
            if (trie.has(letter + upper)) front += letter;
            if (trie.has(upper + letter)) back += letter;
        }
        if (front || back) lines.push(`hook ${board.position(word.row, word.column, word.direction)} ${word.word} front=${front || '-'} back=${back || '-'}`);
    }
    const shown = strategyOrder(moves, strategy).slice(0, count);
    const endgame = unseen.length >= 1 && unseen.length <= 7 && shown.length > 0;
    if (endgame) {
        let best = 0;
        for (let i = 0; i < shown.length; i++) {
            const after = board.clone(grid);
            place(after, shown[i]);
            const replies = legalMoves(after, unseen, trie, table).moves;
            shown[i].net = shown[i].score - (replies.length ? replies[0].score : 0);
            if (shown[i].net > shown[best].net) best = i;
        }
        lines.push(`endgame opponent=${collection(unseen)} best=${best + 1} net=${shown[best].net}`);
    }
    shown.forEach((move, i) => lines.push(`${i + 1} ${notation(move)} score=${move.score} tiles=${move.tiles.length} leave=${collection(move.leave)} value=${move.leaveValue}` +
        (endgame ? ` net=${move.net}` : '') + ` words=${wordList(move)}`));
    return { lines, moves: moves.length, bingos };
}

function checkRecord(grid, fields, trie, table) {
    const [, player, rack, ...action] = fields;
    if (!nameValid(player)) return { error: 'bad player' };
    if (!rackValid(rack)) return { error: 'bad rack' };
    const countError = tileCountError(grid, rack, table);
    if (countError) return { error: countError };
    if (action.length === 1 && action[0] === 'PASS') return { kind: 'pass' };
    if (action[0] === 'EXCHANGE') {
        if (!rackValid(action[1])) return { error: 'bad exchange' };
        const returned = frequencies(action[1]);
        const available = frequencies(rack);
        for (const tile of action[1]) if (returned.get(tile) > (available.get(tile) || 0)) return { error: `rack lacks ${tile}` };
        return { kind: 'exchange' };
    }
    const start = board.parsePosition(action[0]);
    if (start === null) return { error: 'bad position' };
    if (!/^[A-Za-z]{2,15}$/.test(action[1])) return { error: 'bad word' };
    const move = { ...start, word: action[1] };
    const squares = scoring.squares(move);
    if (squares.some(tile => !board.inside(tile.row, tile.column))) return { error: 'off board' };
    for (const tile of squares) {
        if (board.occupied(grid, tile.row, tile.column) && grid[tile.row][tile.column] !== tile.letter) {
            return { error: `mismatch at ${board.square(tile.row, tile.column)}` };
        }
    }
    const dr = move.direction === 'down' ? 1 : 0;
    const dc = move.direction === 'across' ? 1 : 0;
    if (board.occupied(grid, move.row - dr, move.column - dc) ||
        board.occupied(grid, move.row + dr * move.word.length, move.column + dc * move.word.length)) return { error: 'not whole word' };
    const newTiles = squares.filter(tile => !board.occupied(grid, tile.row, tile.column));
    if (newTiles.length === 0) return { error: 'no new tiles' };
    const available = frequencies(rack);
    for (const tile of newTiles) {
        const letter = scoring.tileKind(tile.letter);
        if ((available.get(letter) || 0) === 0) return { error: `rack lacks ${letter}` };
        available.set(letter, available.get(letter) - 1);
    }
    if (board.tiles(grid).length === 0) {
        if (!newTiles.some(tile => tile.row === board.CENTER && tile.column === board.CENTER)) return { error: 'center not covered' };
    } else if (!newTiles.some(tile => board.adjacent(grid, tile.row, tile.column))) return { error: 'not connected' };
    const result = scoring.score(grid, move, table);
    for (const word of result.words) {
        if (!trie.has(word.word.toUpperCase())) return { error: `unknown word ${word.word} at ${board.position(word.row, word.column, word.direction)}` };
    }
    return { kind: 'play', move: result };
}

function validationJob(job, settings, trie, table) {
    const { grid, records } = settings;
    const players = new Map();
    const total = { valid: 0, invalid: 0, score: 0, best: 0, loss: 0 };
    const lines = [`VALIDATE ${job.name}`];
    for (let i = 0; i < records.length; i++) {
        const fields = records[i].split(' ');
        const [, name, rack, ...action] = fields;
        const prefix = `move ${i + 1} ${name} ${action.join(' ')}`;
        const checked = checkRecord(grid, fields, trie, table);
        if (checked.error !== 'bad player') {
            if (!players.has(name)) players.set(name, { moves: 0, valid: 0, score: 0, loss: 0 });
            players.get(name).moves++;
        }
        if (checked.error) {
            total.invalid++;
            lines.push(prefix + ' invalid ' + checked.error);
            continue;
        }
        const moves = legalMoves(grid, rack, trie, table).moves;
        const best = moves.length ? moves[0].score : 0;
        const score = checked.kind === 'play' ? checked.move.score : 0;
        const loss = best - score;
        const player = players.get(name);
        player.valid++;
        player.score += score;
        player.loss += loss;
        total.valid++;
        total.score += score;
        total.best += best;
        total.loss += loss;
        if (checked.kind === 'play') {
            const key = placementKey(checked.move);
            const equivalent = moves.find(move => placementKey(move) === key);
            lines.push(prefix + ` score=${score} total=${player.score} tiles=${checked.move.tiles.length} rank=${equivalent.rank}/${moves.length} best=${best} words=${wordList(checked.move)}`);
            place(grid, checked.move);
        } else lines.push(prefix + ` score=0 total=${player.score} moves=${moves.length} best=${best}`);
    }
    for (const [name, player] of players) {
        lines.push(`player ${name} moves=${player.moves} valid=${player.valid} score=${player.score} loss=${player.loss}`);
    }
    lines.push(`total valid=${total.valid} invalid=${total.invalid} score=${total.score} best=${total.best} loss=${total.loss}`,
        positionSummary(grid), ...board.display(grid));
    return { lines, moves: records.length, ...total };
}

function gameJob(job, settings, trie, table) {
    const random = new game.Minstd(settings.seed);
    const bag = game.makeBag(table, random);
    const grid = board.empty();
    const players = settings.players.map(player => ({ ...player, rack: game.draw(bag, scoring.RACK_SIZE),
        score: 0, plays: 0, bingos: 0, exchanges: 0, passes: 0, top: 0, loss: 0 }));
    const lines = [`GAME ${job.name} seed=${settings.seed} players=${players.length}`];
    players.forEach((player, i) => lines.push(`player ${i + 1} ${player.name} strategy=${player.strategy} threshold=${player.threshold}`));
    let turns = 0;
    let scoreless = 0;
    let reason = null;
    let wentOut = null;
    let highlight = null;
    while (reason === null) {
        const player = players[turns % players.length];
        turns++;
        const moves = legalMoves(grid, player.rack, trie, table).moves;
        const candidate = strategyOrder(moves, player.strategy)[0];
        const prefix = `turn ${turns} ${player.name} rack=${collection(player.rack)} moves=${moves.length}`;
        if (candidate && !(candidate.score < player.threshold && bag.length >= scoring.RACK_SIZE)) {
            place(grid, candidate);
            player.score += candidate.score;
            player.plays++;
            if (candidate.tiles.length === scoring.RACK_SIZE) player.bingos++;
            player.top = Math.max(player.top, candidate.score);
            player.loss += moves[0].score - candidate.score;
            player.rack = candidate.leave;
            const drawn = game.draw(bag, scoring.RACK_SIZE - player.rack.length);
            player.rack += drawn;
            scoreless = 0;
            lines.push(prefix + ` best=${moves[0].score} play ${notation(candidate)} score=${candidate.score} total=${player.score} draw=${collection(drawn)} bag=${bag.length}`);
            if (highlight === null || candidate.score > highlight.move.score) highlight = { turn: turns, player: player.name, move: candidate };
            if (player.rack.length === 0 && bag.length === 0) {
                reason = 'out';
                wentOut = player;
            }
        } else if (bag.length >= scoring.RACK_SIZE) {
            const keep = bestLeave(player.rack, table).tiles;
            const returned = removeTiles(player.rack, keep);
            const drawn = game.exchange(bag, returned, random);
            player.rack = keep + drawn;
            player.exchanges++;
            scoreless++;
            lines.push(prefix + ` exchange keep=${collection(keep)} draw=${collection(drawn)} bag=${bag.length}`);
        } else {
            player.passes++;
            scoreless++;
            lines.push(prefix + ` pass bag=${bag.length}`);
        }
        if (reason === null && scoreless === 6) reason = 'scoreless';
    }
    lines.push(reason === 'out' ? `end reason=out player=${wentOut.name} turns=${turns}` : `end reason=scoreless turns=${turns}`);
    let transferred = 0;
    for (const player of players) {
        player.adjustment = -game.value(player.rack, table);
        if (player !== wentOut) transferred -= player.adjustment;
    }
    if (wentOut !== null) wentOut.adjustment = transferred;
    for (const player of players) {
        player.total = player.score + player.adjustment;
        const adjustment = player.adjustment > 0 ? '+' + player.adjustment : String(player.adjustment);
        lines.push(`final ${player.name} score=${player.score} rack=${collection(player.rack)} adjust=${adjustment} total=${player.total}`);
    }
    const standings = players.slice().sort((a, b) => b.total - a.total || a.index - b.index);
    standings.forEach((player, i) => lines.push(`standing ${i + 1} ${player.name} total=${player.total} plays=${player.plays} bingos=${player.bingos} exchanges=${player.exchanges} passes=${player.passes} top=${player.top} loss=${player.loss}`));
    lines.push('winner ' + players.filter(player => player.total === standings[0].total).map(player => player.name).join(','));
    if (highlight !== null) lines.push(`highlight turn=${highlight.turn} player=${highlight.player} play ${notation(highlight.move)} score=${highlight.move.score}`);
    lines.push(positionSummary(grid), ...board.display(grid));
    const totals = { turns, plays: 0, exchanges: 0, passes: 0, bingos: 0 };
    for (const player of players) {
        totals.plays += player.plays;
        totals.exchanges += player.exchanges;
        totals.passes += player.passes;
        totals.bingos += player.bingos;
    }
    return { lines, ...totals };
}

function duplicateJob(job, settings, trie, table) {
    const random = new game.Minstd(settings.seed);
    const bag = game.makeBag(table, random);
    const grid = board.empty();
    const players = settings.players.map(player => ({ ...player, total: 0 }));
    let rack = game.draw(bag, scoring.RACK_SIZE);
    let masterTotal = 0;
    let rounds = 0;
    let reason;
    const lines = [`DUPLICATE ${job.name} seed=${settings.seed} players=${players.length}`];
    players.forEach((player, i) => lines.push(`player ${i + 1} ${player.name} strategy=${player.strategy}`));
    while (true) {
        const moves = legalMoves(grid, rack, trie, table).moves;
        if (moves.length === 0) { reason = 'stuck'; break; }
        rounds++;
        const master = moves[0];
        const picks = [];
        for (const player of players) {
            const move = strategyOrder(moves, player.strategy)[0];
            player.total += move.score;
            picks.push(move.score);
        }
        masterTotal += master.score;
        lines.push(`round ${rounds} rack=${collection(rack)} moves=${moves.length} master ${notation(master)} score=${master.score} picks=${picks.join(',')}`);
        place(grid, master);
        rack = master.leave;
        rack += game.draw(bag, scoring.RACK_SIZE - rack.length);
        if (rack.length === 0) { reason = 'out'; break; }
    }
    lines.push(reason === 'out' ? `end reason=out rounds=${rounds}` : `end reason=stuck rounds=${rounds} rack=${collection(rack)}`,
        `master total=${masterTotal}`);
    for (const player of players) {
        const percent = masterTotal > 0 ? Math.floor(100 * player.total / masterTotal) : 0;
        lines.push(`final ${player.name} total=${player.total} percent=${percent}`);
    }
    const maximum = Math.max(...players.map(player => player.total));
    lines.push('winner ' + players.filter(player => player.total === maximum).map(player => player.name).join(','),
        positionSummary(grid), ...board.display(grid));
    return { lines, rounds };
}

function writeParagraphs(name, paragraphs) {
    fs.writeFileSync('output/' + name, paragraphs.map(lines => lines.join('\n')).join('\n\n') + '\n', 'ascii');
}

function main() {
    const { table, trie, stats, jobs } = readInput();
    const lengths = Array.from(stats.lengths.keys()).sort((a, b) => a - b);
    const moves = [[`DICTIONARY lines=${stats.lines} words=${trie.words} skipped=${stats.skipped} duplicates=${stats.duplicates} nodes=${trie.nodes}`,
        'lengths ' + lengths.map(length => `${length}=${stats.lengths.get(length)}`).join(' ')]];
    const validation = [];
    const games = [];
    const topTotal = { jobs: 0, errors: 0, moves: 0, bingos: 0 };
    const validationTotal = { jobs: 0, errors: 0, moves: 0, valid: 0, invalid: 0, loss: 0 };
    const gameTotal = { games: 0, duplicates: 0, errors: 0, turns: 0, rounds: 0, plays: 0, exchanges: 0, passes: 0, bingos: 0 };
    const seen = new Set();
    for (const job of jobs) {
        const duplicate = seen.has(job.name);
        seen.add(job.name);
        const settings = checkJob(job, duplicate, table, trie);
        const paragraphs = job.kind === 'TOPN' ? moves : job.kind === 'VALIDATE' ? validation : games;
        const totals = job.kind === 'TOPN' ? topTotal : job.kind === 'VALIDATE' ? validationTotal : gameTotal;
        if (job.kind === 'GAME') gameTotal.games++;
        else if (job.kind === 'DUPLICATE') gameTotal.duplicates++;
        else totals.jobs++;
        if (settings.error) {
            totals.errors++;
            paragraphs.push([`${job.kind} ${job.name}`, 'error ' + settings.error]);
            continue;
        }
        if (job.kind === 'TOPN') {
            const result = topJob(job, settings, trie, table);
            moves.push(result.lines);
            topTotal.moves += result.moves;
            topTotal.bingos += result.bingos;
        } else if (job.kind === 'VALIDATE') {
            const result = validationJob(job, settings, trie, table);
            validation.push(result.lines);
            for (const key of ['moves', 'valid', 'invalid', 'loss']) validationTotal[key] += result[key];
        } else if (job.kind === 'GAME') {
            const result = gameJob(job, settings, trie, table);
            games.push(result.lines);
            for (const key of ['turns', 'plays', 'exchanges', 'passes', 'bingos']) gameTotal[key] += result[key];
        } else {
            const result = duplicateJob(job, settings, trie, table);
            games.push(result.lines);
            gameTotal.rounds += result.rounds;
        }
    }
    moves.push([`SUMMARY jobs=${topTotal.jobs} errors=${topTotal.errors} moves=${topTotal.moves} bingos=${topTotal.bingos}`]);
    validation.push([`SUMMARY jobs=${validationTotal.jobs} errors=${validationTotal.errors} moves=${validationTotal.moves} valid=${validationTotal.valid} invalid=${validationTotal.invalid} loss=${validationTotal.loss}`]);
    games.push([`SUMMARY games=${gameTotal.games} duplicates=${gameTotal.duplicates} errors=${gameTotal.errors} turns=${gameTotal.turns} rounds=${gameTotal.rounds} plays=${gameTotal.plays} exchanges=${gameTotal.exchanges} passes=${gameTotal.passes} bingos=${gameTotal.bingos}`]);
    fs.mkdirSync('output', { recursive: true });
    writeParagraphs('moves.txt', moves);
    writeParagraphs('validation.txt', validation);
    writeParagraphs('game.txt', games);
}

main();
