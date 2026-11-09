import java.util.*;
final class Assembly {
    record Geometry(double length, double cosine, double sine, int[] dofs) {}
    record Properties(double area, double inertia, double young, double yieldStress, double density,
                      double expansion, double stiffness) {}
    record Loading(double[] external, double[] total, double[] temperature, boolean settlement) {}
    static List<Geometry> geometry(List<ModelIo.Node> nodes, List<ModelIo.Member> members,
                                   int[][] nodeDofs) {
        List<Geometry> result = new ArrayList<>();
        for (ModelIo.Member member : members) {
            ModelIo.Node a = nodes.get(member.start()), b = nodes.get(member.end());
            int dx = b.x() - a.x(), dy = b.y() - a.y();
            double length = Math.sqrt(dx * dx + dy * dy);
            result.add(
                new Geometry(length, dx / length, dy / length,
                             new int[] {nodeDofs[member.start()][0], nodeDofs[member.start()][1],
                                        nodeDofs[member.end()][0], nodeDofs[member.end()][1]}));
        }
        return result;
    }
    static List<Properties> properties(ModelIo.Model model, int[] choices,
                                       List<Geometry> geometry) {
        List<Properties> result = new ArrayList<>();
        for (int m = 0; m < choices.length; m++) {
            ModelIo.Member member = model.members().get(m);
            ModelIo.Section section = model.sections().get(choices[m]);
            ModelIo.Material material = model.materials().get(member.material());
            result.add(
                new Properties(section.area(), section.inertia(), material.young(),
                               material.yieldStress(), material.density(), material.expansion(),
                               material.young() * section.area() / geometry.get(m).length()));
        }
        return result;
    }
    static double weight(Properties p, Geometry g) {
        return p.density() * 9.81 * p.area() * g.length() / 1000000000;
    }
    static double[][] stiffness(Properties p, Geometry g) {
        double k = p.stiffness(), c = g.cosine(), s = g.sine(), xx = k * (c * c), xy = k * (c * s),
               yy = k * (s * s);
        return new double[][] {
            {xx, xy, -xx, -xy}, {xy, yy, -xy, -yy}, {-xx, -xy, xx, xy}, {-xy, -yy, xy, yy}};
    }
    static double[][] assemble(List<Geometry> geometry, List<Properties> properties, int degrees,
                               int removed) {
        double[][] matrix = new double[degrees][degrees];
        for (int m = 0; m < geometry.size(); m++)
            if (m != removed) {
                Geometry shape = geometry.get(m);
                double[][] local = stiffness(properties.get(m), shape);
                for (int i = 0; i < 4; i++)
                    for (int j = 0; j < 4; j++)
                        matrix[shape.dofs()[i]][shape.dofs()[j]] += local[i][j];
            }
        return matrix;
    }
    static Loading loads(ModelIo.LoadCase loadCase, List<Geometry> geometry,
                         List<Properties> properties, int[][] nodeDofs, int degrees, int removed) {
        double[] external = new double[degrees], thermal = new double[degrees],
                 temperature = new double[geometry.size()];
        boolean settlement = false;
        for (ModelIo.Load load : loadCase.lines())
            switch (load.kind()) {
            case "FORCE" -> {
                external[nodeDofs[load.index()][0]] += load.first() * 1000;
                external[nodeDofs[load.index()][1]] += load.second() * 1000;
            }
            case "TEMPERATURE" -> {
                int m = load.index();
                if (m != removed) {
                    Properties p = properties.get(m);
                    Geometry g = geometry.get(m);
                    double force = p.young() * p.area() * p.expansion() * load.first();
                    temperature[m] = force;
                    double[] direction = {-g.cosine(), -g.sine(), g.cosine(), g.sine()};
                    for (int i = 0; i < 4; i++)
                        thermal[g.dofs()[i]] += force * direction[i];
                }
            }
            case "SELFWEIGHT" -> {
                for (int m = 0; m < geometry.size(); m++)
                    if (m != removed) {
                        Geometry g = geometry.get(m);
                        double weight = weight(properties.get(m), g);
                        external[g.dofs()[1]] -= weight / 2;
                        external[g.dofs()[3]] -= weight / 2;
                    }
            }
            case "SETTLEMENT" -> settlement = true;
            }
        double[] total = new double[degrees];
        for (int d = 0; d < degrees; d++)
            total[d] = external[d] + thermal[d];
        return new Loading(external, total, temperature, settlement);
    }
}
