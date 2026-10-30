import java.util.*;
final class Bitstream {
    static final class DecodeError extends RuntimeException {
        final String kind;
        DecodeError(String kind) {
            super(kind);
            this.kind = kind;
        }
    }
    static final class Writer {
        final List<Integer> data = new ArrayList<>();
        int buffer, pending, paddingBits, stuffedBytes;
        void write(int value, int width) {
            for (int shift = width - 1; shift >= 0; shift--) {
                buffer = 2 * buffer + ((value >> shift) & 1);
                pending++;
                if (pending == 8) {
                    data.add(buffer);
                    if (buffer == 255) {
                        data.add(0);
                        stuffedBytes++;
                    }
                    buffer = pending = 0;
                }
            }
        }
        void pad() {
            if (pending != 0) {
                int width = 8 - pending;
                paddingBits += width;
                write((1 << width) - 1, width);
            }
        }
        void restart(int number) {
            pad();
            data.add(255);
            data.add(208 + number % 8);
        }
    }
    static final class Reader {
        final int[] data;
        int position, buffer, remaining;
        Reader(int[] data, int position) {
            this.data = data;
            this.position = position;
        }
        int bit() {
            if (remaining == 0) {
                int value = data[position];
                if (value == 255) {
                    if (data[position + 1] != 0)
                        throw new DecodeError("marker");
                    position += 2;
                } else
                    position++;
                buffer = value;
                remaining = 8;
            }
            remaining--;
            return (buffer >> remaining) & 1;
        }
        int read(int width) {
            int value = 0;
            for (int i = 0; i < width; i++)
                value = 2 * value + bit();
            return value;
        }
        void discard() { buffer = remaining = 0; }
    }
    static int resync(int[] data, int position) {
        for (int q = position; q < data.length - 1; q++)
            if (data[q] == 255 && (data[q + 1] >= 208 && data[q + 1] <= 215 || data[q + 1] == 217))
                return q;
        throw new IllegalStateException();
    }
}
