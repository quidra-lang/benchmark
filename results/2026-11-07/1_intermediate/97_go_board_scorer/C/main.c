#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAX_POINTS 361
#define MAX_MOVES 505

typedef struct {
    char board[MAX_POINTS + 1];
    char turn;
    int captures[2];
    int passes;
    int over;
} Position;

typedef struct {
    char color;
    int point;
    int captured;
    Position before;
} Move;

typedef struct {
    int size;
    int komi;
    int superko;
    int handicap[9];
    int handicap_count;
    Position position;
    Move history[MAX_MOVES];
    int move_count;
    char positions[MAX_MOVES + 1][MAX_POINTS + 1];
    int position_count;
    unsigned char dead[MAX_POINTS];
} Game;

typedef struct {
    char color;
    int first;
    int size;
    int liberties;
    unsigned char stones[MAX_POINTS];
    unsigned char empty[MAX_POINTS];
} Group;

typedef struct {
    int first;
    int size;
    char owner;
    unsigned char points[MAX_POINTS];
} Region;

typedef struct {
    char color;
    int point;
} Record;

static const char columns[] = "ABCDEFGHJKLMNOPQRST";
static const char *const handicap_names[3][9] = {
    {"C3","G7","C7","G3","C5","G5","E3","E7","E5"},
    {"D4","K10","D10","K4","D7","K7","G4","G10","G7"},
    {"D4","Q16","D16","Q4","D10","Q10","K4","K16","K10"}
};

static char opponent(char color) {
    return color == 'B' ? 'W' : 'B';
}

static int color_index(char color) {
    return color == 'B' ? 0 : 1;
}

static int size_index(int size) {
    return size == 9 ? 0 : size == 13 ? 1 : 2;
}

static void point_name(int point, int size, char output[8]) {
    int row = point / size + 1;
    output[0] = columns[point % size];
    if (row >= 10) {
        output[1] = (char)('0' + row / 10);
        output[2] = (char)('0' + row % 10);
        output[3] = '\0';
    } else {
        output[1] = (char)('0' + row);
        output[2] = '\0';
    }
}

static int parse_point(const char *text, int size) {
    const char *column = strchr(columns, text[0]);
    if (!column || column - columns >= size || !text[1]) return -1;
    if (text[1] == '0') return -1;
    int row = 0;
    for (const char *p = text + 1; *p; ++p) {
        if (!isdigit((unsigned char)*p)) return -1;
        row = row * 10 + *p - '0';
        if (row > size) return -1;
    }
    if (row < 1) return -1;
    return size * (row - 1) + (int)(column - columns);
}

static void sgf_coordinate(int point, int size, char output[3]) {
    output[0] = (char)('a' + point % size);
    output[1] = (char)('a' + size - 1 - point / size);
    output[2] = '\0';
}

static void half_string(int number, char output[32]) {
    sprintf(output, "%s%d.%d", number < 0 ? "-" : "", abs(number) / 2, abs(number) % 2 ? 5 : 0);
}

static int parse_komi(const char *text, int *value) {
    const char *p = text;
    int sign = 1;
    if (*p == '-') { sign = -1; ++p; }
    if (!isdigit((unsigned char)*p)) return 0;
    if (*p == '0' && isdigit((unsigned char)p[1])) return 0;
    int whole = 0;
    while (isdigit((unsigned char)*p)) {
        whole = 10 * whole + *p - '0';
        if (whole > 100) return 0;
        ++p;
    }
    int half = 0;
    if (*p == '.') {
        ++p;
        if (*p == '5') half = 1;
        else if (*p != '0') return 0;
        ++p;
    }
    if (*p) return 0;
    int number = sign * (whole * 2 + half);
    if (number < -201 || number > 201 || (sign == -1 && number == 0)) return 0;
    *value = number;
    return 1;
}

static int neighbors(int point, int size, int output[4]) {
    int row = point / size, col = point % size, count = 0;
    if (row > 0) output[count++] = point - size;
    if (row + 1 < size) output[count++] = point + size;
    if (col > 0) output[count++] = point - 1;
    if (col + 1 < size) output[count++] = point + 1;
    return count;
}

static int diagonals(int point, int size, int output[4]) {
    int row = point / size, col = point % size, count = 0;
    for (int dr = -1; dr <= 1; dr += 2) {
        for (int dc = -1; dc <= 1; dc += 2) {
            int y = row + dr, x = col + dc;
            if (y >= 0 && y < size && x >= 0 && x < size) output[count++] = y * size + x;
        }
    }
    return count;
}

static void flood(const char *board, int size, int start, char first, char second,
                  unsigned char output[MAX_POINTS], int *count) {
    int queue[MAX_POINTS], head = 0, tail = 1;
    memset(output, 0, MAX_POINTS);
    queue[0] = start;
    output[start] = 1;
    while (head < tail) {
        int near[4], n = neighbors(queue[head++], size, near);
        for (int i = 0; i < n; ++i) {
            int point = near[i];
            if (!output[point] && (board[point] == first || board[point] == second)) {
                output[point] = 1;
                queue[tail++] = point;
            }
        }
    }
    *count = tail;
}

static void group(const char *board, int size, int point, Group *result) {
    memset(result, 0, sizeof(*result));
    result->color = board[point];
    flood(board, size, point, result->color, result->color, result->stones, &result->size);
    result->first = point;
    for (int p = 0; p < size * size; ++p) {
        if (!result->stones[p]) continue;
        if (p < result->first) result->first = p;
        int near[4], n = neighbors(p, size, near);
        for (int i = 0; i < n; ++i) {
            int q = near[i];
            if (board[q] == '.' && !result->empty[q]) {
                result->empty[q] = 1;
                ++result->liberties;
            }
        }
    }
}

static int groups(const char *board, int size, char color, Group result[MAX_POINTS]) {
    unsigned char visited[MAX_POINTS] = {0};
    int count = 0;
    for (int p = 0; p < size * size; ++p) {
        if (board[p] == '.' || visited[p] || (color && color != board[p])) continue;
        group(board, size, p, &result[count]);
        for (int q = 0; q < size * size; ++q) {
            if (result[count].stones[q]) visited[q] = 1;
        }
        ++count;
    }
    return count;
}

static int placement(const char *before, int size, char color, int point,
                     char after[MAX_POINTS + 1], int *captured) {
    strcpy(after, before);
    *captured = 0;
    if (before[point] != '.') return 1;
    after[point] = color;
    unsigned char visited[MAX_POINTS] = {0};
    int near[4], n = neighbors(point, size, near);
    for (int i = 0; i < n; ++i) {
        int q = near[i];
        if (after[q] != opponent(color) || visited[q]) continue;
        Group enemy;
        group(after, size, q, &enemy);
        for (int j = 0; j < size * size; ++j) {
            if (enemy.stones[j]) visited[j] = 1;
        }
        if (enemy.liberties == 0) {
            for (int j = 0; j < size * size; ++j) {
                if (enemy.stones[j]) {
                    after[j] = '.';
                    ++*captured;
                }
            }
        }
    }
    Group own;
    group(after, size, point, &own);
    return own.liberties ? 0 : 2;
}

static const char *check_placement(const Game *game, char color, int point,
                                   char after[MAX_POINTS + 1], int *captured) {
    int result = placement(game->position.board, game->size, color, point, after, captured);
    if (result == 1) return "occupied";
    if (result == 2) return "suicide";
    if (game->position_count >= 2 && !strcmp(after, game->positions[game->position_count - 2])) return "ko";
    if (game->superko) {
        for (int i = 0; i < game->position_count; ++i) {
            if (!strcmp(after, game->positions[i])) return "superko";
        }
    }
    return NULL;
}

static void reset(Game *game, int size, int komi) {
    game->size = size;
    game->komi = komi;
    memset(game->position.board, '.', (size_t)size * size);
    game->position.board[size * size] = '\0';
    game->position.turn = 'B';
    game->position.captures[0] = game->position.captures[1] = 0;
    game->position.passes = 0;
    game->position.over = 0;
    game->handicap_count = game->move_count = 0;
    game->position_count = 1;
    strcpy(game->positions[0], game->position.board);
    memset(game->dead, 0, MAX_POINTS);
}

static void move(Game *game, char color, int point, const char *after, int captured) {
    Move *history = &game->history[game->move_count++];
    history->color = color;
    history->point = point;
    history->captured = captured;
    history->before = game->position;
    if (point < 0) {
        if (++game->position.passes == 2) game->position.over = 1;
    } else {
        strcpy(game->position.board, after);
        game->position.captures[color_index(color)] += captured;
        game->position.passes = 0;
    }
    game->position.turn = opponent(color);
    strcpy(game->positions[game->position_count++], game->position.board);
    memset(game->dead, 0, MAX_POINTS);
}

static int regions(const char *board, int size, Region output[MAX_POINTS]) {
    unsigned char seen[MAX_POINTS] = {0};
    int count = 0;
    for (int p = 0; p < size * size; ++p) {
        if (board[p] != '.' || seen[p]) continue;
        Region *area = &output[count];
        area->first = p;
        flood(board, size, p, '.', '.', area->points, &area->size);
        int black = 0, white = 0;
        for (int q = 0; q < size * size; ++q) {
            if (!area->points[q]) continue;
            seen[q] = 1;
            int near[4], n = neighbors(q, size, near);
            for (int i = 0; i < n; ++i) {
                if (board[near[i]] == 'B') black = 1;
                if (board[near[i]] == 'W') white = 1;
            }
        }
        area->owner = black && !white ? 'B' : white && !black ? 'W' : '-';
        ++count;
    }
    return count;
}

static void cleaned_board(const Game *game, char output[MAX_POINTS + 1]) {
    strcpy(output, game->position.board);
    for (int p = 0; p < game->size * game->size; ++p) if (game->dead[p]) output[p] = '.';
}

static int star_point(const Game *game, int point) {
    int count = game->size == 19 ? 9 : 5;
    for (int i = 0; i < count; ++i) {
        int index = game->size == 19 ? i : i == 4 ? 8 : i;
        if (parse_point(handicap_names[size_index(game->size)][index], game->size) == point) return 1;
    }
    return 0;
}

static void show(const Game *game, int map) {
    int size = game->size;
    char board[MAX_POINTS + 1], characters[MAX_POINTS];
    if (map) cleaned_board(game, board);
    else strcpy(board, game->position.board);
    char ownership[MAX_POINTS] = {0};
    if (map) {
        static Region areas[MAX_POINTS];
        int count = regions(board, size, areas);
        for (int i = 0; i < count; ++i) {
            for (int p = 0; p < size * size; ++p) {
                if (areas[i].points[p]) ownership[p] = areas[i].owner;
            }
        }
    }
    for (int p = 0; p < size * size; ++p) {
        if (board[p] == 'B') characters[p] = game->dead[p] && !map ? 'x' : 'X';
        else if (board[p] == 'W') characters[p] = game->dead[p] && !map ? 'o' : 'O';
        else if (map) characters[p] = ownership[p] == 'B' ? 'x' : ownership[p] == 'W' ? 'o' : '.';
        else characters[p] = star_point(game, p) ? '+' : '.';
    }
    printf("   ");
    for (int c = 0; c < size; ++c) printf("%s%c", c ? " " : "", columns[c]);
    putchar('\n');
    for (int r = size; r >= 1; --r) {
        printf("%2d", r);
        for (int c = 0; c < size; ++c) printf(" %c", characters[(r - 1) * size + c]);
        printf(" %d\n", r);
    }
    printf("   ");
    for (int c = 0; c < size; ++c) printf("%s%c", c ? " " : "", columns[c]);
    putchar('\n');
}

static void score(const Game *game, const char *method) {
    char board[MAX_POINTS + 1];
    cleaned_board(game, board);
    static Region areas[MAX_POINTS];
    int count = regions(board, game->size, areas);
    int territory[2] = {0, 0}, total[2] = {0, 0};
    for (int i = 0; i < count; ++i) {
        if (areas[i].owner == 'B' || areas[i].owner == 'W') territory[color_index(areas[i].owner)] += areas[i].size;
    }
    int area_method = !strcmp(method, "AREA");
    for (int c = 0; c < 2; ++c) {
        char color = c == 0 ? 'B' : 'W';
        int komi = c == 1 ? game->komi : 0;
        char value[32], comp[32];
        if (area_method) {
            int stones = 0;
            for (int p = 0; p < game->size * game->size; ++p) if (board[p] == color) ++stones;
            total[c] = 2 * (stones + territory[c]) + komi;
            half_string(total[c], value);
            if (c == 0) printf("B stones %d territory %d total %s\n", stones, territory[c], value);
            else {
                half_string(game->komi, comp);
                printf("W stones %d territory %d komi %s total %s\n", stones, territory[c], comp, value);
            }
        } else {
            int prisoners = game->position.captures[c];
            for (int p = 0; p < game->size * game->size; ++p) {
                if (game->dead[p] && game->position.board[p] == opponent(color)) ++prisoners;
            }
            total[c] = 2 * (territory[c] + prisoners) + komi;
            half_string(total[c], value);
            if (c == 0) printf("B territory %d prisoners %d total %s\n", territory[c], prisoners, value);
            else {
                half_string(game->komi, comp);
                printf("W territory %d prisoners %d komi %s total %s\n", territory[c], prisoners, comp, value);
            }
        }
    }
    int difference = total[0] - total[1];
    if (!difference) puts("result Draw");
    else {
        char value[32];
        half_string(abs(difference), value);
        printf("result %c+%s\n", difference > 0 ? 'B' : 'W', value);
    }
}

static int safe_groups(const char *board, int size, char color, Group result[MAX_POINTS]) {
    static Group candidates[MAX_POINTS];
    static unsigned char areas[MAX_POINTS][MAX_POINTS];
    static unsigned char vital[MAX_POINTS][MAX_POINTS];
    static unsigned char touch[MAX_POINTS][MAX_POINTS];
    unsigned char seen[MAX_POINTS] = {0}, kept_groups[MAX_POINTS] = {0}, kept_areas[MAX_POINTS] = {0};
    int group_count = groups(board, size, color, candidates), area_count = 0;
    for (int p = 0; p < size * size; ++p) {
        if (board[p] == color || seen[p]) continue;
        int amount = 0;
        flood(board, size, p, '.', opponent(color), areas[area_count], &amount);
        for (int q = 0; q < size * size; ++q) if (areas[area_count][q]) seen[q] = 1;
        for (int i = 0; i < group_count; ++i) {
            int is_vital = 1, is_touching = 0;
            for (int q = 0; q < size * size; ++q) {
                if (!areas[area_count][q]) continue;
                if (board[q] == '.' && !candidates[i].empty[q]) is_vital = 0;
                int near[4], count = neighbors(q, size, near);
                for (int j = 0; j < count; ++j) {
                    if (candidates[i].stones[near[j]]) is_touching = 1;
                }
            }
            vital[area_count][i] = (unsigned char)is_vital;
            touch[area_count][i] = (unsigned char)is_touching;
        }
        kept_areas[area_count++] = 1;
    }
    for (int i = 0; i < group_count; ++i) kept_groups[i] = 1;
    for (;;) {
        int changed = 0;
        for (int i = 0; i < group_count; ++i) {
            if (!kept_groups[i]) continue;
            int amount = 0;
            for (int a = 0; a < area_count; ++a) if (kept_areas[a] && vital[a][i]) ++amount;
            if (amount < 2) kept_groups[i] = 0, changed = 1;
        }
        for (int a = 0; a < area_count; ++a) {
            if (!kept_areas[a]) continue;
            for (int i = 0; i < group_count; ++i) {
                if (touch[a][i] && !kept_groups[i]) {
                    kept_areas[a] = 0;
                    changed = 1;
                    break;
                }
            }
        }
        if (!changed) break;
    }
    int count = 0;
    for (int i = 0; i < group_count; ++i) if (kept_groups[i]) result[count++] = candidates[i];
    return count;
}

static int defend_ladder(const char *board, int size, int point, char defender, int depth, int *first);
static int attack_ladder(const char *board, int size, int point, char defender, int depth, int *first);

static int defend_ladder(const char *board, int size, int point, char defender, int depth, int *first) {
    if (depth >= 40) return 1;
    Group target;
    group(board, size, point, &target);
    unsigned char choices[MAX_POINTS];
    memcpy(choices, target.empty, MAX_POINTS);
    unsigned char seen[MAX_POINTS] = {0};
    for (int p = 0; p < size * size; ++p) {
        if (!target.stones[p]) continue;
        int near[4], count = neighbors(p, size, near);
        for (int j = 0; j < count; ++j) {
            int q = near[j];
            if (board[q] != opponent(defender) || seen[q]) continue;
            Group attacking;
            group(board, size, q, &attacking);
            for (int k = 0; k < size * size; ++k) if (attacking.stones[k]) seen[k] = 1;
            if (attacking.liberties == 1) {
                for (int k = 0; k < size * size; ++k) if (attacking.empty[k]) choices[k] = 1;
            }
        }
    }
    for (int p = 0; p < size * size; ++p) {
        if (!choices[p]) continue;
        char next[MAX_POINTS + 1];
        int captured = 0;
        if (placement(board, size, defender, p, next, &captured)) continue;
        Group after;
        group(next, size, point, &after);
        int irrelevant;
        if (after.liberties >= 3 || (after.liberties == 2 && !attack_ladder(next, size, point, defender, depth + 1, &irrelevant))) {
            *first = p;
            return 1;
        }
    }
    return 0;
}

static int attack_ladder(const char *board, int size, int point, char defender, int depth, int *first) {
    if (depth >= 40) return 0;
    Group target;
    group(board, size, point, &target);
    for (int p = 0; p < size * size; ++p) {
        if (!target.empty[p]) continue;
        char next[MAX_POINTS + 1];
        int captured = 0;
        if (placement(board, size, opponent(defender), p, next, &captured)) continue;
        int irrelevant;
        if (!defend_ladder(next, size, point, defender, depth + 1, &irrelevant)) {
            *first = p;
            return 1;
        }
    }
    return 0;
}

static int parse_sequence(const char *text, int size, Record output[MAX_MOVES]) {
    int n = 0;
    for (const char *p = text; *p;) {
        if (*p++ != ';' || (*p != 'B' && *p != 'W')) return -1;
        char color = *p++;
        if (*p++ != '[') return -1;
        int point = -1;
        if (*p != ']') {
            if (p[0] < 'a' || p[0] >= 'a' + size || p[1] < 'a' || p[1] >= 'a' + size) return -1;
            point = (size - 1 - (p[1] - 'a')) * size + p[0] - 'a';
            p += 2;
        }
        if (*p++ != ']' || n >= MAX_MOVES) return -1;
        output[n].color = color;
        output[n++].point = point;
    }
    return n ? n : -1;
}

static void replay(Game *game, const Record *records, int count) {
    int performed = 0;
    const char *reason = NULL;
    for (int i = 0; i < count; ++i) {
        char color = records[i].color;
        int point = records[i].point, captured = 0;
        char after[MAX_POINTS + 1];
        if (game->position.over) reason = "game over";
        else if (color != game->position.turn) reason = "turn";
        else if (point >= 0) reason = check_placement(game, color, point, after, &captured);
        else reason = NULL;
        if (reason) break;
        move(game, color, point, point < 0 ? NULL : after, captured);
        ++performed;
    }
    printf("replay %d moves", performed);
    if (reason) {
        char name[8];
        int point = records[performed].point;
        if (point >= 0) point_name(point, game->size, name);
        else strcpy(name, "pass");
        printf(" stopped %c %s %s", records[performed].color, name, reason);
    }
    putchar('\n');
    if (game->position.over) puts("game over");
}

static int valid_color(const char *text) {
    return strlen(text) == 1 && (text[0] == 'B' || text[0] == 'W');
}

static void execute(Game *game, char *line) {
    static const char *const names[] = {
        "BOARD","KOMI","SUPERKO","HANDICAP","PLAY","PASS","REPLAY","UNDO",
        "SHOW","MAP","STATUS","CAPTURES","HISTORY","MOVES","GROUP","GROUPS",
        "ATARI","LEGAL","EYES","SAFE","LADDER","DEAD","REGIONS","SCORE"
    };
    static const int arities[] = {
        2,1,1,1,2,1,1,0,0,0,0,0,0,0,1,0,0,1,1,1,1,1,0,1
    };
    char *words[8];
    int count = 0;
    for (char *p = strtok(line, " \r\n"); p; p = strtok(NULL, " \r\n")) {
        if (count >= 8) { puts("ERROR bad arguments"); return; }
        words[count++] = p;
    }
    if (!count) return;
    const char *cmd = words[0];
    int action = -1;
    for (int i = 0; i < 24; ++i) if (!strcmp(cmd, names[i])) action = i;
    if (action < 0) { puts("ERROR unknown command"); return; }
    if (count - 1 != arities[action]) { puts("ERROR bad arguments"); return; }
    int komi = 0, point = -1;
    static Record sequence[MAX_MOVES];
    int sequence_count = 0;
    if (action == 0 && (!(!strcmp(words[1], "9") || !strcmp(words[1], "13") || !strcmp(words[1], "19")) || !parse_komi(words[2], &komi))) {
        puts("ERROR bad arguments"); return;
    }
    if (action == 1 && !parse_komi(words[1], &komi)) { puts("ERROR bad arguments"); return; }
    if (action == 2 && strcmp(words[1], "ON") && strcmp(words[1], "OFF")) { puts("ERROR bad arguments"); return; }
    if (action == 3 && (strlen(words[1]) != 1 || words[1][0] < '2' || words[1][0] > '9')) { puts("ERROR bad arguments"); return; }
    if ((action == 4 || action == 5 || action == 17 || action == 18 || action == 19) && !valid_color(words[1])) { puts("ERROR bad arguments"); return; }
    if (action == 23 && strcmp(words[1], "AREA") && strcmp(words[1], "TERRITORY")) { puts("ERROR bad arguments"); return; }
    if (action == 4 || action == 14 || action == 20 || action == 21) {
        point = parse_point(words[action == 4 ? 2 : 1], game->size);
        if (point < 0) { puts("ERROR bad point"); return; }
    }
    if (action == 6) {
        sequence_count = parse_sequence(words[1], game->size, sequence);
        if (sequence_count < 0) { puts("ERROR bad sequence"); return; }
    }
    if ((action == 4 || action == 5 || action == 6) && game->position.over) { puts("ERROR game over"); return; }
    switch (action) {
        case 0: {
            int size = atoi(words[1]);
            reset(game, size, komi);
            char s[32];
            half_string(game->komi, s);
            printf("board %d komi %s\n", size, s);
            break;
        }
        case 1: {
            char s[32];
            game->komi = komi;
            half_string(komi, s);
            printf("komi %s\n", s);
            break;
        }
        case 2:
            game->superko = !strcmp(words[1], "ON");
            printf("superko %s\n", game->superko ? "on" : "off");
            break;
        case 3: {
            int present = 0;
            for (int p = 0; p < game->size * game->size; ++p) present |= game->position.board[p] != '.';
            if (game->move_count || present) { puts("ERROR handicap not allowed"); break; }
            int k = atoi(words[1]);
            printf("handicap %d", k);
            for (int i = 0; i < k; ++i) {
                int index = k == 5 && i == 4 ? 8 : k == 7 && i == 6 ? 8 : i;
                int p = parse_point(handicap_names[size_index(game->size)][index], game->size);
                game->handicap[i] = p;
                game->position.board[p] = 'B';
                printf(" %s", handicap_names[size_index(game->size)][index]);
            }
            game->handicap_count = k;
            game->position.turn = 'W';
            game->position_count = 1;
            strcpy(game->positions[0], game->position.board);
            memset(game->dead, 0, MAX_POINTS);
            putchar('\n');
            break;
        }
        case 4: {
            char color = words[1][0], after[MAX_POINTS + 1];
            int captured = 0;
            const char *reason = color == game->position.turn ? check_placement(game, color, point, after, &captured) : "turn";
            if (reason) printf("ILLEGAL %c %s %s\n", color, words[2], reason);
            else {
                move(game, color, point, after, captured);
                printf("%c %s", color, words[2]);
                if (captured) printf(" captures %d", captured);
                putchar('\n');
            }
            break;
        }
        case 5: {
            char color = words[1][0];
            if (color != game->position.turn) printf("ILLEGAL %c pass turn\n", color);
            else {
                move(game, color, -1, NULL, 0);
                printf("%c pass\n", color);
                if (game->position.over) puts("game over");
            }
            break;
        }
        case 6: replay(game, sequence, sequence_count); break;
        case 7: {
            if (!game->move_count) { puts("ERROR nothing to undo"); break; }
            Move *entry = &game->history[--game->move_count];
            game->position = entry->before;
            --game->position_count;
            memset(game->dead, 0, MAX_POINTS);
            if (entry->point < 0) printf("undo %c pass\n", entry->color);
            else {
                char name[8];
                point_name(entry->point, game->size, name);
                printf("undo %c %s\n", entry->color, name);
            }
            break;
        }
        case 8: show(game, 0); break;
        case 9: show(game, 1); break;
        case 10: {
            char s[32];
            half_string(game->komi, s);
            printf("size %d komi %s handicap %d superko %s\n", game->size, s, game->handicap_count, game->superko ? "on" : "off");
            printf("moves %d", game->move_count);
            if (game->position.over) puts(" game over");
            else printf(" next %c passes %d\n", game->position.turn, game->position.passes);
            break;
        }
        case 11:
            printf("captures B %d W %d\n", game->position.captures[0], game->position.captures[1]);
            break;
        case 12:
            printf("history %d\n", game->move_count);
            for (int i = 0; i < game->move_count; ++i) {
                Move *entry = &game->history[i];
                char name[8];
                if (entry->point < 0) strcpy(name, "pass");
                else point_name(entry->point, game->size, name);
                printf("%d %c %s", i + 1, entry->color, name);
                if (entry->captured) printf(" captures %d", entry->captured);
                putchar('\n');
            }
            break;
        case 13: {
            char s[32];
            half_string(game->komi, s);
            printf("(;GM[1]FF[4]SZ[%d]KM[%s]", game->size, s);
            if (game->handicap_count) {
                printf("HA[%d]AB", game->handicap_count);
                for (int i = 0; i < game->handicap_count; ++i) {
                    char name[3];
                    sgf_coordinate(game->handicap[i], game->size, name);
                    printf("[%s]", name);
                }
            }
            for (int i = 0; i < game->move_count; ++i) {
                char name[3] = "";
                Move *entry = &game->history[i];
                if (entry->point >= 0) sgf_coordinate(entry->point, game->size, name);
                printf(";%c[%s]", entry->color, name);
            }
            puts(")");
            break;
        }
        case 14: case 20: case 21: {
            if (game->position.board[point] == '.') { puts("ERROR no stone"); break; }
            Group target;
            group(game->position.board, game->size, point, &target);
            char first[8];
            point_name(target.first, game->size, first);
            if (action == 14) {
                printf("group %c %s size %d liberties %d\n", target.color, first, target.size, target.liberties);
                printf("stones");
                for (int p = 0; p < game->size * game->size; ++p) if (target.stones[p]) {
                    char name[8]; point_name(p, game->size, name); printf(" %s", name);
                }
                printf("\nliberties");
                for (int p = 0; p < game->size * game->size; ++p) if (target.empty[p]) {
                    char name[8]; point_name(p, game->size, name); printf(" %s", name);
                }
                putchar('\n');
            } else if (action == 21) {
                int already_dead = game->dead[point];
                for (int p = 0; p < game->size * game->size; ++p) if (target.stones[p]) game->dead[p] = (unsigned char)!already_dead;
                printf("%s %c %s size %d\n", already_dead ? "alive" : "dead", target.color, first, target.size);
            } else {
                int candidate = -1, works;
                if (target.liberties >= 3) printf("ladder %s safe\n", words[1]);
                else if (target.liberties == 1) {
                    works = defend_ladder(game->position.board, game->size, point, target.color, 0, &candidate);
                    printf("ladder %s %s", words[1], works ? "escapes" : "captured");
                    if (works) {char name[8]; point_name(candidate, game->size, name); printf(" %s", name);}
                    putchar('\n');
                } else {
                    works = attack_ladder(game->position.board, game->size, point, target.color, 0, &candidate);
                    printf("ladder %s %s", words[1], works ? "captured" : "escapes");
                    if (works) {char name[8]; point_name(candidate, game->size, name); printf(" %s", name);}
                    putchar('\n');
                }
            }
            break;
        }
        case 15: case 16: {
            static Group all[MAX_POINTS];
            int count = groups(game->position.board, game->size, 0, all);
            if (action == 15) printf("groups %d\n", count);
            int atari = 0;
            for (int i = 0; i < count; ++i) {
                Group *entry = &all[i];
                char name[8]; point_name(entry->first, game->size, name);
                if (action == 15) printf("%c %s size %d liberties %d%s\n", entry->color, name, entry->size, entry->liberties, game->dead[entry->first] ? " dead" : "");
                else if (entry->liberties == 1) {
                    int liberty = -1;
                    for (int p = 0; p < game->size * game->size; ++p) if (entry->empty[p]) {liberty = p; break;}
                    char q[8]; point_name(liberty, game->size, q);
                    printf("atari %c %s size %d at %s\n", entry->color, name, entry->size, q);
                    ++atari;
                }
            }
            if (action == 16 && !atari) puts("atari none");
            break;
        }
        case 17: {
            char color = words[1][0];
            char *reasons[MAX_POINTS] = {0};
            int count = 0;
            for (int p = 0; p < game->size * game->size; ++p) {
                if (game->position.board[p] != '.') continue;
                char after[MAX_POINTS + 1]; int captured = 0;
                const char *reason = check_placement(game, color, p, after, &captured);
                if (!reason) ++count;
                else reasons[p] = (char *)reason;
            }
            printf("legal %c %d\n", color, count);
            for (int p = 0; p < game->size * game->size; ++p) if (reasons[p]) {
                char name[8]; point_name(p, game->size, name);
                printf("%s %s\n", name, reasons[p]);
            }
            break;
        }
        case 18: {
            char color = words[1][0];
            int eye[MAX_POINTS] = {0}, count = 0;
            for (int p = 0; p < game->size * game->size; ++p) {
                if (game->position.board[p] != '.') continue;
                int near[4], n = neighbors(p, game->size, near), all = 1;
                for (int i = 0; i < n; ++i) if (game->position.board[near[i]] != color) all = 0;
                if (!all) continue;
                int diagonals_points[4], m = diagonals(p, game->size, diagonals_points), opponents = 0;
                for (int i = 0; i < m; ++i) if (game->position.board[diagonals_points[i]] == opponent(color)) ++opponents;
                eye[p] = (n == 4 ? opponents <= 1 : opponents == 0) ? 1 : 2;
                ++count;
            }
            printf("eyes %c %d\n", color, count);
            for (int p = 0; p < game->size * game->size; ++p) if (eye[p]) {
                char name[8]; point_name(p, game->size, name);
                printf("%s %s\n", name, eye[p] == 1 ? "real" : "false");
            }
            break;
        }
        case 19: {
            static Group alive[MAX_POINTS];
            int count = safe_groups(game->position.board, game->size, words[1][0], alive);
            printf("safe %c %d\n", words[1][0], count);
            for (int i = 0; i < count; ++i) {
                char name[8]; point_name(alive[i].first, game->size, name);
                printf("%s size %d\n", name, alive[i].size);
            }
            break;
        }
        case 22: {
            char board[MAX_POINTS + 1];
            cleaned_board(game, board);
            static Region areas[MAX_POINTS];
            int count = regions(board, game->size, areas);
            printf("regions %d\n", count);
            for (int i = 0; i < count; ++i) {
                char name[8]; point_name(areas[i].first, game->size, name);
                printf("%s size %d %s\n", name, areas[i].size, areas[i].owner == '-' ? "neutral" : areas[i].owner == 'B' ? "B" : "W");
            }
            break;
        }
        case 23: score(game, words[1]); break;
    }
}

int main(void) {
    static Game game;
    reset(&game, 19, 13);
    char line[256];
    if (!fgets(line, sizeof(line), stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count && fgets(line, sizeof(line), stdin); ++i) execute(&game, line);
    return 0;
}
