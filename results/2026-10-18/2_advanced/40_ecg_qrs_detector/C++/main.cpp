#include "ecg.hpp"
#include <filesystem>
static std::string num(Integer value) {
    return std::to_string(value);
}
static std::string align(const std::string &text, int width) {
    return std::string(std::max(0, width - int(text.size())), ' ') + text;
}
static const std::array<std::string, 5> class_names = {"qrs", "searchback", "twave", "refractory", "noise"};
static int label_index(char label) {
    return label == 'N' ? 0 : label == 'V' ? 1 : 2;
}
struct Beat {
    int peak = 0, sample = 0, reference = -1;
    Integer rr = 0, width = 0;
    char label = 'N';
};
struct Detection {
    std::vector<Peak> peaks;
    std::vector<Beat> beats;
    Levels initial, levels;
    Integer ra1 = 200, ra2 = 200;
    Values recent;
};
static std::pair<Integer, Integer> thresholds(Levels levels) {
    return {levels.npki + floor_div(levels.spki - levels.npki, 4),
            levels.npkf + floor_div(levels.spkf - levels.npkf, 4)};
}
static Detection detect(const Signals &signals, const Params &params) {
    Detection out;
    out.peaks = find_peaks(signals);
    out.initial = out.levels = initial_levels(signals);
    int last = -1;
    auto register_beat = [&](int index) {
        if (last >= 0) {
            const Integer interval = out.peaks[index].time - out.peaks[last].time;
            out.recent.push_back(interval);
            if (out.recent.size() > 8)
                out.recent.erase(out.recent.begin());
            out.ra1 = floor_div(std::accumulate(out.recent.begin(), out.recent.end(), Integer(0)),
                                out.recent.size());
            if (92 * out.ra1 <= 100 * interval && 100 * interval <= 116 * out.ra1)
                out.ra2 = out.ra1;
        }
        last = index;
        out.beats.push_back({index});
    };
    auto update = [&](const Peak &peak, int kind) {
        if (kind == 0) {
            out.levels.spki = floor_div(peak.integrated + 7 * out.levels.spki, 8);
            out.levels.spkf = floor_div(peak.filtered + 7 * out.levels.spkf, 8);
        } else if (kind == 1) {
            out.levels.npki = floor_div(peak.integrated + 7 * out.levels.npki, 8);
            out.levels.npkf = floor_div(peak.filtered + 7 * out.levels.npkf, 8);
        } else {
            out.levels.spki = floor_div(peak.integrated + 3 * out.levels.spki, 4);
            out.levels.spkf = floor_div(peak.filtered + 3 * out.levels.spkf, 4);
        }
    };
    auto searchback = [&](int time) {
        while (true) {
            const int t0 = last < 0 ? 0 : out.peaks[last].time;
            if (time - t0 <= floor_div(out.ra2 * params.searchback_percent, 100))
                break;
            const auto threshold = thresholds(out.levels);
            int selected = -1;
            for (std::size_t i = 0; i < out.peaks.size(); ++i) {
                const Peak &peak = out.peaks[i];
                if (peak.kind == PeakClass::noise && peak.time > t0 && peak.time < time &&
                    peak.integrated > floor_div(threshold.first, 2) &&
                    peak.filtered > floor_div(threshold.second, 2) &&
                    (selected < 0 || peak.integrated > out.peaks[selected].integrated))
                    selected = i;
            }
            if (selected < 0)
                break;
            Peak &peak = out.peaks[selected];
            update(peak, 2);
            peak.kind = PeakClass::searchback;
            register_beat(selected);
        }
    };
    for (std::size_t i = 0; i < out.peaks.size(); ++i) {
        Peak &peak = out.peaks[i];
        searchback(peak.time);
        const auto threshold = thresholds(out.levels);
        peak.thr_i = threshold.first;
        peak.thr_f = threshold.second;
        if (last >= 0 && peak.time - out.peaks[last].time < params.refractory_ms / 5)
            peak.kind = PeakClass::refractory;
        else if (peak.integrated > peak.thr_i && peak.filtered > peak.thr_f) {
            if (last >= 0 && peak.time - out.peaks[last].time < params.twave_ms / 5 &&
                2 * peak.slope < out.peaks[last].slope) {
                peak.kind = PeakClass::twave;
                update(peak, 1);
            } else {
                peak.kind = PeakClass::qrs;
                update(peak, 0);
                register_beat(i);
            }
        } else {
            peak.kind = PeakClass::noise;
            update(peak, 1);
        }
    }
    searchback(signals.integrated.size());
    for (std::size_t i = 0; i < out.beats.size(); ++i) {
        Beat &beat = out.beats[i];
        const Peak &peak = out.peaks[beat.peak];
        beat.sample = std::max(0, peak.r - 21);
        beat.width = qrs_width(signals, peak.r);
        if (i)
            beat.rr = 5 * (beat.sample - out.beats[i - 1].sample);
        if (i >= 9) {
            Integer preceding = 0;
            for (std::size_t j = i - 8; j < i; ++j)
                preceding += out.beats[j].rr;
            if (800 * beat.rr < params.premature_percent * preceding)
                beat.label = beat.width > params.qrs_width_ms ? 'V' : 'A';
        }
    }
    return out;
}
static void match(std::vector<Beat> &beats, std::vector<Annotation> &annotations, Integer tolerance) {
    for (std::size_t k = 0; k < beats.size(); ++k) {
        int selected = -1;
        Integer distance = 0;
        for (std::size_t i = 0; i < annotations.size(); ++i) {
            const Integer difference = std::abs(Integer(annotations[i].sample) - beats[k].sample);
            if (annotations[i].beat < 0 && difference <= tolerance &&
                (selected < 0 || difference < distance)) {
                selected = i;
                distance = difference;
            }
        }
        if (selected >= 0) {
            beats[k].reference = selected;
            annotations[selected].beat = k;
        }
    }
}
static Integer scale(Integer value, Integer top, Integer bottom, Integer rows) {
    return top > bottom ? rdiv((top - value) * (rows - 1), top - bottom) : 0;
}
static void waveform(Lines &out, const Values &upper, const Values &lower, int rows) {
    const Integer top = *std::max_element(upper.begin(), upper.end()),
                  bottom = *std::min_element(lower.begin(), lower.end());
    const int zero = bottom <= 0 && top >= 0 ? int(scale(0, top, bottom, rows)) : -1;
    for (int r = 0; r < rows; ++r) {
        const std::string label = r == 0 ? num(top) : r == rows - 1 ? num(bottom) : r == zero ? "0" : "";
        std::string row = align(label, 6) + " |";
        for (std::size_t i = 0; i < upper.size(); ++i)
            row += scale(upper[i], top, bottom, rows) <= r && r <= scale(lower[i], top, bottom, rows) ? '#'
                   : r == zero                                                                        ? '-'
                                                                                                      : ' ';
        out.push_back(row + "|");
    }
}
static std::string axis(int columns, const std::function<bool(int)> &marked) {
    std::string row = "       +";
    for (int i = 0; i < columns; ++i)
        row += marked(i) ? '+' : '-';
    return row + "+";
}
static std::string label_row(const std::string &heading,
                             const std::vector<std::pair<int, std::string>> &labels) {
    std::string row = align(heading, 6) + "  ";
    for (const auto &label : labels) {
        if (row.size() < std::size_t(8 + label.first))
            row.resize(8 + label.first, ' ');
        row += label.second;
    }
    while (!row.empty() && row.back() == ' ')
        row.pop_back();
    return row;
}
static Lines charts(const Input &input, const Detection &detection) {
    const auto &beats = detection.beats;
    const int size = input.ecg.size(), count = beats.size(), rows = input.params.chart_rows;
    Lines out;
    Values rr;
    for (int i = 1; i < count; ++i)
        rr.push_back(beats[i].rr);
    if (rr.empty()) {
        out.push_back("TACHOGRAM intervals=0");
        out.push_back("POINCARE points=0");
    } else {
        const Integer lo = *std::min_element(rr.begin(), rr.end()),
                      hi = *std::max_element(rr.begin(), rr.end());
        out.push_back("TACHOGRAM intervals=" + num(rr.size()) + " min_ms=" + num(lo) + " max_ms=" + num(hi) +
                      " rows=" + num(rows));
        for (int r = 0; r < rows; ++r) {
            std::string row = align(r == 0 ? num(hi) : r == rows - 1 ? num(lo) : "", 6) + " |";
            for (Integer value : rr)
                row += scale(value, hi, lo, rows) == r ? '*' : ' ';
            out.push_back(row + "|");
        }
        out.push_back(axis(rr.size(), [](int j) { return (j + 2) % 10 == 0; }));
        std::vector<std::pair<int, std::string>> labels;
        for (int j = 0; j < int(rr.size()); ++j)
            if ((j + 2) % 10 == 0)
                labels.push_back({j, num(j + 2)});
        out.push_back(label_row("beat", labels));
        std::string labels_line = " label |";
        for (int i = 1; i < count; ++i)
            labels_line += beats[i].label;
        out.push_back(labels_line + "|");
        const int side = input.params.poincare_size;
        std::vector<std::vector<int>> cells(side, std::vector<int>(side));
        for (std::size_t i = 0; i + 1 < rr.size(); ++i) {
            const int column = hi > lo ? int(rdiv((rr[i] - lo) * (side - 1), hi - lo)) : 0,
                      row = scale(rr[i + 1], hi, lo, side);
            ++cells[row][column];
        }
        out.push_back("POINCARE points=" + num(count - 2) + " size=" + num(side) + " min_ms=" + num(lo) +
                      " max_ms=" + num(hi));
        for (int r = 0; r < side; ++r) {
            std::string row = align(r == 0 ? num(hi) : r == side - 1 ? num(lo) : "", 6) + " |";
            for (int value : cells[r])
                row += value == 0 ? '.' : value >= 10 ? '#' : char('0' + value);
            out.push_back(row + "|");
        }
        out.push_back(axis(side, [](int) { return false; }));
        std::string row = "        " + num(lo);
        row.resize(8 + side - num(hi).size(), ' ');
        row += num(hi);
        out.push_back(row);
    }
    for (char label : std::string("NVA")) {
        std::vector<int> used;
        for (const Beat &beat : beats)
            if (beat.label == label && beat.sample >= 60 && beat.sample <= size - 100)
                used.push_back(beat.sample);
        if (used.empty()) {
            out.push_back(std::string("TEMPLATE ") + label + " beats=0");
            continue;
        }
        Values average(160);
        for (int sample : used) {
            Integer baseline = 0;
            for (int j = sample - 60; j <= sample - 51; ++j)
                baseline += input.ecg[j];
            for (int j = 0; j < 160; ++j)
                average[j] += 10 * input.ecg[sample + j - 60] - baseline;
        }
        for (Integer &value : average)
            value = rdiv(value, 10 * Integer(used.size()));
        const int maximum = std::max_element(average.begin(), average.end()) - average.begin(),
                  minimum = std::min_element(average.begin(), average.end()) - average.begin();
        out.push_back(std::string("TEMPLATE ") + label + " beats=" + num(used.size()) +
                      " max_uv=" + num(average[maximum]) + " max_ms=" + num(5 * (maximum - 60)) + " min_uv=" +
                      num(average[minimum]) + " min_ms=" + num(5 * (minimum - 60)) + " rows=" + num(rows));
        Values upper(80), lower(80);
        for (int i = 0; i < 80; ++i) {
            upper[i] = std::max(average[2 * i], average[2 * i + 1]);
            lower[i] = std::min(average[2 * i], average[2 * i + 1]);
        }
        waveform(out, upper, lower, rows);
        out.push_back(axis(80, [](int i) { return i % 10 == 0; }));
        std::vector<std::pair<int, std::string>> labels;
        for (int i = 0; i < 80; i += 10)
            labels.push_back({i, num(10 * i - 300)});
        out.push_back(label_row("ms", labels));
    }
    return out;
}
static Lines rhythm(const Input &input, const Detection &detection) {
    const Params &p = input.params;
    const int first = p.strip_start_ms / 5, length = p.strip_ms / 5, columns = length / 10;
    Values upper(columns), lower(columns);
    for (int i = 0; i < columns; ++i) {
        const auto begin = input.ecg.begin() + first + 10 * i;
        upper[i] = *std::max_element(begin, begin + 10);
        lower[i] = *std::min_element(begin, begin + 10);
    }
    Lines out = {"RHYTHM start_ms=" + num(p.strip_start_ms) +
                 " end_ms=" + num(p.strip_start_ms + p.strip_ms) + " columns=" + num(columns) + " rows=" +
                 num(p.strip_rows) + " max_uv=" + num(*std::max_element(upper.begin(), upper.end())) +
                 " min_uv=" + num(*std::min_element(lower.begin(), lower.end()))};
    waveform(out, upper, lower, p.strip_rows);
    out.push_back(axis(columns, [](int i) { return i % 20 == 0; }));
    std::vector<std::pair<int, std::string>> labels;
    for (int i = 0; i < columns; i += 20)
        labels.push_back({i, num((p.strip_start_ms + 50 * i) / 1000)});
    out.push_back(label_row("s", labels));
    std::string beat_marks(columns, ' '), ref_marks(columns, ' ');
    for (const Beat &beat : detection.beats)
        if (beat.sample >= first && beat.sample < first + length)
            beat_marks[(beat.sample - first) / 10] = beat.label;
    for (const Annotation &annotation : input.annotations)
        if (annotation.sample >= first && annotation.sample < first + length)
            ref_marks[(annotation.sample - first) / 10] = annotation.label;
    out.push_back(" beats |" + beat_marks + "|");
    out.push_back("  refs |" + ref_marks + "|");
    return out;
}
static Lines performance(const Input &input, const Detection &detection) {
    const auto &beats = detection.beats;
    const auto &annotations = input.annotations;
    std::array<int, 5> classes{};
    std::array<int, 3> refs{}, labels{}, miss{}, extra{};
    std::array<std::array<int, 3>, 3> confusion{};
    std::array<int, 2> method_total{}, method_tp{};
    int tp = 0, max_abs = 0;
    Integer offset_sum = 0, absolute_sum = 0;
    for (const Peak &peak : detection.peaks)
        ++classes[int(peak.kind)];
    for (const Annotation &annotation : annotations) {
        ++refs[label_index(annotation.label)];
        if (annotation.beat < 0)
            ++miss[label_index(annotation.label)];
    }
    for (const Beat &beat : beats) {
        ++labels[label_index(beat.label)];
        const int method = detection.peaks[beat.peak].kind == PeakClass::searchback ? 1 : 0;
        ++method_total[method];
        if (beat.reference >= 0) {
            ++tp;
            ++method_tp[method];
            const Annotation &reference = annotations[beat.reference];
            ++confusion[label_index(reference.label)][label_index(beat.label)];
            const int offset = 5 * (beat.sample - reference.sample);
            offset_sum += offset;
            absolute_sum += std::abs(offset);
            max_abs = std::max(max_abs, std::abs(offset));
        } else
            ++extra[label_index(beat.label)];
    }
    const int fp = int(beats.size()) - tp, fn = int(annotations.size()) - tp;
    auto level_line = [](const std::string &name, Levels levels) {
        return name + " spki=" + num(levels.spki) + " npki=" + num(levels.npki) +
               " spkf=" + num(levels.spkf) + " npkf=" + num(levels.npkf);
    };
    const auto threshold = thresholds(detection.levels);
    Lines out = {"DETECTOR",
                 "samples " + num(input.ecg.size()),
                 "duration_ms " + num(5 * input.ecg.size()),
                 "peaks " + num(detection.peaks.size()) + " qrs=" + num(classes[0]) +
                     " searchback=" + num(classes[1]) + " twave=" + num(classes[2]) +
                     " refractory=" + num(classes[3]) + " noise=" + num(classes[4]),
                 level_line("initial_levels", detection.initial),
                 level_line("final_levels", detection.levels),
                 "final_thresholds thr_i=" + num(threshold.first) + " thr_f=" + num(threshold.second),
                 "final_rr_averages rravg1_ms=" + num(5 * detection.ra1) +
                     " rravg2_ms=" + num(5 * detection.ra2),
                 "MATCHING",
                 "tolerance_ms " + num(input.params.match_ms),
                 "references " + num(annotations.size()) + " N=" + num(refs[0]) + " V=" + num(refs[1]) +
                     " A=" + num(refs[2]),
                 "detections " + num(beats.size()) + " N=" + num(labels[0]) + " V=" + num(labels[1]) +
                     " A=" + num(labels[2]),
                 "true_positives " + num(tp),
                 "false_positives " + num(fp),
                 "false_negatives " + num(fn),
                 "sensitivity " + ratio(tp, tp + fn),
                 "positive_predictivity " + ratio(tp, tp + fp),
                 "detection_error_rate " + ratio(fp + fn, annotations.size()),
                 "by_method threshold=" + num(method_tp[0]) + "/" + num(method_total[0]) +
                     " searchback=" + num(method_tp[1]) + "/" + num(method_total[1]),
                 tp ? "offset_ms mean=" + decimal2(rdiv(100 * offset_sum, tp)) +
                          " mean_abs=" + decimal2(rdiv(100 * absolute_sum, tp)) + " max_abs=" + num(max_abs)
                    : "offset_ms none",
                 "CONFUSION",
                 "ref  " + align("N", 6) + align("V", 6) + align("A", 6) + "  miss"};
    for (int i = 0; i < 3; ++i)
        out.push_back(std::string(1, "NVA"[i]) + "    " + align(num(confusion[i][0]), 6) +
                      align(num(confusion[i][1]), 6) + align(num(confusion[i][2]), 6) +
                      align(num(miss[i]), 6));
    out.push_back("extra" + align(num(extra[0]), 6) + align(num(extra[1]), 6) + align(num(extra[2]), 6));
    out.push_back("veb_sensitivity " + ratio(confusion[1][1], refs[1]));
    out.push_back("veb_positive_predictivity " + ratio(confusion[1][1], labels[1]));
    out.push_back("sveb_sensitivity " + ratio(confusion[2][2], refs[2]));
    out.push_back("sveb_positive_predictivity " + ratio(confusion[2][2], labels[2]));
    const int segment = int(std::min(input.params.segment_ms / 5, Integer(input.ecg.size()))),
              segments = (int(input.ecg.size()) + segment - 1) / segment;
    out.push_back("SEGMENTS segment_ms=" + num(input.params.segment_ms) + " segments=" + num(segments));
    for (int g = 0; g < segments; ++g) {
        const int start = g * segment, end = std::min((g + 1) * segment, int(input.ecg.size()));
        int reference_count = 0, matched = 0, false_positive = 0, noise = 0;
        for (const Annotation &annotation : annotations)
            if (annotation.sample >= start && annotation.sample < end) {
                ++reference_count;
                matched += annotation.beat >= 0;
            }
        for (const Beat &beat : beats)
            if (beat.sample >= start && beat.sample < end && beat.reference < 0)
                ++false_positive;
        for (const Peak &peak : detection.peaks)
            if (peak.time >= start && peak.time < end && peak.kind == PeakClass::noise)
                ++noise;
        out.push_back(align(num(5 * start), 6) + "-" + align(num(5 * end), 6) +
                      " refs=" + num(reference_count) + " tp=" + num(matched) + " fp=" + num(false_positive) +
                      " fn=" + num(reference_count - matched) + " noise_peaks=" + num(noise));
    }
    out.push_back("ERRORS count=" + num(fp + fn));
    struct Error {
        int sample, priority;
        std::string line;
    };
    std::vector<Error> errors;
    for (std::size_t i = 0; i < beats.size(); ++i)
        if (beats[i].reference < 0) {
            const Beat &beat = beats[i];
            errors.push_back({beat.sample, 0,
                              "false_positive beat=" + num(i + 1) + " sample=" + num(beat.sample) +
                                  " time_ms=" + num(5 * beat.sample) + " label=" + beat.label});
        }
    for (const Annotation &reference : annotations)
        if (reference.beat < 0)
            errors.push_back({reference.sample, 1,
                              "false_negative sample=" + num(reference.sample) +
                                  " time_ms=" + num(5 * reference.sample) + " label=" + reference.label});
    std::sort(errors.begin(), errors.end(), [](const Error &a, const Error &b) {
        return std::tie(a.sample, a.priority) < std::tie(b.sample, b.priority);
    });
    for (const Error &error : errors)
        out.push_back(error.line);
    return out;
}
static Lines hrv_report(const Input &input, const Detection &detection) {
    const auto &beats = detection.beats;
    const int count = beats.size();
    Values rr, nn, differences, sums;
    std::vector<bool> is_nn(count);
    for (int i = 1; i < count; ++i) {
        rr.push_back(beats[i].rr);
        if (i >= 2 && beats[i - 1].label == 'N' && beats[i].label == 'N' &&
            5 * std::abs(beats[i].rr - beats[i - 1].rr) <= beats[i - 1].rr) {
            is_nn[i] = true;
            nn.push_back(beats[i].rr);
            if (is_nn[i - 1]) {
                differences.push_back(beats[i].rr - beats[i - 1].rr);
                sums.push_back(beats[i].rr + beats[i - 1].rr);
            }
        }
    }
    Lines out = {"RR", "beats " + num(count), "intervals " + num(rr.size())};
    if (rr.empty()) {
        out.insert(out.end(), {"mean_rr_ms none", "min_rr_ms none", "max_rr_ms none", "mean_hr_bpm none"});
    } else {
        const auto minimum = std::min_element(rr.begin(), rr.end()),
                   maximum = std::max_element(rr.begin(), rr.end());
        out.push_back("mean_rr_ms " + decimal2(mean_scaled(rr)));
        out.push_back("min_rr_ms " + num(*minimum) + " beat=" + num(minimum - rr.begin() + 2));
        out.push_back("max_rr_ms " + num(*maximum) + " beat=" + num(maximum - rr.begin() + 2));
        out.push_back("mean_hr_bpm " + decimal2(mean_hr(rr)));
    }
    int nn50 = 0;
    for (Integer difference : differences)
        nn50 += std::abs(difference) > 50;
    out.insert(out.end(),
               {"NN", "intervals " + num(nn.size()),
                "mean_nn_ms " + (nn.empty() ? "none" : decimal2(mean_scaled(nn))),
                "sdnn_ms " + (nn.size() < 2 ? "none" : decimal2(sample_deviation(nn))),
                "differences " + num(differences.size()),
                "rmssd_ms " + (differences.empty() ? "none" : decimal2(rms(differences))),
                "sdsd_ms " + (differences.size() < 2 ? "none" : decimal2(sample_deviation(differences))),
                "nn50 " + num(nn50),
                differences.empty() ? "pnn50 none"
                                    : "pnn50 " + decimal2(rdiv(10000 * nn50, differences.size())) + "%",
                "sd1_ms " + (differences.size() < 2 ? "none" : decimal2(sample_deviation(differences, 2))),
                "sd2_ms " + (sums.size() < 2 ? "none" : decimal2(sample_deviation(sums, 2)))});
    const auto bins = histogram(nn);
    int maximum_bin = 0;
    for (const auto &bin : bins)
        maximum_bin = std::max(maximum_bin, bin.second);
    out.push_back("HISTOGRAM bin_ms=7.8125 bins=" + num(bins.size()) + " max=" + num(maximum_bin));
    for (const auto &bin : bins)
        out.push_back(align(decimal4(78125 * bin.first), 10) + " " +
                      align(decimal4(78125 * (bin.first + 1)), 10) + " " + align(num(bin.second), 3) + " |" +
                      std::string(bin.second, '#'));
    out.push_back(nn.empty() ? "triangular_index none"
                             : "triangular_index " + reduced(nn.size(), maximum_bin) + " " +
                                   decimal2(rdiv(100 * Integer(nn.size()), maximum_bin)));
    int ventricular = 0, atrial = 0;
    for (const Beat &beat : beats) {
        ventricular += beat.label == 'V';
        atrial += beat.label == 'A';
    }
    out.push_back("PREMATURE count=" + num(ventricular + atrial) + " V=" + num(ventricular) +
                  " A=" + num(atrial));
    for (int i = 0; i < count; ++i)
        if (beats[i].label != 'N') {
            const Beat &beat = beats[i];
            Integer preceding = 0;
            for (int j = i - 8; j < i; ++j)
                preceding += beats[j].rr;
            std::string compensation = "-";
            if (i + 1 < count) {
                const Integer total = beat.rr + beats[i + 1].rr;
                compensation = 10 * std::abs(4 * total - preceding) <= preceding ? "full"
                               : 4 * total < preceding                           ? "partial"
                                                                                 : "long";
            }
            out.push_back(
                "beat=" + num(i + 1) + " sample=" + num(beat.sample) + " label=" + beat.label +
                " rr_ms=" + num(beat.rr) +
                " next_rr_ms=" + optional_number(i + 1 < count, i + 1 < count ? beats[i + 1].rr : 0) +
                " mean_ms=" + decimal2(rdiv(100 * preceding, 8)) +
                " prematurity=" + decimal2(rdiv(80000 * beat.rr, preceding)) +
                "% compensation=" + compensation + " width_ms=" + num(beat.width) + " ref=" +
                (beat.reference < 0 ? "-" : std::string(1, input.annotations[beat.reference].label)));
        }
    Lines runs;
    for (int first = 0; first < count;) {
        if (beats[first].label == 'N') {
            ++first;
            continue;
        }
        int last = first;
        while (last + 1 < count && beats[last + 1].label == beats[first].label)
            ++last;
        const int length = last - first + 1;
        runs.push_back(std::string(1, beats[first].label) + " " +
                       (length == 1   ? "isolated"
                        : length == 2 ? "couplet"
                                      : "run") +
                       " beats=" + num(first + 1) + "-" + num(last + 1) + " length=" + num(length) +
                       " start_ms=" + num(5 * beats[first].sample));
        first = last + 1;
    }
    out.push_back("RUNS count=" + num(runs.size()));
    out.insert(out.end(), runs.begin(), runs.end());
    Lines events;
    for (int i = 1; i < count; ++i)
        if (beats[i].rr > input.params.pause_ms)
            events.push_back("pause beats=" + num(i) + "-" + num(i + 1) + " rr_ms=" + num(beats[i].rr) +
                             " start_ms=" + num(5 * beats[i - 1].sample));
    for (int kind = 0; kind < 2; ++kind) {
        std::vector<bool> flags(count);
        for (int i = 1; i < count; ++i)
            flags[i] = kind == 0 ? beats[i].rr > input.params.brady_ms : beats[i].rr < input.params.tachy_ms;
        for (const auto &range : ranges(flags))
            if (range.second - range.first + 1 >= 3) {
                Values intervals;
                for (int i = range.first; i <= range.second; ++i)
                    intervals.push_back(beats[i].rr);
                events.push_back(std::string(kind == 0 ? "bradycardia" : "tachycardia") +
                                 " beats=" + num(range.first) + "-" + num(range.second + 1) + " intervals=" +
                                 num(intervals.size()) + " mean_hr=" + decimal2(mean_hr(intervals)) +
                                 " start_ms=" + num(5 * beats[range.first - 1].sample));
            }
    }
    std::vector<int> vbeats;
    for (int i = 0; i < count; ++i)
        if (beats[i].label == 'V')
            vbeats.push_back(i);
    for (int step : {2, 3}) {
        int first = 0;
        while (first < int(vbeats.size())) {
            int last = first;
            while (last + 1 < int(vbeats.size())) {
                const int a = vbeats[last], b = vbeats[last + 1];
                bool linked = b - a == step;
                for (int j = a + 1; j < b; ++j)
                    if (beats[j].label != 'N')
                        linked = false;
                if (!linked)
                    break;
                ++last;
            }
            if (last - first + 1 >= 3)
                events.push_back(std::string(step == 2 ? "bigeminy" : "trigeminy") +
                                 " beats=" + num(vbeats[first] + 1) + "-" + num(vbeats[last] + 1) +
                                 " cycles=" + num(last - first + 1) +
                                 " start_ms=" + num(5 * beats[vbeats[first]].sample));
            first = last + 1;
        }
    }
    out.push_back("EVENTS count=" + num(events.size()));
    out.insert(out.end(), events.begin(), events.end());
    const int segment = int(std::min(input.params.segment_ms / 5, Integer(input.ecg.size()))),
              segments = (int(input.ecg.size()) + segment - 1) / segment;
    out.push_back("TREND segment_ms=" + num(input.params.segment_ms) + " segments=" + num(segments));
    for (int g = 0; g < segments; ++g) {
        const int first = g * segment, last = std::min((g + 1) * segment, int(input.ecg.size()));
        Values intervals;
        int beat_count = 0;
        for (int i = 0; i < count; ++i)
            if (beats[i].sample >= first && beats[i].sample < last) {
                ++beat_count;
                if (i)
                    intervals.push_back(beats[i].rr);
            }
        std::string row =
            align(num(5 * first), 6) + "-" + align(num(5 * last), 6) + " beats=" + num(beat_count);
        if (intervals.empty())
            row += " mean_hr=none min_hr=none max_hr=none |";
        else {
            const Integer heart_rate = mean_hr(intervals);
            row +=
                " mean_hr=" + decimal2(heart_rate) +
                " min_hr=" + decimal2(rdiv(6000000, *std::max_element(intervals.begin(), intervals.end()))) +
                " max_hr=" + decimal2(rdiv(6000000, *std::min_element(intervals.begin(), intervals.end()))) +
                " |" + std::string(rdiv(heart_rate, 500), '#');
        }
        out.push_back(row);
    }
    return out;
}
int main() {
    std::filesystem::create_directories("output");
    Input input = read_input();
    const Signals signals = filter(input.ecg);
    Detection detection = detect(signals, input.params);
    match(detection.beats, input.annotations, input.params.match_ms / 5);
    Lines beats = {"beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label"};
    for (std::size_t i = 0; i < detection.beats.size(); ++i) {
        const Beat &beat = detection.beats[i];
        beats.push_back(num(i + 1) + "," + num(beat.sample) + "," + num(5 * beat.sample) + "," +
                        (i ? num(beat.rr) : "-") + "," + (i ? decimal2(rdiv(6000000, beat.rr)) : "-") + "," +
                        num(beat.width) + "," + beat.label + "," +
                        (detection.peaks[beat.peak].kind == PeakClass::qrs ? "threshold" : "searchback") +
                        "," + (beat.reference < 0 ? "-" : num(input.annotations[beat.reference].sample)) +
                        "," +
                        (beat.reference < 0 ? "-" : std::string(1, input.annotations[beat.reference].label)));
    }
    write_lines("beats.csv", beats);
    Lines peaks = {"peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class"};
    for (std::size_t i = 0; i < detection.peaks.size(); ++i) {
        const Peak &peak = detection.peaks[i];
        peaks.push_back(num(i + 1) + "," + num(peak.time) + "," + num(peak.r) + "," + num(peak.integrated) +
                        "," + num(peak.filtered) + "," + num(peak.slope) + "," + num(peak.thr_i) + "," +
                        num(peak.thr_f) + "," + class_names[int(peak.kind)]);
    }
    write_lines("peaks.csv", peaks);
    struct MatchRow {
        int sample, priority;
        std::string line;
    };
    std::vector<MatchRow> matches;
    for (const Annotation &reference : input.annotations) {
        std::string row = num(reference.sample) + "," + reference.label + ",";
        if (reference.beat < 0)
            row += "-,-,-,-,FN,-";
        else {
            const Beat &beat = detection.beats[reference.beat];
            row += num(reference.beat + 1) + "," + num(beat.sample) + "," + beat.label + "," +
                   num(5 * (beat.sample - reference.sample)) + ",TP," +
                   (beat.label == reference.label ? "yes" : "no");
        }
        matches.push_back({reference.sample, 0, row});
    }
    for (std::size_t i = 0; i < detection.beats.size(); ++i) {
        const Beat &beat = detection.beats[i];
        if (beat.reference < 0)
            matches.push_back({beat.sample, 1,
                               "-,-," + num(i + 1) + "," + num(beat.sample) + "," + beat.label + ",-,FP,-"});
    }
    std::sort(matches.begin(), matches.end(), [](const MatchRow &a, const MatchRow &b) {
        return std::tie(a.sample, a.priority) < std::tie(b.sample, b.priority);
    });
    Lines matching = {"ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree"};
    for (const MatchRow &row : matches)
        matching.push_back(row.line);
    write_lines("matching.csv", matching);
    Lines excerpt = {"sample,ecg,lowpass,bandpass,derivative,squared,integrated"};
    for (int i = 0; i < input.params.excerpt_ms / 5; ++i)
        excerpt.push_back(num(i) + "," + num(input.ecg[i]) + "," + num(signals.lowpass[i]) + "," +
                          num(signals.bandpass[i]) + "," + num(signals.derivative[i]) + "," +
                          num(signals.squared[i]) + "," + num(signals.integrated[i]));
    write_lines("signals_excerpt.csv", excerpt);
    write_lines("performance.txt", performance(input, detection));
    write_lines("hrv.txt", hrv_report(input, detection));
    write_lines("charts.txt", charts(input, detection));
    write_lines("rhythm_strip.txt", rhythm(input, detection));
}
