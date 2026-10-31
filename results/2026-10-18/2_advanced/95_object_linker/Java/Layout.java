import java.util.*;
final class Layout {
    static abstract class Component {
        long address, size;
        int alignment = 1;
        boolean live;
    }
    static final class OutputSection {
        String name;
        Segment segment;
        boolean nobits;
        List<ObjectParser.Section> sections = new ArrayList<>();
        List<Component> baseComponents = new ArrayList<>(), components = new ArrayList<>();
        long address, size;
        int alignment = 1;
        OutputSection(String name, Segment segment) {
            this.name = name;
            this.segment = segment;
            nobits = ObjectParser.nobits(name);
        }
    }
    static final class Segment {
        String name;
        long base, length, paddr, filesz, memsz, used;
        int fill;
        byte[] image;
        List<OutputSection> outputs = new ArrayList<>();
        Segment(String name, long base, long length, int fill, List<String> outputNames) {
            this.name = name;
            this.base = base;
            this.length = length;
            this.fill = fill;
            paddr = base;
            for (String output : outputNames)
                outputs.add(new OutputSection(output, this));
        }
    }
    static long align(long value, long alignment) {
        return (value + alignment - 1) / alignment * alignment;
    }
    static OutputSection findOutput(String name, List<OutputSection> outputs) {
        for (OutputSection output : outputs)
            if (ObjectParser.belongs(name, output.name))
                return output;
        return null;
    }
    static void assignSegment(Segment segment) {
        long cursor = segment.base;
        segment.filesz = 0;
        for (OutputSection output : segment.outputs) {
            output.alignment = 1;
            for (Component component : output.components)
                output.alignment = Math.max(output.alignment, component.alignment);
            cursor = align(cursor, output.alignment);
            output.address = cursor;
            for (Component component : output.components) {
                cursor = align(cursor, component.alignment);
                component.address = cursor;
                cursor += component.size;
            }
            output.size = cursor - output.address;
            if (!output.nobits)
                segment.filesz = cursor - segment.base;
        }
        segment.memsz = cursor - segment.base;
    }
}
