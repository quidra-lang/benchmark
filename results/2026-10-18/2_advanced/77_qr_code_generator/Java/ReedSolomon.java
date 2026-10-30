import java.util.*;
final class ReedSolomon {
    static final int[] EXP = new int[255], LOG = new int[256];
    static final Map<Integer, int[]> GENERATORS = new HashMap<>();
    static {
        EXP[0] = 1;
        for (int i = 1; i < 255; i++) {
            int value = 2 * EXP[i - 1];
            EXP[i] = value >= 256 ? value ^ 285 : value;
        }
        for (int i = 0; i < 255; i++)
            LOG[EXP[i]] = i;
    }
    record Correction(int[] syndromes, int[] corrected, List<Integer> positions) {}
    static int multiply(int a, int b) {
        return a == 0 || b == 0 ? 0 : EXP[(LOG[a] + LOG[b]) % 255];
    }
    static int divide(int a, int b) { return a == 0 ? 0 : EXP[(LOG[a] - LOG[b] + 255) % 255]; }
    static int[] generator(int degree) {
        if (!GENERATORS.containsKey(degree)) {
            int[] coefficients = {1};
            for (int power = 0; power < degree; power++) {
                int[] product = new int[coefficients.length + 1];
                for (int j = 0; j < coefficients.length; j++) {
                    product[j] ^= coefficients[j];
                    product[j + 1] ^= multiply(coefficients[j], EXP[power]);
                }
                coefficients = product;
            }
            GENERATORS.put(degree, coefficients);
        }
        return GENERATORS.get(degree);
    }
    static int[] parity(int[] data, int degree) {
        int[] dividend = Arrays.copyOf(data, data.length + degree), generator = generator(degree);
        for (int i = 0; i < data.length; i++) {
            int leading = dividend[i];
            if (leading != 0)
                for (int j = 0; j < generator.length; j++)
                    dividend[i + j] ^= multiply(leading, generator[j]);
        }
        return Arrays.copyOfRange(dividend, data.length, dividend.length);
    }
    static int[] syndromes(int[] words, int degree) {
        int[] values = new int[degree];
        for (int j = 0; j < degree; j++)
            for (int word : words)
                values[j] = multiply(values[j], EXP[j]) ^ word;
        return values;
    }
    static boolean allZero(int[] values) {
        for (int value : values)
            if (value != 0)
                return false;
        return true;
    }
    static int evaluate(int[] coefficients, int x) {
        int value = 0;
        for (int i = coefficients.length - 1; i >= 0; i--)
            value = multiply(value, x) ^ coefficients[i];
        return value;
    }
    static Correction correct(int[] received, int degree) {
        int[] syndromes = syndromes(received, degree);
        if (allZero(syndromes))
            return new Correction(syndromes, received.clone(), List.of());
        int[] locator = new int[degree + 1], previous = new int[degree + 1];
        locator[0] = previous[0] = 1;
        int length = 0, shift = 1, beta = 1;
        for (int q = 0; q < degree; q++) {
            int discrepancy = syndromes[q];
            for (int i = 1; i <= length; i++)
                discrepancy ^= multiply(locator[i], syndromes[q - i]);
            if (discrepancy == 0) {
                shift++;
                continue;
            }
            int[] saved = locator.clone();
            int multiplier = divide(discrepancy, beta);
            for (int i = 0; i <= degree - shift; i++)
                locator[i + shift] ^= multiply(multiplier, previous[i]);
            if (2 * length <= q) {
                length = q + 1 - length;
                previous = saved;
                beta = discrepancy;
                shift = 1;
            } else
                shift++;
        }
        if (length > degree / 2)
            return new Correction(syndromes, null, List.of());
        locator = Arrays.copyOf(locator, length + 1);
        List<Integer> roots = new ArrayList<>();
        for (int i = 0; i < received.length; i++)
            if (evaluate(locator, EXP[(255 - (received.length - 1 - i)) % 255]) == 0)
                roots.add(i);
        if (roots.size() != length)
            return new Correction(syndromes, null, List.of());
        int[] omega = new int[degree], derivative = new int[length];
        for (int i = 0; i < degree; i++)
            for (int j = 0; j < locator.length && i + j < degree; j++)
                omega[i + j] ^= multiply(syndromes[i], locator[j]);
        for (int h = 1; h <= length; h += 2)
            derivative[h - 1] = locator[h];
        int[] corrected = received.clone();
        for (int i : roots) {
            int x = EXP[(received.length - 1 - i) % 255],
                z = EXP[(255 - (received.length - 1 - i)) % 255],
                denominator = evaluate(derivative, z);
            if (denominator == 0)
                return new Correction(syndromes, null, List.of());
            corrected[i] ^= multiply(x, divide(evaluate(omega, z), denominator));
        }
        if (!allZero(syndromes(corrected, degree)))
            return new Correction(syndromes, null, List.of());
        List<Integer> positions = new ArrayList<>();
        for (int i = 0; i < received.length; i++)
            if (received[i] != corrected[i])
                positions.add(i);
        return new Correction(syndromes, corrected, positions);
    }
}
