import java.util.List;

record Scaling(double[] centers, double[] scales) {
    double[] transform(Row row, List<Integer> features) {
        double[] vector = new double[features.size()];
        for (int j = 0; j < features.size(); j++) { int feature = features.get(j); vector[j] = scales[feature] > 0 ? (row.values()[feature] - centers[feature]) / scales[feature] : 0; }
        return vector;
    }
    static Scaling compute(List<Row> rows, String method) {
        double[] centers = new double[rows.getFirst().values().length], scales = new double[centers.length];
        for (int feature = 0; feature < centers.length; feature++) {
            double center = 0, scale = 0;
            if (method.equals("standard")) {
                for (Row row : rows) center += row.values()[feature]; center /= rows.size();
                if (rows.size() > 1) { for (Row row : rows) scale += (row.values()[feature] - center) * (row.values()[feature] - center); scale = Math.sqrt(scale / (rows.size() - 1)); }
            } else {
                double low = rows.getFirst().values()[feature], high = low;
                for (Row row : rows) { low = Math.min(low, row.values()[feature]); high = Math.max(high, row.values()[feature]); }
                center = low; scale = high - low;
            }
            centers[feature] = center; scales[feature] = scale;
        }
        return new Scaling(centers, scales);
    }
}
