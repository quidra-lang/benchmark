import java.util.*;

final class Lz77 {
    record Token(int literal, int distance, int length) {}
    static List<Token> split(int[] data, int b, int k) {
        List<Token> result = new ArrayList<>();
        int i = 0, window = 1 << b, limit = (1 << k) + 2;
        while (i < data.length) {
            int distance = 0, length = 0;
            for (int d = 1; d <= Math.min(window, i); d++) {
                int match = 0;
                while (match < Math.min(limit, data.length - i) && data[i + match] == data[i + match - d])
                    match++;
                if (match > length) {
                    length = match;
                    distance = d;
                }
            }
            if (length >= 3) {
                result.add(new Token(-1, distance, length));
                i += length;
            } else {
                result.add(new Token(data[i], 0, 0));
                i++;
            }
        }
        return result;
    }
    static void copy(List<Integer> output, int distance, int length, long size) {
        if (distance > output.size())
            throw new BitIo.DecodeError("bad_offset", output.size());
        if ((long)output.size() + length > size)
            throw new BitIo.DecodeError("overrun", output.size());
        for (int i = 0; i < length; i++)
            output.add(output.get(output.size() - distance));
    }
}
