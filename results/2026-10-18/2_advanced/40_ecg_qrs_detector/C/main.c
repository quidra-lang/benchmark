#include "ecg.h"
#include <sys/stat.h>
static const char *class_names[] = {"qrs", "searchback", "twave", "refractory", "noise"};
static char *num(Integer value) {
    return format("%lld", (long long)value);
}
static int label_index(char label) {
    return label == 'N' ? 0 : label == 'V' ? 1 : 2;
}
static char *repeat(char character, int count) {
    char *out = resize(NULL, (size_t)count + 1);
    memset(out, character, (size_t)count);
    out[count] = 0;
    return out;
}
static char *align(const char *value, int width) {
    return format("%*s", width, value);
}
typedef struct {
    int peak, sample, reference;
    Integer rr, width;
    char label;
} Beat;
typedef struct {
    Peaks peaks;
    Beat beats[600];
    int beat_count, last;
    Levels initial, levels;
    Integer ra1, ra2, recent[8];
    int recent_count;
} Detection;
static void thresholds(Levels levels, Integer *integrated, Integer *filtered) {
    *integrated = levels.npki + floor_div(levels.spki - levels.npki, 4);
    *filtered = levels.npkf + floor_div(levels.spkf - levels.npkf, 4);
}
static void register_beat(Detection *out, int index) {
    if (out->last >= 0) {
        Integer interval = out->peaks.data[index].time - out->peaks.data[out->last].time;
        if (out->recent_count == 8) {
            memmove(out->recent, out->recent + 1, 7 * sizeof(Integer));
            --out->recent_count;
        }
        out->recent[out->recent_count++] = interval;
        Integer sum = 0;
        for (int i = 0; i < out->recent_count; ++i)
            sum += out->recent[i];
        out->ra1 = floor_div(sum, out->recent_count);
        if (92 * out->ra1 <= 100 * interval && 100 * interval <= 116 * out->ra1)
            out->ra2 = out->ra1;
    }
    out->last = index;
    out->beats[out->beat_count++] = (Beat){.peak = index, .reference = -1, .label = 'N'};
}
static void update(Detection *out, const Peak *peak, int kind) {
    if (kind == 0) {
        out->levels.spki = floor_div(peak->integrated + 7 * out->levels.spki, 8);
        out->levels.spkf = floor_div(peak->filtered + 7 * out->levels.spkf, 8);
    } else if (kind == 1) {
        out->levels.npki = floor_div(peak->integrated + 7 * out->levels.npki, 8);
        out->levels.npkf = floor_div(peak->filtered + 7 * out->levels.npkf, 8);
    } else {
        out->levels.spki = floor_div(peak->integrated + 3 * out->levels.spki, 4);
        out->levels.spkf = floor_div(peak->filtered + 3 * out->levels.spkf, 4);
    }
}
static void searchback(Detection *out, const Params *params, int time) {
    while (true) {
        int t0 = out->last < 0 ? 0 : out->peaks.data[out->last].time;
        if (time - t0 <= floor_div(out->ra2 * params->searchback_percent, 100))
            break;
        Integer thi, thf;
        thresholds(out->levels, &thi, &thf);
        int selected = -1;
        for (int i = 0; i < out->peaks.count; ++i) {
            const Peak *peak = &out->peaks.data[i];
            if (peak->kind == NOISE && peak->time > t0 && peak->time < time &&
                peak->integrated > floor_div(thi, 2) && peak->filtered > floor_div(thf, 2) &&
                (selected < 0 || peak->integrated > out->peaks.data[selected].integrated))
                selected = i;
        }
        if (selected < 0)
            break;
        Peak *peak = &out->peaks.data[selected];
        update(out, peak, 2);
        peak->kind = SEARCHBACK;
        register_beat(out, selected);
    }
}
static Detection *detect(const Signals *signals, const Params *params) {
    Detection *out = calloc(1, sizeof(Detection));
    out->peaks = find_peaks(signals);
    out->initial = out->levels = initial_levels(signals);
    out->last = -1;
    out->ra1 = out->ra2 = 200;
    for (int i = 0; i < out->peaks.count; ++i) {
        Peak *peak = &out->peaks.data[i];
        searchback(out, params, peak->time);
        thresholds(out->levels, &peak->thr_i, &peak->thr_f);
        if (out->last >= 0 && peak->time - out->peaks.data[out->last].time < params->refractory_ms / 5)
            peak->kind = REFRACTORY;
        else if (peak->integrated > peak->thr_i && peak->filtered > peak->thr_f) {
            if (out->last >= 0 && peak->time - out->peaks.data[out->last].time < params->twave_ms / 5 &&
                2 * peak->slope < out->peaks.data[out->last].slope) {
                peak->kind = TWAVE;
                update(out, peak, 1);
            } else {
                peak->kind = QRS;
                update(out, peak, 0);
                register_beat(out, i);
            }
        } else {
            peak->kind = NOISE;
            update(out, peak, 1);
        }
    }
    searchback(out, params, signals->count);
    for (int i = 0; i < out->beat_count; ++i) {
        Beat *beat = &out->beats[i];
        const Peak *peak = &out->peaks.data[beat->peak];
        beat->sample = peak->r > 21 ? peak->r - 21 : 0;
        beat->width = qrs_width(signals, peak->r);
        if (i)
            beat->rr = 5 * (beat->sample - out->beats[i - 1].sample);
        if (i >= 9) {
            Integer preceding = 0;
            for (int j = i - 8; j < i; ++j)
                preceding += out->beats[j].rr;
            if (800 * beat->rr < params->premature_percent * preceding)
                beat->label = beat->width > params->qrs_width_ms ? 'V' : 'A';
        }
    }
    return out;
}
static void match(Detection *detection, Input *input) {
    Integer tolerance = input->params.match_ms / 5;
    for (int k = 0; k < detection->beat_count; ++k) {
        int selected = -1;
        Integer distance = 0;
        for (int i = 0; i < input->annotation_count; ++i) {
            Integer difference = llabs((Integer)input->annotations[i].sample - detection->beats[k].sample);
            if (input->annotations[i].beat < 0 && difference <= tolerance &&
                (selected < 0 || difference < distance)) {
                selected = i;
                distance = difference;
            }
        }
        if (selected >= 0) {
            detection->beats[k].reference = selected;
            input->annotations[selected].beat = k;
        }
    }
}
static Integer scale(Integer value, Integer top, Integer bottom, Integer rows) {
    return top > bottom ? rdiv((top - value) * (rows - 1), top - bottom) : 0;
}
static void waveform(Lines *out, const Values *upper, const Values *lower, int rows) {
    Integer top = upper->data[0], bottom = lower->data[0];
    for (int i = 0; i < upper->count; ++i) {
        if (upper->data[i] > top)
            top = upper->data[i];
        if (lower->data[i] < bottom)
            bottom = lower->data[i];
    }
    int zero = bottom <= 0 && top >= 0 ? (int)scale(0, top, bottom, rows) : -1;
    for (int r = 0; r < rows; ++r) {
        char *marks = repeat(' ', upper->count);
        for (int i = 0; i < upper->count; ++i)
            marks[i] =
                scale(upper->data[i], top, bottom, rows) <= r && r <= scale(lower->data[i], top, bottom, rows)
                    ? '#'
                : r == zero ? '-'
                            : ' ';
        const char *label = r == 0 ? num(top) : r == rows - 1 ? num(bottom) : r == zero ? "0" : "";
        line_push(out, format("%6s |%s|", label, marks));
        free(marks);
    }
}
static char *axis(int columns, int period, int offset) {
    char *marks = repeat('-', columns);
    if (period)
        for (int i = 0; i < columns; ++i)
            if ((i + offset) % period == 0)
                marks[i] = '+';
    char *out = format("       +%s+", marks);
    free(marks);
    return out;
}
static char *label_row(const char *heading, const int *positions, char *const *labels, int count) {
    char *out = format("%6s  ", heading);
    for (int i = 0; i < count; ++i) {
        int length = (int)strlen(out), target = 8 + positions[i];
        char *spaces = repeat(' ', target > length ? target - length : 0);
        char *next = format("%s%s%s", out, spaces, labels[i]);
        free(out);
        free(spaces);
        out = next;
    }
    size_t length = strlen(out);
    while (length && out[length - 1] == ' ')
        out[--length] = 0;
    return out;
}
static Lines charts(const Input *input, const Detection *detection) {
    int size = input->count, count = detection->beat_count, rows = (int)input->params.chart_rows;
    Lines out = {0};
    Values rr = {0};
    for (int i = 1; i < count; ++i)
        value_push(&rr, detection->beats[i].rr);
    if (!rr.count) {
        line_push(&out, text("TACHOGRAM intervals=0"));
        line_push(&out, text("POINCARE points=0"));
    } else {
        Integer lo = rr.data[0], hi = rr.data[0];
        for (int i = 1; i < rr.count; ++i) {
            if (rr.data[i] < lo)
                lo = rr.data[i];
            if (rr.data[i] > hi)
                hi = rr.data[i];
        }
        line_push(&out, format("TACHOGRAM intervals=%d min_ms=%lld max_ms=%lld rows=%d", rr.count,
                               (long long)lo, (long long)hi, rows));
        for (int r = 0; r < rows; ++r) {
            char *marks = repeat(' ', rr.count);
            for (int i = 0; i < rr.count; ++i)
                if (scale(rr.data[i], hi, lo, rows) == r)
                    marks[i] = '*';
            line_push(&out, format("%6s |%s|", r == 0 ? num(hi) : r == rows - 1 ? num(lo) : "", marks));
            free(marks);
        }
        line_push(&out, axis(rr.count, 10, 2));
        int positions[600], label_count = 0;
        char *labels[600];
        for (int j = 0; j < rr.count; ++j)
            if ((j + 2) % 10 == 0) {
                positions[label_count] = j;
                labels[label_count++] = num(j + 2);
            }
        line_push(&out, label_row("beat", positions, labels, label_count));
        for (int i = 0; i < label_count; ++i)
            free(labels[i]);
        char *marks = repeat(' ', rr.count);
        for (int i = 1; i < count; ++i)
            marks[i - 1] = detection->beats[i].label;
        line_push(&out, format(" label |%s|", marks));
        free(marks);
        int side = (int)input->params.poincare_size;
        int *cells = calloc((size_t)side * side, sizeof(int));
        for (int i = 0; i + 1 < rr.count; ++i) {
            int column = hi > lo ? (int)rdiv((rr.data[i] - lo) * (side - 1), hi - lo) : 0,
                row = (int)scale(rr.data[i + 1], hi, lo, side);
            ++cells[row * side + column];
        }
        line_push(&out, format("POINCARE points=%d size=%d min_ms=%lld max_ms=%lld", count - 2, side,
                               (long long)lo, (long long)hi));
        for (int r = 0; r < side; ++r) {
            marks = repeat('.', side);
            for (int i = 0; i < side; ++i) {
                int value = cells[r * side + i];
                marks[i] = value == 0 ? '.' : value >= 10 ? '#' : (char)('0' + value);
            }
            line_push(&out, format("%6s |%s|", r == 0 ? num(hi) : r == side - 1 ? num(lo) : "", marks));
            free(marks);
        }
        free(cells);
        line_push(&out, axis(side, 0, 0));
        char *left = num(lo), *right = num(hi),
             *spaces = repeat(' ', side - (int)strlen(left) - (int)strlen(right));
        line_push(&out, format("        %s%s%s", left, spaces, right));
        free(left);
        free(right);
        free(spaces);
    }
    for (int label_index_ = 0; label_index_ < 3; ++label_index_) {
        char label = "NVA"[label_index_];
        int used[600], used_count = 0;
        for (int i = 0; i < count; ++i) {
            const Beat *beat = &detection->beats[i];
            if (beat->label == label && beat->sample >= 60 && beat->sample <= size - 100)
                used[used_count++] = beat->sample;
        }
        if (!used_count) {
            line_push(&out, format("TEMPLATE %c beats=0", label));
            continue;
        }
        Integer average[160] = {0};
        for (int i = 0; i < used_count; ++i) {
            int sample = used[i];
            Integer baseline = 0;
            for (int j = sample - 60; j <= sample - 51; ++j)
                baseline += input->ecg[j];
            for (int j = 0; j < 160; ++j)
                average[j] += 10 * input->ecg[sample + j - 60] - baseline;
        }
        int maximum = 0, minimum = 0;
        for (int j = 0; j < 160; ++j) {
            average[j] = rdiv(average[j], 10 * (Integer)used_count);
            if (average[j] > average[maximum])
                maximum = j;
            if (average[j] < average[minimum])
                minimum = j;
        }
        line_push(&out, format("TEMPLATE %c beats=%d max_uv=%lld max_ms=%d min_uv=%lld min_ms=%d rows=%d",
                               label, used_count, (long long)average[maximum], 5 * (maximum - 60),
                               (long long)average[minimum], 5 * (minimum - 60), rows));
        Values upper = {0}, lower = {0};
        for (int i = 0; i < 80; ++i) {
            value_push(&upper, average[2 * i] > average[2 * i + 1] ? average[2 * i] : average[2 * i + 1]);
            value_push(&lower, average[2 * i] < average[2 * i + 1] ? average[2 * i] : average[2 * i + 1]);
        }
        waveform(&out, &upper, &lower, rows);
        free(upper.data);
        free(lower.data);
        line_push(&out, axis(80, 10, 0));
        int positions[8];
        char *labels[8];
        for (int i = 0; i < 8; ++i) {
            positions[i] = 10 * i;
            labels[i] = num(100 * i - 300);
        }
        line_push(&out, label_row("ms", positions, labels, 8));
        for (int i = 0; i < 8; ++i)
            free(labels[i]);
    }
    free(rr.data);
    return out;
}
static Lines rhythm(const Input *input, const Detection *detection) {
    const Params *p = &input->params;
    int first = (int)(p->strip_start_ms / 5), length = (int)(p->strip_ms / 5), columns = length / 10;
    Values upper = {0}, lower = {0};
    Integer top = input->ecg[first], bottom = input->ecg[first];
    for (int i = 0; i < columns; ++i) {
        Integer high = input->ecg[first + 10 * i], low = high;
        for (int j = 1; j < 10; ++j) {
            Integer value = input->ecg[first + 10 * i + j];
            if (value > high)
                high = value;
            if (value < low)
                low = value;
        }
        value_push(&upper, high);
        value_push(&lower, low);
        if (high > top)
            top = high;
        if (low < bottom)
            bottom = low;
    }
    Lines out = {0};
    line_push(&out, format("RHYTHM start_ms=%lld end_ms=%lld columns=%d rows=%lld max_uv=%lld min_uv=%lld",
                           (long long)p->strip_start_ms, (long long)(p->strip_start_ms + p->strip_ms),
                           columns, (long long)p->strip_rows, (long long)top, (long long)bottom));
    waveform(&out, &upper, &lower, (int)p->strip_rows);
    free(upper.data);
    free(lower.data);
    line_push(&out, axis(columns, 20, 0));
    int *positions = resize(NULL, (size_t)columns * sizeof(int));
    char **labels = resize(NULL, (size_t)columns * sizeof(char *));
    int count = 0;
    for (int i = 0; i < columns; i += 20) {
        positions[count] = i;
        labels[count++] = num((p->strip_start_ms + 50 * i) / 1000);
    }
    line_push(&out, label_row("s", positions, labels, count));
    for (int i = 0; i < count; ++i)
        free(labels[i]);
    free(positions);
    free(labels);
    char *beat_marks = repeat(' ', columns), *ref_marks = repeat(' ', columns);
    for (int i = 0; i < detection->beat_count; ++i) {
        const Beat *beat = &detection->beats[i];
        if (beat->sample >= first && beat->sample < first + length)
            beat_marks[(beat->sample - first) / 10] = beat->label;
    }
    for (int i = 0; i < input->annotation_count; ++i) {
        const Annotation *reference = &input->annotations[i];
        if (reference->sample >= first && reference->sample < first + length)
            ref_marks[(reference->sample - first) / 10] = reference->label;
    }
    line_push(&out, format(" beats |%s|", beat_marks));
    line_push(&out, format("  refs |%s|", ref_marks));
    free(beat_marks);
    free(ref_marks);
    return out;
}
typedef struct {
    int sample, priority;
    char *line;
} OrderedLine;
static int ordered_compare(const void *left, const void *right) {
    const OrderedLine *a = left, *b = right;
    if (a->sample != b->sample)
        return (a->sample > b->sample) - (a->sample < b->sample);
    return (a->priority > b->priority) - (a->priority < b->priority);
}
static Lines performance(const Input *input, const Detection *detection) {
    int classes[5] = {0}, refs[3] = {0}, labels[3] = {0}, miss[3] = {0}, extra[3] = {0},
        confusion[3][3] = {{0}}, method_total[2] = {0}, method_tp[2] = {0}, tp = 0, max_abs = 0;
    Integer offset_sum = 0, absolute_sum = 0;
    for (int i = 0; i < detection->peaks.count; ++i)
        ++classes[detection->peaks.data[i].kind];
    for (int i = 0; i < input->annotation_count; ++i) {
        const Annotation *reference = &input->annotations[i];
        ++refs[label_index(reference->label)];
        if (reference->beat < 0)
            ++miss[label_index(reference->label)];
    }
    for (int i = 0; i < detection->beat_count; ++i) {
        const Beat *beat = &detection->beats[i];
        ++labels[label_index(beat->label)];
        int method = detection->peaks.data[beat->peak].kind == SEARCHBACK;
        ++method_total[method];
        if (beat->reference >= 0) {
            ++tp;
            ++method_tp[method];
            const Annotation *reference = &input->annotations[beat->reference];
            ++confusion[label_index(reference->label)][label_index(beat->label)];
            int offset = 5 * (beat->sample - reference->sample);
            offset_sum += offset;
            absolute_sum += abs(offset);
            if (abs(offset) > max_abs)
                max_abs = abs(offset);
        } else
            ++extra[label_index(beat->label)];
    }
    int fp = detection->beat_count - tp, fn = input->annotation_count - tp;
    Integer thi, thf;
    thresholds(detection->levels, &thi, &thf);
    Lines out = {0};
    line_push(&out, text("DETECTOR"));
    line_push(&out, format("samples %d", input->count));
    line_push(&out, format("duration_ms %d", 5 * input->count));
    line_push(&out,
              format("peaks %d qrs=%d searchback=%d twave=%d refractory=%d noise=%d", detection->peaks.count,
                     classes[0], classes[1], classes[2], classes[3], classes[4]));
    Levels levels = detection->initial;
    line_push(&out, format("initial_levels spki=%lld npki=%lld spkf=%lld npkf=%lld", (long long)levels.spki,
                           (long long)levels.npki, (long long)levels.spkf, (long long)levels.npkf));
    levels = detection->levels;
    line_push(&out, format("final_levels spki=%lld npki=%lld spkf=%lld npkf=%lld", (long long)levels.spki,
                           (long long)levels.npki, (long long)levels.spkf, (long long)levels.npkf));
    line_push(&out, format("final_thresholds thr_i=%lld thr_f=%lld", (long long)thi, (long long)thf));
    line_push(&out, format("final_rr_averages rravg1_ms=%lld rravg2_ms=%lld", (long long)(5 * detection->ra1),
                           (long long)(5 * detection->ra2)));
    line_push(&out, text("MATCHING"));
    line_push(&out, format("tolerance_ms %lld", (long long)input->params.match_ms));
    line_push(&out,
              format("references %d N=%d V=%d A=%d", input->annotation_count, refs[0], refs[1], refs[2]));
    line_push(&out,
              format("detections %d N=%d V=%d A=%d", detection->beat_count, labels[0], labels[1], labels[2]));
    line_push(&out, format("true_positives %d", tp));
    line_push(&out, format("false_positives %d", fp));
    line_push(&out, format("false_negatives %d", fn));
    line_push(&out, format("sensitivity %s", ratio(tp, tp + fn)));
    line_push(&out, format("positive_predictivity %s", ratio(tp, tp + fp)));
    line_push(&out, format("detection_error_rate %s", ratio(fp + fn, input->annotation_count)));
    line_push(&out, format("by_method threshold=%d/%d searchback=%d/%d", method_tp[0], method_total[0],
                           method_tp[1], method_total[1]));
    if (tp)
        line_push(&out,
                  format("offset_ms mean=%s mean_abs=%s max_abs=%d", decimal2(rdiv(100 * offset_sum, tp)),
                         decimal2(rdiv(100 * absolute_sum, tp)), max_abs));
    else
        line_push(&out, text("offset_ms none"));
    line_push(&out, text("CONFUSION"));
    line_push(&out, format("ref  %6s%6s%6s  miss", "N", "V", "A"));
    for (int i = 0; i < 3; ++i)
        line_push(&out, format("%c    %6d%6d%6d%6d", "NVA"[i], confusion[i][0], confusion[i][1],
                               confusion[i][2], miss[i]));
    line_push(&out, format("extra%6d%6d%6d", extra[0], extra[1], extra[2]));
    line_push(&out, format("veb_sensitivity %s", ratio(confusion[1][1], refs[1])));
    line_push(&out, format("veb_positive_predictivity %s", ratio(confusion[1][1], labels[1])));
    line_push(&out, format("sveb_sensitivity %s", ratio(confusion[2][2], refs[2])));
    line_push(&out, format("sveb_positive_predictivity %s", ratio(confusion[2][2], labels[2])));
    int segment =
            input->params.segment_ms / 5 > input->count ? input->count : (int)(input->params.segment_ms / 5),
        segments = (input->count + segment - 1) / segment;
    line_push(&out,
              format("SEGMENTS segment_ms=%lld segments=%d", (long long)input->params.segment_ms, segments));
    for (int g = 0; g < segments; ++g) {
        int start = g * segment, end = (g + 1) * segment;
        if (end > input->count)
            end = input->count;
        int reference_count = 0, matched = 0, false_positive = 0, noise = 0;
        for (int i = 0; i < input->annotation_count; ++i) {
            const Annotation *reference = &input->annotations[i];
            if (reference->sample >= start && reference->sample < end) {
                ++reference_count;
                matched += reference->beat >= 0;
            }
        }
        for (int i = 0; i < detection->beat_count; ++i) {
            const Beat *beat = &detection->beats[i];
            if (beat->sample >= start && beat->sample < end && beat->reference < 0)
                ++false_positive;
        }
        for (int i = 0; i < detection->peaks.count; ++i) {
            const Peak *peak = &detection->peaks.data[i];
            if (peak->time >= start && peak->time < end && peak->kind == NOISE)
                ++noise;
        }
        line_push(&out, format("%6d-%6d refs=%d tp=%d fp=%d fn=%d noise_peaks=%d", 5 * start, 5 * end,
                               reference_count, matched, false_positive, reference_count - matched, noise));
    }
    line_push(&out, format("ERRORS count=%d", fp + fn));
    OrderedLine errors[900];
    int error_count = 0;
    for (int i = 0; i < detection->beat_count; ++i) {
        const Beat *beat = &detection->beats[i];
        if (beat->reference < 0)
            errors[error_count++] =
                (OrderedLine){beat->sample, 0,
                              format("false_positive beat=%d sample=%d time_ms=%d label=%c", i + 1,
                                     beat->sample, 5 * beat->sample, beat->label)};
    }
    for (int i = 0; i < input->annotation_count; ++i) {
        const Annotation *reference = &input->annotations[i];
        if (reference->beat < 0)
            errors[error_count++] =
                (OrderedLine){reference->sample, 1,
                              format("false_negative sample=%d time_ms=%d label=%c", reference->sample,
                                     5 * reference->sample, reference->label)};
    }
    qsort(errors, (size_t)error_count, sizeof(OrderedLine), ordered_compare);
    for (int i = 0; i < error_count; ++i)
        line_push(&out, errors[i].line);
    return out;
}
static Lines hrv_report(const Input *input, const Detection *detection) {
    int count = detection->beat_count;
    const Beat *beats = detection->beats;
    Values rr = {0}, nn = {0}, differences = {0}, sums = {0};
    bool is_nn[600] = {0};
    for (int i = 1; i < count; ++i) {
        value_push(&rr, beats[i].rr);
        if (i >= 2 && beats[i - 1].label == 'N' && beats[i].label == 'N' &&
            5 * llabs(beats[i].rr - beats[i - 1].rr) <= beats[i - 1].rr) {
            is_nn[i] = true;
            value_push(&nn, beats[i].rr);
            if (is_nn[i - 1]) {
                value_push(&differences, beats[i].rr - beats[i - 1].rr);
                value_push(&sums, beats[i].rr + beats[i - 1].rr);
            }
        }
    }
    Lines out = {0};
    line_push(&out, text("RR"));
    line_push(&out, format("beats %d", count));
    line_push(&out, format("intervals %d", rr.count));
    if (!rr.count) {
        line_push(&out, text("mean_rr_ms none"));
        line_push(&out, text("min_rr_ms none"));
        line_push(&out, text("max_rr_ms none"));
        line_push(&out, text("mean_hr_bpm none"));
    } else {
        int minimum = 0, maximum = 0;
        for (int i = 1; i < rr.count; ++i) {
            if (rr.data[i] < rr.data[minimum])
                minimum = i;
            if (rr.data[i] > rr.data[maximum])
                maximum = i;
        }
        line_push(&out, format("mean_rr_ms %s", decimal2(mean_scaled(&rr))));
        line_push(&out, format("min_rr_ms %lld beat=%d", (long long)rr.data[minimum], minimum + 2));
        line_push(&out, format("max_rr_ms %lld beat=%d", (long long)rr.data[maximum], maximum + 2));
        line_push(&out, format("mean_hr_bpm %s", decimal2(mean_hr(&rr))));
    }
    int nn50 = 0;
    for (int i = 0; i < differences.count; ++i)
        nn50 += llabs(differences.data[i]) > 50;
    line_push(&out, text("NN"));
    line_push(&out, format("intervals %d", nn.count));
    line_push(&out, format("mean_nn_ms %s", nn.count ? decimal2(mean_scaled(&nn)) : "none"));
    line_push(&out, format("sdnn_ms %s", nn.count >= 2 ? decimal2(sample_deviation(&nn, 1)) : "none"));
    line_push(&out, format("differences %d", differences.count));
    line_push(&out, format("rmssd_ms %s", differences.count ? decimal2(rms(&differences)) : "none"));
    line_push(&out, format("sdsd_ms %s",
                           differences.count >= 2 ? decimal2(sample_deviation(&differences, 1)) : "none"));
    line_push(&out, format("nn50 %d", nn50));
    line_push(&out, differences.count
                        ? format("pnn50 %s%%", decimal2(rdiv(10000 * (Integer)nn50, differences.count)))
                        : text("pnn50 none"));
    line_push(&out, format("sd1_ms %s",
                           differences.count >= 2 ? decimal2(sample_deviation(&differences, 2)) : "none"));
    line_push(&out, format("sd2_ms %s", sums.count >= 2 ? decimal2(sample_deviation(&sums, 2)) : "none"));
    Histogram bins = histogram(&nn);
    int maximum_bin = 0;
    for (int i = 0; i < bins.count; ++i)
        if (bins.data[i].count > maximum_bin)
            maximum_bin = bins.data[i].count;
    line_push(&out, format("HISTOGRAM bin_ms=7.8125 bins=%d max=%d", bins.count, maximum_bin));
    for (int i = 0; i < bins.count; ++i) {
        const Bin *bin = &bins.data[i];
        line_push(&out, format("%10s %10s %3d |%s", decimal4(78125 * bin->bin),
                               decimal4(78125 * (bin->bin + 1)), bin->count, repeat('#', bin->count)));
    }
    line_push(&out, nn.count ? format("triangular_index %s %s", reduced(nn.count, maximum_bin),
                                      decimal2(rdiv(100 * (Integer)nn.count, maximum_bin)))
                             : text("triangular_index none"));
    free(bins.data);
    int ventricular = 0, atrial = 0;
    for (int i = 0; i < count; ++i) {
        ventricular += beats[i].label == 'V';
        atrial += beats[i].label == 'A';
    }
    line_push(&out, format("PREMATURE count=%d V=%d A=%d", ventricular + atrial, ventricular, atrial));
    for (int i = 0; i < count; ++i)
        if (beats[i].label != 'N') {
            const Beat *beat = &beats[i];
            Integer preceding = 0;
            for (int j = i - 8; j < i; ++j)
                preceding += beats[j].rr;
            const char *compensation = "-";
            if (i + 1 < count) {
                Integer total = beat->rr + beats[i + 1].rr;
                compensation = 10 * llabs(4 * total - preceding) <= preceding ? "full"
                               : 4 * total < preceding                        ? "partial"
                                                                              : "long";
            }
            line_push(
                &out,
                format(
                    "beat=%d sample=%d label=%c rr_ms=%lld next_rr_ms=%s mean_ms=%s prematurity=%s%% compensation=%s width_ms=%lld ref=%c",
                    i + 1, beat->sample, beat->label, (long long)beat->rr,
                    optional_number(i + 1 < count, i + 1 < count ? beats[i + 1].rr : 0),
                    decimal2(rdiv(100 * preceding, 8)), decimal2(rdiv(80000 * beat->rr, preceding)),
                    compensation, (long long)beat->width,
                    beat->reference < 0 ? '-' : input->annotations[beat->reference].label));
        }
    Lines runs = {0};
    for (int first = 0; first < count;) {
        if (beats[first].label == 'N') {
            ++first;
            continue;
        }
        int last = first;
        while (last + 1 < count && beats[last + 1].label == beats[first].label)
            ++last;
        int length = last - first + 1;
        line_push(&runs, format("%c %s beats=%d-%d length=%d start_ms=%d", beats[first].label,
                                length == 1   ? "isolated"
                                : length == 2 ? "couplet"
                                              : "run",
                                first + 1, last + 1, length, 5 * beats[first].sample));
        first = last + 1;
    }
    line_push(&out, format("RUNS count=%d", runs.count));
    lines_extend(&out, &runs);
    lines_free(&runs);
    Lines events = {0};
    for (int i = 1; i < count; ++i)
        if (beats[i].rr > input->params.pause_ms)
            line_push(&events, format("pause beats=%d-%d rr_ms=%lld start_ms=%d", i, i + 1,
                                      (long long)beats[i].rr, 5 * beats[i - 1].sample));
    for (int kind = 0; kind < 2; ++kind) {
        bool flags[600] = {0};
        for (int i = 1; i < count; ++i)
            flags[i] =
                kind == 0 ? beats[i].rr > input->params.brady_ms : beats[i].rr < input->params.tachy_ms;
        Ranges selected = ranges(flags, count);
        for (int i = 0; i < selected.count; ++i) {
            Range range = selected.data[i];
            if (range.last - range.first + 1 < 3)
                continue;
            Values intervals = {0};
            for (int j = range.first; j <= range.last; ++j)
                value_push(&intervals, beats[j].rr);
            line_push(&events, format("%s beats=%d-%d intervals=%d mean_hr=%s start_ms=%d",
                                      kind == 0 ? "bradycardia" : "tachycardia", range.first, range.last + 1,
                                      intervals.count, decimal2(mean_hr(&intervals)),
                                      5 * beats[range.first - 1].sample));
            free(intervals.data);
        }
        free(selected.data);
    }
    int vbeats[600], vcount = 0;
    for (int i = 0; i < count; ++i)
        if (beats[i].label == 'V')
            vbeats[vcount++] = i;
    for (int step = 2; step <= 3; ++step) {
        int first = 0;
        while (first < vcount) {
            int last = first;
            while (last + 1 < vcount) {
                int a = vbeats[last], b = vbeats[last + 1];
                bool linked = b - a == step;
                for (int j = a + 1; j < b; ++j)
                    if (beats[j].label != 'N')
                        linked = false;
                if (!linked)
                    break;
                ++last;
            }
            if (last - first + 1 >= 3)
                line_push(&events,
                          format("%s beats=%d-%d cycles=%d start_ms=%d", step == 2 ? "bigeminy" : "trigeminy",
                                 vbeats[first] + 1, vbeats[last] + 1, last - first + 1,
                                 5 * beats[vbeats[first]].sample));
            first = last + 1;
        }
    }
    line_push(&out, format("EVENTS count=%d", events.count));
    lines_extend(&out, &events);
    lines_free(&events);
    int segment =
            input->params.segment_ms / 5 > input->count ? input->count : (int)(input->params.segment_ms / 5),
        segments = (input->count + segment - 1) / segment;
    line_push(&out,
              format("TREND segment_ms=%lld segments=%d", (long long)input->params.segment_ms, segments));
    for (int g = 0; g < segments; ++g) {
        int first = g * segment, last = (g + 1) * segment;
        if (last > input->count)
            last = input->count;
        Values intervals = {0};
        int beat_count = 0;
        for (int i = 0; i < count; ++i)
            if (beats[i].sample >= first && beats[i].sample < last) {
                ++beat_count;
                if (i)
                    value_push(&intervals, beats[i].rr);
            }
        if (!intervals.count)
            line_push(&out, format("%6d-%6d beats=%d mean_hr=none min_hr=none max_hr=none |", 5 * first,
                                   5 * last, beat_count));
        else {
            Integer heart_rate = mean_hr(&intervals), minimum = intervals.data[0],
                    maximum = intervals.data[0];
            for (int i = 1; i < intervals.count; ++i) {
                if (intervals.data[i] < minimum)
                    minimum = intervals.data[i];
                if (intervals.data[i] > maximum)
                    maximum = intervals.data[i];
            }
            line_push(&out,
                      format("%6d-%6d beats=%d mean_hr=%s min_hr=%s max_hr=%s |%s", 5 * first, 5 * last,
                             beat_count, decimal2(heart_rate), decimal2(rdiv(6000000, maximum)),
                             decimal2(rdiv(6000000, minimum)), repeat('#', (int)rdiv(heart_rate, 500))));
        }
        free(intervals.data);
    }
    free(rr.data);
    free(nn.data);
    free(differences.data);
    free(sums.data);
    return out;
}
static void write_owned(const char *name, Lines lines) {
    write_lines(name, &lines);
    lines_free(&lines);
}
int main(void) {
    mkdir("output", 0777);
    Input *input = read_input();
    Signals *signals = filter(input);
    Detection *detection = detect(signals, &input->params);
    match(detection, input);
    Lines beats = {0};
    line_push(&beats, text("beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label"));
    for (int i = 0; i < detection->beat_count; ++i) {
        const Beat *beat = &detection->beats[i];
        line_push(&beats, format("%d,%d,%d,%s,%s,%lld,%c,%s,%s,%c", i + 1, beat->sample, 5 * beat->sample,
                                 i ? num(beat->rr) : "-", i ? decimal2(rdiv(6000000, beat->rr)) : "-",
                                 (long long)beat->width, beat->label,
                                 detection->peaks.data[beat->peak].kind == QRS ? "threshold" : "searchback",
                                 beat->reference < 0 ? "-" : num(input->annotations[beat->reference].sample),
                                 beat->reference < 0 ? '-' : input->annotations[beat->reference].label));
    }
    write_owned("beats.csv", beats);
    Lines peaks = {0};
    line_push(&peaks, text("peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class"));
    for (int i = 0; i < detection->peaks.count; ++i) {
        const Peak *peak = &detection->peaks.data[i];
        line_push(&peaks,
                  format("%d,%d,%d,%lld,%lld,%lld,%lld,%lld,%s", i + 1, peak->time, peak->r,
                         (long long)peak->integrated, (long long)peak->filtered, (long long)peak->slope,
                         (long long)peak->thr_i, (long long)peak->thr_f, class_names[peak->kind]));
    }
    write_owned("peaks.csv", peaks);
    OrderedLine matches[900];
    int match_count = 0;
    for (int i = 0; i < input->annotation_count; ++i) {
        const Annotation *reference = &input->annotations[i];
        char *line;
        if (reference->beat < 0)
            line = format("%d,%c,-,-,-,-,FN,-", reference->sample, reference->label);
        else {
            const Beat *beat = &detection->beats[reference->beat];
            line = format("%d,%c,%d,%d,%c,%d,TP,%s", reference->sample, reference->label, reference->beat + 1,
                          beat->sample, beat->label, 5 * (beat->sample - reference->sample),
                          beat->label == reference->label ? "yes" : "no");
        }
        matches[match_count++] = (OrderedLine){reference->sample, 0, line};
    }
    for (int i = 0; i < detection->beat_count; ++i) {
        const Beat *beat = &detection->beats[i];
        if (beat->reference < 0)
            matches[match_count++] = (OrderedLine){
                beat->sample, 1, format("-,-,%d,%d,%c,-,FP,-", i + 1, beat->sample, beat->label)};
    }
    qsort(matches, (size_t)match_count, sizeof(OrderedLine), ordered_compare);
    Lines matching = {0};
    line_push(&matching, text("ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree"));
    for (int i = 0; i < match_count; ++i)
        line_push(&matching, matches[i].line);
    write_owned("matching.csv", matching);
    Lines excerpt = {0};
    line_push(&excerpt, text("sample,ecg,lowpass,bandpass,derivative,squared,integrated"));
    for (int i = 0; i < input->params.excerpt_ms / 5; ++i)
        line_push(&excerpt, format("%d,%lld,%lld,%lld,%lld,%lld,%lld", i, (long long)input->ecg[i],
                                   (long long)signals->lowpass[i], (long long)signals->bandpass[i],
                                   (long long)signals->derivative[i], (long long)signals->squared[i],
                                   (long long)signals->integrated[i]));
    write_owned("signals_excerpt.csv", excerpt);
    write_owned("performance.txt", performance(input, detection));
    write_owned("hrv.txt", hrv_report(input, detection));
    write_owned("charts.txt", charts(input, detection));
    write_owned("rhythm_strip.txt", rhythm(input, detection));
    free(detection);
    free(signals);
    free(input);
    return 0;
}
