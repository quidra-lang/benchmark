#include "ratings.h"

static int team_index(const Season *season, const char *code) {
    for (int i = 0; i < season->n; ++i) if (!strcmp(season->teams[i].code, code)) return i;
    return -1;
}
static Integer *integers(Lines fields) {
    Integer *values = allocate((size_t)(fields.count - 1) * sizeof(*values));
    for (int i = 1; i < fields.count; ++i) values[i - 1] = strtoll(fields.items[i], NULL, 10);
    return values;
}
Season *load_season(void) {
    Season *season = allocate(sizeof(*season));
    Lines teams = read_lines("teams.csv");
    for (int i = 1; i < teams.count; ++i) {
        Lines fields = split_text(teams.items[i], ',');
        season->teams[season->n++] = (Team){fields.items[0], fields.items[1]};
    }
    Lines matches = read_lines("matches.csv");
    for (int i = 1; i < matches.count; ++i) {
        Lines fields = split_text(matches.items[i], ',');
        Match match = {atoi(fields.items[0]), team_index(season, fields.items[1]), team_index(season, fields.items[2]), atoi(fields.items[3]), atoi(fields.items[4]), 0, 0};
        match.margin = match.home_score - match.away_score;
        match.y2 = match.margin > 0 ? 2 : match.margin == 0 ? 1 : 0;
        int position = season->count++;
        while (position && season->matches[position - 1].round > match.round) {
            season->matches[position] = season->matches[position - 1];
            --position;
        }
        season->matches[position] = match;
    }
    season->rounds = season->matches[season->count - 1].round;
    Lines parameters = read_lines("params.txt");
    Settings *settings = &season->settings;
    for (int i = 0; i < parameters.count; ++i) {
        Lines fields = split_text(parameters.items[i], ' ');
        Integer value = strtoll(fields.items[1], NULL, 10);
        switch (i) {
            case 0: settings->win_points = value; break;
            case 1: settings->draw_points = value; break;
            case 2: settings->form_length = (int)value; break;
            case 3: settings->close_margin = value; break;
            case 4: settings->exponent = strtod(fields.items[1], NULL); break;
            case 5: settings->elo_k = value; break;
            case 6: settings->elo_home = value; break;
            case 7: settings->elo_initial = value; break;
            case 8: settings->grid_k = integers(fields); settings->grid_k_count = fields.count - 1; break;
            case 9: settings->grid_home = integers(fields); settings->grid_home_count = fields.count - 1; break;
            case 10: settings->bt_iterations = value; break;
            case 11: settings->od_iterations = value; break;
            case 12: settings->link_iterations = value; break;
            case 13: settings->holdout_round = (int)value; break;
            case 14: settings->upsets = value; break;
            case 15: settings->calibration_bins = (int)value; break;
            case 16: settings->simulations = value; break;
            case 17: settings->seed = value; break;
            case 18: settings->top_positions = (int)value; break;
            case 19: settings->bottom_positions = (int)value; break;
        }
    }
    return season;
}
int matches_before(const Season *season, int round) {
    int count = 0;
    while (count < season->count && season->matches[count].round < round) ++count;
    return count;
}
double match_result(const Match *match) { return match->y2 / 2.0; }
