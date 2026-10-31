#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_MOVES 512

typedef struct {
    char board[64];
    char side;
    unsigned rights;
    int ep;
    int half;
    int full;
} Position;

typedef struct {
    int from;
    int to;
    char promotion;
} Move;

typedef struct {
    Move data[MAX_MOVES];
    int count;
} MoveList;

typedef struct {
    char san[32];
    char uci[7];
    char captured;
} Record;

typedef struct {
    Position *positions;
    Record *records;
    int capacity;
    int count;
    int loaded;
} Game;

typedef struct {
    long long nodes;
    long long captures;
    long long ep;
    long long castles;
    long long promotions;
    long long checks;
    long long mates;
} Perft;

typedef struct {
    char text[32];
    long long value;
} Labeled;

static const int knight_offsets[8][2] = {{1, 2},   {2, 1},   {2, -1}, {1, -2},
                                         {-1, -2}, {-2, -1}, {-2, 1}, {-1, 2}};
static const int directions[8][2] = {{0, 1}, {0, -1}, {-1, 0}, {1, 0},
                                     {1, 1}, {-1, 1}, {1, -1}, {-1, -1}};
static const char *initial_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

static char opposite(char side) {
    return side == 'w' ? 'b' : 'w';
}
static char color(char piece) {
    return isupper((unsigned char)piece) ? 'w' : 'b';
}
static char upper(char piece) {
    return (char)toupper((unsigned char)piece);
}
static char colored(char piece, char side) {
    return side == 'w' ? piece : (char)tolower((unsigned char)piece);
}
static int pawn_step(char side) {
    return side == 'w' ? 8 : -8;
}
static int file_of(int square) {
    return square % 8;
}
static int rank_of(int square) {
    return square / 8;
}

static int parse_square(const char *text) {
    if (strlen(text) != 2 || text[0] < 'a' || text[0] > 'h' || text[1] < '1' || text[1] > '8')
        return -1;
    return 8 * (text[1] - '1') + text[0] - 'a';
}

static void square_name(int square, char out[3]) {
    out[0] = (char)('a' + file_of(square));
    out[1] = (char)('1' + rank_of(square));
    out[2] = '\0';
}

static int shifted(int square, int dx, int dy) {
    int x = file_of(square) + dx, y = rank_of(square) + dy;
    return x >= 0 && x < 8 && y >= 0 && y < 8 ? 8 * y + x : -1;
}

static int number(const char *word, int low, int high) {
    if (!*word || (word[0] == '0' && word[1]))
        return -1;
    int value = 0;
    for (const char *p = word; *p; ++p) {
        if (!isdigit((unsigned char)*p))
            return -1;
        value = value * 10 + *p - '0';
        if (value > high)
            return -1;
    }
    return value >= low ? value : -1;
}

static void push_move(MoveList *list, int from, int to, char promotion) {
    if (list->count < MAX_MOVES)
        list->data[list->count++] = (Move){from, to, promotion};
}

static int piece_attacks(const Position *p, int from, int to) {
    char piece = p->board[from];
    if (piece == '.' || from == to)
        return 0;
    int dx = file_of(to) - file_of(from), dy = rank_of(to) - rank_of(from);
    int ax = abs(dx), ay = abs(dy);
    char kind = upper(piece);
    if (kind == 'P')
        return ax == 1 && dy == (color(piece) == 'w' ? 1 : -1);
    if (kind == 'N')
        return (ax == 1 && ay == 2) || (ax == 2 && ay == 1);
    if (kind == 'K')
        return ax <= 1 && ay <= 1;
    int straight = (dx == 0 || dy == 0), diagonal = ax == ay;
    if (kind == 'R' && !straight)
        return 0;
    if (kind == 'B' && !diagonal)
        return 0;
    if (kind == 'Q' && !straight && !diagonal)
        return 0;
    int step_x = (dx > 0) - (dx < 0), step_y = (dy > 0) - (dy < 0);
    for (int current = shifted(from, step_x, step_y); current != to;
         current = shifted(current, step_x, step_y)) {
        if (current < 0 || p->board[current] != '.')
            return 0;
    }
    return 1;
}

static int attacks(const Position *p, int square, char by_side, int *squares) {
    int count = 0;
    for (int from = 0; from < 64; ++from) {
        if (p->board[from] != '.' && color(p->board[from]) == by_side &&
            piece_attacks(p, from, square)) {
            if (squares)
                squares[count] = from;
            ++count;
        }
    }
    return count;
}

static int in_check(const Position *p, char side) {
    char king = colored('K', side);
    for (int square = 0; square < 64; ++square)
        if (p->board[square] == king)
            return attacks(p, square, opposite(side), NULL) != 0;
    return 0;
}

static int is_castling(const Position *p, Move m) {
    return upper(p->board[m.from]) == 'K' && abs(m.to - m.from) == 2;
}

static int is_enpassant(const Position *p, Move m) {
    return upper(p->board[m.from]) == 'P' && file_of(m.from) != file_of(m.to) &&
           p->board[m.to] == '.';
}

static int is_capture(const Position *p, Move m) {
    return p->board[m.to] != '.' || is_enpassant(p, m);
}

static char captured_piece(const Position *p, Move m) {
    if (p->board[m.to] != '.')
        return (char)tolower((unsigned char)p->board[m.to]);
    return is_enpassant(p, m) ? 'p' : '-';
}

static int castle_right(char side, int kingside) {
    if (side == 'w')
        return kingside ? 1 : 2;
    return kingside ? 4 : 8;
}

static Move castle_move(char side, int kingside) {
    int base = side == 'w' ? 0 : 56;
    return (Move){base + 4, base + (kingside ? 6 : 2), 0};
}

static Position played(const Position *p, Move m) {
    Position q = *p;
    char piece = q.board[m.from], kind = upper(piece);
    int capture = is_capture(p, m);
    if (is_enpassant(p, m))
        q.board[m.to - pawn_step(p->side)] = '.';
    if (is_castling(p, m)) {
        int base = p->side == 'w' ? 0 : 56;
        int rook_from = base + (m.to > m.from ? 7 : 0);
        int rook_to = base + (m.to > m.from ? 5 : 3);
        q.board[rook_to] = q.board[rook_from];
        q.board[rook_from] = '.';
    }
    q.board[m.to] = m.promotion ? colored(m.promotion, p->side) : piece;
    q.board[m.from] = '.';
    if (kind == 'K')
        q.rights &= ~(unsigned)(p->side == 'w' ? 3 : 12);
    if (m.from == 7 || m.to == 7)
        q.rights &= ~1u;
    if (m.from == 0 || m.to == 0)
        q.rights &= ~2u;
    if (m.from == 63 || m.to == 63)
        q.rights &= ~4u;
    if (m.from == 56 || m.to == 56)
        q.rights &= ~8u;
    q.ep = kind == 'P' && abs(m.to - m.from) == 16 ? (m.from + m.to) / 2 : -1;
    q.half = kind == 'P' || capture ? 0 : p->half + 1;
    q.full = p->full + (p->side == 'b');
    q.side = opposite(p->side);
    return q;
}

static void promotion_moves(MoveList *list, int from, int to, char side) {
    if (rank_of(to) == (side == 'w' ? 7 : 0)) {
        const char *promotions = "QRBN";
        for (const char *p = promotions; *p; ++p)
            push_move(list, from, to, *p);
    } else
        push_move(list, from, to, 0);
}

static void pseudo_legal(const Position *p, MoveList *list) {
    list->count = 0;
    for (int from = 0; from < 64; ++from) {
        char piece = p->board[from];
        if (piece == '.' || color(piece) != p->side)
            continue;
        char kind = upper(piece);
        if (kind == 'P') {
            int forward = from + pawn_step(p->side);
            if (forward >= 0 && forward < 64 && p->board[forward] == '.') {
                promotion_moves(list, from, forward, p->side);
                int initial = p->side == 'w' ? 1 : 6;
                if (rank_of(from) == initial) {
                    int double_step = forward + pawn_step(p->side);
                    if (p->board[double_step] == '.')
                        push_move(list, from, double_step, 0);
                }
            }
            for (int dx = -1; dx <= 1; dx += 2) {
                int to = shifted(from, dx, p->side == 'w' ? 1 : -1);
                if (to < 0)
                    continue;
                if ((p->board[to] != '.' && color(p->board[to]) != p->side) || to == p->ep)
                    promotion_moves(list, from, to, p->side);
            }
        } else if (kind == 'N') {
            for (int i = 0; i < 8; ++i) {
                int to = shifted(from, knight_offsets[i][0], knight_offsets[i][1]);
                if (to >= 0 && (p->board[to] == '.' || color(p->board[to]) != p->side))
                    push_move(list, from, to, 0);
            }
        } else if (kind == 'K') {
            for (int i = 0; i < 8; ++i) {
                int to = shifted(from, directions[i][0], directions[i][1]);
                if (to >= 0 && (p->board[to] == '.' || color(p->board[to]) != p->side))
                    push_move(list, from, to, 0);
            }
        } else {
            for (int i = 0; i < 8; ++i) {
                if (kind == 'R' && i >= 4)
                    continue;
                if (kind == 'B' && i < 4)
                    continue;
                int dx = directions[i][0], dy = directions[i][1];
                for (int to = shifted(from, dx, dy); to >= 0; to = shifted(to, dx, dy)) {
                    char target = p->board[to];
                    if (target == '.' || color(target) != p->side)
                        push_move(list, from, to, 0);
                    if (target != '.')
                        break;
                }
            }
        }
    }
}

static const char *castling_problem(const Position *p, int kingside) {
    int right = castle_right(p->side, kingside);
    if (!(p->rights & (unsigned)right))
        return "no castling right";
    int base = p->side == 'w' ? 0 : 56;
    int begin = kingside ? 5 : 1, end = kingside ? 6 : 3;
    for (int i = begin; i <= end; ++i)
        if (p->board[base + i] != '.')
            return "path blocked";
    if (in_check(p, p->side))
        return "in check";
    if (attacks(p, base + (kingside ? 5 : 3), opposite(p->side), NULL))
        return "through check";
    Position next = played(p, castle_move(p->side, kingside));
    if (in_check(&next, p->side))
        return "into check";
    return NULL;
}

static void legal_moves(const Position *p, MoveList *list) {
    MoveList pseudo;
    pseudo_legal(p, &pseudo);
    list->count = 0;
    for (int i = 0; i < pseudo.count; ++i) {
        Move m = pseudo.data[i];
        Position q = played(p, m);
        if (!in_check(&q, p->side))
            push_move(list, m.from, m.to, m.promotion);
    }
    for (int side = 1; side >= 0; --side)
        if (!castling_problem(p, side)) {
            Move m = castle_move(p->side, side);
            push_move(list, m.from, m.to, 0);
        }
}

static char check_mark(const Position *p, Move m) {
    Position q = played(p, m);
    if (!in_check(&q, q.side))
        return 0;
    MoveList legal;
    legal_moves(&q, &legal);
    return legal.count ? '+' : '#';
}

static void disambiguation(const Position *p, Move m, char *out) {
    out[0] = 0;
    MoveList legal;
    legal_moves(p, &legal);
    int other_count = 0, same_file = 0, same_rank = 0;
    for (int i = 0; i < legal.count; ++i) {
        Move n = legal.data[i];
        if (n.from == m.from || n.to != m.to || is_castling(p, n) ||
            p->board[n.from] != p->board[m.from])
            continue;
        ++other_count;
        if (file_of(n.from) == file_of(m.from))
            same_file = 1;
        if (rank_of(n.from) == rank_of(m.from))
            same_rank = 1;
    }
    if (!other_count)
        return;
    if (!same_file) {
        out[0] = (char)('a' + file_of(m.from));
        out[1] = 0;
    } else if (!same_rank) {
        out[0] = (char)('1' + rank_of(m.from));
        out[1] = 0;
    } else
        square_name(m.from, out);
}

static void san(const Position *p, Move m, char out[32]) {
    char destination[3];
    square_name(m.to, destination);
    char kind = upper(p->board[m.from]);
    if (is_castling(p, m))
        strcpy(out, m.to > m.from ? "O-O" : "O-O-O");
    else if (kind == 'P') {
        if (is_capture(p, m))
            sprintf(out, "%cx%s", 'a' + file_of(m.from), destination);
        else
            strcpy(out, destination);
        if (m.promotion) {
            size_t length = strlen(out);
            sprintf(out + length, "=%c", m.promotion);
        }
    } else {
        char hint[3];
        disambiguation(p, m, hint);
        sprintf(out, "%c%s%s%s", kind, hint, is_capture(p, m) ? "x" : "", destination);
    }
    char mark = check_mark(p, m);
    if (mark) {
        size_t size = strlen(out);
        out[size] = mark;
        out[size + 1] = 0;
    }
}

static const char *read_san(const Position *p, const char *text, Move *out) {
    char word[256];
    if (strlen(text) >= sizeof(word))
        return "syntax";
    strcpy(word, text);
    size_t size = strlen(word);
    char mark = 0;
    if (size && (word[size - 1] == '+' || word[size - 1] == '#')) {
        mark = word[--size];
        word[size] = 0;
    }
    int castle = strcmp(word, "O-O") == 0 ? 1 : strcmp(word, "O-O-O") == 0 ? 0 : -1;
    char promotion = 0, piece = 'P', hint_file = 0, hint_rank = 0;
    int to = -1, capture = 0;
    if (castle < 0) {
        if (size >= 2 && word[size - 2] == '=') {
            promotion = word[size - 1];
            if (!strchr("QRBN", promotion))
                return "syntax";
            word[size -= 2] = 0;
        }
        if (size < 2)
            return "syntax";
        to = parse_square(word + size - 2);
        if (to < 0)
            return "syntax";
        word[size -= 2] = 0;
        if (size && word[size - 1] == 'x') {
            capture = 1;
            word[--size] = 0;
        }
        if (size && strchr("KQRBN", word[0])) {
            piece = word[0];
            if (promotion)
                return "syntax";
            const char *hints = word + 1;
            if (*hints >= 'a' && *hints <= 'h')
                hint_file = *hints++;
            if (*hints >= '1' && *hints <= '8')
                hint_rank = *hints++;
            if (*hints)
                return "syntax";
        } else {
            if (capture) {
                if (size != 1 || word[0] < 'a' || word[0] > 'h')
                    return "syntax";
                hint_file = word[0];
            } else if (size)
                return "syntax";
        }
    }
    MoveList legal;
    legal_moves(p, &legal);
    if (!legal.count)
        return "game over";
    Move selected = {0, 0, 0};
    if (castle >= 0) {
        const char *reason = castling_problem(p, castle);
        if (reason)
            return reason;
        selected = castle_move(p->side, castle);
    } else {
        MoveList matching;
        matching.count = 0;
        for (int i = 0; i < legal.count; ++i) {
            Move m = legal.data[i];
            if (upper(p->board[m.from]) != piece || m.to != to || is_castling(p, m))
                continue;
            if (hint_file && 'a' + file_of(m.from) != hint_file)
                continue;
            if (hint_rank && '1' + rank_of(m.from) != hint_rank)
                continue;
            if (piece == 'P' && ((file_of(m.from) != file_of(m.to)) != capture))
                continue;
            push_move(&matching, m.from, m.to, m.promotion);
        }
        if (!matching.count) {
            MoveList pseudo;
            pseudo_legal(p, &pseudo);
            for (int i = 0; i < pseudo.count; ++i) {
                Move m = pseudo.data[i];
                if (upper(p->board[m.from]) != piece || m.to != to)
                    continue;
                if (hint_file && 'a' + file_of(m.from) != hint_file)
                    continue;
                if (hint_rank && '1' + rank_of(m.from) != hint_rank)
                    continue;
                if (piece == 'P' && ((file_of(m.from) != file_of(m.to)) != capture))
                    continue;
                return "leaves king in check";
            }
            return "no such move";
        }
        int different_origins = 0;
        for (int i = 1; i < matching.count; ++i)
            if (matching.data[i].from != matching.data[0].from)
                different_origins = 1;
        if (different_origins)
            return "ambiguous";
        selected = matching.data[0];
        if (is_capture(p, selected) != capture)
            return "capture mark";
        if (selected.promotion && !promotion)
            return "missing promotion";
        if (promotion && !selected.promotion)
            return "invalid promotion";
        if (piece != 'P') {
            char disamb[3], given[3] = {0};
            disambiguation(p, selected, disamb);
            int length = 0;
            if (hint_file)
                given[length++] = hint_file;
            if (hint_rank)
                given[length++] = hint_rank;
            if (strcmp(disamb, given))
                return "disambiguation";
        }
        selected.promotion = promotion;
    }
    if (check_mark(p, selected) != mark)
        return "check mark";
    *out = selected;
    return NULL;
}

static const char *read_uci(const Position *p, const char *word, Move *out) {
    int length = (int)strlen(word);
    if (length != 4 && length != 5)
        return "syntax";
    char from_text[3] = {word[0], word[1], 0}, to_text[3] = {word[2], word[3], 0};
    int from = parse_square(from_text), to = parse_square(to_text);
    char promotion = length == 5 ? upper(word[4]) : 0;
    if (from < 0 || to < 0 || (length == 5 && !strchr("qrbn", word[4])))
        return "syntax";
    MoveList legal;
    legal_moves(p, &legal);
    if (!legal.count)
        return "game over";
    if (p->board[from] == '.' || color(p->board[from]) != p->side)
        return "no piece";
    int index = -1;
    for (int i = 0; i < legal.count; ++i) {
        if (legal.data[i].from == from && legal.data[i].to == to) {
            index = i;
            break;
        }
    }
    if (index < 0) {
        MoveList pseudo;
        pseudo_legal(p, &pseudo);
        for (int i = 0; i < pseudo.count; ++i)
            if (pseudo.data[i].from == from && pseudo.data[i].to == to)
                return "leaves king in check";
        return "no such move";
    }
    Move selected = legal.data[index];
    if (selected.promotion && !promotion)
        return "missing promotion";
    if (promotion && !selected.promotion)
        return "invalid promotion";
    selected.promotion = promotion;
    *out = selected;
    return NULL;
}

static int position_key_equal(const Position *a, const Position *b) {
    if (memcmp(a->board, b->board, 64) || a->side != b->side || a->rights != b->rights)
        return 0;
    int ep_a = a->ep, ep_b = b->ep;
    if (ep_a >= 0) {
        int possible = 0;
        MoveList moves;
        legal_moves(a, &moves);
        for (int i = 0; i < moves.count; ++i)
            if (is_enpassant(a, moves.data[i])) {
                possible = 1;
                break;
            }
        if (!possible)
            ep_a = -1;
    }
    if (ep_b >= 0) {
        int possible = 0;
        MoveList moves;
        legal_moves(b, &moves);
        for (int i = 0; i < moves.count; ++i)
            if (is_enpassant(b, moves.data[i])) {
                possible = 1;
                break;
            }
        if (!possible)
            ep_b = -1;
    }
    return ep_a == ep_b;
}

static int insufficient(const Position *p) {
    int other = 0, bishops = 0, bishop_color = -1;
    for (int s = 0; s < 64; ++s) {
        char kind = upper(p->board[s]);
        if (kind == '.' || kind == 'K')
            continue;
        if (strchr("PRQ", kind))
            return 0;
        other++;
        if (kind == 'B') {
            int parity = (file_of(s) + rank_of(s)) % 2;
            if (bishop_color < 0)
                bishop_color = parity;
            if (bishop_color != parity)
                return other <= 1;
            bishops++;
        }
    }
    return other <= 1 || other == bishops;
}

static const char *state_name(const Position *p) {
    MoveList legal;
    legal_moves(p, &legal);
    int check = in_check(p, p->side);
    if (!legal.count)
        return check ? "checkmate" : "stalemate";
    return check ? "check" : "normal";
}

static void position_fen(const Position *p, char *out) {
    char *dst = out;
    for (int row = 7; row >= 0; --row) {
        int empty = 0;
        for (int f = 0; f < 8; ++f) {
            char piece = p->board[row * 8 + f];
            if (piece == '.')
                ++empty;
            else {
                if (empty) {
                    *dst++ = (char)('0' + empty);
                    empty = 0;
                }
                *dst++ = piece;
            }
        }
        if (empty)
            *dst++ = (char)('0' + empty);
        if (row)
            *dst++ = '/';
    }
    *dst++ = ' ';
    *dst++ = p->side;
    *dst++ = ' ';
    const int rights[] = {1, 2, 4, 8};
    const char rights_text[] = "KQkq";
    int wrote_right = 0;
    for (int i = 0; i < 4; ++i)
        if (p->rights & (unsigned)rights[i]) {
            *dst++ = rights_text[i];
            wrote_right = 1;
        }
    if (!wrote_right)
        *dst++ = '-';
    *dst++ = ' ';
    if (p->ep < 0)
        *dst++ = '-';
    else {
        char name[3];
        square_name(p->ep, name);
        *dst++ = name[0];
        *dst++ = name[1];
    }
    sprintf(dst, " %d %d", p->half, p->full);
}

static const char *parse_fen(int argc, char **argv, Position *p) {
    if (argc != 6)
        return "fields";
    Position next = {.side = 'w', .rights = 0, .ep = -1, .half = 0, .full = 1};
    memset(next.board, '.', sizeof(next.board));
    const char *part = argv[0];
    int row = 7, file = 0, last_digit = 0;
    if (!*part)
        return "placement";
    for (const char *c = part;; ++c) {
        if (*c == '/' || *c == 0) {
            if (file != 8)
                return "placement";
            if (!*c)
                break;
            if (--row < 0)
                return "placement";
            file = last_digit = 0;
        } else if (*c >= '1' && *c <= '8') {
            if (last_digit)
                return "placement";
            file += *c - '0';
            if (file > 8)
                return "placement";
            last_digit = 1;
        } else {
            if (!strchr("KQRBNPkqrbnp", *c) || file >= 8)
                return "placement";
            next.board[row * 8 + file++] = *c;
            last_digit = 0;
        }
    }
    if (row != 0)
        return "placement";
    int white = 0, black = 0;
    for (int i = 0; i < 64; ++i) {
        white += next.board[i] == 'K';
        black += next.board[i] == 'k';
    }
    if (white != 1 || black != 1)
        return "kings";
    for (int i = 0; i < 8; ++i)
        if (upper(next.board[i]) == 'P' || upper(next.board[56 + i]) == 'P')
            return "pawns";
    if (strcmp(argv[1], "w") && strcmp(argv[1], "b"))
        return "side";
    next.side = argv[1][0];
    if (strcmp(argv[2], "-")) {
        int index = -1;
        const char *rights_order = "KQkq";
        for (const char *c = argv[2]; *c; ++c) {
            const char *found = strchr(rights_order, *c);
            if (!found)
                return "castling";
            int order = (int)(found - rights_order);
            if (order <= index)
                return "castling";
            index = order;
            int base = order < 2 ? 0 : 56;
            int king_pos = base + 4;
            int rook_pos = base + (order % 2 == 0 ? 7 : 0);
            if (next.board[king_pos] != (order < 2 ? 'K' : 'k') ||
                next.board[rook_pos] != (order < 2 ? 'R' : 'r'))
                return "castling";
            next.rights |= (unsigned)(1 << order);
        }
        if (!*argv[2])
            return "castling";
    }
    if (strcmp(argv[3], "-")) {
        next.ep = parse_square(argv[3]);
        if (next.ep < 0)
            return "en passant";
        int expected = next.side == 'w' ? 5 : 2;
        int step = pawn_step(next.side);
        if (rank_of(next.ep) != expected || next.board[next.ep] != '.' ||
            next.board[next.ep + step] != '.' ||
            next.board[next.ep - step] != colored('P', opposite(next.side)))
            return "en passant";
    }
    next.half = number(argv[4], 0, 999);
    next.full = number(argv[5], 1, 999);
    if (next.half < 0 || next.full < 0 || (next.ep >= 0 && next.half != 0))
        return "clocks";
    if (in_check(&next, opposite(next.side)))
        return "check";
    *p = next;
    return NULL;
}

static void game_start(Game *g, Position start, int loaded) {
    g->count = 0;
    g->loaded = loaded;
    if (!g->capacity) {
        g->capacity = 32;
        g->positions = malloc((size_t)(g->capacity + 1) * sizeof(Position));
        g->records = malloc((size_t)g->capacity * sizeof(Record));
        if (!g->positions || !g->records)
            exit(1);
    }
    g->positions[0] = start;
}

static Position *current(Game *g) {
    return &g->positions[g->count];
}

static void game_play(Game *g, Move m) {
    if (g->count >= g->capacity) {
        g->capacity *= 2;
        Position *positions = realloc(g->positions, (size_t)(g->capacity + 1) * sizeof(Position));
        Record *records = realloc(g->records, (size_t)g->capacity * sizeof(Record));
        if (!positions || !records)
            exit(1);
        g->positions = positions;
        g->records = records;
    }
    Position *p = current(g);
    Record *record = &g->records[g->count];
    san(p, m, record->san);
    char from[3], to[3];
    square_name(m.from, from);
    square_name(m.to, to);
    sprintf(record->uci, "%s%s%s", from, to,
            m.promotion ? (char[2]){(char)tolower((unsigned char)m.promotion), 0} : "");
    record->captured = captured_piece(p, m);
    Position next = played(p, m);
    ++g->count;
    g->positions[g->count] = next;
}

static int repetition(Game *g) {
    Position *p = current(g);
    int count = 0;
    for (int i = 0; i <= g->count; ++i)
        if (position_key_equal(&g->positions[i], p))
            count++;
    return count;
}

static int draw_marks(Game *g) {
    Position *p = current(g);
    return (p->half >= 100 ? 1 : 0) | (repetition(g) >= 3 ? 2 : 0) | (insufficient(p) ? 4 : 0);
}

static const char *game_result(Game *g) {
    Position *p = current(g);
    const char *state = state_name(p);
    if (!strcmp(state, "checkmate"))
        return p->side == 'b' ? "1-0" : "0-1";
    if (!strcmp(state, "stalemate") || draw_marks(g))
        return "1/2-1/2";
    return "*";
}

static long long perft(const Position *p, int depth, Perft *stats) {
    if (!depth)
        return 1;
    MoveList legal;
    legal_moves(p, &legal);
    long long total = 0;
    for (int i = 0; i < legal.count; ++i) {
        Move m = legal.data[i];
        Position next = played(p, m);
        if (depth == 1) {
            total++;
            if (stats) {
                stats->nodes++;
                stats->captures += is_capture(p, m);
                stats->ep += is_enpassant(p, m);
                stats->castles += is_castling(p, m);
                stats->promotions += m.promotion != 0;
                if (in_check(&next, next.side)) {
                    stats->checks++;
                    MoveList next_legal;
                    legal_moves(&next, &next_legal);
                    if (!next_legal.count)
                        stats->mates++;
                }
            }
        } else
            total += perft(&next, depth - 1, stats);
    }
    return total;
}

static int compare_labeled(const void *left, const void *right) {
    const Labeled *a = left, *b = right;
    return strcmp(a->text, b->text);
}

static int pinned_squares(const Position *p, int pairs[8][2]) {
    int king = -1;
    for (int i = 0; i < 64; ++i)
        if (p->board[i] == colored('K', p->side))
            king = i;
    if (king < 0)
        return 0;
    int count = 0;
    for (int dir = 0; dir < 8; ++dir) {
        int dx = directions[dir][0], dy = directions[dir][1];
        int friendly = -1;
        for (int square = shifted(king, dx, dy); square >= 0; square = shifted(square, dx, dy)) {
            char piece = p->board[square];
            if (piece == '.')
                continue;
            if (friendly < 0) {
                if (color(piece) != p->side)
                    break;
                friendly = square;
            } else {
                char kind = upper(piece);
                if (color(piece) != p->side &&
                    (kind == 'Q' || (dir < 4 ? kind == 'R' : kind == 'B'))) {
                    pairs[count][0] = friendly;
                    pairs[count][1] = square;
                    count++;
                }
                break;
            }
        }
    }
    for (int i = 0; i < count; ++i)
        for (int j = i + 1; j < count; ++j)
            if (pairs[i][0] > pairs[j][0]) {
                int a = pairs[i][0], b = pairs[i][1];
                pairs[i][0] = pairs[j][0];
                pairs[i][1] = pairs[j][1];
                pairs[j][0] = a;
                pairs[j][1] = b;
            }
    return count;
}

static void execute(Game *g, char *line) {
    char *args[256];
    int nargs = 0;
    char *command = strtok(line, " \r\n\t");
    if (!command)
        return;
    for (char *word = strtok(NULL, " \r\n\t"); word && nargs < 256; word = strtok(NULL, " \r\n\t"))
        args[nargs++] = word;
    const char *all =
        " NEW LOAD FEN BOARD MOVE UCI LEGAL STATUS UNDO PERFT DIVIDE ATTACKS PINS HISTORY PGN ";
    char find[64];
    snprintf(find, sizeof(find), " %s ", command);
    if (!strstr(all, find)) {
        puts("ERROR unknown command");
        return;
    }
    if (!strcmp(command, "LOAD")) {
        Position p;
        const char *problem = parse_fen(nargs, args, &p);
        if (problem)
            printf("ERROR bad fen (%s)\n", problem);
        else {
            game_start(g, p, 1);
            puts("OK");
        }
        return;
    }
    if ((!strcmp(command, "NEW") || !strcmp(command, "FEN") || !strcmp(command, "BOARD") ||
         !strcmp(command, "STATUS") || !strcmp(command, "PINS") || !strcmp(command, "HISTORY") ||
         !strcmp(command, "PGN")) &&
        nargs != 0) {
        puts("ERROR bad arguments");
        return;
    }
    if ((!strcmp(command, "MOVE") || !strcmp(command, "UCI")) && nargs == 0) {
        puts("ERROR bad arguments");
        return;
    }
    int square = -1;
    if (!strcmp(command, "LEGAL")) {
        if (nargs > 1 || (nargs == 1 && (square = parse_square(args[0])) < 0)) {
            puts("ERROR bad arguments");
            return;
        }
    }
    if (!strcmp(command, "ATTACKS")) {
        if (nargs != 1 || (square = parse_square(args[0])) < 0) {
            puts("ERROR bad arguments");
            return;
        }
    }
    int depth = -1;
    if (!strcmp(command, "UNDO") || !strcmp(command, "PERFT") || !strcmp(command, "DIVIDE")) {
        depth = nargs == 1 ? number(args[0], 1, !strcmp(command, "UNDO") ? 9999 : 3) : -1;
        if (depth < 0) {
            puts("ERROR bad arguments");
            return;
        }
    }
    Position *p = current(g);
    if (!strcmp(command, "NEW")) {
        char *fields[6];
        char buffer[256];
        strcpy(buffer, initial_fen);
        int count = 0;
        for (char *token = strtok(buffer, " "); token; token = strtok(NULL, " "))
            fields[count++] = token;
        Position initial;
        if (parse_fen(count, fields, &initial))
            exit(1);
        game_start(g, initial, 0);
        puts("OK");
    } else if (!strcmp(command, "FEN")) {
        char text[128];
        position_fen(p, text);
        puts(text);
    } else if (!strcmp(command, "BOARD")) {
        for (int row = 7; row >= 0; --row) {
            printf("%d", row + 1);
            for (int col = 0; col < 8; ++col)
                printf(" %c", p->board[row * 8 + col]);
            putchar('\n');
        }
        puts("  a b c d e f g h");
    } else if (!strcmp(command, "MOVE") || !strcmp(command, "UCI")) {
        int is_uci = !strcmp(command, "UCI");
        char error[256] = {0};
        char (*played_san)[32] = malloc((size_t)nargs * 32);
        if (!played_san)
            exit(1);
        int succeeded = 0;
        for (int i = 0; i < nargs; ++i) {
            Move m;
            const char *reason =
                is_uci ? read_uci(current(g), args[i], &m) : read_san(current(g), args[i], &m);
            if (reason) {
                snprintf(error, sizeof(error), "ILLEGAL move %d: %s (%s)", i + 1, args[i], reason);
                break;
            }
            game_play(g, m);
            if (is_uci)
                strcpy(played_san[succeeded++], g->records[g->count - 1].san);
        }
        if (is_uci && succeeded) {
            printf("san");
            for (int i = 0; i < succeeded; ++i)
                printf(" %s", played_san[i]);
            putchar('\n');
        }
        if (*error)
            puts(error);
        else if (!is_uci)
            puts("OK");
        free(played_san);
    } else if (!strcmp(command, "LEGAL")) {
        MoveList moves;
        legal_moves(p, &moves);
        Labeled rows[MAX_MOVES];
        int count = 0;
        for (int i = 0; i < moves.count; ++i) {
            if (square >= 0 && moves.data[i].from != square)
                continue;
            san(p, moves.data[i], rows[count++].text);
        }
        qsort(rows, (size_t)count, sizeof(Labeled), compare_labeled);
        printf("legal %d", count);
        for (int i = 0; i < count; ++i)
            printf(" %s", rows[i].text);
        putchar('\n');
    } else if (!strcmp(command, "STATUS")) {
        const char *state = state_name(p);
        int rep = repetition(g), draw = draw_marks(g);
        printf("status %s %s rep %d", p->side == 'w' ? "white" : "black", state, rep);
        if (draw & 1)
            printf(" fifty");
        if (draw & 2)
            printf(" threefold");
        if (draw & 4)
            printf(" insufficient");
        putchar('\n');
    } else if (!strcmp(command, "UNDO")) {
        if (depth > g->count)
            puts("ERROR cannot undo");
        else {
            g->count -= depth;
            puts("OK");
        }
    } else if (!strcmp(command, "PERFT")) {
        Perft info = {0};
        perft(p, depth, &info);
        printf(
            "perft %d nodes %lld captures %lld ep %lld castles %lld promotions %lld checks %lld mates %lld\n",
            depth, info.nodes, info.captures, info.ep, info.castles, info.promotions, info.checks,
            info.mates);
    } else if (!strcmp(command, "DIVIDE")) {
        MoveList moves;
        legal_moves(p, &moves);
        Labeled rows[MAX_MOVES];
        long long total = 0;
        for (int i = 0; i < moves.count; ++i) {
            san(p, moves.data[i], rows[i].text);
            Position next = played(p, moves.data[i]);
            rows[i].value = perft(&next, depth - 1, NULL);
            total += rows[i].value;
        }
        qsort(rows, (size_t)moves.count, sizeof(Labeled), compare_labeled);
        for (int i = 0; i < moves.count; ++i)
            printf("%s %lld\n", rows[i].text, rows[i].value);
        printf("total %lld\n", total);
    } else if (!strcmp(command, "ATTACKS")) {
        int white[64], black[64];
        int w = attacks(p, square, 'w', white), b = attacks(p, square, 'b', black);
        printf("attacks %s white %d", args[0], w);
        for (int i = 0; i < w; ++i) {
            char text[3];
            square_name(white[i], text);
            printf(" %s", text);
        }
        printf(" black %d", b);
        for (int i = 0; i < b; ++i) {
            char text[3];
            square_name(black[i], text);
            printf(" %s", text);
        }
        putchar('\n');
    } else if (!strcmp(command, "PINS")) {
        int pins[8][2];
        int count = pinned_squares(p, pins);
        printf("pins %d", count);
        for (int i = 0; i < count; ++i) {
            char a[3], b[3];
            square_name(pins[i][0], a);
            square_name(pins[i][1], b);
            printf(" %s-%s", a, b);
        }
        putchar('\n');
    } else if (!strcmp(command, "HISTORY")) {
        printf("history %d\n", g->count);
        for (int i = 0; i < g->count; ++i)
            printf("%d %s %s %c\n", i + 1, g->records[i].uci, g->records[i].san,
                   g->records[i].captured);
    } else if (!strcmp(command, "PGN")) {
        const char *result = game_result(g);
        printf("[Result \"%s\"]\n", result);
        if (g->loaded) {
            char fen[128];
            position_fen(&g->positions[0], fen);
            puts("[SetUp \"1\"]");
            printf("[FEN \"%s\"]\n", fen);
        }
        int written = 0;
        for (int i = 0; i < g->count; ++i) {
            Position *before = &g->positions[i];
            if (written)
                putchar(' ');
            if (before->side == 'w')
                printf("%d. %s", before->full, g->records[i].san);
            else if (i == 0)
                printf("%d... %s", before->full, g->records[i].san);
            else
                printf("%s", g->records[i].san);
            written = 1;
        }
        if (written)
            putchar(' ');
        puts(result);
    }
}

int main(void) {
    char first[256];
    if (!fgets(first, sizeof(first), stdin))
        return 0;
    int n = atoi(first);
    char *fields[6], initial[256];
    strcpy(initial, initial_fen);
    int nf = 0;
    for (char *token = strtok(initial, " "); token; token = strtok(NULL, " "))
        fields[nf++] = token;
    Position start;
    if (parse_fen(nf, fields, &start))
        return 1;
    Game game = {0};
    game_start(&game, start, 0);
    char line[512];
    for (int i = 0; i < n && fgets(line, sizeof(line), stdin); ++i)
        execute(&game, line);
    free(game.positions);
    free(game.records);
    return 0;
}
