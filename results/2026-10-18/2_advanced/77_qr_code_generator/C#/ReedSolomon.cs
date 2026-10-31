using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
public static class ReedSolomon {
    public static readonly int[] EXP = new int[255], LOG = new int[256];
    public static readonly Dictionary<int, int[]> GENERATORS = new();
    static ReedSolomon() {
        EXP[0] = 1;
        for (int i = 1; i < 255; i++) {
            int value = 2 * EXP[i - 1];
            EXP[i] = value >= 256 ? value ^ 285 : value;
        }
        for (int i = 0; i < 255; i++)
            LOG[EXP[i]] = i;
    }
    public record Correction(int[] syndromes, int[] corrected, List<int> positions) {}
    public static int Multiply(int a, int b) {
        return a == 0 || b == 0 ? 0 : EXP[(LOG[a] + LOG[b]) % 255];
    }
    public static int Divide(int a, int b) {
        return a == 0 ? 0 : EXP[(LOG[a] - LOG[b] + 255) % 255];
    }
    public static int[] Generator(int degree) {
        if (!GENERATORS.ContainsKey(degree)) {
            int[] coefficients = { 1 };
            for (int power = 0; power < degree; power++) {
                int[] product = new int[coefficients.Length + 1];
                for (int j = 0; j < coefficients.Length; j++) {
                    product[j] ^= coefficients[j];
                    product[j + 1] ^= Multiply(coefficients[j], EXP[power]);
                }
                coefficients = product;
            }
            GENERATORS[degree] = coefficients;
        }
        return GENERATORS[degree];
    }
    public static int[] Parity(int[] data, int degree) {
        int[] dividend = data.Concat(new int[degree]).ToArray(), generator = Generator(degree);
        for (int i = 0; i < data.Length; i++) {
            int leading = dividend[i];
            if (leading != 0)
                for (int j = 0; j < generator.Length; j++)
                    dividend[i + j] ^= Multiply(leading, generator[j]);
        }
        return dividend[(data.Length)..(dividend.Length)];
    }
    public static int[] Syndromes(int[] words, int degree) {
        int[] values = new int[degree];
        for (int j = 0; j < degree; j++)
            foreach (int word in words)
                values[j] = Multiply(values[j], EXP[j]) ^ word;
        return values;
    }
    public static bool AllZero(int[] values) {
        foreach (int value in values)
            if (value != 0)
                return false;
        return true;
    }
    public static int Evaluate(int[] coefficients, int x) {
        int value = 0;
        for (int i = coefficients.Length - 1; i >= 0; i--)
            value = Multiply(value, x) ^ coefficients[i];
        return value;
    }
    public static Correction Correct(int[] received, int degree) {
        int[] syndromes = Syndromes(received, degree);
        if (AllZero(syndromes))
            return new Correction(syndromes, received.ToArray(), new());
        int[] locator = new int[degree + 1], previous = new int[degree + 1];
        locator[0] = previous[0] = 1;
        int length = 0, shift = 1, beta = 1;
        for (int q = 0; q < degree; q++) {
            int discrepancy = syndromes[q];
            for (int i = 1; i <= length; i++)
                discrepancy ^= Multiply(locator[i], syndromes[q - i]);
            if (discrepancy == 0) {
                shift++;
                continue;
            }
            int[] saved = locator.ToArray();
            int multiplier = Divide(discrepancy, beta);
            for (int i = 0; i <= degree - shift; i++)
                locator[i + shift] ^= Multiply(multiplier, previous[i]);
            if (2 * length <= q) {
                length = q + 1 - length;
                previous = saved;
                beta = discrepancy;
                shift = 1;
            } else
                shift++;
        }
        if (length > degree / 2)
            return new Correction(syndromes, null, new());
        locator = locator.Take(length + 1).ToArray();
        List<int> roots = new();
        for (int i = 0; i < received.Length; i++)
            if (Evaluate(locator, EXP[(255 - (received.Length - 1 - i)) % 255]) == 0)
                roots.Add(i);
        if (roots.Count != length)
            return new Correction(syndromes, null, new());
        int[] omega = new int[degree], derivative = new int[length];
        for (int i = 0; i < degree; i++)
            for (int j = 0; j < locator.Length && i + j < degree; j++)
                omega[i + j] ^= Multiply(syndromes[i], locator[j]);
        for (int h = 1; h <= length; h += 2)
            derivative[h - 1] = locator[h];
        int[] corrected = received.ToArray();
        foreach (int i in roots) {
            int x = EXP[(received.Length - 1 - i) % 255],
                z = EXP[(255 - (received.Length - 1 - i)) % 255],
                denominator = Evaluate(derivative, z);
            if (denominator == 0)
                return new Correction(syndromes, null, new());
            corrected[i] ^= Multiply(x, Divide(Evaluate(omega, z), denominator));
        }
        if (!AllZero(Syndromes(corrected, degree)))
            return new Correction(syndromes, null, new());
        List<int> positions = new();
        for (int i = 0; i < received.Length; i++)
            if (received[i] != corrected[i])
                positions.Add(i);
        return new Correction(syndromes, corrected, positions);
    }
}
