import java.io.ByteArrayOutputStream;
import java.util.*;
final class Bitstream {
    static final class Writer {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        void byteValue(int value) { output.write(value); }
        void bytes(byte[] values) { output.writeBytes(values); }
        void uleb(long value) {
            while (value >= 128) {
                byteValue((int)(value % 128) + 128);
                value /= 128;
            }
            byteValue((int)value);
        }
        void zigzag(long value) { uleb(value >= 0 ? 2 * value : -2 * value - 1); }
        void integer(long value) {
            for (int i = 0; i < 4; i++)
                byteValue((int)(value >>> (8 * i)) & 255);
        }
        int size() { return output.size(); }
        byte[] value() { return output.toByteArray(); }
    }
    static final class Reader {
        byte[] data;
        int position;
        Reader(byte[] data) { this(data, 0); }
        Reader(byte[] data, int position) {
            this.data = data;
            this.position = position;
        }
        byte[] read(int count) {
            byte[] value = Arrays.copyOfRange(data, position, position + count);
            position += count;
            return value;
        }
        int byteValue() { return data[position++] & 255; }
        long uleb() {
            long value = 0;
            int shift = 0;
            while (true) {
                int b = byteValue();
                value |= (long)(b & 127) << shift;
                if (b < 128)
                    return value;
                shift += 7;
            }
        }
        long zigzag() {
            long value = uleb();
            return value % 2 == 0 ? value / 2 : -(value + 1) / 2;
        }
        long integer(boolean signed) {
            long value = 0;
            for (int i = 0; i < 4; i++)
                value |= (long)byteValue() << (8 * i);
            return signed &&value >= 0x80000000L ? value - 0x100000000L : value;
        }
        long integer() { return integer(false); }
    }
    static int bits(long value) { return value == 0 ? 0 : 64 - Long.numberOfLeadingZeros(value); }
    static byte[] pack(List<Long> values, int width) {
        Writer writer = new Writer();
        long buffer = 0;
        int occupied = 0;
        for (long value : values) {
            buffer |= value << occupied;
            occupied += width;
            while (occupied >= 8) {
                writer.byteValue((int)buffer & 255);
                buffer >>>= 8;
                occupied -= 8;
            }
        }
        return writer.value();
    }
    static List<Long> unpack(Reader reader, int width, int count) {
        List<Long> values = new ArrayList<>();
        long buffer = 0, mask = (1L << width) - 1;
        int occupied = 0;
        for (int i = 0; i < count; i++) {
            while (occupied < width) {
                buffer |= (long)reader.byteValue() << occupied;
                occupied += 8;
            }
            values.add(buffer & mask);
            buffer >>>= width;
            occupied -= width;
        }
        return values;
    }
    static long adler32(byte[] data) {
        long first = 1, second = 0;
        for (byte value : data) {
            first = (first + (value & 255)) % 65521;
            second = (second + first) % 65521;
        }
        return second * 65536 + first;
    }
    static byte[] hybridEncode(List<Long> values, int width) {
        int count = values.size();
        int[] runs = new int[count];
        for (int i = count - 1; i >= 0; i--) {
            runs[i] = 1;
            if (i + 1 < count && values.get(i).equals(values.get(i + 1)))
                runs[i] += runs[i + 1];
        }
        Writer writer = new Writer();
        int i = 0;
        while (i < count) {
            if (runs[i] >= 8) {
                writer.uleb(2L * runs[i]);
                for (int j = 0; j < (width + 7) / 8; j++)
                    writer.byteValue((int)(values.get(i) >>> (8 * j)) & 255);
                i += runs[i];
            } else {
                int end = i, groups = 0;
                do {
                    end += 8;
                    groups++;
                } while (end < count && groups < 63 && runs[end] < 8);
                writer.uleb(2L * groups + 1);
                List<Long> block = new ArrayList<>(values.subList(i, Math.min(end, count)));
                while (block.size() < end - i)
                    block.add(0L);
                writer.bytes(pack(block, width));
                i = end;
            }
        }
        return writer.value();
    }
    static List<Long> hybridDecode(Reader reader, int width, int count) {
        List<Long> values = new ArrayList<>();
        while (values.size() < count) {
            long header = reader.uleb();
            if (header % 2 == 0) {
                long value = 0;
                for (int i = 0; i < (width + 7) / 8; i++)
                    value |= (long)reader.byteValue() << (8 * i);
                for (long i = 0; i < header / 2; i++)
                    values.add(value);
            } else
                values.addAll(unpack(reader, width, (int)((header - 1) / 2) * 8));
        }
        return new ArrayList<>(values.subList(0, count));
    }
}
