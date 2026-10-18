import java.util.*;
import java.math.*;

public class Main {
    static int find(int[] parent, int v) {
        if (parent[v] != v) parent[v] = find(parent,parent[v]);
        return parent[v];
    }
    public static void main(String[] args) {
        int[][] edges = {{0,1,7},
            {2,0,4},
            {1,2,9},
            {1,3,14},
            {3,2,6},
            {2,4,3},
            {4,3,5},
            {5,3,11},
            {4,6,16},
            {6,5,8},
            {7,5,12},
            {6,7,2},
            {7,4,10}};
        Arrays.sort(edges,Comparator.comparingInt(e -> e[2]));
        int[] parent = new int[8];
        for (int i = 0; i < 8; i++) parent[i] = i;
        int accepted = 0, skipped = 0, total = 0;
        for (int[] edge : edges) {
            int a = find(parent,edge[0]), b = find(parent,edge[1]);
            if (a == b) {
                skipped++;
                continue;
            }
            parent[a] = b;
            accepted++;
            total += edge[2];
            char first = (char)('A' + Math.min(edge[0],edge[1]));
            char second = (char)('A' + Math.max(edge[0],edge[1]));
            System.out.println(first + "-" + second + " " + edge[2]);
            if (accepted == 7) break;
        }
        System.out.println("total weight: " + total);
        System.out.println("skipped: " + skipped);
    }
}
