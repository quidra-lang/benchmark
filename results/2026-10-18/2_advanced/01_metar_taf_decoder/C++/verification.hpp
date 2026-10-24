#pragma once

static bool covers(const Report& r, int time) {
    int hour = time-time%60;
    return r.kind == "TAF" && r.time <= time && r.start <= hour && hour<r.end;
}

static const Report* choose_forecast(const std::vector<Report>& all, const string& station, int time) {
    const Report* best = nullptr;
    for (const Report& r:all)if (r.station == station && covers(r, time) && (!best || r.time >= best->time))best = &r;
    return best;
}
struct Contingency {
    std::array<std::array<I, 4>, 4> table {
    };
    I temporary_hits = 0;
    void add(int forecast, int observation, bool hit) {
        table[forecast][observation]++;
        temporary_hits += hit;
    }
    I row(int i)const {
        return std::accumulate(table[i].begin(), table[i].end(), I {
            0
        });
    }
    I column(int j)const {
        I n = 0;
        for (const auto& r:table)n += r[j];
        return n;
    }
    I total()const {
        I n = 0;
        for (int i = 0; i<4; i++)n += row(i);
        return n;
    }
    I hits()const {
        I n = 0;
        for (int i = 0; i<4; i++)n += table[i][i];
        return n;
    }
    std::pair<I, I> skill()const {
        I n = total(), e = 0;
        for (int i = 0; i<4; i++)e += row(i)*column(i);
        return {
            n*hits()-e, n*n-e
        };
    }
    std::pair<I, I> detection(int i)const {
        return {
            table[i][i], column(i)
        };
    }
    std::pair<I, I> false_alarm(int i)const {
        return {
            row(i)-table[i][i], row(i)
        };
    }
};

static int wind_strength(const Value& v) {
    return v.gust<0?v.speed:v.gust;
}
