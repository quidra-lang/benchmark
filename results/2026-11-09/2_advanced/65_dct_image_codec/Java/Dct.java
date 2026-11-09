final class Dct {
    static final int[] ZIGZAG = zigzagIndices();
    static int[] zigzagIndices() {
        int[] result = new int[64];
        int k = 0;
        for (int sum = 0; sum <= 14; sum++)
            for (int j = 0; j < 8; j++) {
                int u = sum % 2 == 1 ? j : 7 - j, v = sum - u;
                if (v >= 0 && v < 8)
                    result[k++] = 8 * u + v;
            }
        return result;
    }
    static int rounded(int value, int shift) { return (value + (1 << (shift - 1))) >> shift; }
    static int[] forward(int[] pixels, int[] c) {
        int[] e = new int[64], f = new int[64];
        for (int u = 0; u < 8; u++)
            for (int x = 0; x < 8; x++) {
                int sum = 0;
                for (int y = 0; y < 8; y++)
                    sum += c[8 * u + y] * (pixels[8 * y + x] - 128);
                e[8 * u + x] = rounded(sum, 11);
            }
        for (int u = 0; u < 8; u++)
            for (int v = 0; v < 8; v++) {
                int sum = 0;
                for (int x = 0; x < 8; x++)
                    sum += e[8 * u + x] * c[8 * v + x];
                f[8 * u + v] = rounded(sum, 15);
            }
        return f;
    }
    static int[] inverse(int[] coefficients, int[] c) {
        int[] s = new int[64], g = new int[64];
        for (int y = 0; y < 8; y++)
            for (int v = 0; v < 8; v++) {
                int sum = 0;
                for (int u = 0; u < 8; u++)
                    sum += c[8 * u + y] * coefficients[8 * u + v];
                s[8 * y + v] = rounded(sum, 11);
            }
        for (int y = 0; y < 8; y++)
            for (int x = 0; x < 8; x++) {
                int sum = 0;
                for (int v = 0; v < 8; v++)
                    sum += s[8 * y + v] * c[8 * v + x];
                g[8 * y + x] = Color.clamp(rounded(sum, 15) + 128);
            }
        return g;
    }
    static int[][] tables(int[][] basic, int quality) {
        int scale = quality < 50 ? 5000 / quality : 200 - 2 * quality;
        int[][] result = new int[4][];
        for (int t = 0; t < 2; t++) {
            result[t] = new int[64];
            for (int i = 0; i < 64; i++)
                result[t][i] = Math.min(Math.max((basic[t][i] * scale + 50) / 100, 1), 255);
        }
        return result;
    }
    static int[] quantize(int[] values, int[] table) {
        int[] result = new int[64];
        for (int i = 0; i < 64; i++) {
            int magnitude = (Math.abs(values[i]) + table[i] / 2) / table[i];
            result[i] = values[i] < 0 ? -magnitude : magnitude;
        }
        return result;
    }
    static int[] zigzag(int[] values) {
        int[] result = new int[64];
        for (int i = 0; i < 64; i++)
            result[i] = values[ZIGZAG[i]];
        return result;
    }
    static int[] unzigzag(int[] values) {
        int[] result = new int[64];
        for (int i = 0; i < 64; i++)
            result[ZIGZAG[i]] = values[i];
        return result;
    }
    static int[] dequantize(int[] sequence, int[] table, int keep) {
        int[] result = new int[64];
        for (int i = 0; i < keep; i++)
            result[ZIGZAG[i]] = sequence[i] * table[ZIGZAG[i]];
        return result;
    }
}
