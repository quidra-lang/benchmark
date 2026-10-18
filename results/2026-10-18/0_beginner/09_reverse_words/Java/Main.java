public class Main {
    public static void main(String[] args) {
        String sentence = "every program starts with a single line";
        System.out.println(new StringBuilder(sentence).reverse());
        String[] words = sentence.split(" ");
        StringBuilder reversedWords = new StringBuilder();
        for (int i = words.length - 1; i >= 0; i--) {
            if (i < words.length - 1) reversedWords.append(' ');
            reversedWords.append(words[i]);
        }
        System.out.println(reversedWords);
    }
}
