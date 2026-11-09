#include "timezone.hpp"

static Lines readLines(const std::string& path) {
    std::ifstream input(path, std::ios::binary);
    Lines lines;
    std::string line;
    while (std::getline(input, line)) lines.push_back(line);
    return lines;
}
static Time yearStart(int year) { return dayNumber(year, 1, 1) * DaySeconds; }
static std::string joined(const Lines& values, const std::string& separator) {
    std::string result;
    for (std::size_t index = 0; index < values.size(); ++index) {
        if (index) result += separator;
        result += values[index];
    }
    return values.empty() ? "none" : result;
}
static Lines indented(Lines lines) {
    for (std::size_t index = 1; index < lines.size(); ++index) lines[index] = "  " + lines[index];
    return lines;
}
static std::vector<Interval> mergeIntervals(std::vector<Interval> intervals) {
    std::sort(intervals.begin(), intervals.end());
    std::vector<Interval> result;
    for (const Interval& interval : intervals) {
        if (!result.empty() && interval.first <= result.back().second) result.back().second = std::max(result.back().second, interval.second);
        else result.push_back(interval);
    }
    return result;
}
static std::vector<Interval> intersectIntervals(const std::vector<Interval>& first, const std::vector<Interval>& second) {
    std::vector<Interval> pieces;
    for (const Interval& a : first) for (const Interval& b : second) {
        Time low = std::max(a.first, b.first);
        Time high = std::min(a.second, b.second);
        if (low < high) pieces.emplace_back(low, high);
    }
    return mergeIntervals(pieces);
}
struct ZoneLine {
    Time standardOffset;
    std::string rulesText;
    std::string ruleSet;
    Time save = 0;
    std::string format;
    std::optional<Until> until;
    Time start = NegativeInfinity;
    Time end = PositiveInfinity;
    explicit ZoneLine(const Lines& fields) {
        standardOffset = parseStandardOffset(fields[0]);
        rulesText = fields[1];
        if (rulesText.front() >= '0' && rulesText.front() <= '9') save = parseSave(rulesText);
        else if (rulesText != "-") ruleSet = rulesText;
        format = fields[2];
        checkFormat(format, !ruleSet.empty());
        if (fields.size() > 3) until = parseUntil(Lines(fields.begin() + 3, fields.end()));
    }
    std::string rulesNotation() const { return ruleSet.empty() ? (rulesText == "-" ? "-" : clockText(save)) : ruleSet; }
    std::string untilNotation() const { return until->yearText + " " + until->monthText + " " + until->dayText + " " + clockText(until->time) + until->type; }
};
struct SourceLine {
    int number;
    Lines fields;
    std::string kind;
    std::optional<std::size_t> block;
    std::size_t position = 0;
    std::optional<ZoneLine> zoneLine;
    bool fieldError = false;
    std::string error;
    SourceLine(int line, const std::string& content) : number(line), fields(splitFields(content)) {
        if (content.front() == ' ') kind = "continuation";
        else if (fields[0] == "Rule" || fields[0] == "Zone" || fields[0] == "Link") kind = fields[0];
        else kind = "unknown";
    }
    bool acceptsContinuation() const { return (kind == "Zone" && fields.size() >= 6) || (kind == "continuation" && fields.size() >= 4); }
};
struct Block {
    std::string name;
    int number;
    std::vector<std::size_t> lines;
    bool defined = false;
};
struct Zone {
    std::string name;
    std::vector<ZoneLine> lines;
    Lines aliases;
    std::map<int, int> applied;
    Timeline timeline;
    Lines ruleSets() const {
        Lines result;
        for (const ZoneLine& line : lines) {
            if (!line.ruleSet.empty() && std::find(result.begin(), result.end(), line.ruleSet) == result.end()) result.push_back(line.ruleSet);
        }
        return result;
    }
    std::size_t lineNumberAt(Time value) const {
        for (std::size_t index = 0; index < lines.size(); ++index) if (lines[index].start <= value && value < lines[index].end) return index + 1;
        throw std::logic_error("missing zone line");
    }
};
static Rule parseRule(const SourceLine& line) {
    const Lines& fields = line.fields;
    Rule rule;
    rule.number = line.number;
    rule.fields = fields;
    rule.name = fields[1];
    rule.from = parseYear(fields[2]);
    rule.to = parseTo(fields[3], rule.from);
    if (fields[4] != "-") throw FieldError("syntax error");
    rule.month = parseMonth(fields[5]);
    rule.day = parseDaySpec(fields[6], rule.month);
    std::pair<Time, char> time = parseTime(fields[7]);
    rule.at = time.first;
    rule.atType = time.second;
    rule.save = parseSave(fields[8]);
    rule.letter = parseLetter(fields[9]);
    return rule;
}
class Database {
    void addToBlock(std::size_t block, std::size_t index) {
        lines[index].block = block;
        lines[index].position = blocks[block].lines.size();
        blocks[block].lines.push_back(index);
    }
    void assembleBlocks() {
        for (std::size_t index = 0; index < lines.size(); ++index) {
            SourceLine& line = lines[index];
            if (line.kind == "Zone") {
                blocks.push_back({line.fields[1], line.number, {}, false});
                addToBlock(blocks.size() - 1, index);
            } else if (line.kind == "continuation" && index && lines[index - 1].block && lines[index - 1].acceptsContinuation()) addToBlock(*lines[index - 1].block, index);
        }
    }
    void parseFields(SourceLine& line) {
        const std::string& kind = line.kind;
        std::size_t size = line.fields.size();
        if (kind == "unknown" || (kind == "continuation" && !line.block)) throw FieldError("syntax error");
        if ((kind == "Rule" && size != 10) || (kind == "Zone" && (size < 5 || size > 9)) || (kind == "continuation" && (size < 3 || size > 7)) || (kind == "Link" && size != 3)) throw FieldError("syntax error");
        if (kind == "Rule") {
            Rule rule = parseRule(line);
            if (!ruleSets.count(rule.name)) ruleOrder.push_back(rule.name);
            ruleSets[rule.name].push_back(rules.size());
            rules.push_back(std::move(rule));
        } else if (kind == "Zone") line.zoneLine.emplace(Lines(line.fields.begin() + 2, line.fields.end()));
        else if (kind == "continuation") line.zoneLine.emplace(line.fields);
    }
    std::string structuralError(SourceLine& line, std::set<std::string>& names) {
        const ZoneLine& zoneLine = *line.zoneLine;
        if (line.kind == "Zone" && !names.insert(line.fields[1]).second) return "duplicate zone " + line.fields[1];
        if (!zoneLine.ruleSet.empty() && !ruleSets.count(zoneLine.ruleSet)) return "unknown rule " + zoneLine.ruleSet;
        if (!zoneLine.until) return "";
        const Block& block = blocks[*line.block];
        if (line.kind == "continuation") {
            const SourceLine& previous = lines[block.lines[line.position - 1]];
            if (!previous.fieldError && zoneLine.until->value <= previous.zoneLine->until->value) return "until not increasing";
        }
        if (line.position + 1 == block.lines.size()) return "missing continuation";
        return "";
    }
    void defineZone(const Block& block) {
        Zone zone;
        zone.name = block.name;
        Time start = NegativeInfinity;
        for (std::size_t sourceIndex : block.lines) {
            ZoneLine line = *lines[sourceIndex].zoneLine;
            line.start = start;
            std::vector<std::pair<Time, std::pair<Time, std::string>>> switches;
            if (line.ruleSet.empty()) {
                if (line.until) line.end = line.until->value - adjustment(line.until->type, line.standardOffset, line.save);
                switches.push_back({start, {line.save, ""}});
            } else {
                const std::vector<RuleInstance>& instances = sequences.at(line.ruleSet);
                LineRun run = runInstances(rules, instances, line.standardOffset, start, line.until);
                line.end = run.end;
                Time save = 0;
                std::string letter;
                if (!run.preStart.empty()) {
                    const Rule& rule = rules[run.preStart.back()];
                    save = rule.save;
                    letter = rule.letter;
                } else {
                    for (const RuleInstance& instance : instances) if (rules[instance.rule].save == 0) { letter = rules[instance.rule].letter; break; }
                }
                switches.push_back({start, {save, letter}});
                for (const std::pair<Time, std::size_t>& instance : run.applied) {
                    const Rule& rule = rules[instance.second];
                    switches.push_back({instance.first, {rule.save, rule.letter}});
                    ++zone.applied[rule.number];
                }
            }
            for (const std::pair<Time, std::pair<Time, std::string>>& item : switches) {
                Period period{item.first, line.standardOffset + item.second.first, item.second.first != 0, abbreviation(line.format, item.second.first, item.second.second)};
                if (zone.timeline.periods.empty() || !period.sameState(zone.timeline.periods.back())) zone.timeline.periods.push_back(std::move(period));
            }
            start = line.end;
            zone.lines.push_back(std::move(line));
        }
        std::string name = zone.name;
        zones.emplace(name, std::move(zone));
    }
public:
    std::vector<SourceLine> lines;
    std::vector<Block> blocks;
    std::vector<Rule> rules;
    Lines ruleOrder;
    std::map<std::string, std::vector<std::size_t>> ruleSets;
    std::map<std::string, std::vector<RuleInstance>> sequences;
    std::map<std::string, Zone> zones;
    std::map<std::string, std::string> aliases;
    explicit Database(const Lines& rawLines) {
        for (std::size_t index = 0; index < rawLines.size(); ++index) {
            std::string content = lineContent(rawLines[index]);
            if (!content.empty()) lines.emplace_back(static_cast<int>(index + 1), content);
        }
        assembleBlocks();
        for (SourceLine& line : lines) {
            try { parseFields(line); }
            catch (const FieldError& error) { line.fieldError = true; line.error = error.what(); }
        }
        std::set<std::string> names;
        for (SourceLine& line : lines) if (line.zoneLine) line.error = structuralError(line, names);
        for (const std::string& name : ruleOrder) sequences[name] = instanceSequence(rules, ruleSets.at(name));
        for (Block& block : blocks) {
            block.defined = std::all_of(block.lines.begin(), block.lines.end(), [this](std::size_t index) { return lines[index].error.empty(); });
            if (block.defined) defineZone(block);
        }
        for (SourceLine& line : lines) if (line.kind == "Link" && line.error.empty()) {
            const std::string& target = line.fields[1];
            const std::string& alias = line.fields[2];
            if (!zones.count(target)) line.error = "unknown link target " + target;
            else if (zones.count(alias) || aliases.count(alias)) line.error = "duplicate link " + alias;
            else { aliases[alias] = target; zones.at(target).aliases.push_back(alias); }
        }
    }
    const Zone* findZone(const std::string& name) const {
        std::map<std::string, Zone>::const_iterator zone = zones.find(name);
        if (zone != zones.end()) return &zone->second;
        std::map<std::string, std::string>::const_iterator alias = aliases.find(name);
        return alias == aliases.end() ? nullptr : &zones.at(alias->second);
    }
    Lines errorLines() const {
        Lines errors;
        for (const SourceLine& line : lines) if (!line.error.empty()) errors.push_back("line " + std::to_string(line.number) + ": " + line.error);
        return errors;
    }
};
static Time offsetShift(const Timeline& timeline, std::size_t index) { return timeline.periods[index].offset - timeline.periods[index - 1].offset; }
static std::vector<std::size_t> transitionsBetween(const Timeline& timeline, Time low, Time high) {
    std::vector<std::size_t> indices;
    for (std::size_t index = 1; index < timeline.periods.size(); ++index) if (low <= timeline.periods[index].start && timeline.periods[index].start < high) indices.push_back(index);
    return indices;
}
static std::string changeAt(const Timeline& timeline, std::size_t index) { return changeText(timeline.periods[index].start, timeline.periods[index - 1], timeline.periods[index]); }
static std::string transitionLine(const Timeline& timeline, std::size_t index) {
    Time time = timeline.periods[index].start;
    Time shift = offsetShift(timeline, index);
    std::string kind = shift > 0 ? "gap " + durationText(shift) : shift < 0 ? "overlap " + durationText(-shift) : "no shift";
    return changeAt(timeline, index) + " (local " + localText(time + timeline.periods[index - 1].offset) + " -> " + localText(time + timeline.periods[index].offset) + ", " + kind + ")";
}
static std::string shiftsText(const Timeline& timeline, const std::vector<std::size_t>& indices) {
    std::size_t gaps = 0, overlaps = 0, unchanged = 0;
    for (std::size_t index : indices) {
        Time shift = offsetShift(timeline, index);
        if (shift > 0) ++gaps;
        else if (shift < 0) ++overlaps;
        else ++unchanged;
    }
    return "gaps " + std::to_string(gaps) + ", overlaps " + std::to_string(overlaps) + ", no shift " + std::to_string(unchanged);
}
static std::string candidateText(const Timeline& timeline, Time local, std::size_t index) {
    const Period& period = timeline.periods[index];
    return utText(local - period.offset) + " (" + stateText(period) + ")";
}
static std::optional<std::size_t> chosenCandidate(const std::vector<std::size_t>& candidates, const std::string& option) {
    if (candidates.size() == 1) return candidates[0];
    if (candidates.size() == 2 && option == "EARLIER") return candidates[0];
    if (candidates.size() == 2 && option == "LATER") return candidates[1];
    return std::nullopt;
}
static std::string unresolvedText(const Timeline& timeline, Time local, const std::vector<std::size_t>& candidates) {
    if (!candidates.empty()) return "AMBIGUOUS " + candidateText(timeline, local, candidates[0]) + " or " + candidateText(timeline, local, candidates[1]);
    std::size_t index = timeline.skippingTransition(local);
    Time time = timeline.periods[index].start;
    return "NONEXISTENT gap " + localText(time + timeline.periods[index - 1].offset) + " to " + localText(time + timeline.periods[index].offset) + " at " + utText(time);
}
static std::vector<Interval> workingHours(const Timeline& timeline, Time start, Time end) {
    std::vector<Interval> pieces;
    std::pair<std::size_t, std::size_t> range = timeline.nearby(start, end);
    for (std::size_t index = range.first; index <= range.second; ++index) {
        Time low = std::max(start - timeline.periods[index].offset, timeline.periods[index].start);
        Time high = std::min(end - timeline.periods[index].offset, timeline.endOf(index));
        if (low < high) pieces.emplace_back(low, high);
    }
    return mergeIntervals(pieces);
}
static std::optional<Time> parseValue(const std::string& kind, const std::string& word) {
    int year = std::stoi(word.substr(0, 4));
    if (year < 1800 || year > 2099) return std::nullopt;
    if (kind == "year") return year;
    int month = std::stoi(word.substr(5, 2));
    int day = std::stoi(word.substr(8, 2));
    if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return std::nullopt;
    if (kind == "date") return dayNumber(year, month, day);
    int hour = std::stoi(word.substr(11, 2));
    int minute = std::stoi(word.substr(14, 2));
    int second = std::stoi(word.substr(17, 2));
    if (hour > 23 || minute > 59 || second > 59) return std::nullopt;
    return timeValue(year, month, day, hour, minute, second);
}
struct QueryError : std::runtime_error { using std::runtime_error::runtime_error; };
class QueryRunner {
    const Database& database;
    Time workStart;
    Time workEnd;
    std::string answer(const std::string& line, const std::string& command, const Lines& words, const std::vector<const Zone*>& zones, const std::vector<Time>& values, const std::string& option) {
        if (command == "TOUTC" || command == "CONVERT") {
            Time local = values[command == "TOUTC" ? 1 : 2];
            const Timeline& timeline = zones[0]->timeline;
            std::vector<std::size_t> candidates = timeline.candidates(local);
            std::optional<std::size_t> chosen = chosenCandidate(candidates, option);
            if (!chosen) return unresolvedText(timeline, local, candidates);
            if (command == "TOUTC") return candidateText(timeline, local, *chosen);
            Time time = local - timeline.periods[*chosen].offset;
            const Period& target = zones[1]->timeline.periodAt(time);
            Time targetLocal = time + target.offset;
            Time shift = floorDivide(targetLocal, DaySeconds) - floorDivide(local, DaySeconds);
            return localText(targetLocal) + " (" + stateText(target) + ") at " + utText(time) + ", day shift " + (shift > 0 ? "+" : "") + std::to_string(shift);
        }
        if (command == "TOLOCAL") {
            const Period& period = zones[0]->timeline.periodAt(values[1]);
            return localText(values[1] + period.offset) + " (" + stateText(period) + ")";
        }
        if (command == "OFFSET") {
            const Timeline& timeline = zones[0]->timeline;
            std::size_t index = timeline.indexAt(values[1]);
            std::string text = stateText(timeline.periods[index]);
            if (index) text += " since " + utText(timeline.periods[index].start);
            if (index + 1 < timeline.periods.size()) text += " until " + utText(timeline.periods[index + 1].start);
            return text;
        }
        if (command == "TRANSITIONS") {
            if (values[1] > values[2]) throw QueryError("invalid range");
            const Timeline& timeline = zones[0]->timeline;
            std::vector<std::size_t> selected = transitionsBetween(timeline, yearStart(static_cast<int>(values[1])), yearStart(static_cast<int>(values[2]) + 1));
            Lines block{line};
            for (std::size_t index : selected) block.push_back(transitionLine(timeline, index));
            block.push_back(shiftsText(timeline, selected));
            transitionBlocks.push_back(std::move(block));
            return "transitions: " + std::to_string(selected.size());
        }
        if (command == "DURATION") {
            const Timeline& timeline = zones[0]->timeline;
            std::array<Time, 2> offsets{};
            for (std::size_t index = 0; index < 2; ++index) {
                std::vector<std::size_t> candidates = timeline.candidates(values[index + 1]);
                if (candidates.size() == 2) return "AMBIGUOUS " + words[index + 1];
                if (candidates.empty()) return "NONEXISTENT " + words[index + 1];
                offsets[index] = timeline.periods[candidates[0]].offset;
            }
            Time elapsed = (values[2] - offsets[1]) - (values[1] - offsets[0]);
            return std::to_string(elapsed) + " s (" + durationText(elapsed) + "), wall clock " + durationText(values[2] - values[1]) + ", offset change " + offsetText(offsets[1] - offsets[0]);
        }
        Time start = values[0] * DaySeconds + workStart;
        Time end = values[0] * DaySeconds + workEnd;
        std::vector<Interval> common = workingHours(zones[1]->timeline, start, end);
        for (std::size_t index = 2; index < zones.size(); ++index) common = intersectIntervals(common, workingHours(zones[index]->timeline, start, end));
        if (common.empty()) return "NONE";
        Lines pieces;
        for (const Interval& interval : common) {
            Lines members;
            for (std::size_t index = 1; index < zones.size(); ++index) {
                const Period& period = zones[index]->timeline.periodAt(interval.first);
                members.push_back(words[index] + " " + localText(interval.first + period.offset) + " " + period.abbreviation);
            }
            pieces.push_back(utText(interval.first) + " to " + utText(interval.second) + " (" + durationText(interval.second - interval.first) + ") [" + joined(members, ", ") + "]");
        }
        return joined(pieces, "; ");
    }
public:
    Lines answers;
    std::vector<Lines> transitionBlocks;
    QueryRunner(const Database& db, Time first, Time last) : database(db), workStart(first), workEnd(last) {}
    void run(const std::string& line) {
        Lines fields = splitFields(line);
        std::string command = fields[0];
        Lines words(fields.begin() + 1, fields.end());
        std::string option;
        if ((command == "TOUTC" || command == "CONVERT") && (words.back() == "EARLIER" || words.back() == "LATER")) { option = words.back(); words.pop_back(); }
        Lines kinds;
        if (command == "MEETING") { kinds.assign(words.size(), "zone"); kinds[0] = "date"; }
        else if (command == "CONVERT") kinds = {"zone", "zone", "local"};
        else if (command == "TRANSITIONS") kinds = {"zone", "year", "year"};
        else if (command == "DURATION") kinds = {"zone", "local", "local"};
        else kinds = {"zone", command == "TOUTC" ? "local" : "ut"};
        std::string result;
        try {
            std::vector<const Zone*> zones(words.size(), nullptr);
            std::vector<Time> values(words.size(), 0);
            for (std::size_t index = 0; index < words.size(); ++index) {
                if (kinds[index] == "zone") {
                    zones[index] = database.findZone(words[index]);
                    if (!zones[index]) throw QueryError("unknown zone " + words[index]);
                } else {
                    std::optional<Time> value = parseValue(kinds[index], words[index]);
                    if (!value) throw QueryError("invalid value " + words[index]);
                    values[index] = *value;
                }
            }
            result = answer(line, command, words, zones, values, option);
        } catch (const QueryError& error) { result = "ERROR " + std::string(error.what()); }
        answers.push_back(line + " => " + result);
    }
};
static std::string ruleText(const Rule& rule) {
    return "rule " + rule.name + " " + rule.fields[2] + " " + rule.fields[3] + " " + rule.fields[5] + " " + rule.fields[6] + " " + clockText(rule.at) + rule.atType + " " + clockText(rule.save) + " " + rule.fields[9];
}
static Lines databaseBlock(const Database& database) {
    std::size_t ruleCount = 0, validRules = 0, linkCount = 0, validLinks = 0, zoneLines = 0;
    for (const SourceLine& line : database.lines) {
        if (line.kind == "Rule") { ++ruleCount; if (line.error.empty()) ++validRules; }
        if (line.kind == "Link") { ++linkCount; if (line.error.empty()) ++validLinks; }
    }
    std::set<std::string> used;
    std::map<std::string, std::size_t> uses;
    for (const std::pair<const std::string, Zone>& entry : database.zones) {
        zoneLines += entry.second.lines.size();
        for (const std::string& name : entry.second.ruleSets()) { used.insert(name); ++uses[name]; }
    }
    Lines unused, invalid;
    for (const std::string& name : database.ruleOrder) if (!used.count(name)) unused.push_back(name);
    for (const Block& block : database.blocks) if (!block.defined) invalid.push_back(block.name + " (line " + std::to_string(block.number) + ")");
    Lines result{"DATABASE", "rule lines: " + std::to_string(validRules) + " valid, " + std::to_string(ruleCount - validRules) + " invalid", "zones: " + std::to_string(database.zones.size()) + " defined, " + std::to_string(database.blocks.size() - database.zones.size()) + " invalid", "zone lines: " + std::to_string(zoneLines) + " in defined zones", "links: " + std::to_string(validLinks) + " defined, " + std::to_string(linkCount - validLinks) + " invalid", "errors: " + std::to_string(database.errorLines().size()), "unused rules: " + joined(unused, " "), "invalid zones: " + joined(invalid, ", ")};
    for (const std::string& name : database.ruleOrder) {
        int first = 2099, last = 1800;
        bool maximum = false;
        const std::vector<std::size_t>& members = database.ruleSets.at(name);
        for (std::size_t index : members) {
            first = std::min(first, database.rules[index].from);
            last = std::max(last, database.rules[index].to);
            maximum = maximum || database.rules[index].fields[3] == "max";
        }
        result.push_back("rule set " + name + ": lines " + std::to_string(members.size()) + ", years " + std::to_string(first) + "-" + (maximum ? "max" : std::to_string(last)) + ", zones " + std::to_string(uses[name]));
    }
    return result;
}
static Lines dstLines(const Timeline& timeline, Time reference) {
    int year = splitTime(reference)[0];
    int minimum = 2100, maximum = 1799;
    std::vector<Interval> pieces;
    for (std::size_t index = 0; index < timeline.periods.size(); ++index) if (timeline.periods[index].dst) {
        int startYear = splitTime(timeline.periods[index].start)[0];
        minimum = std::min(minimum, startYear);
        maximum = std::max(maximum, startYear);
        Time start = std::max(yearStart(year), timeline.periods[index].start);
        Time end = std::min(yearStart(year + 1), timeline.endOf(index));
        if (start < end) pieces.emplace_back(start, end);
    }
    Lines result{maximum < minimum ? "dst years: none" : "dst years: " + std::to_string(minimum) + "-" + std::to_string(maximum)};
    Time total = 0;
    for (const Interval& interval : mergeIntervals(pieces)) {
        result.push_back("dst period: " + utText(interval.first) + " to " + utText(interval.second) + " (" + durationText(interval.second - interval.first) + ")");
        total += interval.second - interval.first;
    }
    result.push_back("dst total " + std::to_string(year) + ": " + durationText(total));
    return result;
}
static Lines zoneBlock(const Database& database, const Zone& zone, Time reference) {
    const Timeline& timeline = zone.timeline;
    Lines result{"ZONE " + zone.name, "aliases: " + joined(zone.aliases, " ")};
    for (std::size_t index = 0; index < zone.lines.size(); ++index) {
        const ZoneLine& line = zone.lines[index];
        std::string text = "line " + std::to_string(index + 1) + ": " + offsetText(line.standardOffset) + " " + line.rulesNotation() + " " + line.format;
        if (index) text += " from " + utText(line.start);
        if (line.until) text += " until " + line.untilNotation() + " = " + utText(line.end);
        result.push_back(text + ", transitions " + std::to_string(transitionsBetween(timeline, line.start, line.end).size()));
    }
    for (const std::string& name : zone.ruleSets()) for (std::size_t index : database.ruleSets.at(name)) {
        const Rule& rule = database.rules[index];
        std::map<int, int>::const_iterator count = zone.applied.find(rule.number);
        result.push_back(ruleText(rule) + ", applied " + std::to_string(count == zone.applied.end() ? 0 : count->second));
    }
    Time minimum = timeline.periods[0].offset, maximum = minimum;
    Lines states;
    std::vector<std::size_t> counts;
    for (const Period& period : timeline.periods) {
        minimum = std::min(minimum, period.offset);
        maximum = std::max(maximum, period.offset);
        std::string state = stateText(period);
        Lines::const_iterator found = std::find(states.cbegin(), states.cend(), state);
        if (found == states.cend()) { states.push_back(state); counts.push_back(1); }
        else ++counts[static_cast<std::size_t>(found - states.cbegin())];
    }
    result.push_back("offset range: " + offsetText(minimum) + " to " + offsetText(maximum));
    for (std::size_t index = 0; index < states.size(); ++index) result.push_back("state " + states[index] + ", periods " + std::to_string(counts[index]));
    std::size_t index = timeline.indexAt(reference);
    const Period& period = timeline.periods[index];
    result.push_back("reference: " + localText(reference + period.offset) + " (" + stateText(period) + "), line " + std::to_string(zone.lineNumberAt(reference)));
    result.push_back("previous transition: " + (index ? changeAt(timeline, index) : "none"));
    result.push_back("next transition: " + (index + 1 < timeline.periods.size() ? changeAt(timeline, index + 1) : "none"));
    std::vector<std::size_t> every = transitionsBetween(timeline, NegativeInfinity, PositiveInfinity);
    result.push_back("transitions: " + std::to_string(every.size()) + ", " + shiftsText(timeline, every));
    Lines dst = dstLines(timeline, reference);
    result.insert(result.end(), dst.begin(), dst.end());
    return result;
}
int main() {
    Database database(readLines("input/tzdata.txt"));
    Lines parameters = readLines("input/params.txt");
    Time reference = *parseValue("ut", splitFields(parameters[0])[1]);
    Lines workday = splitFields(parameters[1]);
    Time workStart = std::stoi(workday[1].substr(0, 2)) * 3600 + std::stoi(workday[1].substr(3, 2)) * 60;
    Time workEnd = std::stoi(workday[2].substr(0, 2)) * 3600 + std::stoi(workday[2].substr(3, 2)) * 60;
    QueryRunner runner(database, workStart, workEnd);
    for (const std::string& line : readLines("input/queries.txt")) runner.run(line);
    std::vector<Lines> blocks{indented(databaseBlock(database))};
    for (const std::pair<const std::string, Zone>& entry : database.zones) blocks.push_back(indented(zoneBlock(database, entry.second, reference)));
    std::filesystem::create_directories("output");
    writeLines("output/answers.txt", runner.answers);
    writeLines("output/errors.txt", database.errorLines());
    writeBlocks("output/transitions.txt", runner.transitionBlocks);
    writeBlocks("output/zone_summary.txt", blocks);
}
