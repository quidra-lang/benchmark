#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <stdexcept>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <numeric>
#include <optional>
#include <regex>
#include <sstream>
#include <string>
#include <vector>
using std::string;
using I = std::int64_t;
struct Runway {
    string name;
    int heading;
};
struct Station {
    string code, name;
    I elevation = 0;
    std::vector<Runway> runways;
};
struct Settings {
    int year = 0, month = 0, days = 0, next_year = 0, next_month = 0, next_days = 0;
    I cross = 0, tail = 0;
    std::vector<string> verify;
};
struct Group {
    int position;
    string text;
};
struct Value {
    string raw, runway;
    int direction = 0, speed = 0, gust = -1, meters_per_second = 0;
    int variation_from = 0, variation_to = 0;
    int visibility_kind = 0, meters = 0, whole = 0, numerator = 0, denominator = 0, mile_form = 0;
    char qualifier = 0, first_qualifier = 0, second_qualifier = 0;
    int first_reading = 0, second_reading = -1, feet = 0, trend = 0;
    int intensity = 0, descriptor = -1, nsw = 0;
    std::vector<int> phenomena;
    int amount = 0, height = 0, cloud_type = 0;
    int temperature = 0, dew_point = 0;
    int pressure_unit = 0, pressure_value = 0, inch = 0, hectopascals = 0;
};
struct State {
    std::optional<Value> modifier, wind, variation, visibility, temperature, pressure, no_trend;
    std::optional<std::vector<Value>> weather, cloud;
    std::vector<Value> rvr;
};
struct Slot {
    int kind;
    bool repeat;
};
struct Change {
    string kind;
    int start = 0, end = 0;
    State state;
    std::vector<string> times;
};
struct Report {
    int number = 0, time = 0, start = 0, end = 0;
    string kind, station, modifier;
    State state;
    std::vector<Change> changes;
    std::vector<int> slp;
    std::vector<std::array<int, 2>> precise;
    string speci;
};
struct Error {
    int report, position;
    string reason;
    std::optional<string> text;
};
enum {
    MOD, WIND, VAR, VIS, RVR, WX, CLOUD, TEMP, PRESS, NOSIG
};
static Settings cfg;
static std::map<string, Station> stations;
static std::vector<Report> reports;
static std::vector<Error> errors;
static int report_number;
static const std::array<string, 4> categories = {
    "VFR", "MVFR", "IFR", "LIFR"
};

static string pad(I n, int width) {
    std::ostringstream s;
    s<<std::setw(width)<<std::setfill('0')<<n;
    return s.str();
}

static string join(const std::vector<string>& a, const string& separator) {
    string s;
    for (const string& x:a) {
        if (!s.empty()) s += separator;
        s += x;
    }
    return s;
}

static std::vector<string> words(const string& text) {
    std::istringstream in(text);
    std::vector<string> a;
    for (string s; in>>s; ) a.push_back(s);
    return a;
}

static void error_at(int pos, const string& reason, std::optional<string> text = std::nullopt) {
    errors.push_back( {
        report_number, pos, reason, std::move(text)
    });
}
static State match_section(const std::vector<Group>&, int, int, const std::vector<Slot>&, bool, const Station&);
/* These headers share the report types in this translation unit. */
#include "units.hpp"
#include "groups.hpp"
#include "metar.hpp"
#include "taf.hpp"
#include "verification.hpp"
static State match_section(const std::vector<Group>& body, int begin, int end, const std::vector<Slot>& slots,
bool context, const Station& station) {
    State state;
    std::size_t cursor = 0;
    for (int i = begin; i<end; i++) {
        const Group& g = body[i];
        std::optional<Value> value;
        std::size_t found = cursor;
        for (; found<slots.size(); found++) if ((value = group_format(slots[found].kind, g.text))) break;
        if (found == slots.size()) {
            bool earlier = false;
            for (std::size_t j = 0; j<cursor; j++) if (group_format(slots[j].kind, g.text)) {
                earlier = true;
                break;
            }
            error_at(g.position, earlier?"out of order group":"unknown group", g.text);
            continue;
        }
        int kind = slots[found].kind;
        if (!group_valid(kind, *value, state, station, context)) {
            error_at(g.position, "invalid group", g.text);
            continue;
        }
        group_accept(state, kind, *value);
        cursor = found+!slots[found].repeat;
        if (kind == VIS && value->visibility_kind == 1) for (std::size_t j = 0; j<slots.size(); j++) if (slots[j].kind == CLOUD) cursor = j+1;
    }
    return state;
}

static std::optional<int> ceiling(const State& s) {
    if (s.cloud) for (const Value& v:*s.cloud) if (v.amount >= 2 && v.amount <= 4) return v.height;
    return std::nullopt;
}

static int category(const State& s) {
    std::optional<int> c = ceiling(s);
    auto visibility = s.visibility?mile_fraction(*s.visibility):std::pair<I, I> {
        1000000, 1
    };
    I p = visibility.first, q = visibility.second;
    if ((c && *c<500) || p<q) return 3;
    if ((c && *c<1000) || p<3*q) return 2;
    if ((c && *c <= 3000) || p <= 5*q) return 1;
    return 0;
}

static string wind_phrase(const Value& v) {
    if (v.direction == 0) return "calm";
    string text = v.direction<0?"variable at "+std::to_string(v.speed)+" KT":pad(v.direction, 3)+" degrees at "+std::to_string(v.speed)+" KT";
    if (v.gust >= 0) text += " gusting "+std::to_string(v.gust)+" KT";
    return text;
}

static string wind_code(const Value& v) {
    if (v.direction == 0) return "00000KT";
    return (v.direction<0?"VRB":pad(v.direction, 3))+pad(v.speed, 2)+(v.gust<0?"":"G"+pad(v.gust, 2))+"KT";
}

static string mile_number(const Value& v) {
    if (!v.denominator) return std::to_string(v.whole);
    return (v.whole?std::to_string(v.whole)+" ":"")+std::to_string(v.numerator)+"/"+std::to_string(v.denominator);
}

static string visibility_phrase(const Value& v) {
    if (v.visibility_kind == 1) return "10 km or more (CAVOK)";
    if (v.visibility_kind == 0) return v.qualifier == 'P'?"10 km or more":std::to_string(v.meters)+" m";
    return string(v.qualifier == 'M'?"less than ":v.qualifier == 'P'?"more than ":"")+mile_number(v)+" SM";
}

static string visibility_code(const Value& v) {
    if (v.visibility_kind == 1) return "CAVOK";
    if (v.visibility_kind == 0) return v.raw;
    return (v.qualifier?string(1, v.qualifier):"")+mile_number(v)+"SM";
}

static string weather_phrase(const Value& v) {
    if (v.nsw) return "no significant weather";
    std::vector<string> parts, phenomena;
    if (v.intensity) parts.push_back(v.intensity == '-'?"light":v.intensity == '+'?"heavy":"nearby");
    if (v.descriptor >= 0) parts.push_back(descriptor_words[v.descriptor]);
    for (int code:v.phenomena) phenomena.push_back(phenomenon_words[code-8]);
    if (!phenomena.empty()) parts.push_back(join(phenomena, " and "));
    return join(parts, " ");
}

static string cloud_phrase(const Value& v) {
    if (v.amount >= 5) return clear_words[v.amount-5];
    if (v.amount == 4) return "vertical visibility "+std::to_string(v.height)+" ft";
    return amount_words[v.amount]+" at "+std::to_string(v.height)+" ft"+(v.cloud_type == 1?" cumulonimbus":v.cloud_type == 2?" towering cumulus":"");
}

static string summary(const State& s) {
    std::vector<string> p;
    if (s.wind) p.push_back("wind "+wind_phrase(*s.wind));
    if (s.visibility) p.push_back("visibility "+visibility_phrase(*s.visibility));
    if (s.weather && !s.weather->empty()) {
        std::vector<string> x;
        for (const Value& v:*s.weather) x.push_back(weather_phrase(v));
        p.push_back("weather "+join(x, ", "));
    }
    if (s.cloud && !s.cloud->empty()) {
        std::vector<string> x;
        for (const Value& v:*s.cloud) x.push_back(cloud_phrase(v));
        p.push_back("cloud "+join(x, ", "));
    }
    return p.empty()?"no conditions":join(p, "; ");
}

static string tokens(const State& s) {
    std::vector<string> p;
    if (s.wind) p.push_back(wind_code(*s.wind));
    if (s.visibility) p.push_back(visibility_code(*s.visibility));
    if (s.weather) for (const Value& v:*s.weather) if (!v.nsw) p.push_back(v.raw);
    if (s.cloud) for (const Value& v:*s.cloud) p.push_back(v.raw);
    p.push_back(categories[category(s)]);
    return join(p, " ");
}

static int wind_change(const std::optional<Value>& a, const std::optional<Value>& b, int angle) {
    if (!a || !b) return 0;
    int flags = 0;
    if (a->direction>0 && b->direction>0 && std::max(a->speed, b->speed) >= 10) {
        int d = std::abs(a->direction-b->direction)%360;
        if (std::min(d, 360-d) >= angle) flags |= 1;
    }
    if (std::abs(a->speed-b->speed) >= 10) flags |= 2;
    return flags;
}

static bool weather_has(const State& s, int descriptor, bool freezing) {
    if (s.weather) for (const Value& v:*s.weather) if (v.descriptor == descriptor && (!freezing || std::find(v.phenomena.begin(),
    v.phenomena.end(), 8) != v.phenomena.end() || std::find(v.phenomena.begin(), v.phenomena.end(), 9) != v.phenomena.end())) return true;
    return false;
}

static string speci_check(const Report* previous, const Report& r) {
    if (!previous) return "no previous report";
    const State& a = previous->state;
    const State& b = r.state;
    std::vector<string> reasons;
    if (category(a) != category(b)) reasons.push_back("category "+categories[category(a)]+" to "+categories[category(b)]);
    int flags = wind_change(a.wind, b.wind, 45);
    if (flags&1) reasons.push_back("wind shift");
    if (flags&2) reasons.push_back("wind speed");
    if (weather_has(a, 6, false) != weather_has(b, 6, false)) reasons.push_back(string("thunderstorm ")+(weather_has(b,
    6, false)?"began":"ended"));
    if (weather_has(a, 7, true) != weather_has(b, 7, true)) reasons.push_back(string("freezing precipitation ")+(weather_has(b,
    7, true)?"began":"ended"));
    return reasons.empty()?"no criteria met":join(reasons, ", ");
}

static string tenth(int n) {
    return string(n<0?"-":"")+std::to_string(std::abs(n)/10)+"."+std::to_string(std::abs(n)%10);
}

static string component(I h, I c) {
    string s = (h<0?"tailwind ":"headwind ")+std::to_string(std::abs(h))+" KT, crosswind "+std::to_string(std::abs(c))+" KT";
    if (c) s += c>0?" from right":" from left";
    return s;
}

static string reading(char q, int n) {
    return string(q == 'M'?"less than ":q == 'P'?"more than ":"")+std::to_string(n);
}

static std::vector<string> observation_lines(const Report& r) {
    const State& s = r.state;
    const Station& st = stations.at(r.station);
    std::vector<string> lines = {
        "time: "+stamp(r.time)
    };
    if (s.modifier) lines.push_back("modifier: "+string(s.modifier->raw == "AUTO"?"automated":"corrected"));
    string w = s.wind?wind_phrase(*s.wind):"not reported";
    if (s.variation) w += ", varying between "+pad(s.variation->variation_from, 3)+" and "+pad(s.variation->variation_to,
    3)+" degrees";
    lines.push_back("wind: "+w);
    lines.push_back("visibility: "+(s.visibility?visibility_phrase(*s.visibility):"not reported"));
    for (const Value& v:s.rvr) {
        string x = v.second_reading<0?reading(v.first_qualifier, v.first_reading):"between "+reading(v.first_qualifier,
        v.first_reading)+" and "+reading(v.second_qualifier, v.second_reading);
        lines.push_back("runway visual range: runway "+v.runway+" "+x+(v.feet?" ft":" m")+(v.trend == 'U'?", rising":v.trend == 'D'?", falling":v.trend == 'N'?", no change":""));
    }
    if (s.weather) for (const Value& v:*s.weather) lines.push_back("weather: "+weather_phrase(v));
    if (s.visibility && s.visibility->visibility_kind == 1) lines.push_back("cloud: no significant cloud");
    else if (!s.cloud) lines.push_back("cloud: not reported");
    else for (const Value& v:*s.cloud) lines.push_back("cloud: "+cloud_phrase(v));
    if (s.temperature) lines.push_back("temperature: "+std::to_string(s.temperature->temperature)+" C, dew point "+std::to_string(s.temperature->dew_point)+" C, spread "+std::to_string(s.temperature->temperature-s.temperature->dew_point)+" C");
    else lines.push_back("temperature: not reported");
    if (s.pressure) {
        const Value& v = *s.pressure;
        string inch = std::to_string(v.inch/100)+"."+pad(v.inch%100, 2)+" inHg", hpa = std::to_string(v.hectopascals)+" hPa";
        lines.push_back("altimeter: "+(v.pressure_unit == 'A'?inch:hpa)+" ("+(v.pressure_unit == 'A'?hpa:inch)+")");
    } else lines.push_back("altimeter: not reported");
    if (s.no_trend) lines.push_back("trend: no significant change");
    for (const Change& c:r.changes) {
        string x = c.kind == "BECMG"?"becoming":"temporarily";
        for (const string& tm:c.times) x += " "+string(tm[0] == 'F'?"from":tm[0] == 'T'?"until":"at")+" "+tm.substr(2,
        2)+":"+tm.substr(4, 2)+"Z";
        lines.push_back("trend: "+x+": "+summary(c.state));
    }
    for (int p:r.slp) lines.push_back("sea level pressure: "+tenth(p)+" hPa");
    for (const auto& p:r.precise) lines.push_back("precise temperature: "+tenth(p[0])+" C, dew point "+tenth(p[1])+" C");
    std::optional<int> c = ceiling(s);
    lines.push_back("ceiling: "+(c?std::to_string(*c)+" ft":"none"));
    lines.push_back("flight category: "+categories[category(s)]);
    std::optional<I> pa;
    if (s.pressure) pa = st.elevation+(2992-s.pressure->inch)*10;
    lines.push_back("pressure altitude: "+(pa?std::to_string(*pa)+" ft":"not available"));
    lines.push_back("density altitude: "+(pa && s.temperature?std::to_string(*pa+floor_div(120*(1000*(I)s.temperature->temperature-15000+2*(*pa)),
    1000))+" ft":"not available"));
    if (!s.wind || s.wind->direction <= 0) lines.push_back("runway wind: not computed");
    else {
        const Value& v = *s.wind;
        std::vector<string> usable;
        string best = "none";
        I best_head = 0;
        for (const Runway& rw:st.runways) {
            int angle = v.direction-rw.heading;
            I h = floor_div(v.speed*icos(angle), 1000), c = floor_div(v.speed*isin(angle), 1000), gh = h, gc = c;
            if (v.gust >= 0) {
                gh = floor_div(v.gust*icos(angle), 1000);
                gc = floor_div(v.gust*isin(angle), 1000);
            }
            lines.push_back("runway "+rw.name+": "+component(h, c)+(v.gust >= 0?"; gusts "+component(gh, gc):""));
            if (std::abs(gc) <= cfg.cross && -gh <= cfg.tail) {
                usable.push_back(rw.name);
                if (best == "none" || h>best_head) {
                    best = rw.name;
                    best_head = h;
                }
            }
        }
        lines.push_back("usable runways: "+(usable.empty()?"none":join(usable, " ")));
        lines.push_back("preferred runway: "+best);
    }
    if (r.kind == "SPECI") lines.push_back("speci check: "+r.speci);
    return lines;
}

static std::vector<string> forecast_lines(const Report& r) {
    std::vector<string> l = {
        "issued: "+stamp(r.time)
    };
    if (!r.modifier.empty()) l.push_back("modifier: "+string(r.modifier == "AMD"?"amended":"corrected"));
    l.push_back("valid: "+stamp(r.start)+" to "+stamp(r.end));
    l.push_back("base: "+summary(r.state));
    for (const Change& c:r.changes) l.push_back(c.kind+" "+(c.kind == "FM"?stamp(c.start):stamp(c.start)+" to "+stamp(c.end))+": "+summary(c.state));
    return l;
}

static string count_text(const std::array<I, 4>& counts) {
    std::vector<string> parts;
    for (int i = 0; i<4; i++) parts.push_back(categories[i]+" "+std::to_string(counts[i]));
    return join(parts, ", ");
}

static string timeline(const Report& r) {
    std::vector<string> lines = {
        "TAF "+r.station+" issued "+stamp(r.time)+" valid "+stamp(r.start)+" to "+stamp(r.end)
    };
    std::array<I, 4> counts {
    };
    for (int h = r.start; h<r.end; h += 60) {
        State s = prevailing(r, h);
        counts[category(s)]++;
        string row = stamp(h)+" "+tokens(s);
        for (const Change& c:r.changes) if (temporary(c, h)) row += " | "+c.kind+" "+tokens(overlay(s, c.state));
        lines.push_back(row);
    }
    lines.push_back("summary: "+count_text(counts));
    return join(lines, "\n");
}

static bool visibility_less(const Value& a, const Value& b) {
    auto x = mile_fraction(a), y = mile_fraction(b);
    return x.first*y.second<y.first*x.second;
}

static string verification_block(const string& code) {
    const Station& st = stations.at(code);
    std::array<I, 4> counts {
    };
    int nm = 0, nsp = 0, missing = 0;
    std::array<const Report*, 5> ext {
    };
    Contingency ct;
    std::array<std::array<I, 2>, 5> buckets {
    };
    std::vector<string> amendments;
    for (const Report& r:reports) {
        if (r.station != code || r.kind == "TAF") continue;
        const State& s = r.state;
        int cat = category(s);
        counts[cat]++;
        if (r.kind == "METAR") nm++;
        else nsp++;
        if (s.temperature) {
            if (!ext[0] || s.temperature->temperature<ext[0]->state.temperature->temperature) ext[0] = &r;
            if (!ext[1] || s.temperature->temperature>ext[1]->state.temperature->temperature) ext[1] = &r;
        }
        if (s.wind && (!ext[2] || wind_strength(*s.wind)>wind_strength(*ext[2]->state.wind))) ext[2] = &r;
        if (ceiling(s) && (!ext[3] || *ceiling(s)<*ceiling(ext[3]->state))) ext[3] = &r;
        if (s.visibility && (!ext[4] || visibility_less(*s.visibility, *ext[4]->state.visibility))) ext[4] = &r;
        const Report* f = choose_forecast(reports, code, r.time);
        int h = r.time-r.time%60;
        for (const Report& a:reports) if (a.station == code && covers(a, r.time)) {
            int b = (h-a.start)/360;
            buckets[b][1]++;
            if (category(prevailing(a, h)) == cat) buckets[b][0]++;
        }
        if (!f) {
            missing++;
            continue;
        }
        State p = prevailing(*f, h);
        int fc = category(p);
        bool hit = fc == cat;
        for (const Change& c:f->changes) if (temporary(c, h) && category(overlay(p, c.state)) == cat) hit = true;
        ct.add(fc, cat, hit);
        std::vector<string> reasons;
        if (!hit) reasons.push_back("category "+categories[cat]+", forecast "+categories[fc]);
        if (wind_change(p.wind, s.wind, 60)) reasons.push_back("wind "+wind_code(*s.wind)+", forecast "+wind_code(*p.wind));
        if (!reasons.empty()) amendments.push_back("amendment "+stamp(r.time)+": "+join(reasons, "; "));
    }
    std::vector<string> lines = {
        "station "+code+" ("+st.name+")", "reports: METAR "+std::to_string(nm)+", SPECI "+std::to_string(nsp), "observed categories: "+count_text(counts)
    };
    std::array<string, 5> labels = {
        "lowest temperature", "highest temperature", "strongest wind", "lowest ceiling", "lowest visibility"
    };
    for (int i = 0; i<5; i++) {
        if (!ext[i]) {
            lines.push_back(labels[i]+": not available");
            continue;
        }
        const State& s = ext[i]->state;
        string v = i<2?std::to_string(s.temperature->temperature)+" C":i == 2?wind_phrase(*s.wind):i == 3?std::to_string(*ceiling(s))+" ft":visibility_phrase(*s.visibility);
        lines.push_back(labels[i]+": "+v+" at "+stamp(ext[i]->time));
    }
    I n = ct.total();
    lines.push_back("verified: "+std::to_string(n));
    lines.push_back("no forecast: "+std::to_string(missing));
    auto row = [](const string& name, const std::vector<string>& cells) {
        std::ostringstream s;
        s<<std::left<<std::setw(8)<<name;
        for (const string& cell:cells) s<<std::right<<std::setw(6)<<cell;
        return s.str();
    };
    lines.push_back(row("forecast", {
        "VFR", "MVFR", "IFR", "LIFR", "total"
    }));
    for (int i = 0; i<4; i++) {
        std::vector<string> cells;
        for (int j = 0; j<4; j++) cells.push_back(std::to_string(ct.table[i][j]));
        cells.push_back(std::to_string(ct.row(i)));
        lines.push_back(row(categories[i], cells));
    }
    std::vector<string> totals;
    for (int i = 0; i<4; i++) totals.push_back(std::to_string(ct.column(i)));
    totals.push_back(std::to_string(n));
    lines.push_back(row("total", totals));
    lines.push_back("hit rate: "+fraction(ct.hits(), n));
    lines.push_back("hit rate with temporary groups: "+fraction(ct.temporary_hits, n));
    auto score = ct.skill();
    lines.push_back("heidke skill score: "+fraction(score.first, score.second));
    for (int i = 0; i<4; i++) {
        auto pod = ct.detection(i), far = ct.false_alarm(i);
        lines.push_back(categories[i]+": pod "+fraction(pod.first, pod.second)+", far "+fraction(far.first, far.second));
    }
    for (int i = 0; i<5; i++) lines.push_back("hours "+std::to_string(i*6)+"-"+std::to_string(i*6+5)+": "+fraction(buckets[i][0],
    buckets[i][1]));
    lines.insert(lines.end(), amendments.begin(), amendments.end());
    return join(lines, "\n");
}

static std::vector<Group> join_groups(const std::vector<string>& w, int cursor) {
    std::vector<Group> g;
    for (int i = cursor; i<(int)w.size(); i++) {
        int pos = i+1;
        string s = w[i];
        if (s.size() == 1 && s[0] >= '0' && s[0] <= '9' && i+1<(int)w.size() && fraction_word(w[i+1])) {
            i++;
            s += " "+w[i];
        }
        g.push_back( {
            pos, s
        });
    }
    return g;
}

static void process(const std::vector<string>& w, int number, std::map<string, std::size_t>& previous) {
    report_number = number;
    Report r;
    r.number = number;
    r.kind = w[0];
    int cursor = 1;
    if (r.kind != "METAR" && r.kind != "SPECI" && r.kind != "TAF") {
        error_at(1, "rejected report, invalid type", w[0]);
        return;
    }
    bool forecast = r.kind == "TAF";
    if (forecast && cursor<(int)w.size() && (w[cursor] == "AMD" || w[cursor] == "COR")) r.modifier = w[cursor++];
    for (int item = 0; item<(forecast?3:2); item++, cursor++) {
        string name = item == 0?"station":item == 1?"time":"validity";
        if (cursor == (int)w.size()) {
            error_at(cursor+1, "rejected report, missing "+name);
            return;
        }
        bool valid = false;
        if (item == 0) {
            valid = stations.count(w[cursor]);
            r.station = w[cursor];
        } else if (item == 1) {
            auto time = observation_time(w[cursor]);
            valid = bool(time);
            if (time) r.time = *time;
        } else {
            auto period = parse_period(w[cursor], r.time/1440+1);
            valid = period && period->second <= period->first+1800;
            if (period) {
                r.start = period->first;
                r.end = period->second;
            }
        }
        if (!valid) {
            error_at(cursor+1, "rejected report, invalid "+name, w[cursor]);
            return;
        }
    }
    std::vector<Group> g = join_groups(w, cursor);
    if (forecast) decode_taf(r, g, stations.at(r.station));
    else {
        decode_metar(r, g, stations.at(r.station));
        if (r.kind == "SPECI") r.speci = speci_check(previous.count(r.station)?&reports[previous[r.station]]:nullptr,
        r);
        previous[r.station] = reports.size();
    }
    reports.push_back(std::move(r));
}

static std::vector<string> read_lines(const string& name) {
    std::ifstream in("input/"+name);
    if (!in) throw std::runtime_error("cannot open input");
    std::vector<string> lines;
    for (string s; std::getline(in, s); ) lines.push_back(s);
    return lines;
}

static void read_inputs() {
    for (const string& line:read_lines("stations.txt")) {
        std::istringstream in(line);
        Station st;
        string runway_list;
        in>>st.code>>st.elevation>>runway_list;
        std::getline(in, st.name);
        st.name.erase(0, 1);
        std::istringstream runway_stream(runway_list);
        for (string s; std::getline(runway_stream, s, ','); ) {
            std::size_t p = s.find('/');
            st.runways.push_back( {
                s.substr(0, p), std::stoi(s.substr(p+1))
            });
        }
        stations[st.code] = std::move(st);
    }
    std::vector<string> params = read_lines("params.txt");
    cfg.year = std::stoi(words(params[0])[1]);
    cfg.month = std::stoi(words(params[1])[1]);
    cfg.cross = std::stoll(words(params[2])[1]);
    cfg.tail = std::stoll(words(params[3])[1]);
    cfg.verify = words(params[4]);
    cfg.verify.erase(cfg.verify.begin());
    calendar_init();
    std::vector<string> raw;
    int number = 0;
    std::map<string, std::size_t> previous;
    for (const string& line:read_lines("reports.txt")) {
        if (line[0] != ' ' && !raw.empty()) {
            process(raw, ++number, previous);
            raw.clear();
        }
        std::vector<string> w = words(line);
        raw.insert(raw.end(), w.begin(), w.end());
    }
    if (!raw.empty()) process(raw, ++number, previous);
}

static void save(const string& name, const std::vector<string>& items, const string& separator) {
    std::ofstream out("output/"+name);
    if (!items.empty()) out<<join(items, separator)<<'\n';
}
int main() {
    read_inputs();
    std::vector<string> decoded, csv = {
        "station,time,ceiling,visibility,category"
    }, timelines, verification, error_lines;
    for (const Report& r:reports) {
        string block = "REPORT "+std::to_string(r.number)+": "+r.kind+" "+r.station+" ("+stations.at(r.station).name+")";
        for (const string& line:r.kind == "TAF"?forecast_lines(r):observation_lines(r)) block += "\n  "+line;
        decoded.push_back(block);
        if (r.kind == "TAF") timelines.push_back(timeline(r));
        else {
            auto c = ceiling(r.state);
            string v = "NONE";
            if (r.state.visibility) {
                const Value& vis = *r.state.visibility;
                v = (vis.qualifier?string(1, vis.qualifier):"")+std::to_string(meter_value(vis));
            }
            csv.push_back(r.station+","+stamp(r.time)+","+(c?std::to_string(*c):"NONE")+","+v+","+categories[category(r.state)]);
        }
    }
    for (const string& code:cfg.verify) verification.push_back(verification_block(code));
    std::stable_sort(errors.begin(), errors.end(), [](const Error& a, const Error& b) {
        return a.report != b.report?a.report<b.report:a.position<b.position;
    });
    for (const Error& e:errors) error_lines.push_back("report "+std::to_string(e.report)+" word "+std::to_string(e.position)+": "+e.reason+(e.text?" \""+*e.text+"\"":""));
    std::filesystem::create_directories("output");
    save("decoded.txt", decoded, "\n\n");
    save("categories.csv", csv, "\n");
    save("taf_timeline.txt", timelines, "\n\n");
    save("verification.txt", verification, "\n\n");
    save("errors.txt", error_lines, "\n");
}
