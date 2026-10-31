#include "audio.hpp"
#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <numeric>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <utility>

template<class... Args> static std::string line(const Args&... args) {
    std::ostringstream out; bool first = true; ((out << (first ? "" : " ") << args,first = false),...); return out.str();
}
static void append(Lines& target, const Lines& source) { target.insert(target.end(),source.begin(),source.end()); }
static Lines split(const std::string& text) { std::istringstream stream(text); Lines tokens; std::string token; while (stream >> token) tokens.push_back(token); return tokens; }
static Integer sum(const Samples& samples) { return std::accumulate(samples.begin(),samples.end(),Integer{}); }
static Samples slice(const Samples& samples, Integer start, Integer count) { return Samples(samples.begin() + start,samples.begin() + start + count); }
static std::string padded(const std::string& text, int width) { return std::string(std::max(0,width - static_cast<int>(text.size())),' ') + text; }
static std::string padded(Integer value, int width) { return padded(std::to_string(value),width); }
static Integer milliseconds(Integer sample, Integer rate) { return sample * 1000 / rate; }
static std::string twoDecimals(Integer value) { return std::to_string(value / 100) + "." + (value % 100 < 10 ? "0" : "") + std::to_string(value % 100); }
static std::string frequency(Integer rate, Integer lag) { return twoDecimals(rdiv(100 * rate,lag)); }
struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };
struct Argument { std::string name, low, high; };
static Argument arg(const std::string& name, Integer low, Integer high) { return {name,std::to_string(low),std::to_string(high)}; }
struct Command {
    std::vector<Argument> arguments, repeated;
    int minimum = 0, maximum = 0;
    bool accepts(int count) const {
        int extra = count - static_cast<int>(arguments.size());
        return repeated.empty() ? extra == 0 : extra >= 0 && extra % repeated.size() == 0 && extra >= minimum * static_cast<int>(repeated.size()) && extra <= maximum * static_cast<int>(repeated.size());
    }
    const Argument& at(int index) const { return index < static_cast<int>(arguments.size()) ? arguments[index] : repeated[(index - arguments.size()) % repeated.size()]; }
};
static std::map<std::string, Command> commandTable() {
    Argument dst{"dst"}, src{"src"}, rate = arg("rate",1000,48000), count = arg("count",1,20000), num = arg("num",-65536,65536), den = arg("den",1,65536);
    Argument attack = arg("attack",1,32768), release = arg("release",1,32768), start{"start","0","L - 1"}, minHz{"min_hz","1","rate div 2 - 1"}, maxHz{"max_hz","min_hz + 1","rate div 2"};
    std::vector<Argument> test{dst,rate,count,{"pos","0","count - 1"},arg("amp",-32768,32767)};
    std::map<std::string, Command> table{
        {"SET",{{{"var"},arg("value",-10000000,10000000)},{{"op"},arg("operand",-10000000,10000000)},0,1}},
        {"IMPULSE",{test}},{"STEP",{test}},{"NOISE",{{dst,rate,count,arg("seed",1,2147483646)}}},
        {"GAIN",{{dst,src,num,den}}},{"MIX",{{dst,den},{src,arg("weight",-65536,65536)},1,8}},
        {"DELAY",{{dst,src,arg("samples",0,20000)}}},{"ECHO",{{dst,src,arg("delay",1,20000),num,den,arg("tail",0,20000)}}},
        {"RESAMPLE",{{dst,src,arg("new_rate",1000,48000)}}},{"FADE",{{dst,src,{"in","0","L"},{"out","0","L"}}}},
        {"TRIM",{{dst,src,start,{"count","1","L - start"}}}},{"CONCAT",{{dst},{src},2,8}},
        {"FIR",{{dst,src,arg("divisor",1,1000000)},{arg("tap",-32768,32767)},1,64}},
        {"BIQUAD",{{dst,src},{arg("b0",-65536,65536),arg("b1",-65536,65536),arg("b2",-65536,65536),arg("a1",-65536,65536),arg("a2",-65536,65536)},1,4}},
        {"MOVAVG",{{dst,src,arg("width",1,1000)}}},{"DCBLOCK",{{dst,src,arg("num",0,65535),{"den","num + 1","65536"}}}},
        {"NORMALIZE",{{dst,src,arg("target",1,32767)}}},{"GATE",{{dst,src,arg("threshold",1,32768),arg("hold",0,20000)}}},
        {"ENVELOPE",{{dst,src,attack,release}}},{"COMPRESS",{{dst,src,arg("threshold",1,32767),arg("ratio_num",1,100),{"ratio_den","1","ratio_num"},attack,release}}},
        {"ANALYZE",{{src,minHz,maxHz}}},{"COMPARE",{{src,src}}},{"EXPECT",{{src,{"metric"},{"op"},arg("value",-1000000000,1000000000)}}},
        {"SEGMENTS",{{src,arg("threshold",1,32768),arg("gap",1,20000),arg("min_length",1,20000)}}},
        {"ONSETS",{{src,attack,release,arg("threshold",1,32767),arg("min_gap",1,20000)}}},
        {"PITCHTRACK",{{src,{"frame","16","L"},{"hop","1","frame"},minHz,maxHz,arg("threshold",0,32767)}}},
        {"EXCERPT",{{src,start,arg("count",1,1000)}}},
        {"PLOT",{{src,start,{"count","1","L - start"},{"columns","8","min(120, count)"},arg("half",2,20),attack,release}}},
        {"METER",{{src,arg("block",1,20000)}}},{"HISTOGRAM",{{src,arg("bins",2,64)}}},{"TRACE",{{src}}},{"SAVE",{{src}}}
    };
    return table;
}
struct Value { std::string text; Integer integer = 0; SignalPtr signal; };
struct Parsed { std::vector<Value> values; std::vector<SignalPtr> sources; };

class Pipeline {
    std::map<std::string, SignalPtr> signals;
    std::map<std::string, Integer> variables;
    const std::map<std::string, Command> commands = commandTable();
    Lines log, analysis{"signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz"}, excerpts, waveforms, saved;
    int steps = 0, errors = 0, passed = 0, failed = 0;
    static Integer bound(const std::string& text, const std::map<std::string, Integer>& known, SignalPtr source) {
        if (text == "L") return source->samples.size();
        if (text == "L - 1") return source->samples.size() - 1;
        if (text == "L - start") return static_cast<Integer>(source->samples.size()) - known.at("start");
        if (text == "count - 1") return known.at("count") - 1;
        if (text == "min(120, count)") return std::min<Integer>(120,known.at("count"));
        if (text == "min_hz + 1") return known.at("min_hz") + 1;
        if (text == "num + 1") return known.at("num") + 1;
        if (text == "rate div 2") return source->rate / 2;
        if (text == "rate div 2 - 1") return source->rate / 2 - 1;
        auto found = known.find(text); return found != known.end() ? found->second : std::stoll(text);
    }
    Parsed parse(const std::string& name, const Command& command, const Lines& tokens) const {
        static const std::regex namePattern("[a-z][a-z0-9_]{0,15}"), integerPattern("-?(0|[1-9][0-9]{0,9})");
        const std::set<std::string> metrics{"samples","peak","rms","sum","zero_crossings","clipped"};
        Parsed parsed; std::map<std::string, Integer> known;
        for (int j = 0; j < static_cast<int>(tokens.size()); ++j) {
            const Argument& argument = command.at(j); const std::string& token = tokens[j]; Value value{token};
            if (argument.name == "dst" || argument.name == "var") {
                if (!std::regex_match(token,namePattern)) throw CommandError("bad name " + token);
            } else if (argument.name == "src") {
                auto found = signals.find(token); if (found == signals.end()) throw CommandError("unknown signal " + token);
                value.signal = found->second; parsed.sources.push_back(value.signal);
            } else if (argument.name == "metric") {
                if (!metrics.count(token)) throw CommandError("unknown metric " + token);
            } else if (argument.name == "op") {
                std::set<std::string> operators = name == "SET" ? std::set<std::string>{"+","-","*","/"} : std::set<std::string>{"eq","ne","lt","le","gt","ge"};
                if (!operators.count(token)) throw CommandError("unknown operator " + token);
            } else {
                if (token[0] == '$') {
                    auto found = variables.find(token.substr(1)); if (found == variables.end()) throw CommandError("undefined variable " + token); value.integer = found->second;
                } else {
                    if (!std::regex_match(token,integerPattern) || token == "-0") throw CommandError("bad integer " + token); value.integer = std::stoll(token);
                }
                SignalPtr source = parsed.sources.empty() ? nullptr : parsed.sources[0];
                if (value.integer < bound(argument.low,known,source) || value.integer > bound(argument.high,known,source)) throw CommandError(argument.name + " out of range");
                known[argument.name] = value.integer;
            }
            parsed.values.push_back(value);
        }
        return parsed;
    }
    static void sameRate(const std::vector<SignalPtr>& sources) {
        for (SignalPtr source : sources) if (source->rate != sources[0]->rate) throw CommandError("rate mismatch");
    }
    std::string generate(int number, const std::string& name, const Parsed& parsed) {
        const auto& a = parsed.values; auto n = [&](int index) { return a[index].integer; };
        Samples samples; Integer rate = parsed.sources.empty() ? n(1) : parsed.sources[0]->rate; Lines extras;
        auto use = [&](Processed result, const std::string& key = "clipped") { samples = std::move(result.samples); extras.push_back(key + "=" + std::to_string(result.count)); };
        const Samples empty; const Samples& x = parsed.sources.empty() ? empty : parsed.sources[0]->samples; Integer length = x.size();
        if (name == "IMPULSE") samples = impulse(n(2),n(3),n(4));
        else if (name == "STEP") samples = step(n(2),n(3),n(4));
        else if (name == "NOISE") samples = noise(n(2),n(3));
        else if (name == "GAIN") use(gain(x,n(2),n(3)));
        else if (name == "MIX") {
            sameRate(parsed.sources); std::vector<Samples> tracks; Samples weights;
            for (int j = 2; j < static_cast<int>(a.size()); j += 2) { tracks.push_back(a[j].signal->samples); weights.push_back(n(j + 1)); } use(mix(tracks,weights,n(1)));
        } else if (name == "DELAY") { if (length + n(2) > 20000) throw CommandError("result too long"); samples = delay(x,n(2)); }
        else if (name == "ECHO") {
            if (std::abs(n(3)) >= n(4)) throw CommandError("unstable feedback");
            if (length + n(5) > 20000) throw CommandError("result too long"); use(echo(x,n(2),n(3),n(4),n(5)));
        } else if (name == "RESAMPLE") {
            if (resampledLength(length,rate,n(2)) > 20000) throw CommandError("result too long"); samples = resample(x,rate,n(2)); rate = n(2);
        } else if (name == "FADE") samples = fade(x,n(2),n(3));
        else if (name == "TRIM") samples = slice(x,n(2),n(3));
        else if (name == "CONCAT") {
            sameRate(parsed.sources); Integer total = 0; for (SignalPtr source : parsed.sources) total += source->samples.size();
            if (total > 20000) throw CommandError("result too long"); for (SignalPtr source : parsed.sources) samples.insert(samples.end(),source->samples.begin(),source->samples.end());
        } else if (name == "FIR") { Samples taps; for (int j = 3; j < static_cast<int>(a.size()); ++j) taps.push_back(n(j)); use(fir(x,n(2),taps)); }
        else if (name == "BIQUAD") {
            Samples coefficients; for (int j = 2; j < static_cast<int>(a.size()); ++j) coefficients.push_back(n(j));
            extras.push_back("sections=" + std::to_string(coefficients.size() / 5)); use(biquad(x,coefficients));
        } else if (name == "MOVAVG") samples = movingAverage(x,n(2));
        else if (name == "DCBLOCK") use(dcBlock(x,n(2),n(3)));
        else if (name == "NORMALIZE") use(normalize(x,n(2)),"source_peak");
        else if (name == "GATE") use(gate(x,n(2),n(3)),"muted");
        else if (name == "ENVELOPE") samples = envelope(x,n(2),n(3));
        else if (name == "COMPRESS") {
            Compressed result = compress(x,n(2),n(3),n(4),n(5),n(6)); samples = std::move(result.samples);
            extras.push_back("min_gain=" + std::to_string(result.minGain)); extras.push_back("reduced=" + std::to_string(result.reduced));
        }
        SignalPtr signal = std::make_shared<const Signal>(Signal{a[0].text,rate,samples,line("line",number,name),parsed.sources}); signals[a[0].text] = signal;
        std::string details = line(signal->name,"rate=" + std::to_string(rate),"samples=" + std::to_string(samples.size()),"peak=" + std::to_string(peak(samples)),"sum=" + std::to_string(sum(samples)));
        for (const std::string& extra : extras) details += " " + extra; return details;
    }
    static Lines waveform(const Signal& source, Integer start, Integer count, Integer columns, Integer half, Integer attack, Integer release) {
        Samples window = slice(source.samples,start,count), levels = slice(envelope(source.samples,attack,release),start,count);
        Integer rows = 2 * half + 1, scale = std::max<Integer>(1,peak(window)); Lines grid(rows,std::string(columns,' '));
        auto rowOf = [&](Integer value) { return rdiv((scale - value) * (rows - 1),2 * scale); };
        for (Integer column = 0; column < columns; ++column) {
            Integer first = column * count / columns, last = (column + 1) * count / columns;
            Integer top = *std::max_element(window.begin() + first,window.begin() + last), bottom = *std::min_element(window.begin() + first,window.begin() + last);
            Integer level = std::min(scale,*std::max_element(levels.begin() + first,levels.begin() + last));
            for (Integer row = 0; row < rows; ++row) grid[row][column] = row == rowOf(level) || row == rowOf(-level) ? '*' : rowOf(top) <= row && row <= rowOf(bottom) ? '#' : row == half ? '-' : ' ';
        }
        Lines lines{line("PLOT",source.name,"rate=" + std::to_string(source.rate),"start=" + std::to_string(start),"count=" + std::to_string(count),"columns=" + std::to_string(columns),"rows=" + std::to_string(rows),"scale=" + std::to_string(scale),"attack=" + std::to_string(attack),"release=" + std::to_string(release))};
        for (Integer row = 0; row < rows; ++row) {
            std::string label = row == 0 ? std::to_string(scale) : row == half ? "0" : row == rows - 1 ? std::to_string(-scale) : "";
            lines.push_back(padded(label,6) + " |" + grid[row] + "|");
        }
        std::string axis = "       +"; for (Integer column = 0; column < columns; ++column) axis += column % 10 == 0 ? '+' : '-'; lines.push_back(axis + "+");
        std::string time = "    ms";
        for (Integer column = 0; column < columns; column += 10) { time.resize(8 + column,' '); time += std::to_string(milliseconds(start + column * count / columns,source.rate)); } lines.push_back(time); return lines;
    }
    static Lines meter(const Signal& source, Integer block) {
        Integer length = source.samples.size(), blocks = (length + block - 1) / block;
        Lines lines{line("METER",source.name,"rate=" + std::to_string(source.rate),"samples=" + std::to_string(length),"block=" + std::to_string(block),"blocks=" + std::to_string(blocks))};
        for (Integer b = 0; b < blocks; ++b) {
            Samples part = slice(source.samples,b * block,std::min(block,length - b * block)); Integer p = peak(part), q = rms(part), np = rdiv(p * 40,32768), nq = rdiv(q * 40,32768);
            std::string bar; for (int j = 0; j < 40; ++j) bar += j < nq ? '#' : j < np ? '-' : ' ';
            lines.push_back(padded(milliseconds(b * block,source.rate),6) + " |" + bar + "| peak=" + std::to_string(p) + " rms=" + std::to_string(q) + " clipped=" + std::to_string(clipped(part)));
        }
        return lines;
    }
    static Lines histogram(const Signal& source, Integer bins) {
        Samples counts(bins); for (Integer sample : source.samples) ++counts[(sample + 32768) * bins / 65536]; Integer maximum = *std::max_element(counts.begin(),counts.end());
        Lines lines{line("HISTOGRAM",source.name,"rate=" + std::to_string(source.rate),"samples=" + std::to_string(source.samples.size()),"bins=" + std::to_string(bins),"max=" + std::to_string(maximum))};
        for (Integer b = 0; b < bins; ++b) {
            Integer low = (b * 65536 + bins - 1) / bins - 32768, high = ((b + 1) * 65536 + bins - 1) / bins - 32769;
            lines.push_back(padded(low,6) + " " + padded(high,6) + " " + padded(counts[b],5) + " |" + std::string(rdiv(counts[b] * 50,maximum),'#'));
        }
        return lines;
    }
    static void trace(SignalPtr source, int depth, Lines& lines) {
        lines.push_back(std::string(depth * 2,' ') + source->name + " <- " + source->origin);
        for (SignalPtr ingredient : source->ingredients) trace(ingredient,depth + 1,lines);
    }
    static Integer measured(const Samples& samples, const std::string& metric) {
        if (metric == "samples") return samples.size();
        if (metric == "peak") return peak(samples);
        if (metric == "rms") return rms(samples);
        if (metric == "sum") return sum(samples);
        if (metric == "zero_crossings") return zeroCrossings(samples);
        return clipped(samples);
    }
    Lines action(const std::string& name, const Parsed& parsed) {
        const auto& a = parsed.values; auto n = [&](int index) { return a[index].integer; };
        if (name == "SET") {
            Integer result = n(1);
            if (a.size() == 4) {
                const std::string& op = a[2].text; Integer operand = n(3);
                if (op == "/" && operand == 0) throw CommandError("division by zero");
                result = op == "+" ? result + operand : op == "-" ? result - operand : op == "*" ? result * operand : floorDiv(result,operand);
                if (std::abs(result) > 10000000) throw CommandError("value out of range");
            }
            variables[a[0].text] = result; return {a[0].text + "=" + std::to_string(result)};
        }
        SignalPtr source = parsed.sources[0]; const Samples& x = source->samples; Integer length = x.size(), rate = source->rate;
        if (name == "ANALYZE" || name == "PITCHTRACK") {
            Integer minHz = name == "ANALYZE" ? n(1) : n(3), maxHz = name == "ANALYZE" ? n(2) : n(4);
            Integer low = (rate + maxHz - 1) / maxHz, high = rate / minHz;
            if (low > high) throw CommandError("empty lag range");
            if (name == "ANALYZE") {
                if (high >= length) throw CommandError("signal too short"); auto lag = pitchLag(x,low,high);
                analysis.push_back(source->name + "," + std::to_string(peak(x)) + "," + std::to_string(rms(x)) + "," + std::to_string(zeroCrossings(x)) + "," + std::to_string(clipped(x)) + "," + crestFraction(x) + "," + (lag ? std::to_string(*lag) : "none") + "," + (lag ? frequency(rate,*lag) : "none"));
                return {line(source->name,"lags=" + std::to_string(low) + "-" + std::to_string(high))};
            }
            Integer frame = n(1), hop = n(2), threshold = n(5);
            if (high >= frame) throw CommandError("frame too short"); Integer count = (length - frame) / hop + 1, voiced = 0; Lines rows;
            for (Integer t = 0; t < count; ++t) {
                Samples window = slice(x,t * hop,frame); Integer level = rms(window); auto lag = level < threshold ? std::optional<Integer>{} : pitchLag(window,low,high);
                std::string band(41,' '), details = "unvoiced rms=" + std::to_string(level);
                if (lag) { ++voiced; Integer position = high > low ? rdiv((high - *lag) * 40,high - low) : 0; band[position] = 'o'; details = "lag=" + std::to_string(*lag) + " hz=" + frequency(rate,*lag) + " rms=" + std::to_string(level); }
                rows.push_back(padded(milliseconds(t * hop,rate),6) + " |" + band + "| " + details);
            }
            waveforms.push_back(line("PITCHTRACK",source->name,"rate=" + std::to_string(rate),"frame=" + std::to_string(frame),"hop=" + std::to_string(hop),"lags=" + std::to_string(low) + "-" + std::to_string(high),"threshold=" + std::to_string(threshold),"frames=" + std::to_string(count),"voiced=" + std::to_string(voiced))); append(waveforms,rows);
            return {line(source->name,"frames=" + std::to_string(count),"voiced=" + std::to_string(voiced))};
        }
        if (name == "COMPARE") {
            sameRate(parsed.sources); const Signal& other = *parsed.sources[1]; Integer count = std::max(x.size(),other.samples.size()), differing = 0, maximum = 0, first = -1, total = 0;
            for (Integer j = 0; j < count; ++j) {
                Integer d = (j < length ? x[j] : 0) - (j < static_cast<Integer>(other.samples.size()) ? other.samples[j] : 0);
                if (d != 0) { ++differing; if (first < 0) first = j; } maximum = std::max(maximum,std::abs(d)); total += d * d;
            }
            return {line(source->name,other.name,"differing=" + std::to_string(differing),"max_diff=" + std::to_string(maximum),"first=" + (first < 0 ? "none" : std::to_string(first)),"error_energy=" + std::to_string(total))};
        }
        if (name == "EXPECT") {
            Integer value = measured(x,a[1].text), expected = n(3); const std::string& op = a[2].text;
            bool ok = op == "eq" ? value == expected : op == "ne" ? value != expected : op == "lt" ? value < expected : op == "le" ? value <= expected : op == "gt" ? value > expected : value >= expected;
            if (ok) ++passed; else ++failed; return {line(source->name,a[1].text + "=" + std::to_string(value),op,expected,ok ? "pass" : "fail")};
        }
        if (name == "SEGMENTS") {
            std::vector<std::pair<Integer, Integer>> segments;
            for (Integer j = 0; j < length; ++j) if (std::abs(x[j]) >= n(1)) {
                if (!segments.empty() && j - segments.back().second <= n(2)) segments.back().second = j; else segments.push_back({j,j});
            }
            Lines lines; int count = 0;
            for (const auto& segment : segments) if (segment.second - segment.first + 1 >= n(3)) {
                Samples part = slice(x,segment.first,segment.second - segment.first + 1);
                lines.push_back("  " + line("segment",++count,"start=" + std::to_string(segment.first),"end=" + std::to_string(segment.second),"start_ms=" + std::to_string(milliseconds(segment.first,rate)),"end_ms=" + std::to_string(milliseconds(segment.second,rate)),"peak=" + std::to_string(peak(part)),"rms=" + std::to_string(rms(part)),"crossings=" + std::to_string(zeroCrossings(part))));
            }
            lines.insert(lines.begin(),line(source->name,"segments=" + std::to_string(count))); return lines;
        }
        if (name == "ONSETS") {
            Samples levels = envelope(x,n(1),n(2)), found, intervals;
            for (Integer j = 0; j < length; ++j) if (levels[j] >= n(3) && (j == 0 || levels[j - 1] < n(3)) && (found.empty() || j - found.back() >= n(4))) found.push_back(j);
            for (int j = 1; j < static_cast<int>(found.size()); ++j) intervals.push_back(found[j] - found[j - 1]);
            std::string tempo = "none";
            if (found.size() >= 2) { Samples ordered = intervals; std::sort(ordered.begin(),ordered.end()); tempo = twoDecimals(rdiv(6000 * rate,ordered[(found.size() - 2) / 2])); }
            Lines lines{line(source->name,"onsets=" + std::to_string(found.size()),"tempo=" + tempo)};
            for (int j = 0; j < static_cast<int>(found.size()); ++j) lines.push_back("  " + line("onset",j + 1,"sample=" + std::to_string(found[j]),"ms=" + std::to_string(milliseconds(found[j],rate)),"interval=" + (j == 0 ? "none" : std::to_string(intervals[j - 1])))); return lines;
        }
        if (name == "EXCERPT") {
            Integer start = n(1), count = std::min(n(2),length - start);
            excerpts.push_back(line("EXCERPT",source->name,"rate=" + std::to_string(rate),"samples=" + std::to_string(length),"start=" + std::to_string(start),"count=" + std::to_string(count)));
            for (Integer offset = 0; offset < count; offset += 8) { std::string row = padded(start + offset,5) + ":"; for (Integer j = offset; j < std::min(offset + 8,count); ++j) row += " " + padded(x[start + j],6); excerpts.push_back(row); }
            return {line(source->name,"start=" + std::to_string(start),"count=" + std::to_string(count))};
        }
        if (name == "PLOT") { append(waveforms,waveform(*source,n(1),n(2),n(3),n(4),n(5),n(6))); return {line(source->name,"start=" + std::to_string(n(1)),"count=" + std::to_string(n(2)),"columns=" + std::to_string(n(3)),"rows=" + std::to_string(2 * n(4) + 1))}; }
        if (name == "METER") { append(waveforms,meter(*source,n(1))); return {line(source->name,"block=" + std::to_string(n(1)))}; }
        if (name == "HISTOGRAM") { append(waveforms,histogram(*source,n(1))); return {line(source->name,"bins=" + std::to_string(n(1)))}; }
        if (name == "TRACE") { Lines lines{source->name}; trace(source,1,lines); return lines; }
        append(saved,formatSignal(*source)); return {line(source->name,"samples=" + std::to_string(length))};
    }
    Lines execute(int number, const std::string& name, const Lines& tokens) {
        auto found = commands.find(name); if (found == commands.end()) throw CommandError("unknown command " + name);
        const Command& command = found->second; if (!command.accepts(static_cast<int>(tokens.size()))) throw CommandError("wrong number of arguments");
        Parsed parsed = parse(name,command,tokens); return command.arguments[0].name == "dst" ? Lines{generate(number,name,parsed)} : action(name,parsed);
    }
public:
    explicit Pipeline(const std::vector<SignalPtr>& loaded) {
        for (SignalPtr signal : loaded) { signals[signal->name] = signal; log.push_back(line("load",signal->name,"rate=" + std::to_string(signal->rate),"samples=" + std::to_string(signal->samples.size()),"peak=" + std::to_string(peak(signal->samples)))); }
    }
    void run() {
        std::ifstream file("input/pipeline.txt"); std::string text; int number = 0;
        while (std::getline(file,text)) {
            ++number; if (text.empty() || text[0] == '#') continue; Lines tokens = split(text); std::string name = tokens[0]; tokens.erase(tokens.begin());
            try { Lines lines = execute(number,name,tokens); log.push_back(line("line",std::to_string(number) + ":",name,lines[0])); log.insert(log.end(),lines.begin() + 1,lines.end()); ++steps; }
            catch (const CommandError& error) { log.push_back(line("line",std::to_string(number) + ": error:",error.what())); ++errors; }
        }
        for (const auto& entry : signals) { const Signal& signal = *entry.second; log.push_back(line("signal",signal.name,"rate=" + std::to_string(signal.rate),"samples=" + std::to_string(signal.samples.size()),"peak=" + std::to_string(peak(signal.samples)),"rms=" + std::to_string(rms(signal.samples)))); }
        log.push_back(line("summary steps=" + std::to_string(steps),"errors=" + std::to_string(errors),"signals=" + std::to_string(signals.size()),"passed=" + std::to_string(passed),"failed=" + std::to_string(failed)));
        std::filesystem::create_directories("output");
        const std::vector<std::pair<std::string, const Lines*>> outputs{{"log.txt",&log},{"analysis.csv",&analysis},{"excerpts.txt",&excerpts},{"waveforms.txt",&waveforms},{"signals_out.txt",&saved}};
        for (const auto& output : outputs) { std::ofstream stream("output/" + output.first,std::ios::binary); for (const std::string& line : *output.second) stream << line << '\n'; }
    }
};

int main() { Pipeline pipeline(readSignals()); pipeline.run(); }
