import java.util.*;
import java.util.function.*;

final class Fitting {
    static final double PHI = 0.6180339887498949;
    record GoldenRecord(double a, double b, double c, double d, double fc, double fd) {}
    record Golden(double point, double value, List<GoldenRecord> records) {}
    static Golden golden(DoubleUnaryOperator function, double a, double b, int iterations) {
        double c = b - PHI * (b - a), d = a + PHI * (b - a), fc = function.applyAsDouble(c),
               fd = function.applyAsDouble(d);
        List<GoldenRecord> records = new ArrayList<>();
        records.add(new GoldenRecord(a, b, c, d, fc, fd));
        for (int i = 0; i < iterations; i++) {
            if (fc < fd) {
                b = d;
                d = c;
                fd = fc;
                c = b - PHI * (b - a);
                fc = function.applyAsDouble(c);
            } else {
                a = c;
                c = d;
                fc = fd;
                d = a + PHI * (b - a);
                fd = function.applyAsDouble(d);
            }
            records.add(new GoldenRecord(a, b, c, d, fc, fd));
        }
        return fc < fd ? new Golden(c, fc, records) : new Golden(d, fd, records);
    }
    record Point(double beta, double gamma) {}
    record Vertex(int serial, double beta, double gamma, double value) {}
    record Operation(String name, Vertex best) {}
    record Simplex(List<Vertex> initial, List<Operation> operations, List<Vertex> vertices) {}
    static int compare(Vertex a, Vertex b) {
        int c = Double.compare(a.value(), b.value());
        return c != 0 ? c : Integer.compare(a.serial(), b.serial());
    }
    static Point toward(Point origin, Point target, double factor) {
        return new Point(origin.beta() + factor * (target.beta() - origin.beta()),
                         origin.gamma() + factor * (target.gamma() - origin.gamma()));
    }
    static Simplex nelder(DoubleBinaryOperator objective, double beta, double gamma, double db, double dg,
                          double alpha, double chi, double psi, double omega, int iterations) {
        List<Vertex> vertices = new ArrayList<>(
            List.of(new Vertex(0, beta, gamma, objective.applyAsDouble(beta, gamma)),
                    new Vertex(1, beta + db, gamma, objective.applyAsDouble(beta + db, gamma)),
                    new Vertex(2, beta, gamma + dg, objective.applyAsDouble(beta, gamma + dg))));
        List<Vertex> initial = new ArrayList<>(vertices);
        List<Operation> operations = new ArrayList<>();
        int serial = 3;
        for (int k = 0; k < iterations; k++) {
            vertices.sort(Fitting::compare);
            Vertex first = vertices.get(0), second = vertices.get(1), third = vertices.get(2);
            Point origin =
                      new Point((first.beta() + second.beta()) / 2, (first.gamma() + second.gamma()) / 2),
                  reflected = new Point(origin.beta() + alpha * (origin.beta() - third.beta()),
                                        origin.gamma() + alpha * (origin.gamma() - third.gamma()));
            double fr = objective.applyAsDouble(reflected.beta(), reflected.gamma()), value = 0;
            Point accepted = null;
            String operation = "shrink";
            if (fr < first.value()) {
                Point expanded = toward(origin, reflected, chi);
                double fe = objective.applyAsDouble(expanded.beta(), expanded.gamma());
                if (fe < fr) {
                    accepted = expanded;
                    value = fe;
                    operation = "expand";
                } else {
                    accepted = reflected;
                    value = fr;
                    operation = "reflect";
                }
            } else if (fr < second.value()) {
                accepted = reflected;
                value = fr;
                operation = "reflect";
            } else if (fr < third.value()) {
                Point contracted = toward(origin, reflected, psi);
                double fc = objective.applyAsDouble(contracted.beta(), contracted.gamma());
                if (fc <= fr) {
                    accepted = contracted;
                    value = fc;
                    operation = "contract_out";
                }
            } else {
                Point contracted = toward(origin, new Point(third.beta(), third.gamma()), psi);
                double fc = objective.applyAsDouble(contracted.beta(), contracted.gamma());
                if (fc < third.value()) {
                    accepted = contracted;
                    value = fc;
                    operation = "contract_in";
                }
            }
            vertices = new ArrayList<>(List.of(first));
            if (accepted == null) {
                for (Vertex vertex : new Vertex[] {second, third}) {
                    Point point = toward(new Point(first.beta(), first.gamma()),
                                         new Point(vertex.beta(), vertex.gamma()), omega);
                    vertices.add(new Vertex(serial++, point.beta(), point.gamma(),
                                            objective.applyAsDouble(point.beta(), point.gamma())));
                }
            } else {
                vertices.add(second);
                vertices.add(new Vertex(serial++, accepted.beta(), accepted.gamma(), value));
            }
            vertices.sort(Fitting::compare);
            operations.add(new Operation(operation, vertices.get(0)));
        }
        return new Simplex(initial, operations, vertices);
    }
}
