#pragma once
static const Slot main_slots[] = {
    {
        MOD, 0
    }, {
        WIND, 0
    }, {
        VAR, 0
    }, {
        VIS, 0
    }, {
        RVR, 1
    }, {
        WX, 1
    }, {
        CLOUD, 1
    }, {
        TEMP, 0
    }, {
        PRESS, 0
    }, {
        NOSIG, 0
    }
};
static const Slot trend_slots[] = {
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

static int trend_indicator(const char *s) {
    return !strcmp(s, "BECMG") || !strcmp(s, "TEMPO");
}

static int trend_time(const char *s, const char *prefix) {
    return strlen(s) == 6 && !strncmp(s, prefix, 2) && digits(s+2, 4);
}

static void add_change(Report *r, Change c) {
    r->changes = realloc(r->changes, (size_t)(r->nch+1)*sizeof(*r->changes));
    r->changes[r->nch++] = c;
}

static void decode_metar(Report *r, Group *g, int n) {
    int remark = n, trend = n;
    for (int i = 0; i<n; i++) if (!strcmp(g[i].text, "RMK")) {
        remark = i;
        break;
    }
    for (int i = 0; i<remark; i++) if (trend_indicator(g[i].text)) {
        trend = i;
        break;
    }
    if (trend>remark) trend = remark;
    r->state = match_section(g, trend, main_slots, 10, 0, &stations[r->station]);
    for (int i = trend; i<remark; ) {
        int end = i+1;
        while (end<remark && !trend_indicator(g[end].text)) end++;
        Change c = {
            0
        };
        c.kind = g[i].text;
        int cursor = i+1, count = 0;
        if (cursor<end && trend_time(g[cursor].text, "FM")) {
            count = 1;
            if (cursor+1<end && trend_time(g[cursor+1].text, "TL")) count = 2;
        } else if (cursor<end && (trend_time(g[cursor].text, "TL") || trend_time(g[cursor].text, "AT"))) count = 1;
        int valid = 1;
        for (int j = 0; j<count; j++) {
            char *s = g[cursor+j].text;
            if (number_at(s, 2, 2)>23 || number_at(s, 4, 2)>59) {
                error_at(g[cursor+j].position, "invalid period", s);
                valid = 0;
                break;
            }
        }
        if (valid) {
            c.nt = count;
            c.times = allocate((size_t)count*sizeof(*c.times));
            for (int j = 0; j<count; j++) c.times[j] = g[cursor+j].text;
            c.state = match_section(g+cursor+count, end-cursor-count, trend_slots, 4, 1, &stations[r->station]);
            add_change(r, c);
        }
        i = end;
    }
    for (int i = remark+1; i<n; i++) {
        char *s = g[i].text;
        if (strlen(s) == 6 && !strncmp(s, "SLP", 3) && digits(s+3, 3)) {
            int p = atoi(s+3);
            r->slp = realloc(r->slp, (size_t)(r->nslp+1)*sizeof(*r->slp));
            r->slp[r->nslp++] = (p >= 500?9000:10000)+p;
        } else if (strlen(s) == 9 && s[0] == 'T' && (s[1] == '0' || s[1] == '1') && (s[5] == '0' || s[5] == '1') && digits(slice(s,
        2, 3), 3) && digits(s+6, 3)) {
            r->precise = realloc(r->precise, (size_t)(r->np+1)*sizeof(*r->precise));
            r->precise[r->np][0] = number_at(s, 2, 3)*(s[1] == '1'?-1:1);
            r->precise[r->np++][1] = number_at(s, 6, 3)*(s[5] == '1'?-1:1);
        }
    }
}
