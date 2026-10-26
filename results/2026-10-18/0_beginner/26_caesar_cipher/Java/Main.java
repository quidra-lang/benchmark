public class Main {
    static String cipher(String text, int shift) {
        StringBuilder result = new StringBuilder();
        for (char ch : text.toCharArray()) {
            int base = ch >= 'A' && ch <= 'Z' ? 'A' : ch >= 'a' && ch <= 'z' ? 'a' : -1;
            result.append(base < 0 ? ch : (char)(base + (ch - base + shift + 26) % 26));
        }
        return result.toString();
    }

    public static void main(String[] args) {
        String encrypted = cipher("Zoe, meet Max by the Old Bridge at six!", 3);
        System.out.println(encrypted);
        System.out.println(cipher(encrypted, -3));
    }
}
