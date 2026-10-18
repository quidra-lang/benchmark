import java.util.*;
import java.math.*;

public class Main {
    static void courses(String[] original, String[][] edges, boolean showCycle) {
        String[] names = original.clone();
        Arrays.sort(names);
        int n = names.length;
        int[] degree = new int[n];
        boolean[][] graph = new boolean[n][n];
        for (String[] edge : edges) {
            int a = Arrays.asList(names).indexOf(edge[0]), b = Arrays.asList(names).indexOf(edge[1]);
            graph[a][b] = true;
            degree[b]++;
        }
        boolean[] taken = new boolean[n];
        List<String> order = new ArrayList<>();
        while (true) {
            int next = -1;
            for (int i = 0; i < n; i++) {
                if (!taken[i] && degree[i] == 0) {
                    next = i;
                    break;
                }
            }
            if (next < 0) break;
            taken[next] = true;
            order.add(names[next]);
            for (int i = 0; i < n; i++) {
                if (graph[next][i]) degree[i]--;
            }
        }
        System.out.println("order: " + String.join(" -> ",order));
        if (showCycle) {
            List<String> remaining = new ArrayList<>();
            for (int i = 0; i < n; i++) {
                if (!taken[i]) remaining.add(names[i]);
            }
            System.out.println("cycle: " + String.join(" ",remaining));
        }
    }
    public static void main(String[] args) {
        courses(new String[]{"physics","algebra","graphics","programming","statistics","calculus","databases","algorithms"}, new String[][]{{"calculus","physics"},
            {"algebra","calculus"},
            {"programming","algorithms"},
            {"algebra","statistics"},
            {"algorithms","databases"},
            {"statistics","databases"},
            {"calculus","graphics"},
            {"algorithms","graphics"},
            {"physics","graphics"}},false);
        courses(new String[]{"music","ecology","art","geology","biology","chemistry"}, new String[][]{{"music","art"},
            {"art","ecology"},
            {"biology","chemistry"},
            {"chemistry","ecology"},
            {"ecology","geology"},
            {"geology","chemistry"}},true);
    }
}
