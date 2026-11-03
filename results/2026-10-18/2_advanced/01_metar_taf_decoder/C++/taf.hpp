#pragma once
static const std::vector<Slot> taf_slots = {
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

static std::optional<int> observation_time(const string& s) {
    if (s.size() != 7 || s[6] != 'Z' || !digits(s.substr(0, 6), 6))return std::nullopt;
    int d = std::stoi(s.substr(0, 2)), h = std::stoi(s.substr(2, 2)), m = std::stoi(s.substr(4, 2));
    if (d<1 || d>cfg.days || h>23 || m>59)return std::nullopt;
    return ((d-1)*24+h)*60+m;
}

static bool period_format(const string& s) {
    return s.size() == 9 && s[4] == '/' && digits(s.substr(0, 4), 4) && digits(s.substr(5), 4);
}

static std::optional<std::pair<int, int>> parse_period(const string& s, int day) {
    if (!period_format(s))return std::nullopt;
    int h1 = std::stoi(s.substr(2, 2)), h2 = std::stoi(s.substr(7, 2));
    if (h1>23 || h2<1 || h2>24)return std::nullopt;
    auto start = forecast_time(std::stoi(s.substr(0, 2)), h1, 0, day), end = forecast_time(std::stoi(s.substr(5,
    2)), h2, 0, day);
    if (!start || !end || *start >= *end)return std::nullopt;
    return std::pair<int, int> {
        *start, *end
    };
}

static bool fm_indicator(const string& s) {
    return s.size() == 8 && s.substr(0, 2) == "FM" && digits(s.substr(2), 6);
}

static bool change_indicator(const string& s) {
    return fm_indicator(s) || trend_indicator(s) || s == "PROB30" || s == "PROB40";
}

static void decode_taf(Report& r, const std::vector<Group>& g, const Station& st) {
    int n = (int)g.size(), base = 0;
    while (base<n && !change_indicator(g[base].text))base++;
    r.state = match_section(g, 0, base, taf_slots, false, st);
    int i = base;
    while (i<n) {
        int pos = g[i].position;
        string kind = g[i++].text;
        Change c;
        c.kind = kind;
        bool valid = true;
        if ((kind == "PROB30" || kind == "PROB40") && i<n && g[i].text == "TEMPO") {
            c.kind += " TEMPO";
            i++;
        }
        if (fm_indicator(kind)) {
            c.kind = "FM";
            int h = std::stoi(kind.substr(4, 2)), m = std::stoi(kind.substr(6, 2));
            auto time = forecast_time(std::stoi(kind.substr(2, 2)), h, m, r.time/1440+1);
            if (h>23 || m>59 || !time || *time<r.start || *time >= r.end) {
                error_at(pos, "invalid period", kind);
                valid = false;
            } else c.start = *time;
        } else if (i == n || !period_format(g[i].text)) {
            error_at(pos, "missing period", c.kind);
            valid = false;
        } else {
            auto p = parse_period(g[i].text, r.time/1440+1);
            if (!p || p->first<r.start || p->second>r.end) {
                error_at(g[i].position, "invalid period", g[i].text);
                valid = false;
            } else {
                c.start = p->first;
                c.end = p->second;
            }
            i++;
        }
        int end = i;
        while (end<n && !change_indicator(g[end].text))end++;
        if (valid) {
            c.state = match_section(g, i, end, taf_slots, true, st);
            r.changes.push_back(std::move(c));
        }
        i = end;
    }
}

static State overlay(State a, const State& b) {
    if (b.wind)a.wind = b.wind;
    if (b.visibility)a.visibility = b.visibility;
    if (b.weather)a.weather = b.weather;
    if (b.cloud)a.cloud = b.cloud;
    return a;
}

static State prevailing(const Report& r, int hour) {
    State s = r.state;
    for (const Change& c:r.changes) {
        if (c.kind == "FM" && c.start <= hour)s = c.state;
        else if (c.kind == "BECMG" && c.end <= hour)s = overlay(s, c.state);
    }
    return s;
}

static bool temporary(const Change& c, int hour) {
    return c.kind != "FM" && c.kind != "BECMG" && c.start <= hour && hour<c.end;
}
