using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed class Optics {
    public static readonly int INF = int.MaxValue;
    public readonly int[] core, reach, predecessor;
    public readonly List<int> order = new();
    public Optics(List<Point> points, int[][] neighborhoods, int minimum) {
        int count = points.Count;
        core = new int[count];
        reach = new int[count];
        predecessor = new int[count];
        Array.Fill(core, INF);
        Array.Fill(reach, INF);
        Array.Fill(predecessor, -1);
        bool[] processed = new bool[count], seeds = new bool[count];
        for (int i = 0; i < count; i++)
            if (neighborhoods[i].Length >= minimum) {
                int[] distances = new int[neighborhoods[i].Length];
                for (int j = 0; j < distances.Length; j++)
                    distances[j] = GridIndex.Distance(points[i], points[neighborhoods[i][j]]);
                Array.Sort(distances);
                core[i] = distances[minimum - 1];
            }
        for (int start = 0; start < count; start++) {
            if (processed[start])
                continue;
            seeds[start] = true;
            while (true) {
                int current = -1;
                for (int i = 0; i < count; i++)
                    if (seeds[i] && (current < 0 || reach[i] < reach[current]))
                        current = i;
                if (current < 0)
                    break;
                seeds[current] = false;
                processed[current] = true;
                order.Add(current);
                if (core[current] == INF)
                    continue;
                foreach (int other in neighborhoods[current])
                    if (!processed[other]) {
                        int distance =
                            Math.Max(core[current], GridIndex.Distance(points[current], points[other]));
                        if (distance < reach[other]) {
                            reach[other] = distance;
                            predecessor[other] = current;
                            seeds[other] = true;
                        }
                    }
            }
        }
    }
}
