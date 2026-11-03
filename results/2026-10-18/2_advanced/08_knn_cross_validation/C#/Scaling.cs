sealed class Scaling(double[] centers, double[] scales)
{
    public double[] Centers = centers, Scales = scales;
    public double[] Transform(Row row, List<int> features) => features.Select(feature => Scales[feature] > 0 ? (row.Values[feature] - Centers[feature]) / Scales[feature] : 0).ToArray();
    public static Scaling Compute(List<Row> rows, string method)
    {
        double[] centers = new double[rows[0].Values.Length], scales = new double[rows[0].Values.Length];
        for (int feature = 0; feature < centers.Length; feature++)
        {
            double center = 0, scale = 0;
            if (method == "standard")
            {
                foreach (Row row in rows) center += row.Values[feature]; center /= rows.Count;
                if (rows.Count > 1) { foreach (Row row in rows) scale += (row.Values[feature] - center) * (row.Values[feature] - center); scale = Math.Sqrt(scale / (rows.Count - 1)); }
            }
            else
            {
                double low = rows[0].Values[feature], high = low;
                foreach (Row row in rows) { low = Math.Min(low, row.Values[feature]); high = Math.Max(high, row.Values[feature]); }
                center = low; scale = high - low;
            }
            centers[feature] = center; scales[feature] = scale;
        }
        return new(centers, scales);
    }
}
