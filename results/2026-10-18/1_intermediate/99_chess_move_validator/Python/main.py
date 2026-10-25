import re
import sys
from dataclasses import dataclass
from functools import cached_property
from typing import NamedTuple

FILES = 'abcdefgh'
RANKS = '12345678'
PIECE_LETTERS = 'KQRBNPkqrbnp'
PROMOTION_TYPES = 'QRBN'
INITIAL_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
PERFT_FIELDS = ('nodes', 'captures', 'ep', 'castles', 'promotions', 'checks', 'mates')

ROOK_DIRECTIONS = ((0, 1), (0, -1), (-1, 0), (1, 0))
BISHOP_DIRECTIONS = ((1, 1), (-1, 1), (1, -1), (-1, -1))
KNIGHT_STEPS = ((1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2))
KING_STEPS = ROOK_DIRECTIONS + BISHOP_DIRECTIONS


class Move(NamedTuple):
    source: int
    target: int
    promotion: str | None = None

    def uci(self):
        promotion = self.promotion.lower() if self.promotion else ''
        return square_name(self.source) + square_name(self.target) + promotion


class CastlingRule(NamedTuple):
    king_square: int
    rook_square: int
    king_target: int
    rook_target: int
    path: tuple


CASTLING_RULES = {
    'K': CastlingRule(4, 7, 6, 5, (5, 6)),
    'Q': CastlingRule(4, 0, 2, 3, (1, 2, 3)),
    'k': CastlingRule(60, 63, 62, 61, (61, 62)),
    'q': CastlingRule(60, 56, 58, 59, (57, 58, 59)),
}


class MoveRecord(NamedTuple):
    san: str
    uci: str
    captured: str


class SanRequest(NamedTuple):
    kind: str
    target: int
    capture: bool
    file_hint: str
    rank_hint: str
    promotion: str | None


class FenError(Exception):
    pass


class IllegalMoveError(Exception):
    pass


class ArgumentError(Exception):
    pass


def square_name(square):
    return FILES[square % 8] + RANKS[square // 8]


def parse_square(text):
    if len(text) == 2 and text[0] in FILES and text[1] in RANKS:
        return RANKS.index(text[1]) * 8 + FILES.index(text[0])
    return None


def parse_number(text, low, high):
    if not re.fullmatch(r'0|[1-9][0-9]*', text):
        return None
    value = int(text)
    return value if low <= value <= high else None


def color_of(piece):
    return 'w' if piece.isupper() else 'b'


def opponent(color):
    return 'b' if color == 'w' else 'w'


def colored(kind, color):
    return kind if color == 'w' else kind.lower()


def pawn_step(color):
    return 8 if color == 'w' else -8


def castling_right(color, kingside):
    return colored('K' if kingside else 'Q', color)


def shift(square, file_step, rank_step):
    file = square % 8 + file_step
    rank = square // 8 + rank_step
    if 0 <= file < 8 and 0 <= rank < 8:
        return rank * 8 + file
    return None


def step_targets(square, steps):
    targets = (shift(square, file_step, rank_step) for file_step, rank_step in steps)
    return [target for target in targets if target is not None]


def ray(square, file_step, rank_step):
    squares = []
    current = shift(square, file_step, rank_step)
    while current is not None:
        squares.append(current)
        current = shift(current, file_step, rank_step)
    return squares


KNIGHT_TARGETS = [step_targets(square, KNIGHT_STEPS) for square in range(64)]
KING_TARGETS = [step_targets(square, KING_STEPS) for square in range(64)]
PAWN_TARGETS = {
    'w': [step_targets(square, ((-1, 1), (1, 1))) for square in range(64)],
    'b': [step_targets(square, ((-1, -1), (1, -1))) for square in range(64)],
}
ROOK_RAYS = [[ray(square, *step) for step in ROOK_DIRECTIONS] for square in range(64)]
BISHOP_RAYS = [[ray(square, *step) for step in BISHOP_DIRECTIONS] for square in range(64)]


def piece_targets(board, square):
    kind = board[square].upper()
    if kind == 'N':
        return KNIGHT_TARGETS[square]
    if kind == 'K':
        return KING_TARGETS[square]
    lines = []
    if kind in 'RQ':
        lines += ROOK_RAYS[square]
    if kind in 'BQ':
        lines += BISHOP_RAYS[square]
    targets = []
    for line in lines:
        for target in line:
            targets.append(target)
            if board[target] is not None:
                break
    return targets


def attackers(board, target, color):
    pawn, knight, bishop, rook, queen, king = (colored(kind, color) for kind in 'PNBRQK')
    found = [square for square in PAWN_TARGETS[opponent(color)][target] if board[square] == pawn]
    found += [square for square in KNIGHT_TARGETS[target] if board[square] == knight]
    found += [square for square in KING_TARGETS[target] if board[square] == king]
    for rays, slider in ((ROOK_RAYS, rook), (BISHOP_RAYS, bishop)):
        for line in rays[target]:
            for square in line:
                piece = board[square]
                if piece is not None:
                    if piece in (slider, queen):
                        found.append(square)
                    break
    return found


@dataclass
class Position:
    board: list
    side: str
    castling: str
    ep_square: int | None
    halfmove: int
    fullmove: int

    def king_square(self, color):
        return self.board.index(colored('K', color))

    def in_check(self, color=None):
        color = color or self.side
        return bool(attackers(self.board, self.king_square(color), opponent(color)))

    def is_castling(self, move):
        return self.board[move.source].upper() == 'K' and abs(move.target - move.source) == 2

    def is_en_passant(self, move):
        return (
            self.board[move.source].upper() == 'P'
            and move.source % 8 != move.target % 8
            and self.board[move.target] is None
        )

    def is_capture(self, move):
        return self.board[move.target] is not None or self.is_en_passant(move)

    def captured_piece(self, move):
        occupant = self.board[move.target]
        if occupant is not None:
            return occupant.lower()
        return 'p' if self.is_en_passant(move) else '-'

    def play(self, move):
        board = self.board.copy()
        piece = board[move.source]
        kind = piece.upper()
        if self.is_en_passant(move):
            board[move.target - pawn_step(self.side)] = None
        if self.is_castling(move):
            rule = CASTLING_RULES[castling_right(self.side, move.target > move.source)]
            board[rule.rook_target] = board[rule.rook_square]
            board[rule.rook_square] = None
        board[move.target] = colored(move.promotion, self.side) if move.promotion else piece
        board[move.source] = None
        castling = self.castling
        if kind == 'K':
            castling = ''.join(right for right in castling if color_of(right) != self.side)
        castling = ''.join(
            right for right in castling
            if CASTLING_RULES[right].rook_square not in (move.source, move.target)
        )
        double_push = kind == 'P' and abs(move.target - move.source) == 16
        return Position(
            board=board,
            side=opponent(self.side),
            castling=castling,
            ep_square=(move.source + move.target) // 2 if double_push else None,
            halfmove=0 if kind == 'P' or self.is_capture(move) else self.halfmove + 1,
            fullmove=self.fullmove + 1 if self.side == 'b' else self.fullmove,
        )

    def pseudo_legal_moves(self):
        moves = []
        for square, piece in enumerate(self.board):
            if piece is None or color_of(piece) != self.side:
                continue
            if piece.upper() == 'P':
                moves.extend(self.pawn_moves(square))
                continue
            for target in piece_targets(self.board, square):
                occupant = self.board[target]
                if occupant is None or color_of(occupant) != self.side:
                    moves.append(Move(square, target))
        return moves

    def pawn_moves(self, square):
        step = pawn_step(self.side)
        start_rank, last_rank = (1, 7) if self.side == 'w' else (6, 0)
        targets = []
        if self.board[square + step] is None:
            targets.append(square + step)
            if square // 8 == start_rank and self.board[square + 2 * step] is None:
                targets.append(square + 2 * step)
        for target in PAWN_TARGETS[self.side][square]:
            occupant = self.board[target]
            enemy = occupant is not None and color_of(occupant) != self.side
            if enemy or target == self.ep_square:
                targets.append(target)
        moves = []
        for target in targets:
            if target // 8 == last_rank:
                moves.extend(Move(square, target, kind) for kind in PROMOTION_TYPES)
            else:
                moves.append(Move(square, target))
        return moves

    def castling_move(self, kingside):
        rule = CASTLING_RULES[castling_right(self.side, kingside)]
        return Move(rule.king_square, rule.king_target)

    def castling_problem(self, kingside):
        right = castling_right(self.side, kingside)
        rule = CASTLING_RULES[right]
        if right not in self.castling:
            return 'no castling right'
        if any(self.board[square] is not None for square in rule.path):
            return 'path blocked'
        if self.in_check():
            return 'in check'
        if attackers(self.board, rule.rook_target, opponent(self.side)):
            return 'through check'
        if self.play(self.castling_move(kingside)).in_check(self.side):
            return 'into check'
        return None

    def successors(self):
        for move in self.pseudo_legal_moves():
            after = self.play(move)
            if not after.in_check(self.side):
                yield move, after
        for kingside in (True, False):
            if self.castling_problem(kingside) is None:
                move = self.castling_move(kingside)
                yield move, self.play(move)

    @cached_property
    def legal_moves(self):
        return [move for move, _ in self.successors()]

    def check_mark(self, move):
        after = self.play(move)
        if not after.in_check():
            return ''
        return '+' if after.legal_moves else '#'

    def disambiguation(self, move):
        piece = self.board[move.source]
        others = [
            other.source for other in self.legal_moves
            if other.target == move.target
            and other.source != move.source
            and self.board[other.source] == piece
        ]
        if not others:
            return ''
        if all(square % 8 != move.source % 8 for square in others):
            return FILES[move.source % 8]
        if all(square // 8 != move.source // 8 for square in others):
            return RANKS[move.source // 8]
        return square_name(move.source)

    def san(self, move):
        piece = self.board[move.source]
        target = square_name(move.target)
        if self.is_castling(move):
            text = 'O-O' if move.target > move.source else 'O-O-O'
        elif piece.upper() == 'P':
            prefix = FILES[move.source % 8] + 'x' if self.is_capture(move) else ''
            promotion = '=' + move.promotion if move.promotion else ''
            text = prefix + target + promotion
        else:
            capture = 'x' if self.is_capture(move) else ''
            text = piece.upper() + self.disambiguation(move) + capture + target
        return text + self.check_mark(move)

    @cached_property
    def key(self):
        ep_square = self.ep_square
        if ep_square is not None and not any(map(self.is_en_passant, self.legal_moves)):
            ep_square = None
        return tuple(self.board), self.side, self.castling, ep_square

    def state(self):
        if self.in_check():
            return 'check' if self.legal_moves else 'checkmate'
        return 'normal' if self.legal_moves else 'stalemate'

    def insufficient_material(self):
        others = [
            (square, piece.upper()) for square, piece in enumerate(self.board)
            if piece is not None and piece.upper() != 'K'
        ]
        if any(kind in 'PRQ' for _, kind in others):
            return False
        if len(others) <= 1:
            return True
        square_colors = {(square % 8 + square // 8) % 2 for square, _ in others}
        return all(kind == 'B' for _, kind in others) and len(square_colors) == 1

    def pins(self):
        enemy = opponent(self.side)
        king = self.king_square(self.side)
        found = []
        for rays, slider in ((ROOK_RAYS, 'R'), (BISHOP_RAYS, 'B')):
            pinners = (colored(slider, enemy), colored('Q', enemy))
            for line in rays[king]:
                occupied = [square for square in line if self.board[square] is not None]
                if len(occupied) < 2:
                    continue
                pinned, pinner = occupied[:2]
                if color_of(self.board[pinned]) == self.side and self.board[pinner] in pinners:
                    found.append((pinned, pinner))
        return sorted(found)

    def fen(self):
        rows = []
        for rank in range(7, -1, -1):
            cells = ''.join(piece or '1' for piece in self.board[rank * 8:rank * 8 + 8])
            rows.append(re.sub(r'1+', lambda run: str(len(run.group())), cells))
        ep = '-' if self.ep_square is None else square_name(self.ep_square)
        fields = [
            '/'.join(rows),
            self.side,
            self.castling or '-',
            ep,
            str(self.halfmove),
            str(self.fullmove),
        ]
        return ' '.join(fields)


def parse_rank(text):
    squares = []
    previous_digit = False
    for char in text:
        if char in '12345678':
            if previous_digit:
                return None
            squares.extend([None] * int(char))
            previous_digit = True
        elif char in PIECE_LETTERS:
            squares.append(char)
            previous_digit = False
        else:
            return None
    return squares if len(squares) == 8 else None


def valid_en_passant(board, side, square):
    step = pawn_step(side)
    expected_rank, enemy_pawn = (5, 'p') if side == 'w' else (2, 'P')
    return (
        square // 8 == expected_rank
        and board[square] is None
        and board[square + step] is None
        and board[square - step] == enemy_pawn
    )


def parse_fen(fields):
    if len(fields) != 6:
        raise FenError('fields')
    placement, side, castling, ep_field, halfmove_field, fullmove_field = fields
    rows = [parse_rank(row) for row in placement.split('/')]
    if len(rows) != 8 or None in rows:
        raise FenError('placement')
    board = [piece for row in reversed(rows) for piece in row]
    if board.count('K') != 1 or board.count('k') != 1:
        raise FenError('kings')
    if any(piece in ('P', 'p') for piece in board[:8] + board[56:]):
        raise FenError('pawns')
    if side not in ('w', 'b'):
        raise FenError('side')
    if castling != '-' and not re.fullmatch(r'K?Q?k?q?', castling):
        raise FenError('castling')
    rights = '' if castling == '-' else castling
    for right in rights:
        rule = CASTLING_RULES[right]
        color = color_of(right)
        if board[rule.king_square] != colored('K', color):
            raise FenError('castling')
        if board[rule.rook_square] != colored('R', color):
            raise FenError('castling')
    ep_square = None
    if ep_field != '-':
        ep_square = parse_square(ep_field)
        if ep_square is None or not valid_en_passant(board, side, ep_square):
            raise FenError('en passant')
    halfmove = parse_number(halfmove_field, 0, 999)
    fullmove = parse_number(fullmove_field, 1, 999)
    if halfmove is None or fullmove is None or (ep_square is not None and halfmove != 0):
        raise FenError('clocks')
    position = Position(board, side, rights, ep_square, halfmove, fullmove)
    if position.in_check(opponent(side)):
        raise FenError('check')
    return position


def parse_san_body(body):
    promotion = None
    if len(body) >= 2 and body[-2] == '=':
        promotion = body[-1]
        if promotion not in PROMOTION_TYPES:
            raise IllegalMoveError('syntax')
        body = body[:-2]
    target = parse_square(body[-2:])
    if target is None:
        raise IllegalMoveError('syntax')
    body = body[:-2]
    capture = body.endswith('x')
    if capture:
        body = body[:-1]
    if body and body[0] in 'KQRBN':
        hints = re.fullmatch(r'([a-h]?)([1-8]?)', body[1:])
        if hints is None or promotion is not None:
            raise IllegalMoveError('syntax')
        return SanRequest(body[0], target, capture, hints[1], hints[2], promotion)
    if not re.fullmatch('[a-h]' if capture else '', body):
        raise IllegalMoveError('syntax')
    return SanRequest('P', target, capture, body, '', promotion)


def find_san_move(position, request):
    def matches(move):
        return (
            position.board[move.source].upper() == request.kind
            and move.target == request.target
            and not position.is_castling(move)
            and (not request.file_hint or FILES[move.source % 8] == request.file_hint)
            and (not request.rank_hint or RANKS[move.source // 8] == request.rank_hint)
            and (request.kind != 'P' or (move.source % 8 != move.target % 8) == request.capture)
        )

    candidates = [move for move in position.legal_moves if matches(move)]
    if not candidates:
        if any(matches(move) for move in position.pseudo_legal_moves()):
            raise IllegalMoveError('leaves king in check')
        raise IllegalMoveError('no such move')
    if len({move.source for move in candidates}) > 1:
        raise IllegalMoveError('ambiguous')
    found = candidates[0]
    if position.is_capture(found) != request.capture:
        raise IllegalMoveError('capture mark')
    if found.promotion and not request.promotion:
        raise IllegalMoveError('missing promotion')
    if request.promotion and not found.promotion:
        raise IllegalMoveError('invalid promotion')
    hint = request.file_hint + request.rank_hint
    if request.kind != 'P' and hint != position.disambiguation(found):
        raise IllegalMoveError('disambiguation')
    return Move(found.source, found.target, request.promotion)


def read_san(position, text):
    mark = text[-1] if text[-1] in '+#' else ''
    body = text[:-1] if mark else text
    request = None if body in ('O-O', 'O-O-O') else parse_san_body(body)
    if not position.legal_moves:
        raise IllegalMoveError('game over')
    if request is None:
        kingside = body == 'O-O'
        problem = position.castling_problem(kingside)
        if problem is not None:
            raise IllegalMoveError(problem)
        move = position.castling_move(kingside)
    else:
        move = find_san_move(position, request)
    if position.check_mark(move) != mark:
        raise IllegalMoveError('check mark')
    return move


def read_uci(position, text):
    source = parse_square(text[:2])
    target = parse_square(text[2:4])
    valid = (
        len(text) in (4, 5)
        and source is not None
        and target is not None
        and text[4:] in ('', 'q', 'r', 'b', 'n')
    )
    if not valid:
        raise IllegalMoveError('syntax')
    promotion = text[4:].upper() or None
    if not position.legal_moves:
        raise IllegalMoveError('game over')
    piece = position.board[source]
    if piece is None or color_of(piece) != position.side:
        raise IllegalMoveError('no piece')
    candidates = [
        move for move in position.legal_moves if move.source == source and move.target == target
    ]
    if not candidates:
        pseudo_legal = position.pseudo_legal_moves()
        if any(move.source == source and move.target == target for move in pseudo_legal):
            raise IllegalMoveError('leaves king in check')
        raise IllegalMoveError('no such move')
    if candidates[0].promotion and not promotion:
        raise IllegalMoveError('missing promotion')
    if promotion and not candidates[0].promotion:
        raise IllegalMoveError('invalid promotion')
    return Move(source, target, promotion)


def perft(position, depth):
    if depth == 0:
        return 1
    return sum(perft(child, depth - 1) for _, child in position.successors())


def perft_statistics(position, depth):
    stats = dict.fromkeys(PERFT_FIELDS, 0)

    def visit(node, remaining):
        for move, child in node.successors():
            if remaining > 1:
                visit(child, remaining - 1)
                continue
            stats['nodes'] += 1
            stats['captures'] += node.is_capture(move)
            stats['ep'] += node.is_en_passant(move)
            stats['castles'] += node.is_castling(move)
            stats['promotions'] += move.promotion is not None
            if child.in_check():
                stats['checks'] += 1
                stats['mates'] += not child.legal_moves

    visit(position, depth)
    return stats


class Game:
    def __init__(self, start=None, loaded=False):
        self.positions = [start or parse_fen(INITIAL_FEN.split(' '))]
        self.records = []
        self.loaded = loaded

    @property
    def current(self):
        return self.positions[-1]

    def play(self, move):
        position = self.current
        record = MoveRecord(position.san(move), move.uci(), position.captured_piece(move))
        self.records.append(record)
        self.positions.append(position.play(move))

    def undo(self, count):
        del self.records[-count:]
        del self.positions[-count:]

    def repetition_count(self):
        key = self.current.key
        return sum(position.key == key for position in self.positions)

    def draw_marks(self):
        position = self.current
        marks = []
        if position.halfmove >= 100:
            marks.append('fifty')
        if self.repetition_count() >= 3:
            marks.append('threefold')
        if position.insufficient_material():
            marks.append('insufficient')
        return marks

    def result(self):
        position = self.current
        state = position.state()
        if state == 'checkmate':
            return '1-0' if position.side == 'b' else '0-1'
        if state == 'stalemate' or self.draw_marks():
            return '1/2-1/2'
        return '*'


def require_no_arguments(args):
    if args:
        raise ArgumentError


def single_argument(args):
    if len(args) != 1:
        raise ArgumentError
    return args[0]


def square_argument(text):
    square = parse_square(text)
    if square is None:
        raise ArgumentError
    return square


def number_argument(args, low, high):
    value = parse_number(single_argument(args), low, high)
    if value is None:
        raise ArgumentError
    return value


class Session:
    def __init__(self):
        self.game = Game()
        self.commands = {
            'NEW': self.do_new,
            'LOAD': self.do_load,
            'FEN': self.do_fen,
            'BOARD': self.do_board,
            'MOVE': self.do_move,
            'UCI': self.do_uci,
            'LEGAL': self.do_legal,
            'STATUS': self.do_status,
            'UNDO': self.do_undo,
            'PERFT': self.do_perft,
            'DIVIDE': self.do_divide,
            'ATTACKS': self.do_attacks,
            'PINS': self.do_pins,
            'HISTORY': self.do_history,
            'PGN': self.do_pgn,
        }

    def execute(self, line):
        name, *args = line.split(' ')
        command = self.commands.get(name)
        if command is None:
            print('ERROR unknown command')
            return
        try:
            command(args)
        except ArgumentError:
            print('ERROR bad arguments')

    def do_new(self, args):
        require_no_arguments(args)
        self.game = Game()
        print('OK')

    def do_load(self, args):
        try:
            position = parse_fen(args)
        except FenError as error:
            print(f'ERROR bad fen ({error})')
            return
        self.game = Game(position, loaded=True)
        print('OK')

    def do_fen(self, args):
        require_no_arguments(args)
        print(self.game.current.fen())

    def do_board(self, args):
        require_no_arguments(args)
        board = self.game.current.board
        for rank in range(7, -1, -1):
            print(RANKS[rank], *(piece or '.' for piece in board[rank * 8:rank * 8 + 8]))
        print('  ' + ' '.join(FILES))

    def do_move(self, args):
        if not args:
            raise ArgumentError
        for number, text in enumerate(args, 1):
            try:
                move = read_san(self.game.current, text)
            except IllegalMoveError as error:
                print(f'ILLEGAL move {number}: {text} ({error})')
                return
            self.game.play(move)
        print('OK')

    def do_uci(self, args):
        if not args:
            raise ArgumentError
        played = []
        failure = None
        for number, text in enumerate(args, 1):
            try:
                move = read_uci(self.game.current, text)
            except IllegalMoveError as error:
                failure = f'ILLEGAL move {number}: {text} ({error})'
                break
            self.game.play(move)
            played.append(self.game.records[-1].san)
        if played:
            print('san', *played)
        if failure:
            print(failure)

    def do_legal(self, args):
        if len(args) > 1:
            raise ArgumentError
        source = square_argument(args[0]) if args else None
        position = self.game.current
        sans = sorted(
            position.san(move) for move in position.legal_moves
            if source is None or move.source == source
        )
        print('legal', len(sans), *sans)

    def do_status(self, args):
        require_no_arguments(args)
        position = self.game.current
        side = 'white' if position.side == 'w' else 'black'
        repetitions = self.game.repetition_count()
        print('status', side, position.state(), 'rep', repetitions, *self.game.draw_marks())

    def do_undo(self, args):
        count = number_argument(args, 1, 9999)
        if count > len(self.game.records):
            print('ERROR cannot undo')
            return
        self.game.undo(count)
        print('OK')

    def do_perft(self, args):
        depth = number_argument(args, 1, 3)
        stats = perft_statistics(self.game.current, depth)
        print('perft', depth, *(f'{field} {stats[field]}' for field in PERFT_FIELDS))

    def do_divide(self, args):
        depth = number_argument(args, 1, 3)
        position = self.game.current
        counts = sorted(
            (position.san(move), perft(child, depth - 1))
            for move, child in position.successors()
        )
        for san, count in counts:
            print(san, count)
        print('total', sum(count for _, count in counts))

    def do_attacks(self, args):
        square = square_argument(single_argument(args))
        board = self.game.current.board
        words = ['attacks', args[0]]
        for color, name in (('w', 'white'), ('b', 'black')):
            found = sorted(attackers(board, square, color))
            words += [name, str(len(found)), *map(square_name, found)]
        print(*words)

    def do_pins(self, args):
        require_no_arguments(args)
        pins = self.game.current.pins()
        entries = [f'{square_name(pinned)}-{square_name(pinner)}' for pinned, pinner in pins]
        print('pins', len(pins), *entries)

    def do_history(self, args):
        require_no_arguments(args)
        records = self.game.records
        print('history', len(records))
        for number, record in enumerate(records, 1):
            print(number, record.uci, record.san, record.captured)

    def do_pgn(self, args):
        require_no_arguments(args)
        game = self.game
        result = game.result()
        print(f'[Result "{result}"]')
        if game.loaded:
            print('[SetUp "1"]')
            print(f'[FEN "{game.positions[0].fen()}"]')
        words = []
        for index, record in enumerate(game.records):
            position = game.positions[index]
            if position.side == 'w':
                words.append(f'{position.fullmove}.')
            elif index == 0:
                words.append(f'{position.fullmove}...')
            words.append(record.san)
        print(*words, result)


def main():
    lines = sys.stdin.read().splitlines()
    session = Session()
    for line in lines[1:int(lines[0]) + 1]:
        session.execute(line)


if __name__ == '__main__':
    main()
