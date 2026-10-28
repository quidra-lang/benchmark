final class Filters {
    record Gradient(int[][] gx, int[][] gy, int[][] magnitude) {}
    static int clamped(int[][] image, int x, int y) {
        return image[Math.min(Math.max(y, 0), image.length - 1)]
                    [Math.min(Math.max(x, 0), image[0].length - 1)];
    }
    static int[][] smooth(int[][] image, PgmIo.Params params) {
        int height = image.length, width = image[0].length, k = params.get("gauss_size"), half = k / 2;
        long[] kernel = params.row("gauss_kernel");
        int[][] result = new int[height][width];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                long sum = 0;
                for (int j = 0; j < k; j++)
                    for (int i = 0; i < k; i++)
                        sum += kernel[j * k + i] * clamped(image, x + i - half, y + j - half);
                result[y][x] = (int)(sum / params.get("gauss_divisor"));
            }
        return result;
    }
    static Gradient gradient(int[][] image) {
        int height = image.length, width = image[0].length;
        int[][] gx = new int[height][width], gy = new int[height][width], m = new int[height][width];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                int a = clamped(image, x - 1, y - 1), b = clamped(image, x, y - 1),
                    c = clamped(image, x + 1, y - 1), d = clamped(image, x - 1, y),
                    f = clamped(image, x + 1, y), g = clamped(image, x - 1, y + 1),
                    h = clamped(image, x, y + 1), i = clamped(image, x + 1, y + 1);
                gx[y][x] = c + 2 * f + i - (a + 2 * d + g);
                gy[y][x] = g + 2 * h + i - (a + 2 * b + c);
                m[y][x] = Math.abs(gx[y][x]) + Math.abs(gy[y][x]);
            }
        return new Gradient(gx, gy, m);
    }
}
