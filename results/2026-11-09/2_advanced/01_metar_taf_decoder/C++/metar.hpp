#pragma once
static const std::vector<Slot> main_slots = {
    {
        MOD, false
    }, {
        WIND, false
    }, {
        VAR, false
    }, {
        VIS, false
    }, {
        RVR, true
    }, {
        WX, true
    }, {
        CLOUD, true
    }, {
        TEMP, false
    }, {
        PRESS, false
    }, {
        NOSIG, false
    }
};
static const std::vector<Slot> trend_slots = {
    {
        WIND, false
    }, {
        VIS, false
    }, {
        WX, true
    }, {
        CLOUD, true
    }
};

static bool trend_indicator(const string& s) {
    return s == "BECMG" || s == "TEMPO";
}

static bool trend_time(const string& s, const string& prefix) {
    return s.size() == 6 && s.substr(0, 2) == prefix && digits(s.substr(2), 4);
}

static void decode_metar(Report& r, const std::vector<Group>& g, const Station& st) {
    int n = (int)g.size(), remark = n, trend = n;
    for (int i = 0; i<n; i++) if (g[i].text == "RMK") {
        remark = i;
        break;
    }
    for (int i = 0; i<remark; i++) if (trend_indicator(g[i].text)) {
        trend = i;
        break;
    }
    trend = std::min(trend, remark);
    r.state = match_section(g, 0, trend, main_slots, false, st);
    for (int i = trend; i<remark; ) {
        int end = i+1;
        while (end<remark && !trend_indicator(g[end].text))end++;
        Change c;
        c.kind = g[i].text;
        int cursor = i+1, count = 0;
        if (cursor<end && trend_time(g[cursor].text, "FM")) {
            count = 1;
            if (cursor+1<end && trend_time(g[cursor+1].text, "TL"))count = 2;
        } else if (cursor<end && (trend_time(g[cursor].text, "TL") || trend_time(g[cursor].text, "AT")))count = 1;
        bool valid = true;
        for (int j = 0; j<count; j++) {
            const Group& tm = g[cursor+j];
            if (std::stoi(tm.text.substr(2, 2))>23 || std::stoi(tm.text.substr(4, 2))>59) {
                error_at(tm.position, "invalid period", tm.text);
                valid = false;
                break;
            }
            c.times.push_back(tm.text);
        }
        if (valid) {
            c.state = match_section(g, cursor+count, end, trend_slots, true, st);
            r.changes.push_back(std::move(c));
        }
        i = end;
    }
    for (int i = remark+1; i<n; i++) {
        const string& s = g[i].text;
        if (s.size() == 6 && s.substr(0, 3) == "SLP" && digits(s.substr(3), 3)) {
            int p = std::stoi(s.substr(3));
            r.slp.push_back((p >= 500?9000:10000)+p);
        } else if (s.size() == 9 && s[0] == 'T' && (s[1] == '0' || s[1] == '1') && (s[5] == '0' || s[5] == '1') && digits(s.substr(2,
        3), 3) && digits(s.substr(6), 3))r.precise.push_back( {
            std::stoi(s.substr(2, 3))*(s[1] == '1'?-1:1), std::stoi(s.substr(6))*(s[5] == '1'?-1:1)
        });
    }
}
