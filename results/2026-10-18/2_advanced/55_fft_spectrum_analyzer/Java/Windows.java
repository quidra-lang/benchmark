final class Windows {
    static final String[] NAMES = {"rectangular", "hann", "hamming", "blackman", "flattop"};
    record Window(double[] values, double s1, double s2, double gain, double bins, double hz,
                  double scalloping) {}
    static double[] coefficients(String name) {
        return switch (name) {
            case "rectangular" -> new double[] {1};
            case "hann" -> new double[] {0.5, 0.5};
            case "hamming" -> new double[] {0.54, 0.46};
            case "blackman" -> new double[] {0.42, 0.5, 0.08};
            default -> new double[] {0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368};
        };
    }
    static Window create(String name, int length, int fs) {
        double[] coefficients = coefficients(name), values = new double[length];
        double s1 = 0, s2 = 0;
        Fft.Complex sum = new Fft.Complex(0, 0);
        for (int n = 0; n < length; n++) {
            double value = 0;
            for (int j = 0; j < coefficients.length; j++)
                value += (j % 2 == 0 ? 1 : -1) * coefficients[j] * Math.cos(2 * Fft.PI * j * n / length);
            values[n] = value;
            s1 += value;
            s2 += value * value;
            sum = sum.add(Fft.rotation(Fft.PI * n / length).scale(value));
        }
        double bins = length * s2 / (s1 * s1);
        return new Window(values, s1, s2, s1 / length, bins, bins * fs / length,
                          -20 * Math.log10(sum.abs() / s1));
    }
}
