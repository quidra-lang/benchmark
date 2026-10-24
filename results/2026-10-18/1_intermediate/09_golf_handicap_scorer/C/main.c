#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LIMIT 1001
#define HOLES 18
#define NO_SCORE (-1000000)

typedef struct Course Course;
typedef struct Tee Tee;
typedef struct Round Round;
typedef struct Player Player;
typedef struct Event Event;

struct Course {
    char id[9];
    int pars[HOLES], si[HOLES], par;
};

struct Tee {
    char id[9];
    Course *course;
    int rating, slope;
};

typedef struct {
    int valid, lowest, average, adjustment, has_low, low;
    int hard, soft, maximum;
} Calculation;

typedef struct {
    int day, index;
} IndexRecord;

struct Round {
    Course *course;
    Tee *tee;
    int day;
    int scores[HOLES], adjusted[HOLES], ags, differential, exceptional;
    int has_handicap, handicap;
    int previous_has_index, previous_index, previous_records;
    Calculation previous_calculation;
};

struct Player {
    char id[9], name[13];
    int has_index, index, round_count, record_count;
    Round *rounds[LIMIT];
    IndexRecord records[LIMIT];
    Calculation calculation;
};

struct Event {
    char id[9], format[12];
    Course *course;
    Tee *tee;
    int day, allowance, count;
    Player *players[10];
};

typedef struct {
    int number, adjusted;
    Round *round;
} Eligible;

typedef struct {
    Round *rounds[10];
    int handicaps[10], nets[10][HOLES], points[10][HOLES];
} EventData;

static Course courses[LIMIT];
static Tee tees[LIMIT];
static Player players[LIMIT];
static Round rounds[LIMIT];
static Event events[LIMIT];
static int course_count, tee_count, player_count, round_count, event_count;

static int floor_div(long long n, long long d) {
    return (int)(n >= 0 ? n / d : -((-n + d - 1) / d));
}

static int round_half_up(long long n, long long d) {
    return floor_div(2 * n + d, 2 * d);
}

static int round_half_away(long long n, long long d) {
    return n < 0 ? -round_half_up(-n, d) : round_half_up(n, d);
}

static void error_line(const char *reason) {
    printf("ERROR %s\n", reason);
}

static void decimal(int value) {
    if (value < 0) {
        putchar('-');
        value = -value;
    }
    printf("%d.%d", value / 10, value % 10);
}

static void print_index(int exists, int value) {
    if (!exists) {
        printf("none");
    } else {
        if (value < 0) {
            putchar('+');
            value = -value;
        }
        printf("%d.%d", value / 10, value % 10);
    }
}

static void print_handicap(int exists, int value) {
    if (!exists) {
        printf("none");
    } else if (value < 0) {
        printf("+%d", -value);
    } else {
        printf("%d", value);
    }
}

static void print_average(long long total, int count) {
    if (!count) {
        putchar('-');
    } else {
        long long value = total * 100 / count;
        printf("%lld.%02lld", value / 100, value % 100);
    }
}

static Course *find_course(const char *id) {
    for (int i = 0; i < course_count; ++i)
        if (!strcmp(courses[i].id, id)) return &courses[i];
    return NULL;
}

static Tee *find_tee(Course *course, const char *id) {
    for (int i = 0; i < tee_count; ++i)
        if (tees[i].course == course && !strcmp(tees[i].id, id))
            return &tees[i];
    return NULL;
}

static Player *find_player(const char *id) {
    for (int i = 0; i < player_count; ++i)
        if (!strcmp(players[i].id, id)) return &players[i];
    return NULL;
}

static Event *find_event(const char *id) {
    for (int i = 0; i < event_count; ++i)
        if (!strcmp(events[i].id, id)) return &events[i];
    return NULL;
}

static Tee *checked_tee(const char *course_id, const char *tee_id) {
    Course *course = find_course(course_id);
    if (!course) {
        error_line("unknown course");
        return NULL;
    }
    Tee *tee = find_tee(course, tee_id);
    if (!tee) error_line("unknown tee");
    return tee;
}

static int course_handicap(int index, Tee *tee) {
    return round_half_up((long long)index * tee->slope +
                         113LL * (tee->rating - 10 * tee->course->par), 1130);
}

static void allocation(int handicap, const Course *course, int strokes[HOLES]) {
    int magnitude = abs(handicap), q = magnitude / HOLES, r = magnitude % HOLES;
    for (int i = 0; i < HOLES; ++i) {
        strokes[i] = handicap >= 0
            ? q + (course->si[i] <= r)
            : -q - (course->si[i] >= 19 - r);
    }
}

static int low_index(Player *player, int day, int *value, int *date) {
    int found = 0;
    for (int i = 0; i < player->record_count; ++i) {
        IndexRecord record = player->records[i];
        if (record.day < day - 365 || record.day >= day) continue;
        if (!found || record.index < *value ||
            (record.index == *value && record.day < *date)) {
            *value = record.index;
            *date = record.day;
            found = 1;
        }
    }
    return found;
}

static int eligible_rounds(Player *player, Eligible eligible[20]) {
    int count = player->round_count < 20 ? player->round_count : 20;
    int reduction = 0;
    for (int i = count - 1; i >= 0; --i) {
        int number = player->round_count - count + i + 1;
        Round *r = player->rounds[number - 1];
        reduction += r->exceptional;
        eligible[i].number = number;
        eligible[i].round = r;
        eligible[i].adjusted = r->differential - reduction;
    }
    return count;
}

static int compare_eligible(const void *left, const void *right) {
    const Eligible *a = left, *b = right;
    if (a->adjusted != b->adjusted)
        return a->adjusted < b->adjusted ? -1 : 1;
    return a->number > b->number ? -1 : (a->number < b->number ? 1 : 0);
}

static int counting_rounds(Eligible eligible[20], int count,
                           Eligible selected[20], int *adjustment) {
    if (count < 3) {
        *adjustment = 0;
        return 0;
    }
    const int limits[8] = {5, 8, 11, 14, 16, 18, 19, 20};
    int k = 1;
    while (count > limits[k - 1]) ++k;
    memcpy(selected, eligible, count * sizeof(Eligible));
    qsort(selected, count, sizeof(Eligible), compare_eligible);
    *adjustment = count == 3 ? -20 : (count == 4 || count == 6 ? -10 : 0);
    return k;
}

static void update_index(Player *player, int day) {
    Eligible eligible[20], selected[20];
    int count = eligible_rounds(player, eligible);
    int adjustment, k = counting_rounds(eligible, count, selected, &adjustment);
    if (!k) {
        player->calculation.valid = 0;
        return;
    }
    long long total = 0;
    for (int i = 0; i < k; ++i) total += selected[i].adjusted;
    int average = round_half_away(total, k);
    int candidate = average + adjustment;
    int low = 0, date = 0, soft = 0, hard = 0, maximum = 0;
    int has_low = low_index(player, day, &low, &date);
    if (has_low) {
        if (candidate - low > 30) {
            candidate = low + 30 + (candidate - low - 30) / 2;
            soft = 1;
        }
        if (candidate - low > 50) {
            candidate = low + 50;
            hard = 1;
        }
    }
    if (candidate > 540) {
        candidate = 540;
        maximum = 1;
    }
    player->has_index = 1;
    player->index = candidate;
    player->calculation = (Calculation){
        1, k, average, adjustment, has_low, low, hard, soft, maximum
    };
}

static int is_complete(Round *r) {
    for (int h = 0; h < HOLES; ++h)
        if (r->scores[h] <= 0) return 0;
    return 1;
}

static void command_course(char **a) {
    if (find_course(a[0])) {
        error_line("duplicate course");
        return;
    }
    int pars[HOLES], indexes[HOLES], seen[19] = {0}, total = 0;
    for (int i = 0; i < HOLES; ++i) {
        pars[i] = atoi(a[i + 1]);
        indexes[i] = atoi(a[i + 19]);
        if (pars[i] < 3 || pars[i] > 5 ||
            indexes[i] < 1 || indexes[i] > 18 || seen[indexes[i]]) {
            error_line("invalid course");
            return;
        }
        seen[indexes[i]] = 1;
        total += pars[i];
    }
    Course *c = &courses[course_count++];
    strcpy(c->id, a[0]);
    memcpy(c->pars, pars, sizeof(pars));
    memcpy(c->si, indexes, sizeof(indexes));
    c->par = total;
}

static void command_tee(char **a) {
    Course *course = find_course(a[0]);
    if (!course) {
        error_line("unknown course");
        return;
    }
    if (find_tee(course, a[1])) {
        error_line("duplicate tee");
        return;
    }
    int rating = atoi(a[2]), slope = atoi(a[3]);
    if (rating < 500 || rating > 900 || slope < 55 || slope > 155) {
        error_line("invalid tee");
        return;
    }
    Tee *tee = &tees[tee_count++];
    strcpy(tee->id, a[1]);
    tee->course = course;
    tee->rating = rating;
    tee->slope = slope;
}

static void command_player(char **a, int argc) {
    if (find_player(a[0])) {
        error_line("duplicate player");
        return;
    }
    int index = argc == 3 ? atoi(a[2]) : 0;
    if (argc == 3 && (index < -100 || index > 540)) {
        error_line("invalid index");
        return;
    }
    Player *p = &players[player_count++];
    strcpy(p->id, a[0]);
    strcpy(p->name, a[1]);
    p->has_index = argc == 3;
    p->index = index;
}

static void command_round(char **a) {
    Player *p = find_player(a[0]);
    if (!p) {
        error_line("unknown player");
        return;
    }
    Tee *tee = checked_tee(a[1], a[2]);
    if (!tee) return;
    int day = atoi(a[3]);
    if (p->round_count && day < p->rounds[p->round_count - 1]->day) {
        error_line("invalid day");
        return;
    }
    int scores[HOLES], unplayed = 0;
    for (int h = 0; h < HOLES; ++h) {
        scores[h] = !strcmp(a[h + 4], "-") ? -1 :
                    (!strcmp(a[h + 4], "X") ? 0 : atoi(a[h + 4]));
        if (scores[h] == -1) ++unplayed;
    }
    if (unplayed >= 5) {
        error_line("too few holes");
        return;
    }
    Round *r = &rounds[round_count++];
    r->course = tee->course;
    r->tee = tee;
    r->day = day;
    memcpy(r->scores, scores, sizeof(scores));
    r->previous_has_index = p->has_index;
    r->previous_index = p->index;
    r->previous_records = p->record_count;
    r->previous_calculation = p->calculation;
    r->has_handicap = p->has_index;
    r->handicap = p->has_index ? course_handicap(p->index, tee) : 0;
    int strokes[HOLES];
    allocation(r->handicap, r->course, strokes);
    r->ags = 0;
    for (int h = 0; h < HOLES; ++h) {
        int limit = p->has_index ? r->course->pars[h] + 2 + strokes[h]
                                 : r->course->pars[h] + 5;
        r->adjusted[h] = scores[h] == -1 ? r->course->pars[h] + strokes[h] :
                         scores[h] == 0 ? limit :
                         (scores[h] < limit ? scores[h] : limit);
        r->ags += r->adjusted[h];
    }
    r->differential = round_half_away(
        113LL * (10 * r->ags - tee->rating), tee->slope);
    r->exceptional = 0;
    if (p->has_index && p->index - r->differential >= 70)
        r->exceptional = p->index - r->differential >= 100 ? 20 : 10;

    p->rounds[p->round_count++] = r;
    update_index(p, day);
    if (p->has_index) {
        p->records[p->record_count++] = (IndexRecord){day, p->index};
    }
    printf("round %s %d: ags %d diff ", p->id, p->round_count, r->ags);
    decimal(r->differential);
    if (r->exceptional) {
        printf(" exceptional ");
        decimal(-r->exceptional);
    }
    printf(" index ");
    print_index(p->has_index, p->index);
    putchar('\n');
}

static void command_remove(char **a) {
    Player *p = find_player(a[0]);
    if (!p) {
        error_line("unknown player");
        return;
    }
    if (!p->round_count) {
        error_line("no rounds");
        return;
    }
    int number = p->round_count;
    Round *r = p->rounds[--p->round_count];
    p->has_index = r->previous_has_index;
    p->index = r->previous_index;
    p->record_count = r->previous_records;
    p->calculation = r->previous_calculation;
    printf("removed %s %d: index ", p->id, number);
    print_index(p->has_index, p->index);
    putchar('\n');
}

static void command_index(char **a) {
    Player *p = find_player(a[0]);
    if (!p) {
        error_line("unknown player");
        return;
    }
    printf("index %s: ", p->id);
    print_index(p->has_index, p->index);
    printf(" rounds %d", p->round_count);
    Calculation *c = &p->calculation;
    if (c->valid) {
        printf(" lowest %d average ", c->lowest);
        decimal(c->average);
        printf(" adjustment ");
        decimal(c->adjustment);
        if (c->has_low) {
            printf(" low ");
            print_index(1, c->low);
        }
        if (c->hard) printf(" hard cap");
        else if (c->soft) printf(" soft cap");
        if (c->maximum) printf(" maximum");
    }
    putchar('\n');
}

static void command_history(char **a) {
    Player *p = find_player(a[0]);
    if (!p) {
        error_line("unknown player");
        return;
    }
    Eligible eligible[20], selected[20];
    int count = eligible_rounds(p, eligible), adjustment;
    int k = counting_rounds(eligible, count, selected, &adjustment);
    printf("history %s: rounds %d\n", p->id, p->round_count);
    for (int i = 0; i < count; ++i) {
        Eligible *entry = &eligible[i];
        Round *r = entry->round;
        printf("%d day %d %s %s ags %d diff ", entry->number, r->day,
               r->course->id, r->tee->id, r->ags);
        decimal(r->differential);
        if (entry->adjusted != r->differential) {
            printf(" adjusted ");
            decimal(entry->adjusted);
        }
        for (int j = 0; j < k; ++j)
            if (selected[j].number == entry->number) {
                printf(" *");
                break;
            }
        putchar('\n');
    }
}

static void command_lowindex(char **a) {
    Player *p = find_player(a[0]);
    if (!p) {
        error_line("unknown player");
        return;
    }
    int day = atoi(a[1]), value = 0, date = 0;
    int found = low_index(p, day, &value, &date);
    printf("lowindex %s %d: ", p->id, day);
    if (!found) printf("none");
    else {
        print_index(1, value);
        printf(" day %d", date);
    }
    putchar('\n');
}

static void command_coursehcp(char **a) {
    Player *p = find_player(a[0]);
    if (!p) {
        error_line("unknown player");
        return;
    }
    Tee *t = checked_tee(a[1], a[2]);
    if (!t) return;
    if (!p->has_index) {
        error_line("no index");
        return;
    }
    int hcp = course_handicap(p->index, t);
    int strokes[HOLES];
    allocation(hcp, t->course, strokes);
    printf("coursehcp %s %s %s: ", p->id, t->course->id, t->id);
    print_handicap(1, hcp);
    printf(" strokes");
    for (int h = 0; h < HOLES; ++h) printf(" %d", strokes[h]);
    putchar('\n');
}

static void command_hcptable(char **a) {
    Tee *t = checked_tee(a[0], a[1]);
    if (!t) return;
    int first = atoi(a[2]), last = atoi(a[3]);
    if (first < -100 || last > 540 || first > last) {
        error_line("invalid index");
        return;
    }
    printf("hcptable %s %s: ", t->course->id, t->id);
    print_index(1, first);
    printf(" to ");
    print_index(1, last);
    putchar('\n');
    int start = first, handicap = course_handicap(first, t);
    for (int i = first + 1; i <= last; ++i) {
        int next = course_handicap(i, t);
        if (next != handicap) {
            print_index(1, start);
            printf(" to ");
            print_index(1, i - 1);
            printf(": ");
            print_handicap(1, handicap);
            putchar('\n');
            start = i;
            handicap = next;
        }
    }
    print_index(1, start);
    printf(" to ");
    print_index(1, last);
    printf(": ");
    print_handicap(1, handicap);
    putchar('\n');
}

static void card_total(const char *label, Round *r,
                       const int strokes[HOLES], const int nets[HOLES],
                       const int points[HOLES], int first, int last) {
    int pars = 0, gross = 0, ags = 0, hcp = 0, net = 0, pts = 0, complete = 1;
    for (int i = first; i < last; ++i) {
        pars += r->course->pars[i];
        if (r->scores[i] <= 0) complete = 0;
        else gross += r->scores[i];
        ags += r->adjusted[i];
        hcp += strokes[i];
        if (nets[i] != NO_SCORE) net += nets[i];
        pts += points[i];
    }
    printf("%s %d ", label, pars);
    if (complete) printf("%d", gross);
    else putchar('-');
    printf(" %d %d ", ags, hcp);
    if (complete) printf("%d", net);
    else putchar('-');
    printf(" %d\n", pts);
}

static void command_card(char **a) {
    Player *p = find_player(a[0]);
    if (!p) {
        error_line("unknown player");
        return;
    }
    int number = atoi(a[1]);
    if (number > p->round_count) {
        error_line("unknown round");
        return;
    }
    Round *r = p->rounds[number - 1];
    int strokes[HOLES], nets[HOLES], points[HOLES];
    allocation(r->handicap, r->course, strokes);
    printf("card %s %d: %s %s day %d handicap ", p->id, number,
           r->course->id, r->tee->id, r->day);
    print_handicap(r->has_handicap, r->handicap);
    putchar('\n');
    for (int i = 0; i < HOLES; ++i) {
        nets[i] = r->scores[i] > 0 ? r->scores[i] - strokes[i] : NO_SCORE;
        points[i] = nets[i] == NO_SCORE ? 0 :
                    r->course->pars[i] + 2 - nets[i];
        if (points[i] < 0) points[i] = 0;
        printf("%d %d %d ", i + 1, r->course->pars[i], r->course->si[i]);
        if (r->scores[i] == -1) printf("-");
        else if (r->scores[i] == 0) printf("X");
        else printf("%d", r->scores[i]);
        printf(" %d %d ", r->adjusted[i], strokes[i]);
        if (nets[i] == NO_SCORE) putchar('-');
        else printf("%d", nets[i]);
        printf(" %d\n", points[i]);
        if (i == 8) card_total("OUT", r, strokes, nets, points, 0, 9);
        if (i == 17) {
            card_total("IN", r, strokes, nets, points, 9, 18);
            card_total("TOTAL", r, strokes, nets, points, 0, 18);
        }
    }
    printf("ags %d diff ", r->ags);
    decimal(r->differential);
    putchar('\n');
}

static void command_stats(char **a) {
    Player *p = find_player(a[0]);
    if (!p) {
        error_line("unknown player");
        return;
    }
    const char *labels[7] = {
        "eagles", "birdies", "pars", "bogeys",
        "doubles", "others", "pickups"
    };
    int counts[7] = {0}, par_count[6] = {0}, par_total[6] = {0};
    int complete_count = 0, best = 0;
    long long complete_total = 0;
    for (int i = 0; i < p->round_count; ++i) {
        Round *r = p->rounds[i];
        if (is_complete(r)) {
            int total = 0;
            for (int h = 0; h < HOLES; ++h) total += r->scores[h];
            if (!complete_count || total < best) best = total;
            ++complete_count;
            complete_total += total;
        }
        for (int h = 0; h < HOLES; ++h) {
            int score = r->scores[h], par = r->course->pars[h];
            if (score == 0) ++counts[6];
            else if (score > 0) {
                int category = score - par + 2;
                if (category < 0) category = 0;
                if (category > 5) category = 5;
                ++counts[category];
                ++par_count[par];
                par_total[par] += score;
            }
        }
    }
    printf("stats %s: rounds %d best ", p->id, p->round_count);
    if (complete_count) printf("%d", best);
    else putchar('-');
    printf(" average ");
    print_average(complete_total, complete_count);
    for (int i = 0; i < 7; ++i)
        printf(" %s %d", labels[i], counts[i]);
    for (int par = 3; par <= 5; ++par) {
        printf(" par%d ", par);
        print_average(par_total[par], par_count[par]);
    }
    putchar('\n');
}

static void command_holestats(char **a) {
    Course *c = find_course(a[0]);
    if (!c) {
        error_line("unknown course");
        return;
    }
    int counts[HOLES] = {0}, totals[HOLES] = {0}, ranks[HOLES];
    int order[HOLES], considered = 0;
    for (int i = 0; i < player_count; ++i)
        for (int j = 0; j < players[i].round_count; ++j) {
            Round *r = players[i].rounds[j];
            if (r->course != c) continue;
            ++considered;
            for (int h = 0; h < HOLES; ++h)
                if (r->scores[h] > 0) {
                    ++counts[h];
                    totals[h] += r->scores[h];
                }
        }
    for (int i = 0; i < HOLES; ++i) order[i] = i;
    for (int i = 0; i < HOLES; ++i)
        for (int j = i + 1; j < HOLES; ++j) {
            int x = order[i], y = order[j], swap = 0;
            if (!counts[x]) swap = counts[y] != 0 || x > y;
            else if (counts[y]) {
                long long left = (long long)(totals[x] - c->pars[x] * counts[x]) * counts[y];
                long long right = (long long)(totals[y] - c->pars[y] * counts[y]) * counts[x];
                swap = right > left || (right == left && y < x);
            }
            if (swap) {
                int t = order[i];
                order[i] = order[j];
                order[j] = t;
            }
        }
    for (int i = 0; i < HOLES; ++i) ranks[order[i]] = i + 1;
    printf("holestats %s: rounds %d\n", c->id, considered);
    for (int h = 0; h < HOLES; ++h) {
        printf("%d par %d si %d scores %d avg ", h + 1,
               c->pars[h], c->si[h], counts[h]);
        print_average(totals[h], counts[h]);
        printf(" rank %d\n", ranks[h]);
    }
}

static int compare_players(const void *a, const void *b) {
    const Player *p = *(Player *const *)a, *q = *(Player *const *)b;
    if (p->has_index != q->has_index) return q->has_index - p->has_index;
    if (p->has_index && p->index != q->index)
        return p->index < q->index ? -1 : 1;
    return strcmp(p->id, q->id);
}

static void command_players(void) {
    Player *order[LIMIT];
    for (int i = 0; i < player_count; ++i) order[i] = &players[i];
    qsort(order, player_count, sizeof(Player *), compare_players);
    printf("players %d\n", player_count);
    for (int i = 0; i < player_count; ++i) {
        Player *p = order[i];
        printf("%s %s ", p->id, p->name);
        print_index(p->has_index, p->index);
        printf(" rounds %d\n", p->round_count);
    }
}

static void command_event(char **a, int argc) {
    if (find_event(a[0])) {
        error_line("duplicate event");
        return;
    }
    Tee *t = checked_tee(a[2], a[3]);
    if (!t) return;
    int allowance = atoi(a[5]);
    if (allowance < 1 || allowance > 100) {
        error_line("invalid allowance");
        return;
    }
    int count = argc - 6;
    Player *participants[10];
    for (int i = 0; i < count; ++i) {
        participants[i] = find_player(a[i + 6]);
        if (!participants[i]) {
            error_line("unknown player");
            return;
        }
    }
    int valid = count >= 2 && count <= 8;
    if (!strcmp(a[1], "MATCH") || !strcmp(a[1], "NASSAU")) valid = count == 2;
    else if (!strcmp(a[1], "FOURBALL")) valid = count == 4;
    else if (!strcmp(a[1], "BETTERBALL"))
        valid = count == 4 || count == 6 || count == 8;
    for (int i = 0; i < count; ++i)
        for (int j = 0; j < i; ++j)
            if (participants[i] == participants[j]) valid = 0;
    if (!valid) {
        error_line("invalid players");
        return;
    }
    Event *e = &events[event_count++];
    strcpy(e->id, a[0]);
    strcpy(e->format, a[1]);
    e->course = t->course;
    e->tee = t;
    e->day = atoi(a[4]);
    e->allowance = allowance;
    e->count = count;
    memcpy(e->players, participants, count * sizeof(Player *));
}

static const char *event_data(Event *event, EventData *data) {
    int minimum = 0;
    for (int i = 0; i < event->count; ++i) {
        Player *p = event->players[i];
        Round *chosen = NULL;
        for (int j = 0; j < p->round_count; ++j) {
            Round *r = p->rounds[j];
            if (r->course == event->course && r->tee == event->tee &&
                r->day == event->day) {
                chosen = r;
                break;
            }
        }
        if (!chosen) return "missing round";
        if (!chosen->has_handicap) return "no index";
        data->rounds[i] = chosen;
        data->handicaps[i] = round_half_up((long long)chosen->handicap *
                                            event->allowance, 100);
        if (!i || data->handicaps[i] < minimum)
            minimum = data->handicaps[i];
    }
    if (strcmp(event->format, "MATCH") && strcmp(event->format, "NASSAU") &&
        strcmp(event->format, "FOURBALL")) minimum = 0;
    for (int i = 0; i < event->count; ++i) {
        int strokes[HOLES];
        allocation(data->handicaps[i] - minimum, event->course, strokes);
        for (int h = 0; h < HOLES; ++h) {
            int score = data->rounds[i]->scores[h];
            data->nets[i][h] = score > 0 ? score - strokes[h] : NO_SCORE;
            int point = score > 0 ? event->course->pars[h] + 2 - data->nets[i][h] : 0;
            data->points[i][h] = point > 0 ? point : 0;
        }
    }
    return NULL;
}

static void event_values(Event *e, const EventData *d, int values[10][HOLES]) {
    for (int i = 0; i < e->count; ++i)
        for (int h = 0; h < HOLES; ++h) {
            if (!strcmp(e->format, "STROKE")) values[i][h] = d->nets[i][h];
            else if (!strcmp(e->format, "STABLEFORD")) values[i][h] = d->points[i][h];
            else {
                int net = d->nets[i][h], par = e->course->pars[h];
                values[i][h] = net == NO_SCORE || net > par ? -1 : (net < par ? 1 : 0);
            }
        }
}

static int compare_countback(const int *a, const int *b, int larger) {
    const int starts[5] = {0, 9, 12, 15, 17};
    for (int k = 0; k < 5; ++k) {
        int x = 0, y = 0;
        for (int h = starts[k]; h < HOLES; ++h) {
            x += a[h];
            y += b[h];
        }
        if (x != y) return larger ? (x > y ? -1 : 1) : (x < y ? -1 : 1);
    }
    return 0;
}

static int compare_rank(Event *e, int *valuesA, int *valuesB,
                        int a, int b, int larger) {
    int order = compare_countback(valuesA, valuesB, larger);
    return order ? order : strcmp(e->players[a]->id, e->players[b]->id);
}

static int event_ranking(Event *e, const EventData *d, int order[10],
                         int values[10][HOLES]) {
    int count = 0;
    event_values(e, d, values);
    for (int i = 0; i < e->count; ++i) {
        if (!strcmp(e->format, "STROKE") && !is_complete(d->rounds[i])) continue;
        order[count++] = i;
    }
    int larger = strcmp(e->format, "STROKE") != 0;
    for (int i = 0; i < count; ++i)
        for (int j = i + 1; j < count; ++j) {
            int a = order[i], b = order[j];
            if (compare_rank(e, values[b], values[a], b, a, larger) < 0) {
                order[i] = b;
                order[j] = a;
            }
        }
    return count;
}

static void individual_results(Event *e, const EventData *d) {
    int order[10], values[10][HOLES];
    int count = event_ranking(e, d, order, values);
    for (int i = 0; i < count; ++i) {
        int index = order[i], total = 0, gross = 0;
        for (int h = 0; h < HOLES; ++h) {
            total += values[index][h];
            gross += d->rounds[index]->scores[h];
        }
        printf("%d %s ", i + 1, e->players[index]->id);
        if (!strcmp(e->format, "STROKE"))
            printf("net %d gross %d", total, gross);
        else if (!strcmp(e->format, "STABLEFORD"))
            printf("points %d", total);
        else {
            char status[24];
            if (!total) strcpy(status, "AS");
            else snprintf(status, sizeof(status), "%d %s", abs(total),
                          total > 0 ? "UP" : "DN");
            printf("%s", status);
        }
        printf(" hcp ");
        print_handicap(1, d->handicaps[index]);
        putchar('\n');
    }
    if (!strcmp(e->format, "STROKE")) {
        int absent[10], absent_count = 0;
        for (int i = 0; i < e->count; ++i)
            if (!is_complete(d->rounds[i])) absent[absent_count++] = i;
        for (int i = 0; i < absent_count; ++i)
            for (int j = i + 1; j < absent_count; ++j)
                if (strcmp(e->players[absent[j]]->id, e->players[absent[i]]->id) < 0) {
                    int tmp = absent[i];
                    absent[i] = absent[j];
                    absent[j] = tmp;
                }
        for (int i = 0; i < absent_count; ++i) {
            int index = absent[i];
            printf("NR %s hcp ", e->players[index]->id);
            print_handicap(1, d->handicaps[index]);
            putchar('\n');
        }
        if (count) {
            int winner = order[0];
            for (int i = 1; i < count; ++i) {
                int other = order[i];
                int cmp = compare_countback(d->rounds[other]->scores,
                                            d->rounds[winner]->scores, 0);
                if (cmp < 0 || (cmp == 0 &&
                    strcmp(e->players[other]->id, e->players[winner]->id) < 0))
                    winner = other;
            }
            int total = 0;
            for (int h = 0; h < HOLES; ++h) total += d->rounds[winner]->scores[h];
            printf("gross %s %d\n", e->players[winner]->id, total);
        }
    }
}

static void match_holes(Event *e, const EventData *d, int holes[HOLES],
                        char names[2][40]) {
    int fourball = !strcmp(e->format, "FOURBALL");
    if (fourball) {
        snprintf(names[0], 40, "%s+%s", e->players[0]->id, e->players[1]->id);
        snprintf(names[1], 40, "%s+%s", e->players[2]->id, e->players[3]->id);
    } else {
        strcpy(names[0], e->players[0]->id);
        strcpy(names[1], e->players[1]->id);
    }
    for (int h = 0; h < HOLES; ++h) {
        int best[2] = {NO_SCORE, NO_SCORE};
        for (int side = 0; side < 2; ++side) {
            int from = fourball ? side * 2 : side;
            int size = fourball ? 2 : 1;
            for (int j = 0; j < size; ++j) {
                int net = d->nets[from + j][h];
                if (net != NO_SCORE &&
                    (best[side] == NO_SCORE || net < best[side]))
                    best[side] = net;
            }
        }
        holes[h] = best[0] == NO_SCORE ? (best[1] == NO_SCORE ? 0 : -1)
                 : best[1] == NO_SCORE || best[0] < best[1] ? 1
                 : best[0] > best[1] ? -1 : 0;
    }
}

static void play_match(const char names[2][40], const int holes[HOLES],
                       int first, int last, int show_status, const char *label) {
    int lead = 0, remaining = 0;
    char statuses[256] = "";
    for (int h = first; h < last; ++h) {
        char status[24];
        lead += holes[h];
        if (!lead) strcpy(status, "AS");
        else snprintf(status, sizeof(status), "%d %s", abs(lead),
                      lead > 0 ? "UP" : "DN");
        if (h > first) strcat(statuses, ", ");
        strcat(statuses, status);
        remaining = last - h - 1;
        if (abs(lead) > remaining || remaining == 0) break;
    }
    if (show_status) printf("status %s\n", statuses);
    printf("%s ", label);
    if (!lead) printf("AS\n");
    else if (remaining) printf("%s %d&%d\n", lead > 0 ? names[0] : names[1],
                               abs(lead), remaining);
    else printf("%s %d UP\n", lead > 0 ? names[0] : names[1], abs(lead));
}

static void match_results(Event *e, const EventData *d) {
    int minimum = d->handicaps[0];
    for (int i = 1; i < e->count; ++i)
        if (d->handicaps[i] < minimum) minimum = d->handicaps[i];
    printf("strokes");
    for (int i = 0; i < e->count; ++i)
        printf(" %s %d", e->players[i]->id, d->handicaps[i] - minimum);
    putchar('\n');
    int holes[HOLES];
    char names[2][40];
    match_holes(e, d, holes, names);
    if (!strcmp(e->format, "NASSAU")) {
        play_match((const char (*)[40])names, holes, 0, 9, 0, "front");
        play_match((const char (*)[40])names, holes, 9, 18, 0, "back");
        play_match((const char (*)[40])names, holes, 0, 18, 0, "total");
    } else {
        play_match((const char (*)[40])names, holes, 0, 18, 1, "result");
    }
}

static void betterball_results(Event *e, const EventData *d) {
    int order[4], values[10][HOLES];
    int count = e->count / 2;
    for (int team = 0; team < count; ++team) {
        order[team] = team;
        for (int h = 0; h < HOLES; ++h) {
            int a = d->points[2 * team][h], b = d->points[2 * team + 1][h];
            values[team][h] = a > b ? a : b;
        }
    }
    for (int i = 0; i < count; ++i)
        for (int j = i + 1; j < count; ++j) {
            int a = order[i], b = order[j];
            int cmp = compare_countback(values[b], values[a], 1);
            if (cmp < 0 || (cmp == 0 &&
                strcmp(e->players[2 * b]->id, e->players[2 * a]->id) < 0)) {
                order[i] = b;
                order[j] = a;
            }
        }
    for (int rank = 0; rank < count; ++rank) {
        int team = order[rank], score = 0;
        for (int h = 0; h < HOLES; ++h) score += values[team][h];
        printf("%d %s+%s points %d hcp ", rank + 1,
               e->players[2 * team]->id, e->players[2 * team + 1]->id, score);
        print_handicap(1, d->handicaps[2 * team]);
        putchar(' ');
        print_handicap(1, d->handicaps[2 * team + 1]);
        putchar('\n');
    }
}

static void skins_results(Event *e, const EventData *d) {
    int totals[10] = {0}, carry = 0, last_count = 0, last[10];
    for (int h = 0; h < HOLES; ++h) {
        ++carry;
        int best = NO_SCORE, winners[10], count = 0;
        for (int i = 0; i < e->count; ++i) {
            int net = d->nets[i][h];
            if (net == NO_SCORE) continue;
            if (best == NO_SCORE || net < best) {
                best = net;
                winners[0] = i;
                count = 1;
            } else if (net == best) winners[count++] = i;
        }
        last_count = count;
        memcpy(last, winners, count * sizeof(int));
        if (count == 1) {
            printf("hole %d %s %d\n", h + 1, e->players[winners[0]]->id, carry);
            totals[winners[0]] += 100 * carry;
            carry = 0;
        }
    }
    if (carry) {
        int ids[10], count = last_count ? last_count : e->count;
        for (int i = 0; i < count; ++i) ids[i] = last_count ? last[i] : i;
        for (int i = 0; i < count; ++i)
            for (int j = i + 1; j < count; ++j)
                if (strcmp(e->players[ids[j]]->id, e->players[ids[i]]->id) < 0) {
                    int t = ids[i]; ids[i] = ids[j]; ids[j] = t;
                }
        int share = carry * 100 / count;
        printf("carry %d", carry);
        for (int i = 0; i < count; ++i) {
            totals[ids[i]] += share;
            printf(" %s", e->players[ids[i]]->id);
        }
        putchar('\n');
    }
    int order[10];
    for (int i = 0; i < e->count; ++i) order[i] = i;
    for (int i = 0; i < e->count; ++i)
        for (int j = i + 1; j < e->count; ++j) {
            int a = order[i], b = order[j];
            if (totals[b] > totals[a] || (totals[b] == totals[a] &&
                strcmp(e->players[b]->id, e->players[a]->id) < 0)) {
                order[i] = b;
                order[j] = a;
            }
        }
    for (int i = 0; i < e->count; ++i) {
        int id = order[i];
        printf("%s %d.%02d\n", e->players[id]->id, totals[id] / 100, totals[id] % 100);
    }
}

static void command_results(char **a) {
    Event *e = find_event(a[0]);
    if (!e) {
        error_line("unknown event");
        return;
    }
    EventData data;
    const char *problem = event_data(e, &data);
    if (problem) {
        error_line(problem);
        return;
    }
    printf("results %s: %s %s %s day %d allowance %d\n", e->id, e->format,
           e->course->id, e->tee->id, e->day, e->allowance);
    if (!strcmp(e->format, "STROKE") || !strcmp(e->format, "STABLEFORD") ||
        !strcmp(e->format, "PAR")) individual_results(e, &data);
    else if (!strcmp(e->format, "BETTERBALL")) betterball_results(e, &data);
    else if (!strcmp(e->format, "SKINS")) skins_results(e, &data);
    else match_results(e, &data);
}

static void command_merit(void) {
    int points[LIMIT] = {0}, wins[LIMIT] = {0}, played[LIMIT] = {0};
    int counted = 0;
    const int awards[8] = {10, 8, 6, 5, 4, 3, 2, 1};
    for (int i = 0; i < event_count; ++i) {
        Event *e = &events[i];
        if (strcmp(e->format, "STROKE") && strcmp(e->format, "STABLEFORD") &&
            strcmp(e->format, "PAR")) continue;
        EventData data;
        if (event_data(e, &data)) continue;
        ++counted;
        int order[10], values[10][HOLES];
        int n = event_ranking(e, &data, order, values);
        for (int j = 0; j < e->count; ++j) ++played[e->players[j] - players];
        for (int rank = 0; rank < n; ++rank) {
            int index = e->players[order[rank]] - players;
            points[index] += awards[rank];
            if (rank == 0) ++wins[index];
        }
    }
    printf("merit: events %d\n", counted);
    int order[LIMIT], count = 0;
    for (int i = 0; i < player_count; ++i)
        if (played[i]) order[count++] = i;
    for (int i = 0; i < count; ++i)
        for (int j = i + 1; j < count; ++j) {
            int a = order[i], b = order[j];
            if (points[b] > points[a] || (points[b] == points[a] &&
                (wins[b] > wins[a] || (wins[b] == wins[a] &&
                    strcmp(players[b].id, players[a].id) < 0)))) {
                order[i] = b;
                order[j] = a;
            }
        }
    for (int i = 0; i < count; ++i) {
        int id = order[i];
        printf("%d %s %d wins %d played %d\n", i + 1, players[id].id,
               points[id], wins[id], played[id]);
    }
}

static void execute(char *line) {
    char *parts[64], *token = strtok(line, " \r\n");
    int count = 0;
    while (token) {
        parts[count++] = token;
        token = strtok(NULL, " \r\n");
    }
    if (!count) return;
    char *op = parts[0], **a = parts + 1;
    int argc = count - 1;
    if (!strcmp(op, "COURSE")) command_course(a);
    else if (!strcmp(op, "TEE")) command_tee(a);
    else if (!strcmp(op, "PLAYER")) command_player(a, argc);
    else if (!strcmp(op, "ROUND")) command_round(a);
    else if (!strcmp(op, "REMOVE")) command_remove(a);
    else if (!strcmp(op, "INDEX")) command_index(a);
    else if (!strcmp(op, "HISTORY")) command_history(a);
    else if (!strcmp(op, "LOWINDEX")) command_lowindex(a);
    else if (!strcmp(op, "COURSEHCP")) command_coursehcp(a);
    else if (!strcmp(op, "HCPTABLE")) command_hcptable(a);
    else if (!strcmp(op, "CARD")) command_card(a);
    else if (!strcmp(op, "STATS")) command_stats(a);
    else if (!strcmp(op, "HOLESTATS")) command_holestats(a);
    else if (!strcmp(op, "PLAYERS")) command_players();
    else if (!strcmp(op, "EVENT")) command_event(a, argc);
    else if (!strcmp(op, "RESULTS")) command_results(a);
    else if (!strcmp(op, "MERIT")) command_merit();
}

int main(void) {
    int n;
    if (scanf("%d", &n) != 1) return 0;
    getchar();
    char line[256];
    for (int i = 0; i < n; ++i) {
        if (!fgets(line, sizeof(line), stdin)) break;
        execute(line);
    }
    return 0;
}
