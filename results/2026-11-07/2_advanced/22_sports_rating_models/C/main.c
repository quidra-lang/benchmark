#include "ratings.h"

typedef struct Allocation { struct Allocation *next; max_align_t alignment; } Allocation;
static Allocation *allocations;
static void release_all(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations);
        allocations = next;
    }
}
void *allocate(size_t bytes) {
    static bool registered;
    if (!registered) { atexit(release_all); registered = true; }
    Allocation *block = calloc(1, sizeof(*block) + bytes);
    if (!block) exit(EXIT_FAILURE);
    block->next = allocations;
    allocations = block;
    return block + 1;
}
static char *formatted(const char *pattern, va_list arguments) {
    va_list copy;
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    if (length < 0) exit(EXIT_FAILURE);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    return result;
}
char *format(const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *result = formatted(pattern, arguments);
    va_end(arguments);
    return result;
}
void text_add(Text *text, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *part = formatted(pattern, arguments);
    va_end(arguments);
    size_t length = strlen(part);
    if (text->size + length + 1 > text->capacity) {
        size_t capacity = text->capacity ? 2 * text->capacity : 64;
        while (capacity < text->size + length + 1) capacity *= 2;
        char *data = allocate(capacity);
        if (text->size) memcpy(data, text->data, text->size);
        text->data = data;
        text->capacity = capacity;
    }
    memcpy(text->data + text->size, part, length + 1);
    text->size += length;
}
void add_line(Lines *lines, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *line = formatted(pattern, arguments);
    va_end(arguments);
    if (lines->count == lines->capacity) {
        int capacity = lines->capacity ? 2 * lines->capacity : 32;
        char **items = allocate((size_t)capacity * sizeof(*items));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(*items));
        lines->items = items;
        lines->capacity = capacity;
    }
    lines->items[lines->count++] = line;
}
Lines read_lines(const char *name) {
    FILE *file = fopen(format("input/%s", name), "rb");
    if (!file) exit(EXIT_FAILURE);
    Lines result = {0};
    Text line = {0};
    int character;
    while ((character = fgetc(file)) != EOF) {
        if (character == '\n') {
            add_line(&result, "%s", line.data ? line.data : "");
            line.size = 0;
            if (line.data) line.data[0] = '\0';
        } else text_add(&line, "%c", character);
    }
    if (ferror(file)) exit(EXIT_FAILURE);
    fclose(file);
    return result;
}
Lines split_text(const char *text, char separator) {
    Lines result = {0};
    size_t start = 0;
    for (size_t i = 0;; ++i) if (!text[i] || text[i] == separator) {
        char *part = allocate(i - start + 1);
        memcpy(part, text + start, i - start);
        add_line(&result, "%s", part);
        if (!text[i]) break;
        start = i + 1;
    }
    return result;
}
void paragraph(Lines *target, Lines source) {
    if (target->count) add_line(target, "");
    for (int i = 0; i < source.count; ++i) add_line(target, "%s", source.items[i]);
}

static const char *comparison_names[] = {"standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag"};
static const char *prediction_names[] = {"base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble"};
static const char *link_names[] = {"colley", "massey", "od", "winpct"};
static const int link_predictions[] = {2,3,5,6};
typedef struct { int played, won, drawn, lost, scored, conceded; Integer points; } Record;
typedef struct { Record records[30]; Integer h2h_points[30]; int h2h_difference[30], order[30], positions[30]; } Standings;
typedef struct { Match *match; int opponent, scored, conceded; bool home; char letter; } Appearance;
typedef struct { int length, first, last; } Streak;
typedef struct {
    EloRun elo;
    double colley[30], massey[30], strengths[30], offense[30], defense[30], od[30];
    double home_advantage, home_factor;
    Fraction win_percentages[30];
} ModelFit;
typedef struct { Match *match; double probabilities[8], losses[8], briers[8], error; int scores[8]; } Prediction;
typedef struct { int number, training, start, count; double base, home_factor; Link links[4]; } ValidationRound;
typedef struct {
    Standings current;
    double ratings[30], opponent_strength[30];
    Integer total_points[30], titles[30], tops[30], bottoms[30];
    int order[30], ranks[30];
} Projection;
typedef struct {
    Season *season;
    Standings final, round_tables[40];
    Appearance appearances[30][40];
    int appearance_count[30];
    Streak wins[30], unbeaten[30];
    ModelFit fit;
    Fraction sos[30], sos2[30], rpi[30];
    double pythag[30], luck[30];
    Comparison comparison[9][30];
    int ranks[6][30], totals[30];
    ValidationRound rounds[40];
    int round_count, prediction_count;
    Prediction predictions[600];
    double losses[8], briers[8], skills[8];
    Fraction accuracies[8];
    int rankings[3][8];
    Projection projection;
} Analysis;

static void record_add(Record *record, int scored, int conceded, const Settings *settings) {
    ++record->played;
    record->scored += scored;
    record->conceded += conceded;
    if (scored > conceded) { ++record->won; record->points += settings->win_points; }
    else if (scored == conceded) { ++record->drawn; record->points += settings->draw_points; }
    else ++record->lost;
}
static bool standing_before(const Standings *table, int first, int second) {
    const Record *a = &table->records[first], *b = &table->records[second];
    if (a->points != b->points) return a->points > b->points;
    if (table->h2h_points[first] != table->h2h_points[second]) return table->h2h_points[first] > table->h2h_points[second];
    if (table->h2h_difference[first] != table->h2h_difference[second]) return table->h2h_difference[first] > table->h2h_difference[second];
    if (a->scored - a->conceded != b->scored - b->conceded) return a->scored - a->conceded > b->scored - b->conceded;
    if (a->scored != b->scored) return a->scored > b->scored;
    return first < second;
}
static Standings standings(const Season *season, int count) {
    Standings table = {0};
    for (int i = 0; i < count; ++i) {
        Match match = season->matches[i];
        record_add(&table.records[match.home], match.home_score, match.away_score, &season->settings);
        record_add(&table.records[match.away], match.away_score, match.home_score, &season->settings);
    }
    for (int i = 0; i < count; ++i) {
        Match match = season->matches[i];
        if (table.records[match.home].points != table.records[match.away].points) continue;
        table.h2h_difference[match.home] += match.margin;
        table.h2h_difference[match.away] -= match.margin;
        if (match.margin > 0) table.h2h_points[match.home] += season->settings.win_points;
        else if (match.margin < 0) table.h2h_points[match.away] += season->settings.win_points;
        else {
            table.h2h_points[match.home] += season->settings.draw_points;
            table.h2h_points[match.away] += season->settings.draw_points;
        }
    }
    for (int team = 0; team < season->n; ++team) {
        int position = team;
        while (position && standing_before(&table, team, table.order[position - 1])) {
            table.order[position] = table.order[position - 1];
            --position;
        }
        table.order[position] = team;
    }
    for (int i = 0; i < season->n; ++i) table.positions[table.order[i]] = i + 1;
    return table;
}
static ModelFit fit_models(const Season *season, int count) {
    int n = season->n;
    Settings settings = season->settings;
    ModelFit fit = {0};
    fit.elo = run_elo(n, season->matches, count, settings.elo_k, settings.elo_home, settings.elo_initial);
    colley_ratings(n, season->matches, count, fit.colley);
    fit.home_advantage = massey_ratings(n, season->matches, count, fit.massey);
    fit.home_factor = bradley_terry(n, season->matches, count, settings.bt_iterations, fit.strengths);
    offense_defense(n, season->matches, count, settings.od_iterations, fit.offense, fit.defense, fit.od);
    Standings table = standings(season, count);
    for (int i = 0; i < n; ++i) {
        Record record = table.records[i];
        fit.win_percentages[i] = fraction(2 * record.won + record.drawn, 2 * record.played);
    }
    return fit;
}
static double feature(const ModelFit *fit, int model, const Match *match) {
    int home = match->home, away = match->away;
    if (model == 0) return fit->colley[home] - fit->colley[away];
    if (model == 1) return fit->massey[home] - fit->massey[away];
    if (model == 2) return log(fit->od[home]) - log(fit->od[away]);
    return fraction_real(fit->win_percentages[home]) - fraction_real(fit->win_percentages[away]);
}
static Streak longest_streak(const Appearance *items, int count, bool unbeaten) {
    Streak best = {0};
    int start = 0, length = 0;
    for (int i = 0; i < count; ++i) {
        if (items[i].letter == 'L' || (!unbeaten && items[i].letter != 'W')) { length = 0; continue; }
        if (!length) start = i;
        ++length;
        if (length > best.length) best = (Streak){length, items[start].match->round, items[i].match->round};
    }
    return best;
}
static Fraction opponent_average(const Analysis *analysis, int team, const Fraction *values) {
    Fraction total = fraction(0, 1);
    for (int i = 0; i < analysis->appearance_count[team]; ++i) total = fraction_add(total, values[analysis->appearances[team][i].opponent]);
    return fraction_divide(total, analysis->appearance_count[team]);
}
static void indicators(Analysis *analysis) {
    int n = analysis->season->n;
    for (int team = 0; team < n; ++team) analysis->sos[team] = opponent_average(analysis, team, analysis->fit.win_percentages);
    for (int team = 0; team < n; ++team) analysis->sos2[team] = opponent_average(analysis, team, analysis->sos);
    for (int team = 0; team < n; ++team) {
        Fraction weighted = fraction_add(analysis->fit.win_percentages[team], fraction_multiply(fraction(2, 1), analysis->sos[team]));
        analysis->rpi[team] = fraction_divide(fraction_add(weighted, analysis->sos2[team]), 4);
        Record record = analysis->final.records[team];
        analysis->pythag[team] = 1 / (1 + pow((double)record.conceded / record.scored, analysis->season->settings.exponent));
        analysis->luck[team] = fraction_real(analysis->fit.win_percentages[team]) - analysis->pythag[team];
        double values[] = {-(double)analysis->final.positions[team], decimal_value(analysis->fit.elo.ratings[team], 2), decimal_value(analysis->fit.colley[team], 4), decimal_value(analysis->fit.massey[team], 4), decimal_value(analysis->fit.strengths[team], 4), decimal_value(analysis->fit.od[team], 2), 0, 0, decimal_value(analysis->pythag[team], 4)};
        for (int model = 0; model < 9; ++model) analysis->comparison[model][team].real = values[model];
        analysis->comparison[6][team] = (Comparison){true, analysis->fit.win_percentages[team], 0};
        analysis->comparison[7][team] = (Comparison){true, analysis->rpi[team], 0};
    }
    for (int model = 0; model < 6; ++model) for (int team = 0; team < n; ++team) {
        int rank = 1;
        for (int other = 0; other < n; ++other) rank += comparison_compare(analysis->comparison[model + 1][other], analysis->comparison[model + 1][team]) > 0;
        analysis->ranks[model][team] = rank;
        analysis->totals[team] += rank;
    }
}

static void validate(Analysis *analysis) {
    Season *season = analysis->season;
    for (int number = season->settings.holdout_round; number <= season->rounds; ++number) {
        ValidationRound *round = &analysis->rounds[analysis->round_count++];
        round->number = number;
        round->training = matches_before(season, number);
        ModelFit fit = fit_models(season, round->training);
        round->home_factor = fit.home_factor;
        int result_sum = 0;
        for (int i = 0; i < round->training; ++i) result_sum += season->matches[i].y2;
        round->base = (double)result_sum / (2 * round->training);
        for (int model = 0; model < 4; ++model) {
            double features[600];
            for (int i = 0; i < round->training; ++i) features[i] = feature(&fit, model, &season->matches[i]);
            round->links[model] = fit_link(features, season->matches, round->training, season->settings.link_iterations);
        }
        round->start = analysis->prediction_count;
        int end = matches_before(season, number + 1);
        for (int i = round->training; i < end; ++i) {
            Prediction *prediction = &analysis->predictions[analysis->prediction_count++];
            Match *match = &season->matches[i];
            prediction->match = match;
            double *probabilities = prediction->probabilities;
            probabilities[0] = round->base;
            probabilities[1] = expected_score(fit.elo.ratings[match->home], fit.elo.ratings[match->away], (double)season->settings.elo_home);
            for (int model = 0; model < 4; ++model) {
                Link link = round->links[model];
                probabilities[link_predictions[model]] = sigma(link.alpha + link.beta * feature(&fit, model, match));
            }
            double home = fit.home_factor * fit.strengths[match->home];
            probabilities[4] = home / (home + fit.strengths[match->away]);
            double total = 0;
            for (int model = 1; model <= 6; ++model) total += probabilities[model];
            probabilities[7] = total / 6;
            prediction->error = match->margin - (fit.massey[match->home] - fit.massey[match->away] + fit.home_advantage);
            for (int model = 0; model < 8; ++model) {
                prediction->losses[model] = log_loss(probabilities[model], match->y2);
                prediction->briers[model] = brier_score(probabilities[model], match->y2);
                prediction->scores[model] = correctness(probabilities[model], match->y2);
            }
        }
        round->count = analysis->prediction_count - round->start;
    }
    for (int model = 0; model < 8; ++model) {
        int correct = 0;
        for (int i = 0; i < analysis->prediction_count; ++i) {
            analysis->losses[model] += analysis->predictions[i].losses[model];
            analysis->briers[model] += analysis->predictions[i].briers[model];
            correct += analysis->predictions[i].scores[model];
        }
        analysis->losses[model] /= analysis->prediction_count;
        analysis->briers[model] /= analysis->prediction_count;
        analysis->accuracies[model] = fraction(correct, 2 * analysis->prediction_count);
    }
    for (int model = 0; model < 8; ++model) analysis->skills[model] = 1 - analysis->briers[model] / analysis->briers[0];
    for (int kind = 0; kind < 3; ++kind) for (int model = 0; model < 8; ++model) {
        int position = model;
        while (position > 0) {
            int previous = analysis->rankings[kind][position - 1];
            bool before;
            if (kind == 2) before = fraction_compare(analysis->accuracies[model], analysis->accuracies[previous]) > 0;
            else {
                const double *values = kind == 0 ? analysis->losses : analysis->briers;
                before = decimal_value(values[model], 4) < decimal_value(values[previous], 4);
            }
            if (!before) break;
            analysis->rankings[kind][position] = previous;
            --position;
        }
        analysis->rankings[kind][position] = model;
    }
}

static void points_order(int *order, const Integer *points, const int *positions, int n) {
    for (int team = 0; team < n; ++team) {
        int position = team;
        while (position) {
            int previous = order[position - 1];
            if (points[team] < points[previous] || (points[team] == points[previous] && positions[team] > positions[previous])) break;
            order[position] = previous;
            --position;
        }
        order[position] = team;
    }
}
static void project(Analysis *analysis) {
    Season *season = analysis->season;
    Settings settings = season->settings;
    Projection *projection = &analysis->projection;
    int current_count = matches_before(season, settings.holdout_round);
    projection->current = standings(season, current_count);
    EloRun run = run_elo(season->n, season->matches, current_count, settings.elo_k, settings.elo_home, settings.elo_initial);
    memcpy(projection->ratings, run.ratings, (size_t)season->n * sizeof(double));
    double probabilities[600];
    for (int i = current_count; i < season->count; ++i) {
        Match match = season->matches[i];
        probabilities[i] = expected_score(run.ratings[match.home], run.ratings[match.away], (double)settings.elo_home);
    }
    Integer random = settings.seed;
    for (Integer simulation = 0; simulation < settings.simulations; ++simulation) {
        Integer points[30];
        int order[30];
        for (int team = 0; team < season->n; ++team) points[team] = projection->current.records[team].points;
        for (int i = current_count; i < season->count; ++i) {
            random = 48271 * random % 2147483647;
            double uniform = (double)random / 2147483647;
            Match match = season->matches[i];
            points[uniform < probabilities[i] ? match.home : match.away] += settings.win_points;
        }
        points_order(order, points, projection->current.positions, season->n);
        for (int place = 1; place <= season->n; ++place) {
            int team = order[place - 1];
            projection->total_points[team] += points[team];
            projection->titles[team] += place == 1;
            projection->tops[team] += place <= settings.top_positions;
            projection->bottoms[team] += place >= season->n - settings.bottom_positions + 1;
        }
    }
    points_order(projection->order, projection->total_points, projection->current.positions, season->n);
    for (int i = 0; i < season->n; ++i) projection->ranks[projection->order[i]] = i + 1;
    for (int team = 0; team < season->n; ++team) {
        int count = 0;
        double total = 0;
        for (int i = current_count; i < season->count; ++i) {
            Match match = season->matches[i];
            if (match.home == team) { total += run.ratings[match.away]; ++count; }
            else if (match.away == team) { total += run.ratings[match.home]; ++count; }
        }
        projection->opponent_strength[team] = total / count;
    }
}

static Analysis *analyze(Season *season) {
    Analysis *analysis = allocate(sizeof(*analysis));
    analysis->season = season;
    analysis->final = standings(season, season->count);
    analysis->fit = fit_models(season, season->count);
    for (int round = 1; round <= season->rounds; ++round) analysis->round_tables[round - 1] = standings(season, matches_before(season, round + 1));
    for (int team = 0; team < season->n; ++team) {
        for (int i = 0; i < season->count; ++i) {
            Match *match = &season->matches[i];
            if (match->home != team && match->away != team) continue;
            bool home = match->home == team;
            int scored = home ? match->home_score : match->away_score, conceded = home ? match->away_score : match->home_score;
            analysis->appearances[team][analysis->appearance_count[team]++] = (Appearance){match, home ? match->away : match->home, scored, conceded, home, scored > conceded ? 'W' : scored == conceded ? 'D' : 'L'};
        }
        analysis->wins[team] = longest_streak(analysis->appearances[team], analysis->appearance_count[team], false);
        analysis->unbeaten[team] = longest_streak(analysis->appearances[team], analysis->appearance_count[team], true);
    }
    indicators(analysis);
    validate(analysis);
    project(analysis);
    return analysis;
}

static char *record_text(const Analysis *analysis, int team, int category, int opponent) {
    int won = 0, drawn = 0, lost = 0;
    for (int i = 0; i < analysis->appearance_count[team]; ++i) {
        Appearance item = analysis->appearances[team][i];
        if ((category == 1 && !item.home) || (category == 2 && item.home)) continue;
        if (category == 3 && abs(item.scored - item.conceded) > analysis->season->settings.close_margin) continue;
        if (category == 4 && item.opponent != opponent) continue;
        won += item.letter == 'W';
        drawn += item.letter == 'D';
        lost += item.letter == 'L';
    }
    return format("%d-%d-%d", won, drawn, lost);
}
static Lines standings_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck");
    for (int position = 0; position < analysis->season->n; ++position) {
        int team = analysis->final.order[position], count = analysis->appearance_count[team];
        const Appearance *items = analysis->appearances[team];
        Record record = analysis->final.records[team];
        Text form = {0};
        for (int i = count - analysis->season->settings.form_length; i < count; ++i) text_add(&form, "%c", items[i].letter);
        int streak = 0;
        for (int i = count - 1; i >= 0 && items[i].letter == items[count - 1].letter; --i) ++streak;
        add_line(&lines, "%d,%s,%s,%d,%d,%d,%d,%d,%d,%d,%lld,%s,%s,%s,%c%d,%s,%d,%d,%s,%s,%s,%s,%s,%s", position + 1, analysis->season->teams[team].code, analysis->season->teams[team].name, record.played, record.won, record.drawn, record.lost, record.scored, record.conceded, record.scored - record.conceded, record.points, record_text(analysis, team, 1, 0), record_text(analysis, team, 2, 0), form.data, items[count - 1].letter, streak, record_text(analysis, team, 3, 0), analysis->wins[team].length, analysis->unbeaten[team].length, fraction_text(analysis->fit.win_percentages[team]), fraction_fixed(analysis->sos[team], 4), fraction_fixed(analysis->sos2[team], 4), fraction_fixed(analysis->rpi[team], 4), fixed(analysis->pythag[team], 4), fixed(analysis->luck[team], 4));
    }
    return lines;
}
static Lines ratings_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank");
    int order[30];
    for (int team = 0; team < analysis->season->n; ++team) {
        int position = team;
        while (position && analysis->totals[team] < analysis->totals[order[position - 1]]) { order[position] = order[position - 1]; --position; }
        order[position] = team;
    }
    const ModelFit *fit = &analysis->fit;
    for (int i = 0; i < analysis->season->n; ++i) {
        int team = order[i], best = 31, worst = 0;
        for (int model = 0; model < 6; ++model) {
            if (analysis->ranks[model][team] < best) best = analysis->ranks[model][team];
            if (analysis->ranks[model][team] > worst) worst = analysis->ranks[model][team];
        }
        add_line(&lines, "%s,%s,%d,%s,%d,%s,%d,%s,%d,%s,%s,%s,%d,%s,%d,%d,%d,%d", analysis->season->teams[team].code, fixed(fit->elo.ratings[team], 2), analysis->ranks[0][team], fixed(fit->colley[team], 4), analysis->ranks[1][team], fixed(fit->massey[team], 4), analysis->ranks[2][team], fixed(fit->strengths[team], 4), analysis->ranks[3][team], fixed(fit->offense[team], 2), fixed(fit->defense[team], 4), fixed(fit->od[team], 2), analysis->ranks[4][team], fraction_fixed(fit->win_percentages[team], 4), analysis->ranks[5][team], analysis->totals[team], best, worst);
    }
    return lines;
}
static Lines history_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "round,team,elo,change,elo_rank,points,position");
    for (int round = 0; round < analysis->season->rounds; ++round) {
        const double *ratings = analysis->fit.elo.round_ratings[round];
        for (int team = 0; team < analysis->season->n; ++team) {
            int rank = 1;
            for (int other = 0; other < analysis->season->n; ++other) rank += decimal_value(ratings[other], 2) > decimal_value(ratings[team], 2);
            double previous = round ? analysis->fit.elo.round_ratings[round - 1][team] : (double)analysis->season->settings.elo_initial;
            const Standings *table = &analysis->round_tables[round];
            add_line(&lines, "%d,%s,%s,%s,%d,%lld,%d", round + 1, analysis->season->teams[team].code, fixed(ratings[team], 2), fixed(ratings[team] - previous, 2), rank, table->records[team].points, table->positions[team]);
        }
    }
    return lines;
}
static Lines summary_lines(const Analysis *analysis) {
    int won = 0, drawn = 0, lost = 0, result_sum = 0;
    for (int i = 0; i < analysis->season->count; ++i) {
        int y2 = analysis->season->matches[i].y2;
        won += y2 == 2; drawn += y2 == 1; lost += y2 == 0; result_sum += y2;
    }
    Lines lines = {0};
    add_line(&lines, "season teams %d matches %d rounds %d", analysis->season->n, analysis->season->count, analysis->season->rounds);
    add_line(&lines, "home won %d drawn %d lost %d rate %s", won, drawn, lost, fraction_with_real(fraction(result_sum, 2 * analysis->season->count)));
    add_line(&lines, "massey_home_advantage %s", fixed(analysis->fit.home_advantage, 4));
    add_line(&lines, "bt_home_factor %s", fixed(analysis->fit.home_factor, 4));
    return lines;
}
static double winning_expected(const Analysis *analysis, int index) {
    return analysis->season->matches[index].margin > 0 ? analysis->fit.elo.expected[index] : 1 - analysis->fit.elo.expected[index];
}
static Lines upset_lines(const Analysis *analysis) {
    int order[600], count = 0;
    for (int i = 0; i < analysis->season->count; ++i) {
        if (!analysis->season->matches[i].margin) continue;
        int position = count++;
        while (position && decimal_value(winning_expected(analysis, i), 4) < decimal_value(winning_expected(analysis, order[position - 1]), 4)) { order[position] = order[position - 1]; --position; }
        order[position] = i;
    }
    Lines lines = {0};
    add_line(&lines, "upsets top %lld", analysis->season->settings.upsets);
    for (int i = 0; i < count && i < analysis->season->settings.upsets; ++i) {
        int index = order[i];
        Match match = analysis->season->matches[index];
        bool home = match.margin > 0;
        add_line(&lines, "round %d %s beat %s %d-%d %s expected %s gain %s", match.round, analysis->season->teams[home ? match.home : match.away].code, analysis->season->teams[home ? match.away : match.home].code, home ? match.home_score : match.away_score, home ? match.away_score : match.home_score, home ? "home" : "away", fixed(winning_expected(analysis, index), 4), fixed(fabs(analysis->fit.elo.changes[index]), 2));
    }
    return lines;
}
static Lines tiebreak_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "tiebreaks");
    for (int start = 0; start < analysis->season->n;) {
        int end = start + 1;
        Integer points = analysis->final.records[analysis->final.order[start]].points;
        while (end < analysis->season->n && analysis->final.records[analysis->final.order[end]].points == points) ++end;
        if (end - start > 1) {
            Text line = {0};
            text_add(&line, "points %lld order", points);
            for (int i = start; i < end; ++i) text_add(&line, " %s", analysis->season->teams[analysis->final.order[i]].code);
            text_add(&line, " h2h_points");
            for (int i = start; i < end; ++i) text_add(&line, " %lld", analysis->final.h2h_points[analysis->final.order[i]]);
            text_add(&line, " h2h_diff");
            for (int i = start; i < end; ++i) text_add(&line, " %d", analysis->final.h2h_difference[analysis->final.order[i]]);
            add_line(&lines, "%s", line.data);
        }
        start = end;
    }
    if (lines.count == 1) add_line(&lines, "none");
    return lines;
}
static Lines leader_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "leaders");
    int previous = -1, recorded = 0;
    for (int round = 0; round < analysis->season->rounds; ++round) {
        const Standings *table = &analysis->round_tables[round];
        int leader = table->order[0];
        if (leader != previous) {
            add_line(&lines, "round %d %s points %lld", round + 1, analysis->season->teams[leader].code, table->records[leader].points);
            ++recorded;
        }
        previous = leader;
    }
    add_line(&lines, "lead_changes %d", recorded - 1);
    return lines;
}
static Lines streak_lines(const Analysis *analysis) {
    Lines lines = {0};
    for (int kind = 0; kind < 2; ++kind) {
        const Streak *streaks = kind ? analysis->unbeaten : analysis->wins;
        int longest = 0;
        for (int team = 0; team < analysis->season->n; ++team) if (streaks[team].length > longest) longest = streaks[team].length;
        for (int team = 0; team < analysis->season->n; ++team) if (streaks[team].length == longest) {
            add_line(&lines, "%s %s length %d rounds %d-%d", kind ? "longest_unbeaten_streak" : "longest_win_streak", analysis->season->teams[team].code, longest, streaks[team].first, streaks[team].last);
        }
    }
    return lines;
}
static Lines crosstable_lines(const Analysis *analysis) {
    int top = analysis->season->settings.top_positions;
    Lines lines = {0};
    add_line(&lines, "crosstable top %d", top);
    Text header = {0};
    text_add(&header, "team");
    for (int i = 0; i < top; ++i) text_add(&header, " %s", analysis->season->teams[analysis->final.order[i]].code);
    add_line(&lines, "%s", header.data);
    for (int i = 0; i < top; ++i) {
        int first = analysis->final.order[i];
        Text row = {0};
        text_add(&row, "%s", analysis->season->teams[first].code);
        for (int j = 0; j < top; ++j) text_add(&row, " %s", i == j ? "-" : record_text(analysis, first, 4, analysis->final.order[j]));
        add_line(&lines, "%s", row.data);
    }
    return lines;
}
static Lines trajectory_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "trajectories");
    for (int team = 0; team < analysis->season->n; ++team) {
        int peak = 0, low = 0, best = 0, worst = 0;
        for (int round = 1; round < analysis->season->rounds; ++round) {
            double value = decimal_value(analysis->fit.elo.round_ratings[round][team], 2);
            if (value > decimal_value(analysis->fit.elo.round_ratings[peak][team], 2)) peak = round;
            if (value < decimal_value(analysis->fit.elo.round_ratings[low][team], 2)) low = round;
            int position = analysis->round_tables[round].positions[team];
            if (position < analysis->round_tables[best].positions[team]) best = round;
            if (position > analysis->round_tables[worst].positions[team]) worst = round;
        }
        add_line(&lines, "%s elo_peak %s round %d elo_low %s round %d best_position %d round %d worst_position %d round %d", analysis->season->teams[team].code, fixed(analysis->fit.elo.round_ratings[peak][team], 2), peak + 1, fixed(analysis->fit.elo.round_ratings[low][team], 2), low + 1, analysis->round_tables[best].positions[team], best + 1, analysis->round_tables[worst].positions[team], worst + 1);
    }
    return lines;
}
static Lines correlation_lines(const Analysis *analysis, bool spearman) {
    Lines lines = {0};
    add_line(&lines, "%s", spearman ? "spearman" : "kendall");
    add_line(&lines, "model standings elo colley massey bt od winpct rpi pythag");
    for (int first = 0; first < 9; ++first) {
        Text line = {0};
        text_add(&line, "%s", comparison_names[first]);
        for (int second = 0; second < 9; ++second) {
            Fraction value = spearman ? spearman_rho(analysis->comparison[first], analysis->comparison[second], analysis->season->n) : kendall_tau(analysis->comparison[first], analysis->comparison[second], analysis->season->n);
            text_add(&line, " %s", fraction_text(value));
        }
        add_line(&lines, "%s", line.data);
    }
    return lines;
}
static Lines similarity_lines(const Analysis *analysis) {
    int most_first = 0, most_second = 1, least_first = 0, least_second = 1;
    Fraction most = kendall_tau(analysis->comparison[0], analysis->comparison[1], analysis->season->n), least = most;
    for (int first = 0; first < 9; ++first) for (int second = first + 1; second < 9; ++second) {
        Fraction tau = kendall_tau(analysis->comparison[first], analysis->comparison[second], analysis->season->n);
        if (fraction_compare(tau, most) > 0) { most = tau; most_first = first; most_second = second; }
        if (fraction_compare(tau, least) < 0) { least = tau; least_first = first; least_second = second; }
    }
    Lines lines = {0};
    add_line(&lines, "most_similar %s %s tau %s", comparison_names[most_first], comparison_names[most_second], fraction_with_real(most));
    add_line(&lines, "least_similar %s %s tau %s", comparison_names[least_first], comparison_names[least_second], fraction_with_real(least));
    return lines;
}
static Lines season_lines(const Analysis *analysis) {
    Lines lines = {0};
    paragraph(&lines, summary_lines(analysis));
    paragraph(&lines, upset_lines(analysis));
    paragraph(&lines, tiebreak_lines(analysis));
    paragraph(&lines, leader_lines(analysis));
    paragraph(&lines, streak_lines(analysis));
    paragraph(&lines, crosstable_lines(analysis));
    paragraph(&lines, trajectory_lines(analysis));
    paragraph(&lines, correlation_lines(analysis, false));
    paragraph(&lines, correlation_lines(analysis, true));
    paragraph(&lines, similarity_lines(analysis));
    return lines;
}

static Lines prediction_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "round,home,away,home_score,away_score,result,base,elo,colley,massey,bt,od,winpct,ensemble");
    for (int i = 0; i < analysis->prediction_count; ++i) {
        const Prediction *prediction = &analysis->predictions[i];
        Match match = *prediction->match;
        Text line = {0};
        text_add(&line, "%d,%s,%s,%d,%d,%c", match.round, analysis->season->teams[match.home].code, analysis->season->teams[match.away].code, match.home_score, match.away_score, match.y2 == 2 ? 'H' : match.y2 == 0 ? 'A' : 'D');
        for (int model = 0; model < 8; ++model) text_add(&line, ",%s", fixed(prediction->probabilities[model], 4));
        add_line(&lines, "%s", line.data);
    }
    return lines;
}
static Lines link_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "links");
    for (int i = 0; i < analysis->round_count; ++i) {
        const ValidationRound *round = &analysis->rounds[i];
        Text line = {0};
        text_add(&line, "round %d train %d base %s bt_home %s", round->number, round->training, fixed(round->base, 4), fixed(round->home_factor, 4));
        for (int model = 0; model < 4; ++model) text_add(&line, " %s %s %s", link_names[model], fixed(round->links[model].alpha, 4), fixed(round->links[model].beta, 4));
        add_line(&lines, "%s", line.data);
    }
    return lines;
}
static Lines score_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "scores");
    add_line(&lines, "model log_loss brier skill accuracy");
    for (int model = 0; model < 8; ++model) add_line(&lines, "%s %s %s %s %s", prediction_names[model], fixed(analysis->losses[model], 4), fixed(analysis->briers[model], 4), fixed(analysis->skills[model], 4), fraction_with_real(analysis->accuracies[model]));
    const char *labels[] = {"ranking_log_loss", "ranking_brier", "ranking_accuracy"};
    for (int kind = 0; kind < 3; ++kind) {
        Text line = {0};
        text_add(&line, "%s", labels[kind]);
        for (int i = 0; i < 8; ++i) text_add(&line, " %s", prediction_names[analysis->rankings[kind][i]]);
        add_line(&lines, "%s", line.data);
    }
    return lines;
}
static Lines paired_lines(const Analysis *analysis) {
    int reference = analysis->rankings[0][0], count = analysis->prediction_count;
    Lines lines = {0};
    add_line(&lines, "paired_log_loss reference %s", prediction_names[reference]);
    for (int model = 0; model < 8; ++model) {
        if (model == reference) continue;
        double deltas[600], total = 0;
        for (int i = 0; i < count; ++i) {
            deltas[i] = analysis->predictions[i].losses[model] - analysis->predictions[i].losses[reference];
            total += deltas[i];
        }
        double average = total / count, squares = 0;
        for (int i = 0; i < count; ++i) { double difference = deltas[i] - average; squares += difference * difference; }
        double spread = sqrt(squares / (count - 1)), t = average / (spread / sqrt(count));
        add_line(&lines, "%s mean_diff %s sd %s t %s", prediction_names[model], fixed(average, 4), fixed(spread, 4), fixed(t, 2));
    }
    return lines;
}
static Lines margin_lines(const Analysis *analysis) {
    double absolute = 0, squares = 0, sum = 0;
    for (int i = 0; i < analysis->prediction_count; ++i) {
        double error = analysis->predictions[i].error;
        absolute += fabs(error);
        squares += error * error;
        sum += error;
    }
    int count = analysis->prediction_count;
    Lines lines = {0};
    add_line(&lines, "massey_margin mae %s rmse %s bias %s", fixed(absolute / count, 4), fixed(sqrt(squares / count), 4), fixed(sum / count, 4));
    return lines;
}
static Lines round_loss_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "round_log_loss");
    add_line(&lines, "round base elo colley massey bt od winpct ensemble");
    for (int i = 0; i < analysis->round_count; ++i) {
        const ValidationRound *round = &analysis->rounds[i];
        Text line = {0};
        text_add(&line, "%d", round->number);
        for (int model = 0; model < 8; ++model) {
            double total = 0;
            for (int j = round->start; j < round->start + round->count; ++j) total += analysis->predictions[j].losses[model];
            text_add(&line, " %s", fixed(total / round->count, 4));
        }
        add_line(&lines, "%s", line.data);
    }
    return lines;
}
static Lines calibration_lines(const Analysis *analysis) {
    int bins = analysis->season->settings.calibration_bins;
    Lines lines = {0};
    add_line(&lines, "calibration bins %d", bins);
    for (int model = 0; model < 8; ++model) {
        int counts[10] = {0}, observed[10] = {0};
        double totals[10] = {0};
        for (int i = 0; i < analysis->prediction_count; ++i) {
            const Prediction *prediction = &analysis->predictions[i];
            int bin = (int)floor(bins * prediction->probabilities[model]);
            if (bin >= bins) bin = bins - 1;
            ++counts[bin];
            totals[bin] += prediction->probabilities[model];
            observed[bin] += prediction->match->y2;
        }
        for (int bin = 0; bin < bins; ++bin) {
            if (!counts[bin]) add_line(&lines, "%s bin %d count 0 predicted - observed -", prediction_names[model], bin + 1);
            else add_line(&lines, "%s bin %d count %d predicted %s observed %s", prediction_names[model], bin + 1, counts[bin], fixed(totals[bin] / counts[bin], 4), fraction_text(fraction(observed[bin], 2 * counts[bin])));
        }
    }
    return lines;
}
static Lines grid_lines(const Analysis *analysis) {
    Season *season = analysis->season;
    Settings settings = season->settings;
    Lines lines = {0};
    add_line(&lines, "elo_grid");
    Text header = {0};
    text_add(&header, "k");
    for (int i = 0; i < settings.grid_home_count; ++i) text_add(&header, " h%lld", settings.grid_home[i]);
    add_line(&lines, "%s", header.data);
    double best_loss = 0;
    Integer best_k = 0, best_home = 0;
    bool has_best = false;
    int start = matches_before(season, settings.holdout_round);
    for (int i = 0; i < settings.grid_k_count; ++i) {
        Integer k = settings.grid_k[i];
        Text row = {0};
        text_add(&row, "%lld", k);
        for (int j = 0; j < settings.grid_home_count; ++j) {
            Integer home = settings.grid_home[j];
            EloRun run = run_elo(season->n, season->matches, season->count, k, home, settings.elo_initial);
            double total = 0;
            for (int match = start; match < season->count; ++match) total += log_loss(run.expected[match], season->matches[match].y2);
            double loss = total / analysis->prediction_count;
            text_add(&row, " %s", fixed(loss, 4));
            if (!has_best || decimal_value(loss, 4) < decimal_value(best_loss, 4)) { has_best = true; best_loss = loss; best_k = k; best_home = home; }
        }
        add_line(&lines, "%s", row.data);
    }
    add_line(&lines, "best k %lld home %lld log_loss %s", best_k, best_home, fixed(best_loss, 4));
    return lines;
}
static Fraction projection_tau(const Analysis *analysis) {
    Comparison projected[30], final[30];
    for (int team = 0; team < analysis->season->n; ++team) {
        projected[team] = (Comparison){false, {0,1}, -analysis->projection.ranks[team]};
        final[team] = (Comparison){false, {0,1}, -analysis->final.positions[team]};
    }
    return kendall_tau(projected, final, analysis->season->n);
}
static Lines evaluation_lines(const Analysis *analysis) {
    Lines lines = {0}, holdout = {0}, projection = {0};
    add_line(&holdout, "holdout rounds %d-%d matches %d", analysis->season->settings.holdout_round, analysis->season->rounds, analysis->prediction_count);
    paragraph(&lines, holdout);
    paragraph(&lines, link_lines(analysis));
    paragraph(&lines, score_lines(analysis));
    paragraph(&lines, paired_lines(analysis));
    paragraph(&lines, margin_lines(analysis));
    paragraph(&lines, round_loss_lines(analysis));
    paragraph(&lines, calibration_lines(analysis));
    paragraph(&lines, grid_lines(analysis));
    add_line(&projection, "projection simulations %lld kendall %s", analysis->season->settings.simulations, fraction_with_real(projection_tau(analysis)));
    paragraph(&lines, projection);
    return lines;
}
static Lines projection_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position");
    const Projection *projection = &analysis->projection;
    Integer simulations = analysis->season->settings.simulations;
    for (int rank = 0; rank < analysis->season->n; ++rank) {
        int team = projection->order[rank];
        add_line(&lines, "%d,%s,%lld,%d,%s,%s,%s,%s,%s,%lld,%d", rank + 1, analysis->season->teams[team].code, projection->current.records[team].points, projection->current.positions[team], fixed(projection->opponent_strength[team], 2), fraction_fixed(fraction(projection->total_points[team], simulations), 4), fraction_fixed(fraction(projection->titles[team], simulations), 4), fraction_fixed(fraction(projection->tops[team], simulations), 4), fraction_fixed(fraction(projection->bottoms[team], simulations), 4), analysis->final.records[team].points, analysis->final.positions[team]);
    }
    return lines;
}

int main(void) {
    Analysis *analysis = analyze(load_season());
    write_lines("standings.csv", standings_lines(analysis));
    write_lines("ratings.csv", ratings_lines(analysis));
    write_lines("history.csv", history_lines(analysis));
    write_lines("season.txt", season_lines(analysis));
    write_lines("predictions.csv", prediction_lines(analysis));
    write_lines("evaluation.txt", evaluation_lines(analysis));
    write_lines("projection.csv", projection_lines(analysis));
    return 0;
}
