import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

final class Transposition {
    private Transposition() {}

    static int rail(int position, int rails) {
        int cycle = 2 * rails - 2;
        int offset = position % cycle;
        return Math.min(offset, cycle - offset);
    }

    static String railFence(String text, int rails, boolean encrypt) {
        Integer[] order = new Integer[text.length()];
        for (int i = 0; i < order.length; i++) order[i] = i;
        Arrays.sort(order, Comparator.<Integer>comparingInt(i -> rail(i, rails)).thenComparingInt(i -> i));
        char[] output = new char[text.length()];
        for (int i = 0; i < order.length; i++) {
            if (encrypt) output[i] = text.charAt(order[i]);
            else output[order[i]] = text.charAt(i);
        }
        return new String(output);
    }

    static List<Integer> columnOrder(String key) {
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < key.length(); i++) order.add(i);
        order.sort(Comparator.<Integer>comparingInt(key::charAt).thenComparingInt(i -> i));
        return order;
    }

    static String rankString(String key) {
        char[] result = new char[key.length()];
        List<Integer> order = columnOrder(key);
        for (int i = 0; i < order.size(); i++) result[order.get(i)] = (char)('1' + i);
        return new String(result);
    }

    static String columnar(String text, String key, boolean encrypt) {
        char[] output = new char[text.length()];
        int pointer = 0;
        for (int column : columnOrder(key)) {
            for (int i = column; i < text.length(); i += key.length()) {
                if (encrypt) output[pointer++] = text.charAt(i);
                else output[i] = text.charAt(pointer++);
            }
        }
        return new String(output);
    }
}
