#pragma once
#include <regex.h>
static const char *descriptor_codes[] = {
    "MI", "BC", "PR", "DR", "BL", "SH", "TS", "FZ"
};
static const char *descriptor_words[] = {
    "shallow", "patches", "partial", "low drifting", "blowing", "showers", "thunderstorm", "freezing"
};
static const char *phenomenon_codes[] = {
    "DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP", "BR", "FG", "FU", "VA", "DU", "SA", "HZ", "PY", "PO",
    "SQ", "FC", "SS", "DS"
};
static const char *phenomenon_words[] = {
    "drizzle", "rain", "snow", "snow grains", "ice crystals", "ice pellets", "hail", "small hail", "unknown precipitation",
    "mist", "fog", "smoke", "volcanic ash", "dust", "sand", "haze", "spray", "dust whirls", "squalls", "funnel cloud",
    "sandstorm", "duststorm"
};
static const char *amount_codes[] = {
    "FEW", "SCT", "BKN", "OVC", "VV", "SKC", "CLR", "NSC"
};
static const char *amount_words[] = {
    "few", "scattered", "broken", "overcast"
};
static const char *clear_words[] = {
    "sky clear", "clear below 12000 ft", "no significant cloud"
};

static int digits(const char *s, int n) {
    if ((int)strlen(s) != n) return 0;
    for (int i = 0; i<n; i++) if (s[i]<'0' || s[i]>'9') return 0;
    return 1;
}

static int number_at(const char *s, int start, int n) {
    int v = 0;
    for (int i = 0; i<n; i++) v = v*10+s[start+i]-'0';
    return v;
}

static int pattern(int id, const char *s, regmatch_t *m) {
    static regex_t compiled[13];
    static int ready[13];
    static const char *patterns[] = {
        "^(AUTO|COR)$", "^([0-9]{3}|VRB)([0-9]{2,3})(G([0-9]{2,3}))?(KT|MPS)$", "^([0-9]{3})V([0-9]{3})$", "^([MP]?)([0-9]{1,2}|[0-9]/[0-9]{1,2})SM$",
        "^R([0-9]{2}[LCR]?)/([MP]?)([0-9]{4})(V([MP]?)([0-9]{4}))?(FT)?([UDN])?$", "", "^(FEW|SCT|BKN|OVC)([0-9]{3})(CB|TCU)?$",
        "^(M?)([0-9]{2})/(M?)([0-9]{2})$", "^([AQ])([0-9]{4})$", "^NOSIG$", "^([0-9]) ([0-9])/([0-9]{1,2})SM$", "^[0-9]/[0-9]{1,2}SM$",
        "^VV([0-9]{3})$"
    };
    if (!ready[id]) {
        if (regcomp(&compiled[id], patterns[id], REG_EXTENDED)) exit(1);
        ready[id] = 1;
    }
    return regexec(&compiled[id], s, 12, m, 0) == 0;
}

static int capnum(const char *s, regmatch_t *m, int i) {
    return m[i].rm_so<0?0:number_at(s, m[i].rm_so, m[i].rm_eo-m[i].rm_so);
}

static char capchar(const char *s, regmatch_t *m, int i) {
    return m[i].rm_so<0 || m[i].rm_so == m[i].rm_eo?0:s[m[i].rm_so];
}

static int fraction_word(const char *s) {
    regmatch_t m[12];
    return pattern(11, s, m);
}

static int code_index(const char *s) {
    for (int i = 0; i<8; i++) if (strncmp(s, descriptor_codes[i], 2) == 0) return i;
    for (int i = 0; i<22; i++) if (strncmp(s, phenomenon_codes[i], 2) == 0) return i+8;
    return -1;
}

static Value *group_format(int kind, const char *text) {
    Value *v = allocate(sizeof(*v));
    v->raw = (char *)text;
    regmatch_t m[12];
    int ok = 0;
    switch (kind) {
        case MOD: case NOSIG: ok = pattern(kind, text, m);
        break;
        case WIND: if ((ok = pattern(WIND, text, m))) {
            v->direction = capchar(text, m, 1) == 'V'?-1:capnum(text, m, 1);
            v->speed = capnum(text, m, 2);
            v->gust = m[4].rm_so<0?-1:capnum(text, m, 4);
            v->meters_per_second = capchar(text, m, 5) == 'M';
        }
        break;
        case VAR: if ((ok = pattern(VAR, text, m))) {
            v->variation_from = capnum(text, m, 1);
            v->variation_to = capnum(text, m, 2);
        }
        break;
        case VIS: if (!strcmp(text, "CAVOK")) {
            ok = 1;
            v->visibility_kind = 1;
            v->meters = 10000;
            v->qualifier = 'P';
        } else if (digits(text, 4)) {
            ok = 1;
            v->meters = atoi(text);
            if (v->meters == 9999) {
                v->meters = 10000;
                v->qualifier = 'P';
            }
        } else if (pattern(10, text, m)) {
            ok = 1;
            v->visibility_kind = 2;
            v->whole = capnum(text, m, 1);
            v->numerator = capnum(text, m, 2);
            v->denominator = capnum(text, m, 3);
            v->mile_form = 1;
        } else if (pattern(VIS, text, m)) {
            ok = 1;
            v->visibility_kind = 2;
            v->qualifier = capchar(text, m, 1);
            char *body = slice(text, m[2].rm_so, m[2].rm_eo-m[2].rm_so), *slash = strchr(body, '/');
            if (slash) {
                *slash = 0;
                v->numerator = atoi(body);
                v->denominator = atoi(slash+1);
                v->mile_form = 2;
            } else v->whole = atoi(body);
            free(body);
        }
        break;
        case RVR: if ((ok = pattern(RVR, text, m))) {
            int n = m[1].rm_eo-m[1].rm_so;
            memcpy(v->runway, text+m[1].rm_so, (size_t)n);
            v->first_qualifier = capchar(text, m, 2);
            v->first_reading = capnum(text, m, 3);
            v->second_qualifier = capchar(text, m, 5);
            v->second_reading = m[6].rm_so<0?-1:capnum(text, m, 6);
            v->feet = m[7].rm_so >= 0;
            v->trend = capchar(text, m, 8);
        }
        break;
        case WX: v->descriptor = -1;
        if (!strcmp(text, "NSW")) {
            ok = 1;
            v->nsw = 1;
        } else {
            const char *p = text;
            if (!strncmp(p, "VC", 2)) {
                v->intensity = 'V';
                p += 2;
            } else if (*p == '-' || *p == '+') v->intensity = *p++;
            int n = (int)strlen(p);
            ok = n>0 && n%2 == 0;
            for (int i = 0; ok && i<n; i += 2) {
                int code = code_index(p+i);
                if (code<0) ok = 0;
                else if (i == 0 && code<8) v->descriptor = code;
                else v->phenomena[v->nphenomena++] = code;
            }
        }
        break;
        case CLOUD: for (int i = 5; i<8; i++) if (!strcmp(text, amount_codes[i])) {
            ok = 1;
            v->amount = i;
        }
        if (!ok && pattern(CLOUD, text, m)) {
            ok = 1;
            for (int i = 0; i<4; i++) if (!strncmp(text, amount_codes[i], 3)) v->amount = i;
            v->height = capnum(text, m, 2)*100;
            v->cloud_type = m[3].rm_so<0?0:capchar(text, m, 3) == 'C'?1:2;
        }
        if (!ok && pattern(12, text, m)) {
            ok = 1;
            v->amount = 4;
            v->height = capnum(text, m, 1)*100;
        }
        break;
        case TEMP: if ((ok = pattern(TEMP, text, m))) {
            v->temperature = capnum(text, m, 2)*(capchar(text, m, 1)?-1:1);
            v->dew_point = capnum(text, m, 4)*(capchar(text, m, 3)?-1:1);
        }
        break;
        case PRESS: if ((ok = pattern(PRESS, text, m))) {
            v->pressure_unit = capchar(text, m, 1);
            v->pressure_value = capnum(text, m, 2);
        }
        break;
    }
    if (!ok) {
        free(v);
        return NULL;
    }
    return v;
}

static int group_valid(int kind, Value *v, State *s, Station *st, int context) {
    switch (kind) {
        case WIND: if (v->direction<0) {
            if (v->speed<1) return 0;
        } else if (v->direction>360 || v->direction%10 || ((v->direction == 0) != (v->speed == 0))) return 0;
        return v->gust<0 || (v->direction != 0 && v->gust>v->speed);
        case VAR: return v->variation_from >= 10 && v->variation_from <= 360 && v->variation_from%10 == 0 && v->variation_to >= 10 && v->variation_to <= 360 && v->variation_to%10 == 0 && v->variation_from != v->variation_to && s->wind && s->wind->direction>0;
        case VIS: if (v->visibility_kind != 2) return 1;
        if (!v->mile_form) return v->whole >= 1;
        return (v->denominator == 2 || v->denominator == 4 || v->denominator == 8 || v->denominator == 16) && v->numerator >= 1 && v->numerator<v->denominator && (v->mile_form != 1 || v->whole >= 1);
        case RVR: {
            int found = 0;
            for (int i = 0; i<st->nr; i++) if (!strcmp(v->runway, st->runways[i].name)) found = 1;
            return found && (v->second_reading<0 || v->first_reading<v->second_reading);
        }
        case WX: if (s->nw >= 3 || (s->nw>0 && s->weather[0]->nsw)) return 0;
        if (v->nsw) return s->nw <= 0 && context;
        {
            int precip = 0;
            for (int i = 0; i<v->nphenomena; i++) {
                if (v->phenomena[i]<8) return 0;
                if (v->phenomena[i]<17) precip++;
                for (int j = 0; j<i; j++) if (v->phenomena[i] == v->phenomena[j]) return 0;
            }
            if (!v->nphenomena && v->descriptor != 5 && v->descriptor != 6) return 0;
            if ((v->intensity == '-' || v->intensity == '+') && !precip) return 0;
            return v->nphenomena<2 || precip == v->nphenomena;
        }
        case CLOUD: return s->nc <= 0 || (v->amount<4 && s->cloud[s->nc-1]->amount<4 && v->height>s->cloud[s->nc-1]->height);
        case TEMP: return v->dew_point <= v->temperature;
        case PRESS: return v->pressure_unit == 'A'?(v->pressure_value >= 2500 && v->pressure_value <= 3150):(v->pressure_value >= 850 && v->pressure_value <= 1070);
        default: return 1;
    }
}

static void group_accept(State *s, int kind, Value *v) {
    if (kind == WIND && v->meters_per_second) {
        v->speed = knots(v->speed);
        if (v->gust >= 0) v->gust = knots(v->gust);
    }
    if (kind == PRESS) {
        v->inch = v->pressure_unit == 'A'?v->pressure_value:inhg(v->pressure_value);
        v->hectopascals = v->pressure_unit == 'Q'?v->pressure_value:hpa(v->pressure_value);
    }
    switch (kind) {
        case MOD:s->modifier = v;
        break;
        case WIND:s->wind = v;
        break;
        case VAR:s->variation = v;
        break;
        case VIS:s->visibility = v;
        if (v->visibility_kind == 1) {
            s->nw = s->nc = 0;
        }
        break;
        case RVR:push_value(&s->rvr, &s->nr, v);
        break;
        case WX:if (s->nw<0)s->nw = 0;
        push_value(&s->weather, &s->nw, v);
        break;
        case CLOUD:if (s->nc<0)s->nc = 0;
        push_value(&s->cloud, &s->nc, v);
        break;
        case TEMP:s->temperature = v;
        break;
        case PRESS:s->pressure = v;
        break;
        case NOSIG:s->no_trend = v;
        break;
    }
}
