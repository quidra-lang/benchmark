using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Fitting {
    public static readonly double PHI = 0.6180339887498949;
    public record GoldenRecord(double a, double b, double c, double d, double fc, double fd) {
    }
    public record Golden(double point, double value, List<GoldenRecord> records) {
    }
    public static Golden SearchGolden(Func<double, double> function, double a, double b, int iterations) {
        double c = b - PHI * (b - a), d = a + PHI * (b - a), fc = function.Invoke(c), fd = function.Invoke(d);
        List<GoldenRecord> records = new();
        records.Add(new GoldenRecord(a, b, c, d, fc, fd));
        for (int i = 0; i < iterations; i++) {
            if (fc < fd) {
                b = d;
                d = c;
                fd = fc;
                c = b - PHI * (b - a);
                fc = function.Invoke(c);
            } else {
                a = c;
                c = d;
                fc = fd;
                d = a + PHI * (b - a);
                fd = function.Invoke(d);
            }
            records.Add(new GoldenRecord(a, b, c, d, fc, fd));
        }
        return fc < fd ? new Golden(c, fc, records) : new Golden(d, fd, records);
    }
    public record Point(double beta, double gamma) {
    }
    public record Vertex(int serial, double beta, double gamma, double value) {
    }
    public record Operation(string name, Vertex best) {
    }
    public record Simplex(List<Vertex> initial, List<Operation> operations, List<Vertex> vertices) {
    }
    public static int Compare(Vertex a, Vertex b) {
        int c = (a.value).CompareTo(b.value);
        return c != 0 ? c : (a.serial).CompareTo(b.serial);
    }
    public static Point Toward(Point origin, Point target, double factor) {
        return new Point(origin.beta + factor * (target.beta - origin.beta),
                         origin.gamma + factor * (target.gamma - origin.gamma));
    }
    public static Simplex Nelder(Func<double, double, double> objective, double beta, double gamma, double db,
                                 double dg, double alpha, double chi, double psi, double omega,
                                 int iterations) {
        List<Vertex> vertices = new([
            new Vertex(0, beta, gamma, objective.Invoke(beta, gamma)),
            new Vertex(1, beta + db, gamma, objective.Invoke(beta + db, gamma)),
            new Vertex(2, beta, gamma + dg, objective.Invoke(beta, gamma + dg))
        ]);
        List<Vertex> initial = new(vertices);
        List<Operation> operations = new();
        int serial = 3;
        for (int k = 0; k < iterations; k++) {
            vertices.Sort(Compare);
            Vertex first = vertices[0], second = vertices[1], third = vertices[2];
            Point origin = new Point((first.beta + second.beta) / 2, (first.gamma + second.gamma) / 2),
                  reflected = new Point(origin.beta + alpha * (origin.beta - third.beta),
                                        origin.gamma + alpha * (origin.gamma - third.gamma));
            double fr = objective.Invoke(reflected.beta, reflected.gamma), value = 0;
            Point accepted = null;
            string operation = "shrink";
            if (fr < first.value) {
                Point expanded = Toward(origin, reflected, chi);
                double fe = objective.Invoke(expanded.beta, expanded.gamma);
                if (fe < fr) {
                    accepted = expanded;
                    value = fe;
                    operation = "expand";
                } else {
                    accepted = reflected;
                    value = fr;
                    operation = "reflect";
                }
            } else if (fr < second.value) {
                accepted = reflected;
                value = fr;
                operation = "reflect";
            } else if (fr < third.value) {
                Point contracted = Toward(origin, reflected, psi);
                double fc = objective.Invoke(contracted.beta, contracted.gamma);
                if (fc <= fr) {
                    accepted = contracted;
                    value = fc;
                    operation = "contract_out";
                }
            } else {
                Point contracted = Toward(origin, new Point(third.beta, third.gamma), psi);
                double fc = objective.Invoke(contracted.beta, contracted.gamma);
                if (fc < third.value) {
                    accepted = contracted;
                    value = fc;
                    operation = "contract_in";
                }
            }
            vertices = new([first]);
            if (accepted == null) {
                foreach (Vertex vertex in new Vertex[] { second, third }) {
                    Point point = Toward(new Point(first.beta, first.gamma),
                                         new Point(vertex.beta, vertex.gamma), omega);
                    vertices.Add(new Vertex(serial++, point.beta, point.gamma,
                                            objective.Invoke(point.beta, point.gamma)));
                }
            } else {
                vertices.Add(second);
                vertices.Add(new Vertex(serial++, accepted.beta, accepted.gamma, value));
            }
            vertices.Sort(Compare);
            operations.Add(new Operation(operation, vertices[0]));
        }
        return new Simplex(initial, operations, vertices);
    }
}
