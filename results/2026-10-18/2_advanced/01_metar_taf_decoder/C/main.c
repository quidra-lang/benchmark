#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <ctype.h>
#include <sys/stat.h>
typedef int64_t I;
typedef struct {
    char *name;
    int heading;
} Runway;
typedef struct {
    char *code, *name;
    I elevation;
    int nr;
    Runway *runways;
} Station;
typedef struct {
    int year, month, days, next_year, next_month, next_days;
    I cross, tail;
    char **verify;
    int nv;
} Settings;
typedef struct {
    int position;
    char *text;
} Group;
typedef struct Value {
    char *raw;
    int direction, speed, gust, meters_per_second; /* -1 direction is VRB; -1 gust is absent. */
    int variation_from, variation_to;
    int visibility_kind, meters, whole, numerator, denominator, mile_form; /* meters, CAVOK, miles: 0, 1, 2 */
    char qualifier, first_qualifier, second_qualifier, runway[8];
    int first_reading, second_reading, feet, trend;
    int intensity, descriptor, nsw, phenomena[100], nphenomena;
    int amount, height, cloud_type;
    int temperature, dew_point;
    int pressure_unit, pressure_value, inch, hectopascals;
} Value;
typedef struct {
    Value *modifier, *wind, *variation, *visibility, *temperature, *pressure, *no_trend;
    Value **weather, **cloud, **rvr;
    int nw, nc, nr; /* -1 weather/cloud count means none; 0 means explicitly empty. */
} State;
typedef struct {
    int kind, repeat;
} Slot;
typedef struct {
    int report, position;
    char *reason, *text;
} Error;
typedef struct {
    char *kind;
    int start, end;
    State state;
    char **times;
    int nt;
} Change;
typedef struct Report {
    int number, station, time, start, end;
    char *kind, *modifier;
    State state;
    Change *changes;
    int nch;
    int *slp, nslp, (*precise)[2], np;
    char *speci;
} Report;
typedef struct {
    char *data;
    size_t len, cap;
} Text;
enum {
    MOD, WIND, VAR, VIS, RVR, WX, CLOUD, TEMP, PRESS, NOSIG
};
static Settings cfg;
static Station *stations;
static int ns;
static Report **reports;
static int nreports;
static Error *errors;
static int ne;
static int current_report;

static void *allocate(size_t n) {
    void *p = calloc(1, n ? n : 1);
    if (!p) exit(1);
    return p;
}

static char *copy(const char *s) {
    size_t n = strlen(s)+1;
    char *p = allocate(n);
    memcpy(p, s, n);
    return p;
}

static char *slice(const char *s, int a, int n) {
    char *p = allocate((size_t)n+1);
    memcpy(p, s+a, (size_t)n);
    return p;
}

static void append(Text *t, const char *s) {
    size_t n = strlen(s);
    if (t->len+n+1>t->cap) {
        t->cap = (t->len+n+1)*2;
        t->data = realloc(t->data, t->cap);
        if (!t->data) exit(1);
    }
    memcpy(t->data+t->len, s, n+1);
    t->len += n;
}

static char *format(const char *fmt, ...) {
    va_list a, b;
    va_start(a, fmt);
    va_copy(b, a);
    int n = vsnprintf(NULL, 0, fmt, a);
    va_end(a);
    char *s = allocate((size_t)n+1);
    vsnprintf(s, (size_t)n+1, fmt, b);
    va_end(b);
    return s;
}

static void line(Text *t, const char *fmt, ...) {
    va_list a, b;
    va_start(a, fmt);
    va_copy(b, a);
    int n = vsnprintf(NULL, 0, fmt, a);
    va_end(a);
    char *s = allocate((size_t)n+1);
    vsnprintf(s, (size_t)n+1, fmt, b);
    va_end(b);
    append(t, s);
    append(t, "\n");
    free(s);
}

static void push_value(Value ***a, int *n, Value *v) {
    *a = realloc(*a, (size_t)(*n+1)*sizeof(**a));
    (*a)[(*n)++] = v;
}

static void error_at(int position, const char *reason, const char *text) {
    errors = realloc(errors, (size_t)(ne+1)*sizeof(*errors));
    errors[ne++] = (Error) {
        current_report, position, copy(reason), text?copy(text):NULL
    };
}
static State match_section(Group *, int, const Slot *, int, int, Station *);
/* These headers share the report types in this translation unit. */
#include "units.h"
#include "groups.h"
#include "metar.h"
#include "taf.h"
#include "verification.h"

static State match_section(Group *g, int n, const Slot *slots, int count, int context, Station *station) {
    State s = {
        0
    };
    s.nw = s.nc = -1;
    int cursor = 0;
    for (int i = 0; i<n; i++) {
        Value *v = NULL;
        int j = cursor;
        for (; j<count; j++) {
            v = group_format(slots[j].kind, g[i].text);
            if (v) break;
        }
        if (j == count) {
            int earlier = 0;
            for (int k = 0; k<cursor; k++) {
                Value *p = group_format(slots[k].kind, g[i].text);
                if (p) {
                    earlier = 1;
                    free(p);
                    break;
                }
            }
            error_at(g[i].position, earlier?"out of order group":"unknown group", g[i].text);
            continue;
        }
        int kind = slots[j].kind;
        if (!group_valid(kind, v, &s, station, context)) {
            error_at(g[i].position, "invalid group", g[i].text);
            free(v);
            continue;
        }
        group_accept(&s, kind, v);
        cursor = j+!slots[j].repeat;
        if (kind == VIS && v->visibility_kind == 1) {
            for (int k = 0; k<count; k++) if (slots[k].kind == CLOUD) cursor = k+1;
        }
    }
    return s;
}

static int ceiling(State s) {
    for (int i = 0; i<s.nc; i++) if (s.cloud[i]->amount >= 2 && s.cloud[i]->amount <= 4) return s.cloud[i]->height;
    return -1;
}

static int category(State s) {
    I p = 0, q = 1;
    int c = ceiling(s);
    if (s.visibility) mile_fraction(s.visibility, &p, &q);
    else p = 1000000;
    if ((c >= 0 && c<500) || p<q) return 3;
    if ((c >= 0 && c<1000) || p<3*q) return 2;
    if ((c >= 0 && c <= 3000) || p <= 5*q) return 1;
    return 0;
}
static const char *categories[] = {
    "VFR", "MVFR", "IFR", "LIFR"
};

static char *wind_phrase(Value *v) {
    if (!v) return "not reported";
    if (v->direction == 0) return "calm";
    char *s = v->direction<0?format("variable at %d KT", v->speed):format("%03d degrees at %d KT", v->direction,
    v->speed);
    return v->gust<0?s:format("%s gusting %d KT", s, v->gust);
}

static char *wind_code(Value *v) {
    if (v->direction == 0) return "00000KT";
    char *d = v->direction<0?"VRB":format("%03d", v->direction);
    return v->gust<0?format("%s%02dKT", d, v->speed):format("%s%02dG%02dKT", d, v->speed, v->gust);
}

static char *mile_number(Value *v) {
    if (!v->denominator) return format("%d", v->whole);
    return v->whole?format("%d %d/%d", v->whole, v->numerator, v->denominator):format("%d/%d", v->numerator, v->denominator);
}

static char *visibility_phrase(Value *v) {
    if (!v) return "not reported";
    if (v->visibility_kind == 1) return "10 km or more (CAVOK)";
    if (v->visibility_kind == 0) return v->qualifier == 'P'?"10 km or more":format("%d m", v->meters);
    return format("%s%s SM", v->qualifier == 'M'?"less than ":v->qualifier == 'P'?"more than ":"", mile_number(v));
}

static char *visibility_code(Value *v) {
    if (v->visibility_kind == 1) return "CAVOK";
    if (v->visibility_kind == 0) return v->raw;
    return format("%s%sSM", v->qualifier?format("%c", v->qualifier):"", mile_number(v));
}

static char *weather_phrase(Value *v) {
    if (v->nsw) return "no significant weather";
    Text s = {
        0
    };
    if (v->intensity) append(&s, v->intensity == '-'?"light":v->intensity == '+'?"heavy":"nearby");
    if (v->descriptor >= 0) {
        if (s.len) append(&s, " ");
        append(&s, descriptor_words[v->descriptor]);
    }
    for (int i = 0; i<v->nphenomena; i++) {
        if (s.len) append(&s, i?" and ":" ");
        append(&s, phenomenon_words[v->phenomena[i]-8]);
    }
    return s.data?s.data:"";
}

static char *cloud_phrase(Value *v) {
    if (v->amount >= 5) return (char *)clear_words[v->amount-5];
    if (v->amount == 4) return format("vertical visibility %d ft", v->height);
    return format("%s at %d ft%s", amount_words[v->amount], v->height, v->cloud_type == 1?" cumulonimbus":v->cloud_type == 2?" towering cumulus":"");
}

static char *summary(State s) {
    Text t = {
        0
    };
    if (s.wind) append(&t, format("wind %s", wind_phrase(s.wind)));
    if (s.visibility) {
        if (t.len) append(&t, "; ");
        append(&t, format("visibility %s", visibility_phrase(s.visibility)));
    }
    if (s.nw>0) {
        if (t.len) append(&t, "; ");
        append(&t, "weather ");
        for (int i = 0; i<s.nw; i++) {
            if (i) append(&t, ", ");
            append(&t, weather_phrase(s.weather[i]));
        }
    }
    if (s.nc>0) {
        if (t.len) append(&t, "; ");
        append(&t, "cloud ");
        for (int i = 0; i<s.nc; i++) {
            if (i) append(&t, ", ");
            append(&t, cloud_phrase(s.cloud[i]));
        }
    }
    return t.data?t.data:"no conditions";
}

static void token(Text *t, const char *s) {
    if (t->len) append(t, " ");
    append(t, s);
}

static char *tokens(State s) {
    Text t = {
        0
    };
    if (s.wind) token(&t, wind_code(s.wind));
    if (s.visibility) token(&t, visibility_code(s.visibility));
    for (int i = 0; i<s.nw; i++) if (!s.weather[i]->nsw) token(&t, s.weather[i]->raw);
    for (int i = 0; i<s.nc; i++) token(&t, s.cloud[i]->raw);
    token(&t, categories[category(s)]);
    return t.data;
}

static int wind_change(Value *a, Value *b, int angle) {
    if (!a || !b) return 0;
    int flags = 0;
    if (a->direction>0 && b->direction>0 && (a->speed >= 10 || b->speed >= 10)) {
        int d = abs(a->direction-b->direction)%360;
        if (d>180) d = 360-d;
        if (d >= angle) flags |= 1;
    }
    if (abs(a->speed-b->speed) >= 10) flags |= 2;
    return flags;
}

static int weather_has(State s, int descriptor, int freezing) {
    for (int i = 0; i<s.nw; i++) if (s.weather[i]->descriptor == descriptor) {
        if (!freezing) return 1;
        for (int j = 0; j<s.weather[i]->nphenomena; j++) if (s.weather[i]->phenomena[j] == 8 || s.weather[i]->phenomena[j] == 9) return 1;
    }
    return 0;
}

static void reason(Text *t, const char *s) {
    if (t->len) append(t, ", ");
    append(t, s);
}

static char *speci_check(Report *previous, Report *r) {
    if (!previous) return "no previous report";
    State a = previous->state, b = r->state;
    Text t = {
        0
    };
    if (category(a) != category(b)) reason(&t, format("category %s to %s", categories[category(a)], categories[category(b)]));
    int w = wind_change(a.wind, b.wind, 45);
    if (w&1) reason(&t, "wind shift");
    if (w&2) reason(&t, "wind speed");
    if (weather_has(a, 6, 0) != weather_has(b, 6, 0)) reason(&t, weather_has(b, 6, 0)?"thunderstorm began":"thunderstorm ended");
    if (weather_has(a, 7, 1) != weather_has(b, 7, 1)) reason(&t, weather_has(b, 7, 1)?"freezing precipitation began":"freezing precipitation ended");
    return t.data?t.data:"no criteria met";
}

static char *tenth(int n) {
    return format("%s%d.%d", n<0?"-":"", abs(n)/10, abs(n)%10);
}

static char *component(int head, int cross) {
    return cross?format("%s %d KT, crosswind %d KT from %s", head<0?"tailwind":"headwind", abs(head), abs(cross),
    cross>0?"right":"left"):format("%s %d KT, crosswind 0 KT", head<0?"tailwind":"headwind", abs(head));
}

static char *reading(char q, int n) {
    return format("%s%d", q == 'M'?"less than ":q == 'P'?"more than ":"", n);
}

static void observation_lines(Text *t, Report *r) {
    State s = r->state;
    Station *st = &stations[r->station];
    line(t, "  time: %s", stamp(r->time));
    if (s.modifier) line(t, "  modifier: %s", strcmp(s.modifier->raw, "AUTO") == 0?"automated":"corrected");
    char *w = wind_phrase(s.wind);
    if (s.variation) w = format("%s, varying between %03d and %03d degrees", w, s.variation->variation_from, s.variation->variation_to);
    line(t, "  wind: %s", w);
    line(t, "  visibility: %s", visibility_phrase(s.visibility));
    for (int i = 0; i<s.nr; i++) {
        Value *v = s.rvr[i];
        char *range = v->second_reading<0?reading(v->first_qualifier, v->first_reading):format("between %s and %s",
        reading(v->first_qualifier, v->first_reading), reading(v->second_qualifier, v->second_reading));
        line(t, "  runway visual range: runway %s %s %s%s", v->runway, range, v->feet?"ft":"m", v->trend == 'U'?", rising":v->trend == 'D'?", falling":v->trend == 'N'?", no change":"");
    }
    for (int i = 0; i<s.nw; i++) line(t, "  weather: %s", weather_phrase(s.weather[i]));
    if (s.visibility && s.visibility->visibility_kind == 1) line(t, "  cloud: no significant cloud");
    else if (s.nc<0) line(t, "  cloud: not reported");
    else for (int i = 0; i<s.nc; i++) line(t, "  cloud: %s", cloud_phrase(s.cloud[i]));
    if (s.temperature) line(t, "  temperature: %d C, dew point %d C, spread %d C", s.temperature->temperature,
    s.temperature->dew_point, s.temperature->temperature-s.temperature->dew_point);
    else line(t, "  temperature: not reported");
    if (s.pressure) {
        Value *v = s.pressure;
        char *inch = format("%d.%02d inHg", v->inch/100, v->inch%100), *hpa = format("%d hPa", v->hectopascals);
        line(t, "  altimeter: %s (%s)", v->pressure_unit == 'A'?inch:hpa, v->pressure_unit == 'A'?hpa:inch);
    } else line(t, "  altimeter: not reported");
    if (s.no_trend) line(t, "  trend: no significant change");
    for (int i = 0; i<r->nch; i++) {
        Change *c = &r->changes[i];
        Text p = {
            0
        };
        append(&p, strcmp(c->kind, "BECMG") == 0?"becoming":"temporarily");
        for (int j = 0; j<c->nt; j++) {
            char *a = c->times[j];
            append(&p, format(" %s %.2s:%.2sZ", a[0] == 'A'?"at":a[0] == 'F'?"from":"until", a+2, a+4));
        }
        line(t, "  trend: %s: %s", p.data, summary(c->state));
    }
    for (int i = 0; i<r->nslp; i++) line(t, "  sea level pressure: %s hPa", tenth(r->slp[i]));
    for (int i = 0; i<r->np; i++) line(t, "  precise temperature: %s C, dew point %s C", tenth(r->precise[i][0]),
    tenth(r->precise[i][1]));
    int c = ceiling(s);
    line(t, "  ceiling: %s", c<0?"none":format("%d ft", c));
    line(t, "  flight category: %s", categories[category(s)]);
    I pa = 0;
    if (s.pressure) pa = st->elevation+(2992-s.pressure->inch)*10;
    line(t, "  pressure altitude: %s", s.pressure?format("%lld ft", (long long)pa):"not available");
    line(t, "  density altitude: %s", s.pressure && s.temperature?format("%lld ft", (long long)(pa+floor_div(120*(1000*(I)s.temperature->temperature-15000+2*pa),
    1000))):"not available");
    if (!s.wind || s.wind->direction <= 0) line(t, "  runway wind: not computed");
    else {
        Text usable = {
            0
        };
        int best = -1, besthead = 0;
        Value *v = s.wind;
        for (int i = 0; i<st->nr; i++) {
            Runway rw = st->runways[i];
            int angle = v->direction-rw.heading, head = (int)floor_div(v->speed*icos(angle), 1000), cross = (int)floor_div(v->speed*isin(angle),
            1000);
            int gh = head, gc = cross;
            if (v->gust >= 0) {
                gh = (int)floor_div(v->gust*icos(angle), 1000);
                gc = (int)floor_div(v->gust*isin(angle), 1000);
            }
            line(t, "  runway %s: %s%s", rw.name, component(head, cross), v->gust >= 0?format("; gusts %s", component(gh,
            gc)):"");
            if (abs(gc) <= cfg.cross && -gh <= cfg.tail) {
                token(&usable, rw.name);
                if (best<0 || head>besthead) {
                    best = i;
                    besthead = head;
                }
            }
        }
        line(t, "  usable runways: %s", usable.len?usable.data:"none");
        line(t, "  preferred runway: %s", best<0?"none":st->runways[best].name);
    }
    if (strcmp(r->kind, "SPECI") == 0) line(t, "  speci check: %s", r->speci);
}

static void forecast_lines(Text *t, Report *r) {
    line(t, "  issued: %s", stamp(r->time));
    if (r->modifier) line(t, "  modifier: %s", strcmp(r->modifier, "AMD") == 0?"amended":"corrected");
    line(t, "  valid: %s to %s", stamp(r->start), stamp(r->end));
    line(t, "  base: %s", summary(r->state));
    for (int i = 0; i<r->nch; i++) {
        Change c = r->changes[i];
        line(t, "  %s %s: %s", c.kind, strcmp(c.kind, "FM") == 0?stamp(c.start):format("%s to %s", stamp(c.start),
        stamp(c.end)), summary(c.state));
    }
}

static void timeline(Text *t, Report *r) {
    Station st = stations[r->station];
    line(t, "TAF %s issued %s valid %s to %s", st.code, stamp(r->time), stamp(r->start), stamp(r->end));
    int counts[4] = {
        0
    };
    for (int h = r->start; h<r->end; h += 60) {
        State s = prevailing(r, h);
        counts[category(s)]++;
        Text row = {
            0
        };
        append(&row, format("%s %s", stamp(h), tokens(s)));
        for (int i = 0; i<r->nch; i++) if (temporary(&r->changes[i], h)) append(&row, format(" | %s %s", r->changes[i].kind,
        tokens(overlay(s, r->changes[i].state))));
        line(t, "%s", row.data);
    }
    line(t, "summary: VFR %d, MVFR %d, IFR %d, LIFR %d", counts[0], counts[1], counts[2], counts[3]);
}

static int visibility_less(Value *a, Value *b) {
    I p, q, r, s;
    mile_fraction(a, &p, &q);
    mile_fraction(b, &r, &s);
    return p*s<r*q;
}

static void verification_block(Text *t, int station) {
    Station st = stations[station];
    int counts[4] = {
        0
    }, nm = 0, nsp = 0;
    Report *ext[5] = {
        0
    };
    const char *labels[] = {
        "lowest temperature", "highest temperature", "strongest wind", "lowest ceiling", "lowest visibility"
    };
    Contingency ct = {
        0
    };
    I buckets[5][2] = {
        {
            0
        }
    };
    int missing = 0;
    Text amendments = {
        0
    };
    for (int i = 0; i<nreports; i++) {
        Report *r = reports[i];
        if (r->station != station || strcmp(r->kind, "TAF") == 0) continue;
        State s = r->state;
        int cat = category(s);
        counts[cat]++;
        if (strcmp(r->kind, "METAR") == 0) nm++;
        else nsp++;
        if (s.temperature) {
            if (!ext[0] || s.temperature->temperature<ext[0]->state.temperature->temperature) ext[0] = r;
            if (!ext[1] || s.temperature->temperature>ext[1]->state.temperature->temperature) ext[1] = r;
        }
        if (s.wind && (!ext[2] || wind_strength(s.wind)>wind_strength(ext[2]->state.wind))) ext[2] = r;
        if (ceiling(s) >= 0 && (!ext[3] || ceiling(s)<ceiling(ext[3]->state))) ext[3] = r;
        if (s.visibility && (!ext[4] || visibility_less(s.visibility, ext[4]->state.visibility))) ext[4] = r;
        Report *f = choose_forecast(reports, nreports, station, r->time);
        int h = r->time-r->time%60;
        for (int j = 0; j<nreports; j++) if (reports[j]->station == station && covers(reports[j], r->time)) {
            Report *a = reports[j];
            int b = (h-a->start)/360;
            buckets[b][1]++;
            if (category(prevailing(a, h)) == cat) buckets[b][0]++;
        }
        if (!f) {
            missing++;
            continue;
        }
        State p = prevailing(f, h);
        int fc = category(p), hit = fc == cat;
        for (int j = 0; j<f->nch; j++) if (temporary(&f->changes[j], h) && category(overlay(p, f->changes[j].state)) == cat) hit = 1;
        contingency_add(&ct, fc, cat, hit);
        Text why = {
            0
        };
        if (!hit) append(&why, format("category %s, forecast %s", categories[cat], categories[fc]));
        if (wind_change(p.wind, s.wind, 60)) {
            if (why.len) append(&why, "; ");
            append(&why, format("wind %s, forecast %s", wind_code(s.wind), wind_code(p.wind)));
        }
        if (why.len) line(&amendments, "amendment %s: %s", stamp(r->time), why.data);
    }
    line(t, "station %s (%s)", st.code, st.name);
    line(t, "reports: METAR %d, SPECI %d", nm, nsp);
    line(t, "observed categories: VFR %d, MVFR %d, IFR %d, LIFR %d", counts[0], counts[1], counts[2], counts[3]);
    for (int k = 0; k<5; k++) {
        if (!ext[k]) {
            line(t, "%s: not available", labels[k]);
            continue;
        }
        State s = ext[k]->state;
        char *value = k<2?format("%d C", s.temperature->temperature):k == 2?wind_phrase(s.wind):k == 3?format("%d ft",
        ceiling(s)):visibility_phrase(s.visibility);
        line(t, "%s: %s at %s", labels[k], value, stamp(ext[k]->time));
    }
    I n = contingency_total(&ct), hits = contingency_hits(&ct);
    line(t, "verified: %lld", (long long)n);
    line(t, "no forecast: %d", missing);
    line(t, "%-8s%6s%6s%6s%6s%6s", "forecast", "VFR", "MVFR", "IFR", "LIFR", "total");
    for (int i = 0; i<4; i++) line(t, "%-8s%6lld%6lld%6lld%6lld%6lld", categories[i], (long long)ct.table[i][0],
    (long long)ct.table[i][1], (long long)ct.table[i][2], (long long)ct.table[i][3], (long long)row_total(&ct,
    i));
    line(t, "%-8s%6lld%6lld%6lld%6lld%6lld", "total", (long long)column_total(&ct, 0), (long long)column_total(&ct,
    1), (long long)column_total(&ct, 2), (long long)column_total(&ct, 3), (long long)n);
    I a, b;
    skill_score(&ct, &a, &b);
    line(t, "hit rate: %s", fraction(hits, n));
    line(t, "hit rate with temporary groups: %s", fraction(ct.temporary_hits, n));
    line(t, "heidke skill score: %s", fraction(a, b));
    for (int i = 0; i<4; i++) {
        detection(&ct, i, &a, &b);
        char *pod = fraction(a, b);
        false_alarm(&ct, i, &a, &b);
        line(t, "%s: pod %s, far %s", categories[i], pod, fraction(a, b));
    }
    for (int i = 0; i<5; i++) line(t, "hours %d-%d: %s", i*6, i*6+5, fraction(buckets[i][0], buckets[i][1]));
    if (amendments.data) append(t, amendments.data);
}

static char **words(char *s, int *n) {
    char **a = NULL;
    *n = 0;
    char *p = strtok(s, " \n\r");
    while (p) {
        a = realloc(a, (size_t)(*n+1)*sizeof(*a));
        a[(*n)++] = copy(p);
        p = strtok(NULL, " \n\r");
    }
    return a;
}

static int station_index(const char *code) {
    for (int i = 0; i<ns; i++) if (strcmp(stations[i].code, code) == 0) return i;
    return -1;
}

static Group *join_groups(char **w, int n, int cursor, int *ng) {
    Group *g = NULL;
    *ng = 0;
    for (int i = cursor; i<n; i++) {
        char *s = w[i];
        int pos = i+1;
        if (strlen(s) == 1 && isdigit((unsigned char)s[0]) && i+1<n && fraction_word(w[i+1])) {
            i++;
            s = format("%s %s", s, w[i]);
        }
        g = realloc(g, (size_t)(*ng+1)*sizeof(*g));
        g[(*ng)++] = (Group) {
            pos, s
        };
    }
    return g;
}

static void process(char **w, int n, int number, Report **previous) {
    current_report = number;
    Report *r = allocate(sizeof(*r));
    r->number = number;
    r->kind = w[0];
    int cursor = 1;
    if (strcmp(w[0], "METAR") && strcmp(w[0], "SPECI") && strcmp(w[0], "TAF")) {
        error_at(1, "rejected report, invalid type", w[0]);
        goto done;
    }
    int forecast = strcmp(w[0], "TAF") == 0;
    if (forecast && cursor<n && (!strcmp(w[cursor], "AMD") || !strcmp(w[cursor], "COR"))) r->modifier = w[cursor++];
    for (int item = 0; item<(forecast?3:2); item++, cursor++) {
        const char *name = item == 0?"station":item == 1?"time":"validity";
        if (cursor == n) {
            error_at(n+1, format("rejected report, missing %s", name), NULL);
            goto done;
        }
        int valid = 0;
        if (item == 0) valid = (r->station = station_index(w[cursor])) >= 0;
        else if (item == 1) valid = (r->time = observation_time(w[cursor])) >= 0;
        else valid = parse_period(w[cursor], r->time/1440+1, &r->start, &r->end) && r->end <= r->start+1800;
        if (!valid) {
            error_at(cursor+1, format("rejected report, invalid %s", name), w[cursor]);
            goto done;
        }
    }
    int ng;
    Group *g = join_groups(w, n, cursor, &ng);
    if (forecast) decode_taf(r, g, ng);
    else {
        decode_metar(r, g, ng);
        if (!strcmp(r->kind, "SPECI")) r->speci = speci_check(previous[r->station], r);
        previous[r->station] = r;
    }
    reports = realloc(reports, (size_t)(nreports+1)*sizeof(*reports));
    reports[nreports++] = r;
    done: return;
}

static void read_inputs(void) {
    char buf[1000];
    FILE *f = fopen("input/stations.txt", "r");
    if (!f) exit(1);
    while (fgets(buf, sizeof(buf), f)) {
        char *fields[4] = {buf};
        for (int i = 0; i<3; i++) {
            char *separator = strchr(fields[i], ' ');
            *separator = '\0';
            fields[i+1] = separator+1;
        }
        fields[3][strcspn(fields[3], "\n")] = '\0';
        Station st = {
            0
        };
        st.code = copy(fields[0]);
        st.elevation = strtoll(fields[1], NULL, 10);
        st.name = copy(fields[3]);
        char *rw = strtok(fields[2], ",");
        while (rw) {
            char *slash = strchr(rw, '/');
            *slash = 0;
            st.runways = realloc(st.runways, (size_t)(st.nr+1)*sizeof(*st.runways));
            st.runways[st.nr++] = (Runway) {
                copy(rw), atoi(slash+1)
            };
            rw = strtok(NULL, ",");
        }
        stations = realloc(stations, (size_t)(ns+1)*sizeof(*stations));
        stations[ns++] = st;
    }
    fclose(f);
    f = fopen("input/params.txt", "r");
    if (!f) exit(1);
    int row = 0;
    while (fgets(buf, sizeof(buf), f)) {
        int n;
        char **w = words(buf, &n);
        I value = strtoll(w[1], NULL, 10);
        if (row == 0) cfg.year = (int)value;
        if (row == 1) cfg.month = (int)value;
        if (row == 2) cfg.cross = value;
        if (row == 3) cfg.tail = value;
        if (row == 4) {
            cfg.nv = n-1;
            cfg.verify = allocate((size_t)cfg.nv*sizeof(*cfg.verify));
            for (int i = 1; i<n; i++) cfg.verify[i-1] = w[i];
        }
        row++;
    }
    fclose(f);
    calendar_init();
    f = fopen("input/reports.txt", "r");
    if (!f) exit(1);
    char **raw = NULL;
    int nr = 0, number = 0;
    Report **previous = allocate((size_t)ns*sizeof(*previous));
    while (fgets(buf, sizeof(buf), f)) {
        int continuation = buf[0] == ' ';
        if (!continuation && nr) {
            process(raw, nr, ++number, previous);
            raw = NULL;
            nr = 0;
        }
        int n;
        char **w = words(buf, &n);
        raw = realloc(raw, (size_t)(nr+n)*sizeof(*raw));
        for (int i = 0; i<n; i++) raw[nr++] = w[i];
    }
    if (nr) process(raw, nr, ++number, previous);
    fclose(f);
}

static void save(const char *name, Text t) {
    char *p = format("output/%s", name);
    FILE *f = fopen(p, "w");
    if (!f) exit(1);
    if (t.data) fwrite(t.data, 1, t.len, f);
    fclose(f);
}

static int compare_errors(const void *a, const void *b) {
    const Error *x = a, *y = b;
    return x->report != y->report?x->report-y->report:x->position-y->position;
}
int main(void) {
    read_inputs();
    Text decoded = {
        0
    }, csv = {
        0
    }, tl = {
        0
    }, verify = {
        0
    }, err = {
        0
    };
    line(&csv, "station,time,ceiling,visibility,category");
    int nt = 0;
    for (int i = 0; i<nreports; i++) {
        Report *r = reports[i];
        Station st = stations[r->station];
        if (i) append(&decoded, "\n");
        line(&decoded, "REPORT %d: %s %s (%s)", r->number, r->kind, st.code, st.name);
        if (!strcmp(r->kind, "TAF")) {
            forecast_lines(&decoded, r);
            if (nt++) append(&tl, "\n");
            timeline(&tl, r);
        } else {
            observation_lines(&decoded, r);
            int c = ceiling(r->state);
            Value *v = r->state.visibility;
            line(&csv, "%s,%s,%s,%s,%s", st.code, stamp(r->time), c<0?"NONE":format("%d", c), v?format("%s%lld", v->qualifier?format("%c",
            v->qualifier):"", (long long)meter_value(v)):"NONE", categories[category(r->state)]);
        }
    }
    for (int i = 0; i<cfg.nv; i++) {
        if (i) append(&verify, "\n");
        verification_block(&verify, station_index(cfg.verify[i]));
    }
    if (ne) qsort(errors, (size_t)ne, sizeof(*errors), compare_errors);
    for (int i = 0; i<ne; i++) line(&err, "report %d word %d: %s%s", errors[i].report, errors[i].position, errors[i].reason,
    errors[i].text?format(" \"%s\"", errors[i].text):"");
    mkdir("output", 0777);
    save("decoded.txt", decoded);
    save("categories.csv", csv);
    save("taf_timeline.txt", tl);
    save("verification.txt", verify);
    save("errors.txt", err);
    return 0;
}
