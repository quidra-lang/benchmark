import java.util.*;

final class BitIo {
    static final class DecodeError extends RuntimeException {
        String kind;
        int position;
        DecodeError(String kind, int position) {
            this.kind = kind;
            this.position = position;
        }
    }
    static int bits(int value) {
        int count = 0;
        while (value != 0) {
            count++;
            value >>>= 1;
        }
        return count;
    }
    static final class Writer {
        List<Integer> bytes = new ArrayList<>();
        int current, used, count;
        void write(int value, int width) {
            for (int i = width - 1; i >= 0; i--) {
                current = (current << 1) | ((value >>> i) & 1);
                used++;
                count++;
                if (used == 8) {
                    bytes.add(current);
                    current = 0;
                    used = 0;
                }
            }
        }
        int[] finish() {
            List<Integer> result = new ArrayList<>(bytes);
            if (used > 0)
                result.add(current << (8 - used));
            int[] data = new int[result.size()];
            for (int i = 0; i < data.length; i++)
                data[i] = result.get(i);
            return data;
        }
    }
    static final class Reader {
        int[] data;
        int position;
        boolean zero;
        Reader(int[] data, boolean zero) {
            this.data = data;
            this.zero = zero;
        }
        int read(int width, int output) {
            if (!zero && (long)position + width > 8L * data.length)
                throw new DecodeError("end_of_data", output);
            int result = 0;
            for (int i = 0; i < width; i++) {
                int bit = position < 8L * data.length ? (data[position / 8] >>> (7 - position % 8)) & 1 : 0;
                position++;
                result = (result << 1) | bit;
            }
            return result;
        }
    }
    static int[] array(List<Integer> values) {
        int[] result = new int[values.size()];
        for (int i = 0; i < result.length; i++)
            result[i] = values.get(i);
        return result;
    }
}
