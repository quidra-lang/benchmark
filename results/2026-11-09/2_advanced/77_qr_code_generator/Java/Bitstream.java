import java.util.*;
final class Bitstream {
    static final String ALPHANUMERIC = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
    static String binary(int value, int width) {
        StringBuilder result = new StringBuilder();
        for (int bit = width - 1; bit >= 0; bit--)
            result.append((value >>> bit) & 1);
        return result.toString();
    }
    static final class Writer {
        StringBuilder bits = new StringBuilder();
        void write(int value, int width) { bits.append(binary(value, width)); }
        String value() { return bits.toString(); }
    }
    static final class Reader {
        String bits;
        int position;
        Reader(String bits) { this.bits = bits; }
        int remaining() { return bits.length() - position; }
        int read(int width) {
            int value = 0;
            for (int i = 0; i < width; i++)
                value = (value << 1) | (bits.charAt(position++) - '0');
            return value;
        }
    }
    static int[] toCodewords(String bits) {
        int[] words = new int[bits.length() / 8];
        Reader reader = new Reader(bits);
        for (int i = 0; i < words.length; i++)
            words[i] = reader.read(8);
        return words;
    }
    static String fromCodewords(int[] words) {
        Writer writer = new Writer();
        for (int word : words)
            writer.write(word, 8);
        return writer.value();
    }
    static String hexadecimal(int[] words) {
        StringBuilder result = new StringBuilder();
        for (int word : words) {
            result.append("0123456789abcdef".charAt(word >>> 4));
            result.append("0123456789abcdef".charAt(word & 15));
        }
        return result.toString();
    }
}
