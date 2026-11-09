import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class ObjectParser {
    static boolean belongs(String name, String prefix) {
        return name.equals(prefix) || name.startsWith(prefix + ".");
    }
    static boolean nobits(String name) { return belongs(name, ".bss"); }
    static boolean stringSection(String name) { return belongs(name, ".rodata.str"); }
    static List<String> readLines(String path) throws Exception {
        return Files.readAllLines(Path.of("input", path), StandardCharsets.US_ASCII);
    }
    static final class Section extends Layout.Component {
        Obj owner;
        String name, discardReason;
        byte[] contents;
        boolean nobits, string;
        Layout.OutputSection output;
        Main.MergedStrings merged;
        Map<Integer, Integer> mergedPositions = new HashMap<>();
        List<Relocation> relocations = new ArrayList<>();
        Section(Obj owner, String name, int alignment, int size) {
            this.owner = owner;
            this.name = name;
            this.alignment = alignment;
            this.size = size;
            nobits = ObjectParser.nobits(name);
            string = stringSection(name);
            contents = nobits ? new byte[0] : new byte[size];
        }
    }
    static final class Symbol {
        Obj owner;
        String name, binding, kind;
        Section section;
        int offset, alignment = 1;
        long size;
        Symbol(Obj owner, String name, String binding, String kind) {
            this.owner = owner;
            this.name = name;
            this.binding = binding;
            this.kind = kind;
        }
    }
    static final class Relocation {
        Section section;
        int offset;
        Relocator.Type type;
        Symbol symbol;
        long addend, place;
        Long symbolValue, value, field;
        boolean unpaired;
        String status;
        Relocation(Section section, int offset, Relocator.Type type, Symbol symbol, long addend) {
            this.section = section;
            this.offset = offset;
            this.type = type;
            this.symbol = symbol;
            this.addend = addend;
        }
    }
    record Comdat(String signature, List<Section> sections) {}
    static final class Obj {
        String name;
        int order;
        List<Section> sections = new ArrayList<>();
        Map<String, Section> sectionNames = new HashMap<>();
        List<Comdat> comdats = new ArrayList<>();
        List<Symbol> symbols = new ArrayList<>();
        Map<String, Symbol> symbolNames = new HashMap<>();
        Obj(String name) { this.name = name; }
    }
    record Parsed(Obj object, int next) {}
    static Parsed parse(List<String> lines, int index, String name) {
        Obj object = new Obj(name);
        while (!lines.get(index).equals("end")) {
            String[] fields = lines.get(index++).split(" ");
            switch (fields[0]) {
            case "section" -> {
                Section section = new Section(object, fields[1], Integer.parseInt(fields[2]),
                                              Integer.parseInt(fields[3]));
                object.sections.add(section);
                object.sectionNames.put(section.name, section);
                if (!section.nobits) {
                    int position = 0;
                    while (position < section.size) {
                        byte[] data = HexFormat.of().parseHex(lines.get(index++).split(" ")[1]);
                        System.arraycopy(data, 0, section.contents, position, data.length);
                        position += data.length;
                    }
                }
            }
            case "comdat" -> {
                List<Section> sections = new ArrayList<>();
                for (int i = 2; i < fields.length; i++)
                    sections.add(object.sectionNames.get(fields[i]));
                object.comdats.add(new Comdat(fields[1], sections));
            }
            case "symbol" -> {
                String kind = fields[3].equals("undef")    ? "undefined"
                              : fields[3].equals("common") ? "common"
                                                           : "defined";
                Symbol symbol = new Symbol(object, fields[1], fields[2], kind);
                if (kind.equals("common")) {
                    symbol.size = Long.parseLong(fields[4]);
                    symbol.alignment = Integer.parseInt(fields[5]);
                } else if (kind.equals("defined")) {
                    symbol.section = object.sectionNames.get(fields[3]);
                    symbol.offset = Integer.parseInt(fields[4]);
                }
                object.symbols.add(symbol);
                object.symbolNames.put(symbol.name, symbol);
            }
            case "reloc" -> {
                Section section = object.sectionNames.get(fields[1]);
                section.relocations.add(new Relocation(
                    section, Integer.parseInt(fields[2]), Relocator.Type.valueOf(fields[3]),
                    object.symbolNames.get(fields[4]), Long.parseLong(fields[5])));
            }
            }
        }
        return new Parsed(object, index + 1);
    }
    static Obj readObject(String path) throws Exception {
        return parse(readLines(path), 0, path).object();
    }
}
