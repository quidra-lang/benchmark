object DocumentParser {
    val body = setOf("paragraph","item","enum","quote","term");
    val preamble = setOf("page","header","footer");
    val empty = setOf("newpage","verbatim","toc","lot","index","bibliography");
    val names = setOf("width","indent","align","page","header","footer","newpage","hyphenation","bib","title","author","h1","h2","item","enum","quote","term","table","verbatim","toc","lot","index","bibliography")
    data class Source(val line: Int, val text: String)
    data class Warning(val line: Int, val text: String)
    class Bib(val line: Int, val key: String, val author: String, val year: String, val title: String) {
        var base = "";
        var label = "";
        var cited = false
    }
    class Block {
        var kind = "";
        var argument = "";
        var align = "";
        var term = "";
        var columns = "";
        var caption = "";
        var text = "";
        var label: String? = null;
        var number = "";
        var line = 0;
        var width = 0;
        var indent = 0;
        var id = 0;
        var paragraph = 0;
        var pageBreak = false;
        val body = mutableListOf<Source>();
        val inner = mutableListOf<Source>();
        val tokens = mutableListOf<Token>();
        val tableRows = mutableListOf<List<String>>();
        var tableLines = listOf<String>()
    }
    class Document {
        var height = 40;
        var width = 60;
        var header = listOf("","","");
        var footer = listOf("","","");
        val blocks = mutableListOf<Block>();
        val warnings = mutableListOf<Warning>();
        val additions = mutableListOf<String>();
        val bibliography = mutableListOf<Bib>()
    }
    fun valid(name: String, argument: String): Boolean {
        if (name in setOf("width","indent","page")) {
            if (!Regex("[0-9]{1,9}").matches(argument)) return false;
            val value = argument.toInt();
            return when (name) {
                "width" -> value in 20..80;
                "indent" -> value in 0..8;
                else -> value in 10..100
            }
        }
        if (name == "align") return argument in setOf("left","right","center","justify")
        if (name in setOf("header","footer")) return argument.split('|').size == 3
        if (name in empty) return argument.isEmpty()
        if (name == "hyphenation") return Regex("[a-z]+(-[a-z]+)*( [a-z]+(-[a-z]+)*)*").matches(argument)
        if (name == "bib") {
            val space = argument.indexOf(' ');
            if (space < 0 || !Regex("[a-z0-9]+").matches(argument.substring(0,space))) return false;
            val fields = argument.substring(space + 1).split('|');
            return fields.size == 3 && fields[0].isNotEmpty() && Regex("[0-9]{4}").matches(fields[1]) && fields[2].isNotEmpty()
        }
        if (name == "term") {
            val separator = argument.indexOf('|');
            return separator > 0 && separator + 1 < argument.length
        }
        if (name == "table") return Regex("[lrc]+").matches(argument.split(' ')[0])
        return argument.isNotEmpty()
    }
    class State {
        val document = Document();
        var width = 60;
        var indent = 0;
        var align = "left";
        var pending = false
        fun create(kind: String, line: Int, argument: String): Block {
            if (document.blocks.isEmpty()) document.width = width;
            val block = Block();
            block.kind = kind;
            block.line = line;
            block.argument = argument;
            block.width = width;
            block.indent = indent;
            block.align = align;
            block.pageBreak = pending;
            pending = false;
            document.blocks.add(block);
            return block
        }
    }
    fun parse(lines: List<String>): Document {
        val state = State();
        val document = state.document;
        val accepted = mutableSetOf<String>();
        var open: Block? = null;
        var index = 0
        while (index < lines.size) {
            val line = lines[index];
            val number = index + 1;
            index++
            if (line.isEmpty()) {
                open = null;
                continue
            }
            if (!line.startsWith(".")) {
                val block = open ?: state.create("paragraph",number,"").also {
                    open = it
                };
                block.body.add(Source(number,line));
                continue
            }
            open = null;
            val space = line.indexOf(' ');
            val name = line.substring(1,if (space < 0) line.length else space);
            val argument = if (space < 0) "" else line.substring(space + 1)
            val warning = when {
                name !in names -> "unknown directive .$name";
                !valid(name,argument) -> "bad argument for .$name";
                name in preamble && document.blocks.isNotEmpty() -> ".$name ignored after the preamble";
                name in preamble && name in accepted -> "duplicate .$name";
                else -> null
            }
            if (warning != null) {
                document.warnings.add(Warning(number,warning));
                continue
            }
            when {
                name == "width" -> state.width = argument.toInt()
                name == "indent" -> state.indent = argument.toInt()
                name == "align" -> state.align = argument
                name in preamble -> {
                    accepted.add(name);
                    if (name == "page") document.height = argument.toInt() else if (name == "header") document.header = argument.split('|') else document.footer = argument.split('|')
                }
                name == "newpage" -> state.pending = true
                name == "hyphenation" -> document.additions.addAll(argument.split(' '))
                name == "bib" -> {
                    val separator = argument.indexOf(' ');
                    val fields = argument.substring(separator + 1).split('|');
                    document.bibliography.add(Bib(number,argument.substring(0,separator),fields[0],fields[1],fields[2]))
                }
                else -> {
                    val block = state.create(name,number,argument)
                    if (name in setOf("item","enum","quote")) {
                        block.body.add(Source(number,argument));
                        open = block
                    }
                    else if (name == "term") {
                        val separator = argument.indexOf('|');
                        block.term = argument.substring(0,separator);
                        block.body.add(Source(number,argument.substring(separator + 1)));
                        open = block
                    }
                    else if (name in setOf("verbatim","table")) {
                        if (name == "table") {
                            val separator = argument.indexOf(' ');
                            block.columns = if (separator < 0) argument else argument.substring(0,separator);
                            block.caption = if (separator < 0) "" else argument.substring(separator + 1)
                        };
                        while (index < lines.size && lines[index] != ".end") {
                            block.inner.add(Source(index + 1,lines[index]));
                            index++
                        };
                        if (index == lines.size) document.warnings.add(Warning(number,"unterminated $name")) else index++
                    }
                }
            }
        }
        return document
    }
}
