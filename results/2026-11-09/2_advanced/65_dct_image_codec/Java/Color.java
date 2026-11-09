final class Color {
    static int clamp(int v) { return Math.min(Math.max(v, 0), 255); }
    static int[] toYcbcr(int r, int g, int b) {
        return new int[] {Math.floorDiv(19595 * r + 38470 * g + 7471 * b + 32768, 65536),
                          Math.floorDiv(-11059 * r - 21709 * g + 32768 * b + 8421375, 65536),
                          Math.floorDiv(32768 * r - 27439 * g - 5329 * b + 8421375, 65536)};
    }
    static int[] toRgb(int y, int cb, int cr) {
        return new int[] {
            clamp(y + Math.floorDiv(91881 * (cr - 128) + 32768, 65536)),
            clamp(y + Math.floorDiv(-22554 * (cb - 128) - 46802 * (cr - 128) + 32768, 65536)),
            clamp(y + Math.floorDiv(116130 * (cb - 128) + 32768, 65536))};
    }
    static ImageIo.Plane[] split(ImageIo.Image image) {
        int w = image.width(), h = image.height();
        ImageIo.Plane[] planes = new ImageIo.Plane[3];
        for (int k = 0; k < 3; k++)
            planes[k] = new ImageIo.Plane(w, h, new int[w * h]);
        for (int p = 0; p < w * h; p++) {
            int[] pixel = toYcbcr(image.pixels()[3 * p], image.pixels()[3 * p + 1],
                                  image.pixels()[3 * p + 2]);
            for (int k = 0; k < 3; k++)
                planes[k].pixels()[p] = pixel[k];
        }
        return planes;
    }
    static ImageIo.Plane[] components(ImageIo.Plane[] planes, int[][] factors, int mx, int my) {
        int hmax = 1, vmax = 1;
        for (int[] f : factors) {
            hmax = Math.max(hmax, f[0]);
            vmax = Math.max(vmax, f[1]);
        }
        ImageIo.Plane[] result = new ImageIo.Plane[3];
        for (int k = 0; k < 3; k++) {
            ImageIo.Plane source = planes[k];
            int fx = hmax / factors[k][0], fy = vmax / factors[k][1], w = 8 * factors[k][0] * mx,
                h = 8 * factors[k][1] * my;
            int[] data = new int[w * h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                    int sum = 0;
                    for (int j = 0; j < fy; j++)
                        for (int i = 0; i < fx; i++)
                            sum += source.pixels()[Math.min(fy * y + j, source.height() - 1) *
                                                       source.width() +
                                                   Math.min(fx * x + i, source.width() - 1)];
                    data[y * w + x] = sum / (fx * fy);
                }
            result[k] = new ImageIo.Plane(w, h, data);
        }
        return result;
    }
    static ImageIo.Plane[] upsample(ImageIo.Plane[] planes, int[][] factors, int w, int h) {
        int hmax = 1, vmax = 1;
        for (int[] f : factors) {
            hmax = Math.max(hmax, f[0]);
            vmax = Math.max(vmax, f[1]);
        }
        ImageIo.Plane[] result = new ImageIo.Plane[3];
        for (int k = 0; k < 3; k++) {
            int[] pixels = new int[w * h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    pixels[y * w + x] =
                        planes[k].pixels()[(y * factors[k][1] / vmax) * planes[k].width() +
                                           x * factors[k][0] / hmax];
            result[k] = new ImageIo.Plane(w, h, pixels);
        }
        return result;
    }
    static ImageIo.Image combine(ImageIo.Plane[] planes) {
        int w = planes[0].width(), h = planes[0].height();
        int[] image = new int[3 * w * h];
        for (int p = 0; p < w * h; p++) {
            int[] rgb = toRgb(planes[0].pixels()[p], planes[1].pixels()[p], planes[2].pixels()[p]);
            System.arraycopy(rgb, 0, image, 3 * p, 3);
        }
        return new ImageIo.Image(w, h, image);
    }
}
