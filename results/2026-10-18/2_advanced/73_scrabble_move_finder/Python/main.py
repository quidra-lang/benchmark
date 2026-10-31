"""Validate Scrabble jobs, rank moves and run ordinary and duplicate games."""

from collections import Counter, namedtuple
from itertools import product
from pathlib import Path
import re

from board import CENTER, PREMIUMS, SIZE, Move, connected, display, inside, neighbors, parse_position, position, square_name, tiles, transpose, words
from dictionary_trie import Trie
from game import TILE_ORDER, Minstd, draw, exchange, make_bag, points
from move_generator import LETTERS, anchors, cross_checks, generate
from scoring import RACK_SIZE, apply, cross_words, placement, score_move, squares


Evaluated = namedtuple("Evaluated", "move score new_tiles words leave value")
VOWELS = "AEIOU"
STRATEGIES = ("score", "tiles", "equity")


def valid_name(value):
    return re.fullmatch(r"[a-z0-9_]{1,20}", value) is not None


def valid_number(value, minimum, maximum):
    return re.fullmatch(r"0|[1-9][0-9]*", value) is not None and minimum <= int(value) <= maximum


def valid_rack(value):
    return 1 <= len(value) <= RACK_SIZE and all(letter in TILE_ORDER for letter in value)


def collection(value):
    return "".join(sorted(value)) or "-"


def tile_kind(letter):
    return letter if letter.isupper() else "?"


def remove_tiles(rack, removed):
    counts = Counter(rack)
    counts.subtract(removed)
    return "".join(letter * counts[letter] for letter in sorted(counts))


def notation(evaluated):
    return position(evaluated.move) + " " + evaluated.move.word


def standard_key(evaluated):
    move = evaluated.move
    return -evaluated.score, move.row, move.column, move.direction, move.word


def strategy_key(evaluated, strategy):
    prefix = () if strategy == "score" else (-len(evaluated.new_tiles),) if strategy == "tiles" else (-evaluated.score - evaluated.value,)
    return prefix + standard_key(evaluated)


def read_inputs():
    values, counts, weights = {}, {}, {}
    for line in Path("input/tiles.txt").read_text(encoding="ascii").splitlines():
        if line and not line.startswith("#"):
            letter, value, count, weight = line.split()
            values[letter], counts[letter], weights[letter] = int(value), int(count), int(weight)
    trie, dictionary_counts, lengths = Trie(), Counter(), Counter()
    for line in Path("input/dictionary.txt").read_text(encoding="ascii").splitlines():
        if not line or line.startswith("#"):
            continue
        dictionary_counts["lines"] += 1
        if not 2 <= len(line) <= 15 or any(letter not in LETTERS for letter in line):
            dictionary_counts["skipped"] += 1
        elif trie.add(line):
            lengths[len(line)] += 1
        else:
            dictionary_counts["duplicates"] += 1
    jobs, current = [], None
    for line in Path("input/jobs.txt").read_text(encoding="ascii").splitlines():
        if current is None:
            if line and not line.startswith("#"):
                current = [line]
        elif line == "END":
            jobs.append(current)
            current = None
        else:
            current.append(line)
    dictionary_lines = [f"DICTIONARY lines={dictionary_counts['lines']} words={trie.words} "
                        f"skipped={dictionary_counts['skipped']} duplicates={dictionary_counts['duplicates']} nodes={trie.nodes}",
                        "lengths" + "".join(f" {length}={lengths[length]}" for length in sorted(lengths))]
    return values, counts, weights, trie, jobs, dictionary_lines


class Scrabble:
    def __init__(self, values, counts, weights, trie):
        self.values, self.counts, self.weights, self.trie = values, counts, weights, trie
        self.topn_totals, self.validation_totals, self.game_totals = Counter(), Counter(), Counter()

    def used_tiles(self, board):
        return Counter(tile_kind(letter) for _, _, letter in tiles(board))

    def tile_error(self, board, rack):
        counts = self.used_tiles(board) + Counter(rack)
        for letter in TILE_ORDER:
            if counts[letter] > self.counts[letter]:
                return "too many " + letter
        return None

    def unseen(self, board, rack):
        used = self.used_tiles(board) + Counter(rack)
        return "".join(letter * (self.counts[letter] - used[letter]) for letter in TILE_ORDER)

    def board_error(self, board, rack):
        if len(board) != SIZE:
            return f"board rows {len(board)}"
        for number, row in enumerate(board, 1):
            if len(row) != SIZE or any(letter not in "." + LETTERS + LETTERS.lower() for letter in row):
                return f"bad board row {number}"
        error = self.tile_error(board, rack)
        if error:
            return error
        if tiles(board) and board[CENTER[0]][CENTER[1]] == ".":
            return "center empty"
        if not connected(board):
            return "disconnected"
        for word in words(board):
            if word.word.upper() not in self.trie:
                return f"unknown word {word.word} at {position(word)}"
        return None

    def job_error(self, job, seen):
        fields = job[0].split()
        kind, name = fields[:2]
        if not valid_name(name):
            return "bad name"
        if name in seen:
            return "duplicate name"
        if kind == "TOPN":
            if not valid_number(fields[2], 1, 99):
                return "bad count"
            if fields[3] not in STRATEGIES:
                return "bad order"
            rack = job[1].split()[1]
            if not valid_rack(rack):
                return "bad rack"
            return self.board_error([list(row) for row in job[3:]], rack)
        if kind == "VALIDATE":
            rows = []
            for line in job[2:]:
                if line.startswith("MOVE"):
                    break
                rows.append(list(line))
            return self.board_error(rows, "")
        if not valid_number(fields[2], 1, 2147483646):
            return "bad seed"
        if not 2 <= len(job) - 1 <= 4:
            return f"bad player count {len(job) - 1}"
        names = set()
        for number, line in enumerate(job[1:], 1):
            player = line.split()
            if not valid_name(player[1]) or player[2] not in STRATEGIES:
                return f"bad player {number}"
            if kind == "GAME" and not valid_number(player[3], 0, 99):
                return f"bad player {number}"
            if player[1] in names:
                return f"duplicate player {number}"
            names.add(player[1])
        return None

    def leave_value(self, rack):
        counts = Counter(rack)
        duplicates = sum(max(0, counts[letter] - 1) for letter in LETTERS)
        vowels = sum(counts[letter] for letter in VOWELS)
        consonants = sum(counts[letter] for letter in LETTERS if letter not in VOWELS)
        return sum(self.weights[letter] for letter in rack) - 4 * duplicates - 3 * max(0, abs(vowels - consonants) - 1)

    def best_leave(self, rack):
        counts = Counter(rack)
        letters = sorted(counts)
        candidates = []
        for quantities in product(*(range(counts[letter] + 1) for letter in letters)):
            if sum(quantities) < len(rack):
                candidate = "".join(letter * count for letter, count in zip(letters, quantities))
                candidates.append(candidate)
        return min(candidates, key=lambda candidate: (-self.leave_value(candidate), -len(candidate), candidate))

    def evaluate(self, board, rack, move):
        score, new_tiles, word_scores = score_move(board, move, self.values)
        leave = remove_tiles(rack, (tile_kind(letter) for _, _, letter in new_tiles))
        word_list = ",".join(f"{word.word}:{value}" for word, value in word_scores)
        return Evaluated(move, score, new_tiles, word_list, leave, self.leave_value(leave))

    def legal_moves(self, board, rack):
        return sorted((self.evaluate(board, rack, move) for move in generate(board, rack, self.trie)), key=standard_key)

    def position_summary(self, board):
        board_words, occupied = words(board), tiles(board)
        longest = max(board_words, key=lambda word: len(word.word)).word if board_words else "-"
        blanks = sum(letter.islower() for _, _, letter in occupied)
        premiums = Counter(PREMIUMS[row][column] for row, column, _ in occupied)
        return (f"position tiles={len(occupied)} words={len(board_words)} longest={longest} blanks={blanks} "
                f"premiums=TW:{premiums['#']},DW:{premiums['*']},TL:{premiums['^']},DL:{premiums['+']}")

    def topn(self, job):
        _, name, count, order = job[0].split()
        count = int(count)
        rack = job[1].split()[1]
        board = [list(row) for row in job[3:]]
        moves = self.legal_moves(board, rack)
        shown = sorted(moves, key=lambda move: strategy_key(move, order))[:count]
        unseen, anchor_squares = self.unseen(board, rack), anchors(board)
        checks = [cross_checks(board, self.trie), cross_checks(transpose(board), self.trie)]
        statistics = [f"{len(check)},{sum(not allowed for allowed in check.values())},{sum(map(len, check.values()))}"
                      for check in checks]
        vowels = sum(letter in VOWELS for letter in rack)
        consonants = sum(letter in LETTERS and letter not in VOWELS for letter in rack)
        across = sum(move.move.direction == 0 for move in moves)
        bingos = sum(len(move.new_tiles) == RACK_SIZE for move in moves)
        blanks = sum(any(letter.islower() for _, _, letter in move.new_tiles) for move in moves)
        lines = [f"TOPN {name} n={count} order={order} rack={collection(rack)}",
                 f"board tiles={len(tiles(board))} anchors={len(anchor_squares)}",
                 f"unseen count={len(unseen)} tiles={collection(unseen)}",
                 f"rack vowels={vowels} consonants={consonants} blanks={rack.count('?')} value={points(rack, self.values)}",
                 f"checks across={statistics[0]} down={statistics[1]}",
                 f"moves total={len(moves)} across={across} down={len(moves) - across} bingos={bingos} blanks={blanks}"]
        scores = [max((move.score for move in moves if len(move.new_tiles) == number), default="-")
                  for number in range(1, RACK_SIZE + 1)]
        lines.append("best_by_tiles" + "".join(f" {number}={score}" for number, score in enumerate(scores, 1)))
        keep = self.best_leave(rack)
        lines.append(f"exchange keep={collection(keep)} value={self.leave_value(keep)}")
        anagrams = sorted(self.trie.anagrams(rack), key=lambda word: (-len(word), word))
        lines.append(f"anagrams total={len(anagrams)} top={','.join(anagrams[:10]) or '-'}")
        for word in words(board):
            if len(word.word) < 3:
                continue
            front = "".join(letter for letter in LETTERS if letter + word.word.upper() in self.trie)
            back = "".join(letter for letter in LETTERS if word.word.upper() + letter in self.trie)
            if front or back:
                lines.append(f"hook {position(word)} {word.word} front={front or '-'} back={back or '-'}")
        nets = None
        if 1 <= len(unseen) <= RACK_SIZE and shown:
            nets = []
            for move in shown:
                replies = self.legal_moves(apply(board, move.new_tiles), unseen)
                nets.append(move.score - (replies[0].score if replies else 0))
            best = max(range(len(nets)), key=lambda index: nets[index])
            lines.append(f"endgame opponent={collection(unseen)} best={best + 1} net={nets[best]}")
        for number, move in enumerate(shown, 1):
            net = f" net={nets[number - 1]}" if nets is not None else ""
            lines.append(f"{number} {notation(move)} score={move.score} tiles={len(move.new_tiles)} "
                         f"leave={collection(move.leave)} value={move.value}{net} words={move.words}")
        self.topn_totals["moves"] += len(moves)
        self.topn_totals["bingos"] += bingos
        return lines

    def record_error(self, board, player, rack, action):
        if not valid_name(player):
            return "bad player", None
        if not valid_rack(rack):
            return "bad rack", None
        error = self.tile_error(board, rack)
        if error:
            return error, None
        if len(action) == 1 and action[0] == "PASS":
            return None, None
        if action[0] == "EXCHANGE":
            returned = action[1]
            if not valid_rack(returned):
                return "bad exchange", None
            available, requested = Counter(rack), Counter(returned)
            for letter in returned:
                if requested[letter] > available[letter]:
                    return "rack lacks " + letter, None
            return None, None
        parsed = parse_position(action[0])
        if parsed is None:
            return "bad position", None
        word = action[1]
        if not 2 <= len(word) <= SIZE or any(letter not in LETTERS + LETTERS.lower() for letter in word):
            return "bad word", None
        move = Move(*parsed, word)
        cells = squares(move)
        if any(not inside(row, column) for row, column, _ in cells):
            return "off board", None
        for row, column, letter in cells:
            if board[row][column] not in (".", letter):
                return "mismatch at " + square_name(row, column), None
        dr, dc = move.direction, 1 - move.direction
        before = move.row - dr, move.column - dc
        after = move.row + dr * len(word), move.column + dc * len(word)
        if any(inside(row, column) and board[row][column] != "." for row, column in (before, after)):
            return "not whole word", None
        new_tiles = placement(board, move)
        if not new_tiles:
            return "no new tiles", None
        available = Counter(rack)
        for _, _, letter in new_tiles:
            tile = tile_kind(letter)
            if not available[tile]:
                return "rack lacks " + tile, None
            available[tile] -= 1
        if not tiles(board):
            if not any((row, column) == CENTER for row, column, _ in new_tiles):
                return "center not covered", None
        elif not any(board[r][c] != "." for row, column, _ in new_tiles for r, c in neighbors(row, column)):
            return "not connected", None
        for formed in [move] + cross_words(board, move):
            if formed.word.upper() not in self.trie:
                return f"unknown word {formed.word} at {position(formed)}", None
        return None, move

    def validate(self, job):
        name = job[0].split()[1]
        board = [list(row) for row in job[2:2 + SIZE]]
        records = job[2 + SIZE:]
        lines, players, totals = [f"VALIDATE {name}"], {}, Counter()
        for number, line in enumerate(records, 1):
            _, player, rack, *action = line.split()
            prefix = f"move {number} {player} " + " ".join(action)
            error, move = self.record_error(board, player, rack, action)
            if error != "bad player":
                players.setdefault(player, Counter())["moves"] += 1
            if error:
                lines.append(prefix + " invalid " + error)
                totals["invalid"] += 1
                continue
            legal = self.legal_moves(board, rack)
            best = legal[0].score if legal else 0
            score = 0
            if move is not None:
                evaluated = self.evaluate(board, rack, move)
                score = evaluated.score
                target = tuple(sorted(evaluated.new_tiles))
                rank = next(index for index, candidate in enumerate(legal, 1)
                            if tuple(sorted(candidate.new_tiles)) == target)
            statistics = players[player]
            statistics["valid"] += 1
            statistics["score"] += score
            statistics["loss"] += best - score
            totals["valid"] += 1
            totals["score"] += score
            totals["best"] += best
            totals["loss"] += best - score
            if move is None:
                lines.append(f"{prefix} score=0 total={statistics['score']} moves={len(legal)} best={best}")
            else:
                lines.append(f"{prefix} score={score} total={statistics['score']} tiles={len(evaluated.new_tiles)} "
                             f"rank={rank}/{len(legal)} best={best} words={evaluated.words}")
                board = apply(board, evaluated.new_tiles)
        for player, statistics in players.items():
            lines.append(f"player {player} moves={statistics['moves']} valid={statistics['valid']} "
                         f"score={statistics['score']} loss={statistics['loss']}")
        lines.append(f"total valid={totals['valid']} invalid={totals['invalid']} score={totals['score']} "
                     f"best={totals['best']} loss={totals['loss']}")
        lines.append(self.position_summary(board))
        lines.extend(display(board))
        self.validation_totals["moves"] += len(records)
        for key in ("valid", "invalid", "loss"):
            self.validation_totals[key] += totals[key]
        return lines

    def ordinary_game(self, job):
        _, name, seed = job[0].split()
        random = Minstd(int(seed))
        bag = make_bag(self.counts, random)
        board = [["."] * SIZE for _ in range(SIZE)]
        players = []
        lines = [f"GAME {name} seed={int(seed)} players={len(job) - 1}"]
        for number, line in enumerate(job[1:], 1):
            _, player, strategy, threshold = line.split()
            players.append({"name": player, "strategy": strategy, "threshold": int(threshold),
                            "rack": draw(bag, RACK_SIZE), "score": 0, "statistics": Counter()})
            lines.append(f"player {number} {player} strategy={strategy} threshold={int(threshold)}")
        turn, consecutive, outgoing, highlight = 0, 0, None, None
        while True:
            index = turn % len(players)
            player = players[index]
            turn += 1
            rack, statistics = player["rack"], player["statistics"]
            legal = self.legal_moves(board, rack)
            candidate = min(legal, key=lambda move: strategy_key(move, player["strategy"])) if legal else None
            prefix = f"turn {turn} {player['name']} rack={collection(rack)} moves={len(legal)}"
            if candidate is not None and not (candidate.score < player["threshold"] and len(bag) >= RACK_SIZE):
                best = legal[0].score
                board = apply(board, candidate.new_tiles)
                player["score"] += candidate.score
                drawn = draw(bag, RACK_SIZE - len(candidate.leave))
                player["rack"] = candidate.leave + drawn
                statistics["plays"] += 1
                statistics["bingos"] += len(candidate.new_tiles) == RACK_SIZE
                statistics["top"] = max(statistics["top"], candidate.score)
                statistics["loss"] += best - candidate.score
                consecutive = 0
                if highlight is None or candidate.score > highlight[2].score:
                    highlight = turn, player["name"], candidate
                lines.append(f"{prefix} best={best} play {notation(candidate)} score={candidate.score} "
                             f"total={player['score']} draw={collection(drawn)} bag={len(bag)}")
                if not player["rack"] and not bag:
                    outgoing = index
                    break
            elif len(bag) >= RACK_SIZE:
                keep = self.best_leave(rack)
                returned = remove_tiles(rack, keep)
                drawn = exchange(bag, returned, random)
                player["rack"] = keep + drawn
                statistics["exchanges"] += 1
                consecutive += 1
                lines.append(f"{prefix} exchange keep={collection(keep)} draw={collection(drawn)} bag={len(bag)}")
            else:
                statistics["passes"] += 1
                consecutive += 1
                lines.append(f"{prefix} pass bag={len(bag)}")
            if consecutive == 6:
                break
        if outgoing is None:
            lines.append(f"end reason=scoreless turns={turn}")
        else:
            lines.append(f"end reason=out player={players[outgoing]['name']} turns={turn}")
        adjustments = [-points(player["rack"], self.values) for player in players]
        if outgoing is not None:
            adjustments[outgoing] = sum(points(player["rack"], self.values)
                                        for index, player in enumerate(players) if index != outgoing)
        final_scores = [player["score"] + adjustment for player, adjustment in zip(players, adjustments)]
        for player, adjustment, final_score in zip(players, adjustments, final_scores):
            adjusted = f"+{adjustment}" if adjustment > 0 else str(adjustment)
            lines.append(f"final {player['name']} score={player['score']} rack={collection(player['rack'])} "
                         f"adjust={adjusted} total={final_score}")
        standings = sorted(range(len(players)), key=lambda index: (-final_scores[index], index))
        for rank, index in enumerate(standings, 1):
            player, statistics = players[index], players[index]["statistics"]
            lines.append(f"standing {rank} {player['name']} total={final_scores[index]} plays={statistics['plays']} "
                         f"bingos={statistics['bingos']} exchanges={statistics['exchanges']} passes={statistics['passes']} "
                         f"top={statistics['top']} loss={statistics['loss']}")
        winners = [player["name"] for index, player in enumerate(players) if final_scores[index] == max(final_scores)]
        lines.append("winner " + ",".join(winners))
        if highlight is not None:
            number, player, move = highlight
            lines.append(f"highlight turn={number} player={player} play {notation(move)} score={move.score}")
        lines.append(self.position_summary(board))
        lines.extend(display(board))
        self.game_totals["turns"] += turn
        for player in players:
            for key in ("plays", "exchanges", "passes", "bingos"):
                self.game_totals[key] += player["statistics"][key]
        return lines

    def duplicate_game(self, job):
        _, name, seed = job[0].split()
        random = Minstd(int(seed))
        bag = make_bag(self.counts, random)
        board = [["."] * SIZE for _ in range(SIZE)]
        rack = draw(bag, RACK_SIZE)
        players = [line.split()[1:] for line in job[1:]]
        totals = [0] * len(players)
        lines = [f"DUPLICATE {name} seed={int(seed)} players={len(players)}"]
        for number, (player, strategy) in enumerate(players, 1):
            lines.append(f"player {number} {player} strategy={strategy}")
        round_number, master_total, reason = 0, 0, "stuck"
        while True:
            legal = self.legal_moves(board, rack)
            if not legal:
                break
            round_number += 1
            master = legal[0]
            choices = [min(legal, key=lambda move: strategy_key(move, strategy)) for _, strategy in players]
            for index, move in enumerate(choices):
                totals[index] += move.score
            master_total += master.score
            picks = ",".join(str(move.score) for move in choices)
            lines.append(f"round {round_number} rack={collection(rack)} moves={len(legal)} "
                         f"master {notation(master)} score={master.score} picks={picks}")
            board = apply(board, master.new_tiles)
            rack = master.leave + draw(bag, RACK_SIZE - len(master.leave))
            if not rack:
                reason = "out"
                break
        suffix = f" rack={collection(rack)}" if reason == "stuck" else ""
        lines.extend([f"end reason={reason} rounds={round_number}{suffix}", f"master total={master_total}"])
        for (player, _), total in zip(players, totals):
            percent = 100 * total // master_total if master_total >= 1 else 0
            lines.append(f"final {player} total={total} percent={percent}")
        winners = [player for (player, _), total in zip(players, totals) if total == max(totals)]
        lines.append("winner " + ",".join(winners))
        lines.append(self.position_summary(board))
        lines.extend(display(board))
        self.game_totals["rounds"] += round_number
        return lines

    def process(self, jobs, dictionary_lines):
        move_blocks, validation_blocks, game_blocks = [dictionary_lines], [], []
        seen = set()
        for job in jobs:
            kind, name = job[0].split()[:2]
            if kind == "TOPN":
                destination, totals, key = move_blocks, self.topn_totals, "jobs"
            elif kind == "VALIDATE":
                destination, totals, key = validation_blocks, self.validation_totals, "jobs"
            else:
                destination, totals = game_blocks, self.game_totals
                key = "games" if kind == "GAME" else "duplicates"
            totals[key] += 1
            error = self.job_error(job, seen)
            seen.add(name)
            if error:
                destination.append([f"{kind} {name}", "error " + error])
                totals["errors"] += 1
            elif kind == "TOPN":
                destination.append(self.topn(job))
            elif kind == "VALIDATE":
                destination.append(self.validate(job))
            elif kind == "GAME":
                destination.append(self.ordinary_game(job))
            else:
                destination.append(self.duplicate_game(job))
        summaries = ((move_blocks, self.topn_totals, ("jobs", "errors", "moves", "bingos")),
                     (validation_blocks, self.validation_totals, ("jobs", "errors", "moves", "valid", "invalid", "loss")),
                     (game_blocks, self.game_totals, ("games", "duplicates", "errors", "turns", "rounds", "plays", "exchanges", "passes", "bingos")))
        for blocks, totals, keys in summaries:
            blocks.append(["SUMMARY " + " ".join(f"{key}={totals[key]}" for key in keys)])
        return move_blocks, validation_blocks, game_blocks


def main():
    values, counts, weights, trie, jobs, dictionary_lines = read_inputs()
    program = Scrabble(values, counts, weights, trie)
    reports = program.process(jobs, dictionary_lines)
    output = Path("output")
    output.mkdir(exist_ok=True)
    for filename, blocks in zip(("moves.txt", "validation.txt", "game.txt"), reports):
        text = "\n\n".join("\n".join(block) for block in blocks) + "\n"
        (output / filename).write_text(text, encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
