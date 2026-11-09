using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Ratings {
    public record Rating(int user, int item, int rating, long time) {
    }
    public record Item(string title, string genreText, List<string> genres) {
    }
    public sealed class Settings {
        public Dictionary<string, string[]> values = new();
        public int Integer(string key) {
            return int.Parse(values[key][0]);
        }
        public double Number(string key) {
            return Decimal(key, 0);
        }
        public double Decimal(string key, int index) {
            return double.Parse(values[key][index]);
        }
        public int[] List(string key) {
            string[] words = values[key];
            int[] result = new int[words.Length];
            for (int i = 0; i < words.Length; i++)
                result[i] = int.Parse(words[i]);
            return result;
        }
    }
    public sealed class Data {
        public List<Rating> training = new(), test = new();
        public List<int> users, items;
        public Dictionary<int, int> userIndex = new(), itemIndex = new();
        public Dictionary<int, Item> catalog = new();
        public Settings settings = new Settings();
        public int[][] ratings;
        public List<List<int>> byUser = new(), byItem = new();
        public int[] userCounts, itemCounts;
        public double[] userMeans, itemMeans;
        public double mean;
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static List<Rating> Rows(string name, bool training) {
        List<Rating> rows = new();
        List<string> lines = Lines(name);
        for (int i = 1; i < lines.Count; i++) {
            string[] w = lines[i].Split(',');
            rows.Add(new Rating(int.Parse(w[0]), int.Parse(w[1]), int.Parse(w[2]),
                                training ? long.Parse(w[3]) : 0));
        }
        return rows;
    }
    public static Data Read() {
        Data data = new Data();
        List<Rating> raw = Rows("ratings.csv", true);
        SortedSet<int> users = new(), items = new();
        foreach (Rating row in raw) {
            users.Add(row.user);
            items.Add(row.item);
        }
        data.users = new(users);
        data.items = new(items);
        for (int u = 0; u < data.users.Count; u++) {
            data.userIndex[data.users[u]] = u;
            data.byUser.Add(new());
        }
        for (int i = 0; i < data.items.Count; i++) {
            data.itemIndex[data.items[i]] = i;
            data.byItem.Add(new());
        }
        data.ratings = Enumerable.Range(0, users.Count)
                           .Select(
                               _ => new int[items.Count])
                           .ToArray();
        long sum = 0;
        foreach (Rating row in raw) {
            int u = data.userIndex[row.user], i = data.itemIndex[row.item];
            data.training.Add(new Rating(u, i, row.rating, row.time));
            data.ratings[u][i] = row.rating;
            sum += row.rating;
        }
        data.mean = (double)sum / raw.Count;
        foreach (Rating row in Rows("test.csv", false))
            data.test.Add(new Rating(data.userIndex[row.user], data.itemIndex[row.item], row.rating, 0));
        data.userCounts = new int[users.Count];
        data.itemCounts = new int[items.Count];
        data.userMeans = new double[users.Count];
        data.itemMeans = new double[items.Count];
        for (int u = 0; u < users.Count; u++) {
            int total = 0;
            for (int i = 0; i < items.Count; i++)
                if (data.ratings[u][i] > 0) {
                    data.byUser[u].Add(i);
                    total += data.ratings[u][i];
                }
            data.userCounts[u] = data.byUser[u].Count;
            data.userMeans[u] = (double)total / data.userCounts[u];
        }
        for (int i = 0; i < items.Count; i++) {
            int total = 0;
            for (int u = 0; u < users.Count; u++)
                if (data.ratings[u][i] > 0) {
                    data.byItem[i].Add(u);
                    total += data.ratings[u][i];
                }
            data.itemCounts[i] = data.byItem[i].Count;
            data.itemMeans[i] = (double)total / data.itemCounts[i];
        }
        List<string> catalog = Lines("items.csv");
        for (int l = 1; l < catalog.Count; l++) {
            string[] w = catalog[l].Split(',');
            data.catalog[int.Parse(w[0])] = new Item(w[1], w[2], w[2].Split('|').ToList());
        }
        foreach (string line in Lines("params.txt")) {
            string[] w = line.Split(' ');
            data.settings.values[w[0]] = w[1..w.Length];
        }
        return data;
    }
}
