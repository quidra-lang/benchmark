import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class Ratings {
    record Rating(int user, int item, int rating, long time) {}
    record Item(String title, String genreText, List<String> genres) {}
    static final class Settings {
        Map<String, String[]> values = new HashMap<>();
        int integer(String key) {
            return Integer.parseInt(values.get(key)[0]);
        }
        double number(String key) {
            return decimal(key, 0);
        }
        double decimal(String key, int index) {
            return Double.parseDouble(values.get(key)[index]);
        }
        int[] list(String key) {
            String[] words = values.get(key);
            int[] result = new int[words.length];
            for (int i = 0; i < words.length; i++)
                result[i] = Integer.parseInt(words[i]);
            return result;
        }
    }
    static final class Data {
        List<Rating> training = new ArrayList<>(), test = new ArrayList<>();
        List<Integer> users, items;
        Map<Integer, Integer> userIndex = new HashMap<>(), itemIndex = new HashMap<>();
        Map<Integer, Item> catalog = new HashMap<>();
        Settings settings = new Settings();
        int[][] ratings;
        List<List<Integer>> byUser = new ArrayList<>(), byItem = new ArrayList<>();
        int[] userCounts, itemCounts;
        double[] userMeans, itemMeans;
        double mean;
    }
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static List<Rating> rows(String name, boolean training) throws IOException {
        List<Rating> rows = new ArrayList<>();
        List<String> lines = lines(name);
        for (int i = 1; i < lines.size(); i++) {
            String[] w = lines.get(i).split(",");
            rows.add(new Rating(Integer.parseInt(w[0]), Integer.parseInt(w[1]), Integer.parseInt(w[2]),
                                training ? Long.parseLong(w[3]) : 0));
        }
        return rows;
    }
    static Data read() throws IOException {
        Data data = new Data();
        List<Rating> raw = rows("ratings.csv", true);
        SortedSet<Integer> users = new TreeSet<>(), items = new TreeSet<>();
        for (Rating row : raw) {
            users.add(row.user());
            items.add(row.item());
        }
        data.users = new ArrayList<>(users);
        data.items = new ArrayList<>(items);
        for (int u = 0; u < data.users.size(); u++) {
            data.userIndex.put(data.users.get(u), u);
            data.byUser.add(new ArrayList<>());
        }
        for (int i = 0; i < data.items.size(); i++) {
            data.itemIndex.put(data.items.get(i), i);
            data.byItem.add(new ArrayList<>());
        }
        data.ratings = new int[users.size()][items.size()];
        long sum = 0;
        for (Rating row : raw) {
            int u = data.userIndex.get(row.user()), i = data.itemIndex.get(row.item());
            data.training.add(new Rating(u, i, row.rating(), row.time()));
            data.ratings[u][i] = row.rating();
            sum += row.rating();
        }
        data.mean = (double)sum / raw.size();
        for (Rating row : rows("test.csv", false))
            data.test.add(
                new Rating(data.userIndex.get(row.user()), data.itemIndex.get(row.item()), row.rating(), 0));
        data.userCounts = new int[users.size()];
        data.itemCounts = new int[items.size()];
        data.userMeans = new double[users.size()];
        data.itemMeans = new double[items.size()];
        for (int u = 0; u < users.size(); u++) {
            int total = 0;
            for (int i = 0; i < items.size(); i++)
                if (data.ratings[u][i] > 0) {
                    data.byUser.get(u).add(i);
                    total += data.ratings[u][i];
                }
            data.userCounts[u] = data.byUser.get(u).size();
            data.userMeans[u] = (double)total / data.userCounts[u];
        }
        for (int i = 0; i < items.size(); i++) {
            int total = 0;
            for (int u = 0; u < users.size(); u++)
                if (data.ratings[u][i] > 0) {
                    data.byItem.get(i).add(u);
                    total += data.ratings[u][i];
                }
            data.itemCounts[i] = data.byItem.get(i).size();
            data.itemMeans[i] = (double)total / data.itemCounts[i];
        }
        List<String> catalog = lines("items.csv");
        for (int l = 1; l < catalog.size(); l++) {
            String[] w = catalog.get(l).split(",");
            data.catalog.put(Integer.parseInt(w[0]), new Item(w[1], w[2], Arrays.asList(w[2].split("\\|"))));
        }
        for (String line : lines("params.txt")) {
            String[] w = line.split(" ");
            data.settings.values.put(w[0], Arrays.copyOfRange(w, 1, w.length));
        }
        return data;
    }
}
