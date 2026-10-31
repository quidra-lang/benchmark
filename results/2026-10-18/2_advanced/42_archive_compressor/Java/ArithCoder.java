import java.util.*;

final class ArithCoder {
    static final class Table {
        int[] frequencies = new int[257];
        int total = 257, rescales;
        Table() {
            Arrays.fill(frequencies, 1);
        }
        int cumulative(int symbol) {
            int sum = 0;
            for (int i = 0; i < symbol; i++)
                sum += frequencies[i];
            return sum;
        }
        int[] locate(int value) {
            int cumulative = 0;
            for (int symbol = 0; symbol < 257; symbol++) {
                if (value < cumulative + frequencies[symbol])
                    return new int[] {symbol, cumulative, frequencies[symbol]};
                cumulative += frequencies[symbol];
            }
            throw new IllegalStateException();
        }
        void update(int symbol) {
            frequencies[symbol] += 32;
            total += 32;
            if (total >= 8192) {
                total = 0;
                for (int i = 0; i < 257; i++) {
                    frequencies[i] = (frequencies[i] + 1) / 2;
                    total += frequencies[i];
                }
                rescales++;
            }
        }
    }
    record Encoded(int[] payload, int bits, int contexts, int rescales) {}
    static final class Encoder {
        BitIo.Writer writer = new BitIo.Writer();
        int follow;
        void emit(int bit) {
            writer.write(bit, 1);
            for (int i = 0; i < follow; i++)
                writer.write(1 - bit, 1);
            follow = 0;
        }
    }
    static Encoded encode(int[] data) {
        Encoder e = new Encoder();
        Map<Integer, Table> tables = new HashMap<>();
        int low = 0, high = 65535, context = 10;
        for (int index = 0; index <= data.length; index++) {
            int symbol = index == data.length ? 256 : data[index];
            Table table = tables.computeIfAbsent(context, key -> new Table());
            int cumulative = table.cumulative(symbol), span = high - low + 1;
            high = low + span * (cumulative + table.frequencies[symbol]) / table.total - 1;
            low += span * cumulative / table.total;
            while (true) {
                if (high < 32768)
                    e.emit(0);
                else if (low >= 32768) {
                    e.emit(1);
                    low -= 32768;
                    high -= 32768;
                } else if (low >= 16384 && high < 49152) {
                    e.follow++;
                    low -= 16384;
                    high -= 16384;
                } else
                    break;
                low *= 2;
                high = 2 * high + 1;
            }
            if (symbol != 256) {
                table.update(symbol);
                context = symbol;
            }
        }
        e.follow++;
        e.emit(low < 16384 ? 0 : 1);
        int rescales = 0;
        for (Table t : tables.values())
            rescales += t.rescales;
        return new Encoded(e.writer.finish(), e.writer.count, tables.size(), rescales);
    }
    static int[] decode(int[] payload, long size) {
        BitIo.Reader reader = new BitIo.Reader(payload, true);
        Map<Integer, Table> tables = new HashMap<>();
        List<Integer> output = new ArrayList<>();
        int low = 0, high = 65535, value = reader.read(16, 0), context = 10;
        while (true) {
            Table table = tables.computeIfAbsent(context, key -> new Table());
            int span = high - low + 1, quantile = ((value - low + 1) * table.total - 1) / span;
            int[] found = table.locate(quantile);
            int symbol = found[0], cumulative = found[1], frequency = found[2];
            high = low + span * (cumulative + frequency) / table.total - 1;
            low += span * cumulative / table.total;
            while (true) {
                if (high < 32768) {
                } else if (low >= 32768) {
                    low -= 32768;
                    high -= 32768;
                    value -= 32768;
                } else if (low >= 16384 && high < 49152) {
                    low -= 16384;
                    high -= 16384;
                    value -= 16384;
                } else
                    break;
                low *= 2;
                high = 2 * high + 1;
                value = 2 * value + reader.read(1, output.size());
            }
            if (symbol == 256) {
                if (output.size() < size)
                    throw new BitIo.DecodeError("early_end", output.size());
                return BitIo.array(output);
            }
            if (output.size() == size)
                throw new BitIo.DecodeError("overrun", output.size());
            output.add(symbol);
            table.update(symbol);
            context = symbol;
        }
    }
}
