import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class JobFault extends RuntimeException {
    JobFault(String reason) {
        super(reason);
    }
}

record Candidate(String key, String plaintext, int score, int order) {}

record BreakOutcome(
    List<Candidate> ranked,
    Candidate choice,
    int length,
    String method,
    int passes,
    int changes,
    KasiskiData kasiski
) {
    BreakOutcome(List<Candidate> ranked, Candidate choice) {
        this(ranked, choice, 0, "", 0, 0, null);
    }
}

record OptionRule(int min, int max, int fallback) {}

public final class Main {
    private static final List<String> COMMANDS =
        List.of("ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY");
    private static final Set<String> CIPHERS = Set.of(
        "caesar", "affine", "vigenere", "autokey", "railfence", "columnar", "playfair");
    private static final List<Integer> MULTIPLIERS =
        List.of(1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25);
    private static final Set<String> SUBSTITUTIONS =
        Set.of("caesar", "affine", "vigenere", "autokey");
    private static final Pattern WORD_RUN = Pattern.compile("[A-Za-z]+");

    private final Map<String, List<String>> messages = new LinkedHashMap<>();
    private final Map<String, int[]> totals = new LinkedHashMap<>();
    private final List<String> results = new ArrayList<>();
    private final List<String> candidateLines = new ArrayList<>();
    private final List<String> analysisLines = new ArrayList<>();
    private final Weights weights;

    private Main() throws IOException {
        weights = Scoring.read("input/weights.txt");
        for (String command : COMMANDS)
            totals.put(command, new int[2]);
        loadMessages("input/messages.txt");
    }

    private static void fail(String reason) {
        throw new JobFault(reason);
    }

    private static boolean validName(String name) {
        return name.matches("[a-z0-9_]{1,16}");
    }

    private static boolean digits(String text, int max) {
        return text.matches("[0-9]{1," + max + "}");
    }

    private String body(String name) {
        return String.join("\n", messages.get(name));
    }

    private String letterString(String name) {
        return Scoring.letters(body(name));
    }

    private static List<String> readLines(String path) throws IOException {
        return Files.readAllLines(Path.of(path), StandardCharsets.US_ASCII);
    }

    private void loadMessages(String path) throws IOException {
        String current = null;
        List<String> lines = new ArrayList<>();
        for (String text : readLines(path)) {
            if (current == null) {
                if (text.isEmpty())
                    continue;
                current = text.substring("MESSAGE ".length());
                lines = new ArrayList<>();
            } else if (text.equals("END")) {
                messages.put(current, lines);
                current = null;
            } else {
                lines.add(text);
            }
        }
    }

    private static String normalizeKey(String cipher, String raw) {
        if (cipher.equals("caesar")) {
            if (!digits(raw, 2) || Integer.parseInt(raw) > 25)
                throw new JobFault("bad key " + raw);
            return Integer.toString(Integer.parseInt(raw));
        }
        if (cipher.equals("affine")) {
            String[] parts = raw.split(",", -1);
            if (parts.length != 2 || !digits(parts[0], 2) || !digits(parts[1], 2))
                throw new JobFault("bad key " + raw);
            int a = Integer.parseInt(parts[0]);
            int b = Integer.parseInt(parts[1]);
            if (!MULTIPLIERS.contains(a) || b > 25)
                throw new JobFault("bad key " + raw);
            return a + "," + b;
        }
        if (cipher.equals("railfence")) {
            if (!digits(raw, 2))
                throw new JobFault("bad key " + raw);
            int rails = Integer.parseInt(raw);
            if (rails < 2 || rails > 20)
                throw new JobFault("bad key " + raw);
            return Integer.toString(rails);
        }
        String pattern = switch (cipher) {
            case "vigenere", "autokey" -> "[A-Za-z]{1,20}";
            case "playfair" -> "[A-Za-z]{1,25}";
            case "columnar" -> "[A-Za-z0-9]{2,9}";
            default -> "";
        };
        if (!raw.matches(pattern))
            throw new JobFault("bad key " + raw);
        String key = raw.toUpperCase(java.util.Locale.ROOT);
        return cipher.equals("playfair") ? key.replace('J', 'I') : key;
    }

    private static Map<String, OptionRule> optionRules(String command, String cipher) {
        Map<String, OptionRule> rules = new LinkedHashMap<>();
        if (command.equals("ANALYZE"))
            rules.put("MAXLEN", new OptionRule(2, 20, 10));
        if (!command.equals("BREAK"))
            return rules;
        rules.put("TOP", new OptionRule(1, 20, 5));
        switch (cipher) {
            case "vigenere" -> {
                rules.put("MAXLEN", new OptionRule(2, 20, 10));
                rules.put("IOC", new OptionRule(1, 100000, 6000));
                rules.put("KASISKI", new OptionRule(1, 100, 60));
                rules.put("REFINE", new OptionRule(0, 10, 5));
            }
            case "autokey" -> rules.put("MAXLEN", new OptionRule(1, 20, 8));
            case "railfence" -> rules.put("MAXRAILS", new OptionRule(2, 20, 10));
            case "columnar" -> rules.put("MAXLEN", new OptionRule(2, 6, 6));
            default -> {}
        }
        return rules;
    }

    private static Map<String, String> parseOptions(
        String command, String cipher, List<String> words
    ) {
        Map<String, OptionRule> rules = optionRules(command, cipher);
        Map<String, String> parsed = new LinkedHashMap<>();
        for (var rule : rules.entrySet())
            parsed.put(rule.getKey(), Integer.toString(rule.getValue().fallback()));
        Set<String> seen = new HashSet<>();
        for (String word : words) {
            int equals = word.indexOf('=');
            String name = equals < 0 ? "" : word.substring(0, equals);
            String value = equals < 0 ? "" : word.substring(equals + 1);
            if (equals < 0 || !seen.add(name))
                throw new JobFault("bad option " + word);
            if (name.equals("KEYS") && (command.equals("IDENTIFY")
                || command.equals("BREAK") && cipher.equals("playfair"))) {
                if (!validName(value))
                    throw new JobFault("bad option " + word);
                parsed.put(name, value);
                continue;
            }
            OptionRule rule = rules.get(name);
            if (rule == null || !digits(value, 6))
                throw new JobFault("bad option " + word);
            int number = Integer.parseInt(value);
            if (number < rule.min() || number > rule.max())
                throw new JobFault("bad option " + word);
            parsed.put(name, Integer.toString(number));
        }
        if (command.equals("BREAK") && cipher.equals("playfair")
            && !parsed.containsKey("KEYS"))
            throw new JobFault("missing option KEYS");
        return parsed;
    }

    private static int option(Map<String, String> options, String name) {
        return Integer.parseInt(options.get(name));
    }

    private static boolean isSubstitution(String cipher) {
        return SUBSTITUTIONS.contains(cipher);
    }

    private static String decrypt(String text, String cipher, String key) {
        if (isSubstitution(cipher))
            return Scoring.letters(Substitution.apply(text, cipher, key, false));
        return switch (cipher) {
            case "railfence" -> Transposition.railFence(text, Integer.parseInt(key), false);
            case "columnar" -> Transposition.columnar(text, key, false);
            default -> Playfair.apply(text, key, false);
        };
    }

    private static String transform(String text, String cipher, String key, boolean encrypt) {
        if (isSubstitution(cipher))
            return Substitution.apply(text, cipher, key, encrypt);
        String letters = Scoring.letters(text);
        return switch (cipher) {
            case "railfence" -> Transposition.railFence(letters, Integer.parseInt(key), encrypt);
            case "columnar" -> Transposition.columnar(letters, key, encrypt);
            default -> Playfair.apply(letters, key, encrypt);
        };
    }

    private List<String> keyList(String name) {
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = WORD_RUN.matcher(body(name));
        while (matcher.find())
            seen.add(matcher.group().toUpperCase(java.util.Locale.ROOT).replace('J', 'I'));
        return new ArrayList<>(seen);
    }

    private static void visitPermutations(
        char[] digits, int index, List<String> result
    ) {
        if (index == digits.length) {
            result.add(new String(digits));
            return;
        }
        for (int i = index; i < digits.length; i++) {
            char first = digits[index];
            digits[index] = digits[i];
            digits[i] = first;
            visitPermutations(digits, index + 1, result);
            first = digits[index];
            digits[index] = digits[i];
            digits[i] = first;
        }
    }

    private static List<String> permutations(int length) {
        char[] digits = new char[length];
        for (int i = 0; i < length; i++)
            digits[i] = (char)('1' + i);
        List<String> result = new ArrayList<>();
        visitPermutations(digits, 0, result);
        result.sort(String::compareTo);
        return result;
    }

    private String columnKey(String text, int length, boolean autokey) {
        StringBuilder key = new StringBuilder();
        for (int position = 0; position < length; position++) {
            String column = Analysis.column(text, length, position);
            int best = 0;
            int high = Integer.MIN_VALUE;
            for (int guess = 0; guess < 26; guess++) {
                int score;
                if (autokey) {
                    score = 0;
                    int previous = guess;
                    for (int i = 0; i < column.length(); i++) {
                        previous = Substitution.mod(Scoring.value(column.charAt(i)) - previous);
                        score += weights.mono()[previous];
                    }
                } else {
                    String plain = Substitution.apply(
                        column, "caesar", Integer.toString(guess), false);
                    score = Scoring.monogram(plain, weights.mono());
                }
                if (score > high) {
                    best = guess;
                    high = score;
                }
            }
            key.append(Scoring.upper(best));
        }
        return key.toString();
    }

    private List<String> candidateKeys(
        String cipher, String text, Map<String, String> options, List<String> words
    ) {
        List<String> keys = new ArrayList<>();
        switch (cipher) {
            case "caesar" -> {
                for (int k = 0; k <= 25; k++)
                    keys.add(Integer.toString(k));
            }
            case "affine" -> {
                for (int a : MULTIPLIERS)
                    for (int b = 0; b <= 25; b++)
                        keys.add(a + "," + b);
            }
            case "railfence" -> {
                for (int r = 2; r <= option(options, "MAXRAILS"); r++)
                    keys.add(Integer.toString(r));
            }
            case "columnar" -> {
                for (int length = 2; length <= option(options, "MAXLEN"); length++)
                    keys.addAll(permutations(length));
            }
            case "playfair" -> keys.addAll(words);
            default -> {
                for (int length = 1; length <= option(options, "MAXLEN"); length++)
                    keys.add(columnKey(text, length, cipher.equals("autokey")));
            }
        }
        return keys;
    }

    private int score(String cipher, String plain) {
        if (cipher.equals("caesar") || cipher.equals("affine"))
            return Scoring.monogram(plain, weights.mono());
        return Scoring.bigram(plain, weights.bi());
    }

    private BreakOutcome breakCipher(
        String cipher, String text, Map<String, String> options, List<String> keys
    ) {
        List<Candidate> candidates = new ArrayList<>();
        for (String key : candidateKeys(cipher, text, options, keys)) {
            String plain = decrypt(text, cipher, key);
            candidates.add(new Candidate(key, plain, score(cipher, plain), candidates.size()));
        }
        List<Candidate> ranked = new ArrayList<>(candidates);
        ranked.sort(Comparator.comparingInt(Candidate::score).reversed()
            .thenComparingInt(Candidate::order));
        if (!cipher.equals("vigenere"))
            return new BreakOutcome(ranked, ranked.get(0));

        int maxlen = option(options, "MAXLEN");
        int threshold = option(options, "IOC");
        KasiskiData kasiski = Analysis.kasiski(text);
        int[] average = new int[maxlen];
        for (int length = 1; length <= maxlen; length++)
            average[length - 1] = Analysis.averageIOC(text, length);
        int kasiskiLength = 0;
        for (int length = 2; length <= maxlen; length++) {
            if (!kasiski.gaps().isEmpty()
                && 100 * kasiski.count(length)
                    >= option(options, "KASISKI") * kasiski.gaps().size())
                kasiskiLength = length;
        }
        int chosen = 0;
        String method;
        if (kasiskiLength != 0 && average[kasiskiLength - 1] >= threshold) {
            chosen = kasiskiLength;
            method = "kasiski";
        } else {
            for (int length = 1; length <= maxlen; length++) {
                if (average[length - 1] >= threshold) {
                    chosen = length;
                    break;
                }
            }
            if (chosen != 0) {
                method = "ioc";
            } else {
                chosen = 1;
                for (int length = 2; length <= maxlen; length++) {
                    if (average[length - 1] > average[chosen - 1])
                        chosen = length;
                }
                method = "maxioc";
            }
        }

        String key = candidates.get(chosen - 1).key();
        int reference = score(cipher, decrypt(text, cipher, key));
        int passes = 0;
        int changes = 0;
        for (int pass = 0; pass < option(options, "REFINE"); pass++) {
            passes++;
            int changed = 0;
            for (int position = 0; position < key.length(); position++) {
                char winner = key.charAt(position);
                int high = reference;
                for (int value = 0; value < 26; value++) {
                    String test = key.substring(0, position) + Scoring.upper(value)
                        + key.substring(position + 1);
                    int trial = score(cipher, decrypt(text, cipher, test));
                    if (trial > high) {
                        winner = Scoring.upper(value);
                        high = trial;
                    }
                }
                if (high > reference) {
                    key = key.substring(0, position) + winner + key.substring(position + 1);
                    reference = high;
                    changes++;
                    changed++;
                }
            }
            if (changed == 0)
                break;
        }
        Candidate winner = new Candidate(key, decrypt(text, cipher, key), reference, -1);
        return new BreakOutcome(ranked, winner, chosen, method, passes, changes, kasiski);
    }

    private void candidateReport(
        int job, String cipher, String source, BreakOutcome outcome, int top
    ) {
        List<Candidate> ranked = outcome.ranked();
        int margin = ranked.size() > 1 ? ranked.get(0).score() - ranked.get(1).score() : 0;
        candidateLines.add("JOB " + job + " BREAK " + cipher + " source=" + source
            + " tried=" + ranked.size() + " margin=" + margin);
        for (int index = 0; index < Math.min(top, ranked.size()); index++) {
            Candidate candidate = ranked.get(index);
            String preview = candidate.plaintext().substring(
                0, Math.min(40, candidate.plaintext().length()));
            candidateLines.add((index + 1) + " " + candidate.key()
                + " " + candidate.score() + " " + preview);
        }
    }

    private void breakAnalysis(
        int job, String cipher, String source, String text,
        Map<String, String> options, BreakOutcome outcome
    ) {
        if (cipher.equals("vigenere")) {
            analysisLines.add("JOB " + job + " BREAK vigenere source=" + source);
            analysisLines.add("letters=" + text.length());
            analysisLines.addAll(Analysis.periodTable(
                text, option(options, "MAXLEN"), outcome.kasiski()));
            analysisLines.addAll(Analysis.kasiskiTable(outcome.kasiski()));
            analysisLines.add("decision length=" + outcome.length() + " method=" + outcome.method());
            analysisLines.add("refine passes=" + outcome.passes() + " changes="
                + outcome.changes() + " key=" + outcome.choice().key());
        } else if (cipher.equals("playfair")) {
            String normalized = text.replace('J', 'I');
            Set<String> distinct = new HashSet<>();
            for (int i = 0; i < normalized.length(); i += 2)
                distinct.add(normalized.substring(i, i + 2));
            String square = Playfair.square(outcome.choice().key());
            List<String> rows = new ArrayList<>();
            for (int i = 0; i < 5; i++)
                rows.add(square.substring(5 * i, 5 * i + 5));
            analysisLines.add("JOB " + job + " BREAK playfair source=" + source);
            analysisLines.add("letters=" + normalized.length());
            analysisLines.add("digraphs pairs=" + normalized.length() / 2
                + " distinct=" + distinct.size());
            analysisLines.add("top " + Analysis.topPairs(normalized, true));
            analysisLines.add("square " + String.join(" ", rows));
        }
    }

    private static List<String> outputText(
        String source, String cipher, String key, boolean encrypt
    ) {
        String converted = transform(source, cipher, key, encrypt);
        if (isSubstitution(cipher))
            return Arrays.asList(converted.split("\n", -1));
        return Scoring.groups(converted);
    }

    private void save(String target, List<String> lines) {
        if (target != null)
            messages.put(target, new ArrayList<>(lines));
    }

    private void cipherJob(
        int job, String command, String cipher, String key, String source, String target
    ) {
        String text = letterString(source);
        if (text.isEmpty())
            fail("no letters");
        if (command.equals("DECRYPT") && cipher.equals("playfair") && !Playfair.valid(text))
            fail("bad playfair text");
        List<String> output = outputText(body(source), cipher, key, command.equals("ENCRYPT"));
        int letterCount = 0;
        for (String line : output)
            letterCount += Scoring.letters(line).length();
        String header = "JOB " + job + " " + command + " " + cipher + " key=" + key
            + " source=" + source + " letters=" + letterCount + " lines=" + output.size();
        if (target != null)
            header += " as=" + target;
        results.add(header);
        results.addAll(output);
        save(target, output);
    }

    private void breakJob(
        int job, String cipher, String source, String target, Map<String, String> options
    ) {
        String text = letterString(source);
        if (text.length() < 40)
            fail("text too short");
        if (cipher.equals("playfair") && !Playfair.valid(text))
            fail("bad playfair text");
        List<String> keys = cipher.equals("playfair")
            ? keyList(options.get("KEYS")) : List.of();
        if (cipher.equals("playfair") && keys.isEmpty())
            fail("empty key list");
        BreakOutcome broken = breakCipher(cipher, text, options, keys);
        Candidate winner = broken.choice();
        List<String> output = outputText(body(source), cipher, winner.key(), false);
        String header = "JOB " + job + " BREAK " + cipher + " source=" + source
            + " key=" + winner.key() + " score=" + winner.score()
            + " lines=" + output.size();
        if (target != null)
            header += " as=" + target;
        results.add(header);
        results.addAll(output);
        candidateReport(job, cipher, source, broken, option(options, "TOP"));
        breakAnalysis(job, cipher, source, text, options, broken);
        save(target, output);
    }

    private void analyzeJob(int job, String source, Map<String, String> options) {
        String text = letterString(source);
        if (text.length() < 40)
            fail("text too short");
        results.add("JOB " + job + " ANALYZE source=" + source + " letters=" + text.length());
        analysisLines.addAll(Analysis.report(
            job, source, text, weights, option(options, "MAXLEN")));
    }

    private void compareJob(int job, String firstName, String secondName) {
        String first = letterString(firstName);
        String second = letterString(secondName);
        int length = Math.min(first.length(), second.length());
        int position = length + 1;
        int mismatches = 0;
        for (int i = 0; i < length; i++) {
            if (first.charAt(i) != second.charAt(i)) {
                if (mismatches == 0)
                    position = i + 1;
                mismatches++;
            }
        }
        if (first.equals(second)) {
            results.add("JOB " + job + " COMPARE " + firstName + " " + secondName
                + " equal letters=" + first.length());
        } else {
            results.add("JOB " + job + " COMPARE " + firstName + " " + secondName
                + " differ letters=" + first.length() + "," + second.length()
                + " first=" + position + " mismatches=" + mismatches);
        }
    }

    private void identifyJob(int job, String source, Map<String, String> options) {
        String text = letterString(source);
        if (text.length() < 40)
            fail("text too short");
        int coincidence = Analysis.ioc(text);
        int average = Scoring.monogram(text, weights.mono()) / text.length();
        int distinct = 0;
        for (int count : Analysis.frequencies(text))
            if (count != 0)
                distinct++;
        boolean shape = text.indexOf('J') < 0 && Playfair.valid(text);
        String family = shape ? "playfair"
            : coincidence >= 5500 && average >= 44 ? "transposition"
            : coincidence >= 5500 ? "monoalphabetic" : "polyalphabetic";

        List<String> keys = null;
        if (family.equals("playfair") && options.containsKey("KEYS")) {
            keys = keyList(options.get("KEYS"));
            if (keys.isEmpty())
                fail("empty key list");
        }
        List<String> candidates = switch (family) {
            case "transposition" -> List.of("railfence", "columnar");
            case "monoalphabetic" -> List.of("affine");
            case "polyalphabetic" -> List.of("vigenere", "autokey");
            default -> keys == null ? List.of() : List.of("playfair");
        };

        Map<String, Candidate> tested = new LinkedHashMap<>();
        Candidate winner = null;
        String chosenCipher = null;
        for (String cipher : candidates) {
            List<String> raw = cipher.equals("playfair")
                ? List.of("KEYS=" + options.get("KEYS")) : List.of();
            Map<String, String> defaults = parseOptions("BREAK", cipher, raw);
            Candidate outcome = breakCipher(cipher, text, defaults, keys).choice();
            tested.put(cipher, outcome);
            if (winner == null || outcome.score() > winner.score()) {
                winner = outcome;
                chosenCipher = cipher;
            }
        }

        String header = "JOB " + job + " IDENTIFY source=" + source + " family=" + family;
        String reported = chosenCipher;
        if (winner == null) {
            results.add(header);
        } else {
            String key = winner.key();
            if (reported.equals("affine") && key.substring(0, key.indexOf(',')).equals("1")) {
                reported = "caesar";
                key = key.substring(key.indexOf(',') + 1);
            }
            List<String> output = outputText(body(source), reported, key, false);
            results.add(header + " cipher=" + reported + " key=" + key
                + " score=" + winner.score() + " lines=" + output.size());
            results.addAll(output);
        }
        analysisLines.add("JOB " + job + " IDENTIFY source=" + source);
        analysisLines.add("letters=" + text.length() + " ioc=" + coincidence
            + " mono_avg=" + average + " distinct=" + distinct
            + " shape=" + (shape ? "yes" : "no"));
        analysisLines.add("family=" + family);
        for (var entry : tested.entrySet())
            analysisLines.add("try " + entry.getKey() + " key=" + entry.getValue().key()
                + " score=" + entry.getValue().score());
        if (winner != null)
            analysisLines.add("choice " + reported);
    }

    private void checkReferences(
        List<String> words, String command, Map<String, String> options
    ) {
        String source = switch (command) {
            case "ENCRYPT", "DECRYPT" -> words.get(3);
            case "BREAK" -> words.get(2);
            default -> words.get(1);
        };
        if (!messages.containsKey(source))
            fail("unknown message " + source);
        if (options.containsKey("KEYS") && !messages.containsKey(options.get("KEYS")))
            fail("unknown message " + options.get("KEYS"));
        if (command.equals("COMPARE") && !messages.containsKey(words.get(2)))
            fail("unknown message " + words.get(2));
    }

    private void execute(int job, String line) {
        List<String> words = new ArrayList<>(Arrays.asList(line.split(" ", -1)));
        String command = words.get(0);
        if (!COMMANDS.contains(command))
            fail("unknown command");
        String target = null;
        if (Set.of("ENCRYPT", "DECRYPT", "BREAK").contains(command)
            && words.size() >= 5 && words.get(words.size() - 2).equals("AS")) {
            target = words.get(words.size() - 1);
            words = new ArrayList<>(words.subList(0, words.size() - 2));
            if (!validName(target))
                fail("bad syntax");
        }
        boolean valid = switch (command) {
            case "ENCRYPT", "DECRYPT" -> words.size() == 4;
            case "BREAK" -> words.size() >= 3;
            case "ANALYZE", "IDENTIFY" -> words.size() == 2 || words.size() == 3;
            default -> words.size() == 3;
        };
        if (!valid)
            fail("bad syntax");
        String cipher = Set.of("ENCRYPT", "DECRYPT", "BREAK").contains(command)
            ? words.get(1) : "";
        if (!cipher.isEmpty() && !CIPHERS.contains(cipher))
            fail("unknown cipher " + cipher);
        String key = Set.of("ENCRYPT", "DECRYPT").contains(command)
            ? normalizeKey(cipher, words.get(2)) : "";
        List<String> optionWords = switch (command) {
            case "BREAK" -> words.subList(3, words.size());
            case "ANALYZE", "IDENTIFY" -> words.subList(2, words.size());
            default -> List.of();
        };
        Map<String, String> options = parseOptions(command, cipher, optionWords);
        checkReferences(words, command, options);
        if (target != null && messages.containsKey(target))
            fail("duplicate message " + target);
        switch (command) {
            case "ENCRYPT", "DECRYPT" ->
                cipherJob(job, command, cipher, key, words.get(3), target);
            case "BREAK" -> breakJob(job, cipher, words.get(2), target, options);
            case "ANALYZE" -> analyzeJob(job, words.get(1), options);
            case "COMPARE" -> compareJob(job, words.get(1), words.get(2));
            case "IDENTIFY" -> identifyJob(job, words.get(1), options);
            default -> throw new IllegalStateException(command);
        }
    }

    private void runJobs(String path) throws IOException {
        int jobs = 0;
        int successful = 0;
        int errors = 0;
        for (String line : readLines(path)) {
            if (line.isEmpty() || line.charAt(0) == '#')
                continue;
            jobs++;
            String command = line.split(" ", 2)[0];
            try {
                execute(jobs, line);
                successful++;
                if (totals.containsKey(command))
                    totals.get(command)[0]++;
            } catch (JobFault fault) {
                errors++;
                if (totals.containsKey(command))
                    totals.get(command)[1]++;
                results.add("JOB " + jobs + " ERROR " + fault.getMessage());
            }
        }
        for (String command : COMMANDS) {
            int[] counts = totals.get(command);
            results.add("TOTAL " + command + " ok=" + counts[0] + " errors=" + counts[1]);
        }
        results.add("SUMMARY jobs=" + jobs + " ok=" + successful
            + " errors=" + errors + " messages=" + messages.size());
    }

    private static void write(String filename, List<String> lines) throws IOException {
        String text = lines.isEmpty() ? "" : String.join("\n", lines) + "\n";
        Files.writeString(Path.of("output", filename), text, StandardCharsets.US_ASCII);
    }

    private void run() throws IOException {
        runJobs("input/jobs.txt");
        Files.createDirectories(Path.of("output"));
        write("results.txt", results);
        write("candidates.txt", candidateLines);
        write("analysis.txt", analysisLines);
    }

    public static void main(String[] args) throws IOException {
        new Main().run();
    }
}
