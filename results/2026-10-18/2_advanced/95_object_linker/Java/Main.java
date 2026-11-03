import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.regex.*;
import java.io.ByteArrayOutputStream;
public final class Main {
    record Pair(String first, String second) {}
    record Define(String name, String expression) {}
    record Input(String kind, List<String> names) {}
    static final class Script {
        String entry;
        boolean gc;
        List<Layout.Segment> segments = new ArrayList<>();
        List<Pair> loads = new ArrayList<>();
        Set<String> kept = new HashSet<>(), sorted = new HashSet<>(), wrapped = new HashSet<>(),
                    scriptNames = new HashSet<>();
        List<Define> defines = new ArrayList<>();
        Pair checksum;
        List<Input> inputs = new ArrayList<>();
        Map<String, Layout.Segment> segmentNames = new HashMap<>();
        List<Layout.OutputSection> outputs = new ArrayList<>();
        Map<String, Layout.OutputSection> outputNames = new HashMap<>();
        Script(List<String> lines) {
            for (String line : lines) {
                if (line.startsWith("define ")) {
                    int equals = line.indexOf(" = ");
                    String name = line.substring(7, equals);
                    defines.add(new Define(name, line.substring(equals + 3)));
                    scriptNames.add(name);
                    continue;
                }
                List<String> fields = List.of(line.split(" "));
                switch (fields.get(0)) {
                case "entry" -> entry = fields.get(1);
                case "gc" -> gc = fields.get(1).equals("on");
                case "segment" ->
                    segments.add(new Layout.Segment(
                        fields.get(1), Long.parseLong(fields.get(2).substring(2), 16),
                        Long.parseLong(fields.get(3).substring(2), 16),
                        Integer.parseInt(fields.get(4).substring(2), 16),
                        fields.subList(5, fields.size())));
                case "load" -> loads.add(new Pair(fields.get(1), fields.get(2)));
                case "keep" -> kept.add(fields.get(1));
                case "sort" -> sorted.add(fields.get(1));
                case "wrap" -> wrapped.add(fields.get(1));
                case "checksum" -> checksum = new Pair(fields.get(1), fields.get(2));
                default -> inputs.add(new Input(fields.get(0), fields.subList(1, fields.size())));
                }
            }
            for (Layout.Segment segment : segments) {
                segmentNames.put(segment.name, segment);
                for (Layout.OutputSection output : segment.outputs) {
                    outputs.add(output);
                    outputNames.put(output.name, output);
                }
            }
        }
    }
    record BytesKey(byte[] bytes) {
        public boolean equals(Object value) {
            return value instanceof BytesKey other && Arrays.equals(bytes, other.bytes);
        }
        public int hashCode() { return Arrays.hashCode(bytes); }
    }
    static final class MergedStrings extends Layout.Component {
        List<ObjectParser.Section> sections;
        byte[] contents;
        int strings, unique;
        long saved;
        MergedStrings(List<ObjectParser.Section> sections) {
            this.sections = sections;
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            Map<BytesKey, Integer> positions = new HashMap<>();
            long original = 0;
            for (ObjectParser.Section section : sections) {
                section.merged = this;
                original += section.size;
                int start = 0;
                while (start < section.size) {
                    int end = start;
                    while (section.contents[end] != 0)
                        end++;
                    end++;
                    byte[] string = Arrays.copyOfRange(section.contents, start, end);
                    BytesKey key = new BytesKey(string);
                    if (!positions.containsKey(key)) {
                        positions.put(key, bytes.size());
                        bytes.writeBytes(string);
                    }
                    section.mergedPositions.put(start, positions.get(key));
                    strings++;
                    start = end;
                }
            }
            contents = bytes.toByteArray();
            size = contents.length;
            unique = positions.size();
            saved = original - size;
        }
    }
    static final class Veneer extends Layout.Component {
        Layout.OutputSection output;
        String name;
        Veneer(Layout.OutputSection output, String name) {
            this.output = output;
            this.name = name;
            size = 8;
            alignment = 4;
        }
    }
    static final class ScriptExpression {
        List<String> tokens = new ArrayList<>();
        int index;
        Map<String, Layout.OutputSection> outputs;
        Map<String, Long> values;
        ScriptExpression(String text, Map<String, Layout.OutputSection> outputs,
                         Map<String, Long> values) {
            this.outputs = outputs;
            this.values = values;
            Matcher matcher =
                Pattern.compile("0x[0-9a-f]+|[0-9]+|[A-Za-z_.][A-Za-z0-9_.]*|[(),+\\-]")
                    .matcher(text);
            while (matcher.find())
                tokens.add(matcher.group());
        }
        String take() { return tokens.get(index++); }
        long expression() {
            long value = term();
            while (index < tokens.size() && Set.of("+", "-").contains(tokens.get(index))) {
                String operator = take();
                long right = term();
                value = operator.equals("+") ? value + right : value - right;
            }
            return value;
        }
        long term() {
            String token = take();
            if (token.equals("(")) {
                long value = expression();
                take();
                return value;
            }
            if (Character.isDigit(token.charAt(0)))
                return token.startsWith("0x") ? Long.parseLong(token.substring(2), 16)
                                              : Long.parseLong(token);
            if (index == tokens.size() || !tokens.get(index).equals("("))
                return values.get(token);
            take();
            if (token.equals("align")) {
                long value = expression();
                take();
                long alignment = expression();
                take();
                return Layout.align(value, alignment);
            }
            Layout.OutputSection output = outputs.get(take());
            take();
            return switch (token) {
                case "start" -> output.address;
                case "end" -> output.address + output.size;
                case "size" -> output.size;
                default -> output.segment.paddr + output.address - output.segment.base;
            };
        }
    }
    record Extraction(String object, String referrer, String reason) {}
    record ComdatKeeper(String keeper, List<String> discarded) {}
    record VeneerPair(Layout.OutputSection output, String name) {}
    static final class Linker {
        Script script;
        List<ObjectParser.Obj> objects = new ArrayList<>();
        Map<String, List<ObjectParser.Symbol>> entries = new HashMap<>();
        Map<String, List<Archive.Member>> archives = new HashMap<>();
        Map<String, ComdatKeeper> comdats = new LinkedHashMap<>();
        List<Extraction> extractions = new ArrayList<>();
        Map<String, Integer> orphans = new TreeMap<>();
        Map<String, Long> scriptValues = new HashMap<>();
        Map<VeneerPair, Veneer> veneers = new HashMap<>();
        Set<ObjectParser.Relocation> farCalls = new HashSet<>();
        List<ObjectParser.Relocation> applied = new ArrayList<>();
        Map<Relocator.Type, Map<String, Integer>> relocationCounts =
            new EnumMap<>(Relocator.Type.class);
        Map<String, Resolver.Resolution> names;
        List<Resolver.Resolution> commons = new ArrayList<>();
        List<ObjectParser.Section> candidates = new ArrayList<>();
        Linker(Script script) {
            this.script = script;
            for (Relocator.Type type : Relocator.Type.values())
                relocationCounts.put(type, new HashMap<>());
        }
        boolean defined(String name) {
            if (script.scriptNames.contains(name))
                return true;
            for (ObjectParser.Symbol entry : entries.getOrDefault(name, List.of()))
                if (entry.kind.equals("defined") || entry.kind.equals("common"))
                    return true;
            return false;
        }
        boolean undefined(String name) {
            if (defined(name))
                return false;
            if (name.equals(script.entry))
                return true;
            for (ObjectParser.Symbol entry : entries.getOrDefault(name, List.of()))
                if (entry.kind.equals("undefined") && entry.binding.equals("global"))
                    return true;
            return false;
        }
        void loadObject(ObjectParser.Obj object) {
            object.order = objects.size();
            for (ObjectParser.Comdat group : object.comdats) {
                ComdatKeeper keeper = comdats.get(group.signature());
                if (keeper != null) {
                    keeper.discarded().add(object.name);
                    for (ObjectParser.Section section : group.sections())
                        section.discardReason = "comdat";
                } else
                    comdats.put(group.signature(),
                                new ComdatKeeper(object.name, new ArrayList<>()));
            }
            for (ObjectParser.Symbol symbol : object.symbols)
                if (!symbol.binding.equals("local") && symbol.kind.equals("defined") &&
                    "comdat".equals(symbol.section.discardReason)) {
                    symbol.kind = "undefined";
                    symbol.section = null;
                }
            for (ObjectParser.Symbol symbol : object.symbols)
                if (symbol.kind.equals("undefined")) {
                    if (script.wrapped.contains(symbol.name))
                        symbol.name = "__wrap_" + symbol.name;
                    else if (symbol.name.startsWith("__real_") &&
                             script.wrapped.contains(symbol.name.substring(7)))
                        symbol.name = symbol.name.substring(7);
                }
            object.symbolNames.clear();
            for (ObjectParser.Symbol symbol : object.symbols) {
                object.symbolNames.put(symbol.name, symbol);
                if (!symbol.binding.equals("local"))
                    entries.computeIfAbsent(symbol.name, ignored -> new ArrayList<>()).add(symbol);
            }
            objects.add(object);
        }
        void extract(ObjectParser.Obj object, String reason) {
            String referrer = "*entry*";
            for (ObjectParser.Symbol entry : entries.getOrDefault(reason, List.of()))
                if (entry.kind.equals("undefined") && entry.binding.equals("global")) {
                    referrer = entry.owner.name;
                    break;
                }
            extractions.add(new Extraction(object.name, referrer, reason));
            loadObject(object);
        }
        int scanArchive(String name) throws Exception {
            if (!archives.containsKey(name))
                archives.put(name, Archive.read(name));
            return Archive.scan(archives.get(name), this::undefined, this::extract);
        }
        void loadInputs() throws Exception {
            for (Input input : script.inputs)
                if (input.kind().equals("object"))
                    loadObject(ObjectParser.readObject(input.names().getFirst()));
                else if (input.kind().equals("library"))
                    scanArchive(input.names().getFirst());
                else
                    while (true) {
                        int extracted = 0;
                        for (String name : input.names())
                            extracted += scanArchive(name);
                        if (extracted == 0)
                            break;
                    }
            names = Resolver.resolve(entries, script.scriptNames);
            for (Resolver.Resolution resolution : names.values())
                if (resolution.kind.equals("common"))
                    commons.add(resolution);
        }
        void assignOutputs() {
            for (ObjectParser.Obj object : objects)
                for (ObjectParser.Section section : object.sections) {
                    if ("comdat".equals(section.discardReason))
                        continue;
                    section.output = Layout.findOutput(section.name, script.outputs);
                    if (section.output == null) {
                        section.discardReason = "orphan";
                        orphans.merge(section.name, 1, Integer::sum);
                    } else {
                        section.output.sections.add(section);
                        candidates.add(section);
                    }
                }
        }
        Layout.Component target(ObjectParser.Symbol symbol) {
            if (symbol.binding.equals("local"))
                return symbol.section;
            Resolver.Resolution resolution = names.get(symbol.name);
            if (resolution.kind.equals("global") || resolution.kind.equals("weak"))
                return resolution.definition.section;
            if (resolution.kind.equals("common"))
                return resolution;
            return null;
        }
        void collectGarbage() {
            Set<Layout.Component> units = new HashSet<>(candidates);
            units.addAll(commons);
            if (!script.gc)
                for (Layout.Component unit : units)
                    unit.live = true;
            else {
                Deque<Layout.Component> pending = new ArrayDeque<>();
                for (ObjectParser.Section section : candidates)
                    if (script.kept.contains(section.output.name))
                        pending.push(section);
                Resolver.Resolution entry = names.get(script.entry);
                if (entry != null) {
                    if (entry.kind.equals("global") || entry.kind.equals("weak"))
                        pending.push(entry.definition.section);
                    else if (entry.kind.equals("common"))
                        pending.push(entry);
                }
                while (!pending.isEmpty()) {
                    Layout.Component unit = pending.pop();
                    if (!units.contains(unit) || unit.live)
                        continue;
                    unit.live = true;
                    if (unit instanceof ObjectParser.Section section)
                        for (ObjectParser.Relocation relocation : section.relocations) {
                            Layout.Component target = target(relocation.symbol);
                            if (target != null)
                                pending.push(target);
                        }
                }
            }
            for (ObjectParser.Section section : candidates)
                if (!section.live)
                    section.discardReason = "gc";
            for (ObjectParser.Obj object : objects) {
                Set<String> unresolved = new HashSet<>();
                for (ObjectParser.Section section : object.sections)
                    if (section.live)
                        for (ObjectParser.Relocation relocation : section.relocations) {
                            ObjectParser.Symbol symbol = relocation.symbol;
                            if (!symbol.binding.equals("local") &&
                                names.get(symbol.name).kind.equals("undefined"))
                                unresolved.add(symbol.name);
                        }
                for (String name : unresolved)
                    names.get(name).unresolvedReferrers.add(object.name);
            }
        }
        void buildComponents() {
            for (Layout.OutputSection output : script.outputs) {
                List<ObjectParser.Section> sections = new ArrayList<>(), strings =
                                                                             new ArrayList<>();
                for (ObjectParser.Section section : output.sections)
                    if (section.live)
                        sections.add(section);
                if (script.sorted.contains(output.name))
                    sections.sort(
                        Comparator.comparingInt(section
                                                -> section.name.equals(output.name)
                                                       ? 65536
                                                       : Integer.parseInt(section.name.substring(
                                                             output.name.length() + 1))));
                for (ObjectParser.Section section : sections)
                    if (section.string)
                        strings.add(section);
                MergedStrings merged = strings.isEmpty() ? null : new MergedStrings(strings);
                List<Layout.Component> components = new ArrayList<>();
                boolean inserted = false;
                for (ObjectParser.Section section : sections)
                    if (section.string) {
                        if (!inserted) {
                            components.add(merged);
                            inserted = true;
                        }
                    } else
                        components.add(section);
                if (output.name.equals(".bss")) {
                    List<Resolver.Resolution> common = new ArrayList<>();
                    for (Resolver.Resolution resolution : commons)
                        if (resolution.live)
                            common.add(resolution);
                    common.sort(
                        Comparator
                            .<Resolver.Resolution>comparingInt(resolution -> resolution.alignment)
                            .reversed()
                            .thenComparing(resolution -> resolution.name));
                    components.addAll(common);
                }
                output.baseComponents = components;
            }
        }
        long locationAddress(ObjectParser.Section section, int offset) {
            return section.string ? section.merged.address + section.mergedPositions.get(offset)
                                  : section.address + offset;
        }
        long definitionAddress(Resolver.Resolution resolution) {
            return locationAddress(resolution.definition.section, resolution.definition.offset);
        }
        Set<ObjectParser.Relocation> findFarCalls() {
            Set<ObjectParser.Relocation> calls = new HashSet<>();
            for (ObjectParser.Section section : candidates)
                if (section.live)
                    for (ObjectParser.Relocation relocation : section.relocations) {
                        ObjectParser.Symbol symbol = relocation.symbol;
                        if (relocation.type != Relocator.Type.CALL24 ||
                            symbol.binding.equals("local"))
                            continue;
                        Resolver.Resolution resolution = names.get(symbol.name);
                        if (!resolution.kind.equals("global") && !resolution.kind.equals("weak"))
                            continue;
                        long displacement = definitionAddress(resolution) + relocation.addend -
                                            section.address - relocation.offset;
                        if (!Relocator.inRange(Relocator.Type.CALL24, displacement))
                            calls.add(relocation);
                    }
            return calls;
        }
        void performLayout() {
            buildComponents();
            while (true) {
                for (Layout.OutputSection output : script.outputs) {
                    List<Veneer> owned = new ArrayList<>();
                    for (Veneer veneer : veneers.values())
                        if (veneer.output == output)
                            owned.add(veneer);
                    owned.sort(Comparator.comparing(veneer -> veneer.name));
                    output.components = new ArrayList<>(output.baseComponents);
                    output.components.addAll(owned);
                }
                for (Layout.Segment segment : script.segments)
                    Layout.assignSegment(segment);
                Set<ObjectParser.Relocation> calls = findFarCalls();
                Set<VeneerPair> added = new HashSet<>();
                for (ObjectParser.Relocation relocation : calls) {
                    VeneerPair pair =
                        new VeneerPair(relocation.section.output, relocation.symbol.name);
                    if (!veneers.containsKey(pair))
                        added.add(pair);
                }
                if (added.isEmpty()) {
                    farCalls = calls;
                    break;
                }
                for (VeneerPair pair : added)
                    veneers.put(pair, new Veneer(pair.output(), pair.name()));
            }
        }
        void loadAddresses() {
            Map<String, Long> storage = new HashMap<>();
            for (Layout.Segment segment : script.segments)
                storage.put(segment.name, segment.base + segment.memsz);
            for (Pair load : script.loads) {
                Layout.Segment segment = script.segmentNames.get(load.first());
                segment.paddr = Layout.align(storage.get(load.second()), 4);
                storage.put(load.second(), segment.paddr + segment.filesz);
            }
            for (Layout.Segment segment : script.segments)
                segment.used = storage.get(segment.name) - segment.base;
        }
        void evaluateDefines() {
            for (Define define : script.defines)
                scriptValues.put(
                    define.name(),
                    new ScriptExpression(define.expression(), script.outputNames, scriptValues)
                        .expression());
        }
        Long symbolValue(ObjectParser.Symbol symbol) {
            if (symbol.binding.equals("local"))
                return locationAddress(symbol.section, symbol.offset);
            Resolver.Resolution resolution = names.get(symbol.name);
            return switch (resolution.kind) {
                case "global", "weak" -> definitionAddress(resolution);
                case "common" -> resolution.address;
                case "script" -> scriptValues.get(resolution.name);
                case "weakundef" -> 0L;
                default -> null;
            };
        }
        long entryAddress() {
            Resolver.Resolution entry = names.get(script.entry);
            if (entry != null) {
                if (entry.kind.equals("global") || entry.kind.equals("weak"))
                    return definitionAddress(entry);
                if (entry.kind.equals("common"))
                    return entry.address;
            }
            return 0;
        }
        void applyRelocations() {
            long gp = scriptValues.getOrDefault("_gp", 0L);
            for (Layout.OutputSection output : script.outputs)
                for (Layout.Component component : output.components)
                    if (component instanceof ObjectParser.Section section)
                        for (int index = 0; index < section.relocations.size(); index++) {
                            ObjectParser.Relocation relocation = section.relocations.get(index);
                            relocation.place = section.address + relocation.offset;
                            relocation.unpaired = Relocator.unpaired(section.relocations, index);
                            relocation.symbolValue = symbolValue(relocation.symbol);
                            if (relocation.symbolValue == null)
                                relocation.status = "undefined";
                            else {
                                relocation.status = "ok";
                                if (farCalls.contains(relocation)) {
                                    relocation.symbolValue =
                                        veneers.get(new VeneerPair(output, relocation.symbol.name))
                                            .address;
                                    relocation.status = "veneer";
                                }
                                Relocator.Calculation calculated =
                                    Relocator.calculate(relocation.type, relocation.symbolValue,
                                                        relocation.addend, relocation.place, gp);
                                relocation.value = calculated.value();
                                relocation.field = calculated.field();
                                if (!calculated.inRange())
                                    relocation.status = "overflow";
                                writeLittle(section.contents, relocation.offset, relocation.field,
                                            Relocator.width(relocation.type));
                            }
                            relocationCounts.get(relocation.type)
                                .merge(relocation.status, 1, Integer::sum);
                            applied.add(relocation);
                        }
        }
        void buildImages() {
            for (Layout.Segment segment : script.segments) {
                segment.image = new byte[Math.toIntExact(segment.filesz)];
                Arrays.fill(segment.image, (byte)segment.fill);
                for (Layout.OutputSection output : segment.outputs)
                    if (!output.nobits)
                        for (Layout.Component component : output.components) {
                            byte[] contents;
                            if (component instanceof Veneer veneer) {
                                contents = new byte[] {4, (byte)240, 31, (byte)229, 0, 0, 0, 0};
                                writeLittle(contents, 4, definitionAddress(names.get(veneer.name)),
                                            4);
                            } else if (component instanceof ObjectParser.Section section)
                                contents = section.contents;
                            else
                                contents = ((MergedStrings)component).contents;
                            System.arraycopy(contents, 0, segment.image,
                                             Math.toIntExact(component.address - segment.base),
                                             Math.toIntExact(component.size));
                        }
            }
            if (script.checksum != null) {
                Layout.Segment segment = script.segmentNames.get(script.checksum.first());
                int offset = Math.toIntExact(
                    definitionAddress(names.get(script.checksum.second())) - segment.base);
                writeLittle(segment.image, offset, 0, 4);
                long total = 0;
                for (int start = 0; start < segment.image.length; start += 4)
                    for (int j = 0; j < 4 && start + j < segment.image.length; j++)
                        total += (long)(segment.image[start + j] & 255) << (8 * j);
                writeLittle(segment.image, offset, Math.floorMod(-total, 1L << 32), 4);
            }
        }
        List<SymbolRow> symbolRows() {
            List<SymbolRow> rows = new ArrayList<>();
            for (Resolver.Resolution resolution : names.values()) {
                if ((resolution.kind.equals("global") || resolution.kind.equals("weak")) &&
                    resolution.definition.section.live)
                    rows.add(new SymbolRow(definitionAddress(resolution), resolution.name,
                                           resolution.kind, resolution.definer));
                else if (resolution.kind.equals("common") && resolution.live)
                    rows.add(new SymbolRow(resolution.address, resolution.name, "common",
                                           resolution.definer));
                else if (resolution.kind.equals("script"))
                    rows.add(new SymbolRow(scriptValues.get(resolution.name), resolution.name,
                                           "script", "*script*"));
            }
            for (Layout.OutputSection output : script.outputs)
                for (Layout.Component component : output.components)
                    if (component instanceof Veneer veneer)
                        rows.add(new SymbolRow(veneer.address, "__veneer_" + veneer.name, "veneer",
                                               "*linker*"));
            rows.sort(Comparator.comparingLong(SymbolRow::address).thenComparing(SymbolRow::name));
            return rows;
        }
        List<String> diagnostics() {
            List<String> lines = new ArrayList<>();
            for (var orphan : orphans.entrySet())
                lines.add("warning: orphan section " + orphan.getKey() + " discarded from " +
                          orphan.getValue() + " object(s)");
            for (Resolver.Resolution resolution : names.values()) {
                String name = resolution.name;
                if (resolution.strongDefiners.size() >= 2)
                    lines.add("error: multiple definition of " + name + ": " +
                              String.join(" ", resolution.strongDefiners));
                if (!resolution.commons.isEmpty() &&
                    (resolution.kind.equals("global") || resolution.kind.equals("script")))
                    lines.add("warning: common symbol " + name + " overridden by " +
                              resolution.definer);
                Set<CommonShape> shapes = new HashSet<>();
                for (ObjectParser.Symbol common : resolution.commons)
                    shapes.add(new CommonShape(common.size, common.alignment));
                if (resolution.kind.equals("common") && shapes.size() >= 2)
                    lines.add("warning: common symbol " + name + " merged to size " +
                              resolution.size + " align " + resolution.alignment);
            }
            Resolver.Resolution entry = names.get(script.entry);
            if (entry == null || entry.kind.equals("undefined") || entry.kind.equals("weakundef"))
                lines.add("error: entry symbol " + script.entry + " is undefined");
            for (Resolver.Resolution resolution : names.values())
                if (resolution.kind.equals("undefined") &&
                    !resolution.unresolvedReferrers.isEmpty())
                    lines.add("error: undefined symbol " + resolution.name + " referenced by " +
                              String.join(" ", resolution.unresolvedReferrers));
            for (Layout.Segment segment : script.segments)
                if (segment.used > segment.length)
                    lines.add("error: segment " + segment.name + " overflows its length by " +
                              (segment.used - segment.length) + " bytes");
            for (int i = 0; i < script.segments.size(); i++)
                for (int j = i + 1; j < script.segments.size(); j++) {
                    Layout.Segment first = script.segments.get(i), second = script.segments.get(j);
                    if (first.memsz >= 1 && second.memsz >= 1 &&
                        first.base < second.base + second.memsz &&
                        second.base < first.base + first.memsz)
                        lines.add("error: segments " + first.name + " and " + second.name +
                                  " overlap");
                }
            for (ObjectParser.Relocation relocation : applied) {
                String location = relocationLocation(relocation);
                if (relocation.unpaired)
                    lines.add("error: unpaired HI16 at " + location + " against " +
                              relocation.symbol.name);
                if (relocation.status.equals("overflow"))
                    lines.add("error: relocation overflow at " + location + ": " + relocation.type +
                              " value " + relocation.value + " against " + relocation.symbol.name);
            }
            int errors = 0, warnings = 0;
            for (String line : lines) {
                if (line.startsWith("error:"))
                    errors++;
                if (line.startsWith("warning:"))
                    warnings++;
            }
            lines.add("errors " + errors + " warnings " + warnings);
            return lines;
        }
        void link() throws Exception {
            loadInputs();
            assignOutputs();
            collectGarbage();
            performLayout();
            loadAddresses();
            evaluateDefines();
            applyRelocations();
            buildImages();
            Files.createDirectories(Path.of("output"));
            write("image.hex", imageDump(this));
            write("flash.ihex", intelHex(this));
            write("link.map", linkMap(this));
            write("xref.txt", crossReferences(this));
            write("relocations.txt", relocationReport(this));
            write("diagnostics.txt", diagnostics());
        }
    }
    record SymbolRow(long address, String name, String kind, String definer) {}
    record CommonShape(long size, int alignment) {}
    static void writeLittle(byte[] bytes, int offset, long value, int width) {
        for (int i = 0; i < width; i++)
            bytes[offset + i] = (byte)(value >>> (8 * i));
    }
    static String hex(long value, int digits) {
        return String.format(Locale.ROOT, "%0" + digits + "x", value);
    }
    static String relocationLocation(ObjectParser.Relocation relocation) {
        return relocation.section.owner.name + " " + relocation.section.name + "+" +
            relocation.offset;
    }
    static String segmentHeading(Layout.Segment segment) {
        return "segment " + segment.name + " vaddr " + hex(segment.base, 8) + " paddr " +
            hex(segment.paddr, 8) + " filesz " + segment.filesz + " memsz " + segment.memsz;
    }
    static List<String> imageDump(Linker linker) {
        List<String> lines = new ArrayList<>();
        lines.add("entry " + hex(linker.entryAddress(), 8) + " " + linker.script.entry);
        for (Layout.Segment segment : linker.script.segments) {
            lines.add(segmentHeading(segment));
            for (int start = 0; start < segment.image.length; start += 16) {
                StringBuilder line = new StringBuilder(hex(segment.base + start, 8));
                for (int i = start; i < Math.min(start + 16, segment.image.length); i++)
                    line.append(" ").append(hex(segment.image[i] & 255, 2));
                lines.add(line.toString());
            }
        }
        return lines;
    }
    static String hexRecord(int type, int address, byte[] data) {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        bytes.write(data.length);
        bytes.write(address >>> 8);
        bytes.write(address & 255);
        bytes.write(type);
        bytes.writeBytes(data);
        int total = 0;
        for (byte value : bytes.toByteArray())
            total += value & 255;
        bytes.write(Math.floorMod(-total, 256));
        return ":" + HexFormat.of().withUpperCase().formatHex(bytes.toByteArray());
    }
    static List<String> intelHex(Linker linker) {
        List<String> lines = new ArrayList<>();
        long upper = 0;
        List<Layout.Segment> segments = new ArrayList<>(linker.script.segments);
        segments.sort(Comparator.comparingLong(segment -> segment.paddr));
        for (Layout.Segment segment : segments) {
            int start = 0;
            while (start < segment.image.length) {
                long address = segment.paddr + start;
                int count = (int)Math.min(Math.min(16, segment.image.length - start),
                                          65536 - address % 65536);
                if (address / 65536 != upper) {
                    upper = address / 65536;
                    lines.add(hexRecord(4, 0, new byte[] {(byte)(upper >>> 8), (byte)upper}));
                }
                lines.add(hexRecord(0, (int)(address % 65536),
                                    Arrays.copyOfRange(segment.image, start, start + count)));
                start += count;
            }
        }
        long entry = linker.entryAddress();
        lines.add(hexRecord(5, 0,
                            new byte[] {(byte)(entry >>> 24), (byte)(entry >>> 16),
                                        (byte)(entry >>> 8), (byte)entry}));
        lines.add(hexRecord(1, 0, new byte[0]));
        return lines;
    }
    static String componentLine(Layout.Component component) {
        if (component instanceof ObjectParser.Section section)
            return "input " + hex(section.address, 8) + " " + section.size + " " +
                section.alignment + " " + section.owner.name + " " + section.name;
        if (component instanceof MergedStrings merged)
            return "merged " + hex(merged.address, 8) + " " + merged.size + " sections " +
                merged.sections.size() + " strings " + merged.strings + " unique " + merged.unique +
                " saved " + merged.saved;
        if (component instanceof Resolver.Resolution common)
            return "common " + hex(common.address, 8) + " " + common.size + " " + common.alignment +
                " " + common.definer + " " + common.name;
        Veneer veneer = (Veneer)component;
        return "veneer " + hex(veneer.address, 8) + " 8 " + veneer.name;
    }
    static List<String> linkMap(Linker linker) {
        List<String> lines = new ArrayList<>();
        for (Extraction extraction : linker.extractions)
            lines.add("member " + extraction.object() + " " + extraction.referrer() + " " +
                      extraction.reason());
        for (var entry : linker.comdats.entrySet()) {
            ComdatKeeper group = entry.getValue();
            lines.add("comdat " + entry.getKey() + " " + group.keeper() + " " +
                      (group.discarded().isEmpty() ? "-" : String.join(",", group.discarded())));
        }
        for (Layout.Segment segment : linker.script.segments) {
            long usage = 100 * segment.used / segment.length;
            lines.add(segmentHeading(segment) + " used " + segment.used + " length " +
                      segment.length + " " + usage + "%");
            for (Layout.OutputSection output : segment.outputs) {
                lines.add("section " + output.name + " " + hex(output.address, 8) + " " +
                          output.size + " " + output.alignment);
                for (Layout.Component component : output.components)
                    lines.add(componentLine(component));
            }
        }
        for (ObjectParser.Obj object : linker.objects)
            for (ObjectParser.Section section : object.sections)
                if (section.discardReason != null)
                    lines.add("discard " + object.name + " " + section.name + " " + section.size +
                              " " + section.discardReason);
        for (Resolver.Resolution common : linker.commons)
            if (!common.live)
                lines.add("discard " + common.definer + " COMMON(" + common.name + ") " +
                          common.size + " gc");
        for (SymbolRow row : linker.symbolRows())
            lines.add("symbol " + hex(row.address(), 8) + " " + row.name() + " " + row.kind() +
                      " " + row.definer());
        return lines;
    }
    static List<String> crossReferences(Linker linker) {
        List<String> lines = new ArrayList<>();
        for (Resolver.Resolution resolution : linker.names.values()) {
            String status;
            if (resolution.kind.equals("global") || resolution.kind.equals("weak"))
                status = resolution.definition.section.live ? "kept" : "discarded";
            else if (resolution.kind.equals("common"))
                status = resolution.live ? "kept" : "discarded";
            else
                status = resolution.kind.equals("script") ? "kept" : "-";
            lines.add(
                resolution.name + " " + resolution.kind + " " + status + " " + resolution.definer +
                " " +
                (resolution.referrers.isEmpty() ? "-" : String.join(",", resolution.referrers)));
        }
        return lines;
    }
    static List<String> relocationReport(Linker linker) {
        List<String> lines = new ArrayList<>();
        for (ObjectParser.Relocation relocation : linker.applied) {
            String prefix = hex(relocation.place, 8) + " " + relocationLocation(relocation) + " " +
                            relocation.type + " " + relocation.symbol.name + " " +
                            relocation.addend,
                   values = relocation.status.equals("undefined")
                                ? "- - -"
                                : hex(relocation.symbolValue, 8) + " " + relocation.value + " " +
                                      hex(relocation.field, 2 * Relocator.width(relocation.type));
            lines.add(prefix + " " + values + " " + relocation.status);
        }
        for (Relocator.Type type : Relocator.Type.values()) {
            Map<String, Integer> counts = linker.relocationCounts.get(type);
            int total = 0;
            for (int count : counts.values())
                total += count;
            StringBuilder line = new StringBuilder("summary " + type + " total " + total);
            for (String status : List.of("ok", "veneer", "overflow", "undefined"))
                line.append(" ").append(status).append(" ").append(counts.getOrDefault(status, 0));
            lines.add(line.toString());
        }
        return lines;
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", name),
                          lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws Exception {
        new Linker(new Script(ObjectParser.readLines("link.txt"))).link();
    }
}
