import java.nio.file.*;
import java.util.*;
final class SequenceIo {
    record Reference(String name, String bases, int masked) {}
    record Read(String name, String bases, String quality) {}
    record Input(List<Reference> references, List<Read> reads, Map<String, int[]> parameters) {}
    static String reverseComplement(String sequence) {
        StringBuilder result = new StringBuilder();
        for (int i = sequence.length() - 1; i >= 0; i--)
            result.append("TGCAN".charAt("ACGTN".indexOf(sequence.charAt(i))));
        return result.toString();
    }
    static Input read() throws Exception {
        List<Reference> references = new ArrayList<>();
        String name = null;
        StringBuilder bases = new StringBuilder();
        int masked = 0;
        for (String line : Files.readAllLines(Path.of("input", "reference.fasta")))
            if (line.startsWith(">")) {
                if (name != null)
                    references.add(new Reference(name, bases.toString(), masked));
                name = line.substring(1).split(" ", 2)[0];
                bases.setLength(0);
                masked = 0;
            } else {
                for (char base : line.toCharArray())
                    if (base >= 'a' && base <= 'z')
                        masked++;
                bases.append(line.toUpperCase(Locale.ROOT));
            }
        if (name != null)
            references.add(new Reference(name, bases.toString(), masked));
        List<String> lines = Files.readAllLines(Path.of("input", "reads.fastq"));
        List<Read> reads = new ArrayList<>();
        for (int i = 0; i < lines.size(); i += 4)
            reads.add(new Read(lines.get(i).substring(1), lines.get(i + 1), lines.get(i + 3)));
        Map<String, int[]> parameters = new HashMap<>();
        for (String line : Files.readAllLines(Path.of("input", "params.txt"))) {
            String[] w = line.split(" ");
            int[] values = new int[w.length - 1];
            for (int i = 1; i < w.length; i++)
                values[i - 1] = Integer.parseInt(w[i]);
            parameters.put(w[0], values);
        }
        return new Input(references, reads, parameters);
    }
}
