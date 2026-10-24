#pragma once
static const std::vector<string> descriptor_codes = {
    "MI", "BC", "PR", "DR", "BL", "SH", "TS", "FZ"
};
static const std::vector<string> descriptor_words = {
    "shallow", "patches", "partial", "low drifting", "blowing", "showers", "thunderstorm", "freezing"
};
static const std::vector<string> phenomenon_codes = {
    "DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP", "BR", "FG", "FU", "VA", "DU", "SA", "HZ", "PY", "PO",
    "SQ", "FC", "SS", "DS"
};
static const std::vector<string> phenomenon_words = {
    "drizzle", "rain", "snow", "snow grains", "ice crystals", "ice pellets", "hail", "small hail", "unknown precipitation",
    "mist", "fog", "smoke", "volcanic ash", "dust", "sand", "haze", "spray", "dust whirls", "squalls", "funnel cloud",
    "sandstorm", "duststorm"
};
static const std::vector<string> amount_codes = {
    "FEW", "SCT", "BKN", "OVC", "VV", "SKC", "CLR", "NSC"
};
static const std::vector<string> amount_words = {
    "few", "scattered", "broken", "overcast"
};
static const std::vector<string> clear_words = {
    "sky clear", "clear below 12000 ft", "no significant cloud"
};

static bool digits(const string& s, int n) {
    return (int)s.size() == n && std::all_of(s.begin(), s.end(), [](char c) {
        return c >= '0' && c <= '9';
    });
}

static int code_index(const string& code) {
    for (int i = 0; i<8; i++) if (code == descriptor_codes[i]) return i;
    for (int i = 0; i<22; i++) if (code == phenomenon_codes[i]) return i+8;
    return -1;
}

static bool fraction_word(const string& s) {
    static const std::regex re("[0-9]/[0-9]{1,2}SM");
    return std::regex_match(s, re);
}

static std::optional<Value> group_format(int kind, const string& text) {
    static const std::array<std::regex, 10> patterns = {
        std::regex("AUTO|COR"), std::regex("([0-9]{3}|VRB)([0-9]{2,3})(G([0-9]{2,3}))?(KT|MPS)"), std::regex("([0-9]{3})V([0-9]{3})"),
        std::regex("([MP]?)([0-9]{1,2}|[0-9]/[0-9]{1,2})SM"), std::regex("R([0-9]{2}[LCR]?)/([MP]?)([0-9]{4})(V([MP]?)([0-9]{4}))?(FT)?([UDN])?"),
        std::regex(""), std::regex("(FEW|SCT|BKN|OVC)([0-9]{3})(CB|TCU)?"), std::regex("(M?)([0-9]{2})/(M?)([0-9]{2})"),
        std::regex("([AQ])([0-9]{4})"), std::regex("NOSIG")
    };
    static const std::regex mixed("([0-9]) ([0-9])/([0-9]{1,2})SM"), vv("VV([0-9]{3})");
    Value v;
    v.raw = text;
    std::smatch m;
    auto num = [&](int i) {
        return m[i].matched?std::stoi(m[i].str()):0;
    };
    auto ch = [&](int i) {
        return m[i].length()?m[i].str()[0]:char(0);
    };
    bool ok = false;
    switch (kind) {
        case MOD:case NOSIG:ok = std::regex_match(text, m, patterns[kind]);
        break;
        case WIND:if ((ok = std::regex_match(text, m, patterns[WIND]))) {
            v.direction = m[1] == "VRB"?-1:num(1);
            v.speed = num(2);
            v.gust = m[4].matched?num(4):-1;
            v.meters_per_second = m[5] == "MPS";
        }
        break;
        case VAR:if ((ok = std::regex_match(text, m, patterns[VAR]))) {
            v.variation_from = num(1);
            v.variation_to = num(2);
        }
        break;
        case VIS:if (text == "CAVOK") {
            ok = true;
            v.visibility_kind = 1;
            v.meters = 10000;
            v.qualifier = 'P';
        } else if (digits(text, 4)) {
            ok = true;
            v.meters = std::stoi(text);
            if (v.meters == 9999) {
                v.meters = 10000;
                v.qualifier = 'P';
            }
        } else if (std::regex_match(text, m, mixed)) {
            ok = true;
            v.visibility_kind = 2;
            v.whole = num(1);
            v.numerator = num(2);
            v.denominator = num(3);
            v.mile_form = 1;
        } else if (std::regex_match(text, m, patterns[VIS])) {
            ok = true;
            v.visibility_kind = 2;
            v.qualifier = ch(1);
            string body = m[2];
            std::size_t slash = body.find('/');
            if (slash != string::npos) {
                v.numerator = std::stoi(body.substr(0, slash));
                v.denominator = std::stoi(body.substr(slash+1));
                v.mile_form = 2;
            } else v.whole = std::stoi(body);
        }
        break;
        case RVR:if ((ok = std::regex_match(text, m, patterns[RVR]))) {
            v.runway = m[1];
            v.first_qualifier = ch(2);
            v.first_reading = num(3);
            v.second_qualifier = ch(5);
            v.second_reading = m[6].matched?num(6):-1;
            v.feet = m[7].matched;
            v.trend = ch(8);
        }
        break;
        case WX:v.descriptor = -1;
        if (text == "NSW") {
            ok = true;
            v.nsw = 1;
        } else {
            string body = text;
            if (body.rfind("VC", 0) == 0) {
                v.intensity = 'V';
                body.erase(0, 2);
            } else if (!body.empty() && (body[0] == '-' || body[0] == '+')) {
                v.intensity = body[0];
                body.erase(0, 1);
            }
            ok = !body.empty() && body.size()%2 == 0;
            for (std::size_t i = 0; ok && i<body.size(); i += 2) {
                int code = code_index(body.substr(i, 2));
                if (code<0)ok = false;
                else if (i == 0 && code<8)v.descriptor = code;
                else v.phenomena.push_back(code);
            }
        }
        break;
        case CLOUD:for (int i = 5; i<8; i++)if (text == amount_codes[i]) {
            ok = true;
            v.amount = i;
        }
        if (!ok && std::regex_match(text, m, patterns[CLOUD])) {
            ok = true;
            v.amount = (int)(std::find(amount_codes.begin(), amount_codes.end(), m[1].str())-amount_codes.begin());
            v.height = num(2)*100;
            v.cloud_type = !m[3].matched?0:m[3] == "CB"?1:2;
        }
        if (!ok && std::regex_match(text, m, vv)) {
            ok = true;
            v.amount = 4;
            v.height = num(1)*100;
        }
        break;
        case TEMP:if ((ok = std::regex_match(text, m, patterns[TEMP]))) {
            v.temperature = num(2)*(ch(1)?-1:1);
            v.dew_point = num(4)*(ch(3)?-1:1);
        }
        break;
        case PRESS:if ((ok = std::regex_match(text, m, patterns[PRESS]))) {
            v.pressure_unit = ch(1);
            v.pressure_value = num(2);
        }
        break;
    }
    return ok?std::optional<Value>(v):std::nullopt;
}

static bool group_valid(int kind, const Value& v, const State& s, const Station& st, bool context) {
    switch (kind) {
        case WIND:if (v.direction<0) {
            if (v.speed<1)return false;
        } else if (v.direction>360 || v.direction%10 || ((v.direction == 0) != (v.speed == 0)))return false;
        return v.gust<0 || (v.direction != 0 && v.gust>v.speed);
        case VAR:return v.variation_from >= 10 && v.variation_from <= 360 && v.variation_from%10 == 0 && v.variation_to >= 10 && v.variation_to <= 360 && v.variation_to%10 == 0 && v.variation_from != v.variation_to && s.wind && s.wind->direction>0;
        case VIS:if (v.visibility_kind != 2)return true;
        if (!v.mile_form)return v.whole >= 1;
        return (v.denominator == 2 || v.denominator == 4 || v.denominator == 8 || v.denominator == 16) && v.numerator >= 1 && v.numerator<v.denominator && (v.mile_form != 1 || v.whole >= 1);
        case RVR:return std::any_of(st.runways.begin(), st.runways.end(), [&](const Runway& r) {
            return r.name == v.runway;
        }) && (v.second_reading<0 || v.first_reading<v.second_reading);
        case WX: {
            if (s.weather && (s.weather->size() >= 3 || (!s.weather->empty() && s.weather->front().nsw)))return false;
            if (v.nsw)return context && (!s.weather || s.weather->empty());
            int precip = 0;
            std::vector<int> seen;
            for (int code:v.phenomena) {
                if (code<8 || std::find(seen.begin(), seen.end(), code) != seen.end())return false;
                seen.push_back(code);
                if (code<17)precip++;
            }
            if (v.phenomena.empty() && v.descriptor != 5 && v.descriptor != 6)return false;
            if ((v.intensity == '-' || v.intensity == '+') && !precip)return false;
            return v.phenomena.size()<2 || precip == (int)v.phenomena.size();
        }
        case CLOUD:return !s.cloud || s.cloud->empty() || (v.amount<4 && s.cloud->back().amount<4 && v.height>s.cloud->back().height);
        case TEMP:return v.dew_point <= v.temperature;
        case PRESS:return v.pressure_unit == 'A'?(v.pressure_value >= 2500 && v.pressure_value <= 3150):(v.pressure_value >= 850 && v.pressure_value <= 1070);
        default:return true;
    }
}

static void group_accept(State& s, int kind, Value v) {
    if (kind == WIND && v.meters_per_second) {
        v.speed = knots(v.speed);
        if (v.gust >= 0)v.gust = knots(v.gust);
    }
    if (kind == PRESS) {
        v.inch = v.pressure_unit == 'A'?v.pressure_value:inhg(v.pressure_value);
        v.hectopascals = v.pressure_unit == 'Q'?v.pressure_value:hpa(v.pressure_value);
    }
    switch (kind) {
        case MOD:s.modifier = v;
        break;
        case WIND:s.wind = v;
        break;
        case VAR:s.variation = v;
        break;
        case VIS:s.visibility = v;
        if (v.visibility_kind == 1) {
            s.weather = std::vector<Value> {
            };
            s.cloud = std::vector<Value> {
            };
        }
        break;
        case RVR:s.rvr.push_back(v);
        break;
        case WX:if (!s.weather)s.weather = std::vector<Value> {
        };
        s.weather->push_back(v);
        break;
        case CLOUD:if (!s.cloud)s.cloud = std::vector<Value> {
        };
        s.cloud->push_back(v);
        break;
        case TEMP:s.temperature = v;
        break;
        case PRESS:s.pressure = v;
        break;
        case NOSIG:s.no_trend = v;
        break;
    }
}
