using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Materials {
    public record Material(char code, string name, double k, double rho, double cp) {
    }
    public static List<Material> Read() {
        List<Material> materials = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input/materials.txt")).ToList()) {
            string[] w = line.Split(' ');
            materials.Add(
                new Material(w[0][0], w[1], double.Parse(w[2]), double.Parse(w[3]), double.Parse(w[4])));
        }
        return materials;
    }
    public static double Capacity(Material m, double dx, double d) {
        return m.rho * m.cp * dx * dx * d;
    }
    public static double Interior(double k1, double k2, double d) {
        return 2 * k1 * k2 / (k1 + k2) * d;
    }
    public static double FixedFace(double k, double d) {
        return 2 * k * d;
    }
    public static double Convective(double k, double h, double dx, double d) {
        return 1 / (1 / (h * dx * d) + 1 / (2 * k * d));
    }
}
