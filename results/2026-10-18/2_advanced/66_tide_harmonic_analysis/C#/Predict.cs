using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Predict {
    public sealed class Extremum {
        public bool high;
        public double minute, height;
        public int rounded;
        public string label;
        public Extremum(bool high, double minute, double height) {
            this.high = high;
            this.minute = minute;
            this.height = height;
        }
    }
    public static double Height(HarmonicFit.Model m, double t) {
        double value = m.coefficients[0];
        for (int k = 0; k < m.selected.Count; k++) {
            double angle = HarmonicFit.Angle(m.selected[k].speed, t);
            HarmonicFit.Constant c = m.constants[k];
            value += c.a * Math.Cos(angle) + c.b * Math.Sin(angle);
        }
        return value;
    }
    public static double[] Hours(HarmonicFit.Model m, int start, int count) {
        double[] values = new double[count + 1];
        for (int i = 0; i <= count; i++)
            values[i] = Height(m, start + i);
        return values;
    }
    public static List<Extremum> Extrema(HarmonicFit.Model m, int start, int hours, int grid) {
        int count = hours * 60 / grid;
        double[] values = new double[count + 1];
        for (int j = 0; j <= count; j++)
            values[j] = Height(m, (60 * start + j * grid) / 60.0);
        List<Extremum> result = new();
        for (int j = 1; j < count; j++) {
            double left = values[j - 1], center = values[j], right = values[j + 1];
            bool high = left < center && center > right, low = left > center && center < right;
            if (!high && !low)
                continue;
            double delta = (left - right) / (2 * (left - 2 * center + right)),
                   minute = 60 * start + j * grid + delta * grid,
                   z = center - (left - right) * delta / 4;
            result.Add(new Extremum(high, minute, z));
        }
        return result;
    }
}
