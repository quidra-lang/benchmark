using System;
using System.Collections.Generic;
using System.Linq;
public static class Assembly {
    public record Geometry(double length, double cosine, double sine, int[] dofs);
    public record Properties(double area, double inertia, double young, double yieldStress,
                             double density, double expansion, double stiffness);
    public record Loading(double[] external, double[] total, double[] temperature, bool settlement);
    public static List<Geometry> GeometryList(List<ModelIo.Node> nodes,
                                              List<ModelIo.Member> members, int[][] nodeDofs) {
        List<Geometry> result = new();
        foreach (ModelIo.Member member in members) {
            ModelIo.Node a = nodes[member.start], b = nodes[member.end];
            int dx = b.x - a.x, dy = b.y - a.y;
            double length = Math.Sqrt(dx * dx + dy * dy);
            result.Add(new(length, dx / length, dy / length,
                           new[] { nodeDofs[member.start][0], nodeDofs[member.start][1],
                                   nodeDofs[member.end][0], nodeDofs[member.end][1] }));
        }
        return result;
    }
    public static List<Properties> PropertyList(ModelIo.Model model, int[] choices,
                                                List<Geometry> geometry) {
        List<Properties> result = new();
        for (int m = 0; m < choices.Length; m++) {
            ModelIo.Member member = model.members[m];
            ModelIo.Section section = model.sections[choices[m]];
            ModelIo.Material material = model.materials[member.material];
            result.Add(new(section.area, section.inertia, material.young, material.yieldStress,
                           material.density, material.expansion,
                           material.young * section.area / geometry[m].length));
        }
        return result;
    }
    public static double Weight(Properties p, Geometry g) => p.density * 9.81 * p.area * g.length /
                                                             1000000000;
    public static double[][] Stiffness(Properties p, Geometry g) {
        double k = p.stiffness, c = g.cosine, s = g.sine, xx = k * (c * c), xy = k * (c * s),
               yy = k * (s * s);
        return new[] { new[] { xx, xy, -xx, -xy }, new[] { xy, yy, -xy, -yy },
                       new[] { -xx, -xy, xx, xy }, new[] { -xy, -yy, xy, yy } };
    }
    public static double[][] Assemble(List<Geometry> geometry, List<Properties> properties,
                                      int degrees, int removed) {
        double[][] matrix = Enumerable.Range(0, degrees)
                                .Select(
                                    _ => new double[degrees])
                                .ToArray();
        for (int m = 0; m < geometry.Count; m++)
            if (m != removed) {
                Geometry shape = geometry[m];
                double[][] local = Stiffness(properties[m], shape);
                for (int i = 0; i < 4; i++)
                    for (int j = 0; j < 4; j++)
                        matrix[shape.dofs[i]][shape.dofs[j]] += local[i][j];
            }
        return matrix;
    }
    public static Loading Loads(ModelIo.LoadCase loadCase, List<Geometry> geometry,
                                List<Properties> properties, int[][] nodeDofs, int degrees,
                                int removed) {
        double[] external = new double[degrees], thermal = new double[degrees],
                 temperature = new double[geometry.Count];
        bool settlement = false;
        foreach (ModelIo.Load load in loadCase.lines)
            switch (load.kind) {
            case "FORCE":
                external[nodeDofs[load.index][0]] += load.first * 1000;
                external[nodeDofs[load.index][1]] += load.second * 1000;
                break;
            case "TEMPERATURE": {
                int m = load.index;
                if (m != removed) {
                    Properties p = properties[m];
                    Geometry g = geometry[m];
                    double force = p.young * p.area * p.expansion * load.first;
                    temperature[m] = force;
                    double[] direction = { -g.cosine, -g.sine, g.cosine, g.sine };
                    for (int i = 0; i < 4; i++)
                        thermal[g.dofs[i]] += force * direction[i];
                }
                break;
            }
            case "SELFWEIGHT":
                for (int m = 0; m < geometry.Count; m++)
                    if (m != removed) {
                        Geometry g = geometry[m];
                        double weight = Weight(properties[m], g);
                        external[g.dofs[1]] -= weight / 2;
                        external[g.dofs[3]] -= weight / 2;
                    }
                break;
            case "SETTLEMENT":
                settlement = true;
                break;
            }
        double[] total = new double[degrees];
        for (int d = 0; d < degrees; d++)
            total[d] = external[d] + thermal[d];
        return new(external, total, temperature, settlement);
    }
}
