import java.util.*;

final class Inference {
    static double logGamma(double x) {
        double[] c = {76.18009172947146,  -86.50532032941677,   24.01409824083091,
                      -1.231739572450155, 0.001208650973866179, -0.000005395239384953};
        double t = x + 5.5, total = t - (x + 0.5) * Math.log(t), sum = 1.000000000190015;
        for (int j = 1; j <= c.length; j++)
            sum += c[j - 1] / (x + j);
        return -total + Math.log(2.5066282746310005 * sum / x);
    }
    static double small(double value) {
        return Math.abs(value) < 1e-300 ? 1e-300 : value;
    }
    static double betaFraction(double a, double b, double x) {
        double c = 1, d = 1 / small(1 - (a + b) * x / (a + 1)), h = d;
        for (int m = 1; m <= 1000; m++) {
            double q = m * (b - m) * x / ((a - 1 + 2 * m) * (a + 2 * m));
            d = 1 / small(1 + q * d);
            c = small(1 + q / c);
            h *= d * c;
            q = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 1 + 2 * m));
            d = 1 / small(1 + q * d);
            c = small(1 + q / c);
            double delta = d * c;
            h *= delta;
            if (Math.abs(delta - 1) < 1e-15)
                break;
        }
        return h;
    }
    static double beta(double x, double a, double b) {
        if (x <= 0)
            return 0;
        if (x >= 1)
            return 1;
        double front =
            Math.exp(logGamma(a + b) - logGamma(a) - logGamma(b) + a * Math.log(x) + b * Math.log(1 - x));
        return x < (a + 1) / (a + b + 2) ? front * betaFraction(a, b, x) / a
                                         : 1 - front * betaFraction(b, a, 1 - x) / b;
    }
    static double gammaQ(double a, double x) {
        if (x == 0)
            return 1;
        double front = Math.exp(-x + a * Math.log(x) - logGamma(a));
        if (x < a + 1) {
            double t = 1 / a, sum = t, e = a;
            for (int i = 0; i < 1000; i++) {
                e += 1;
                t *= x / e;
                sum += t;
                if (Math.abs(t) < Math.abs(sum) * 1e-15)
                    break;
            }
            return 1 - sum * front;
        }
        double b = x + 1 - a, c = 1 / 1e-300, d = 1 / b, h = d;
        for (int i = 1; i <= 1000; i++) {
            double q = -i * (i - a);
            b += 2;
            d = 1 / small(q * d + b);
            c = small(b + q / c);
            double delta = d * c;
            h *= delta;
            if (Math.abs(delta - 1) < 1e-15)
                break;
        }
        return front * h;
    }
    static double pt(double t, int degrees) {
        return beta((double)degrees / (degrees + t * t), degrees / 2.0, 0.5);
    }
    static double pf(double f, int a, int b) {
        return beta((double)b / (b + a * f), b / 2.0, a / 2.0);
    }
    static double pchi(double value, int degrees) {
        return gammaQ(degrees / 2.0, value / 2);
    }
    static double quantile(double confidence, int degrees) {
        double lo = 0, hi = 1000;
        for (int i = 0; i < 100; i++) {
            double mid = (lo + hi) / 2;
            if (pt(mid, degrees) > 1 - confidence)
                lo = mid;
            else
                hi = mid;
        }
        return (lo + hi) / 2;
    }
    static String mark(double p) {
        return p < 0.001 ? "***" : p < 0.01 ? "**" : p < 0.05 ? "*" : p < 0.1 ? "." : "";
    }
    static String real(double value) {
        if (Double.isNaN(value))
            return "NA";
        String text = String.format(Locale.ROOT, "%.4f", value);
        return text.equals("-0.0000") ? "0.0000" : text;
    }
    static String pvalue(double value) {
        return Double.isNaN(value) ? "NA" : value < 0.0001 ? "<0.0001" : real(value);
    }
}
