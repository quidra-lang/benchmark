import java.util.*;
final class SuffixArray {
    static final String SYMBOLS = "$#ACGT", BASES = "ACGT";
    record Built(int[] suffixes, List<Integer> classes) {}
    record Check(int ordered, int lcpSum, int maximum, int row) {}
    static int[] counting(int[] positions, int[] keys, int keyCount) {
        int[] counts = new int[keyCount];
        for (int position : positions)
            counts[keys[position]]++;
        int offset = 0;
        for (int i = 0; i < counts.length; i++) {
            int value = counts[i];
            counts[i] = offset;
            offset += value;
        }
        int[] result = new int[positions.length];
        for (int position : positions)
            result[counts[keys[position]]++] = position;
        return result;
    }
    static Built build(String text) {
        int size = text.length();
        int[] positions = new int[size], codes = new int[size], ranks = new int[size];
        for (int i = 0; i < size; i++) {
            positions[i] = i;
            codes[i] = SYMBOLS.indexOf(text.charAt(i));
        }
        int[] order = counting(positions, codes, 6);
        int count = 0, previous = -1;
        for (int position : order) {
            if (codes[position] != previous) {
                count++;
                previous = codes[position];
            }
            ranks[position] = count - 1;
        }
        List<Integer> classes = new ArrayList<>();
        classes.add(count);
        for (int width = 1; count < size; width *= 2) {
            int[] second = new int[size];
            for (int i = 0; i < size; i++)
                second[i] = i + width < size ? ranks[i + width] + 1 : 0;
            order = counting(counting(positions, second, count + 1), ranks, count);
            int[] updated = new int[size];
            count = 0;
            int firstKey = -1, secondKey = -1;
            for (int position : order) {
                if (ranks[position] != firstKey || second[position] != secondKey) {
                    count++;
                    firstKey = ranks[position];
                    secondKey = second[position];
                }
                updated[position] = count - 1;
            }
            ranks = updated;
            classes.add(count);
        }
        return new Built(order, classes);
    }
    static int[] direct(String text) {
        Integer[] positions = new Integer[text.length()];
        for (int i = 0; i < positions.length; i++)
            positions[i] = i;
        Arrays.sort(positions, (a, b) -> {
            int i = a, j = b;
            while (i < text.length() && j < text.length()) {
                int order = Character.compare(text.charAt(i++), text.charAt(j++));
                if (order != 0)
                    return order;
            }
            return Integer.compare(text.length() - a, text.length() - b);
        });
        return Arrays.stream(positions).mapToInt(Integer::intValue).toArray();
    }
    static Check check(String text, int[] suffixes) {
        int ordered = 0, sum = 0, maximum = -1, longest = 1;
        for (int row = 1; row < suffixes.length; row++) {
            int left = suffixes[row - 1], right = suffixes[row], common = 0;
            while (text.charAt(left + common) == text.charAt(right + common))
                common++;
            if (SYMBOLS.indexOf(text.charAt(left + common)) <
                SYMBOLS.indexOf(text.charAt(right + common)))
                ordered++;
            sum += common;
            if (common > maximum) {
                maximum = common;
                longest = row;
            }
        }
        return new Check(ordered, sum, maximum, longest);
    }
}
