import java.nio.charset.StandardCharsets;
import java.util.*;
final class Encoding {
    static final List<String> METHODS =
        List.of("PLAIN", "DICTIONARY", "RLE", "DELTA_BINARY_PACKED", "DELTA_LENGTH_BYTE_ARRAY");
    record Bounds(SchemaIo.Value low, SchemaIo.Value high) {}
    static List<Integer> candidates(String kind) {
        return kind.equals("BOOL") ? List.of(0, 2)
        : kind.equals("STRING")    ? List.of(0, 1, 4)
                                   : List.of(0, 1, 3);
    }
    static byte[] deltaEncode(List<Long> values) {
        Bitstream.Writer writer = new Bitstream.Writer();
        writer.uleb(128);
        writer.uleb(4);
        writer.uleb(values.size());
        writer.zigzag(values.isEmpty() ? 0 : values.getFirst());
        List<Long> deltas = new ArrayList<>();
        for (int i = 1; i < values.size(); i++)
            deltas.add(values.get(i) - values.get(i - 1));
        for (int start = 0; start < deltas.size(); start += 128) {
            List<Long> block = deltas.subList(start, Math.min(start + 128, deltas.size()));
            long minimum = Collections.min(block);
            writer.zigzag(minimum);
            List<List<Long>> miniblocks = new ArrayList<>();
            int[] widths = new int[4];
            for (int t = 0; t < 4; t++) {
                List<Long> mini = new ArrayList<>();
                long maximum = 0;
                for (int j = 32 * t; j < Math.min(32 * (t + 1), block.size()); j++) {
                    long value = block.get(j) - minimum;
                    mini.add(value);
                    maximum = Math.max(maximum, value);
                }
                widths[t] = Bitstream.bits(maximum);
                writer.byteValue(widths[t]);
                miniblocks.add(mini);
            }
            for (int t = 0; t < 4; t++)
                if (!miniblocks.get(t).isEmpty()) {
                    List<Long> mini = miniblocks.get(t);
                    while (mini.size() < 32)
                        mini.add(0L);
                    writer.bytes(Bitstream.pack(mini, widths[t]));
                }
        }
        return writer.value();
    }
    static List<Long> deltaDecode(Bitstream.Reader reader) {
        int blockSize = (int)reader.uleb(), miniblockCount = (int)reader.uleb(),
            count = (int)reader.uleb();
        long first = reader.zigzag();
        List<Long> values = new ArrayList<>();
        if (count > 0)
            values.add(first);
        int miniblockSize = blockSize / miniblockCount;
        while (values.size() < count) {
            long minimum = reader.zigzag();
            int[] widths = new int[miniblockCount];
            for (int i = 0; i < widths.length; i++)
                widths[i] = reader.byteValue();
            for (int width : widths) {
                if (values.size() == count)
                    break;
                List<Long> differences = Bitstream.unpack(reader, width, miniblockSize);
                int remaining = Math.min(miniblockSize, count - values.size());
                for (int i = 0; i < remaining; i++)
                    values.add(values.getLast() + minimum + differences.get(i));
            }
        }
        return values;
    }
    static byte[] encodeValues(String kind, int method, List<SchemaIo.Value> values,
                               List<SchemaIo.Value> dictionary) {
        Bitstream.Writer writer = new Bitstream.Writer();
        if (method == 0) {
            if (kind.equals("INT") || kind.equals("DATE"))
                for (SchemaIo.Value value : values)
                    writer.integer(((SchemaIo.NumberValue)value).value());
            else if (kind.equals("STRING"))
                for (SchemaIo.Value value : values) {
                    String text = ((SchemaIo.TextValue)value).value();
                    writer.integer(text.length());
                    writer.bytes(text.getBytes(StandardCharsets.US_ASCII));
                }
            else {
                List<Long> bits = new ArrayList<>();
                for (SchemaIo.Value value : values)
                    bits.add(((SchemaIo.BoolValue)value).value() ? 1L : 0L);
                while (bits.size() % 8 != 0)
                    bits.add(0L);
                writer.bytes(Bitstream.pack(bits, 1));
            }
        } else if (method == 1) {
            Map<SchemaIo.Value, Integer> ranks = new HashMap<>();
            for (int i = 0; i < dictionary.size(); i++)
                ranks.put(dictionary.get(i), i);
            int width = Bitstream.bits(dictionary.size() - 1);
            writer.byteValue(width);
            List<Long> indices = new ArrayList<>();
            for (SchemaIo.Value value : values)
                indices.add(ranks.get(value).longValue());
            writer.bytes(Bitstream.hybridEncode(indices, width));
        } else if (method == 2) {
            List<Long> bits = new ArrayList<>();
            for (SchemaIo.Value value : values)
                bits.add(((SchemaIo.BoolValue)value).value() ? 1L : 0L);
            byte[] encoded = Bitstream.hybridEncode(bits, 1);
            writer.integer(encoded.length);
            writer.bytes(encoded);
        } else if (method == 3) {
            List<Long> numbers = new ArrayList<>();
            for (SchemaIo.Value value : values)
                numbers.add(((SchemaIo.NumberValue)value).value());
            writer.bytes(deltaEncode(numbers));
        } else {
            List<Long> lengths = new ArrayList<>();
            for (SchemaIo.Value value : values)
                lengths.add((long)((SchemaIo.TextValue)value).value().length());
            writer.bytes(deltaEncode(lengths));
            for (SchemaIo.Value value : values)
                writer.bytes(
                    ((SchemaIo.TextValue)value).value().getBytes(StandardCharsets.US_ASCII));
        }
        return writer.value();
    }
    static List<SchemaIo.Value> decodeValues(Bitstream.Reader reader, String kind, int method,
                                             int count, List<SchemaIo.Value> dictionary) {
        List<SchemaIo.Value> values = new ArrayList<>();
        if (method == 0) {
            if (kind.equals("INT") || kind.equals("DATE"))
                for (int i = 0; i < count; i++)
                    values.add(new SchemaIo.NumberValue(reader.integer(true)));
            else if (kind.equals("STRING"))
                for (int i = 0; i < count; i++)
                    values.add(new SchemaIo.TextValue(
                        new String(reader.read((int)reader.integer()), StandardCharsets.US_ASCII)));
            else {
                List<Long> bits = Bitstream.unpack(reader, 1, (count + 7) / 8 * 8);
                for (int i = 0; i < count; i++)
                    values.add(new SchemaIo.BoolValue(bits.get(i) != 0));
            }
        } else if (method == 1) {
            int width = reader.byteValue();
            for (long index : Bitstream.hybridDecode(reader, width, count))
                values.add(dictionary.get((int)index));
        } else if (method == 2) {
            Bitstream.Reader encoded = new Bitstream.Reader(reader.read((int)reader.integer()));
            for (long value : Bitstream.hybridDecode(encoded, 1, count))
                values.add(new SchemaIo.BoolValue(value != 0));
        } else if (method == 3)
            for (long value : deltaDecode(reader))
                values.add(new SchemaIo.NumberValue(value));
        else
            for (long length : deltaDecode(reader))
                values.add(new SchemaIo.TextValue(
                    new String(reader.read((int)length), StandardCharsets.US_ASCII)));
        return values;
    }
    static byte[] encodeStatistics(String kind, Bounds bounds) {
        Bitstream.Writer writer = new Bitstream.Writer();
        writer.byteValue(bounds == null ? 0 : 1);
        if (bounds != null)
            for (SchemaIo.Value value : List.of(bounds.low(), bounds.high()))
                if (kind.equals("INT") || kind.equals("DATE"))
                    writer.zigzag(((SchemaIo.NumberValue)value).value());
                else if (kind.equals("STRING")) {
                    String text = ((SchemaIo.TextValue)value).value();
                    writer.uleb(text.length());
                    writer.bytes(text.getBytes(StandardCharsets.US_ASCII));
                } else
                    writer.byteValue(((SchemaIo.BoolValue)value).value() ? 1 : 0);
        return writer.value();
    }
    static Bounds decodeStatistics(Bitstream.Reader reader, String kind) {
        if (reader.byteValue() == 0)
            return null;
        List<SchemaIo.Value> values = new ArrayList<>();
        for (int i = 0; i < 2; i++)
            if (kind.equals("INT") || kind.equals("DATE"))
                values.add(new SchemaIo.NumberValue(reader.zigzag()));
            else if (kind.equals("STRING"))
                values.add(new SchemaIo.TextValue(
                    new String(reader.read((int)reader.uleb()), StandardCharsets.US_ASCII)));
            else
                values.add(new SchemaIo.BoolValue(reader.byteValue() != 0));
        return new Bounds(values.get(0), values.get(1));
    }
}
