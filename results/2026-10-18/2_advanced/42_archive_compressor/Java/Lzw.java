import java.util.*;

final class Lzw {
    static final class Statistics {
        int codes, clears, longest;
        int[] widths = new int[4];
    }
    record Encoded(int[] payload, Statistics stats) {}
    static Map<String, Integer> dictionary() {
        Map<String, Integer> result = new HashMap<>();
        for (int i = 0; i < 256; i++)
            result.put(Character.toString((char)i), i);
        return result;
    }
    static final class Encoder {
        BitIo.Writer writer = new BitIo.Writer();
        Statistics stats = new Statistics();
        int since;
        void emit(int code, int length) {
            int width = Math.min(12, BitIo.bits(258 + since));
            writer.write(code, width);
            stats.codes++;
            stats.widths[width - 9]++;
            stats.longest = Math.max(stats.longest, length);
            if (code == 256) {
                stats.clears++;
                since = 0;
            } else
                since++;
        }
    }
    static Encoded encode(int[] data) {
        Encoder e = new Encoder();
        Map<String, Integer> dictionary = dictionary();
        int next = 258;
        e.emit(256, 0);
        String sequence = "";
        for (int value : data) {
            String character = Character.toString((char)value), extended = sequence + character;
            if (dictionary.containsKey(extended)) {
                sequence = extended;
                continue;
            }
            e.emit(dictionary.get(sequence), sequence.length());
            dictionary.put(extended, next++);
            if (next == 4096) {
                e.emit(256, 0);
                dictionary = dictionary();
                next = 258;
            }
            sequence = character;
        }
        if (!sequence.isEmpty())
            e.emit(dictionary.get(sequence), sequence.length());
        e.emit(257, 0);
        return new Encoded(e.writer.finish(), e.stats);
    }
    static List<String> decodedDictionary() {
        List<String> result = new ArrayList<>();
        for (int i = 0; i < 256; i++)
            result.add(Character.toString((char)i));
        result.add(null);
        result.add(null);
        return result;
    }
    static int[] decode(int[] payload, long size) {
        BitIo.Reader reader = new BitIo.Reader(payload, false);
        List<String> dictionary = decodedDictionary();
        List<Integer> output = new ArrayList<>();
        int previous = -1, since = 0;
        while (true) {
            int count = since, code = reader.read(Math.min(12, BitIo.bits(258 + count)), output.size());
            if (code == 256) {
                dictionary = decodedDictionary();
                previous = -1;
                since = 0;
                continue;
            }
            since++;
            if (code == 257) {
                if (output.size() < size)
                    throw new BitIo.DecodeError("early_end", output.size());
                return BitIo.array(output);
            }
            if (count == 3838)
                throw new BitIo.DecodeError("bad_code", output.size());
            String sequence;
            if (previous == -1) {
                if (code >= 256)
                    throw new BitIo.DecodeError("bad_code", output.size());
                sequence = dictionary.get(code);
            } else if (code < dictionary.size())
                sequence = dictionary.get(code);
            else if (code == dictionary.size())
                sequence = dictionary.get(previous) + dictionary.get(previous).charAt(0);
            else
                throw new BitIo.DecodeError("bad_code", output.size());
            if ((long)output.size() + sequence.length() > size)
                throw new BitIo.DecodeError("overrun", output.size());
            for (int i = 0; i < sequence.length(); i++)
                output.add((int)sequence.charAt(i));
            if (previous != -1)
                dictionary.add(dictionary.get(previous) + sequence.charAt(0));
            previous = code;
        }
    }
}
