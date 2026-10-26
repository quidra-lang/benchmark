import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public final class Main {
    record Range(long low, long high) {}
    static final class QueryError extends RuntimeException { QueryError(String message) { super(message); } }

    static List<String> read(String name) throws IOException { return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII); }
    static long yearStart(int year) { return DayRules.dayNumber(year, 1, 1) * DayRules.DAY; }
    static long clockSeconds(String text) { return Long.parseLong(text.substring(0, 2)) * 3600 + Long.parseLong(text.substring(3, 5)) * 60; }
    static String namesOrNone(List<String> names, String separator) { return names.isEmpty() ? "none" : String.join(separator, names); }

    static List<String> indented(List<String> lines) {
        List<String> result = new ArrayList<>();
        for (int i = 0; i < lines.size(); i++) result.add((i == 0 ? "" : "  ") + lines.get(i));
        return result;
    }

    static List<Range> mergeIntervals(List<Range> intervals) {
        List<Range> ordered = new ArrayList<>(intervals), result = new ArrayList<>();
        ordered.sort(Comparator.comparingLong(Range::low).thenComparingLong(Range::high));
        for (Range range : ordered) {
            if (!result.isEmpty() && range.low <= result.getLast().high) {
                Range previous = result.removeLast(); result.add(new Range(previous.low, Math.max(previous.high, range.high)));
            } else result.add(range);
        }
        return result;
    }

    static List<Range> intersectIntervals(List<Range> first, List<Range> second) {
        List<Range> pieces = new ArrayList<>();
        for (Range one : first) for (Range other : second) {
            long low = Math.max(one.low, other.low), high = Math.min(one.high, other.high);
            if (low < high) pieces.add(new Range(low, high));
        }
        return mergeIntervals(pieces);
    }

    static final class SourceLine {
        final int number;
        final String[] fields;
        final String kind;
        Block block;
        int position;
        ZoneLine zoneLine;
        boolean fieldError;
        String error;

        SourceLine(int number, String content) {
            this.number = number;
            fields = TzParser.fields(content);
            kind = TzParser.continuation(content) ? "continuation" : Set.of("Rule", "Zone", "Link").contains(fields[0]) ? fields[0] : "unknown";
        }
        boolean acceptsContinuation() { return kind.equals("Zone") ? fields.length >= 6 : kind.equals("continuation") && fields.length >= 4; }
    }

    static final class Block {
        final String name;
        final int number;
        final List<SourceLine> lines = new ArrayList<>();
        boolean defined;
        Block(SourceLine first) { name = first.fields[1]; number = first.number; add(first); }
        void add(SourceLine line) { line.block = this; line.position = lines.size(); lines.add(line); }
    }

    static final class ZoneLine {
        final long stdoff;
        final String rulesText, ruleSet, format;
        final long save;
        final TzParser.Until until;
        long start = DayRules.NEG_INFINITY, end = DayRules.POS_INFINITY;

        ZoneLine(String[] fields) {
            stdoff = TzParser.offset(fields[0]);
            rulesText = fields[1];
            if (rulesText.charAt(0) >= '0' && rulesText.charAt(0) <= '9') { save = TzParser.save(rulesText); ruleSet = null; }
            else { save = 0; ruleSet = rulesText.equals("-") ? null : rulesText; }
            format = fields[2];
            TzParser.checkFormat(format, ruleSet != null);
            until = fields.length > 3 ? TzParser.until(Arrays.copyOfRange(fields, 3, fields.length)) : null;
        }
        String rulesNotation() { return ruleSet != null ? ruleSet : rulesText.equals("-") ? "-" : Report.clock(save); }
        String untilNotation() { return until.yearText() + " " + until.monthText() + " " + until.dayText() + " " + Report.clock(until.time()) + until.type(); }
    }

    static final class Zone {
        final String name;
        final List<ZoneLine> lines;
        final List<String> aliases = new ArrayList<>();
        final Map<Integer, Integer> applied = new HashMap<>();
        Resolver.Timeline timeline;
        Zone(String name, List<ZoneLine> lines) { this.name = name; this.lines = lines; }
        List<String> ruleSets() {
            List<String> names = new ArrayList<>();
            for (ZoneLine line : lines) if (line.ruleSet != null && !names.contains(line.ruleSet)) names.add(line.ruleSet);
            return names;
        }
        int lineNumberAt(long time) {
            for (int i = 0; i < lines.size(); i++) if (lines.get(i).start <= time && time < lines.get(i).end) return i + 1;
            throw new IllegalStateException();
        }
    }

    static Transitions.Rule parseRule(SourceLine line) {
        String[] fields = line.fields;
        int from = TzParser.year(fields[2]), to = TzParser.toYear(fields[3], from);
        if (!fields[4].equals("-")) throw new TzParser.FieldError("syntax error");
        int month = TzParser.month(fields[5]);
        DayRules.DaySpec day = TzParser.day(fields[6], month);
        TzParser.Time time = TzParser.time(fields[7]);
        long save = TzParser.save(fields[8]);
        String letter = TzParser.letter(fields[9]);
        return new Transitions.Rule(line.number, fields, from, to, month, day, time.value(), time.type(), save, letter);
    }

    static final class Database {
        final List<SourceLine> lines = new ArrayList<>();
        final List<Block> blocks = new ArrayList<>();
        final Map<String, List<Transitions.Rule>> rules = new LinkedHashMap<>();
        final Map<String, List<Transitions.Instance>> sequences = new HashMap<>();
        final Map<String, Zone> zones = new LinkedHashMap<>(), aliases = new HashMap<>();

        Database(List<String> rawLines) {
            for (int i = 0; i < rawLines.size(); i++) { String content = TzParser.content(rawLines.get(i)); if (!content.isEmpty()) lines.add(new SourceLine(i + 1, content)); }
            SourceLine previous = null;
            for (SourceLine line : lines) {
                if (line.kind.equals("Zone")) blocks.add(new Block(line));
                else if (line.kind.equals("continuation") && previous != null && previous.block != null && previous.acceptsContinuation()) previous.block.add(line);
                previous = line;
            }
            for (SourceLine line : lines) {
                try { parseFields(line); }
                catch (TzParser.FieldError error) { line.fieldError = true; line.error = error.getMessage(); }
            }
            Set<String> zoneNames = new HashSet<>();
            for (SourceLine line : lines) if (line.zoneLine != null) line.error = structuralError(line, zoneNames);
            for (var entry : rules.entrySet()) sequences.put(entry.getKey(), Transitions.instances(entry.getValue()));
            for (Block block : blocks) { block.defined = block.lines.stream().allMatch(line -> line.error == null); if (block.defined) defineZone(block); }
            for (SourceLine line : lines) if (line.kind.equals("Link") && line.error == null) registerLink(line);
        }

        void parseFields(SourceLine line) {
            int low, high;
            switch (line.kind) {
                case "Rule" -> { low = high = 10; }
                case "Zone" -> { low = 5; high = 9; }
                case "continuation" -> { if (line.block == null) throw new TzParser.FieldError("syntax error"); low = 3; high = 7; }
                case "Link" -> { low = high = 3; }
                default -> throw new TzParser.FieldError("syntax error");
            }
            if (line.fields.length < low || line.fields.length > high) throw new TzParser.FieldError("syntax error");
            if (line.kind.equals("Rule")) { Transitions.Rule rule = parseRule(line); rules.computeIfAbsent(rule.name(), key -> new ArrayList<>()).add(rule); }
            else if (line.kind.equals("Zone")) line.zoneLine = new ZoneLine(Arrays.copyOfRange(line.fields, 2, line.fields.length));
            else if (line.kind.equals("continuation")) line.zoneLine = new ZoneLine(line.fields);
        }

        String structuralError(SourceLine line, Set<String> zoneNames) {
            ZoneLine value = line.zoneLine;
            if (line.kind.equals("Zone") && !zoneNames.add(line.fields[1])) return "duplicate zone " + line.fields[1];
            if (value.ruleSet != null && !rules.containsKey(value.ruleSet)) return "unknown rule " + value.ruleSet;
            if (value.until == null) return null;
            if (line.kind.equals("continuation")) {
                SourceLine previous = line.block.lines.get(line.position - 1);
                if (!previous.fieldError && value.until.value() <= previous.zoneLine.until.value()) return "until not increasing";
            }
            return line.position == line.block.lines.size() - 1 ? "missing continuation" : null;
        }

        void defineZone(Block block) {
            Zone zone = new Zone(block.name, block.lines.stream().map(line -> line.zoneLine).toList());
            List<Resolver.Period> switches = new ArrayList<>();
            long start = DayRules.NEG_INFINITY;
            for (ZoneLine line : zone.lines) {
                line.start = start;
                for (Transitions.Switch value : lineSwitches(zone, line)) switches.add(new Resolver.Period(value.time(), line.stdoff + value.save(), value.save() != 0, Transitions.abbreviation(line.format, value.save(), value.letter())));
                start = line.end;
            }
            List<Resolver.Period> periods = new ArrayList<>();
            for (Resolver.Period period : switches) if (periods.isEmpty() || !periods.getLast().sameState(period)) periods.add(period);
            zone.timeline = new Resolver.Timeline(periods);
            zones.put(zone.name, zone);
        }

        List<Transitions.Switch> lineSwitches(Zone zone, ZoneLine line) {
            if (line.ruleSet == null) {
                if (line.until != null) line.end = line.until.value() - Transitions.adjustment(line.until.type(), line.stdoff, line.save);
                return List.of(new Transitions.Switch(line.start, line.save, ""));
            }
            List<Transitions.Instance> instances = sequences.get(line.ruleSet);
            Transitions.LineRun run = Transitions.run(instances, line.stdoff, line.start, line.until);
            line.end = run.end;
            long save = 0;
            String letter = "";
            if (!run.preStart.isEmpty()) { Transitions.Rule last = run.preStart.getLast(); save = last.save(); letter = last.letter(); }
            else for (Transitions.Instance instance : instances) if (instance.rule().save() == 0) { letter = instance.rule().letter(); break; }
            List<Transitions.Switch> switches = new ArrayList<>(List.of(new Transitions.Switch(line.start, save, letter)));
            for (Transitions.Applied value : run.applied) {
                switches.add(new Transitions.Switch(value.time(), value.rule().save(), value.rule().letter()));
                zone.applied.merge(value.rule().number(), 1, Integer::sum);
            }
            return switches;
        }

        void registerLink(SourceLine line) {
            String target = line.fields[1], alias = line.fields[2];
            if (!zones.containsKey(target)) line.error = "unknown link target " + target;
            else if (zones.containsKey(alias) || aliases.containsKey(alias)) line.error = "duplicate link " + alias;
            else { aliases.put(alias, zones.get(target)); zones.get(target).aliases.add(alias); }
        }
        Zone findZone(String name) { return zones.containsKey(name) ? zones.get(name) : aliases.get(name); }
        List<String> errorLines() { return lines.stream().filter(line -> line.error != null).map(line -> "line " + line.number + ": " + line.error).toList(); }
    }

    static long offsetShift(Resolver.Timeline timeline, int index) { return timeline.periods.get(index).offset() - timeline.periods.get(index - 1).offset(); }
    static List<Integer> transitionsBetween(Resolver.Timeline timeline, long low, long high) {
        List<Integer> indices = new ArrayList<>();
        for (int i = 1; i < timeline.periods.size(); i++) if (low <= timeline.periods.get(i).start() && timeline.periods.get(i).start() < high) indices.add(i);
        return indices;
    }
    static String changeAt(Resolver.Timeline timeline, int index) { return Report.change(timeline.periods.get(index).start(), timeline.periods.get(index - 1), timeline.periods.get(index)); }
    static String transitionLine(Resolver.Timeline timeline, int index) {
        long time = timeline.periods.get(index).start(), shift = offsetShift(timeline, index);
        String kind = shift > 0 ? "gap " + Report.duration(shift) : shift < 0 ? "overlap " + Report.duration(-shift) : "no shift";
        return changeAt(timeline, index) + " (local " + Report.local(time + timeline.periods.get(index - 1).offset()) + " -> " + Report.local(time + timeline.periods.get(index).offset()) + ", " + kind + ")";
    }
    static String shiftsText(Resolver.Timeline timeline, List<Integer> indices) {
        int gaps = 0, overlaps = 0, unchanged = 0;
        for (int index : indices) { long shift = offsetShift(timeline, index); if (shift > 0) gaps++; else if (shift < 0) overlaps++; else unchanged++; }
        return "gaps " + gaps + ", overlaps " + overlaps + ", no shift " + unchanged;
    }
    static String candidateText(Resolver.Timeline timeline, long local, int index) { Resolver.Period period = timeline.periods.get(index); return Report.ut(local - period.offset()) + " (" + Report.state(period) + ")"; }
    static Integer chosenCandidate(List<Integer> candidates, String option) {
        if (candidates.size() == 1 || candidates.size() == 2 && "EARLIER".equals(option)) return candidates.getFirst();
        return candidates.size() == 2 && "LATER".equals(option) ? candidates.get(1) : null;
    }
    static String unresolvedText(Resolver.Timeline timeline, long local, List<Integer> candidates) {
        if (!candidates.isEmpty()) return "AMBIGUOUS " + String.join(" or ", candidates.stream().map(index -> candidateText(timeline, local, index)).toList());
        int index = timeline.skippingTransition(local);
        long time = timeline.periods.get(index).start();
        return "NONEXISTENT gap " + Report.local(time + timeline.periods.get(index - 1).offset()) + " to " + Report.local(time + timeline.periods.get(index).offset()) + " at " + Report.ut(time);
    }
    static List<Range> workingHours(Resolver.Timeline timeline, long start, long end) {
        List<Range> pieces = new ArrayList<>();
        for (int i = timeline.nearbyFirst(start); i <= timeline.nearbyLast(end); i++) {
            long offset = timeline.periods.get(i).offset(), low = Math.max(start - offset, timeline.periods.get(i).start()), high = Math.min(end - offset, timeline.endOf(i));
            if (low < high) pieces.add(new Range(low, high));
        }
        return mergeIntervals(pieces);
    }
    static Long parseValue(String kind, String word) {
        int year = Integer.parseInt(word.substring(0, 4));
        if (year < 1800 || year > 2099) return null;
        if (kind.equals("year")) return (long) year;
        int month = Integer.parseInt(word.substring(5, 7)), day = Integer.parseInt(word.substring(8, 10));
        if (month < 1 || month > 12 || day < 1 || day > DayRules.daysInMonth(year, month)) return null;
        if (kind.equals("date")) return DayRules.dayNumber(year, month, day);
        int hour = Integer.parseInt(word.substring(11, 13)), minute = Integer.parseInt(word.substring(14, 16)), second = Integer.parseInt(word.substring(17, 19));
        return hour > 23 || minute > 59 || second > 59 ? null : DayRules.timeValue(year, month, day, hour, minute, second);
    }

    static final class QueryRunner {
        final Database database;
        final long workStart, workEnd;
        final List<String> answers = new ArrayList<>();
        final List<List<String>> transitionBlocks = new ArrayList<>();
        QueryRunner(Database database, long start, long end) { this.database = database; workStart = start; workEnd = end; }

        void run(String line) {
            String[] words = line.split(" ");
            String command = words[0], option = null;
            List<String> arguments = new ArrayList<>(Arrays.asList(words).subList(1, words.length));
            if ((command.equals("TOUTC") || command.equals("CONVERT")) && Set.of("EARLIER", "LATER").contains(arguments.getLast())) option = arguments.removeLast();
            List<String> kinds = switch (command) {
                case "TOUTC" -> List.of("zone", "local");
                case "TOLOCAL", "OFFSET" -> List.of("zone", "ut");
                case "CONVERT" -> List.of("zone", "zone", "local");
                case "TRANSITIONS" -> List.of("zone", "year", "year");
                case "DURATION" -> List.of("zone", "local", "local");
                default -> { List<String> result = new ArrayList<>(List.of("date")); for (int i = 1; i < arguments.size(); i++) result.add("zone"); yield result; }
            };
            String result;
            try {
                List<Object> values = new ArrayList<>();
                for (int i = 0; i < arguments.size(); i++) {
                    String kind = kinds.get(i), word = arguments.get(i);
                    if (kind.equals("zone")) { Zone zone = database.findZone(word); if (zone == null) throw new QueryError("unknown zone " + word); values.add(zone); }
                    else { Long value = parseValue(kind, word); if (value == null) throw new QueryError("invalid value " + word); values.add(value); }
                }
                result = answer(line, command, values, arguments, option);
            } catch (QueryError error) { result = "ERROR " + error.getMessage(); }
            answers.add(line + " => " + result);
        }

        String answer(String line, String command, List<Object> values, List<String> arguments, String option) {
            if (command.equals("MEETING")) {
                List<Zone> zones = new ArrayList<>(); for (int i = 1; i < values.size(); i++) zones.add((Zone) values.get(i));
                return meeting((long) values.get(0), zones, arguments.subList(1, arguments.size()));
            }
            Zone zone = (Zone) values.get(0);
            if (command.equals("TOUTC")) return toUtc(zone, (long) values.get(1), option);
            if (command.equals("TOLOCAL")) return toLocal(zone, (long) values.get(1));
            if (command.equals("CONVERT")) return convert(zone, (Zone) values.get(1), (long) values.get(2), option);
            if (command.equals("OFFSET")) return offset(zone, (long) values.get(1));
            if (command.equals("TRANSITIONS")) return transitions(line, zone, (int) (long) values.get(1), (int) (long) values.get(2));
            return duration(zone, (long) values.get(1), (long) values.get(2), arguments.subList(1, arguments.size()));
        }
        String toUtc(Zone zone, long local, String option) {
            List<Integer> candidates = zone.timeline.candidates(local); Integer index = chosenCandidate(candidates, option);
            return index == null ? unresolvedText(zone.timeline, local, candidates) : candidateText(zone.timeline, local, index);
        }
        String toLocal(Zone zone, long time) { Resolver.Period period = zone.timeline.periodAt(time); return Report.local(time + period.offset()) + " (" + Report.state(period) + ")"; }
        String convert(Zone source, Zone target, long local, String option) {
            List<Integer> candidates = source.timeline.candidates(local); Integer index = chosenCandidate(candidates, option);
            if (index == null) return unresolvedText(source.timeline, local, candidates);
            long time = local - source.timeline.periods.get(index).offset(); Resolver.Period period = target.timeline.periodAt(time);
            long targetLocal = time + period.offset(), shift = Math.floorDiv(targetLocal, DayRules.DAY) - Math.floorDiv(local, DayRules.DAY);
            return Report.local(targetLocal) + " (" + Report.state(period) + ") at " + Report.ut(time) + ", day shift " + (shift > 0 ? "+" : "") + shift;
        }
        String offset(Zone zone, long time) {
            Resolver.Timeline timeline = zone.timeline; int index = timeline.indexAt(time); String text = Report.state(timeline.periods.get(index));
            if (index >= 1) text += " since " + Report.ut(timeline.periods.get(index).start());
            if (index + 1 < timeline.periods.size()) text += " until " + Report.ut(timeline.periods.get(index + 1).start());
            return text;
        }
        String transitions(String line, Zone zone, int first, int last) {
            if (first > last) throw new QueryError("invalid range");
            List<Integer> selected = transitionsBetween(zone.timeline, yearStart(first), yearStart(last + 1));
            List<String> block = new ArrayList<>(List.of(line));
            for (int index : selected) block.add(transitionLine(zone.timeline, index));
            block.add(shiftsText(zone.timeline, selected)); transitionBlocks.add(block);
            return "transitions: " + selected.size();
        }
        String duration(Zone zone, long first, long second, List<String> words) {
            Resolver.Period[] periods = new Resolver.Period[2]; long[] locals = {first, second};
            for (int i = 0; i < 2; i++) {
                List<Integer> candidates = zone.timeline.candidates(locals[i]);
                if (candidates.size() == 2) return "AMBIGUOUS " + words.get(i);
                if (candidates.isEmpty()) return "NONEXISTENT " + words.get(i);
                periods[i] = zone.timeline.periods.get(candidates.getFirst());
            }
            long elapsed = (second - periods[1].offset()) - (first - periods[0].offset()), change = periods[1].offset() - periods[0].offset();
            return elapsed + " s (" + Report.duration(elapsed) + "), wall clock " + Report.duration(second - first) + ", offset change " + Report.offset(change);
        }
        String meeting(long day, List<Zone> zones, List<String> words) {
            long start = day * DayRules.DAY + workStart, end = day * DayRules.DAY + workEnd;
            List<Range> common = workingHours(zones.getFirst().timeline, start, end);
            for (int i = 1; i < zones.size(); i++) common = intersectIntervals(common, workingHours(zones.get(i).timeline, start, end));
            List<String> parts = new ArrayList<>();
            for (Range range : common) {
                List<String> members = new ArrayList<>();
                for (int i = 0; i < zones.size(); i++) { Resolver.Period period = zones.get(i).timeline.periodAt(range.low); members.add(words.get(i) + " " + Report.local(range.low + period.offset()) + " " + period.abbreviation()); }
                parts.add(Report.ut(range.low) + " to " + Report.ut(range.high) + " (" + Report.duration(range.high - range.low) + ") [" + String.join(", ", members) + "]");
            }
            return parts.isEmpty() ? "NONE" : String.join("; ", parts);
        }
    }

    static String ruleText(Transitions.Rule rule) {
        String[] fields = rule.fields();
        return "rule " + rule.name() + " " + fields[2] + " " + fields[3] + " " + fields[5] + " " + fields[6] + " " + Report.clock(rule.at()) + rule.type() + " " + Report.clock(rule.save()) + " " + fields[9];
    }
    static List<String> databaseBlock(Database database) {
        long ruleLines = database.lines.stream().filter(line -> line.kind.equals("Rule")).count(), linkLines = database.lines.stream().filter(line -> line.kind.equals("Link")).count();
        long validRules = database.lines.stream().filter(line -> line.kind.equals("Rule") && line.error == null).count(), validLinks = database.lines.stream().filter(line -> line.kind.equals("Link") && line.error == null).count();
        Set<String> used = new HashSet<>(); for (Zone zone : database.zones.values()) used.addAll(zone.ruleSets());
        List<String> unused = database.rules.keySet().stream().filter(name -> !used.contains(name)).toList();
        List<String> invalid = database.blocks.stream().filter(block -> !block.defined).map(block -> block.name + " (line " + block.number + ")").toList();
        List<String> lines = new ArrayList<>(List.of("DATABASE", "rule lines: " + validRules + " valid, " + (ruleLines - validRules) + " invalid", "zones: " + database.zones.size() + " defined, " + (database.blocks.size() - database.zones.size()) + " invalid",
            "zone lines: " + database.zones.values().stream().mapToInt(zone -> zone.lines.size()).sum() + " in defined zones", "links: " + validLinks + " defined, " + (linkLines - validLinks) + " invalid", "errors: " + database.errorLines().size(), "unused rules: " + namesOrNone(unused, " "), "invalid zones: " + namesOrNone(invalid, ", ")));
        for (var entry : database.rules.entrySet()) {
            List<Transitions.Rule> rules = entry.getValue(); int first = rules.stream().mapToInt(Transitions.Rule::fromYear).min().orElseThrow();
            String last = rules.stream().anyMatch(rule -> rule.fields()[3].equals("max")) ? "max" : Integer.toString(rules.stream().mapToInt(Transitions.Rule::toYear).max().orElseThrow());
            long count = database.zones.values().stream().filter(zone -> zone.ruleSets().contains(entry.getKey())).count();
            lines.add("rule set " + entry.getKey() + ": lines " + rules.size() + ", years " + first + "-" + last + ", zones " + count);
        }
        return lines;
    }
    static List<String> dstLines(Resolver.Timeline timeline, long reference) {
        List<Integer> indices = new ArrayList<>(); for (int i = 0; i < timeline.periods.size(); i++) if (timeline.periods.get(i).dst()) indices.add(i);
        List<String> lines = new ArrayList<>();
        if (indices.isEmpty()) lines.add("dst years: none");
        else { int first = Integer.MAX_VALUE, last = Integer.MIN_VALUE; for (int i : indices) { int year = DayRules.splitTime(timeline.periods.get(i).start())[0]; first = Math.min(first, year); last = Math.max(last, year); } lines.add("dst years: " + first + "-" + last); }
        int year = DayRules.splitTime(reference)[0]; long low = yearStart(year), high = yearStart(year + 1), total = 0;
        List<Range> pieces = new ArrayList<>();
        for (int index : indices) { long start = Math.max(low, timeline.periods.get(index).start()), end = Math.min(high, timeline.endOf(index)); if (start < end) pieces.add(new Range(start, end)); }
        for (Range range : mergeIntervals(pieces)) { lines.add("dst period: " + Report.ut(range.low) + " to " + Report.ut(range.high) + " (" + Report.duration(range.high - range.low) + ")"); total += range.high - range.low; }
        lines.add("dst total " + year + ": " + Report.duration(total));
        return lines;
    }
    static List<String> zoneBlock(Database database, Zone zone, long reference) {
        Resolver.Timeline timeline = zone.timeline; List<Resolver.Period> periods = timeline.periods;
        List<String> lines = new ArrayList<>(List.of("ZONE " + zone.name, "aliases: " + namesOrNone(zone.aliases, " ")));
        for (int i = 0; i < zone.lines.size(); i++) {
            ZoneLine value = zone.lines.get(i); String text = "line " + (i + 1) + ": " + Report.offset(value.stdoff) + " " + value.rulesNotation() + " " + value.format;
            if (i >= 1) text += " from " + Report.ut(value.start);
            if (value.until != null) text += " until " + value.untilNotation() + " = " + Report.ut(value.end);
            lines.add(text + ", transitions " + transitionsBetween(timeline, value.start, value.end).size());
        }
        for (String name : zone.ruleSets()) for (Transitions.Rule rule : database.rules.get(name)) lines.add(ruleText(rule) + ", applied " + zone.applied.getOrDefault(rule.number(), 0));
        long min = periods.stream().mapToLong(Resolver.Period::offset).min().orElseThrow(), max = periods.stream().mapToLong(Resolver.Period::offset).max().orElseThrow();
        lines.add("offset range: " + Report.offset(min) + " to " + Report.offset(max));
        Map<String, Integer> states = new LinkedHashMap<>(); for (Resolver.Period period : periods) states.merge(Report.state(period), 1, Integer::sum);
        for (var entry : states.entrySet()) lines.add("state " + entry.getKey() + ", periods " + entry.getValue());
        int index = timeline.indexAt(reference); Resolver.Period period = periods.get(index);
        lines.add("reference: " + Report.local(reference + period.offset()) + " (" + Report.state(period) + "), line " + zone.lineNumberAt(reference));
        lines.add("previous transition: " + (index >= 1 ? changeAt(timeline, index) : "none"));
        lines.add("next transition: " + (index + 1 < periods.size() ? changeAt(timeline, index + 1) : "none"));
        List<Integer> every = new ArrayList<>(); for (int i = 1; i < periods.size(); i++) every.add(i);
        lines.add("transitions: " + every.size() + ", " + shiftsText(timeline, every)); lines.addAll(dstLines(timeline, reference));
        return lines;
    }

    public static void main(String[] args) throws IOException {
        Database database = new Database(read("tzdata.txt")); List<String> parameters = read("params.txt");
        long reference = parseValue("ut", parameters.get(0).split(" ")[1]); String[] workday = parameters.get(1).split(" ");
        QueryRunner runner = new QueryRunner(database, clockSeconds(workday[1]), clockSeconds(workday[2]));
        for (String line : read("queries.txt")) runner.run(line);
        List<List<String>> blocks = new ArrayList<>(List.of(indented(databaseBlock(database))));
        for (String name : new TreeSet<>(database.zones.keySet())) blocks.add(indented(zoneBlock(database, database.zones.get(name), reference)));
        Files.createDirectories(Path.of("output"));
        Report.writeLines("answers.txt", runner.answers); Report.writeLines("errors.txt", database.errorLines());
        Report.writeBlocks("transitions.txt", runner.transitionBlocks); Report.writeBlocks("zone_summary.txt", blocks);
    }
}
