#include "tides.h"
static const double pi = 3.141592653589793;
typedef struct {
    int chosen[30], count;
    char *status[30];
    double speeds[30];
} Selection;
static Selection select_constituents(const Input *input, int length, double rayleigh) {
    Selection out = {0};
    for (int i = 0; i < input->constituent_count; ++i) {
        Constituent item = input->constituents[i];
        char *status = "fitted";
        if (item.speed * length < 360 * rayleigh)
            status = "short";
        else
            for (int k = 0; k < out.count; ++k) {
                int previous = out.chosen[k];
                if (fabs(item.speed - input->constituents[previous].speed) * length <
                    360 * rayleigh) {
                    status = format("conflict:%s", input->constituents[previous].name);
                    break;
                }
            }
        out.status[i] = status;
        if (strcmp(status, "fitted") == 0) {
            out.chosen[out.count] = i;
            out.speeds[out.count++] = item.speed;
        }
    }
    return out;
}
typedef struct {
    int day, high_count, low_count, best_high, best_low;
    double hhw, llw, range;
    bool has_range;
} Day;
typedef struct {
    int first, last, peak, sign;
} Event;
typedef struct {
    int day, filled;
    double level;
} DailyMean;
typedef struct {
    const Station *station;
    int first, last;
    Selection selection;
    Model *model;
    Sample *usable;
    int usable_count;
    double residuals[10001];
    bool used[10001];
    double *hourly;
    Extrema waters;
    int *high, *low, high_count, low_count;
    Day *days;
    int day_count;
    double mhhw, mllw, mhw, mlw, mtl, gt;
    Lines cleaning, constituents, extremes, summary;
} State;
static char *at(int time, const Params *p) { return datetime(60 * time, p->epoch_day); }
static double average(const double *values, int count) {
    double sum = 0;
    for (int i = 0; i < count; ++i)
        sum += values[i];
    return sum / count;
}
static int model_index(const State *state, const Input *input, const char *name) {
    for (int k = 0; k < state->selection.count; ++k)
        if (strcmp(input->constituents[state->selection.chosen[k]].name, name) == 0)
            return k;
    return -1;
}
static double amplitude(const State *state, const Input *input, const char *name) {
    return state->model->amplitudes[model_index(state, input, name)];
}
static double phase(const State *state, const Input *input, const char *name) {
    return state->model->phases[model_index(state, input, name)];
}
static const State *top_state;
static int residual_order(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    double ax = fabs(top_state->residuals[x]), ay = fabs(top_state->residuals[y]);
    return ax != ay ? (ax > ay ? -1 : 1) : x - y;
}
static int event_sign(const State *state, int time, const Params *p) {
    double residual = state->residuals[time];
    return residual > p->surge ? 1 : residual < -p->surge ? -1 : 0;
}
static void analyze(State *s, const Station *station, const Input *input) {
    const Params *p = &input->params;
    s->station = station;
    s->first = station->first;
    s->last = station->last;
    int length = s->last - s->first, *reasons = allocate(10001, sizeof(int)), numeric = 0, na = 0,
        absent = 0, flat_count = 0;
    for (int t = s->first; t <= s->last; ++t) {
        Observation entry = station->observations[t];
        if (!entry.present) {
            reasons[t] = 1;
            ++absent;
        } else if (!entry.numeric) {
            reasons[t] = 2;
            ++na;
        } else
            ++numeric;
    }
    Flats flats = flat_runs(station->observations, s->first, s->last, p->flat_run);
    for (int i = 0; i < flats.count; ++i)
        for (int t = flats.data[i].first + 1; t <= flats.data[i].last; ++t) {
            reasons[t] = 3;
            ++flat_count;
        }
    Sample *candidates = allocate((size_t)length + 1, sizeof(Sample));
    int candidate_count = 0;
    for (int t = s->first; t <= s->last; ++t)
        if (station->observations[t].numeric && !reasons[t])
            candidates[candidate_count++] =
                (Sample){t, (double)station->observations[t].milli / 1000};
    s->selection = select_constituents(input, length, p->rayleigh);
    Model *preliminary = fit(candidates, candidate_count, s->selection.speeds, s->selection.count);
    Sample *pre_residuals = allocate((size_t)candidate_count, sizeof(Sample));
    double pre_ss = 0;
    for (int i = 0; i < candidate_count; ++i) {
        Sample sample = candidates[i];
        double value = sample.value - prediction(preliminary, sample.time);
        pre_residuals[i] = (Sample){sample.time, value};
        pre_ss += value * value;
    }
    Spikes found_spikes = spikes(pre_residuals, candidate_count, p);
    for (int i = 0; i < found_spikes.count; ++i)
        reasons[found_spikes.data[i].time] = 4;
    s->usable = allocate((size_t)candidate_count, sizeof(Sample));
    for (int i = 0; i < candidate_count; ++i)
        if (!reasons[candidates[i].time]) {
            s->usable[s->usable_count++] = candidates[i];
            s->used[candidates[i].time] = true;
        }
    line(&s->cleaning, "station=%s name=%s", station->code, station->name);
    line(&s->cleaning, "span start=%s end=%s hours=%d record_length=%d", at(s->first, p),
         at(s->last, p), length + 1, length);
    line(&s->cleaning, "counts rows=%d numeric=%d na=%d absent=%d flat=%d spikes=%d usable=%d",
         station->rows, numeric, na, absent, flat_count, found_spikes.count, s->usable_count);
    for (int i = 0; i < flats.count; ++i) {
        Flat flat = flats.data[i];
        line(&s->cleaning, "flat start=%s end=%s value=%s removed=%d", at(flat.first, p),
             at(flat.last, p), real((double)flat.milli / 1000, 3), flat.last - flat.first);
    }
    line(&s->cleaning, "spike_test window=%d candidates=%d tested=%d prefit_rms=%s",
         p->spike_window, candidate_count, found_spikes.tested,
         real(sqrt(pre_ss / candidate_count), 4));
    for (int i = 0; i < found_spikes.count; ++i) {
        Spike spike = found_spikes.data[i];
        line(&s->cleaning, "spike time=%s value=%s residual=%s median=%s mad=%s limit=%s",
             at(spike.time, p), real((double)station->observations[spike.time].milli / 1000, 3),
             real(spike.residual, 4), real(spike.median, 4), real(spike.mad, 4),
             real(spike.limit, 4));
    }
    Gaps found_gaps = gaps(reasons, s->first, s->last);
    const char *causes[6] = {"", "absent", "na", "flat", "spike", "mixed"};
    for (int i = 0; i < found_gaps.count; ++i) {
        Gap gap = found_gaps.data[i];
        line(&s->cleaning, "gap start=%s end=%s hours=%d cause=%s", at(gap.first, p),
             at(gap.last, p), gap.last - gap.first + 1, causes[gap.cause]);
    }
    s->model = fit(s->usable, s->usable_count, s->selection.speeds, s->selection.count);
    int unknowns = s->model->size, n = s->usable_count, dof = n - unknowns;
    double ss = 0, max_abs = 0, mean = 0;
    for (int i = 0; i < n; ++i) {
        Sample sample = s->usable[i];
        double residual = sample.value - prediction(s->model, sample.time);
        s->residuals[sample.time] = residual;
        ss += residual * residual;
        if (fabs(residual) > max_abs)
            max_abs = fabs(residual);
        mean += sample.value;
    }
    mean /= n;
    double variance = ss / dof, observed_ss = 0, lag_numerator = 0, lag_denominator = 0;
    for (int i = 0; i < n; ++i) {
        Sample sample = s->usable[i];
        double centered = sample.value - mean;
        observed_ss += centered * centered;
        if (sample.time < s->last && s->used[sample.time + 1]) {
            double residual = s->residuals[sample.time];
            lag_numerator += residual * s->residuals[sample.time + 1];
            lag_denominator += residual * residual;
        }
    }
    int fitted_index = 0;
    for (int i = 0; i < input->constituent_count; ++i) {
        Constituent item = input->constituents[i];
        if (strcmp(s->selection.status[i], "fitted") != 0) {
            line(&s->constituents, "%s,%s,%s,%s,,,,,,", station->code, item.name,
                 real(item.speed, 7), s->selection.status[i]);
            continue;
        }
        int k = fitted_index++, ia = 2 * k + 1, ib = 2 * k + 2;
        double a = s->model->coefficients[ia], b = s->model->coefficients[ib],
               amp = s->model->amplitudes[k], va = variance * s->model->inverse[ia][ia],
               vb = variance * s->model->inverse[ib][ib],
               cab = variance * s->model->inverse[ia][ib],
               amplitude_error = sqrt(a * a * va + b * b * vb + 2 * a * b * cab) / amp,
               phase_error =
                   sqrt(b * b * va + a * a * vb - 2 * a * b * cab) / (amp * amp) * 180 / pi,
               ratio = amp / amplitude_error, snr = ratio * ratio;
        line(&s->constituents, "%s,%s,%s,fitted,%s,%s,%s,%s,%s,%s", station->code, item.name,
             real(item.speed, 7), real(amp, 4), real(s->model->phases[k], 2),
             real(amplitude_error, 4), real(phase_error, 2), real(snr, 1),
             snr >= p->snr ? "yes" : "no");
    }
    s->hourly = allocate((size_t)p->length + 1, sizeof(double));
    for (int i = 0; i <= p->length; ++i)
        s->hourly[i] = prediction(s->model, p->start + i);
    s->waters = extrema(s->model, p->start, p->length, p->grid);
    int raw = s->waters.count;
    while (s->waters.count >= 2) {
        int first = 0;
        double minimum = fabs(s->waters.data[0].height - s->waters.data[1].height);
        for (int i = 1; i + 1 < s->waters.count; ++i) {
            double difference = fabs(s->waters.data[i].height - s->waters.data[i + 1].height);
            if (difference < minimum) {
                minimum = difference;
                first = i;
            }
        }
        if (minimum >= p->min_range)
            break;
        memmove(s->waters.data + first, s->waters.data + first + 2,
                (size_t)(s->waters.count - first - 2) * sizeof(Extremum));
        s->waters.count -= 2;
    }
    s->day_count = p->length / 24;
    s->days = allocate((size_t)s->day_count, sizeof(Day));
    for (int i = 0; i < s->day_count; ++i) {
        s->days[i].day = p->start / 24 + i;
        s->days[i].best_high = s->days[i].best_low = -1;
    }
    s->high = allocate((size_t)s->waters.count, sizeof(int));
    s->low = allocate((size_t)s->waters.count, sizeof(int));
    for (int i = 0; i < s->waters.count; ++i) {
        Extremum *water = &s->waters.data[i];
        water->minute = (int)floor(water->mu + 0.5);
        Day *day = &s->days[water->minute / 1440 - p->start / 24];
        if (water->high) {
            s->high[s->high_count++] = i;
            ++day->high_count;
            if (day->best_high < 0 || water->height > s->waters.data[day->best_high].height)
                day->best_high = i;
        } else {
            s->low[s->low_count++] = i;
            ++day->low_count;
            if (day->best_low < 0 || water->height < s->waters.data[day->best_low].height)
                day->best_low = i;
        }
    }
    for (int i = 0; i < s->day_count; ++i) {
        Day *day = &s->days[i];
        if (day->high_count)
            day->hhw = s->waters.data[day->best_high].height;
        if (day->low_count)
            day->llw = s->waters.data[day->best_low].height;
        if (day->high_count && day->low_count) {
            day->has_range = true;
            day->range = day->hhw - day->llw;
        }
    }
    for (int i = 0; i < s->waters.count; ++i) {
        Extremum *water = &s->waters.data[i];
        Day *day = &s->days[water->minute / 1440 - p->start / 24];
        water->label = water->high ? (i == day->best_high ? 0 : 1) : (i == day->best_low ? 3 : 2);
    }
    line(&s->extremes, "station=%s extremes=%d raw=%d removed=%d", station->code, s->waters.count,
         raw, raw - s->waters.count);
    const char *labels[4] = {"HHW", "LHW", "HLW", "LLW"};
    for (int i = 0; i < s->waters.count; ++i) {
        Extremum water = s->waters.data[i];
        line(&s->extremes, "%s %s %s change=%s", datetime(water.minute, p->epoch_day),
             labels[water.label], real(water.height, 3),
             i ? real(water.height - s->waters.data[i - 1].height, 3) : "none");
    }
    for (int i = 0; i < s->day_count; ++i) {
        Day day = s->days[i];
        line(&s->extremes, "day date=%s high_waters=%d low_waters=%d hhw=%s llw=%s range=%s",
             date(day.day, p->epoch_day), day.high_count, day.low_count,
             day.high_count ? real(day.hhw, 3) : "none", day.low_count ? real(day.llw, 3) : "none",
             day.has_range ? real(day.range, 3) : "none");
    }
    double hhws[100], llws[100], *highs = allocate((size_t)s->high_count, sizeof(double)),
                                 *lows = allocate((size_t)s->low_count, sizeof(double));
    int hhw_count = 0, llw_count = 0;
    for (int i = 0; i < s->day_count; ++i) {
        Day day = s->days[i];
        if (day.high_count)
            hhws[hhw_count++] = day.hhw;
        if (day.low_count)
            llws[llw_count++] = day.llw;
    }
    for (int i = 0; i < s->high_count; ++i)
        highs[i] = s->waters.data[s->high[i]].height;
    for (int i = 0; i < s->low_count; ++i)
        lows[i] = s->waters.data[s->low[i]].height;
    s->mhhw = average(hhws, hhw_count);
    s->mllw = average(llws, llw_count);
    s->mhw = average(highs, s->high_count);
    s->mlw = average(lows, s->low_count);
    s->mtl = (s->mhw + s->mlw) / 2;
    s->gt = s->mhhw - s->mllw;
    double amp_m2 = amplitude(s, input, "M2"), amp_s2 = amplitude(s, input, "S2"),
           amp_k1 = amplitude(s, input, "K1"), amp_o1 = amplitude(s, input, "O1"),
           amp_m4 = amplitude(s, input, "M4"), phase_m2 = phase(s, input, "M2"),
           phase_s2 = phase(s, input, "S2"), phase_m4 = phase(s, input, "M4"),
           form = (amp_k1 + amp_o1) / (amp_m2 + amp_s2), spring = 2 * (amp_m2 + amp_s2),
           neap = 2 * (amp_m2 - amp_s2), sum_amplitudes = 0;
    for (int k = 0; k < s->model->count; ++k)
        sum_amplitudes += s->model->amplitudes[k];
    double *rise = allocate((size_t)s->waters.count, sizeof(double)),
           *fall = allocate((size_t)s->waters.count, sizeof(double));
    int rise_count = 0, fall_count = 0;
    for (int i = 1; i < s->waters.count; ++i) {
        Extremum previous = s->waters.data[i - 1], water = s->waters.data[i];
        if (!previous.high && water.high)
            rise[rise_count++] = water.minute - previous.minute;
        if (previous.high && !water.high)
            fall[fall_count++] = water.minute - previous.minute;
    }
    double relative = 2 * phase_m2 - phase_m4;
    while (relative < 0)
        relative += 360;
    while (relative >= 360)
        relative -= 360;
    int highest = s->high[0], lowest = s->low[0], widest = -1, narrowest = -1;
    for (int i = 0; i < s->high_count; ++i) {
        int index = s->high[i];
        if (s->waters.data[index].height > s->waters.data[highest].height)
            highest = index;
    }
    for (int i = 0; i < s->low_count; ++i) {
        int index = s->low[i];
        if (s->waters.data[index].height < s->waters.data[lowest].height)
            lowest = index;
    }
    for (int i = 0; i < s->day_count; ++i)
        if (s->days[i].has_range) {
            if (widest < 0 || s->days[i].range > s->days[widest].range)
                widest = i;
            if (narrowest < 0 || s->days[i].range < s->days[narrowest].range)
                narrowest = i;
        }
    int above = 0, below = 0;
    for (int i = 0; i <= p->length; ++i) {
        above += s->hourly[i] > s->mhhw;
        below += s->hourly[i] < s->mllw;
    }
    int mid = s->first + length / 2;
    Sample *training = allocate((size_t)n, sizeof(Sample)),
           *test_data = allocate((size_t)n, sizeof(Sample));
    int train_count = 0, test_count = 0;
    for (int i = 0; i < n; ++i) {
        Sample sample = s->usable[i];
        if (sample.time <= mid)
            training[train_count++] = sample;
        else
            test_data[test_count++] = sample;
    }
    Selection validation_selection =
        select_constituents(input, training[train_count - 1].time - training[0].time, p->rayleigh);
    Model *validation =
        fit(training, train_count, validation_selection.speeds, validation_selection.count);
    double test_ss = 0, in_sample = 0, test_mean = 0, test_variance = 0;
    for (int i = 0; i < test_count; ++i)
        test_mean += test_data[i].value;
    test_mean /= test_count;
    for (int i = 0; i < test_count; ++i) {
        Sample sample = test_data[i];
        double residual = sample.value - prediction(validation, sample.time);
        test_ss += residual * residual;
        double fitted_residual = s->residuals[sample.time];
        in_sample += fitted_residual * fitted_residual;
        double centered = sample.value - test_mean;
        test_variance += centered * centered;
    }
    line(&s->summary, "[station %s] %s", station->code, station->name);
    line(&s->summary, "record first=%s last=%s length=%d usable=%d", at(s->first, p),
         at(s->last, p), length, n);
    line(&s->summary, "fit constituents=%d unknowns=%d dof=%d mean_level=%s", s->selection.count,
         unknowns, dof, real(s->model->coefficients[0], 4));
    line(&s->summary, "residual rms=%s max_abs=%s explained_percent=%s lag1_autocorrelation=%s",
         real(sqrt(ss / n), 4), real(max_abs, 4), real(100 * (1 - ss / observed_ss), 4),
         real(lag_numerator / lag_denominator, 4));
    int *top = allocate((size_t)n, sizeof(int));
    for (int i = 0; i < n; ++i)
        top[i] = s->usable[i].time;
    top_state = s;
    qsort(top, (size_t)n, sizeof(int), residual_order);
    for (int i = 0; i < p->top; ++i) {
        int t = top[i];
        line(&s->summary, "top_residual rank=%d time=%s observed=%s fitted=%s residual=%s", i + 1,
             at(t, p), real((double)station->observations[t].milli / 1000, 3),
             real(prediction(s->model, t), 4), real(s->residuals[t], 4));
    }
    line(&s->summary,
         "validation split=%s train=%d test=%d constituents=%d rms=%s in_sample_rms=%s skill=%s",
         at(mid, p), train_count, test_count, validation_selection.count,
         real(sqrt(test_ss / test_count), 4), real(sqrt(in_sample / test_count), 4),
         real(1 - test_ss / test_variance, 4));
    line(&s->summary, "form_number=%s type=%s", real(form, 4),
         form < 0.25  ? "semidiurnal"
         : form < 1.5 ? "mixed_semidiurnal"
         : form < 3   ? "mixed_diurnal"
                      : "diurnal");
    line(&s->summary, "ranges spring=%s neap=%s mn=%s gt=%s", real(spring, 3), real(neap, 3),
         real(s->mhw - s->mlw, 3), real(s->gt, 3));
    line(&s->summary,
         "asymmetry rise_minutes=%s fall_minutes=%s m4_m2_ratio=%s relative_phase=%s dominance=%s",
         real(average(rise, rise_count), 1), real(average(fall, fall_count), 1),
         real(amp_m4 / amp_m2, 4), real(relative, 2), relative < 180 ? "flood" : "ebb");
    line(&s->summary, "datums mhhw=%s mhw=%s mtl=%s dtl=%s mlw=%s mllw=%s", real(s->mhhw, 3),
         real(s->mhw, 3), real(s->mtl, 3), real((s->mhhw + s->mllw) / 2, 3), real(s->mlw, 3),
         real(s->mllw, 3));
    line(&s->summary, "bounds hat=%s lat=%s", real(s->model->coefficients[0] + sum_amplitudes, 3),
         real(s->model->coefficients[0] - sum_amplitudes, 3));
    line(&s->summary,
         "window high_waters=%d low_waters=%d highest=%s highest_time=%s lowest=%s lowest_time=%s",
         s->high_count, s->low_count, real(s->waters.data[highest].height, 3),
         datetime(s->waters.data[highest].minute, p->epoch_day),
         real(s->waters.data[lowest].height, 3),
         datetime(s->waters.data[lowest].minute, p->epoch_day));
    line(&s->summary, "daily_range widest=%s widest_date=%s narrowest=%s narrowest_date=%s",
         real(s->days[widest].range, 3), date(s->days[widest].day, p->epoch_day),
         real(s->days[narrowest].range, 3), date(s->days[narrowest].day, p->epoch_day));
    line(&s->summary, "exceedance above_mhhw=%s below_mllw=%s",
         real(100.0 * above / (p->length + 1), 2), real(100.0 * below / (p->length + 1), 2));
    double dw = s->model->speeds[model_index(s, input, "S2")] -
                s->model->speeds[model_index(s, input, "M2")],
           dg = phase_s2 - phase_m2, q1 = (dw * p->start - dg) / 180,
           q2 = (dw * (p->start + p->length) - dg) / 180;
    int qfirst = (int)floor(fmin(q1, q2)) - 1, qlast = (int)ceil(fmax(q1, q2)) + 1;
    for (int q = qfirst; q <= qlast; ++q) {
        double t = (dg + 180.0 * q) / dw;
        if (p->start <= t && t <= p->start + p->length)
            line(&s->summary, "%s time=%s", q % 2 == 0 ? "spring" : "neap",
                 datetime((int)floor(t * 60 + 0.5), p->epoch_day));
    }
    Event *events = allocate((size_t)n, sizeof(Event));
    int event_count = 0, position = 0;
    while (position < n) {
        int t = s->usable[position].time, sign = event_sign(s, t, p);
        if (!sign) {
            ++position;
            continue;
        }
        int first = t, last = t, peak = t;
        while (position + 1 < n && s->usable[position + 1].time == last + 1 &&
               event_sign(s, s->usable[position + 1].time, p) == sign) {
            ++position;
            last = s->usable[position].time;
            if ((sign > 0 && s->residuals[last] > s->residuals[peak]) ||
                (sign < 0 && s->residuals[last] < s->residuals[peak]))
                peak = last;
        }
        if (last - first + 1 >= p->surge_hours)
            events[event_count++] = (Event){first, last, peak, sign};
        ++position;
    }
    line(&s->summary, "surges count=%d threshold=%s min_hours=%d", event_count, real(p->surge, 3),
         p->surge_hours);
    for (int i = 0; i < event_count; ++i) {
        Event event = events[i];
        line(&s->summary, "surge type=%s start=%s end=%s hours=%d peak=%s peak_time=%s",
             event.sign > 0 ? "positive" : "negative", at(event.first, p), at(event.last, p),
             event.last - event.first + 1, real(s->residuals[event.peak], 4), at(event.peak, p));
    }
    const int weights[20] = {0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1};
    DailyMean means[418];
    int mean_count = 0;
    for (int day = s->first / 24; day <= s->last / 24; ++day) {
        int noon = 24 * day + 12;
        if (noon - 19 < s->first || noon + 19 > s->last)
            continue;
        double sum = 0;
        int filled = 0;
        for (int j = -19; j <= 19; ++j) {
            int t = noon + j;
            bool usable = s->used[t];
            double value =
                usable ? (double)station->observations[t].milli / 1000 : prediction(s->model, t);
            sum += weights[abs(j)] * value;
            filled += !usable;
        }
        means[mean_count++] = (DailyMean){day, filled, sum / 30};
    }
    double x[418], levels[418];
    int maximum = 0, minimum = 0;
    for (int i = 0; i < mean_count; ++i) {
        x[i] = means[i].day - means[0].day;
        levels[i] = means[i].level;
        if (means[i].level > means[maximum].level)
            maximum = i;
        if (means[i].level < means[minimum].level)
            minimum = i;
    }
    double xm = average(x, mean_count), vm = average(levels, mean_count), numerator = 0,
           denominator = 0;
    for (int i = 0; i < mean_count; ++i) {
        double dx = x[i] - xm;
        numerator += dx * (levels[i] - vm);
        denominator += dx * dx;
    }
    line(&s->summary,
         "daily_mean days=%d average=%s slope_mm_per_day=%s max=%s max_date=%s min=%s min_date=%s",
         mean_count, real(vm, 4), real(1000 * (numerator / denominator), 3),
         real(means[maximum].level, 4), date(means[maximum].day, p->epoch_day),
         real(means[minimum].level, 4), date(means[minimum].day, p->epoch_day));
    for (int i = 0; i < mean_count; ++i)
        line(&s->summary, "daily_mean date=%s level=%s filled=%d", date(means[i].day, p->epoch_day),
             real(means[i].level, 4), means[i].filled);
}
static double lag(const State *station, const State *reference, bool high) {
    const int *items = high ? station->high : station->low,
              *ref = high ? reference->high : reference->low;
    int count = high ? station->high_count : station->low_count,
        ref_count = high ? reference->high_count : reference->low_count;
    double sum = 0;
    for (int i = 0; i < count; ++i) {
        int minute = station->waters.data[items[i]].minute, best = ref[0];
        for (int j = 0; j < ref_count; ++j) {
            int index = ref[j], difference = abs(minute - reference->waters.data[index].minute),
                previous = abs(minute - reference->waters.data[best].minute);
            if (difference < previous ||
                (difference == previous &&
                 reference->waters.data[index].minute < reference->waters.data[best].minute))
                best = index;
        }
        sum += minute - reference->waters.data[best].minute;
    }
    return sum / count;
}
typedef struct {
    double value;
    int pairs;
} Correlation;
static Correlation correlation(const State *a, const State *b, int lag) {
    double x[10001], y[10001];
    int count = 0;
    for (int i = 0; i < a->usable_count; ++i) {
        int time = a->usable[i].time, other = time + lag;
        if (other < 0 || other > 10000 || !b->used[other])
            continue;
        x[count] = a->residuals[time];
        y[count++] = b->residuals[other];
    }
    double xm = average(x, count), ym = average(y, count), cross = 0, xx = 0, yy = 0;
    for (int i = 0; i < count; ++i) {
        double dx = x[i] - xm, dy = y[i] - ym;
        cross += dx * dy;
        xx += dx * dx;
        yy += dy * dy;
    }
    return (Correlation){cross / sqrt(xx * yy), count};
}
static void extend(Lines *out, Lines lines) {
    for (int i = 0; i < lines.count; ++i)
        line(out, "%s", lines.data[i]);
}
int main(void) {
    const Input *input = read_inputs();
    const Params *p = &input->params;
    State *states = allocate((size_t)input->station_count, sizeof(State));
    Lines cleaning = {0}, constituents = {0}, predictions = {0}, waters = {0}, summary = {0};
    line(
        &constituents,
        "station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant");
    char *header = "time";
    for (int i = 0; i < input->station_count; ++i)
        header = joined(header, format(",%s", input->stations[i].code));
    line(&predictions, "%s", header);
    int reference_index = 0, plot_index = 0;
    for (int i = 0; i < input->station_count; ++i) {
        analyze(&states[i], &input->stations[i], input);
        extend(&cleaning, states[i].cleaning);
        extend(&constituents, states[i].constituents);
        extend(&waters, states[i].extremes);
        extend(&summary, states[i].summary);
        if (strcmp(input->stations[i].code, p->reference) == 0)
            reference_index = i;
        if (strcmp(input->stations[i].code, p->plot) == 0)
            plot_index = i;
    }
    for (int i = 0; i <= p->length; ++i) {
        char *row = at(p->start + i, p);
        for (int station = 0; station < input->station_count; ++station)
            row = joined(row, format(",%s", real(states[station].hourly[i], 3)));
        line(&predictions, "%s", row);
    }
    const State *reference = &states[reference_index];
    line(&summary, "[comparison] reference=%s", p->reference);
    const char *compared[4] = {"M2", "S2", "K1", "O1"};
    for (int i = 0; i < input->station_count; ++i) {
        const State *state = &states[i];
        if (i == reference_index)
            continue;
        line(&summary, "%s tide hw_lag_min=%s lw_lag_min=%s range_ratio=%s mtl_diff=%s",
             state->station->code, real(lag(state, reference, true), 1),
             real(lag(state, reference, false), 1), real(state->gt / reference->gt, 4),
             real(state->mtl - reference->mtl, 3));
        for (int j = 0; j < 4; ++j) {
            const char *name = compared[j];
            int k = model_index(state, input, name), kr = model_index(reference, input, name);
            double phase_difference = state->model->phases[k] - reference->model->phases[kr];
            if (phase_difference > 180)
                phase_difference -= 360;
            if (phase_difference <= -180)
                phase_difference += 360;
            line(&summary, "%s %s amplitude_ratio=%s phase_diff=%s time_lag_min=%s",
                 state->station->code, name,
                 real(state->model->amplitudes[k] / reference->model->amplitudes[kr], 4),
                 real(phase_difference, 2),
                 real(phase_difference / state->model->speeds[k] * 60, 1));
        }
    }
    line(&summary, "[correlation] max_lag=%d", p->lag);
    for (int a = 0; a < input->station_count; ++a)
        for (int b = a + 1; b < input->station_count; ++b) {
            int best_lag = -p->lag;
            Correlation best = correlation(&states[a], &states[b], best_lag),
                        zero = correlation(&states[a], &states[b], 0);
            for (int lag = -p->lag + 1; lag <= p->lag; ++lag) {
                Correlation value = correlation(&states[a], &states[b], lag);
                if (value.value > best.value ||
                    (value.value == best.value &&
                     (abs(lag) < abs(best_lag) || (abs(lag) == abs(best_lag) && lag < best_lag)))) {
                    best = value;
                    best_lag = lag;
                }
            }
            line(&summary, "%s-%s lag0=%s best_lag=%d best=%s pairs=%d", states[a].station->code,
                 states[b].station->code, real(zero.value, 4), best_lag, real(best.value, 4),
                 best.pairs);
        }
    const State *plotted = &states[plot_index];
    line(&summary, "[plot] station=%s start=%s hours=%d step_cm=%d", p->plot, at(p->start, p),
         p->plot_hours, p->plot_step);
    int rows = (p->plot_top - p->plot_bottom) / p->plot_step + 1;
    Lines cells = {0};
    for (int row = 0; row < rows; ++row) {
        char *text = allocate((size_t)p->plot_hours + 1, 1);
        memset(text, ' ', (size_t)p->plot_hours);
        line(&cells, "%s", text);
    }
    int zero_row =
        (int)floor((p->plot_top - 100 * plotted->model->coefficients[0]) / p->plot_step + 0.5);
    if (zero_row >= 0 && zero_row < rows)
        memset(cells.data[zero_row], '-', (size_t)p->plot_hours);
    char *marks = allocate((size_t)p->plot_hours, 1);
    memset(marks, ' ', (size_t)p->plot_hours);
    for (int i = 0; i < plotted->waters.count; ++i) {
        Extremum water = plotted->waters.data[i];
        int column = (water.minute - 60 * p->start + 30) / 60;
        if (column >= 0 && column < p->plot_hours)
            marks[column] = water.high ? 'H' : 'L';
    }
    for (int column = 0; column < p->plot_hours; ++column) {
        int row = (int)floor((p->plot_top - 100 * plotted->hourly[column]) / p->plot_step + 0.5);
        if (row < 0)
            cells.data[0][column] = '^';
        else if (row >= rows)
            cells.data[rows - 1][column] = 'v';
        else
            cells.data[row][column] = marks[column] == ' ' ? '*' : marks[column];
    }
    double heights[60];
    for (int row = 0; row < rows; ++row)
        heights[row] = (double)(p->plot_top - row * p->plot_step) / 100;
    char *axis = allocate((size_t)p->plot_hours + 1, 1);
    for (int column = 0; column < p->plot_hours; ++column)
        axis[column] = column % 6 == 0 ? '+' : '-';
    extend(&summary, plot_lines(heights, cells, axis));
    mkdir("output", 0777);
    save("cleaning.txt", cleaning);
    save("constituents.csv", constituents);
    save("predictions.csv", predictions);
    save("extremes.txt", waters);
    save("summary.txt", summary);
    return 0;
}
