import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.IntStream;

public class Main {
    static void courses(String[] original, String[][] edges, boolean showCycle) {
        String[] names = Arrays.stream(original).sorted().toArray(String[]::new);
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
            int next = IntStream.range(0, n).filter(i -> !taken[i] && degree[i] == 0).findFirst().orElse(-1);
            if (next < 0) {
                break;
            }
            taken[next] = true;
            order.add(names[next]);
            for (int i = 0; i < n; i++) {
                if (graph[next][i]) {
                    degree[i]--;
                }
            }
        }
        System.out.println("order: " + String.join(" -> ", order));
        if (showCycle) {
            var remaining = IntStream.range(0, n).filter(i -> !taken[i]).mapToObj(i -> names[i]).toList();
            System.out.println("cycle: " + String.join(" ", remaining));
        }
    }

    public static void main(String[] args) {
        String[] names1 = {"physics", "algebra", "graphics", "programming", "statistics", "calculus", "databases",
            "algorithms"};
        String[][] edges1 = {{"calculus", "physics"}, {"algebra", "calculus"}, {"programming", "algorithms"},
            {"algebra", "statistics"}, {"algorithms", "databases"}, {"statistics", "databases"},
            {"calculus", "graphics"}, {"algorithms", "graphics"}, {"physics", "graphics"}};
        String[] names2 = {"music", "ecology", "art", "geology", "biology", "chemistry"};
        String[][] edges2 = {{"music", "art"}, {"art", "ecology"}, {"biology", "chemistry"},
            {"chemistry", "ecology"}, {"ecology", "geology"}, {"geology", "chemistry"}};
        courses(names1, edges1, false);
        courses(names2, edges2, true);
    }
}
