#include "spc.hpp"
#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <set>
#include <sstream>
#include <tuple>
#include <utility>

static const Lines chartNames{"XBAR_R","R","XBAR_S","S","I","MR","CUSUM","EWMA","MA"};
static const Lines familyNames{"XBAR_R","XBAR_S","I_MR"};
static const Lines attributeNames{"p","np","c","u"};
static const std::array<Lines, 3> labels{{{"XBAR","R"},{"XBAR","S"},{"I","MR"}}};

template<class... Args> static std::string line(const Args&... args) {
    std::ostringstream out;
    bool first = true;
    ((out << (first ? "" : " ") << args,first = false),...);
    return out.str();
}

static std::string real(double value) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(4) << value;
    return out.str() == "-0.0000" ? "0.0000" : out.str();
}

static std::string join(const Lines& values, const std::string& separator = " ") {
    std::string result;
    for (const std::string& value : values) { if (!result.empty()) result += separator; result += value; }
    return result;
}

static Numbers range(int first, int last) {
    Numbers result;
    for (int i = first; i <= last; ++i) result.push_back(i);
    return result;
}

static std::string numberList(const Numbers& values) {
    Lines parts;
    for (int value : values) parts.push_back(std::to_string(value));
    return parts.empty() ? "none" : join(parts);
}

static std::string limitText(const std::string& name, Limits limits) {
    return line(name,"lcl",real(limits.lcl),"cl",real(limits.cl),"ucl",real(limits.ucl));
}

static std::string pairText(int family, const LimitPair& limits) {
    return line(limitText(labels[family][0],limits[0]),limitText(labels[family][1],limits[1]));
}

static std::string ruleName(int rule) { return rule < 9 ? std::to_string(rule) : rule == 9 ? "UPPER" : "LOWER"; }
static std::string status(bool converged) { return converged ? "converged" : "stopped"; }
static void append(Lines& target, const Lines& source) { target.insert(target.end(),source.begin(),source.end()); }

struct EstimationPass { int points; LimitPair limits; Numbers outliers; };
struct Estimate {
    std::vector<EstimationPass> passes;
    LimitPair limits;
    Numbers retained, removed;
    bool converged = false;
};
struct Pattern { int chart, points; std::vector<Signal> signals; };
struct Proposal { int family, points; LimitPair limits; };
struct CusumPoint { int number; double upper, lower; };
struct BandPoint { int number; double value, width; };
struct Event {
    int number, start, end, onset, outOfSpec = 0;
    std::vector<Signal> signals;
    std::array<int, 5> counts{};
    std::array<int, 9> detection{};
    double shift = 0, spread = 0;
    int kind = 0;
    int length() const { return end - start + 1; }
    bool contains(int point) const { return start <= point && point <= end; }
};
struct AttributePass { int lots; Center center; Numbers outliers; };
struct AttributeResult {
    int chart, retained = 0;
    bool converged = false;
    std::vector<AttributePass> passes;
    Numbers removed;
    std::vector<LotPoint> points;
    std::vector<Signal> signals;
};

class Analysis {
    Dataset data;
    Settings s;
    Constants constants;
    std::vector<Subgroup> groups;
    std::array<Estimate, 3> estimates;
    std::vector<Pattern> patterns;
    std::vector<Proposal> proposals;
    std::vector<Signal> signals;
    std::vector<Event> events;
    std::vector<CusumPoint> cusum;
    std::vector<BandPoint> ewma, average;
    std::vector<AttributeResult> attributes;
    double mu = 0, sigma = 0, reference = 0, interval = 0, sbar = 0, ewmaWidth = 0, maWidth = 0;

    LimitPair familyLimits(int family, const Numbers& points) const {
        return variableLimits(family,points,data.values,groups,s.size,constants);
    }
    std::array<Series, 2> familySeries(int family, const Numbers& points) const {
        std::array<Series, 2> result;
        for (int j = 0; j < static_cast<int>(points.size()); ++j) {
            int point = points[j];
            result[0].numbers.push_back(point);
            if (family == 2) {
                result[0].values.push_back(data.values[point - 1]);
                if (j > 0) {
                    result[1].numbers.push_back(point);
                    result[1].values.push_back(std::abs(data.values[point - 1] - data.values[points[j - 1] - 1]));
                }
            } else {
                const Subgroup& group = groups[point - 1];
                result[0].values.push_back(group.mean); result[1].numbers.push_back(point);
                result[1].values.push_back(family == 0 ? static_cast<double>(group.range) : group.sd);
            }
        }
        return result;
    }
    int subgroup(const Signal& signal) const { return signal.chart == 4 || signal.chart == 5 ? (signal.end - 1) / s.size + 1 : signal.end; }
    bool hasSignal(int chart, int end, int rule = 0) const {
        return std::any_of(signals.begin(),signals.end(),[&](const Signal& signal) { return signal.chart == chart && signal.end == end && (rule == 0 || signal.rule == rule); });
    }
    const Event* eventOf(int number) const {
        for (const Event& event : events) if (event.contains(number)) return &event;
        return nullptr;
    }
    void addBand(int chart, const BandPoint& point, int start) {
        if (point.value > mu + point.width) signals.push_back({chart,9,start,point.number,point.value,"UP"});
        else if (point.value < mu - point.width) signals.push_back({chart,10,start,point.number,point.value,"DOWN"});
    }
    void estimateFamilies() {
        for (int family = 0; family < 3; ++family) {
            Numbers initial = range(1,s.phase1 * (family == 2 ? s.size : 1)), points = initial;
            Estimate& estimate = estimates[family];
            for (int pass = 1; pass <= s.passes; ++pass) {
                LimitPair limits = familyLimits(family,points);
                auto series = familySeries(family,points);
                std::set<int> found;
                for (int chart = 0; chart < 2; ++chart) for (int j = 0; j < static_cast<int>(series[chart].values.size()); ++j)
                    if (limits[chart].outside(series[chart].values[j])) found.insert(series[chart].numbers[j]);
                Numbers outliers(found.begin(),found.end());
                estimate.passes.push_back({static_cast<int>(points.size()),limits,outliers}); estimate.limits = limits;
                if (outliers.empty()) { estimate.converged = true; break; }
                if (pass == s.passes) break;
                points.erase(std::remove_if(points.begin(),points.end(),[&](int value) { return found.count(value) != 0; }),points.end());
            }
            estimate.retained = points;
            for (int point : initial) if (!std::binary_search(points.begin(),points.end(),point)) estimate.removed.push_back(point);
        }
        for (int family = 0; family < 3; ++family) {
            auto sequences = familySeries(family,estimates[family].retained);
            for (int index = 0; index < 2; ++index) {
                int chart = family * 2 + index;
                patterns.push_back({chart,static_cast<int>(sequences[index].values.size()),checkRules(chart,sequences[index],estimates[family].limits[index],s.rules[chart])});
            }
        }
    }
    void monitor() {
        mu = estimates[0].limits[0].cl;
        sigma = estimates[0].limits[1].cl / constants.d2 / std::sqrt(s.size);
        reference = s.cusumK * sigma; interval = s.cusumH * sigma; sbar = estimates[1].limits[1].cl;
        for (int chart = 0; chart < 6; ++chart) {
            Series sequence;
            if (chart >= 4) for (int t = s.phase1 * s.size + 1; t <= static_cast<int>(data.values.size()); ++t) {
                sequence.numbers.push_back(t);
                sequence.values.push_back(chart == 4 ? data.values[t - 1] : std::abs(data.values[t - 1] - data.values[t - 2]));
            } else for (int i = s.phase1; i < static_cast<int>(groups.size()); ++i) {
                sequence.numbers.push_back(i + 1);
                sequence.values.push_back(chart == 0 || chart == 2 ? groups[i].mean : chart == 1 ? static_cast<double>(groups[i].range) : groups[i].sd);
            }
            std::vector<Signal> found = checkRules(chart,sequence,estimates[chart / 2].limits[chart % 2],s.rules[chart]);
            signals.insert(signals.end(),found.begin(),found.end());
        }
        double upper = 0, lower = 0, smooth = mu, factor = 1;
        int upperRun = 0, lowerRun = 0;
        double decay = (1 - s.weight) * (1 - s.weight), ratio = s.weight / (2 - s.weight);
        ewmaWidth = s.ewmaL * sigma * std::sqrt(ratio); maWidth = 3 * sigma / std::sqrt(s.span);
        for (int i = s.phase1 + 1; i <= static_cast<int>(groups.size()); ++i) {
            const Subgroup& group = groups[i - 1];
            upper = std::max(0.0,upper + (group.mean - mu - reference));
            lower = std::max(0.0,lower + (mu - group.mean - reference));
            upperRun = upper > 0 ? upperRun + 1 : 0; lowerRun = lower > 0 ? lowerRun + 1 : 0;
            cusum.push_back({i,upper,lower});
            if (upper > interval) { signals.push_back({6,9,i - upperRun + 1,i,upper,"UP"}); upper = 0; upperRun = 0; }
            if (lower > interval) { signals.push_back({6,10,i - lowerRun + 1,i,lower,"DOWN"}); lower = 0; lowerRun = 0; }
            smooth = s.weight * group.mean + (1 - s.weight) * smooth; factor = factor * decay;
            BandPoint e{i,smooth,s.ewmaL * sigma * std::sqrt(ratio * (1 - factor))};
            ewma.push_back(e); addBand(7,e,i);
            int first = std::max(s.phase1 + 1,i - s.span + 1), count = i - first + 1;
            Integer total = 0;
            for (int j = first; j <= i; ++j) total += groups[j - 1].total;
            BandPoint a{i,static_cast<double>(total) / (s.size * count),3 * sigma / std::sqrt(count)};
            average.push_back(a); addBand(8,a,first);
        }
        std::sort(signals.begin(),signals.end(),[](const Signal& a, const Signal& b) { return std::tie(a.chart,a.end,a.rule) < std::tie(b.chart,b.end,b.rule); });
    }
    void buildEvents() {
        std::set<int> points;
        for (const Signal& signal : signals) points.insert(subgroup(signal));
        for (int point : points) {
            if (!events.empty() && point - events.back().end - 1 <= s.gap) events.back().end = point;
            else events.push_back({static_cast<int>(events.size()) + 1,point,point,point});
        }
        for (Event& event : events) {
            bool cusumFound = false;
            for (const Signal& signal : signals) if (event.contains(subgroup(signal))) {
                event.signals.push_back(signal);
                bool location = signal.chart == 0 || signal.chart == 2 || signal.chart == 4 || signal.chart >= 6;
                int kind = signal.direction == "NONE" ? 4 : (location ? 0 : 2) + (signal.direction == "DOWN" ? 1 : 0);
                ++event.counts[kind];
                int point = subgroup(signal);
                int& detection = event.detection[signal.chart];
                if (!detection || point < detection) detection = point;
                if (signal.chart == 6) { event.onset = cusumFound ? std::min(event.onset,signal.start) : signal.start; cusumFound = true; }
            }
            event.kind = static_cast<int>(std::max_element(event.counts.begin(),event.counts.end()) - event.counts.begin());
            Integer total = 0;
            double deviations = 0;
            for (int i = event.start; i <= event.end; ++i) {
                total += groups[i - 1].total; deviations += groups[i - 1].sd;
                for (Integer value : groups[i - 1].values) event.outOfSpec += value < s.lsl || value > s.usl;
            }
            double mean = static_cast<double>(total) / (s.size * event.length());
            event.shift = (mean - mu) / sigma; event.spread = (deviations / event.length()) / sbar;
        }
        for (int family = 0; family < 3; ++family) {
            Numbers retained = estimates[family].retained;
            for (int i = s.phase1 + 1; i <= static_cast<int>(groups.size()); ++i) if (!eventOf(i)) {
                if (family == 2) { Numbers samples = range((i - 1) * s.size + 1,i * s.size); retained.insert(retained.end(),samples.begin(),samples.end()); }
                else retained.push_back(i);
            }
            proposals.push_back({family,static_cast<int>(retained.size()),familyLimits(family,retained)});
        }
    }
    void estimateAttributes() {
        for (int chart = 0; chart < 4; ++chart) {
            AttributeResult result; result.chart = chart;
            Numbers points = range(1,static_cast<int>(data.lots.size()));
            Center center{};
            for (int pass = 1; pass <= s.passes; ++pass) {
                center = attributeCenter(chart,data.lots,points);
                Numbers outliers;
                for (int number : points) if (attributePoint(data.lots[number - 1],center).status != "ok") outliers.push_back(number);
                result.passes.push_back({static_cast<int>(points.size()),center,outliers});
                if (outliers.empty()) { result.converged = true; break; }
                if (pass == s.passes) break;
                points.erase(std::remove_if(points.begin(),points.end(),[&](int number) { return std::binary_search(outliers.begin(),outliers.end(),number); }),points.end());
            }
            result.retained = static_cast<int>(points.size());
            Series standardized;
            for (const Lot& lot : data.lots) {
                if (!std::binary_search(points.begin(),points.end(),lot.number)) result.removed.push_back(lot.number);
                LotPoint point = attributePoint(lot,center); result.points.push_back(point);
                standardized.numbers.push_back(lot.number); standardized.values.push_back(point.z);
            }
            result.signals = checkRules(chart,standardized,{-3,0,3},s.rules[6]);
            attributes.push_back(result);
        }
    }
    Lines limitsLines() const {
        Lines result{line("characteristic",s.characteristic),line("subgroup_size",s.size),line("subgroups",groups.size()),line("samples",data.values.size()),line("phase1_subgroups",s.phase1)};
        for (int family = 0; family < 3; ++family) {
            const Estimate& e = estimates[family]; result.push_back(line("family",familyNames[family]));
            for (int j = 0; j < static_cast<int>(e.passes.size()); ++j) {
                const EstimationPass& p = e.passes[j];
                result.push_back(line("pass",j + 1,"points",p.points,pairText(family,p.limits),"out",numberList(p.outliers)));
            }
            result.push_back(line("result",status(e.converged),"passes",e.passes.size(),"retained",e.retained.size(),"removed",numberList(e.removed)));
        }
        for (const Pattern& pattern : patterns) {
            for (const Signal& signal : pattern.signals) result.push_back(line("phase1_signal",chartNames[pattern.chart],signal.rule,signal.start,signal.end,real(signal.value)));
            result.push_back(line("phase1_check",chartNames[pattern.chart],"points",pattern.points,"signals",pattern.signals.size()));
        }
        for (const Proposal& p : proposals) result.push_back(line("proposed",familyNames[p.family],"points",p.points,pairText(p.family,p.limits)));
        std::string target = line("target",real(mu),"sigma",real(sigma));
        result.push_back(line("cusum",target,"k",real(reference),"h",real(interval)));
        result.push_back(line("ewma",target,"lcl",real(mu - ewmaWidth),"ucl",real(mu + ewmaWidth)));
        result.push_back(line("ma",target,"span",s.span,"lcl",real(mu - maWidth),"ucl",real(mu + maWidth)));
        for (int chart = 0; chart < 9; ++chart) {
            int count = 0; std::set<int> ends; std::map<int, int> counts;
            for (const Signal& signal : signals) if (signal.chart == chart) { ++count; ends.insert(signal.end); ++counts[signal.rule]; }
            Numbers rules = chart < 6 ? s.rules[chart] : Numbers{9,10};
            Lines ruleCounts;
            for (int rule : rules) ruleCounts.push_back(ruleName(rule) + ":" + std::to_string(counts[rule]));
            int points = static_cast<int>(groups.size()) - s.phase1;
            if (chart == 4 || chart == 5) points *= s.size;
            result.push_back(line("phase2",chartNames[chart],"points",points,"signals",count,"signalled",ends.size(),"first",ends.empty() ? "none" : std::to_string(*ends.begin()),"by_rule",join(ruleCounts)));
        }
        return result;
    }
    Lines signalLines() const {
        Lines result{"chart,rule,start,end,value,direction"};
        for (const Signal& signal : signals) result.push_back(join({chartNames[signal.chart],ruleName(signal.rule),std::to_string(signal.start),std::to_string(signal.end),real(signal.value),signal.direction},","));
        return result;
    }
    Lines eventLines() const {
        const Lines types{"SHIFT_UP","SHIFT_DOWN","SPREAD_UP","SPREAD_DOWN","PATTERN"};
        Lines result{line("events",events.size())};
        for (const Event& e : events) {
            Lines charts, detection;
            for (int chart = 0; chart < 9; ++chart) {
                if (e.detection[chart]) charts.push_back(chartNames[chart]);
                detection.push_back(chartNames[chart] + ":" + (e.detection[chart] ? std::to_string(e.detection[chart]) : "-"));
            }
            result.push_back(line("event",e.number,"start",e.start,"end",e.end,"length",e.length(),"signals",e.signals.size(),"charts",join(charts,","),"location_up",e.counts[0],"location_down",e.counts[1],"spread_up",e.counts[2],"spread_down",e.counts[3],"pattern",e.counts[4],"onset",e.onset,"shift",real(e.shift),"spread",real(e.spread),"out_of_spec",e.outOfSpec,"type",types[e.kind]));
            result.push_back(line("detection",e.number,join(detection)));
        }
        return result;
    }
    Lines subgroupLines() const {
        Lines result{"subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event"};
        Zones zones(estimates[0].limits[0]);
        for (const Subgroup& g : groups) {
            bool phase2 = g.number > s.phase1;
            std::string phase = phase2 ? "phase2" : std::binary_search(estimates[0].removed.begin(),estimates[0].removed.end(),g.number) ? "excluded" : "phase1";
            Lines fields{std::to_string(g.number),phase,real(g.mean),zones.name(g.mean),std::to_string(g.range),real(g.sd)};
            if (phase2) { int index = g.number - s.phase1 - 1; append(fields,{real(cusum[index].upper),real(cusum[index].lower),real(ewma[index].value),real(average[index].value)}); }
            else append(fields,{"-","-","-","-"});
            int count = 0; for (const Signal& signal : signals) count += subgroup(signal) == g.number;
            const Event* event = eventOf(g.number);
            append(fields,{std::to_string(count),event ? std::to_string(event->number) : "-"});
            result.push_back(join(fields,","));
        }
        return result;
    }
    Lines attributeLines() const {
        Lines lines;
        for (const AttributeResult& r : attributes) {
            lines.push_back(line("chart",attributeNames[r.chart]));
            for (int j = 0; j < static_cast<int>(r.passes.size()); ++j) {
                const AttributePass& p = r.passes[j];
                lines.push_back(line("pass",j + 1,"lots",p.lots,"center",real(p.center.value),"out",numberList(p.outliers)));
            }
            lines.push_back(line("result",status(r.converged),"passes",r.passes.size(),"retained",r.retained,"removed",numberList(r.removed)));
            for (int j = 0; j < static_cast<int>(data.lots.size()); ++j) {
                const Lot& lot = data.lots[j]; const LotPoint& p = r.points[j];
                std::string value = r.chart == 1 ? std::to_string(lot.defectives) : r.chart == 2 ? std::to_string(lot.defects) : real(p.value);
                lines.push_back(line("lot",lot.number,"size",lot.inspected,"value",value,"lcl",real(p.lcl),"ucl",real(p.ucl),"z",real(p.z),"status",p.status));
            }
            for (const Signal& signal : r.signals) lines.push_back(line("signal",signal.rule,signal.start,signal.end,real(signal.value)));
            lines.push_back(line("signals",r.signals.size()));
        }
        return lines;
    }
    std::vector<Subgroup> selected(const Numbers& points) const {
        std::vector<Subgroup> result;
        for (int point : points) result.push_back(groups[point - 1]);
        return result;
    }
    Lines capabilityLines() const {
        Lines lines;
        for (int phase = 0; phase < 2; ++phase) {
            std::vector<Subgroup> chosen = selected(phase == 0 ? estimates[0].retained : range(s.phase1 + 1,static_cast<int>(groups.size())));
            Capability r = capability(chosen,s,constants);
            lines.push_back(line("group",phase == 0 ? "phase1" : "phase2","subgroups",chosen.size(),"values",r.count));
            const std::vector<std::pair<std::string, double>> measures{{"mean",r.mean},{"sigma_within",r.within},{"sigma_sbar",r.sbar},{"sigma_overall",r.overall},{"cp",r.cp},{"cpu",r.cpu},{"cpl",r.cpl},{"cpk",r.cpk},{"pp",r.pp},{"ppu",r.ppu},{"ppl",r.ppl},{"ppk",r.ppk},{"cpm",r.cpm}};
            for (const auto& measure : measures) lines.push_back(line(measure.first,real(measure.second)));
            lines.push_back(line("cpk_ci",real(r.cpkInterval[0]),real(r.cpkInterval[1]))); lines.push_back(line("ppk_ci",real(r.ppkInterval[0]),real(r.ppkInterval[1])));
            append(lines,{line("below_lsl",r.below),line("above_usl",r.above),line("ppm",real(r.ppm))});
            for (const Subgroup& g : chosen) for (int j = 0; j < s.size; ++j) {
                Integer value = g.values[j];
                if (value < s.lsl || value > s.usl) lines.push_back(line("out_of_spec sample",(g.number - 1) * s.size + j + 1,"subgroup",g.number,"value",value,"side",value < s.lsl ? "low" : "high"));
            }
            lines.push_back(line("verdict",r.verdict));
            for (const HistogramBin& bin : r.bins) {
                std::string text = line("bin",bin.lower,bin.upper,bin.frequency);
                if (bin.length) text += " " + std::string(bin.length,'#');
                for (const std::string& mark : bin.marks) text += " " + mark;
                lines.push_back(text);
            }
        }
        for (int first = s.phase1 + 1; first + s.window - 1 <= static_cast<int>(groups.size()); first += s.step) {
            int last = first + s.window - 1;
            Capability r = capability(selected(range(first,last)),s,constants);
            lines.push_back(line("rolling",first,last,"mean",real(r.mean),"sigma_within",real(r.within),"sigma_overall",real(r.overall),"cpk",real(r.cpk),"ppk",real(r.ppk),"verdict",r.verdict));
        }
        return lines;
    }
    static std::string pictureNumber(int number) { std::ostringstream out; out << std::setw(3) << number; return out.str(); }
    Lines chartLines() const {
        Lines lines;
        for (int picture = 0; picture < 3; ++picture) {
            int chart = picture == 0 ? 0 : picture == 1 ? 1 : 3, family = chart / 2;
            Limits limits = estimates[family].limits[chart % 2];
            lines.push_back(limitText("chart " + std::string(picture == 0 ? "XBAR" : picture == 1 ? "R" : "S"),limits));
            for (const Subgroup& g : groups) {
                double value = picture == 0 ? g.mean : picture == 1 ? static_cast<double>(g.range) : g.sd;
                std::string mark = g.number > s.phase1 ? "2" : std::binary_search(estimates[family].removed.begin(),estimates[family].removed.end(),g.number) ? "x" : "1";
                lines.push_back(line(pictureNumber(g.number),mark,limitsBand(limits,value,g.number > s.phase1 && hasSignal(chart,g.number)),real(value)));
            }
        }
        lines.push_back(line("chart CUSUM h",real(interval)));
        for (const CusumPoint& p : cusum) lines.push_back(line(pictureNumber(p.number),cusumBand(p.upper,p.lower,interval,hasSignal(6,p.number,9),hasSignal(6,p.number,10)),real(p.upper),real(p.lower)));
        for (int chart = 7; chart <= 8; ++chart) {
            double scale = chart == 7 ? ewmaWidth : maWidth;
            const std::vector<BandPoint>& points = chart == 7 ? ewma : average;
            lines.push_back(limitText("chart " + chartNames[chart],{mu - scale,mu,mu + scale}));
            for (const BandPoint& p : points) lines.push_back(line(pictureNumber(p.number),widthBand(scale,p.width,p.value,mu,hasSignal(chart,p.number)),real(p.value),real(mu - p.width),real(mu + p.width)));
        }
        const Lines pictures{"P_STD","NP_STD","C_STD","U_STD"};
        for (const AttributeResult& r : attributes) {
            lines.push_back(limitText("chart " + pictures[r.chart],{-3,0,3}));
            for (int j = 0; j < static_cast<int>(data.lots.size()); ++j) lines.push_back(line(pictureNumber(data.lots[j].number),standardBand(r.points[j].z,r.points[j].status == "ok"),real(r.points[j].z)));
        }
        return lines;
    }
public:
    explicit Analysis(Dataset input) : data(std::move(input)), s(data.settings), constants(controlConstants(s.size)), groups(subgroupStatistics(data.values,s.size)) {}
    void run() {
        estimateFamilies(); monitor(); buildEvents(); estimateAttributes();
        std::filesystem::create_directories("output");
        const std::vector<std::pair<std::string, Lines>> outputs{{"limits.txt",limitsLines()},{"signals.csv",signalLines()},{"events.txt",eventLines()},{"subgroups.csv",subgroupLines()},{"attribute_charts.txt",attributeLines()},{"capability.txt",capabilityLines()},{"charts.txt",chartLines()}};
        for (const auto& output : outputs) { std::ofstream file("output/" + output.first,std::ios::binary); for (const std::string& text : output.second) file << text << '\n'; }
    }
};

int main() { Analysis analysis(readDataset()); analysis.run(); }
