#pragma once
typedef struct {
    I table[4][4], temporary_hits;
} Contingency;

static int covers(Report *r, int t) {
    int h = t-t%60;
    return !strcmp(r->kind, "TAF") && r->time <= t && r->start <= h && h<r->end;
}

static Report *choose_forecast(Report **a, int n, int station, int t) {
    Report *best = NULL;
    for (int i = 0; i<n; i++) if (a[i]->station == station && covers(a[i], t) && (!best || a[i]->time >= best->time)) best = a[i];
    return best;
}

static void contingency_add(Contingency *c, int f, int o, int hit) {
    c->table[f][o]++;
    c->temporary_hits += hit;
}

static I row_total(Contingency *c, int r) {
    I n = 0;
    for (int j = 0; j<4; j++) n += c->table[r][j];
    return n;
}

static I column_total(Contingency *c, int j) {
    I n = 0;
    for (int i = 0; i<4; i++) n += c->table[i][j];
    return n;
}

static I contingency_total(Contingency *c) {
    I n = 0;
    for (int i = 0; i<4; i++) n += row_total(c, i);
    return n;
}

static I contingency_hits(Contingency *c) {
    I n = 0;
    for (int i = 0; i<4; i++) n += c->table[i][i];
    return n;
}

static void skill_score(Contingency *c, I *p, I *q) {
    I n = contingency_total(c), e = 0;
    for (int i = 0; i<4; i++) e += row_total(c, i)*column_total(c, i);
    *p = n*contingency_hits(c)-e;
    *q = n*n-e;
}

static void detection(Contingency *c, int i, I *p, I *q) {
    *p = c->table[i][i];
    *q = column_total(c, i);
}

static void false_alarm(Contingency *c, int i, I *p, I *q) {
    *q = row_total(c, i);
    *p = *q-c->table[i][i];
}

static int wind_strength(Value *v) {
    return v->gust<0?v->speed:v->gust;
}
