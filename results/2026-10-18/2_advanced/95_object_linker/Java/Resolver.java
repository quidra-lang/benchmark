import java.util.*;
final class Resolver {
    static final class Resolution extends Layout.Component {
        String name, kind, definer;
        List<ObjectParser.Symbol> entries, strong = new ArrayList<>(), weak = new ArrayList<>(),
                                           commons = new ArrayList<>(),
                                           references = new ArrayList<>();
        List<String> referrers, strongDefiners = new ArrayList<>(),
                                unresolvedReferrers = new ArrayList<>();
        ObjectParser.Symbol definition;
        Resolution(String name, List<ObjectParser.Symbol> entries, boolean script) {
            this.name = name;
            this.entries = entries;
            for (ObjectParser.Symbol entry : entries) {
                if (entry.kind.equals("defined")) {
                    if (entry.binding.equals("global"))
                        strong.add(entry);
                    else if (entry.binding.equals("weak"))
                        weak.add(entry);
                } else if (entry.kind.equals("common"))
                    commons.add(entry);
                else
                    references.add(entry);
            }
            Set<String> referring = new LinkedHashSet<>();
            for (ObjectParser.Symbol entry : references)
                referring.add(entry.owner.name);
            referrers = new ArrayList<>(referring);
            if (script)
                strongDefiners.add("*script*");
            for (ObjectParser.Symbol entry : strong)
                strongDefiners.add(entry.owner.name);
            if (script) {
                kind = "script";
                definer = "*script*";
            } else if (!strong.isEmpty()) {
                kind = "global";
                definition = strong.getFirst();
                definer = definition.owner.name;
            } else if (!commons.isEmpty()) {
                kind = "common";
                for (ObjectParser.Symbol entry : commons) {
                    size = Math.max(size, entry.size);
                    alignment = Math.max(alignment, entry.alignment);
                }
                for (ObjectParser.Symbol entry : commons)
                    if (entry.size == size) {
                        definer = entry.owner.name;
                        break;
                    }
            } else if (!weak.isEmpty()) {
                kind = "weak";
                definition = weak.getFirst();
                definer = definition.owner.name;
            } else {
                kind = references.stream().anyMatch(entry -> entry.binding.equals("global"))
                           ? "undefined"
                           : "weakundef";
                definer = "-";
            }
        }
    }
    static Map<String, Resolution> resolve(Map<String, List<ObjectParser.Symbol>> entries,
                                           Set<String> scriptNames) {
        Set<String> names = new TreeSet<>(entries.keySet());
        names.addAll(scriptNames);
        Map<String, Resolution> resolutions = new TreeMap<>();
        for (String name : names)
            resolutions.put(name, new Resolution(name, entries.getOrDefault(name, List.of()),
                                                 scriptNames.contains(name)));
        return resolutions;
    }
}
