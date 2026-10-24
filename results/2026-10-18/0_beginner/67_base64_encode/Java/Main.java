public class Main {
    public static void main(String[] args) {
        String alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        for (String text : new String[]{"Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?"}) {
            StringBuilder encoded = new StringBuilder();
            for (int i = 0; i < text.length(); i += 3) {
                int remaining = text.length() - i;
                int bits = text.charAt(i) << 16;
                if (remaining > 1) bits |= text.charAt(i + 1) << 8;
                if (remaining > 2) bits |= text.charAt(i + 2);
                encoded.append(alphabet.charAt((bits >> 18) & 63));
                encoded.append(alphabet.charAt((bits >> 12) & 63));
                encoded.append(remaining > 1 ? alphabet.charAt((bits >> 6) & 63) : '=');
                encoded.append(remaining > 2 ? alphabet.charAt(bits & 63) : '=');
            }
            System.out.println("\"" + text + "\" -> \"" + encoded + "\"");
        }
    }
}
