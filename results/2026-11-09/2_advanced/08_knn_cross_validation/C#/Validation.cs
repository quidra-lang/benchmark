record Model(int K, string Metric, string Weighting, string Scaling)
{
    public string Notation => $"k={K} metric={Metric} weighting={Weighting} scaling={Scaling}";
}
record Prediction(Vote Result, double Estimate, List<Neighbor> Neighbors);
static class Validation
{
    public static List<List<int>> Folds(List<Row> rows, int count)
    {
        List<List<int>> folds = Enumerable.Range(0, count).Select(_ => new List<int>()).ToList();
        List<int> ordered = Enumerable.Range(0, rows.Count).OrderBy(index => rows[index].Label, StringComparer.Ordinal).ThenBy(index => rows[index].Id, StringComparer.Ordinal).ToList();
        for (int j = 0; j < ordered.Count; j++) folds[j % count].Add(ordered[j]);
        foreach (List<int> fold in folds) fold.Sort(); return folds;
    }
    public static List<Row> Without(List<Row> rows, List<int> excluded)
    {
        HashSet<int> skipped = new(excluded); return rows.Where((_, index) => !skipped.Contains(index)).ToList();
    }
    public static List<Row> Selected(List<Row> rows, List<int> indices) => indices.Select(index => rows[index]).ToList();
    public static List<List<Neighbor>> Orders(List<Row> training, List<Row> queries, string method, string metric, List<int> features)
    {
        Scaling scaling = Scaling.Compute(training, method);
        List<(double[], Row)> references = training.Select(row => (scaling.Transform(row, features), row)).ToList();
        return queries.Select(query => Neighbors.Order(scaling.Transform(query, features), references, metric)).ToList();
    }
    public static Prediction FromOrder(List<Neighbor> order, int k, string weighting)
    {
        List<Neighbor> nearest = order.Take(k).ToList(); return new(Neighbors.Vote(nearest, weighting), Neighbors.Estimate(nearest, weighting), nearest);
    }
    public static List<Prediction> Predict(Model model, List<Row> training, List<Row> queries, List<int> features) => Orders(training, queries, model.Scaling, model.Metric, features).Select(order => FromOrder(order, model.K, model.Weighting)).ToList();
    public static double Rmse(List<double> errors) { double total = 0; foreach (double error in errors) total += error * error; return Math.Sqrt(total / errors.Count); }
    public static double Mae(List<double> errors) { double total = 0; foreach (double error in errors) total += Math.Abs(error); return total / errors.Count; }
    public static double RSquared(List<double> errors, List<double> targets)
    {
        double total = 0; foreach (double target in targets) total += target; double mean = total / targets.Count;
        double residual = 0; foreach (double error in errors) residual += error * error;
        double spread = 0; foreach (double target in targets) spread += (target - mean) * (target - mean); return 1 - residual / spread;
    }
}
