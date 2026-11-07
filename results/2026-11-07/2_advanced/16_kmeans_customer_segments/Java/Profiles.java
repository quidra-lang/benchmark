import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

record NamingCondition(int feature, String comparison, double threshold) {
    boolean holds(double[] center) { return comparison.equals(">") ? center[feature] > threshold : center[feature] < threshold; }
}
record NamingRule(String name, List<NamingCondition> conditions) {
    boolean holds(double[] center) { return conditions.stream().allMatch(condition -> condition.holds(center)); }
}
final class Profiles {
    static List<NamingRule> read(String path) throws IOException {
        List<NamingRule> rules = new ArrayList<>();
        for (String line : Transactions.lines(path)) {
            String[] words = line.split(" ");
            List<NamingCondition> conditions = new ArrayList<>();
            for (int i = 1; i < words.length; i += 3) conditions.add(new NamingCondition(Features.NAMES.indexOf(words[i]), words[i + 1], Double.parseDouble(words[i + 2])));
            rules.add(new NamingRule(words[0], conditions));
        }
        return rules;
    }
    static int ruleNumber(List<NamingRule> rules, double[] center) {
        for (int i = 0; i < rules.size(); i++) if (rules.get(i).holds(center)) return i + 1;
        throw new IllegalStateException();
    }
    static double[] originalScale(double[] center, double[] means, double[] sds) {
        double[] values = new double[center.length];
        for (int f = 0; f < center.length; f++) {
            double value = means[f] + sds[f] * center[f];
            values[f] = Features.SQRT[f] ? value * value : value;
        }
        return values;
    }
}
