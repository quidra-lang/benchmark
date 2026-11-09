using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Clustering(int[] labels, bool[] core);
static class Dbscan {
    public static Clustering Cluster(int[][] neighborhoods, int minimum) {
        int[] labels = new int[neighborhoods.Length];
        Array.Fill(labels, -2);
        bool[] core = new bool[labels.Length];
        for (int i = 0; i < core.Length; i++)
            core[i] = neighborhoods[i].Length >= minimum;
        int cluster = 0;
        for (int p = 0; p < labels.Length; p++) {
            if (labels[p] != -2)
                continue;
            if (!core[p]) {
                labels[p] = -1;
                continue;
            }
            labels[p] = cluster;
            Queue<int> queue = new();
            foreach (int q in neighborhoods[p])
                queue.Enqueue(q);
            while (queue.Count != 0) {
                int q = queue.Dequeue();
                if (labels[q] == -1)
                    labels[q] = cluster;
                else if (labels[q] == -2) {
                    labels[q] = cluster;
                    if (core[q])
                        foreach (int neighbor in neighborhoods[q])
                            queue.Enqueue(neighbor);
                }
            }
            cluster++;
        }
        return new Clustering(labels, core);
    }
}
