final class Gaussian {
    static final double PI = Math.PI;
    record Eigen(double leading, double trailing, double ux, double uy, double angle, double major,
                 double minor, double area, double correlation) {}
    static double det(double[] s) {
        return s[0] * s[2] - s[1] * s[1];
    }
    static double q(double x, double y, double[] mean, double[] s) {
        double dx = x - mean[0], dy = y - mean[1];
        return (s[2] * dx * dx - 2 * s[1] * dx * dy + s[0] * dy * dy) / det(s);
    }
    static double logDensity(double x, double y, double weight, double[] mean, double[] s) {
        return Math.log(weight) - Math.log(2 * PI) - Math.log(det(s)) / 2 - q(x, y, mean, s) / 2;
    }
    static Eigen eigen(double[] s) {
        double a = s[0], b = s[1], c = s[2], h = (a + c) / 2,
               g = Math.sqrt(((a - c) / 2) * ((a - c) / 2) + b * b), l1 = h + g, l2 = h - g, ux, uy;
        if (b == 0) {
            ux = a >= c ? 1 : 0;
            uy = a >= c ? 0 : 1;
        } else {
            double vx = a >= c ? l1 - c : b, vy = a >= c ? b : l1 - a, length = Math.sqrt(vx * vx + vy * vy);
            ux = vx / length;
            uy = vy / length;
            if (vx < 0) {
                ux = -ux;
                uy = -uy;
            }
        }
        return new Eigen(l1, l2, ux, uy, Math.atan2(uy, ux) * 180 / PI, Math.sqrt(l1), Math.sqrt(l2),
                         PI * Math.sqrt(l1 * l2), b / Math.sqrt(a * c));
    }
    static double bhattacharyya(double[] m1, double[] s1, double[] m2, double[] s2) {
        double[] average = {(s1[0] + s2[0]) / 2, (s1[1] + s2[1]) / 2, (s1[2] + s2[2]) / 2};
        return q(m2[0], m2[1], m1, average) / 8 + Math.log(det(average) / Math.sqrt(det(s1) * det(s2))) / 2;
    }
}
