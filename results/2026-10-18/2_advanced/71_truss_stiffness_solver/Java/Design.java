import java.util.*;
final class Design {
    static final double PI = 3.141592653589793;
    static double buckling(Assembly.Properties p, Assembly.Geometry g, double inertia) {
        return PI * PI * p.young() * inertia / (g.length() * g.length());
    }
    static double buckling(Assembly.Properties p, Assembly.Geometry g) {
        return buckling(p, g, p.inertia());
    }
    static double utilization(double force, Assembly.Properties p, Assembly.Geometry g,
                              ModelIo.Section section) {
        double area = section == null ? p.area() : section.area(),
               inertia = section == null ? p.inertia() : section.inertia();
        return Math.max(Math.abs(force / area) / p.yieldStress(),
                        Math.max(0, -force) / buckling(p, g, inertia));
    }
    static double utilization(double force, Assembly.Properties p, Assembly.Geometry g) {
        return utilization(force, p, g, null);
    }
    static double slenderness(Assembly.Properties p, Assembly.Geometry g, ModelIo.Section section) {
        double area = section == null ? p.area() : section.area(),
               inertia = section == null ? p.inertia() : section.inertia();
        return g.length() / Math.sqrt(inertia / area);
    }
    static double slenderness(Assembly.Properties p, Assembly.Geometry g) {
        return slenderness(p, g, null);
    }
    static double limit(int member, List<Postprocess.Result> combinations,
                        ModelIo.Settings settings) {
        for (Postprocess.Result result : combinations)
            if (result.forces()[member] < 0)
                return settings.compressionLimit;
        return settings.tensionLimit;
    }
    static int select(List<Integer> members, List<ModelIo.Section> sections,
                      List<Assembly.Properties> properties, List<Assembly.Geometry> geometry,
                      List<Postprocess.Result> combinations, double[] limits) {
        for (int s = 0; s < sections.size(); s++) {
            ModelIo.Section section = sections.get(s);
            boolean acceptable = true;
            for (int m : members) {
                if (slenderness(properties.get(m), geometry.get(m), section) > limits[m]) {
                    acceptable = false;
                    break;
                }
                for (Postprocess.Result result : combinations)
                    if (utilization(result.forces()[m], properties.get(m), geometry.get(m),
                                    section) > 1) {
                        acceptable = false;
                        break;
                    }
                if (!acceptable)
                    break;
            }
            if (acceptable)
                return s;
        }
        return sections.size() - 1;
    }
}
