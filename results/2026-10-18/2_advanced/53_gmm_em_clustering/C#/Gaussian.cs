using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Gaussian {
    public static readonly double PI = Math.PI;
    public record Eigen(double leading, double trailing, double ux, double uy, double angle, double major,
                        double minor, double area, double correlation) {
    }
    public static double Det(double[] s) {
        return s[0] * s[2] - s[1] * s[1];
    }
    public static double Q(double x, double y, double[] mean, double[] s) {
        double dx = x - mean[0], dy = y - mean[1];
        return (s[2] * dx * dx - 2 * s[1] * dx * dy + s[0] * dy * dy) / Det(s);
    }
    public static double LogDensity(double x, double y, double weight, double[] mean, double[] s) {
        return Math.Log(weight) - Math.Log(2 * PI) - Math.Log(Det(s)) / 2 - Q(x, y, mean, s) / 2;
    }
    public static Eigen EigenData(double[] s) {
        double a = s[0], b = s[1], c = s[2], h = (a + c) / 2,
               g = Math.Sqrt(((a - c) / 2) * ((a - c) / 2) + b * b), l1 = h + g, l2 = h - g, ux, uy;
        if (b == 0) {
            ux = a >= c ? 1 : 0;
            uy = a >= c ? 0 : 1;
        } else {
            double vx = a >= c ? l1 - c : b, vy = a >= c ? b : l1 - a, length = Math.Sqrt(vx * vx + vy * vy);
            ux = vx / length;
            uy = vy / length;
            if (vx < 0) {
                ux = -ux;
                uy = -uy;
            }
        }
        return new Eigen(l1, l2, ux, uy, Math.Atan2(uy, ux) * 180 / PI, Math.Sqrt(l1), Math.Sqrt(l2),
                         PI * Math.Sqrt(l1 * l2), b / Math.Sqrt(a * c));
    }
    public static double Bhattacharyya(double[] m1, double[] s1, double[] m2, double[] s2) {
        double[] average = { (s1[0] + s2[0]) / 2, (s1[1] + s2[1]) / 2, (s1[2] + s2[2]) / 2 };
        return Q(m2[0], m2[1], m1, average) / 8 + Math.Log(Det(average) / Math.Sqrt(Det(s1) * Det(s2))) / 2;
    }
}
