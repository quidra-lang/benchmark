using System;
using System.Collections.Generic;
public static class Design {
    public const double PI = 3.141592653589793;
    public static double Buckling(Assembly.Properties p, Assembly.Geometry g,
                                  double inertia) => PI * PI * p.young * inertia /
                                                     (g.length * g.length);
    public static double Buckling(Assembly.Properties p,
                                  Assembly.Geometry g) => Buckling(p, g, p.inertia);
    public static double Utilization(double force, Assembly.Properties p, Assembly.Geometry g,
                                     ModelIo.Section section = null) {
        double area = section == null ? p.area : section.area,
               inertia = section == null ? p.inertia : section.inertia;
        return Math.Max(Math.Abs(force / area) / p.yieldStress,
                        Math.Max(0, -force) / Buckling(p, g, inertia));
    }
    public static double Slenderness(Assembly.Properties p, Assembly.Geometry g,
                                     ModelIo.Section section = null) {
        double area = section == null ? p.area : section.area,
               inertia = section == null ? p.inertia : section.inertia;
        return g.length / Math.Sqrt(inertia / area);
    }
    public static double Limit(int member, List<Postprocess.Result> combinations,
                               ModelIo.Settings settings) {
        foreach (Postprocess.Result result in combinations)
            if (result.forces[member] < 0)
                return settings.compressionLimit;
        return settings.tensionLimit;
    }
    public static int Select(List<int> members, List<ModelIo.Section> sections,
                             List<Assembly.Properties> properties, List<Assembly.Geometry> geometry,
                             List<Postprocess.Result> combinations, double[] limits) {
        for (int s = 0; s < sections.Count; s++) {
            ModelIo.Section section = sections[s];
            bool acceptable = true;
            foreach (int m in members) {
                if (Slenderness(properties[m], geometry[m], section) > limits[m]) {
                    acceptable = false;
                    break;
                }
                foreach (Postprocess.Result result in combinations)
                    if (Utilization(result.forces[m], properties[m], geometry[m], section) > 1) {
                        acceptable = false;
                        break;
                    }
                if (!acceptable)
                    break;
            }
            if (acceptable)
                return s;
        }
        return sections.Count - 1;
    }
}
