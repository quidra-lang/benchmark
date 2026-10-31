#pragma once
static const Slot taf_slots[] = {
    {
        WIND, 0
    }, {
        VIS, 0
    }, {
        WX, 1
    }, {
        CLOUD, 1
    }
};

static int observation_time(const char *s) {
    if (strlen(s) != 7 || s[6] != 'Z' || !digits(slice(s, 0, 6), 6)) return -1;
    int d = number_at(s, 0, 2), h = number_at(s, 2, 2), m = number_at(s, 4, 2);
    if (d<1 || d>cfg.days || h>23 || m>59) return -1;
    return ((d-1)*24+h)*60+m;
}

static int period_format(const char *s) {
    return strlen(s) == 9 && s[4] == '/' && digits(slice(s, 0, 4), 4) && digits(s+5, 4);
}

static int parse_period(const char *s, int day, int *start, int *end) {
    if (!period_format(s)) return 0;
    int h1 = number_at(s, 2, 2), h2 = number_at(s, 7, 2);
    if (h1>23 || h2<1 || h2>24) return 0;
    *start = forecast_time(number_at(s, 0, 2), h1, 0, day);
    *end = forecast_time(number_at(s, 5, 2), h2, 0, day);
    return *start >= 0 && *end>*start;
}

static int fm_indicator(const char *s) {
    return strlen(s) == 8 && !strncmp(s, "FM", 2) && digits(s+2, 6);
}

static int change_indicator(const char *s) {
    return fm_indicator(s) || trend_indicator(s) || !strcmp(s, "PROB30") || !strcmp(s, "PROB40");
}

static void decode_taf(Report *r, Group *g, int n) {
    int base = 0;
    while (base<n && !change_indicator(g[base].text)) base++;
    r->state = match_section(g, base, taf_slots, 4, 0, &stations[r->station]);
    int i = base;
    while (i<n) {
        int pos = g[i].position;
        char *kind = g[i++].text;
        Change c = {
            0
        };
        c.kind = kind;
        int valid = 1;
        if (!strncmp(kind, "PROB", 4) && i<n && !strcmp(g[i].text, "TEMPO")) {
            c.kind = format("%s TEMPO", kind);
            i++;
        }
        if (fm_indicator(kind)) {
            c.kind = "FM";
            int h = number_at(kind, 4, 2), m = number_at(kind, 6, 2);
            c.start = forecast_time(number_at(kind, 2, 2), h, m, r->time/1440+1);
            if (h>23 || m>59 || c.start<r->start || c.start >= r->end) {
                error_at(pos, "invalid period", kind);
                valid = 0;
            }
        } else if (i == n || !period_format(g[i].text)) {
            error_at(pos, "missing period", c.kind);
            valid = 0;
        } else {
            if (!parse_period(g[i].text, r->time/1440+1, &c.start, &c.end) || c.start<r->start || c.end>r->end) {
                error_at(g[i].position, "invalid period", g[i].text);
                valid = 0;
            }
            i++;
        }
        int end = i;
        while (end<n && !change_indicator(g[end].text)) end++;
        if (valid) {
            c.state = match_section(g+i, end-i, taf_slots, 4, 1, &stations[r->station]);
            add_change(r, c);
        }
        i = end;
    }
}

static State overlay(State a, State b) {
    if (b.wind) a.wind = b.wind;
    if (b.visibility) a.visibility = b.visibility;
    if (b.nw >= 0) {
        a.weather = b.weather;
        a.nw = b.nw;
    }
    if (b.nc >= 0) {
        a.cloud = b.cloud;
        a.nc = b.nc;
    }
    return a;
}

static State prevailing(Report *r, int h) {
    State s = r->state;
    for (int i = 0; i<r->nch; i++) {
        Change c = r->changes[i];
        if (!strcmp(c.kind, "FM") && c.start <= h) s = c.state;
        else if (!strcmp(c.kind, "BECMG") && c.end <= h) s = overlay(s, c.state);
    }
    return s;
}

static int temporary(Change *c, int h) {
    return strcmp(c->kind, "FM") && strcmp(c->kind, "BECMG") && c->start <= h && h<c->end;
}
