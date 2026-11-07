object Renderer {
    fun display(original: List<String>, slack: Int, alignment: String, last: Boolean): String {
        val pieces = original.map {
            it.replace('~',' ')
        };
        val text = pieces.joinToString(" ");
        if (slack <= 0) return text;
        val gaps = pieces.size - 1;
        if (alignment == "justify" && !last && gaps > 0) {
            val output = StringBuilder(pieces.first());
            for (i in 0 until gaps) output.append(" ".repeat(slack / gaps + 1 + if (i < slack % gaps) 1 else 0)).append(pieces[i + 1]);
            return output.toString()
        };
        return (if (alignment == "right") " ".repeat(slack) else if (alignment == "center") " ".repeat(slack / 2) else "") + text
    }
    fun trim(text: String) = text.trimEnd(' ')
    fun table(rows: List<List<String>>, columns: String, caption: String, number: String): List<String> {
        val widths = IntArray(columns.length);
        for (row in rows) for (i in widths.indices) widths[i] = maxOf(widths[i],row[i].length);
        val output = mutableListOf<String>();
        if (caption.isNotEmpty()) output.add("Table $number. $caption");
        for (r in rows.indices) {
            val fields = widths.indices.map {
                i -> val text = rows[r][i];
                val missing = widths[i] - text.length;
                val before = if (columns[i] == 'l') 0 else if (columns[i] == 'r') missing else missing / 2;
                " ".repeat(before) + text + " ".repeat(missing - before)
            };
            output.add(trim(fields.joinToString(" | ")));
            if (r == 0) output.add(widths.joinToString("-+-") {
                "-".repeat(it)
            })
        };
        return output
    }
    fun head(fields: List<String>, values: Map<String,String>, width: Int, serial: Int): String {
        val expanded = fields.toMutableList();
        for (i in 0..2) for ((name,value) in values) expanded[i] = expanded[i].replace("{$name}",value);
        if (serial % 2 == 0) {
            val swap = expanded[0];
            expanded[0] = expanded[2];
            expanded[2] = swap
        };
        val line = CharArray(width) {
            ' '
        };
        val starts = intArrayOf(0,(width - expanded[1].length) / 2,width - expanded[2].length);
        for (i in 0..2) for (j in expanded[i].indices) line[starts[i] + j] = expanded[i][j];
        return trim(String(line))
    }
    fun pages(pages: List<Page>): List<String> {
        val output = mutableListOf<String>();
        for (page in pages) {
            output.add("--- page ${page.serial} ---");
            output.add(page.header);
            output.add("");
            output.addAll(page.body);
            output.add("");
            output.add(page.footer)
        };
        return output
    }
}
