import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.OptionalInt;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.function.Consumer;
import java.util.function.Predicate;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;

public class Main {
    private static final Pattern TOKEN_PATTERN = Pattern.compile("[A-Za-z]+");
    private static final Pattern WORD_PATTERN = Pattern.compile("[A-Za-z]{1,30}");
    private static final Pattern NUMBER_PATTERN = Pattern.compile("[0-9]{1,7}");
    private static final Pattern PREFIX_TERM_PATTERN = Pattern.compile("[A-Za-z]{1,30}\\*");
    private static final Pattern LEXEME_PATTERN = Pattern.compile("[()]|[^ ()]+");
    private static final String VOWELS = "aeiou";
    private static final List<String> STEP_NAMES =
            List.of("1a", "1b", "1c", "2", "3", "4", "5a", "5b");
    private static final List<String> STEP_4_SUFFIXES = List.of(
            "al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment",
            "ent", "ion", "ou", "ism", "ate", "iti", "ous", "ive", "ize");
    private static final int KWIC_WIDTH = 30;
    private static final int MAX_COUNT = 100;
    private static final int MAX_DOCUMENT_NUMBER = 999;
    private static final int MAX_LINE_NUMBER = 999;

    static final class CommandError extends RuntimeException {
        CommandError(String message) {
            super(message);
        }
    }

    record Rule(String suffix, String replacement, Predicate<String> condition) {}

    record RuleOutcome(String word, String suffix) {}

    record StepChange(String step, String word) {}

    record Stemming(String stem, List<StepChange> changes) {}

    record Token(String text, String form, String stem, int line, int position, int start) {
        int end() {
            return start + text.length();
        }
    }

    record Occurrence(Document document, Token token) {
        String reference() {
            return document.reference(token);
        }
    }

    record StemCount(String stem, int count) {}

    record Fraction(int numerator, int denominator) implements Comparable<Fraction> {
        static Fraction of(int numerator, int denominator) {
            int divisor = gcd(numerator, denominator);
            return new Fraction(numerator / divisor, denominator / divisor);
        }

        @Override
        public int compareTo(Fraction other) {
            return Long.compare(
                    (long) numerator * other.denominator, (long) other.numerator * denominator);
        }

        @Override
        public String toString() {
            return numerator + "/" + denominator;
        }
    }

    record Similarity(int document, Fraction score) {}

    record Ranking(int document, int matched, int total) {}

    enum Kind { AND, OR, NOT, OPEN, CLOSE, TERM, PREFIX }

    record QueryItem(Kind kind, String spelling) {}

    record QueryResult(String canonical, Set<Integer> documents) {}

    record Command(int minimum, int maximum, Consumer<List<String>> handler) {}

    private static final Map<String, Kind> SYMBOLS = Map.of(
            "AND", Kind.AND, "OR", Kind.OR, "NOT", Kind.NOT, "(", Kind.OPEN, ")", Kind.CLOSE);
    private static final Set<Kind> CONJUNCTION_CONTINUATIONS =
            EnumSet.of(Kind.AND, Kind.NOT, Kind.OPEN, Kind.TERM, Kind.PREFIX);
    private static final Comparator<StemCount> BY_COUNT =
            Comparator.comparingInt(StemCount::count).reversed().thenComparing(StemCount::stem);

    static int gcd(int first, int second) {
        return second == 0 ? first : gcd(second, first % second);
    }

    static String letterPattern(String word) {
        var kinds = new StringBuilder();
        for (int index = 0; index < word.length(); index++) {
            char letter = word.charAt(index);
            boolean vowel = VOWELS.indexOf(letter) >= 0
                    || (letter == 'y' && index > 0 && kinds.charAt(index - 1) == 'C');
            kinds.append(vowel ? 'V' : 'C');
        }
        return kinds.toString();
    }

    static int measure(String word) {
        String pattern = letterPattern(word);
        int count = 0;
        for (int index = 1; index < pattern.length(); index++) {
            if (pattern.charAt(index - 1) == 'V' && pattern.charAt(index) == 'C') {
                count++;
            }
        }
        return count;
    }

    static boolean hasVowel(String word) {
        return letterPattern(word).contains("V");
    }

    static boolean endsDouble(String word) {
        int length = word.length();
        return letterPattern(word).endsWith("CC")
                && word.charAt(length - 1) == word.charAt(length - 2);
    }

    static boolean endsCvc(String word) {
        return letterPattern(word).endsWith("CVC")
                && "wxy".indexOf(word.charAt(word.length() - 1)) < 0;
    }

    static boolean measureAboveZero(String remainder) {
        return measure(remainder) > 0;
    }

    static boolean measureAboveOne(String remainder) {
        return measure(remainder) > 1;
    }

    static boolean ionCondition(String remainder) {
        return measure(remainder) > 1 && (remainder.endsWith("s") || remainder.endsWith("t"));
    }

    static boolean finalECondition(String remainder) {
        int value = measure(remainder);
        return value > 1 || (value == 1 && !endsCvc(remainder));
    }

    static List<Rule> rulesWith(Predicate<String> condition, String[][] replacements) {
        return Arrays.stream(replacements)
                .map(pair -> new Rule(pair[0], pair[1], condition))
                .toList();
    }

    private static final Map<String, List<Rule>> RULE_TABLES = Map.of(
            "1a", rulesWith(remainder -> true,
                    new String[][] {{"sses", "ss"}, {"ies", "i"}, {"ss", "ss"}, {"s", ""}}),
            "1b", List.of(
                    new Rule("eed", "ee", Main::measureAboveZero),
                    new Rule("ed", "", Main::hasVowel),
                    new Rule("ing", "", Main::hasVowel)),
            "1c", List.of(new Rule("y", "i", Main::hasVowel)),
            "2", rulesWith(Main::measureAboveZero, new String[][] {
                {"ational", "ate"}, {"tional", "tion"}, {"enci", "ence"}, {"anci", "ance"},
                {"izer", "ize"}, {"abli", "able"}, {"alli", "al"}, {"entli", "ent"},
                {"eli", "e"}, {"ousli", "ous"}, {"ization", "ize"}, {"ation", "ate"},
                {"ator", "ate"}, {"alism", "al"}, {"iveness", "ive"}, {"fulness", "ful"},
                {"ousness", "ous"}, {"aliti", "al"}, {"iviti", "ive"}, {"biliti", "ble"},
            }),
            "3", rulesWith(Main::measureAboveZero, new String[][] {
                {"icate", "ic"}, {"ative", ""}, {"alize", "al"}, {"iciti", "ic"},
                {"ical", "ic"}, {"ful", ""}, {"ness", ""},
            }),
            "4", STEP_4_SUFFIXES.stream()
                    .map(suffix -> new Rule(suffix, "",
                            suffix.equals("ion") ? Main::ionCondition : Main::measureAboveOne))
                    .toList(),
            "5a", List.of(new Rule("e", "", Main::finalECondition)));

    static RuleOutcome applyRules(String word, List<Rule> rules) {
        Optional<Rule> selected = rules.stream()
                .filter(rule -> word.endsWith(rule.suffix()))
                .max(Comparator.comparingInt(rule -> rule.suffix().length()));
        if (selected.isEmpty()) {
            return new RuleOutcome(word, null);
        }
        Rule rule = selected.get();
        String remainder = word.substring(0, word.length() - rule.suffix().length());
        if (!rule.condition().test(remainder)) {
            return new RuleOutcome(word, null);
        }
        return new RuleOutcome(remainder + rule.replacement(), rule.suffix());
    }

    static String tidyStep1b(String word) {
        if (word.endsWith("at") || word.endsWith("bl") || word.endsWith("iz")) {
            return word + "e";
        }
        if (endsDouble(word) && "lsz".indexOf(word.charAt(word.length() - 1)) < 0) {
            return word.substring(0, word.length() - 1);
        }
        if (measure(word) == 1 && endsCvc(word)) {
            return word + "e";
        }
        return word;
    }

    static String applyStep(String name, String word) {
        if (name.equals("5b")) {
            if (measure(word) > 1 && endsDouble(word) && word.endsWith("l")) {
                return word.substring(0, word.length() - 1);
            }
            return word;
        }
        RuleOutcome outcome = applyRules(word, RULE_TABLES.get(name));
        String suffix = outcome.suffix();
        if (name.equals("1b") && ("ed".equals(suffix) || "ing".equals(suffix))) {
            return tidyStep1b(outcome.word());
        }
        return outcome.word();
    }

    static Stemming stemmingSteps(String word) {
        var changes = new ArrayList<StepChange>();
        String current = word;
        if (word.length() > 2) {
            for (String name : STEP_NAMES) {
                String result = applyStep(name, current);
                if (!result.equals(current)) {
                    changes.add(new StepChange(name, result));
                }
                current = result;
            }
        }
        return new Stemming(current, changes);
    }

    static String porterStem(String word) {
        return stemmingSteps(word).stem();
    }

    static String yesNo(boolean flag) {
        return flag ? "YES" : "NO";
    }

    static String lower(String text) {
        return text.toLowerCase(Locale.ROOT);
    }

    static String wordArgument(String text) {
        if (!WORD_PATTERN.matcher(text).matches()) {
            throw new CommandError("BAD WORD " + text);
        }
        return lower(text);
    }

    static int numberArgument(String text, int minimum, int maximum) {
        if (!NUMBER_PATTERN.matcher(text).matches()) {
            throw new CommandError("BAD NUMBER " + text);
        }
        int value = Integer.parseInt(text);
        if (value < minimum || value > maximum) {
            throw new CommandError("BAD NUMBER " + text);
        }
        return value;
    }

    static List<String> splitArguments(String name, String rest) {
        return switch (name) {
            case "SEARCH" -> List.of(rest);
            case "APPEND" -> List.of(rest.split(" ", 2));
            default -> List.of(rest.split(" ", -1));
        };
    }

    static Stream<StemCount> stemCounts(Map<String, Integer> counts) {
        return counts.entrySet().stream()
                .map(entry -> new StemCount(entry.getKey(), entry.getValue()));
    }

    static long documentCount(List<Occurrence> occurrences) {
        return occurrences.stream()
                .map(occurrence -> occurrence.document().number)
                .distinct()
                .count();
    }

    static OptionalInt closestDistance(
            List<Integer> positions, List<Integer> others, boolean sameStem) {
        var gaps = new ArrayList<Integer>();
        if (sameStem) {
            for (int index = 1; index < positions.size(); index++) {
                gaps.add(positions.get(index) - positions.get(index - 1));
            }
        } else {
            // The closest pair of different stems is adjacent in the merged order.
            record Marker(int position, int source) {}
            var merged = new ArrayList<Marker>();
            positions.forEach(position -> merged.add(new Marker(position, 0)));
            others.forEach(other -> merged.add(new Marker(other, 1)));
            merged.sort(Comparator.comparingInt(Marker::position));
            for (int index = 1; index < merged.size(); index++) {
                Marker earlier = merged.get(index - 1);
                Marker later = merged.get(index);
                if (earlier.source() != later.source()) {
                    gaps.add(later.position() - earlier.position());
                }
            }
        }
        return gaps.stream().mapToInt(Integer::intValue).min();
    }

    static QueryItem classify(String lexeme) {
        Kind symbol = SYMBOLS.get(lexeme);
        if (symbol != null) {
            return new QueryItem(symbol, lexeme);
        }
        if (WORD_PATTERN.matcher(lexeme).matches()) {
            return new QueryItem(Kind.TERM, lower(lexeme));
        }
        if (PREFIX_TERM_PATTERN.matcher(lexeme).matches()) {
            return new QueryItem(Kind.PREFIX, lower(lexeme.substring(0, lexeme.length() - 1)));
        }
        throw new CommandError("BAD TERM " + lexeme);
    }

    static final class Document {
        final int number;
        final List<String> lines = new ArrayList<>();
        final List<Token> tokens = new ArrayList<>();

        Document(int number) {
            this.number = number;
        }

        List<Token> addLine(String text) {
            lines.add(text);
            var added = new ArrayList<Token>();
            Matcher matcher = TOKEN_PATTERN.matcher(text);
            while (matcher.find()) {
                String form = lower(matcher.group());
                var token = new Token(matcher.group(), form, porterStem(form), lines.size(),
                        tokens.size() + 1, matcher.start());
                tokens.add(token);
                added.add(token);
            }
            return added;
        }

        List<Token> lineTokens(int lineNumber) {
            return tokens.stream().filter(token -> token.line() == lineNumber).toList();
        }

        String reference(Token token) {
            return number + ":" + token.line() + ":" + token.position();
        }
    }

    static final class QueryParser {
        private final List<QueryItem> items;
        private final Map<Integer, Set<String>> stemSets;
        private int position;

        QueryParser(List<QueryItem> items, Map<Integer, Set<String>> stemSets) {
            this.items = items;
            this.stemSets = stemSets;
        }

        private Kind peek() {
            return position < items.size() ? items.get(position).kind() : null;
        }

        private QueryItem take() {
            if (position >= items.size()) {
                throw new CommandError("SYNTAX");
            }
            return items.get(position++);
        }

        QueryResult parse() {
            QueryResult result = expression();
            if (position < items.size()) {
                throw new CommandError("SYNTAX");
            }
            return result;
        }

        private QueryResult expression() {
            QueryResult result = conjunction();
            while (peek() == Kind.OR) {
                position++;
                QueryResult right = conjunction();
                var documents = new TreeSet<>(result.documents());
                documents.addAll(right.documents());
                result = new QueryResult(
                        "(" + result.canonical() + " OR " + right.canonical() + ")", documents);
            }
            return result;
        }

        private QueryResult conjunction() {
            QueryResult result = negation();
            while (CONJUNCTION_CONTINUATIONS.contains(peek())) {
                if (peek() == Kind.AND) {
                    position++;
                }
                QueryResult right = negation();
                var documents = new TreeSet<>(result.documents());
                documents.retainAll(right.documents());
                result = new QueryResult(
                        "(" + result.canonical() + " AND " + right.canonical() + ")", documents);
            }
            return result;
        }

        private QueryResult negation() {
            if (peek() == Kind.NOT) {
                position++;
                QueryResult inner = negation();
                var documents = new TreeSet<>(stemSets.keySet());
                documents.removeAll(inner.documents());
                return new QueryResult("(NOT " + inner.canonical() + ")", documents);
            }
            return element();
        }

        private QueryResult element() {
            QueryItem item = take();
            return switch (item.kind()) {
                case OPEN -> {
                    QueryResult result = expression();
                    if (take().kind() != Kind.CLOSE) {
                        throw new CommandError("SYNTAX");
                    }
                    yield result;
                }
                case TERM -> {
                    String stem = porterStem(item.spelling());
                    yield new QueryResult(stem, documentsWhere(stems -> stems.contains(stem)));
                }
                case PREFIX -> {
                    String prefix = item.spelling();
                    yield new QueryResult(prefix + "*", documentsWhere(
                            stems -> stems.stream().anyMatch(stem -> stem.startsWith(prefix))));
                }
                default -> throw new CommandError("SYNTAX");
            };
        }

        private Set<Integer> documentsWhere(Predicate<Set<String>> condition) {
            return stemSets.entrySet().stream()
                    .filter(entry -> condition.test(entry.getValue()))
                    .map(Map.Entry::getKey)
                    .collect(Collectors.toCollection(TreeSet::new));
        }
    }

    static final class SearchEngine {
        private final Set<String> stopwords;
        private final Map<Integer, Document> documents = new TreeMap<>();
        private final StringBuilder output = new StringBuilder();
        private final Map<String, Command> handlers = Map.ofEntries(
                Map.entry("STEM", new Command(1, 10, this::stemWords)),
                Map.entry("STEPS", new Command(1, 1, this::showSteps)),
                Map.entry("MEASURE", new Command(1, 1, this::showMeasure)),
                Map.entry("INDEX", new Command(0, 1, this::showIndex)),
                Map.entry("SEARCH", new Command(1, 1, this::search)),
                Map.entry("PHRASE", new Command(2, 10, this::phrase)),
                Map.entry("NEAR", new Command(3, 3, this::near)),
                Map.entry("TOP", new Command(1, 2, this::top)),
                Map.entry("KWIC", new Command(1, 1, this::kwic)),
                Map.entry("TF", new Command(2, 2, this::termFrequency)),
                Map.entry("DF", new Command(1, 1, this::documentFrequency)),
                Map.entry("VARIANTS", new Command(1, 1, this::variants)),
                Map.entry("SIMILAR", new Command(2, 2, this::similar)),
                Map.entry("RANK", new Command(2, 11, this::rank)),
                Map.entry("INFO", new Command(1, 1, this::info)),
                Map.entry("LINE", new Command(2, 2, this::showLine)),
                Map.entry("STATS", new Command(0, 0, this::stats)),
                Map.entry("STOP", new Command(1, 1, this::stop)),
                Map.entry("UNSTOP", new Command(1, 1, this::unstop)),
                Map.entry("APPEND", new Command(2, 2, this::append)),
                Map.entry("DELETE", new Command(1, 1, this::delete)));

        SearchEngine(Set<String> stopwords) {
            this.stopwords = stopwords;
        }

        String output() {
            return output.toString();
        }

        private void emit(String head, List<String> items) {
            output.append(head);
            for (String item : items) {
                output.append(' ').append(item);
            }
            output.append('\n');
        }

        private void emit(String line) {
            emit(line, List.of());
        }

        Document addDocument(int number) {
            var document = new Document(number);
            documents.put(number, document);
            return document;
        }

        private boolean isStopword(String word) {
            return stopwords.contains(word);
        }

        private boolean isIndexed(Token token) {
            return !isStopword(token.form());
        }

        private List<Token> indexedTokens(Document document) {
            return document.tokens.stream().filter(this::isIndexed).toList();
        }

        private Map<String, Integer> termFrequencies(Document document) {
            var counts = new HashMap<String, Integer>();
            for (Token token : indexedTokens(document)) {
                counts.merge(token.stem(), 1, Integer::sum);
            }
            return counts;
        }

        private Set<String> stemSet(Document document) {
            return new HashSet<>(termFrequencies(document).keySet());
        }

        private Map<String, Integer> totalFrequencies() {
            var totals = new HashMap<String, Integer>();
            for (Document document : documents.values()) {
                termFrequencies(document)
                        .forEach((stem, count) -> totals.merge(stem, count, Integer::sum));
            }
            return totals;
        }

        private Map<String, List<Occurrence>> occurrenceMap() {
            var occurrences = new TreeMap<String, List<Occurrence>>();
            for (Document document : documents.values()) {
                for (Token token : indexedTokens(document)) {
                    occurrences.computeIfAbsent(token.stem(), stem -> new ArrayList<>())
                            .add(new Occurrence(document, token));
                }
            }
            return occurrences;
        }

        private List<Occurrence> occurrencesOf(String stem) {
            return occurrenceMap().getOrDefault(stem, List.of());
        }

        private List<Integer> stemPositions(Document document, String stem) {
            return indexedTokens(document).stream()
                    .filter(token -> token.stem().equals(stem))
                    .map(Token::position)
                    .toList();
        }

        private long formCount(String form) {
            return documents.values().stream()
                    .flatMap(document -> document.tokens.stream())
                    .filter(token -> token.form().equals(form))
                    .count();
        }

        private boolean tokenMatches(Token token, String target) {
            return target.equals("?") || (isIndexed(token) && token.stem().equals(target));
        }

        private boolean phraseMatches(List<Token> tokens, int start, List<String> targets) {
            for (int offset = 0; offset < targets.size(); offset++) {
                if (!tokenMatches(tokens.get(start + offset), targets.get(offset))) {
                    return false;
                }
            }
            return true;
        }

        private String describeToken(Token token) {
            return token.form() + "/" + (isIndexed(token) ? token.stem() : "-");
        }

        private String termArgument(String text) {
            String word = wordArgument(text);
            if (isStopword(word)) {
                throw new CommandError("STOPWORD " + word);
            }
            return porterStem(word);
        }

        private Document documentArgument(String text) {
            int number = numberArgument(text, 1, MAX_DOCUMENT_NUMBER);
            Document document = documents.get(number);
            if (document == null) {
                throw new CommandError("NO DOC " + number);
            }
            return document;
        }

        private void stemWords(List<String> arguments) {
            List<String> words = arguments.stream().map(Main::wordArgument).toList();
            emit("STEM", words.stream().map(word -> word + ":" + porterStem(word)).toList());
        }

        private void showSteps(List<String> arguments) {
            String word = wordArgument(arguments.get(0));
            List<StepChange> changes = stemmingSteps(word).changes();
            if (changes.isEmpty()) {
                emit("STEPS " + word + " NONE");
            } else {
                emit("STEPS " + word, changes.stream()
                        .map(change -> change.step() + ":" + change.word())
                        .toList());
            }
        }

        private void showMeasure(List<String> arguments) {
            String word = wordArgument(arguments.get(0));
            emit("MEASURE %s %s m=%d vowel=%s double=%s cvc=%s".formatted(
                    word, letterPattern(word), measure(word), yesNo(hasVowel(word)),
                    yesNo(endsDouble(word)), yesNo(endsCvc(word))));
        }

        private void showIndex(List<String> arguments) {
            String prefix = arguments.isEmpty() ? "" : wordArgument(arguments.get(0));
            Map<String, List<Occurrence>> occurrences = occurrenceMap();
            List<String> stems = occurrences.keySet().stream()
                    .filter(stem -> stem.startsWith(prefix))
                    .toList();
            emit("INDEX stems=" + stems.size());
            for (String stem : stems) {
                List<Occurrence> found = occurrences.get(stem);
                emit(stem + " df=" + documentCount(found),
                        found.stream().map(Occurrence::reference).toList());
            }
        }

        private void search(List<String> arguments) {
            List<QueryItem> items = LEXEME_PATTERN.matcher(arguments.get(0)).results()
                    .map(match -> classify(match.group()))
                    .toList();
            var stemSets = new TreeMap<Integer, Set<String>>();
            for (Document document : documents.values()) {
                stemSets.put(document.number, stemSet(document));
            }
            QueryResult result = new QueryParser(items, stemSets).parse();
            for (QueryItem item : items) {
                if (item.kind() == Kind.TERM && isStopword(item.spelling())) {
                    throw new CommandError("STOPWORD " + item.spelling());
                }
            }
            emit("SEARCH " + result.canonical() + " count=" + result.documents().size(),
                    result.documents().stream().sorted().map(String::valueOf).toList());
        }

        private void phrase(List<String> arguments) {
            List<String> words = arguments.stream().map(Main::wordArgument).toList();
            if (words.stream().allMatch(this::isStopword)) {
                throw new CommandError("STOPWORDS ONLY");
            }
            List<String> targets = words.stream()
                    .map(word -> isStopword(word) ? "?" : porterStem(word))
                    .toList();
            var matches = new ArrayList<String>();
            for (Document document : documents.values()) {
                List<Token> tokens = document.tokens;
                for (int start = 0; start + targets.size() <= tokens.size(); start++) {
                    if (phraseMatches(tokens, start, targets)) {
                        matches.add(document.reference(tokens.get(start)));
                    }
                }
            }
            emit("PHRASE \"" + String.join(" ", targets) + "\" matches=" + matches.size(), matches);
        }

        private void near(List<String> arguments) {
            String first = termArgument(arguments.get(0));
            String second = termArgument(arguments.get(1));
            int limit = numberArgument(arguments.get(2), 1, MAX_COUNT);
            var found = new ArrayList<String>();
            for (Document document : documents.values()) {
                OptionalInt distance = closestDistance(stemPositions(document, first),
                        stemPositions(document, second), first.equals(second));
                if (distance.isPresent() && distance.getAsInt() <= limit) {
                    found.add(document.number + ":" + distance.getAsInt());
                }
            }
            emit("NEAR %s %s %d count=%d".formatted(first, second, limit, found.size()), found);
        }

        private void top(List<String> arguments) {
            int limit = numberArgument(arguments.get(0), 1, MAX_COUNT);
            Map<String, Integer> counts;
            String header;
            if (arguments.size() == 2) {
                Document document = documentArgument(arguments.get(1));
                counts = termFrequencies(document);
                header = "TOP " + limit + " doc=" + document.number;
            } else {
                counts = totalFrequencies();
                header = "TOP " + limit;
            }
            emit(header, stemCounts(counts)
                    .sorted(BY_COUNT)
                    .limit(limit)
                    .map(entry -> entry.stem() + ":" + entry.count())
                    .toList());
        }

        private void kwic(List<String> arguments) {
            String stem = termArgument(arguments.get(0));
            List<Occurrence> found = occurrencesOf(stem);
            emit("KWIC " + stem + " count=" + found.size());
            for (Occurrence occurrence : found) {
                Token token = occurrence.token();
                String text = occurrence.document().lines.get(token.line() - 1);
                String before =
                        text.substring(Math.max(0, token.start() - KWIC_WIDTH), token.start());
                int end = Math.min(text.length(), token.end() + KWIC_WIDTH);
                String after = text.substring(token.end(), end);
                emit("|" + " ".repeat(KWIC_WIDTH - before.length()) + before
                        + "[" + token.text() + "]"
                        + after + " ".repeat(KWIC_WIDTH - after.length())
                        + "| " + occurrence.reference());
            }
        }

        private void termFrequency(List<String> arguments) {
            Document document = documentArgument(arguments.get(0));
            String stem = termArgument(arguments.get(1));
            int count = termFrequencies(document).getOrDefault(stem, 0);
            emit("TF " + document.number + " " + stem + " " + count);
        }

        private void documentFrequency(List<String> arguments) {
            String stem = termArgument(arguments.get(0));
            emit("DF " + stem + " " + documentCount(occurrencesOf(stem)));
        }

        private void variants(List<String> arguments) {
            String stem = termArgument(arguments.get(0));
            var forms = new TreeMap<String, Integer>();
            for (Occurrence occurrence : occurrencesOf(stem)) {
                forms.merge(occurrence.token().form(), 1, Integer::sum);
            }
            emit("VARIANTS " + stem + " count=" + forms.size(), forms.entrySet().stream()
                    .map(entry -> entry.getKey() + ":" + entry.getValue())
                    .toList());
        }

        private void similar(List<String> arguments) {
            Document document = documentArgument(arguments.get(0));
            int limit = numberArgument(arguments.get(1), 1, MAX_COUNT);
            Set<String> stems = stemSet(document);
            var scores = new ArrayList<Similarity>();
            for (Document other : documents.values()) {
                if (other == document) {
                    continue;
                }
                Set<String> otherStems = stemSet(other);
                var common = new HashSet<>(stems);
                common.retainAll(otherStems);
                var union = new HashSet<>(stems);
                union.addAll(otherStems);
                Fraction score = union.isEmpty()
                        ? new Fraction(0, 1)
                        : Fraction.of(common.size(), union.size());
                scores.add(new Similarity(other.number, score));
            }
            scores.sort(Comparator.comparing(Similarity::score).reversed()
                    .thenComparingInt(Similarity::document));
            emit("SIMILAR " + document.number, scores.stream()
                    .limit(limit)
                    .map(entry -> entry.document() + ":" + entry.score())
                    .toList());
        }

        private void rank(List<String> arguments) {
            int limit = numberArgument(arguments.get(0), 1, MAX_COUNT);
            var query = new HashSet<String>();
            for (String argument : arguments.subList(1, arguments.size())) {
                query.add(termArgument(argument));
            }
            var ranked = new ArrayList<Ranking>();
            for (Document document : documents.values()) {
                Map<String, Integer> counts = termFrequencies(document);
                int matched = (int) query.stream().filter(counts::containsKey).count();
                int total = query.stream().mapToInt(stem -> counts.getOrDefault(stem, 0)).sum();
                if (matched > 0) {
                    ranked.add(new Ranking(document.number, matched, total));
                }
            }
            ranked.sort(Comparator.comparingInt((Ranking entry) -> -entry.matched())
                    .thenComparingInt(entry -> -entry.total())
                    .thenComparingInt(Ranking::document));
            emit("RANK count=" + ranked.size(), ranked.stream()
                    .limit(limit)
                    .map(entry -> entry.document() + ":" + entry.matched() + ":" + entry.total())
                    .toList());
        }

        private void info(List<String> arguments) {
            Document document = documentArgument(arguments.get(0));
            Map<String, Integer> counts = termFrequencies(document);
            String top = stemCounts(counts)
                    .min(BY_COUNT)
                    .map(entry -> entry.stem() + ":" + entry.count())
                    .orElse("-");
            int indexed = counts.values().stream().mapToInt(Integer::intValue).sum();
            emit("INFO %d lines=%d tokens=%d indexed=%d stems=%d top=%s".formatted(
                    document.number, document.lines.size(), document.tokens.size(), indexed,
                    counts.size(), top));
        }

        private void showLine(List<String> arguments) {
            Document document = documentArgument(arguments.get(0));
            int lineNumber = numberArgument(arguments.get(1), 1, MAX_LINE_NUMBER);
            if (lineNumber > document.lines.size()) {
                throw new CommandError("NO LINE " + document.number + ":" + lineNumber);
            }
            List<Token> tokens = document.lineTokens(lineNumber);
            emit("LINE " + document.number + ":" + lineNumber + " tokens=" + tokens.size(),
                    tokens.stream().map(this::describeToken).toList());
        }

        private void stats(List<String> arguments) {
            Collection<Document> all = documents.values();
            emit("STATS docs=%d lines=%d tokens=%d indexed=%d stems=%d stopwords=%d".formatted(
                    all.size(),
                    all.stream().mapToInt(document -> document.lines.size()).sum(),
                    all.stream().mapToInt(document -> document.tokens.size()).sum(),
                    all.stream().mapToInt(document -> indexedTokens(document).size()).sum(),
                    totalFrequencies().size(),
                    stopwords.size()));
        }

        private void stop(List<String> arguments) {
            String word = wordArgument(arguments.get(0));
            if (isStopword(word)) {
                throw new CommandError("ALREADY STOPWORD " + word);
            }
            stopwords.add(word);
            emit("STOP " + word + " unindexed=" + formCount(word));
        }

        private void unstop(List<String> arguments) {
            String word = wordArgument(arguments.get(0));
            if (!isStopword(word)) {
                throw new CommandError("NOT STOPWORD " + word);
            }
            stopwords.remove(word);
            emit("UNSTOP " + word + " indexed=" + formCount(word));
        }

        private void append(List<String> arguments) {
            int number = numberArgument(arguments.get(0), 1, MAX_DOCUMENT_NUMBER);
            boolean created = !documents.containsKey(number);
            Document document = created ? addDocument(number) : documents.get(number);
            List<Token> tokens = document.addLine(arguments.get(1));
            long indexed = tokens.stream().filter(this::isIndexed).count();
            emit("APPEND %d line=%d tokens=%d indexed=%d new=%s".formatted(
                    number, document.lines.size(), tokens.size(), indexed, yesNo(created)));
        }

        private void delete(List<String> arguments) {
            Document document = documentArgument(arguments.get(0));
            documents.remove(document.number);
            emit("DELETE %d lines=%d tokens=%d".formatted(
                    document.number, document.lines.size(), document.tokens.size()));
        }

        void execute(String line) {
            int space = line.indexOf(' ');
            String name = space < 0 ? line : line.substring(0, space);
            try {
                Command command = handlers.get(name);
                if (command == null) {
                    throw new CommandError("UNKNOWN COMMAND " + name);
                }
                List<String> arguments =
                        space < 0 ? List.of() : splitArguments(name, line.substring(space + 1));
                if (arguments.size() < command.minimum() || arguments.size() > command.maximum()) {
                    throw new CommandError("BAD ARGUMENTS " + name);
                }
                command.handler().accept(arguments);
            } catch (CommandError error) {
                emit("ERROR " + error.getMessage());
            }
        }
    }

    public static void main(String[] args) {
        var reader = new BufferedReader(new InputStreamReader(System.in));
        List<String> lines = reader.lines().toList();
        String[] header = lines.get(0).split(" ");
        var stopwords = new HashSet<>(Arrays.asList(header).subList(1, header.length));
        var engine = new SearchEngine(stopwords);
        int index = 1;
        while (lines.get(index).startsWith("DOC ")) {
            Document document = engine.addDocument(Integer.parseInt(lines.get(index).substring(4)));
            index++;
            while (!lines.get(index).equals("ENDDOC")) {
                document.addLine(lines.get(index));
                index++;
            }
            index++;
        }
        for (String line : lines.subList(index, lines.size())) {
            if (line.equals("END")) {
                break;
            }
            engine.execute(line);
        }
        System.out.print(engine.output());
    }
}
