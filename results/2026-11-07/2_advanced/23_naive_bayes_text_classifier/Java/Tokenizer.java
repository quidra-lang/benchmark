import java.util.*;
import java.util.regex.*;

final class Tokenizer {
    private static final Pattern WORD = Pattern.compile("[A-Za-z0-9]+");
    final List<String> words = new ArrayList<>();
    final List<String> bigrams = new ArrayList<>();
    final List<String> bigramTerms;
    int rawCount;
    int stopwordCount;
    int shortCount;

    Tokenizer(String text, Set<String> stopwords) {
        Matcher matcher = WORD.matcher(text);
        while (matcher.find()) {
            String word = matcher.group().toLowerCase(Locale.ROOT);
            rawCount++;
            if (stopwords.contains(word)) stopwordCount++;
            else if (word.length() == 1) shortCount++;
            else words.add(word);
        }
        for (int i = 1; i < words.size(); i++) bigrams.add(words.get(i - 1) + "_" + words.get(i));
        bigramTerms = new ArrayList<>(words);
        bigramTerms.addAll(bigrams);
    }

    List<String> terms(boolean useBigrams) {
        return useBigrams ? bigramTerms : words;
    }
}
