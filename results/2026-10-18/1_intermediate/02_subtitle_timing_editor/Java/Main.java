import java.io.*;
import java.util.*;
import java.util.regex.Pattern;
import java.util.stream.IntStream;

public class Main {
    record Cue(long index, long start, long end, List<String> text) {
        long duration() { return end-start; }
        long chars() { return text.stream().mapToLong(String::length).sum(); }
        boolean dialogue() { return text.stream().anyMatch(s -> s.startsWith("- ")); }
    }
    record Undo(String command, List<Cue> cues) {}
    record Item(String text, int kind, int digit) {}
    static class Problem extends RuntimeException {
        Problem(String message) { super(message); }
    }
    List<Cue> cues = new ArrayList<>();
    final Deque<Undo> history = new ArrayDeque<>();
    static final Map<String,String> SCHEMAS = Map.ofEntries(
        Map.entry("LIST",""),Map.entry("VALIDATE",""),Map.entry("SEARCH","X"),Map.entry("AT","T"),
        Map.entry("GAPS","g"),Map.entry("STATS",""),Map.entry("PRINT",""),Map.entry("TOVTT",""),
        Map.entry("TOASS",""),Map.entry("FRAMES","F"),Map.entry("SHIFT","I"),Map.entry("SHIFTFROM","PI"),
        Map.entry("SCALE","rr"),Map.entry("SYNC","PTPT"),Map.entry("SNAP","F"),Map.entry("FIXOVERLAP","g"),
        Map.entry("EXTEND","e"),Map.entry("TIME","PTT"),Map.entry("SORT",""),Map.entry("RENUMBER",""),
        Map.entry("MERGE","g"),Map.entry("SPLIT","w"),Map.entry("INSERT","PTTX"),Map.entry("DELETE","P"),
        Map.entry("TEXT","PX"),Map.entry("BALANCE",""),Map.entry("STRIP",""),Map.entry("CLEANHI",""),
        Map.entry("REPLACE","X"),Map.entry("UNDO",""));
    static final Set<String> MODIFY = Set.of("SHIFT","SHIFTFROM","SCALE","SYNC","SNAP","FIXOVERLAP",
        "EXTEND","TIME","SORT","RENUMBER","MERGE","SPLIT","INSERT","DELETE","TEXT","BALANCE","STRIP","CLEANHI","REPLACE");
    static void bad() { throw new Problem("bad arguments"); }
    static long number(String s) {
        if (!s.matches("[0-9]{1,9}")) bad();
        return Long.parseLong(s);
    }
    static long time(String s) {
        if (!s.matches("[0-9]{2}:[0-5][0-9]:[0-5][0-9],[0-9]{3}")) bad();
        return Long.parseLong(s.substring(0,2))*3600000+Long.parseLong(s.substring(3,5))*60000+
            Long.parseLong(s.substring(6,8))*1000+Long.parseLong(s.substring(9));
    }
    static long[] fps(String s) {
        String[] pieces = s.split("/",-1);
        if (pieces.length > 2) bad();
        long a = number(pieces[0]), b = pieces.length == 2 ? number(pieces[1]) : 1;
        if (a < 1 || a > 100000 || b < 1 || b > 100000) bad();
        return new long[]{a,b};
    }
    static List<String> text(String s) {
        List<String> lines = Arrays.asList(s.split("\\|",-1));
        if (lines.stream().anyMatch(String::isEmpty)) bad();
        return lines;
    }
    static String srt(long t) {
        return String.format(Locale.ROOT,"%02d:%02d:%02d,%03d",t/3600000,t/60000%60,t/1000%60,t%1000);
    }
    static String ass(long t) {
        long c = (t+5)/10;
        return String.format(Locale.ROOT,"%d:%02d:%02d.%02d",c/360000,c/6000%60,c/100%60,c%100);
    }
    static String decimal(long v) { return String.format(Locale.ROOT,"%d.%02d",v/100,v%100); }
    static long round(long a, long b) {
        if (b < 0) {
            a = -a;
            b = -b;
        }
        return Math.floorDiv(2*a+b,2*b);
    }
    static List<String> words(List<String> lines) {
        return Arrays.stream(String.join(" ",lines).split(" ")).filter(s -> !s.isEmpty()).toList();
    }
    static List<String> wrap(List<String> lines, long width) {
        List<String> result = new ArrayList<>();
        for (String word : words(lines)) {
            if (result.isEmpty() || result.getLast().length()+1+word.length() > width) {
                result.add(word);
            } else {
                result.set(result.size()-1,result.getLast()+" "+word);
            }
        }
        return result;
    }
    static String normalize(String s) { return String.join(" ",words(List.of(s))); }
    static final Pattern MARKUP = Pattern.compile("</?[ibu]>|</font>|<font(?=[ >])[^>]*>|\\{\\\\an[1-9]\\}|.");
    static List<Item> markup(String line) {
        return MARKUP.matcher(line).results().map(match -> {
            String text = match.group();
            int kind = text.startsWith("{\\an") ? 3 :
                text.startsWith("<font") || text.equals("</font>") ? 2 : text.length() > 1 ? 1 : 0;
            return new Item(text,kind,kind == 3 ? text.charAt(4)-'0' : 0);
        }).toList();
    }
    static String listing(int p, Cue c) {
        return p+" "+c.index()+" "+srt(c.start())+" "+srt(c.end())+" "+String.join("|",c.text());
    }
    void load(List<List<String>> blocks, List<String> out) {
        int bad = 0;
        for (int i = 0; i < blocks.size(); i++) {
            List<String> block = blocks.get(i);
            String reason = "";
            long start = 0, end = 0;
            if (!block.getFirst().matches("[0-9]{1,6}")) reason = "index";
            else {
                try {
                    if (block.size() < 2 || block.get(1).length() != 29 || !block.get(1).substring(12,17).equals(" --> ")) bad();
                    start = time(block.get(1).substring(0,12));
                    end = time(block.get(1).substring(17));
                } catch (Problem problem) {
                    reason = "time";
                }
                if (reason.isEmpty() && block.size() < 3) reason = "no text";
            }
            if (!reason.isEmpty()) {
                out.add("BAD CUE "+(i+1)+": "+reason);
                bad++;
            } else {
                cues.add(new Cue(Long.parseLong(block.getFirst()),start,end,List.copyOf(block.subList(2,block.size()))));
            }
        }
        out.add("LOAD cues="+cues.size()+" bad="+bad);
    }
    List<String> execute(String line) {
        String command = line.split(" ",2)[0];
        if (!SCHEMAS.containsKey(command)) throw new Problem("unknown command");
        String schema = SCHEMAS.get(command);
        if (command.equals("DELETE") && line.split(" ").length == 3) schema = "PP";
        String[] tokens = schema.endsWith("X") ? line.split(" ",schema.length()+1) : line.split(" ");
        if (tokens.length != schema.length()+1) bad();
        String[] args = Arrays.copyOfRange(tokens,1,tokens.length);
        long[] values = new long[args.length];
        for (int i = 0; i < args.length; i++) {
            char type = schema.charAt(i);
            if (type == 'T') values[i] = time(args[i]);
            else if (type == 'F') fps(args[i]);
            else if (type == 'X') {
                if (command.equals("INSERT") || command.equals("TEXT")) text(args[i]);
                if (command.equals("REPLACE")) {
                    String[] parts = args[i].split("\\|",-1);
                    if (parts.length != 2 || parts[0].isEmpty() || parts[1].isEmpty()) bad();
                }
            } else {
                String raw = args[i];
                boolean negative = type == 'I' && raw.startsWith("-");
                values[i] = number(negative ? raw.substring(1) : raw)*(negative ? -1 : 1);
                if (type == 'P' && values[i] < 1 || type == 'r' && (values[i] < 1 || values[i] > 100000) ||
                    type == 'g' && values[i] > 60000 || type == 'e' && (values[i] < 1 || values[i] > 60000) ||
                    type == 'w' && (values[i] < 10 || values[i] > 80)) bad();
            }
        }
        if (command.equals("DELETE") && values.length == 2 && values[1] < values[0]) bad();
        for (int i = 0; i < args.length; i++) {
            if (schema.charAt(i) == 'P' && values[i] > cues.size()+(command.equals("INSERT") ? 1 : 0)) {
                throw new Problem("no cue "+values[i]);
            }
        }
        if (command.equals("SYNC") && cues.get((int)values[0]-1).start() == cues.get((int)values[2]-1).start()) {
            throw new Problem("sync points coincide");
        }
        if (command.equals("UNDO")) {
            if (history.isEmpty()) throw new Problem("nothing to undo");
            Undo undo = history.pop();
            cues = undo.cues();
            return List.of("UNDO command="+undo.command());
        }
        if (MODIFY.contains(command)) history.push(new Undo(command,new ArrayList<>(cues)));
        List<String> out = new ArrayList<>();
        int n = cues.size();
        long v = values.length == 0 ? 0 : values[0];
        switch (command) {
            case "LIST", "AT", "SEARCH", "GAPS": {
                int count = 0;
                for (int i = 0; i < n; i++) {
                    Cue cue = cues.get(i);
                    if (command.equals("LIST") || command.equals("AT") && cue.start() <= v && v < cue.end()) {
                        out.add(listing(i+1,cue));
                        count++;
                    }
                    if (command.equals("SEARCH")) {
                        for (String t : cue.text()) {
                            if (t.contains(args[0])) {
                                out.add((i+1)+" "+srt(cue.start())+" "+t);
                                count++;
                                break;
                            }
                        }
                    }
                    if (command.equals("GAPS") && i+1 < n && cues.get(i+1).start()-cue.end() < v) {
                        out.add((i+1)+" "+(i+2)+" "+(cues.get(i+1).start()-cue.end()));
                        count++;
                    }
                }
                if (!command.equals("LIST")) out.add(command+switch (command) {
                    case "AT" -> " active=";
                    case "SEARCH" -> " found=";
                    default -> " count=";
                }+count);
                break;
            }
            case "VALIDATE": {
                for (int i = 0; i < n; i++) {
                    Cue c = cues.get(i);
                    long d = c.duration();
                    String p = "cue "+(i+1)+": ";
                    if (c.index() != i+1) out.add(p+"index "+c.index()+" (expected "+(i+1)+")");
                    if (d <= 0) out.add(p+"end not after start");
                    if (i > 0 && c.start() < cues.get(i-1).end()) out.add(p+"overlaps previous by "+(cues.get(i-1).end()-c.start())+" ms");
                    if (d >= 1 && d < 700) out.add(p+"too short ("+d+" ms)");
                    if (d > 7000) out.add(p+"too long ("+d+" ms)");
                    for (int j = 0; j < c.text().size(); j++) {
                        int size = c.text().get(j).length();
                        if (size > 42) out.add(p+"line "+(j+1)+" too long ("+size+" chars)");
                    }
                    if (c.text().size() >= 3) out.add(p+"too many lines ("+c.text().size()+")");
                    if (d >= 1 && c.chars()*1000 > 21*d) out.add(p+"too fast ("+decimal(c.chars()*100000/d)+" cps)");
                }
                out.add("VALIDATE problems="+out.size());
                break;
            }
            case "STATS": {
                out.add("STATS cues="+n);
                if (n == 0) break;
                List<Long> durations = cues.stream().map(c -> Math.max(0,c.duration())).toList();
                long total = durations.stream().mapToLong(Long::longValue).sum(), longest = Collections.max(durations);
                long chars = cues.stream().filter(c -> c.duration() > 0).mapToLong(Cue::chars).sum();
                out.add("duration total="+srt(total)+" mean="+srt(total/n));
                out.add("speed "+(total == 0 ? "-" : decimal(chars*100000/total)));
                out.add("longest cue="+(durations.indexOf(longest)+1)+" duration="+srt(longest));
                if (n == 1) out.add("gap none");
                else {
                    List<Long> gaps = IntStream.range(0,n-1).mapToObj(i -> cues.get(i+1).start()-cues.get(i).end()).toList();
                    long gap = Collections.max(gaps);
                    out.add("gap cue="+(gaps.indexOf(gap)+1)+" ms="+gap);
                }
                break;
            }
            case "PRINT", "TOVTT", "TOASS": {
                if (command.equals("TOVTT")) out.addAll(List.of("WEBVTT",""));
                if (command.equals("TOASS")) out.addAll(List.of("[Events]","Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"));
                for (Cue c : cues) {
                    List<String> lines = new ArrayList<>();
                    int code = 0;
                    for (String t : c.text()) {
                        StringBuilder converted = new StringBuilder();
                        for (Item item : markup(t)) {
                            if (code == 0 && item.kind() == 3) code = item.digit();
                            if (command.equals("PRINT")) converted.append(item.text());
                            else if (command.equals("TOASS")) {
                                if (item.kind() == 1) {
                                    char tag = item.text().charAt(item.text().startsWith("</") ? 2 : 1);
                                    converted.append("{\\").append(tag).append(item.text().startsWith("</") ? "0}" : "1}");
                                } else if (item.kind() != 2) converted.append(item.text());
                            } else if (item.kind() == 1) converted.append(item.text());
                            else if (item.kind() == 0) converted.append(switch (item.text()) {
                                case "&" -> "&amp;";
                                case "<" -> "&lt;";
                                case ">" -> "&gt;";
                                default -> item.text();
                            });
                        }
                        String convertedText = converted.toString();
                        if (command.equals("TOVTT")) convertedText = convertedText.trim();
                        if (!command.equals("TOVTT") || !convertedText.isEmpty()) lines.add(convertedText);
                    }
                    if (command.equals("TOASS")) {
                        out.add("Dialogue: 0,"+ass(c.start())+","+ass(c.end())+",Default,,0,0,0,,"+String.join("\\N",lines));
                    } else if (!lines.isEmpty()) {
                        String settings = "";
                        if (command.equals("TOVTT") && code != 0) {
                            if (code >= 7) settings += " line:0";
                            else if (code >= 4) settings += " line:50%";
                            if (code%3 == 1) settings += " align:start";
                            if (code%3 == 0) settings += " align:end";
                        }
                        out.add(Long.toString(c.index()));
                        String times = srt(c.start())+" --> "+srt(c.end());
                        out.add((command.equals("TOVTT") ? times.replace(',','.') : times)+settings);
                        out.addAll(lines);
                        out.add("");
                    }
                }
                break;
            }
            case "FRAMES": {
                long[] rate = fps(args[0]);
                for (int i = 0; i < n; i++) {
                    Cue c = cues.get(i);
                    out.add((i+1)+" "+c.start()*rate[0]/(1000*rate[1])+" "+c.end()*rate[0]/(1000*rate[1]));
                }
                break;
            }
            case "SHIFT", "SHIFTFROM", "SCALE", "SYNC", "SNAP": {
                int first = command.equals("SHIFTFROM") ? (int)v-1 : 0;
                long delta = command.equals("SHIFTFROM") ? values[1] : v;
                long s1 = command.equals("SYNC") ? cues.get((int)v-1).start() : 0;
                long s2 = command.equals("SYNC") ? cues.get((int)values[2]-1).start() : 0;
                long[] rate = command.equals("SNAP") ? fps(args[0]) : new long[]{1,1};
                int clamped = 0, changed = 0;
                for (int i = first; i < n; i++) {
                    Cue c = cues.get(i);
                    long[] times = {c.start(),c.end()};
                    boolean clamp = false;
                    for (int j = 0; j < 2; j++) {
                        long old = times[j], next;
                        if (command.equals("SCALE")) next = round(old*v,values[1]);
                        else if (command.equals("SYNC")) next = round(values[1]*(s2-s1)+(old-s1)*(values[3]-values[1]),s2-s1);
                        else if (command.equals("SNAP")) next = round(round(old*rate[0],1000*rate[1])*1000*rate[1],rate[0]);
                        else next = old+delta;
                        if (next < 0) clamp = true;
                        times[j] = Math.max(0,next);
                        if (times[j] != old) changed++;
                    }
                    if (clamp) clamped++;
                    cues.set(i,new Cue(c.index(),times[0],times[1],c.text()));
                }
                if (command.equals("SNAP")) out.add("SNAP changed="+changed);
                else out.add(command+" cues="+(n-first)+(command.equals("SCALE") ? "" : " clamped="+clamped));
                break;
            }
            case "FIXOVERLAP", "EXTEND": {
                int changed = 0, failed = 0;
                for (int i = 0; i < n; i++) {
                    Cue c = cues.get(i);
                    long end = c.end();
                    if (command.equals("FIXOVERLAP") && i+1 < n && end > cues.get(i+1).start()-v) {
                        long candidate = cues.get(i+1).start()-v;
                        if (candidate > c.start()) {
                            end = candidate;
                            changed++;
                        } else {
                            out.add("cue "+(i+1)+": cannot fix");
                            failed++;
                        }
                    }
                    if (command.equals("EXTEND") && c.duration() < v) {
                        long candidate = c.start()+v;
                        if (i+1 < n) candidate = Math.min(candidate,cues.get(i+1).start());
                        if (candidate > end) {
                            end = candidate;
                            changed++;
                        }
                    }
                    cues.set(i,new Cue(c.index(),c.start(),end,c.text()));
                }
                if (command.equals("FIXOVERLAP")) out.add("FIXOVERLAP fixed="+changed+" failed="+failed);
                else out.add("EXTEND extended="+changed+" short="+cues.stream().filter(c -> c.duration() < v).count());
                break;
            }
            case "TIME": {
                Cue c = cues.get((int)v-1);
                cues.set((int)v-1,new Cue(c.index(),values[1],values[2],c.text()));
                out.add("TIME cue="+v);
                break;
            }
            case "SORT": {
                List<Cue> old = new ArrayList<>(cues);
                cues.sort(Comparator.comparingLong(Cue::start).thenComparingLong(Cue::end));
                int moved = 0;
                for (int i = 0; i < n; i++) {
                    if (old.get(i) != cues.get(i)) moved++;
                }
                out.add("SORT moved="+moved);
                break;
            }
            case "RENUMBER": {
                int changed = 0;
                for (int i = 0; i < n; i++) {
                    Cue c = cues.get(i);
                    if (c.index() != i+1) changed++;
                    cues.set(i,new Cue(i+1,c.start(),c.end(),c.text()));
                }
                out.add("RENUMBER changed="+changed);
                break;
            }
            case "MERGE": {
                List<Cue> result = new ArrayList<>();
                int merged = 0;
                for (Cue b : cues) {
                    if (!result.isEmpty()) {
                        Cue a = result.getLast();
                        List<String> both = new ArrayList<>(a.text());
                        both.addAll(b.text());
                        List<String> wrapped = wrap(both,42);
                        if (b.start()-a.end() < v && !a.dialogue() && !b.dialogue() && wrapped.size() <= 2) {
                            result.set(result.size()-1,new Cue(a.index(),a.start(),Math.max(a.end(),b.end()),wrapped));
                            merged++;
                            continue;
                        }
                    }
                    result.add(b);
                }
                cues = result;
                out.add("MERGE merged="+merged+" cues="+cues.size());
                break;
            }
            case "SPLIT": {
                List<Cue> result = new ArrayList<>();
                int split = 0;
                for (Cue c : cues) {
                    if (c.duration() <= 0 || c.dialogue()) {
                        result.add(c);
                        continue;
                    }
                    List<String> wrapped = wrap(c.text(),v);
                    if (wrapped.size() <= 2) {
                        result.add(new Cue(c.index(),c.start(),c.end(),wrapped));
                        continue;
                    }
                    split++;
                    List<List<String>> parts = new ArrayList<>();
                    for (int i = 0; i < wrapped.size(); i += 2) parts.add(List.copyOf(wrapped.subList(i,Math.min(i+2,wrapped.size()))));
                    long total = parts.stream().flatMap(List::stream).mapToLong(String::length).sum();
                    long[] durations = new long[parts.size()], remainders = new long[parts.size()];
                    List<Integer> order = new ArrayList<>();
                    long allocated = 0;
                    for (int i = 0; i < parts.size(); i++) {
                        long count = parts.get(i).stream().mapToLong(String::length).sum();
                        durations[i] = c.duration()*count/total;
                        remainders[i] = c.duration()*count%total;
                        allocated += durations[i];
                        order.add(i);
                    }
                    order.sort(Comparator.<Integer>comparingLong(i -> remainders[i]).reversed().thenComparingInt(i -> i));
                    for (int i = 0; i < c.duration()-allocated; i++) durations[order.get(i)]++;
                    long start = c.start();
                    for (int i = 0; i < parts.size(); i++) {
                        result.add(new Cue(c.index(),start,start+durations[i],parts.get(i)));
                        start += durations[i];
                    }
                }
                cues = result;
                out.add("SPLIT split="+split+" cues="+cues.size());
                break;
            }
            case "INSERT": {
                cues.add((int)v-1,new Cue(v,values[1],values[2],text(args[3])));
                out.add("INSERT cue="+v+" cues="+cues.size());
                break;
            }
            case "DELETE": {
                long last = values.length == 2 ? values[1] : v;
                cues.subList((int)v-1,(int)last).clear();
                out.add("DELETE removed="+(last-v+1)+" cues="+cues.size());
                break;
            }
            case "TEXT": {
                Cue c = cues.get((int)v-1);
                List<String> lines = text(args[1]);
                cues.set((int)v-1,new Cue(c.index(),c.start(),c.end(),lines));
                out.add("TEXT cue="+v+" lines="+lines.size());
                break;
            }
            case "BALANCE": {
                int changed = 0, skipped = 0, dialogue = 0;
                for (int i = 0; i < n; i++) {
                    Cue c = cues.get(i);
                    if (c.dialogue()) {
                        dialogue++;
                        continue;
                    }
                    List<String> tokens2 = words(c.text());
                    String joined = String.join(" ",tokens2);
                    List<String> best = joined.length() <= 42 ? List.of(joined) : null;
                    int difference = Integer.MAX_VALUE, firstLength = Integer.MAX_VALUE;
                    for (int j = 1; joined.length() > 42 && j < tokens2.size(); j++) {
                        String a = String.join(" ",tokens2.subList(0,j)), b = String.join(" ",tokens2.subList(j,tokens2.size()));
                        int d = Math.abs(a.length()-b.length());
                        if (a.length() <= 42 && b.length() <= 42 && (d < difference || d == difference && a.length() < firstLength)) {
                            best = List.of(a,b);
                            difference = d;
                            firstLength = a.length();
                        }
                    }
                    if (best == null) skipped++;
                    else if (!best.equals(c.text())) {
                        changed++;
                        cues.set(i,new Cue(c.index(),c.start(),c.end(),best));
                    }
                }
                out.add("BALANCE changed="+changed+" skipped="+skipped+" dialogue="+dialogue);
                break;
            }
            case "STRIP", "CLEANHI": {
                List<Cue> result = new ArrayList<>();
                int tags = 0, segments = 0, labels = 0, removed = 0;
                for (Cue c : cues) {
                    List<String> lines = new ArrayList<>();
                    for (String t : c.text()) {
                        StringBuilder builder = new StringBuilder();
                        if (command.equals("STRIP")) {
                            for (Item item : markup(t)) {
                                if (item.kind() == 0) builder.append(item.text());
                                else tags++;
                            }
                        } else {
                            int p = 0;
                            while (p < t.length()) {
                                char ch = t.charAt(p);
                                int end = ch == '[' || ch == '(' ? t.indexOf(ch == '[' ? ']' : ')',p+1) : -1;
                                if (end >= 0) {
                                    segments++;
                                    p = end+1;
                                } else {
                                    builder.append(ch);
                                    p++;
                                }
                            }
                        }
                        String cleaned = command.equals("STRIP") ? builder.toString().trim() : normalize(builder.toString());
                        if (command.equals("CLEANHI")) {
                            String prefix = cleaned.startsWith("- ") ? "- " : "";
                            String body = cleaned.substring(prefix.length());
                            int colon = body.indexOf(':');
                            if (colon > 0 && body.substring(0,colon).matches("[A-Z][A-Z0-9 ]*")) {
                                labels++;
                                cleaned = normalize(prefix+body.substring(colon+1));
                            }
                        }
                        if (cleaned.isEmpty() || command.equals("CLEANHI") && cleaned.equals("-")) removed++;
                        else lines.add(cleaned);
                    }
                    if (!lines.isEmpty()) result.add(new Cue(c.index(),c.start(),c.end(),lines));
                }
                int removedCues = n-result.size();
                cues = result;
                out.add(command.equals("STRIP") ? "STRIP tags="+tags+" removed_lines="+removed+" removed_cues="+removedCues :
                    "CLEANHI segments="+segments+" labels="+labels+" removed_lines="+removed+" removed_cues="+removedCues);
                break;
            }
            case "REPLACE": {
                String[] parts = args[0].split("\\|",-1);
                String old = parts[0], replacement = parts[1];
                int count = 0, changed = 0;
                for (int i = 0; i < n; i++) {
                    Cue c = cues.get(i);
                    List<String> lines = new ArrayList<>();
                    int before = count;
                    for (String t : c.text()) {
                        String[] pieces = t.split(Pattern.quote(old),-1);
                        count += pieces.length-1;
                        lines.add(String.join(replacement,pieces));
                    }
                    if (count > before) changed++;
                    cues.set(i,new Cue(c.index(),c.start(),c.end(),lines));
                }
                out.add("REPLACE count="+count+" cues="+changed);
                break;
            }
        }
        return out;
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        List<List<String>> blocks = new ArrayList<>();
        List<String> block = new ArrayList<>();
        String line;
        while (!(line = input.readLine()).equals("###")) {
            if (line.isEmpty()) {
                if (!block.isEmpty()) blocks.add(block);
                block = new ArrayList<>();
            } else block.add(line);
        }
        if (!block.isEmpty()) blocks.add(block);
        Main editor = new Main();
        List<String> loaded = new ArrayList<>();
        editor.load(blocks,loaded);
        loaded.forEach(output::println);
        int count = Integer.parseInt(input.readLine());
        for (int i = 0; i < count; i++) {
            try {
                editor.execute(input.readLine()).forEach(output::println);
            } catch (Problem problem) {
                output.println("ERROR "+problem.getMessage());
            }
        }
        output.flush();
    }
}
