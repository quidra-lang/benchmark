#include "tides.hpp"
static constexpr double pi = 3.141592653589793;
struct Selection {
    std::vector<int> chosen;
    std::vector<std::string> status;
    Vector speeds;
};
static Selection select(const std::vector<Constituent> &constituents, int length, double rayleigh) {
    Selection out;
    for (int i = 0; i < int(constituents.size()); ++i) {
        const Constituent &item = constituents[i];
        std::string status = "fitted";
        if (item.speed * length < 360 * rayleigh)
            status = "short";
        else
            for (int previous : out.chosen)
                if (std::abs(item.speed - constituents[previous].speed) * length < 360 * rayleigh) {
                    status = "conflict:" + constituents[previous].name;
                    break;
                }
        out.status.push_back(status);
        if (status == "fitted") {
            out.chosen.push_back(i);
            out.speeds.push_back(item.speed);
        }
    }
    return out;
}
struct Day {
    int day;
    std::vector<int> high, low;
    std::optional<double> hhw, llw, range;
};
struct Event {
    int first, last, peak, sign;
};
struct DailyMean {
    int day, filled;
    double level;
};
struct State {
    const Station *station = nullptr;
    int first = 0, last = 0;
    Selection selection;
    Model model;
    std::vector<Sample> usable;
    std::map<int, double> residuals;
    Vector hourly;
    std::vector<Extremum> waters;
    std::vector<int> high, low;
    std::vector<Day> days;
    double mhhw = 0, mllw = 0, mhw = 0, mlw = 0, mtl = 0, gt = 0;
    std::map<std::string, int> index;
    Lines cleaning, constituents, extremes, summary;
};
static std::string at(int t, const Params &p) { return datetime(60 * t, p.epoch_day); }
static std::string optional(std::optional<double> value) {
    return value ? real(*value, 3) : "none";
}
static double average(const Vector &values) {
    double sum = 0;
    for (double value : values)
        sum += value;
    return sum / values.size();
}
static void analyze(State &s, const Station &station, const Input &input) {
    const Params &p = input.params;
    s.station = &station;
    s.first = station.observations.begin()->first;
    s.last = station.observations.rbegin()->first;
    const int length = s.last - s.first;
    std::map<int, std::string> reasons;
    int numeric = 0, na = 0, absent = 0, flat_count = 0;
    for (int t = s.first; t <= s.last; ++t) {
        auto entry = station.observations.find(t);
        if (entry == station.observations.end()) {
            reasons[t] = "absent";
            ++absent;
        } else if (!entry->second) {
            reasons[t] = "na";
            ++na;
        } else
            ++numeric;
    }
    const std::vector<Flat> flats = flat_runs(station.observations, s.first, s.last, p.flat_run);
    for (Flat flat : flats)
        for (int t = flat.first + 1; t <= flat.last; ++t) {
            reasons[t] = "flat";
            ++flat_count;
        }
    std::vector<Sample> candidates;
    for (const auto &entry : station.observations)
        if (entry.second && !reasons.count(entry.first))
            candidates.push_back({entry.first, double(*entry.second) / 1000});
    s.selection = select(input.constituents, length, p.rayleigh);
    const Model preliminary = fit(candidates, s.selection.speeds);
    std::map<int, double> pre_residuals;
    double pre_ss = 0;
    for (Sample sample : candidates) {
        double value = sample.value - prediction(preliminary, sample.time);
        pre_residuals[sample.time] = value;
        pre_ss += value * value;
    }
    int tested = 0;
    const std::vector<Spike> found_spikes = spikes(pre_residuals, p, tested);
    for (Spike spike : found_spikes)
        reasons[spike.time] = "spike";
    for (Sample sample : candidates)
        if (!reasons.count(sample.time))
            s.usable.push_back(sample);
    line(s.cleaning, "station=", station.code, " name=", station.name);
    line(s.cleaning, "span start=", at(s.first, p), " end=", at(s.last, p), " hours=", length + 1,
         " record_length=", length);
    line(s.cleaning, "counts rows=", station.observations.size(), " numeric=", numeric, " na=", na,
         " absent=", absent, " flat=", flat_count, " spikes=", found_spikes.size(),
         " usable=", s.usable.size());
    for (Flat flat : flats)
        line(s.cleaning, "flat start=", at(flat.first, p), " end=", at(flat.last, p),
             " value=", real(double(flat.milli) / 1000, 3), " removed=", flat.last - flat.first);
    line(s.cleaning, "spike_test window=", p.spike_window, " candidates=", candidates.size(),
         " tested=", tested, " prefit_rms=", real(std::sqrt(pre_ss / candidates.size()), 4));
    for (Spike spike : found_spikes)
        line(s.cleaning, "spike time=", at(spike.time, p),
             " value=", real(double(*station.observations.at(spike.time)) / 1000, 3),
             " residual=", real(spike.residual, 4), " median=", real(spike.median, 4),
             " mad=", real(spike.mad, 4), " limit=", real(spike.limit, 4));
    for (Gap gap : gaps(reasons, s.first, s.last))
        line(s.cleaning, "gap start=", at(gap.first, p), " end=", at(gap.last, p),
             " hours=", gap.last - gap.first + 1, " cause=", gap.cause);
    s.model = fit(s.usable, s.selection.speeds);
    int unknowns = int(s.model.coefficients.size()), n = int(s.usable.size()), dof = n - unknowns;
    double ss = 0, max_abs = 0, mean = 0;
    for (Sample sample : s.usable) {
        double residual = sample.value - prediction(s.model, sample.time);
        s.residuals[sample.time] = residual;
        ss += residual * residual;
        max_abs = std::max(max_abs, std::abs(residual));
        mean += sample.value;
    }
    mean /= n;
    double variance = ss / dof, observed_ss = 0, lag_numerator = 0, lag_denominator = 0;
    for (Sample sample : s.usable) {
        double centered = sample.value - mean;
        observed_ss += centered * centered;
        auto following = s.residuals.find(sample.time + 1);
        if (following != s.residuals.end()) {
            double residual = s.residuals.at(sample.time);
            lag_numerator += residual * following->second;
            lag_denominator += residual * residual;
        }
    }
    for (int k = 0; k < int(s.selection.chosen.size()); ++k)
        s.index[input.constituents[s.selection.chosen[k]].name] = k;
    int fitted_index = 0;
    for (int i = 0; i < int(input.constituents.size()); ++i) {
        const Constituent &item = input.constituents[i];
        if (s.selection.status[i] != "fitted") {
            line(s.constituents, station.code, ",", item.name, ",", real(item.speed, 7), ",",
                 s.selection.status[i], ",,,,,,");
            continue;
        }
        int k = fitted_index++, ia = 2 * k + 1, ib = 2 * k + 2;
        double a = s.model.coefficients[ia], b = s.model.coefficients[ib],
               amplitude = s.model.amplitudes[k], va = variance * s.model.inverse[ia][ia],
               vb = variance * s.model.inverse[ib][ib], cab = variance * s.model.inverse[ia][ib],
               amplitude_error = std::sqrt(a * a * va + b * b * vb + 2 * a * b * cab) / amplitude,
               phase_error = std::sqrt(b * b * va + a * a * vb - 2 * a * b * cab) /
                             (amplitude * amplitude) * 180 / pi,
               ratio = amplitude / amplitude_error, snr = ratio * ratio;
        line(s.constituents, station.code, ",", item.name, ",", real(item.speed, 7), ",fitted,",
             real(amplitude, 4), ",", real(s.model.phases[k], 2), ",", real(amplitude_error, 4),
             ",", real(phase_error, 2), ",", real(snr, 1), ",", snr >= p.snr ? "yes" : "no");
    }
    for (int i = 0; i <= p.length; ++i)
        s.hourly.push_back(prediction(s.model, p.start + i));
    s.waters = extrema(s.model, p.start, p.length, p.grid);
    int raw = int(s.waters.size());
    while (s.waters.size() >= 2) {
        int first = 0;
        double minimum = std::abs(s.waters[0].height - s.waters[1].height);
        for (int i = 1; i + 1 < int(s.waters.size()); ++i) {
            double difference = std::abs(s.waters[i].height - s.waters[i + 1].height);
            if (difference < minimum) {
                minimum = difference;
                first = i;
            }
        }
        if (minimum >= p.min_range)
            break;
        s.waters.erase(s.waters.begin() + first, s.waters.begin() + first + 2);
    }
    for (Extremum &water : s.waters)
        water.minute = int(std::floor(water.mu + 0.5));
    for (int day = 0; day < p.length / 24; ++day)
        s.days.push_back({p.start / 24 + day, {}, {}, {}, {}, {}});
    for (int i = 0; i < int(s.waters.size()); ++i) {
        Extremum &water = s.waters[i];
        int day = water.minute / 1440 - p.start / 24;
        Day &record = s.days[day];
        if (water.high) {
            s.high.push_back(i);
            record.high.push_back(i);
        } else {
            s.low.push_back(i);
            record.low.push_back(i);
        }
    }
    for (Day &day : s.days) {
        if (!day.high.empty()) {
            int best = day.high[0];
            for (int i : day.high)
                if (s.waters[i].height > s.waters[best].height)
                    best = i;
            day.hhw = s.waters[best].height;
            for (int i : day.high)
                s.waters[i].label = i == best ? "HHW" : "LHW";
        }
        if (!day.low.empty()) {
            int best = day.low[0];
            for (int i : day.low)
                if (s.waters[i].height < s.waters[best].height)
                    best = i;
            day.llw = s.waters[best].height;
            for (int i : day.low)
                s.waters[i].label = i == best ? "LLW" : "HLW";
        }
        if (day.hhw && day.llw)
            day.range = *day.hhw - *day.llw;
    }
    line(s.extremes, "station=", station.code, " extremes=", s.waters.size(), " raw=", raw,
         " removed=", raw - int(s.waters.size()));
    for (int i = 0; i < int(s.waters.size()); ++i) {
        const Extremum &water = s.waters[i];
        line(s.extremes, datetime(water.minute, p.epoch_day), " ", water.label, " ",
             real(water.height, 3),
             " change=", i ? real(water.height - s.waters[i - 1].height, 3) : "none");
    }
    for (const Day &day : s.days)
        line(s.extremes, "day date=", date(day.day, p.epoch_day), " high_waters=", day.high.size(),
             " low_waters=", day.low.size(), " hhw=", optional(day.hhw), " llw=", optional(day.llw),
             " range=", optional(day.range));
    Vector hhws, llws, highs, lows;
    for (const Day &day : s.days) {
        if (day.hhw)
            hhws.push_back(*day.hhw);
        if (day.llw)
            llws.push_back(*day.llw);
    }
    for (int i : s.high)
        highs.push_back(s.waters[i].height);
    for (int i : s.low)
        lows.push_back(s.waters[i].height);
    s.mhhw = average(hhws);
    s.mllw = average(llws);
    s.mhw = average(highs);
    s.mlw = average(lows);
    s.mtl = (s.mhw + s.mlw) / 2;
    s.gt = s.mhhw - s.mllw;
    auto amplitude = [&](const std::string &name) { return s.model.amplitudes[s.index.at(name)]; };
    auto phase = [&](const std::string &name) { return s.model.phases[s.index.at(name)]; };
    double form = (amplitude("K1") + amplitude("O1")) / (amplitude("M2") + amplitude("S2")),
           spring = 2 * (amplitude("M2") + amplitude("S2")),
           neap = 2 * (amplitude("M2") - amplitude("S2")), sum_amplitudes = 0;
    for (double value : s.model.amplitudes)
        sum_amplitudes += value;
    Vector rise, fall;
    for (int i = 1; i < int(s.waters.size()); ++i) {
        const Extremum &previous = s.waters[i - 1], &water = s.waters[i];
        if (!previous.high && water.high)
            rise.push_back(water.minute - previous.minute);
        if (previous.high && !water.high)
            fall.push_back(water.minute - previous.minute);
    }
    double relative = 2 * phase("M2") - phase("M4");
    while (relative < 0)
        relative += 360;
    while (relative >= 360)
        relative -= 360;
    int highest = s.high[0], lowest = s.low[0], widest = -1, narrowest = -1;
    for (int i : s.high)
        if (s.waters[i].height > s.waters[highest].height)
            highest = i;
    for (int i : s.low)
        if (s.waters[i].height < s.waters[lowest].height)
            lowest = i;
    for (int i = 0; i < int(s.days.size()); ++i)
        if (s.days[i].range) {
            if (widest < 0 || *s.days[i].range > *s.days[widest].range)
                widest = i;
            if (narrowest < 0 || *s.days[i].range < *s.days[narrowest].range)
                narrowest = i;
        }
    int above = 0, below = 0;
    for (double value : s.hourly) {
        above += value > s.mhhw;
        below += value < s.mllw;
    }
    int mid = s.first + length / 2;
    std::vector<Sample> training, test_data;
    for (Sample sample : s.usable)
        (sample.time <= mid ? training : test_data).push_back(sample);
    Selection validation_selection =
        select(input.constituents, training.back().time - training.front().time, p.rayleigh);
    Model validation = fit(training, validation_selection.speeds);
    double test_ss = 0, in_sample = 0, test_mean = 0, test_variance = 0;
    for (Sample sample : test_data)
        test_mean += sample.value;
    test_mean /= test_data.size();
    for (Sample sample : test_data) {
        double residual = sample.value - prediction(validation, sample.time);
        test_ss += residual * residual;
        double fitted_residual = s.residuals.at(sample.time);
        in_sample += fitted_residual * fitted_residual;
        double centered = sample.value - test_mean;
        test_variance += centered * centered;
    }
    line(s.summary, "[station ", station.code, "] ", station.name);
    line(s.summary, "record first=", at(s.first, p), " last=", at(s.last, p), " length=", length,
         " usable=", n);
    line(s.summary, "fit constituents=", s.selection.chosen.size(), " unknowns=", unknowns,
         " dof=", dof, " mean_level=", real(s.model.coefficients[0], 4));
    line(s.summary, "residual rms=", real(std::sqrt(ss / n), 4), " max_abs=", real(max_abs, 4),
         " explained_percent=", real(100 * (1 - ss / observed_ss), 4),
         " lag1_autocorrelation=", real(lag_numerator / lag_denominator, 4));
    std::vector<int> top;
    for (Sample sample : s.usable)
        top.push_back(sample.time);
    std::sort(top.begin(), top.end(), [&](int a, int b) {
        double x = std::abs(s.residuals.at(a)), y = std::abs(s.residuals.at(b));
        return x != y ? x > y : a < b;
    });
    for (int i = 0; i < p.top; ++i) {
        int t = top[i];
        line(s.summary, "top_residual rank=", i + 1, " time=", at(t, p),
             " observed=", real(double(*station.observations.at(t)) / 1000, 3),
             " fitted=", real(prediction(s.model, t), 4), " residual=", real(s.residuals.at(t), 4));
    }
    line(s.summary, "validation split=", at(mid, p), " train=", training.size(),
         " test=", test_data.size(), " constituents=", validation_selection.chosen.size(),
         " rms=", real(std::sqrt(test_ss / test_data.size()), 4),
         " in_sample_rms=", real(std::sqrt(in_sample / test_data.size()), 4),
         " skill=", real(1 - test_ss / test_variance, 4));
    line(s.summary, "form_number=", real(form, 4), " type=",
         form < 0.25  ? "semidiurnal"
         : form < 1.5 ? "mixed_semidiurnal"
         : form < 3   ? "mixed_diurnal"
                      : "diurnal");
    line(s.summary, "ranges spring=", real(spring, 3), " neap=", real(neap, 3),
         " mn=", real(s.mhw - s.mlw, 3), " gt=", real(s.gt, 3));
    line(s.summary, "asymmetry rise_minutes=", real(average(rise), 1),
         " fall_minutes=", real(average(fall), 1),
         " m4_m2_ratio=", real(amplitude("M4") / amplitude("M2"), 4),
         " relative_phase=", real(relative, 2), " dominance=", relative < 180 ? "flood" : "ebb");
    line(s.summary, "datums mhhw=", real(s.mhhw, 3), " mhw=", real(s.mhw, 3),
         " mtl=", real(s.mtl, 3), " dtl=", real((s.mhhw + s.mllw) / 2, 3), " mlw=", real(s.mlw, 3),
         " mllw=", real(s.mllw, 3));
    line(s.summary, "bounds hat=", real(s.model.coefficients[0] + sum_amplitudes, 3),
         " lat=", real(s.model.coefficients[0] - sum_amplitudes, 3));
    line(s.summary, "window high_waters=", s.high.size(), " low_waters=", s.low.size(),
         " highest=", real(s.waters[highest].height, 3),
         " highest_time=", datetime(s.waters[highest].minute, p.epoch_day),
         " lowest=", real(s.waters[lowest].height, 3),
         " lowest_time=", datetime(s.waters[lowest].minute, p.epoch_day));
    line(s.summary, "daily_range widest=", real(*s.days[widest].range, 3),
         " widest_date=", date(s.days[widest].day, p.epoch_day),
         " narrowest=", real(*s.days[narrowest].range, 3),
         " narrowest_date=", date(s.days[narrowest].day, p.epoch_day));
    line(s.summary, "exceedance above_mhhw=", real(100.0 * above / (p.length + 1), 2),
         " below_mllw=", real(100.0 * below / (p.length + 1), 2));
    double dw = s.model.speeds[s.index.at("S2")] - s.model.speeds[s.index.at("M2")],
           dg = phase("S2") - phase("M2"), q1 = (dw * p.start - dg) / 180,
           q2 = (dw * (p.start + p.length) - dg) / 180;
    int qfirst = int(std::floor(std::min(q1, q2))) - 1,
        qlast = int(std::ceil(std::max(q1, q2))) + 1;
    for (int q = qfirst; q <= qlast; ++q) {
        double t = (dg + 180 * q) / dw;
        if (p.start <= t && t <= p.start + p.length)
            line(s.summary, q % 2 == 0 ? "spring" : "neap",
                 " time=", datetime(int(std::floor(t * 60 + 0.5)), p.epoch_day));
    }
    std::vector<Event> events;
    auto sign = [&](int t) {
        double residual = s.residuals.at(t);
        return residual > p.surge ? 1 : residual < -p.surge ? -1 : 0;
    };
    int position = 0;
    while (position < n) {
        int t = s.usable[position].time, event_sign = sign(t);
        if (!event_sign) {
            ++position;
            continue;
        }
        int first = t, last = t, peak = t;
        while (position + 1 < n && s.usable[position + 1].time == last + 1 &&
               sign(s.usable[position + 1].time) == event_sign) {
            ++position;
            last = s.usable[position].time;
            if ((event_sign > 0 && s.residuals.at(last) > s.residuals.at(peak)) ||
                (event_sign < 0 && s.residuals.at(last) < s.residuals.at(peak)))
                peak = last;
        }
        if (last - first + 1 >= p.surge_hours)
            events.push_back({first, last, peak, event_sign});
        ++position;
    }
    line(s.summary, "surges count=", events.size(), " threshold=", real(p.surge, 3),
         " min_hours=", p.surge_hours);
    for (Event event : events)
        line(s.summary, "surge type=", event.sign > 0 ? "positive" : "negative",
             " start=", at(event.first, p), " end=", at(event.last, p),
             " hours=", event.last - event.first + 1, " peak=", real(s.residuals.at(event.peak), 4),
             " peak_time=", at(event.peak, p));
    const std::array<int, 20> weights{0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1};
    std::vector<DailyMean> means;
    for (int day = s.first / 24; day <= s.last / 24; ++day) {
        int noon = 24 * day + 12;
        if (noon - 19 < s.first || noon + 19 > s.last)
            continue;
        double sum = 0;
        int filled = 0;
        for (int j = -19; j <= 19; ++j) {
            int t = noon + j;
            bool usable = s.residuals.count(t) > 0;
            double value =
                usable ? double(*station.observations.at(t)) / 1000 : prediction(s.model, t);
            sum += weights[std::abs(j)] * value;
            filled += !usable;
        }
        means.push_back({day, filled, sum / 30});
    }
    Vector x, levels;
    int maximum = 0, minimum = 0;
    for (int i = 0; i < int(means.size()); ++i) {
        x.push_back(means[i].day - means[0].day);
        levels.push_back(means[i].level);
        if (means[i].level > means[maximum].level)
            maximum = i;
        if (means[i].level < means[minimum].level)
            minimum = i;
    }
    double xm = average(x), vm = average(levels), numerator = 0, denominator = 0;
    for (int i = 0; i < int(means.size()); ++i) {
        double dx = x[i] - xm;
        numerator += dx * (levels[i] - vm);
        denominator += dx * dx;
    }
    line(s.summary, "daily_mean days=", means.size(), " average=", real(vm, 4),
         " slope_mm_per_day=", real(1000 * (numerator / denominator), 3),
         " max=", real(means[maximum].level, 4),
         " max_date=", date(means[maximum].day, p.epoch_day),
         " min=", real(means[minimum].level, 4),
         " min_date=", date(means[minimum].day, p.epoch_day));
    for (DailyMean mean : means)
        line(s.summary, "daily_mean date=", date(mean.day, p.epoch_day),
             " level=", real(mean.level, 4), " filled=", mean.filled);
}
static double lag(const State &station, const State &reference, bool high) {
    const std::vector<int> &items = high ? station.high : station.low,
                           &ref = high ? reference.high : reference.low;
    double sum = 0;
    for (int i : items) {
        int minute = station.waters[i].minute, best = ref[0];
        for (int j : ref) {
            int difference = std::abs(minute - reference.waters[j].minute),
                previous = std::abs(minute - reference.waters[best].minute);
            if (difference < previous ||
                (difference == previous &&
                 reference.waters[j].minute < reference.waters[best].minute))
                best = j;
        }
        sum += minute - reference.waters[best].minute;
    }
    return sum / items.size();
}
struct Correlation {
    double value;
    int pairs;
};
static Correlation correlation(const State &a, const State &b, int lag) {
    Vector x, y;
    for (const auto &entry : a.residuals) {
        auto other = b.residuals.find(entry.first + lag);
        if (other != b.residuals.end()) {
            x.push_back(entry.second);
            y.push_back(other->second);
        }
    }
    double xm = average(x), ym = average(y), cross = 0, xx = 0, yy = 0;
    for (int i = 0; i < int(x.size()); ++i) {
        double dx = x[i] - xm, dy = y[i] - ym;
        cross += dx * dy;
        xx += dx * dx;
        yy += dy * dy;
    }
    return {cross / std::sqrt(xx * yy), int(x.size())};
}
int main() {
    const Input input = read_inputs();
    const Params &p = input.params;
    std::vector<State> states(input.stations.size());
    Lines cleaning,
        constituents{
            "station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant"},
        predictions, waters, summary;
    std::string header = "time";
    for (const Station &station : input.stations)
        header += "," + station.code;
    predictions.push_back(header);
    for (int i = 0; i < int(states.size()); ++i) {
        analyze(states[i], input.stations[i], input);
        cleaning.insert(cleaning.end(), states[i].cleaning.begin(), states[i].cleaning.end());
        constituents.insert(constituents.end(), states[i].constituents.begin(),
                            states[i].constituents.end());
        waters.insert(waters.end(), states[i].extremes.begin(), states[i].extremes.end());
        summary.insert(summary.end(), states[i].summary.begin(), states[i].summary.end());
    }
    for (int i = 0; i <= p.length; ++i) {
        std::string row = at(p.start + i, p);
        for (const State &state : states)
            row += "," + real(state.hourly[i], 3);
        predictions.push_back(row);
    }
    const State &reference = *std::find_if(states.begin(), states.end(), [&](const State &state) {
        return state.station->code == p.reference;
    });
    line(summary, "[comparison] reference=", p.reference);
    for (const State &state : states) {
        if (state.station->code == p.reference)
            continue;
        line(summary, state.station->code,
             " tide hw_lag_min=", real(lag(state, reference, true), 1),
             " lw_lag_min=", real(lag(state, reference, false), 1),
             " range_ratio=", real(state.gt / reference.gt, 4),
             " mtl_diff=", real(state.mtl - reference.mtl, 3));
        for (const std::string &name : {"M2", "S2", "K1", "O1"}) {
            int k = state.index.at(name), kr = reference.index.at(name);
            double phase = state.model.phases[k] - reference.model.phases[kr];
            if (phase > 180)
                phase -= 360;
            if (phase <= -180)
                phase += 360;
            line(summary, state.station->code, " ", name, " amplitude_ratio=",
                 real(state.model.amplitudes[k] / reference.model.amplitudes[kr], 4),
                 " phase_diff=", real(phase, 2),
                 " time_lag_min=", real(phase / state.model.speeds[k] * 60, 1));
        }
    }
    line(summary, "[correlation] max_lag=", p.lag);
    for (int a = 0; a < int(states.size()); ++a)
        for (int b = a + 1; b < int(states.size()); ++b) {
            int best_lag = -p.lag;
            Correlation best = correlation(states[a], states[b], best_lag),
                        zero = correlation(states[a], states[b], 0);
            for (int lag = -p.lag + 1; lag <= p.lag; ++lag) {
                Correlation value = correlation(states[a], states[b], lag);
                if (value.value > best.value ||
                    (value.value == best.value &&
                     (std::abs(lag) < std::abs(best_lag) ||
                      (std::abs(lag) == std::abs(best_lag) && lag < best_lag)))) {
                    best = value;
                    best_lag = lag;
                }
            }
            line(summary, states[a].station->code, "-", states[b].station->code,
                 " lag0=", real(zero.value, 4), " best_lag=", best_lag,
                 " best=", real(best.value, 4), " pairs=", best.pairs);
        }
    const State &plotted = *std::find_if(states.begin(), states.end(), [&](const State &state) {
        return state.station->code == p.plot;
    });
    line(summary, "[plot] station=", p.plot, " start=", at(p.start, p), " hours=", p.plot_hours,
         " step_cm=", p.plot_step);
    int rows = (p.plot_top - p.plot_bottom) / p.plot_step + 1;
    Lines cells(rows, std::string(p.plot_hours, ' '));
    int zero_row =
        int(std::floor((p.plot_top - 100 * plotted.model.coefficients[0]) / p.plot_step + 0.5));
    if (zero_row >= 0 && zero_row < rows)
        std::fill(cells[zero_row].begin(), cells[zero_row].end(), '-');
    std::string marks(p.plot_hours, ' ');
    for (const Extremum &water : plotted.waters) {
        int column = (water.minute - 60 * p.start + 30) / 60;
        if (column >= 0 && column < p.plot_hours)
            marks[column] = water.high ? 'H' : 'L';
    }
    for (int column = 0; column < p.plot_hours; ++column) {
        int row = int(std::floor((p.plot_top - 100 * plotted.hourly[column]) / p.plot_step + 0.5));
        if (row < 0)
            cells[0][column] = '^';
        else if (row >= rows)
            cells[rows - 1][column] = 'v';
        else
            cells[row][column] = marks[column] == ' ' ? '*' : marks[column];
    }
    Vector heights;
    for (int row = 0; row < rows; ++row)
        heights.push_back(double(p.plot_top - row * p.plot_step) / 100);
    std::string axis;
    for (int column = 0; column < p.plot_hours; ++column)
        axis += column % 6 == 0 ? '+' : '-';
    Lines plot = plot_lines(heights, cells, axis);
    summary.insert(summary.end(), plot.begin(), plot.end());
    std::filesystem::create_directories("output");
    save("cleaning.txt", cleaning);
    save("constituents.csv", constituents);
    save("predictions.csv", predictions);
    save("extremes.txt", waters);
    save("summary.txt", summary);
}
