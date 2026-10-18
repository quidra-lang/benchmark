import java.io.*;
import java.util.*;
import java.util.regex.*;

public class Main {
    static final Map<String,Integer> counts = Map.ofEntries(
            Map.entry("CONVERT",2),Map.entry("NORMALIZE",0),Map.entry("REVERSE",1),Map.entry("VALID",1),
            Map.entry("DETECT",0),Map.entry("DIFF",2),Map.entry("SAME",2),Map.entry("MORAE",1),Map.entry("SYLLABLES",1),
            Map.entry("ROW",1),Map.entry("STATS",1),Map.entry("SORT",1),Map.entry("INDEX",1),Map.entry("FIND",2),
            Map.entry("HAIKU",1),Map.entry("KAIBUN",1),Map.entry("SHIRITORI",1));

    record Meta(String id, String row, String dan, boolean contracted) {}
    record Mora(String id, int column) {}
    record Word(String text, int start, int pattern, List<Mora> morae) {}
    record Match(String id, int length) {}
    record LongInfo(boolean[] paired, boolean[] elements, char[] vowels) {}
    record Element(String base, int voice, int size) {}
    static class Problem extends RuntimeException {
        Problem(String message) {
            super(message);
        }
    }
    static final List<String> SYSTEMS = List.of("HEPBURN","TRADITIONAL","KUNREI","NIHON","WAPURO");
    static final List<String> ROWS = List.of("a","ka","sa","ta","na","ha","ma","ya","ra","wa","ga","za","da","ba","pa");
    static final String GOJUON = "a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N";
    static final String IROHA = "i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N";
    static final Pattern WORDS = Pattern.compile("[A-Za-z'-]+");
    final LinkedHashMap<String,Meta> metadata = new LinkedHashMap<>();
    final Map<String,Map<String,String>> readers = new HashMap<>();
    String longSetting = "KEEP", caseSetting = "KEEP", orderSetting = "GOJUON";

    Main() {
        String[] rows = {"a i u e o", "ka ki ku ke ko", "sa si su se so", "ta ti tu te to",
            "na ni nu ne no", "ha hi hu he ho", "ma mi mu me mo", "ya yu yo", "ra ri ru re ro",
            "wa wi we wo", "ga gi gu ge go", "za zi zu ze zo", "da di du de do", "ba bi bu be bo", "pa pi pu pe po"};
        for (int i = 0; i < rows.length; i++) {
            for (String id : rows[i].split(" ")) {
                metadata.put(id,new Meta(id,ROWS.get(i),id.substring(id.length()-1),false));
            }
        }
        for (String row : List.of("ka","sa","ta","na","ha","ma","ra","ga","za","da","ba","pa")) {
            for (String dan : List.of("ya","yu","yo")) {
                String id = row.substring(0,1)+dan;
                metadata.put(id,new Meta(id,row,dan,true));
            }
        }
        for (String system : SYSTEMS) {
            readers.put(system,new HashMap<>());
        }
        readers.put("ANY",new HashMap<>());
        for (Meta meta : metadata.values()) {
            for (String system : SYSTEMS) {
                String spelling = spelling(system,meta.id());
                readers.get(system).putIfAbsent(spelling,meta.id());
                readers.get("ANY").putIfAbsent(spelling,meta.id());
            }
        }
    }
    static void fail(String message) {
        throw new Problem(message);
    }
    static void column(int value, String message) {
        fail("col " + value + ": " + message);
    }
    static boolean letter(char c) {
        return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z';
    }
    static boolean begins(String text, String choices) {
        return !text.isEmpty() && choices.indexOf(text.charAt(0)) >= 0;
    }
    boolean regular(String id) {
        return metadata.containsKey(id);
    }
    static boolean vowel(String id) {
        return id.length() == 1 && "aiueo".contains(id);
    }
    static char last(String id) {
        return id.charAt(id.length()-1);
    }
    static String devoice(String id) {
        int index = "gzdbp".indexOf(id.charAt(0));
        return index < 0 ? id : "ksthh".charAt(index)+id.substring(1);
    }
    static String baseRow(String row) {
        return switch (row) {
            case "ga" -> "ka";
            case "za" -> "sa";
            case "da" -> "ta";
            case "ba", "pa" -> "ha";
            default -> row;
        };
    }
    static int voice(String row) {
        return row.equals("pa") ? 2 : Set.of("ga","za","da","ba").contains(row) ? 1 : 0;
    }
    static String spelling(String system, String id) {
        boolean hepburn = system.equals("HEPBURN") || system.equals("TRADITIONAL");
        boolean wapuro = system.equals("WAPURO");
        if (hepburn || wapuro) {
            String result = switch (id) {
                case "si" -> "shi";
                case "ti" -> "chi";
                case "tu" -> "tsu";
                case "hu" -> "fu";
                case "zi" -> "ji";
                case "di" -> hepburn ? "ji" : id;
                case "du" -> hepburn ? "zu" : id;
                case "wi" -> hepburn ? "i" : id;
                case "we" -> hepburn ? "e" : id;
                case "wo" -> hepburn ? "o" : id;
                default -> id;
            };
            if (id.startsWith("sy")) {
                return "sh"+last(id);
            }
            if (id.startsWith("ty")) {
                return "ch"+last(id);
            }
            if (id.startsWith("zy") || hepburn && id.startsWith("dy")) {
                return "j"+last(id);
            }
            return result;
        }
        if (system.equals("KUNREI")) {
            return switch (id) {
                case "di" -> "zi";
                case "du" -> "zu";
                case "wi" -> "i";
                case "we" -> "e";
                case "wo" -> "o";
                default -> id.startsWith("dy") ? "z"+id.substring(1) : id;
            };
        }
        return id;
    }
    Match match(String text, int position, String system) {
        for (int length = Math.min(3,text.length()-position); length >= 1; length--) {
            String id = readers.get(system).get(text.substring(position,position+length));
            if (id != null) {
                return new Match(id,length);
            }
        }
        return null;
    }
    List<Mora> parse(Word word, String system) {
        String text = word.text().toLowerCase(Locale.ROOT);
        List<Mora> result = new ArrayList<>();
        boolean normalize = system.equals("ANY");
        int p = 0;
        while (p < text.length()) {
            char c = text.charAt(p), next = p+1 < text.length() ? text.charAt(p+1) : 0;
            int at = word.start()+p+1;
            String id;
            int advance;
            if (c == '-') {
                if (result.isEmpty() || !regular(result.getLast().id())) {
                    column(at,"misplaced long mark");
                }
                id = "L";
                advance = 1;
            } else if (c == '\'') {
                column(at,"misplaced apostrophe");
                return result;
            } else {
                Match syllable = match(text,p,system);
                if (syllable != null) {
                    id = syllable.id();
                    advance = syllable.length();
                } else if ((normalize || system.equals("WAPURO")) && text.startsWith("xtu",p)) {
                    id = "Q";
                    advance = 3;
                } else if (c == 'n') {
                    id = "N";
                    advance = 1;
                    if (normalize) {
                        char third = p+2 < text.length() ? text.charAt(p+2) : 0;
                        if (next == '\'' || next == 'n' && "aiueoy'".indexOf(third) < 0) {
                            advance = 2;
                        }
                    } else if (system.equals("WAPURO")) {
                        if (next == 'n') {
                            advance = 2;
                        }
                    } else if (next == '\'') {
                        advance = 2;
                    }
                } else if ((normalize || system.equals("TRADITIONAL")) && c == 'm' && "bmp".indexOf(next) >= 0) {
                    id = "N";
                    advance = 1;
                } else if (letter(c) && "aiueon".indexOf(c) < 0 && c == next && match(text,p+1,system) != null) {
                    id = "Q";
                    advance = 1;
                } else if ((normalize || system.equals("HEPBURN") || system.equals("TRADITIONAL")) &&
                    c == 't' && text.startsWith("ch",p+1) && match(text,p+1,system) != null) {
                    id = "Q";
                    advance = 1;
                } else {
                    column(at,"unknown syllable");
                    return result;
                }
            }
            result.add(new Mora(id,at));
            p += advance;
        }
        return result;
    }
    List<Word> scan(String text) {
        List<Word> result = new ArrayList<>();
        Matcher matcher = WORDS.matcher(text);
        while (matcher.find()) {
            result.add(new Word(matcher.group(),matcher.start(),0,List.of()));
        }
        return result;
    }
    static int pattern(String text) {
        List<Character> letters = new ArrayList<>();
        for (char c : text.toCharArray()) {
            if (letter(c)) {
                letters.add(c);
            }
        }
        if (letters.stream().allMatch(c -> c >= 'a' && c <= 'z')) {
            return 0;
        }
        if (text.charAt(0) >= 'A' && text.charAt(0) <= 'Z' &&
            letters.subList(1,letters.size()).stream().allMatch(c -> c >= 'a' && c <= 'z')) {
            return 1;
        }
        if (letters.size() >= 2 && letters.stream().allMatch(c -> c >= 'A' && c <= 'Z')) {
            return 2;
        }
        return -1;
    }
    LongInfo longInfo(List<Mora> morae) {
        int count = morae.size();
        boolean[] paired = new boolean[count], elements = new boolean[count];
        char[] vowels = new char[count];
        for (int i = 0; i < count; i++) {
            if (morae.get(i).id().equals("L")) {
                elements[i] = true;
                vowels[i] = last(morae.get(i-1).id());
            }
        }
        int i = 0;
        while (i+1 < count) {
            String a = morae.get(i).id(), b = morae.get(i+1).id();
            char v = last(a);
            if (regular(a) && vowel(b) && (v == last(b) || v == 'o' && b.equals("u") || v == 'e' && b.equals("i"))) {
                paired[i+1] = true;
                if (v == 'o' && (b.equals("o") || b.equals("u")) || v == 'u' && b.equals("u")) {
                    elements[i+1] = true;
                    vowels[i+1] = v;
                }
                i += 2;
            } else {
                i++;
            }
        }
        return new LongInfo(paired,elements,vowels);
    }
    List<String> parts(Word word, String system, String longMode) {
        List<Mora> morae = word.morae();
        LongInfo info = longInfo(morae);
        List<String> result = new ArrayList<>();
        for (int i = 0; i < morae.size(); i++) {
            Mora mora = morae.get(i);
            String id = mora.id();
            String nextId = i+1 < morae.size() ? morae.get(i+1).id() : "";
            String next = regular(nextId) ? spelling(system,nextId) : "";
            String part;
            if (info.elements()[i]) {
                char v = info.vowels()[i];
                part = switch (longMode) {
                    case "KEEP" -> id.equals("L") ? "-" : spelling(system,id);
                    case "DROP" -> "";
                    case "PASSPORT" -> v == 'o' && !begins(next,"aiueo") ? "h" : "";
                    case "HYPHEN" -> "-";
                    default -> String.valueOf(v);
                };
            } else if (regular(id)) {
                part = spelling(system,id);
            } else if (id.equals("N")) {
                if (system.equals("WAPURO")) {
                    part = nextId.equals("N") || begins(next,"aiueoyn") ? "nn" : "n";
                } else if (system.equals("TRADITIONAL") && begins(next,"bmp")) {
                    part = "m";
                } else {
                    part = begins(next,"aiueoy") ? "n'" : "n";
                }
            } else {
                if (!next.isEmpty() && !begins(next,"aiueon")) {
                    part = (system.equals("HEPBURN") || system.equals("TRADITIONAL")) && next.startsWith("ch") ? "t" : next.substring(0,1);
                } else if (system.equals("WAPURO")) {
                    part = "xtu";
                } else {
                    column(mora.column(),"small tsu cannot be written");
                    return result;
                }
            }
            result.add(part);
        }
        return result;
    }
    String write(Word word, String system, String longMode, String caseMode) {
        String result = String.join("",parts(word,system,longMode));
        int pattern = caseMode.equals("KEEP") ? word.pattern() : caseMode.equals("LOWER") ? 0 : caseMode.equals("TITLE") ? 1 : 2;
        if (pattern == 1) {
            result = result.substring(0,1).toUpperCase(Locale.ROOT)+result.substring(1);
        }
        if (pattern == 2) {
            result = result.toUpperCase(Locale.ROOT);
        }
        return result;
    }
    String canonical(Word word, String system) {
        return write(word,system,"KEEP","KEEP");
    }
    static List<String> ids(Word word) {
        return word.morae().stream().map(Mora::id).toList();
    }
    List<String> loose(Word word) {
        LongInfo info = longInfo(word.morae());
        List<String> result = new ArrayList<>();
        for (int i = 0; i < word.morae().size(); i++) {
            if (!info.elements()[i]) {
                result.add(word.morae().get(i).id());
            }
        }
        return result;
    }
    List<Element> elements(Word word) {
        List<Element> result = new ArrayList<>();
        for (Mora mora : word.morae()) {
            String id = mora.id();
            if (id.equals("L")) {
                continue;
            }
            if (id.equals("N")) {
                result.add(new Element("N",0,0));
            } else if (id.equals("Q")) {
                result.add(new Element("tu",0,1));
            } else {
                Meta meta = metadata.get(id);
                if (meta.contracted()) {
                    result.add(new Element(devoice(meta.row().substring(0,1)+"i"),voice(meta.row()),0));
                    result.add(new Element("y"+last(id),0,1));
                } else {
                    result.add(new Element(devoice(id),voice(meta.row()),0));
                }
            }
        }
        return result;
    }
    List<Word> sorted(List<Word> words) {
        Map<String,Integer> ranks = new HashMap<>();
        String[] bases = (orderSetting.equals("GOJUON") ? GOJUON : IROHA).split(" ");
        for (int i = 0; i < bases.length; i++) {
            ranks.put(bases[i],i);
        }
        record Keyed(Word word, int[][] keys) {}
        return words.stream().map(word -> {
            List<Element> elements = elements(word);
            return new Keyed(word,new int[][] {
                elements.stream().mapToInt(e -> ranks.get(e.base())).toArray(),
                elements.stream().mapToInt(Element::voice).toArray(),
                elements.stream().mapToInt(Element::size).toArray(),
                word.morae().stream().mapToInt(m -> m.id().equals("L") ? 1 : 0).toArray()
            });
        }).sorted((a,b) -> Arrays.compare(a.keys(),b.keys(),Arrays::compare)).map(Keyed::word).toList();
    }
    List<String> patternMorae(String pattern, String system) {
        if (!pattern.matches("[a-z'?*\\-]+")) {
            fail("invalid pattern");
        }
        List<String> result = new ArrayList<>();
        try {
            for (String part : pattern.splitWithDelimiters("[?*]",0)) {
                if (part.equals("?") || part.equals("*")) {
                    result.add(part);
                } else if (!part.isEmpty()) {
                    result.addAll(parse(new Word(part,0,0,List.of()),system).stream().map(Mora::id).toList());
                }
            }
        } catch (Problem problem) {
            fail("invalid pattern");
        }
        return result;
    }
    static boolean matches(List<String> pattern, List<String> word) {
        boolean[] dp = new boolean[word.size()+1];
        dp[0] = true;
        for (String token : pattern) {
            boolean[] next = new boolean[word.size()+1];
            next[0] = token.equals("*") && dp[0];
            for (int j = 1; j <= word.size(); j++) {
                next[j] = token.equals("*") ? dp[j] || next[j-1] : dp[j-1] && (token.equals("?") || token.equals(word.get(j-1)));
            }
            dp = next;
        }
        return dp[word.size()];
    }
    String detect(List<Word> words) {
        List<String> result = new ArrayList<>();
        for (String system : SYSTEMS) {
            String verdict = "canonical";
            try {
                List<Word> parsed = new ArrayList<>();
                for (Word word : words) {
                    parsed.add(new Word(word.text(),word.start(),word.pattern(),parse(word,system)));
                }
                for (Word word : parsed) {
                    if (!word.text().equals(canonical(word,system))) {
                        verdict = "readable";
                    }
                }
            } catch (Problem problem) {
                verdict = "error";
            }
            result.add(system+"="+verdict);
        }
        return String.join(" ",result);
    }
    String execute(String line) {
        String command = line.split(" ",2)[0];
        if (!counts.containsKey(command) && !command.equals("SET") && !command.equals("TABLE")) {
            fail("unknown command "+command);
        }
        if (command.equals("SET") || command.equals("TABLE")) {
            String[] tokens = line.split(" ");
            if (tokens.length < 3) {
                fail("missing argument");
            }
            if (tokens.length > 3) {
                fail("too many arguments");
            }
            if (command.equals("SET")) {
                Set<String> allowed = switch (tokens[1]) {
                    case "LONG" -> Set.of("KEEP","DROP","PASSPORT","HYPHEN","DOUBLE");
                    case "CASE" -> Set.of("KEEP","LOWER","UPPER","TITLE");
                    case "ORDER" -> Set.of("GOJUON","IROHA");
                    default -> throw new Problem("unknown option "+tokens[1]);
                };
                if (!allowed.contains(tokens[2])) {
                    fail("unknown value "+tokens[2]);
                }
                if (tokens[1].equals("LONG")) {
                    longSetting = tokens[2];
                }
                if (tokens[1].equals("CASE")) {
                    caseSetting = tokens[2];
                }
                if (tokens[1].equals("ORDER")) {
                    orderSetting = tokens[2];
                }
                return tokens[1]+"="+tokens[2];
            }
            if (!SYSTEMS.contains(tokens[1])) {
                fail("unknown system "+tokens[1]);
            }
            if (!ROWS.contains(tokens[2])) {
                fail("unknown row "+tokens[2]);
            }
            List<String> result = new ArrayList<>();
            for (Meta meta : metadata.values()) {
                if (meta.row().equals(tokens[2])) {
                    result.add(spelling(tokens[1],meta.id()));
                }
            }
            return String.join(" ",result);
        }
        int fixed = counts.get(command);
        String[] tokens = line.split(" ",fixed+2);
        if (tokens.length < fixed+2) {
            fail("missing argument");
        }
        String[] arguments = Arrays.copyOfRange(tokens,1,fixed+1);
        String text = tokens[fixed+1];
        int systemCount = command.equals("NORMALIZE") || command.equals("DETECT") ? 0 :
            Set.of("CONVERT","DIFF","SAME").contains(command) ? 2 : 1;
        for (int i = 0; i < systemCount; i++) {
            if (!SYSTEMS.contains(arguments[i])) {
                fail("unknown system "+arguments[i]);
            }
        }
        List<String> searchPattern = command.equals("FIND") ? patternMorae(arguments[1],arguments[0]) : List.of();
        boolean slash = command.equals("SAME") || command.equals("HAIKU");
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (!letter(c) && c != '\'' && c != '-' && " 0123456789.,!?;:()\"".indexOf(c) < 0 && !(slash && c == '/')) {
                column(i+1,"invalid character");
            }
        }
        String[] poem = text.split("/",-1);
        if (command.equals("SAME") && (poem.length != 2 || scan(poem[0]).isEmpty() || scan(poem[1]).isEmpty())) {
            fail("expected two texts");
        }
        if (command.equals("HAIKU")) {
            if (poem.length != 3 && poem.length != 5) {
                fail("expected 3 or 5 lines");
            }
            for (String part : poem) {
                if (scan(part).isEmpty()) {
                    fail("expected 3 or 5 lines");
                }
            }
        }
        List<Word> words = scan(text);
        if (words.isEmpty()) {
            fail("no words");
        }
        for (int i = 0; i < words.size(); i++) {
            Word word = words.get(i);
            int pattern = pattern(word.text());
            if (pattern < 0) {
                column(word.start()+1,"mixed case");
            }
            words.set(i,new Word(word.text(),word.start(),pattern,List.of()));
        }
        if (command.equals("DETECT")) {
            return detect(words);
        }
        for (int i = 0; i < words.size(); i++) {
            Word word = words.get(i);
            String source = command.equals("NORMALIZE") ? "ANY" :
                command.equals("SAME") && word.start() > text.indexOf('/') ? arguments[1] : arguments[0];
            words.set(i,new Word(word.text(),word.start(),word.pattern(),parse(word,source)));
        }
        String system = command.equals("NORMALIZE") ? "HEPBURN" : arguments[0];
        switch (command) {
            case "CONVERT", "NORMALIZE", "REVERSE": {
                String target = command.equals("CONVERT") ? arguments[1] : system;
                StringBuilder result = new StringBuilder();
                int cursor = 0;
                for (Word word : words) {
                    result.append(text,cursor,word.start());
                    Word written = word;
                    if (command.equals("REVERSE")) {
                        List<Mora> reversed = new ArrayList<>();
                        for (int i = 0; i < word.morae().size(); i++) {
                            Mora mora = word.morae().get(i);
                            reversed.add(mora.id().equals("L") ? new Mora(String.valueOf(last(word.morae().get(i-1).id())),mora.column()) : mora);
                        }
                        Collections.reverse(reversed);
                        written = new Word(word.text(),word.start(),word.pattern(),reversed);
                    }
                    result.append(write(written,target,longSetting,caseSetting));
                    cursor = word.start()+word.text().length();
                }
                result.append(text.substring(cursor));
                return result.toString();
            }
            case "VALID": {
                for (Word word : words) {
                    String expected = canonical(word,system);
                    if (!word.text().equals(expected)) {
                        int i = 0;
                        while (i < Math.min(word.text().length(),expected.length()) && word.text().charAt(i) == expected.charAt(i)) {
                            i++;
                        }
                        return "INVALID col "+(word.start()+i+1)+": expected "+expected;
                    }
                }
                return "VALID";
            }
            case "DIFF": {
                List<String> changes = new ArrayList<>();
                for (Word word : words) {
                    String a = write(word,system,longSetting,caseSetting);
                    String b = write(word,arguments[1],longSetting,caseSetting);
                    if (!a.equals(b)) {
                        changes.add(a+">"+b);
                    }
                }
                return changes.size()+" of "+words.size()+(changes.isEmpty() ? "" : ": "+String.join(" ",changes));
            }
            case "SAME": {
                List<Word> left = words.stream().filter(w -> w.start() < text.indexOf('/')).toList();
                List<Word> right = words.stream().filter(w -> w.start() > text.indexOf('/')).toList();
                boolean exact = true;
                for (int i = 0; i < Math.min(left.size(),right.size()); i++) {
                    if (!loose(left.get(i)).equals(loose(right.get(i)))) {
                        return "DIFFERENT at word "+(i+1);
                    }
                    if (!ids(left.get(i)).equals(ids(right.get(i)))) {
                        exact = false;
                    }
                }
                if (left.size() != right.size()) {
                    return "DIFFERENT at word "+(Math.min(left.size(),right.size())+1);
                }
                return exact ? "EXACT" : "LOOSE";
            }
            case "MORAE": {
                List<String> result = new ArrayList<>();
                int count = 0;
                for (Word word : words) {
                    List<String> pieces = new ArrayList<>();
                    for (Mora mora : word.morae()) {
                        pieces.add(regular(mora.id()) ? spelling(system,mora.id()) : mora.id().equals("L") ? "-" : mora.id());
                    }
                    count += pieces.size();
                    result.add(String.join(".",pieces));
                }
                return count+": "+String.join(" ",result);
            }
            case "SYLLABLES": {
                List<String> result = new ArrayList<>();
                int count = 0;
                for (Word word : words) {
                    List<String> pieces = parts(word,system,"KEEP"), syllables = new ArrayList<>();
                    LongInfo info = longInfo(word.morae());
                    for (int i = 0; i < pieces.size(); i++) {
                        if (i == 0 || regular(word.morae().get(i).id()) && !info.paired()[i]) {
                            syllables.add(pieces.get(i));
                        } else {
                            syllables.set(syllables.size()-1,syllables.getLast()+pieces.get(i));
                        }
                    }
                    count += syllables.size();
                    result.add(String.join(".",syllables));
                }
                return count+": "+String.join(" ",result);
            }
            case "ROW": {
                List<String> result = new ArrayList<>();
                for (Word word : words) {
                    for (Mora mora : word.morae()) {
                        Meta meta = metadata.get(mora.id());
                        result.add(meta == null ? (mora.id().equals("L") ? "-" : mora.id())+": special" :
                            spelling(system,meta.id())+": "+meta.row()+" "+meta.dan());
                    }
                }
                return String.join(", ",result);
            }
            case "STATS": {
                Map<String,Integer> rowCounts = new HashMap<>();
                int count = 0, voiced = 0, semivoiced = 0, contracted = 0, n = 0, q = 0, l = 0;
                for (Word word : words) {
                    for (Mora mora : word.morae()) {
                        count++;
                        Meta meta = metadata.get(mora.id());
                        if (meta == null) {
                            if (mora.id().equals("N")) {
                                n++;
                            }
                            if (mora.id().equals("Q")) {
                                q++;
                            }
                            if (mora.id().equals("L")) {
                                l++;
                            }
                        } else {
                            rowCounts.merge(baseRow(meta.row()),1,Integer::sum);
                            if (voice(meta.row()) == 1) {
                                voiced++;
                            }
                            if (voice(meta.row()) == 2) {
                                semivoiced++;
                            }
                            if (meta.contracted()) {
                                contracted++;
                            }
                        }
                    }
                }
                List<String> result = new ArrayList<>(List.of("morae="+count));
                for (String row : ROWS.subList(0,10)) {
                    if (rowCounts.containsKey(row)) {
                        result.add(row+"="+rowCounts.get(row));
                    }
                }
                result.addAll(List.of("voiced="+voiced,"semivoiced="+semivoiced,"contracted="+contracted,"N="+n,"Q="+q,"L="+l));
                return String.join(" ",result);
            }
            case "SORT", "INDEX": {
                List<Word> sorted = sorted(words);
                if (command.equals("SORT")) {
                    return String.join(" ",sorted.stream().map(Word::text).toList());
                }
                List<String> groups = new ArrayList<>(), group = new ArrayList<>();
                String previous = "";
                for (Word word : sorted) {
                    String base = elements(word).getFirst().base();
                    String heading = orderSetting.equals("IROHA") || base.equals("N") ? base : metadata.get(base).row();
                    if (!heading.equals(previous) && !group.isEmpty()) {
                        groups.add(previous+": "+String.join(" ",group));
                        group.clear();
                    }
                    previous = heading;
                    group.add(word.text());
                }
                groups.add(previous+": "+String.join(" ",group));
                return String.join("; ",groups);
            }
            case "FIND": {
                List<String> found = words.stream().filter(w -> matches(searchPattern,ids(w))).map(Word::text).toList();
                return found.size()+" of "+words.size()+(found.isEmpty() ? "" : ": "+String.join(" ",found));
            }
            case "HAIKU": {
                int[] totals = new int[poem.length];
                for (Word word : words) {
                    int index = (int)text.substring(0,word.start()).chars().filter(c -> c == '/').count();
                    totals[index] += word.morae().size();
                }
                int[] expected = poem.length == 3 ? new int[]{5,7,5} : new int[]{5,7,5,7,7};
                return (Arrays.equals(totals,expected) ? "OK " : "NG ")+(poem.length == 3 ? "haiku " : "tanka ")+
                    String.join("-",Arrays.stream(totals).mapToObj(String::valueOf).toList());
            }
            case "KAIBUN": {
                List<String> bases = words.stream().flatMap(w -> elements(w).stream()).map(Element::base).toList();
                List<String> reversed = bases.reversed();
                return (bases.equals(reversed) ? "YES " : "NO ")+String.join(".",bases);
            }
            case "SHIRITORI": {
                Set<List<String>> seen = new HashSet<>();
                String previous = "";
                for (int i = 0; i < words.size(); i++) {
                    Word word = words.get(i);
                    List<Element> elements = elements(word);
                    String head = elements.getFirst().base(), tail = elements.getLast().base();
                    String prefix = "NG "+(i+1)+": "+word.text();
                    if (i > 0 && !head.equals(previous)) {
                        return prefix+" must start with "+spelling(system,previous);
                    }
                    if (!seen.add(ids(word))) {
                        return prefix+" is repeated";
                    }
                    if (tail.equals("N")) {
                        return prefix+" ends with N";
                    }
                    previous = tail;
                }
                return "OK "+words.size();
            }
            default: throw new IllegalStateException("Unreachable command");
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        Main converter = new Main();
        int count = Integer.parseInt(input.readLine());
        for (int i = 0; i < count; i++) {
            try {
                output.println(converter.execute(input.readLine()));
            } catch (Problem problem) {
                output.println("ERROR "+problem.getMessage());
            }
        }
        output.flush();
    }
}
