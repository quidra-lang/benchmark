import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    static final String[] ADJACENT_KEYS = {
        "qswz", "ghnv", "dfvx", "cefrsx", "drsw", "cdgrtv", "bfhtvy", "bgjnuy",
        "jkou", "hikmnu", "ijlmo", "kop", "jkn", "bhjm", "iklp", "lo",
        "aw", "deft", "adewxz", "fgry", "hijy", "bcfg", "aeqs", "cdsz",
        "ghtu", "asx"
    };
    static final String[] COUNTERS = {"checked", "unknown", "case", "capital", "repeats", "corrected"};
    static final String[] FINDINGS = {"unknown", "case", "capital", "repeats"};
    static final Set<String> TEXT_COMMANDS = Set.of("CHECK", "CORRECT", "FIX", "PROFILE", "LEARN");
    static final Map<String, Integer> ARITIES = Map.ofEntries(
        Map.entry("SUGGEST", 1), Map.entry("DIST", 2), Map.entry("SOUNDEX", 1),
        Map.entry("SOUNDS", 1), Map.entry("SPLIT", 1), Map.entry("PREFIX", 2),
        Map.entry("COMPLETE", 2), Map.entry("LIST", 2), Map.entry("WORD", 1),
        Map.entry("ADD", 2), Map.entry("REMOVE", 1), Map.entry("IGNORE", 1),
        Map.entry("UNIGNORE", 1), Map.entry("RULE", 2), Map.entry("UNRULE", 1),
        Map.entry("RULES", 0), Map.entry("KEYBOARD", 1), Map.entry("SET", 2),
        Map.entry("UNDO", 0), Map.entry("REPORT", 0), Map.entry("HISTORY", 0),
        Map.entry("STATS", 0));
    static final Pattern WORD_ARGUMENT = Pattern.compile("[A-Za-z]{1,30}");
    static final Pattern NUMBER_ARGUMENT = Pattern.compile("[0-9]{1,7}");
    static final Pattern WORD_TOKEN = Pattern.compile("[A-Za-z]+");
    static final String[] SOUNDEX_DIGITS = new String[26];

    static {
        String[] groups = {"bfpv", "cgjkqsxz", "dt", "l", "mn", "r", "aeiouy"};
        for (int i = 0; i < groups.length; ++i) {
            for (char ch : groups[i].toCharArray()) SOUNDEX_DIGITS[ch - 'a'] = "" + (i == 6 ? 0 : i + 1);
        }
    }

    static class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    static String wordArgument(String text) {
        if (!WORD_ARGUMENT.matcher(text).matches()) throw new CommandError("BAD WORD " + text);
        return text.toLowerCase();
    }

    static int numberArgument(String text, int minimum, int maximum) {
        if (!NUMBER_ARGUMENT.matcher(text).matches()) throw new CommandError("BAD NUMBER " + text);
        int value = Integer.parseInt(text);
        if (value < minimum || value > maximum) throw new CommandError("BAD NUMBER " + text);
        return value;
    }

    static String decimalText(long numerator, long denominator, int digits) {
        long scale = digits == 1 ? 10 : 100;
        long value = (2 * numerator * scale + denominator) / (2 * denominator);
        String fraction = "" + (value % scale);
        return value / scale + "." + "0".repeat(digits - fraction.length()) + fraction;
    }

    static String applyCase(String original, String word) {
        if (original.length() >= 2 && original.equals(original.toUpperCase())) return word.toUpperCase();
        if (Character.isUpperCase(original.charAt(0))) return Character.toUpperCase(word.charAt(0)) + word.substring(1);
        return word;
    }

    static final class Token {
        final int number, start, end;
        final String text, word, gap;
        final boolean sentenceStart, repeat;
        Token(int number, String text, int start, int end, String gap, Token previous) {
            this.number = number;
            this.text = text;
            this.word = text.toLowerCase();
            this.start = start;
            this.end = end;
            this.gap = gap;
            sentenceStart = previous == null || gap.indexOf('.') >= 0 ||
                gap.indexOf('!') >= 0 || gap.indexOf('?') >= 0;
            repeat = previous != null && word.equals(previous.word) &&
                gap.chars().allMatch(ch -> ch == ' ');
        }
        boolean mixedCase() {
            for (int i = 1; i < text.length(); ++i) {
                if (Character.isUpperCase(text.charAt(i)) && !text.equals(text.toUpperCase())) return true;
            }
            return false;
        }
    }

    static List<Token> textTokens(String text) {
        List<Token> tokens = new ArrayList<>();
        Matcher matcher = WORD_TOKEN.matcher(text);
        Token previous = null;
        int position = 0;
        while (matcher.find()) {
            Token token = new Token(tokens.size() + 1, matcher.group(), matcher.start(), matcher.end(),
                text.substring(position, matcher.start()), previous);
            tokens.add(token);
            previous = token;
            position = matcher.end();
        }
        return tokens;
    }

    static int substitutionCost(char first, char second, boolean keyboard) {
        if (first == second) return 0;
        if (!keyboard) return 1;
        return ADJACENT_KEYS[first - 'a'].indexOf(second) >= 0 ? 1 : 2;
    }

    static boolean isSwap(String first, String second, int i, int j) {
        return i >= 2 && j >= 2 && first.charAt(i - 1) == second.charAt(j - 2) &&
            first.charAt(i - 2) == second.charAt(j - 1);
    }

    static int[][] distanceTable(String first, String second, boolean keyboard) {
        int rows = first.length(), columns = second.length();
        int gap = keyboard ? 2 : 1;
        int[][] table = new int[rows + 1][columns + 1];
        for (int i = 0; i <= rows; ++i) table[i][0] = i * gap;
        for (int j = 0; j <= columns; ++j) table[0][j] = j * gap;
        for (int i = 1; i <= rows; ++i) {
            for (int j = 1; j <= columns; ++j) {
                int best = Math.min(Math.min(table[i - 1][j] + gap, table[i][j - 1] + gap),
                    table[i - 1][j - 1] + substitutionCost(first.charAt(i - 1),
                                                            second.charAt(j - 1), keyboard));
                if (isSwap(first, second, i, j)) best = Math.min(best, table[i - 2][j - 2] + 1);
                table[i][j] = best;
            }
        }
        return table;
    }

    static int editDistance(String first, String second, boolean keyboard) {
        return distanceTable(first, second, keyboard)[first.length()][second.length()];
    }

    static int prefixDistance(String word, String other, boolean keyboard) {
        return Arrays.stream(distanceTable(word, other, keyboard)[word.length()]).min().orElse(0);
    }

    record DistanceResult(int distance, List<String> operations) {}

    static DistanceResult editOperations(String first, String second, boolean keyboard) {
        int[][] table = distanceTable(first, second, keyboard);
        int gap = keyboard ? 2 : 1;
        List<String> operations = new ArrayList<>();
        int i = first.length(), j = second.length();
        while (i > 0 || j > 0) {
            if (i >= 1 && j >= 1 && table[i][j] == table[i - 1][j - 1] +
                    substitutionCost(first.charAt(i - 1), second.charAt(j - 1), keyboard)) {
                if (first.charAt(i - 1) != second.charAt(j - 1)) {
                    operations.add("sub:" + first.charAt(i - 1) + ">" + second.charAt(j - 1));
                }
                --i; --j;
            } else if (isSwap(first, second, i, j) && table[i][j] == table[i - 2][j - 2] + 1) {
                operations.add("swap:" + first.charAt(i - 2) + first.charAt(i - 1));
                i -= 2; j -= 2;
            } else if (i >= 1 && table[i][j] == table[i - 1][j] + gap) {
                operations.add("del:" + first.charAt(i - 1));
                --i;
            } else {
                operations.add("ins:" + second.charAt(j - 1));
                --j;
            }
        }
        java.util.Collections.reverse(operations);
        return new DistanceResult(table[first.length()][second.length()], operations);
    }

    static String soundex(String word) {
        StringBuilder code = new StringBuilder(word.substring(0, 1).toUpperCase());
        char start = word.charAt(0);
        String previous = start == 'h' || start == 'w' ? "0" : SOUNDEX_DIGITS[start - 'a'];
        for (int i = 1; i < word.length(); ++i) {
            char letter = word.charAt(i);
            if (letter == 'h' || letter == 'w') continue;
            String digit = SOUNDEX_DIGITS[letter - 'a'];
            if (!digit.equals("0") && !digit.equals(previous)) code.append(digit);
            previous = digit;
        }
        return (code + "000").substring(0, 4);
    }

    static int compareWordLists(List<String> first, List<String> second) {
        for (int i = 0; i < Math.min(first.size(), second.size()); ++i) {
            int cmp = first.get(i).compareTo(second.get(i));
            if (cmp != 0) return cmp;
        }
        return Integer.compare(first.size(), second.size());
    }

    record Segmentation(long ways, List<String> best) {}

    static Segmentation segment(String word, Map<String, Integer> dictionary) {
        int length = word.length();
        long[] ways = new long[length + 1];
        @SuppressWarnings("unchecked")
        List<String>[] best = new List[length + 1];
        ways[length] = 1;
        best[length] = new ArrayList<>();
        for (int start = length - 1; start >= 0; --start) {
            for (int end = start + 1; end <= length; ++end) {
                String piece = word.substring(start, end);
                if (!dictionary.containsKey(piece) || ways[end] == 0) continue;
                ways[start] += ways[end];
                List<String> candidate = new ArrayList<>();
                candidate.add(piece);
                candidate.addAll(best[end]);
                if (best[start] == null || candidate.size() < best[start].size() ||
                    (candidate.size() == best[start].size() &&
                     compareWordLists(candidate, best[start]) < 0)) {
                    best[start] = candidate;
                }
            }
        }
        return new Segmentation(ways[0], best[0]);
    }

    record Candidate(String word, int distance, int frequency) {}
    record Snapshot(String name, Map<String, Integer> dictionary, Set<String> ignored,
                    Map<String, String> rules) {}

    static final class SpellChecker {
        Map<String, Integer> dictionary;
        Set<String> ignored = new HashSet<>();
        Map<String, String> rules = new HashMap<>();
        boolean keyboard = false;
        int baseLimit = 2;
        int suggestionCount = 5;
        final List<Snapshot> undoHistory = new ArrayList<>();
        final Map<String, Integer> unknownLog = new HashMap<>();
        final Map<String, Integer> correctionLog = new HashMap<>();
        final Map<String, Integer> counters = new LinkedHashMap<>();
        final List<String> output = new ArrayList<>();

        SpellChecker(Map<String, Integer> dictionary) {
            this.dictionary = dictionary;
            for (String name : COUNTERS) counters.put(name, 0);
        }

        void emit(String... parts) { output.add(String.join(" ", parts)); }
        int limit() { return keyboard ? 2 * baseLimit : baseLimit; }
        boolean isKnown(String word) { return dictionary.containsKey(word) || ignored.contains(word); }

        List<String> frequencyOrder() {
            List<String> words = new ArrayList<>(dictionary.keySet());
            words.sort((a, b) -> {
                int cmp = Integer.compare(dictionary.get(b), dictionary.get(a));
                return cmp != 0 ? cmp : a.compareTo(b);
            });
            return words;
        }

        int requireEntry(String word) {
            Integer value = dictionary.get(word);
            if (value == null) throw new CommandError("NOT FOUND " + word);
            return value;
        }

        List<Candidate> candidates(String word) {
            int maxDistance = limit(), gap = keyboard ? 2 : 1;
            List<Candidate> found = new ArrayList<>();
            for (Map.Entry<String, Integer> entry : dictionary.entrySet()) {
                String other = entry.getKey();
                if (other.equals(word) || Math.abs(other.length() - word.length()) * gap > maxDistance) continue;
                int distance = editDistance(word, other, keyboard);
                if (distance <= maxDistance) found.add(new Candidate(other, distance, entry.getValue()));
            }
            found.sort((a, b) -> {
                int byDistance = Integer.compare(a.distance(), b.distance());
                if (byDistance != 0) return byDistance;
                int byFrequency = Integer.compare(b.frequency(), a.frequency());
                return byFrequency != 0 ? byFrequency : a.word().compareTo(b.word());
            });
            return found;
        }

        String correction(String word) {
            if (isKnown(word)) return null;
            if (rules.containsKey(word)) return rules.get(word);
            List<Candidate> found = candidates(word);
            return found.isEmpty() ? null : found.get(0).word();
        }

        void recordUndo(String name) {
            undoHistory.add(new Snapshot(name, new HashMap<>(dictionary),
                new HashSet<>(ignored), new HashMap<>(rules)));
        }

        void logCorrection(String word, String replacement) {
            correctionLog.merge(word + ">" + replacement, 1, Integer::sum);
            counters.merge("corrected", 1, Integer::sum);
        }

        String unknownFinding(Token token) {
            String prefix = "UNKNOWN " + token.number + " " + token.text;
            if (rules.containsKey(token.word)) return prefix + " RULE " + rules.get(token.word);
            List<Candidate> found = candidates(token.word);
            if (found.isEmpty()) return prefix + " NONE";
            StringBuilder line = new StringBuilder(prefix).append(" SUGGEST");
            for (int i = 0; i < Math.min(suggestionCount, found.size()); ++i) {
                line.append(' ').append(found.get(i).word());
            }
            return line.toString();
        }

        void checkText(String text) {
            List<Token> tokens = textTokens(text);
            List<String> findings = new ArrayList<>();
            Map<String, Integer> counts = new HashMap<>();
            for (String name : FINDINGS) counts.put(name, 0);
            for (Token token : tokens) {
                if (!isKnown(token.word)) {
                    findings.add(unknownFinding(token));
                    counts.merge("unknown", 1, Integer::sum);
                    unknownLog.merge(token.word, 1, Integer::sum);
                }
                if (token.mixedCase()) {
                    findings.add("CASE " + token.number + " " + token.text);
                    counts.merge("case", 1, Integer::sum);
                }
                if (token.sentenceStart && Character.isLowerCase(token.text.charAt(0))) {
                    findings.add("CAPITAL " + token.number + " " + token.text);
                    counts.merge("capital", 1, Integer::sum);
                }
                if (token.repeat) {
                    findings.add("REPEAT " + token.number + " " + token.text);
                    counts.merge("repeats", 1, Integer::sum);
                }
            }
            counters.merge("checked", tokens.size(), Integer::sum);
            StringBuilder header = new StringBuilder("CHECK words=").append(tokens.size());
            for (String name : FINDINGS) {
                int count = counts.get(name);
                header.append(' ').append(name).append('=').append(count);
                counters.merge(name, count, Integer::sum);
            }
            output.add(header.toString());
            output.addAll(findings);
        }

        void correctText(String text) {
            StringBuilder result = new StringBuilder();
            int position = 0, changed = 0;
            for (Token token : textTokens(text)) {
                String replacement = correction(token.word);
                result.append(token.gap);
                if (replacement == null) {
                    result.append(token.text);
                } else {
                    result.append(applyCase(token.text, replacement));
                    logCorrection(token.word, replacement);
                    ++changed;
                }
                position = token.end;
            }
            result.append(text.substring(position));
            output.add("CORRECT changed=" + changed + ": " + result);
        }

        void fixText(String text) {
            StringBuilder result = new StringBuilder();
            int position = 0, removed = 0, replaced = 0, recased = 0;
            for (Token token : textTokens(text)) {
                position = token.end;
                if (token.repeat) {
                    ++removed;
                    continue;
                }
                String replacement = correction(token.word);
                String target = replacement == null ? token.word : replacement;
                String revised = applyCase(token.text, target);
                if (token.sentenceStart && Character.isLowerCase(revised.charAt(0))) {
                    revised = Character.toUpperCase(revised.charAt(0)) + revised.substring(1);
                }
                if (replacement != null) {
                    logCorrection(token.word, replacement);
                    ++replaced;
                } else if (!revised.equals(token.text)) {
                    ++recased;
                }
                result.append(token.gap).append(revised);
            }
            result.append(text.substring(position));
            output.add("FIX removed=" + removed + " replaced=" + replaced +
                " recased=" + recased + ": " + result);
        }

        void profile(String text) {
            List<Token> tokens = textTokens(text);
            Set<String> distinct = new HashSet<>();
            int unknown = 0, sentences = 0, characters = 0;
            String longest = "-";
            for (Token token : tokens) {
                distinct.add(token.word);
                if (!isKnown(token.word)) ++unknown;
                if (token.sentenceStart) ++sentences;
                characters += token.text.length();
                if (longest.equals("-") || token.text.length() > longest.length()) longest = token.word;
            }
            int size = tokens.size();
            String rate = size == 0 ? "0.0" : decimalText(100L * unknown, size, 1);
            String average = size == 0 ? "0.00" : decimalText(characters, size, 2);
            output.add("PROFILE words=" + size + " distinct=" + distinct.size() +
                " unknown=" + unknown + " rate=" + rate + " avglen=" + average +
                " longest=" + longest + " sentences=" + sentences);
        }

        void learn(String text) {
            recordUndo("LEARN");
            int updated = 0, added = 0, skipped = 0;
            for (Token token : textTokens(text)) {
                if (token.word.length() > 30) {
                    ++skipped;
                } else if (dictionary.containsKey(token.word)) {
                    dictionary.merge(token.word, 1, Integer::sum);
                    ++updated;
                } else {
                    dictionary.put(token.word, 1);
                    ignored.remove(token.word);
                    ++added;
                }
            }
            output.add("LEARN updated=" + updated + " added=" + added + " skipped=" + skipped);
        }

        void suggest(String[] args) {
            String word = wordArgument(args[0]);
            if (isKnown(word)) {
                emit("SUGGEST", word, "KNOWN");
            } else if (rules.containsKey(word)) {
                emit("SUGGEST", word, "RULE", rules.get(word));
            } else {
                List<Candidate> found = candidates(word);
                StringBuilder line = new StringBuilder("SUGGEST ").append(word)
                    .append(" found=").append(found.size());
                for (int i = 0; i < Math.min(suggestionCount, found.size()); ++i) {
                    Candidate candidate = found.get(i);
                    line.append(' ').append(candidate.word()).append(':').append(candidate.distance());
                }
                output.add(line.toString());
            }
        }

        void distance(String[] args) {
            String first = wordArgument(args[0]), second = wordArgument(args[1]);
            DistanceResult result = editOperations(first, second, keyboard);
            StringBuilder line = new StringBuilder("DIST ").append(first).append(' ')
                .append(second).append(' ').append(result.distance());
            for (String operation : result.operations()) line.append(' ').append(operation);
            output.add(line.toString());
        }

        void sounds(String[] args) {
            String word = wordArgument(args[0]);
            String code = soundex(word);
            List<String> matches = new ArrayList<>();
            for (String other : frequencyOrder()) {
                if (!other.equals(word) && soundex(other).equals(code)) matches.add(other);
            }
            StringBuilder line = new StringBuilder("SOUNDS ").append(word).append(' ')
                .append(code).append(" count=").append(matches.size());
            for (int i = 0; i < Math.min(10, matches.size()); ++i) line.append(' ').append(matches.get(i));
            output.add(line.toString());
        }

        void split(String[] args) {
            String word = wordArgument(args[0]);
            Segmentation segmentation = segment(word, dictionary);
            StringBuilder line = new StringBuilder("SPLIT ").append(word)
                .append(" ways=").append(segmentation.ways()).append(" ->");
            if (segmentation.ways() == 0) line.append(" NONE");
            else for (String piece : segmentation.best()) line.append(' ').append(piece);
            output.add(line.toString());
        }

        void prefix(String[] args) {
            String word = wordArgument(args[0]);
            int count = numberArgument(args[1], 1, 20);
            List<String> matches = new ArrayList<>();
            for (String other : frequencyOrder()) if (other.startsWith(word)) matches.add(other);
            StringBuilder line = new StringBuilder("PREFIX ").append(word).append(" count=").append(matches.size());
            for (int i = 0; i < Math.min(count, matches.size()); ++i) {
                String other = matches.get(i);
                line.append(' ').append(other).append(':').append(dictionary.get(other));
            }
            output.add(line.toString());
        }

        void complete(String[] args) {
            String word = wordArgument(args[0]);
            int count = numberArgument(args[1], 1, 20), threshold = limit() / 2;
            List<Candidate> found = new ArrayList<>();
            for (Map.Entry<String, Integer> entry : dictionary.entrySet()) {
                int distance = prefixDistance(word, entry.getKey(), keyboard);
                if (distance <= threshold) found.add(new Candidate(entry.getKey(), distance, entry.getValue()));
            }
            found.sort((a, b) -> {
                int cmp = Integer.compare(a.distance(), b.distance());
                if (cmp != 0) return cmp;
                cmp = Integer.compare(b.frequency(), a.frequency());
                return cmp != 0 ? cmp : a.word().compareTo(b.word());
            });
            StringBuilder line = new StringBuilder("COMPLETE ").append(word).append(" count=").append(found.size());
            for (int i = 0; i < Math.min(count, found.size()); ++i) {
                Candidate match = found.get(i);
                line.append(' ').append(match.word()).append(':').append(match.distance());
            }
            output.add(line.toString());
        }

        void listWords(String[] args) {
            String word = wordArgument(args[0]);
            int count = numberArgument(args[1], 1, 20);
            List<String> matches = new ArrayList<>();
            for (String other : dictionary.keySet()) if (other.compareTo(word) >= 0) matches.add(other);
            matches.sort(String::compareTo);
            StringBuilder line = new StringBuilder("LIST ").append(word).append(" count=").append(matches.size());
            for (int i = 0; i < Math.min(count, matches.size()); ++i) {
                String other = matches.get(i);
                line.append(' ').append(other).append(':').append(dictionary.get(other));
            }
            output.add(line.toString());
        }

        void wordInfo(String[] args) {
            String word = wordArgument(args[0]);
            int frequency = requireEntry(word);
            int rank = frequencyOrder().indexOf(word) + 1;
            output.add("WORD " + word + " freq=" + frequency + " rank=" + rank +
                " soundex=" + soundex(word) + " neighbors=" + candidates(word).size());
        }

        void add(String[] args) {
            String word = wordArgument(args[0]);
            int frequency = numberArgument(args[1], 1, 1000000);
            if (dictionary.containsKey(word)) throw new CommandError("DUPLICATE " + word);
            recordUndo("ADD");
            dictionary.put(word, frequency);
            ignored.remove(word);
            emit("ADD", word, "" + frequency);
        }

        void remove(String[] args) {
            String word = wordArgument(args[0]);
            int frequency = requireEntry(word);
            recordUndo("REMOVE");
            dictionary.remove(word);
            emit("REMOVE", word, "" + frequency);
        }

        void ignore(String[] args) {
            String word = wordArgument(args[0]);
            if (dictionary.containsKey(word)) throw new CommandError("IN DICTIONARY " + word);
            if (ignored.contains(word)) throw new CommandError("ALREADY IGNORED " + word);
            recordUndo("IGNORE");
            ignored.add(word);
            emit("IGNORE", word);
        }

        void unignore(String[] args) {
            String word = wordArgument(args[0]);
            if (!ignored.contains(word)) throw new CommandError("NOT IGNORED " + word);
            recordUndo("UNIGNORE");
            ignored.remove(word);
            emit("UNIGNORE", word);
        }

        void rule(String[] args) {
            String source = wordArgument(args[0]), target = wordArgument(args[1]);
            if (dictionary.containsKey(source)) throw new CommandError("IN DICTIONARY " + source);
            if (!dictionary.containsKey(target)) throw new CommandError("NOT FOUND " + target);
            recordUndo("RULE");
            String previous = rules.put(source, target);
            if (previous == null) emit("RULE", source, target);
            else emit("RULE", source, target, "REPLACED", previous);
        }

        void unrule(String[] args) {
            String word = wordArgument(args[0]);
            if (!rules.containsKey(word)) throw new CommandError("NO RULE " + word);
            recordUndo("UNRULE");
            emit("UNRULE", word, rules.remove(word));
        }

        void showRules() {
            List<String> sources = new ArrayList<>(rules.keySet());
            sources.sort(String::compareTo);
            StringBuilder line = new StringBuilder("RULES count=").append(sources.size());
            for (String source : sources) line.append(' ').append(source).append('>').append(rules.get(source));
            output.add(line.toString());
        }

        void keyboardMode(String[] args) {
            String mode = args[0];
            if (!mode.equals("ON") && !mode.equals("OFF")) throw new CommandError("BAD MODE " + mode);
            keyboard = mode.equals("ON");
            emit("KEYBOARD", mode);
        }

        void setOption(String[] args) {
            String option = args[0];
            if (!option.equals("LIMIT") && !option.equals("SUGGESTIONS")) {
                throw new CommandError("BAD OPTION " + option);
            }
            int value = numberArgument(args[1], 1, option.equals("LIMIT") ? 3 : 10);
            if (option.equals("LIMIT")) baseLimit = value;
            else suggestionCount = value;
            emit("SET", option, "" + value);
        }

        void undo() {
            if (undoHistory.isEmpty()) throw new CommandError("NOTHING TO UNDO");
            Snapshot record = undoHistory.remove(undoHistory.size() - 1);
            dictionary = record.dictionary();
            ignored = record.ignored();
            rules = record.rules();
            emit("UNDO", record.name());
        }

        void report() {
            List<String> words = new ArrayList<>(unknownLog.keySet());
            words.sort((a, b) -> {
                int cmp = Integer.compare(unknownLog.get(b), unknownLog.get(a));
                return cmp != 0 ? cmp : a.compareTo(b);
            });
            StringBuilder line = new StringBuilder("REPORT distinct=").append(words.size());
            for (int i = 0; i < Math.min(10, words.size()); ++i) {
                String word = words.get(i);
                line.append(' ').append(word).append(':').append(unknownLog.get(word));
            }
            output.add(line.toString());
        }

        void history() {
            List<String> corrections = new ArrayList<>(correctionLog.keySet());
            corrections.sort((a, b) -> {
                int cmp = Integer.compare(correctionLog.get(b), correctionLog.get(a));
                return cmp != 0 ? cmp : a.compareTo(b);
            });
            StringBuilder line = new StringBuilder("HISTORY distinct=").append(corrections.size());
            for (int i = 0; i < Math.min(10, corrections.size()); ++i) {
                String correction = corrections.get(i);
                line.append(' ').append(correction).append(':').append(correctionLog.get(correction));
            }
            output.add(line.toString());
        }

        void stats() {
            List<String> words = frequencyOrder();
            String top = words.get(0);
            long total = 0, characters = 0;
            for (String word : words) {
                total += dictionary.get(word);
                characters += word.length();
            }
            output.add("STATS words=" + words.size() + " total=" + total +
                " avglen=" + decimalText(characters, words.size(), 2) +
                " top=" + top + ":" + dictionary.get(top) +
                " ignored=" + ignored.size() + " rules=" + rules.size() +
                " keyboard=" + (keyboard ? "ON" : "OFF") + " limit=" + limit() +
                " suggestions=" + suggestionCount + " undo=" + undoHistory.size());
            StringBuilder session = new StringBuilder("SESSION");
            for (String counter : COUNTERS) session.append(' ').append(counter).append('=').append(counters.get(counter));
            output.add(session.toString());
        }

        void execute(String line) {
            int space = line.indexOf(' ');
            String name = space == -1 ? line : line.substring(0, space);
            String rest = space == -1 ? "" : line.substring(space + 1);
            try {
                if (TEXT_COMMANDS.contains(name)) {
                    if (space < 0) throw new CommandError("BAD ARGUMENTS " + name);
                    switch (name) {
                        case "CHECK" -> checkText(rest);
                        case "CORRECT" -> correctText(rest);
                        case "FIX" -> fixText(rest);
                        case "PROFILE" -> profile(rest);
                        case "LEARN" -> learn(rest);
                    }
                    return;
                }
                Integer expected = ARITIES.get(name);
                if (expected == null) throw new CommandError("UNKNOWN COMMAND " + name);
                String[] args = space == -1 ? new String[0] : rest.split(" ", -1);
                if (args.length != expected) throw new CommandError("BAD ARGUMENTS " + name);
                switch (name) {
                    case "SUGGEST" -> suggest(args);
                    case "DIST" -> distance(args);
                    case "SOUNDEX" -> { String w = wordArgument(args[0]); emit("SOUNDEX", w, soundex(w)); }
                    case "SOUNDS" -> sounds(args);
                    case "SPLIT" -> split(args);
                    case "PREFIX" -> prefix(args);
                    case "COMPLETE" -> complete(args);
                    case "LIST" -> listWords(args);
                    case "WORD" -> wordInfo(args);
                    case "ADD" -> add(args);
                    case "REMOVE" -> remove(args);
                    case "IGNORE" -> ignore(args);
                    case "UNIGNORE" -> unignore(args);
                    case "RULE" -> rule(args);
                    case "UNRULE" -> unrule(args);
                    case "RULES" -> showRules();
                    case "KEYBOARD" -> keyboardMode(args);
                    case "SET" -> setOption(args);
                    case "UNDO" -> undo();
                    case "REPORT" -> report();
                    case "HISTORY" -> history();
                    case "STATS" -> stats();
                    default -> throw new IllegalStateException("Unhandled command " + name);
                }
            } catch (CommandError e) {
                emit("ERROR", e.getMessage());
            }
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        Map<String, Integer> dictionary = new HashMap<>();
        for (int i = 0; i < count; ++i) {
            String[] entry = input.readLine().split(" ");
            dictionary.put(entry[0], Integer.parseInt(entry[1]));
        }
        SpellChecker checker = new SpellChecker(dictionary);
        int commands = Integer.parseInt(input.readLine());
        for (int i = 0; i < commands; ++i) checker.execute(input.readLine());
        System.out.print(String.join("\n", checker.output) + "\n");
    }
}
