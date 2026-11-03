import java.util.*;

final class Transitions {
    record Rule(int number, String[] fields, int fromYear, int toYear, int month, DayRules.DaySpec day, long at, char type, long save, String letter) {
        String name() { return fields[1]; }
    }
    record Instance(Rule rule, long nominal) {}
    record Applied(long time, Rule rule) {}
    record Switch(long time, long save, String letter) {}
    static final class LineRun {
        final List<Rule> preStart = new ArrayList<>();
        final List<Applied> applied = new ArrayList<>();
        long end = DayRules.POS_INFINITY;
    }

    static List<Instance> instances(List<Rule> rules) {
        List<Instance> result = new ArrayList<>();
        for (Rule rule : rules) for (int year = rule.fromYear; year <= rule.toYear; year++) result.add(new Instance(rule, rule.day.value(year, rule.month) * DayRules.DAY + rule.at));
        result.sort(Comparator.comparingLong(Instance::nominal).thenComparingInt(instance -> instance.rule.number));
        return result;
    }

    static long adjustment(char type, long offset, long save) { return type == 'u' ? 0 : type == 's' ? offset : offset + save; }

    static LineRun run(List<Instance> instances, long offset, long start, TzParser.Until until) {
        LineRun result = new LineRun();
        long save = 0;
        for (Instance instance : instances) {
            Rule rule = instance.rule;
            long time = instance.nominal - adjustment(rule.type, offset, save);
            if (until != null && time >= until.value() - adjustment(until.type(), offset, save)) break;
            if (time <= start) result.preStart.add(rule);
            else result.applied.add(new Applied(time, rule));
            save = rule.save;
        }
        if (until != null) result.end = until.value() - adjustment(until.type(), offset, save);
        return result;
    }

    static String abbreviation(String format, long save, String letter) {
        if (format.contains("/")) { String[] parts = format.split("/", -1); return save == 0 ? parts[0] : parts[1]; }
        return format.replace("%s", letter);
    }
}
