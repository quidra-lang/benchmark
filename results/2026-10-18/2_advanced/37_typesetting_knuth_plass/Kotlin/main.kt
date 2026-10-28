import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
import java.util.Locale
data class Token(val kind: String, val argument: String, val number: Int)
data class Mark(val word: Int, val position: Int, val footnote: Boolean, val number: Int)
data class RawMark(val position: Int, val footnote: Boolean, val number: Int)
data class Expanded(val words: List<String>, val marks: List<Mark>)
data class Break(val sw: Int, val sc: Int, val ew: Int, val ec: Int, val mid: Boolean, val hyphen: Boolean)
class Measure {
    var start = 0;
    var end = 0;
    var slack = 0;
    var last = false;
    var mid = false;
    val pieces = mutableListOf<String>();
    val ranges = mutableListOf<IntArray>()
}
class Metrics(val words: List<String>, val first: Int, val later: Int, dictionary: Hyphenation) {
    val offsets = IntArray(words.size);
    val breaks = mutableListOf(Break(0,0,0,0,false,false))
    init {
        var offset = 0;
        for (i in words.indices) {
            val word = words[i];
            offsets[i] = offset;
            offset += word.length + 1;
            for ((position,append) in dictionary.points(word)) breaks.add(Break(i,position,i,position,true,append));
            breaks.add(Break(i + 1,0,i,word.length,false,false))
        }
    }
    fun end() = breaks.size - 1
    fun slack(start: Int, end: Int): Int {
        val a = breaks[start];
        val b = breaks[end];
        val length = offsets[b.ew] + b.ec - offsets[a.sw] - a.sc + if (b.hyphen) 1 else 0;
        return (if (start == 0) first else later) - length
    }
    fun measure(start: Int, end: Int): Measure {
        val result = Measure();
        result.start = start;
        result.end = end;
        result.slack = slack(start,end);
        result.last = end == this.end();
        result.mid = breaks[end].mid;
        val a = breaks[start];
        val b = breaks[end];
        for (word in a.sw..b.ew) {
            val first = if (word == a.sw) a.sc else 0;
            val last = if (word == b.ew) b.ec else words[word].length;
            result.pieces.add(words[word].substring(first,last));
            result.ranges.add(intArrayOf(word,first,last))
        };
        if (b.hyphen) result.pieces[result.pieces.lastIndex] = result.pieces.last() + "-";
        return result
    }
}
class Line(var text: String) {
    var origin: DocumentParser.Block? = null;
    var first = false;
    val footnotes = mutableListOf<Int>();
    val indexes = mutableListOf<Int>()
}
class Broken {
    var name = "";
    var align = "";
    var body = false;
    var cost = 0;
    val measures = mutableListOf<Measure>();
    val lines = mutableListOf<Line>()
}
class LayoutBlock(val kind: String, val list: Boolean, var forced: Boolean, val lines: List<Line>)
class Page {
    var content = listOf<Line>();
    var notes = listOf<Int>();
    val body = mutableListOf<String>();
    var height = 0;
    var serial = 0;
    var forced = false;
    var blank = false;
    var header = "";
    var footer = "";
    var display = ""
}
class IndexEntry(val name: String) {
    val marks = mutableListOf<Int>();
    val see = sortedSetOf<String>();
    val children = mutableMapOf<String,IndexEntry>()
}
data class Deferred(val kind: String, val block: DocumentParser.Block, val lines: List<Line>)
class Layout {
    var pages = listOf<Page>();
    val labels = mutableMapOf<String,String>();
    val bodies = mutableMapOf<Int,Broken>();
    val broken = mutableListOf<Broken>();
    val warnings = mutableListOf<String>()
}
fun words(text: String) = text.split(' ').filter {
    it.isNotEmpty()
}
fun lines(text: List<String>, origin: DocumentParser.Block): List<Line> = text.mapIndexed {
    i,value -> Line(value).also {
        it.origin = origin;
        it.first = i == 0
    }
}
fun splitLabel(text: String): Pair<String,String?> {
    val position = text.lastIndexOf(" {#");
    return if (text.endsWith('}') && position >= 0) text.substring(0,position) to text.substring(position + 3,text.length - 1) else text to null
}
fun roman(number: Int) = "x".repeat(number / 10) + listOf("","i","ii","iii","iv","v","vi","vii","viii","ix")[number % 10]
class Typesetter(val document: DocumentParser.Document, val params: Map<String,Int>, hyphenation: List<String>) {
    val dictionary = Hyphenation(hyphenation,document.additions,params.getValue("left_min"),params.getValue("right_min"));
    val labels = mutableMapOf<String,DocumentParser.Block>();
    val bibliography = linkedMapOf<String,DocumentParser.Bib>();
    val cited = mutableListOf<DocumentParser.Bib>();
    val bodies = mutableListOf<DocumentParser.Block>();
    val headings = mutableListOf<DocumentParser.Block>();
    val tables = mutableListOf<DocumentParser.Block>();
    val footnotes = mutableListOf<String>();
    val indexMarks = mutableListOf<String>();
    val index = mutableMapOf<String,IndexEntry>()
    init {
        register();
        check();
        bibliographyLabels();
        prepareIndex();
        document.warnings.sortBy {
            it.line
        }
    }
    fun warn(line: Int, text: String) {
        document.warnings.add(DocumentParser.Warning(line,text))
    }
    fun register() {
        var chapter = 0;
        var section = 0;
        var table = 0;
        var previous: DocumentParser.Block? = null
        for (i in document.blocks.indices) {
            val block = document.blocks[i];
            block.id = i;
            val before = previous
            if (block.kind in listOf("h1","h2")) {
                val parts = splitLabel(block.argument);
                block.text = parts.first;
                block.label = parts.second;
                if (block.kind == "h1") {
                    chapter++;
                    section = 0;
                    block.number = chapter.toString();
                    if (i > 0) block.pageBreak = true
                } else {
                    section++;
                    block.number = "$chapter.$section"
                };
                headings.add(block)
            }
            else if (block.kind == "enum") block.number = (if (before != null && before.kind == "enum") before.number.toInt() + 1 else 1).toString()
            else if (block.kind == "table") {
                val parts = splitLabel(block.caption);
                block.caption = parts.first;
                block.label = parts.second;
                if (block.caption.isNotEmpty()) {
                    table++;
                    block.number = table.toString();
                    tables.add(block)
                }
            }
            val label = block.label;
            if (label != null) {
                if (label in labels) {
                    warn(block.line,"duplicate label $label");
                    block.label = null
                } else labels[label] = block
            }
            if (block.kind == "paragraph" && before != null && before.kind in listOf("h1","h2")) block.indent = 0
            if (block.kind in DocumentParser.body) {
                bodies.add(block);
                block.paragraph = bodies.size
            };
            previous = block
        }
        for (entry in document.bibliography) if (entry.key in bibliography) warn(entry.line,"duplicate bibliography key ${entry.key}") else bibliography[entry.key] = entry
    }
    fun command(kind: String, argument: String, line: Int): Token {
        if (kind in listOf("ref","page") && argument !in labels) warn(line,"undefined label $argument");
        if (kind == "cite") for (key in argument.split(',')) {
            val entry = bibliography[key];
            if (entry != null) entry.cited = true else warn(line,"undefined citation $key")
        };
        if (kind == "fn") {
            footnotes.add(argument);
            return Token(kind,"",footnotes.size)
        };
        if (kind == "idx") {
            indexMarks.add(argument);
            return Token(kind,"",indexMarks.size)
        };
        return Token(kind,argument,0)
    }
    fun parseBody(block: DocumentParser.Block, source: DocumentParser.Source) {
        val text = source.text;
        var position = 0;
        while (position < text.length) {
            val opening = text.indexOf('{',position);
            if (opening < 0) {
                block.tokens.add(Token("",text.substring(position),0));
                break
            };
            if (opening > position) block.tokens.add(Token("",text.substring(position,opening),0));
            val closing = text.indexOf('}',opening + 1);
            if (closing < 0) {
                warn(source.line,"unclosed brace");
                block.tokens.add(Token("",text.substring(opening),0));
                break
            };
            val content = text.substring(opening + 1,closing);
            val colon = content.indexOf(':');
            val name = if (colon < 0) content else content.substring(0,colon);
            val argument = if (colon < 0) "" else content.substring(colon + 1);
            if (name in setOf("ref","page","fn","idx","cite") && colon >= 0 && argument.isNotEmpty()) block.tokens.add(command(name,argument,source.line)) else warn(source.line,"bad command {$content}");
            position = closing + 1
        }
    }
    fun check() {
        for (block in document.blocks) {
            if (block.kind == "table") {
                val columns = block.columns.length;
                for (source in block.inner) {
                    val cells = source.text.split('|');
                    if (cells.size != columns) warn(source.line,"table row has ${cells.size} cells, expected $columns");
                    block.tableRows.add(List(columns) {
                        i -> if (i < cells.size) cells[i].trim(' ') else ""
                    })
                };
                block.tableLines = Renderer.table(block.tableRows,block.columns,block.caption,block.number);
                val width = block.tableLines.maxOf {
                    it.length
                };
                if (width > block.width) warn(block.line,"table too wide by ${width - block.width}")
            }
            else if (block.kind == "verbatim") {
                for (source in block.inner) if (source.text.length > block.width) warn(source.line,"verbatim line too long by ${source.text.length - block.width}")
            }
            else if (block.kind in DocumentParser.body) for (i in block.body.indices) {
                if (i > 0) block.tokens.add(Token(""," ",0));
                parseBody(block,block.body[i])
            }
        };
        for (entry in bibliography.values) if (!entry.cited) warn(entry.line,"unused bibliography entry ${entry.key}")
    }
    fun bibliographyLabels() {
        for (entry in bibliography.values) if (entry.cited) {
            val names = entry.author.split(" and ");
            val base = if (names.size == 1) names[0].take(3) else names.take(if (names.size >= 5) 3 else 4).joinToString("") {
                it[0].toString()
            }
            + if (names.size >= 5) "+" else "";
            entry.base = base + entry.year.substring(2);
            cited.add(entry)
        }
        cited.sortWith(compareBy<DocumentParser.Bib> {
            it.base
        }.thenBy {
            it.author
        }.thenBy {
            it.title
        }.thenBy {
            it.key
        });
        var start = 0
        while (start < cited.size) {
            var end = start + 1;
            while (end < cited.size && cited[end].base == cited[start].base) end++;
            for (i in start until end) cited[i].label = cited[i].base + if (end - start == 1) "" else ('a' + i - start).toString();
            start = end
        }
    }
    fun prepareIndex() {
        for (i in indexMarks.indices) {
            val phrase = indexMarks[i];
            val pipe = phrase.indexOf('|');
            val entryPart = if (pipe < 0) phrase else phrase.substring(0,pipe);
            val reference = if (pipe < 0) null else phrase.substring(pipe + 1);
            val bang = entryPart.indexOf('!');
            val parent = if (bang < 0) entryPart else entryPart.substring(0,bang);
            val child = if (bang < 0) null else entryPart.substring(bang + 1);
            var entry = index.getOrPut(parent) {
                IndexEntry(parent)
            };
            if (child != null) entry = entry.children.getOrPut(child) {
                IndexEntry(child)
            };
            if (reference != null) entry.see.add(reference) else entry.marks.add(i + 1)
        }
    }
    fun expand(block: DocumentParser.Block, pages: Map<String,String>): Expanded {
        val text = StringBuilder();
        val marks = mutableListOf<RawMark>()
        for (token in block.tokens) when (token.kind) {
            "" -> text.append(token.argument)
            "ref" -> text.append(labels[token.argument]?.number ?: "??")
            "page" -> text.append(pages[token.argument] ?: "??")
            "fn" -> {
                marks.add(RawMark(text.length,true,token.number));
                text.append('[').append(token.number).append(']')
            }
            "idx" -> marks.add(RawMark(text.length - 1,false,token.number))
            else -> {
                val citations = sortedSetOf<String>();
                var missing = false;
                for (key in token.argument.split(',')) {
                    val entry = bibliography[key];
                    if (entry == null) missing = true else citations.add(entry.label)
                };
                val values = citations.toMutableList();
                if (missing) values.add("?");
                text.append('[').append(values.joinToString(", ")).append(']')
            }
        }
        val words = mutableListOf<String>();
        val starts = mutableListOf<Int>();
        val value = text.toString();
        var position = 0
        while (position < value.length) {
            if (value[position] == ' ') {
                position++;
                continue
            };
            val start = position;
            while (position < value.length && value[position] != ' ') position++;
            starts.add(start);
            words.add(value.substring(start,position))
        }
        val located = marks.map {
            mark -> var word = 0;
            while (word + 1 < starts.size && starts[word + 1] <= mark.position) word++;
            Mark(word,mark.position - starts[word],mark.footnote,mark.number)
        };
        return Expanded(words,located)
    }
    fun breakText(words: List<String>, marks: List<Mark>, first: Int, later: Int, alignment: String, firstPrefix: String, laterPrefix: String, name: String, body: Boolean, optimal: Boolean): Broken {
        val metrics = Metrics(words,first,later,dictionary);
        val result = LineBreaker.split(metrics,optimal,params);
        val broken = Broken();
        broken.name = name;
        broken.align = alignment;
        broken.body = body;
        broken.cost = result.cost;
        var start = 0;
        for (end in result.breaks) {
            val measure = metrics.measure(start,end);
            val line = Line((if (start == 0) firstPrefix else laterPrefix) + Renderer.display(measure.pieces,measure.slack,alignment,measure.last));
            for (mark in marks) for (range in measure.ranges) if (range[0] == mark.word && range[1] <= mark.position && mark.position < range[2]) {
                if (mark.footnote) line.footnotes.add(mark.number) else line.indexes.add(mark.number)
            };
            broken.measures.add(measure);
            broken.lines.add(line);
            start = end
        };
        return broken
    }
    fun pageList(pages: Set<Int>): String {
        val ordered = pages.sorted();
        val parts = mutableListOf<String>();
        var start = 0;
        while (start < ordered.size) {
            var end = start;
            while (end + 1 < ordered.size && ordered[end + 1] == ordered[end] + 1) end++;
            if (end - start + 1 >= 3) parts.add("${ordered[start]}-${ordered[end]}") else for (i in start..end) parts.add(ordered[i].toString());
            start = end + 1
        };
        return parts.joinToString(", ")
    }
    fun indexLine(entry: IndexEntry, child: Boolean, markPages: IntArray): String {
        val pages = entry.marks.map {
            markPages[it]
        }.toSet();
        var line = (if (child) "  " else "") + entry.name;
        if (pages.isNotEmpty()) line += ", " + pageList(pages);
        if (entry.see.isNotEmpty()) line += ", see " + entry.see.joinToString(", ");
        return line
    }
    fun sortedNames(names: Set<String>) = names.sortedWith(compareBy<String> {
        it.lowercase(Locale.ROOT)
    }.thenBy {
        it
    })
    fun indexLines(markPages: IntArray): List<String> {
        val result = mutableListOf<String>();
        var previous: String? = null;
        for (name in sortedNames(index.keys)) {
            val entry = index.getValue(name);
            val first = name[0];
            val group = if (Hyphenation.letter(first)) first.uppercaseChar().toString() else "Symbols";
            if (group != previous) {
                result.add(group);
                previous = group
            };
            result.add(indexLine(entry,false,markPages));
            for (child in sortedNames(entry.children.keys)) result.add(indexLine(entry.children.getValue(child),true,markPages))
        };
        return result
    }
    fun entries(kind: String, width: Int, blockPages: IntArray?, pages: List<Page>?): List<String> {
        val result = mutableListOf<String>();
        for (block in if (kind == "toc") headings else tables) {
            val left = if (kind == "toc") (if (block.kind == "h2") "  " else "") + block.number + " " + block.text else "Table ${block.number}. ${block.caption}";
            val number = if (blockPages == null) "??" else pages!![blockPages[block.id] - 1].display;
            result.add(left + " " + ".".repeat(width - left.length - number.length - 2) + " " + number)
        };
        return result
    }
    fun once(optimal: Boolean, pageValues: Map<String,String>): Layout {
        val layout = Layout();
        val blocks = mutableListOf<LayoutBlock>();
        val deferred = mutableListOf<Deferred>();
        val footnoteLines = mutableMapOf<Int,List<Line>>();
        val footnoteBroken = mutableListOf<Broken>()
        for (i in footnotes.indices) {
            val prefix = "[${i + 1}] ";
            val broken = breakText(words(footnotes[i]),emptyList(),document.width - prefix.length,document.width - prefix.length,"left",prefix," ".repeat(prefix.length),"footnote ${i + 1}",false,optimal);
            footnoteLines[i + 1] = broken.lines;
            footnoteBroken.add(broken)
        }
        val referenceWidth = (cited.maxOfOrNull {
            it.label.length
        }
        ?: 0) + 3
        for (block in document.blocks) {
            val start = blocks.size;
            val kind = block.kind
            if (kind in DocumentParser.body) {
                val expanded = expand(block,pageValues);
                var first = block.width;
                var later = block.width;
                var firstPrefix = "";
                var laterPrefix = ""
                when (kind) {
                    "paragraph" -> {
                        first -= block.indent;
                        firstPrefix = " ".repeat(block.indent)
                    }
                    "item" -> {
                        first -= 2;
                        later = first;
                        firstPrefix = "- ";
                        laterPrefix = "  "
                    }
                    "enum" -> {
                        first -= 4;
                        later = first;
                        firstPrefix = block.number.padStart(2) + ". ";
                        laterPrefix = "    "
                    }
                    "quote" -> {
                        first -= 8;
                        later = first;
                        firstPrefix = "    ";
                        laterPrefix = firstPrefix
                    }
                    else -> {
                        first -= 12;
                        later = first;
                        firstPrefix = if (block.term.length <= 10) block.term.padEnd(12) else "            ";
                        laterPrefix = "            "
                    }
                }
                val broken = breakText(expanded.words,expanded.marks,first,later,block.align,firstPrefix,laterPrefix,"paragraph ${block.paragraph}",true,optimal);
                layout.bodies[block.paragraph] = broken;
                layout.broken.add(broken);
                val body = mutableListOf<Line>();
                if (kind == "term" && block.term.length >= 11) body.add(Line(block.term));
                body.addAll(broken.lines);
                for (i in body.indices) {
                    body[i].origin = block;
                    body[i].first = i == 0
                };
                blocks.add(LayoutBlock("flow",kind in setOf("item","enum","term"),false,body))
            } else if (kind in listOf("title","author")) {
                val text = if (kind == "title") block.argument.uppercase(Locale.ROOT) else block.argument;
                blocks.add(LayoutBlock("heading",false,false,lines(listOf(" ".repeat((block.width - text.length) / 2) + text),block)))
            }
            else if (kind in listOf("h1","h2")) {
                val text = block.number + " " + if (kind == "h1") block.text.uppercase(Locale.ROOT) else block.text;
                blocks.add(LayoutBlock("heading",false,false,lines(listOf(text,(if (kind == "h1") "=" else "-").repeat(text.length)),block)))
            }
            else if (kind == "table") blocks.add(LayoutBlock("solid",false,false,lines(block.tableLines,block)))
            else if (kind == "verbatim") blocks.add(LayoutBlock("flow",false,false,lines(block.inner.map {
                it.text
            },block)))
            else {
                val title = when (kind) {
                    "toc" -> "CONTENTS";
                    "lot" -> "TABLES";
                    "index" -> "INDEX";
                    else -> "REFERENCES"
                };
                blocks.add(LayoutBlock("heading",false,false,lines(listOf(title,"=".repeat(title.length)),block)))
                if (kind == "bibliography") for (entry in cited) {
                    val prefix = "[${entry.label}]".padEnd(referenceWidth);
                    val broken = breakText(words("${entry.author}. ${entry.year}. ${entry.title}"),emptyList(),block.width - referenceWidth,block.width - referenceWidth,"left",prefix," ".repeat(referenceWidth),"reference ${entry.label}",false,optimal);
                    layout.broken.add(broken);
                    for (line in broken.lines) line.origin = block;
                    blocks.add(LayoutBlock("flow",true,false,broken.lines))
                }
                else {
                    val text = if (kind == "index") indexLines(IntArray(indexMarks.size + 1)) else entries(kind,block.width,null,null);
                    val entryLines = lines(text,block);
                    blocks.add(LayoutBlock("flow",false,false,entryLines));
                    deferred.add(Deferred(kind,block,entryLines))
                }
            }
            if (blocks.size > start) blocks[start].forced = block.pageBreak
        }
        layout.broken.addAll(footnoteBroken);
        val raw = PageBuilder.build(blocks,footnoteLines,document.height,params.getValue("orphan_lines"),params.getValue("widow_lines"));
        val pages = mutableListOf<Page>()
        for (page in raw) {
            val first = page.content.firstOrNull();
            val chapter = first != null && first.first && first.origin?.kind == "h1";
            if (chapter && (pages.size + 1) % 2 == 0) {
                val blank = Page();
                blank.blank = true;
                pages.add(blank)
            };
            pages.add(page)
        }
        layout.pages = pages;
        var front = 0;
        var foundChapter = false;
        val blockPages = IntArray(document.blocks.size);
        val markPages = IntArray(indexMarks.size + 1)
        for (i in pages.indices) {
            val page = pages[i];
            page.serial = i + 1;
            for (line in page.content) {
                val origin = line.origin;
                if (line.first && origin != null) {
                    if (blockPages[origin.id] == 0) blockPages[origin.id] = page.serial;
                    if (!foundChapter && origin.kind == "h1") {
                        front = page.serial - 1;
                        foundChapter = true
                    }
                }
            }
        }
        for (page in pages) {
            page.display = if (page.serial <= front) roman(page.serial) else (page.serial - front).toString();
            for (line in page.content) for (mark in line.indexes) markPages[mark] = page.serial - front
        }
        for ((label,block) in labels) layout.labels[label] = pages[blockPages[block.id] - 1].display
        for (item in deferred) {
            val text = if (item.kind == "index") indexLines(markPages) else entries(item.kind,item.block.width,blockPages,pages);
            for (i in text.indices) item.lines[i].text = text[i]
        }
        var chapter = "";
        var section = "";
        var heading = 0
        for (page in pages) {
            if (page.blank) {
                repeat(document.height) {
                    page.body.add("")
                };
                continue
            }
            while (heading < headings.size && blockPages[headings[heading].id] <= page.serial) {
                val block = headings[heading++];
                if (block.kind == "h1") {
                    chapter = block.number + " " + block.text;
                    section = ""
                } else section = block.number + " " + block.text
            }
            val values = mapOf("page" to page.display,"pages" to (pages.size - front).toString(),"chapter" to chapter,"section" to section);
            val first = page.content.firstOrNull();
            val chapterPage = first != null && first.first && first.origin?.kind == "h1";
            page.header = if (chapterPage) "" else Renderer.head(document.header,values,document.width,page.serial);
            page.footer = Renderer.head(document.footer,values,document.width,page.serial)
            page.body.addAll(page.content.map {
                it.text
            });
            while (page.body.size < document.height - (if (page.notes.isEmpty()) 0 else 1) - footnoteHeight(page.notes,footnoteLines)) page.body.add("");
            if (page.notes.isNotEmpty()) {
                page.body.add("----------");
                for (number in page.notes) page.body.addAll(footnoteLines.getValue(number).map {
                    it.text
                })
            }
        }
        return layout
    }
    fun footnoteHeight(numbers: List<Int>, lines: Map<Int,List<Line>>) = numbers.sumOf {
        lines.getValue(it).size
    }
    fun layout(optimal: Boolean): Layout {
        var values: Map<String,String> = labels.keys.associateWith { "??" }
        var current = once(optimal,values)
        while (current.labels != values) {
            values = current.labels
            current = once(optimal,values)
        }
        val result = current
        val prefix = if (optimal) "kp: " else "greedy: ";
        var hyphenated = 0
        for (broken in result.broken) for (i in broken.measures.indices) {
            val line = broken.measures[i];
            if (broken.body && line.mid) hyphenated++;
            if (line.slack < 0) result.warnings.add("$prefix${broken.name} line ${i + 1}: overfull by ${-line.slack}") else if (broken.body && broken.align == "justify" && !line.last && line.slack >= params.getValue("underfull_slack")) result.warnings.add("$prefix${broken.name} line ${i + 1}: underfull, slack ${line.slack}")
        }
        for (page in result.pages) if (!page.blank && !page.forced && document.height - page.height >= params.getValue("underfull_page")) result.warnings.add("${prefix}page ${page.serial}: underfull, ${document.height - page.height} empty lines");
        result.warnings.add("$prefix${result.pages.size} pages, $hyphenated hyphenated lines");
        return result
    }
}
fun write(name: String, lines: List<String>) {
    Files.writeString(Path.of("output",name),if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n",StandardCharsets.US_ASCII)
}
fun main() {
    val params = Files.readAllLines(Path.of("input/params.txt"),StandardCharsets.US_ASCII).associate {
        val parts = it.split(' ');
        parts[0] to parts[1].toInt()
    };
    val document = DocumentParser.parse(Files.readAllLines(Path.of("input/document.txt"),StandardCharsets.US_ASCII));
    val typesetter = Typesetter(document,params,Files.readAllLines(Path.of("input/hyphenation.txt"),StandardCharsets.US_ASCII));
    val kp = typesetter.layout(true);
    val greedy = typesetter.layout(false);
    val stats = mutableListOf("paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy");
    val totals = IntArray(4)
    for (block in typesetter.bodies) {
        val a = kp.bodies.getValue(block.paragraph);
        val b = greedy.bodies.getValue(block.paragraph);
        val values = intArrayOf(a.measures.size,a.cost,b.measures.size,b.cost);
        for (i in 0..3) totals[i] += values[i];
        stats.add(block.paragraph.toString() + "," + values.joinToString(","))
    };
    stats.add("total," + totals.joinToString(","));
    val log = document.warnings.map {
        "line ${it.line}: ${it.text}"
    }.toMutableList();
    log.addAll(kp.warnings);
    log.addAll(greedy.warnings);
    Files.createDirectories(Path.of("output"));
    write("pages.txt",Renderer.pages(kp.pages));
    write("greedy_pages.txt",Renderer.pages(greedy.pages));
    write("stats.csv",stats);
    write("log.txt",log)
}
