import java.util.*;
final class Renderer {
    static String display(List<String> original, int slack, String alignment, boolean last) {
        List<String> pieces = new ArrayList<>();
        for (String piece : original)
            pieces.add(piece.replace('~', ' '));
        String text = String.join(" ", pieces);
        if (slack <= 0)
            return text;
        int gaps = pieces.size() - 1;
        if (alignment.equals("justify") && !last && gaps > 0) {
            StringBuilder output = new StringBuilder(pieces.getFirst());
            for (int i = 0; i < gaps; i++)
                output.append(" ".repeat(slack / gaps + 1 + (i < slack % gaps ? 1 : 0)))
                    .append(pieces.get(i + 1));
            return output.toString();
        }
        return (alignment.equals("right")    ? " ".repeat(slack)
                : alignment.equals("center") ? " ".repeat(slack / 2)
                                             : "") +
            text;
    }
    static String trim(String text) {
        int end = text.length();
        while (end > 0 && text.charAt(end - 1) == ' ')
            end--;
        return text.substring(0, end);
    }
    static List<String> table(List<List<String>> rows, String columns, String caption, String number) {
        int[] widths = new int[columns.length()];
        for (List<String> row : rows)
            for (int i = 0; i < widths.length; i++)
                widths[i] = Math.max(widths[i], row.get(i).length());
        List<String> output = new ArrayList<>();
        if (!caption.isEmpty())
            output.add("Table " + number + ". " + caption);
        for (int r = 0; r < rows.size(); r++) {
            List<String> fields = new ArrayList<>();
            for (int i = 0; i < widths.length; i++) {
                String text = rows.get(r).get(i);
                int missing = widths[i] - text.length(), before = columns.charAt(i) == 'l'   ? 0
                                                                  : columns.charAt(i) == 'r' ? missing
                                                                                             : missing / 2;
                fields.add(" ".repeat(before) + text + " ".repeat(missing - before));
            }
            output.add(trim(String.join(" | ", fields)));
            if (r == 0) {
                List<String> rule = new ArrayList<>();
                for (int width : widths)
                    rule.add("-".repeat(width));
                output.add(String.join("-+-", rule));
            }
        }
        return output;
    }
    static String head(String[] fields, Map<String, String> values, int width, int serial) {
        String[] expanded = fields.clone();
        for (int i = 0; i < 3; i++)
            for (Map.Entry<String, String> value : values.entrySet())
                expanded[i] = expanded[i].replace("{" + value.getKey() + "}", value.getValue());
        if (serial % 2 == 0) {
            String swap = expanded[0];
            expanded[0] = expanded[2];
            expanded[2] = swap;
        }
        char[] line = new char[width];
        Arrays.fill(line, ' ');
        int[] starts = {0, (width - expanded[1].length()) / 2, width - expanded[2].length()};
        for (int i = 0; i < 3; i++)
            for (int j = 0; j < expanded[i].length(); j++)
                line[starts[i] + j] = expanded[i].charAt(j);
        return trim(new String(line));
    }
    static List<String> pages(List<Main.Page> pages) {
        List<String> output = new ArrayList<>();
        for (Main.Page page : pages) {
            output.add("--- page " + page.serial + " ---");
            output.add(page.header);
            output.add("");
            output.addAll(page.body);
            output.add("");
            output.add(page.footer);
        }
        return output;
    }
}
