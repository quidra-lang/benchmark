import java.util.ArrayList;
import java.util.List;

final class Substitution {
    private Substitution() {}

    static int mod(int value) {
        return (value % 26 + 26) % 26;
    }

    static int inverse(int value) {
        for (int i = 1; i < 26; i++) if ((i * value) % 26 == 1) return i;
        throw new IllegalArgumentException("Noninvertible key");
    }

    static String apply(String text, String cipher, String key, boolean encrypt) {
        int a = 1;
        int b = 0;
        if (cipher.equals("caesar")) b = Integer.parseInt(key);
        if (cipher.equals("affine")) {
            String[] pieces = key.split(",");
            a = Integer.parseInt(pieces[0]);
            b = Integer.parseInt(pieces[1]);
        }
        int inverse = cipher.equals("affine") ? inverse(a) : 1;
        List<Integer> plaintext = new ArrayList<>();
        StringBuilder result = new StringBuilder();
        int letterIndex = 0;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (!Scoring.letter(c)) {
                result.append(c);
                continue;
            }
            int x = Scoring.value(c);
            int shift = 0;
            if (cipher.equals("vigenere"))
                shift = Scoring.value(key.charAt(letterIndex % key.length()));
            else if (cipher.equals("autokey"))
                shift = letterIndex < key.length() ? Scoring.value(key.charAt(letterIndex))
                    : plaintext.get(letterIndex - key.length());
            int y = switch (cipher) {
                case "caesar" -> mod(x + (encrypt ? b : -b));
                case "affine" -> encrypt ? mod(a * x + b) : mod(inverse * (x - b));
                case "vigenere", "autokey" -> mod(x + (encrypt ? shift : -shift));
                default -> throw new IllegalArgumentException("Unknown cipher");
            };
            plaintext.add(encrypt ? x : y);
            result.append((char)((c >= 'a' ? 'a' : 'A') + y));
            letterIndex++;
        }
        return result.toString();
    }
}
