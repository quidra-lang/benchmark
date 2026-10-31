import java.io.File
import java.math.BigInteger

object Main {
    lateinit var parsed: GrammarParser.Grammar
    lateinit var cleaned: GrammarParser.Grammar
    lateinit var eliminated: GrammarParser.Grammar
    lateinit var factored: GrammarParser.Grammar
    lateinit var grammar: GrammarParser.Grammar
    val diagnostics=mutableListOf<String>();
    var eliminationLog=emptyList<String>();
    var factorLog=emptyList<String>();
    val unreachableLog=mutableListOf<String>();
    lateinit var sets: FirstFollow.Sets;
    lateinit var table: Table.Result;
    var beforeConflicts=0
    data class Metric(val length: BigInteger,val height: Int): Comparable<Metric> {
        override fun compareTo(other: Metric): Int {
            val c=length.compareTo(other.length);
            return if(c!=0)c else height.compareTo(other.height)
        }
    }
    val lengths=mutableMapOf<String,Metric>();
    val costs=mutableMapOf<String,Metric>();
    val words=mutableMapOf<String,List<String>>();
    val leftContext=mutableMapOf<String,List<String>>();
    val rightContext=mutableMapOf<String,List<String>>()
    fun list(heading: String,values: Collection<*>)=heading+values.joinToString("") {
        " $it"
    }
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun write(name: String,lines: List<String>) {
        File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
    fun reachable(g: GrammarParser.Grammar): Set<String> {
        val seen=mutableSetOf(g.start);
        val queue=ArrayDeque<String>();
        queue.addLast(g.start);
        while(queue.isNotEmpty()) {
            val lhs=queue.removeFirst();
            for(rhs in g.rules.getValue(lhs))for(symbol in rhs)if(GrammarParser.nonterminal(symbol)&&seen.add(symbol))queue.addLast(symbol)
        };
        return seen
    }
    fun filterAlternatives(g: GrammarParser.Grammar,removed: Set<String>,reason: String) {
        for(lhs in g.order) {
            val keep=mutableListOf<List<String>>();
            for(rhs in g.rules.getValue(lhs)) {
                val symbol=rhs.firstOrNull {
                    it in removed
                };
                if(symbol==null)keep.add(rhs) else diagnostics+="removed ${GrammarParser.production(lhs,rhs)} ($reason $symbol)"
            };
            g.rules[lhs]=keep
        }
    }
    fun remove(g: GrammarParser.Grammar,removed: Set<String>) {
        g.order.removeAll(removed);
        for(symbol in removed)g.rules.remove(symbol)
    }
    fun clean(): GrammarParser.Grammar {
        val g=GrammarParser.copy(parsed);
        if(parsed.hasDeclaration)for(word in FirstFollow.terminalOrder(parsed.words.keys))if(word !in parsed.declared)diagnostics+="undeclared terminal $word at line ${parsed.words.getValue(word)}";
        val undefined=g.rules.values.flatten().flatten().filter {
            GrammarParser.nonterminal(it)&&it !in g.rules
        }.toSet();
        for(symbol in undefined.sortedBy {
            it.substring(1,it.length-1)
        })diagnostics+="undefined nonterminal $symbol";
        filterAlternatives(g,undefined,"undefined");
        val productive=mutableSetOf<String>();
        var changed: Boolean;
        do {
            changed=false;
            for(lhs in g.order)if(lhs !in productive)for(rhs in g.rules.getValue(lhs))if(rhs.all {
                !GrammarParser.nonterminal(it)||it in productive
            }) {
                productive+=lhs;
                changed=true;
                break
            }
        }
        while(changed);
        var removed=g.order.filter {
            it !in productive
        }.toSet();
        for(lhs in g.order)if(lhs in removed)diagnostics+="unproductive nonterminal $lhs";
        remove(g,removed);
        filterAlternatives(g,removed,"unproductive");
        val reachable=reachable(g);
        removed=g.order.filter {
            it !in reachable
        }.toSet();
        for(lhs in g.order)if(lhs in removed)diagnostics+="unreachable nonterminal $lhs";
        remove(g,removed);
        return g
    }
    fun leftRecursion() {
        for(origin in cleaned.order) {
            val queue=ArrayDeque<String>();
            val parent=mutableMapOf<String,String>();
            val seen=mutableSetOf(origin);
            queue.addLast(origin);
            var last: String?=null;
            while(queue.isNotEmpty()&&last==null) {
                val current=queue.removeFirst();
                for(rhs in cleaned.rules.getValue(current)) {
                    if(rhs.isEmpty())continue;
                    val first=rhs[0];
                    if(first==origin) {
                        last=current;
                        break
                    };
                    if(GrammarParser.nonterminal(first)&&seen.add(first)) {
                        parent[first]=current;
                        queue.addLast(first)
                    }
                }
            };
            if(last!=null) {
                val path=mutableListOf<String>();
                var current=last;
                while(current!=origin) {
                    path+=current!!;
                    current=parent.getValue(current)
                };
                path.reverse();
                path.add(0,origin);
                path+=origin;
                diagnostics+="left recursion: ${path.joinToString(" -> ")}"
            }
        }
    }
    fun prepare() {
        diagnostics.addAll(parsed.diagnostics);
        cleaned=clean();
        leftRecursion();
        beforeConflicts=Table.build(cleaned,FirstFollow.analyze(cleaned)).conflicts.size;
        val elimination=Transform.eliminate(cleaned);
        eliminated=elimination.grammar;
        eliminationLog=elimination.log;
        val factoring=Transform.factor(eliminated);
        factored=factoring.grammar;
        factorLog=factoring.log;
        grammar=GrammarParser.copy(factored);
        val reachable=reachable(grammar);
        val removed=grammar.order.filter {
            it !in reachable
        }.toSet();
        for(lhs in grammar.order)if(lhs in removed) {
            unreachableLog+="remove unreachable $lhs";
            diagnostics+="unreachable after transformation $lhs"
        };
        remove(grammar,removed);
        sets=FirstFollow.analyze(grammar);
        table=Table.build(grammar,sets);
        if(parsed.hasDeclaration)for(t in FirstFollow.terminalOrder(parsed.declared-sets.terminals.toSet()))diagnostics+="unused token $t";
        shortest();
        contexts()
    }
    fun metric(rhs: List<String>): Metric? {
        var length=BigInteger.ZERO;
        var height=1;
        for(symbol in rhs)if(GrammarParser.nonterminal(symbol)) {
            val child=lengths[symbol]?:return null;
            length+=child.length;
            height=maxOf(height,child.height+1)
        } else length+=BigInteger.ONE;
        return Metric(length,height)
    }
    fun shortest() {
        var changed: Boolean;
        do {
            changed=false;
            for(lhs in grammar.order)for(rhs in grammar.rules.getValue(lhs)) {
                val candidate=metric(rhs);
                val old=lengths[lhs];
                if(candidate!=null&&(old==null||candidate<old)) {
                    lengths[lhs]=candidate;
                    changed=true
                }
            }
        }
        while(changed);
        for(lhs in grammar.order)word(lhs)
    }
    fun word(lhs: String): List<String> {
        words[lhs]?.let {
            return it
        };
        for(rhs in grammar.rules.getValue(lhs))if(metric(rhs)==lengths[lhs]) {
            val result=sentence(rhs);
            words[lhs]=result;
            return result
        };
        error("shortest")
    }
    fun sentence(rhs: List<String>): List<String> {
        val result=mutableListOf<String>();
        for(symbol in rhs)if(GrammarParser.nonterminal(symbol))result.addAll(word(symbol)) else result+=symbol;
        return result
    }
    fun contextMetric(p: Table.Production,occurrence: Int): Metric? {
        val parent=costs[p.lhs]?:return null;
        var length=parent.length;
        for(i in p.rhs.indices)if(i!=occurrence) {
            val symbol=p.rhs[i];
            length+=if(GrammarParser.nonterminal(symbol))lengths.getValue(symbol).length else BigInteger.ONE
        };
        return Metric(length,parent.height+1)
    }
    fun contexts() {
        costs[grammar.start]=Metric(BigInteger.ZERO,0);
        var changed: Boolean;
        do {
            changed=false;
            for(p in table.productions)for(i in p.rhs.indices) {
                val symbol=p.rhs[i];
                if(!GrammarParser.nonterminal(symbol)||symbol==grammar.start)continue;
                val candidate=contextMetric(p,i);
                val old=costs[symbol];
                if(candidate!=null&&(old==null||candidate<old)) {
                    costs[symbol]=candidate;
                    changed=true
                }
            }
        }
        while(changed);
        leftContext[grammar.start]=emptyList();
        rightContext[grammar.start]=emptyList();
        for(lhs in grammar.order)context(lhs)
    }
    fun context(lhs: String) {
        if(lhs in leftContext)return;
        for(p in table.productions)for(i in p.rhs.indices)if(p.rhs[i]==lhs&&contextMetric(p,i)!=null&&contextMetric(p,i)==costs[lhs]) {
            context(p.lhs);
            leftContext[lhs]=leftContext.getValue(p.lhs)+sentence(p.rhs.take(i));
            rightContext[lhs]=sentence(p.rhs.drop(i+1))+rightContext.getValue(p.lhs);
            return
        }
    }
    fun example(p: Table.Production)=leftContext.getValue(p.lhs)+sentence(p.rhs)+rightContext.getValue(p.lhs)
    fun summary(g: GrammarParser.Grammar): String {
        val rows=g.order.flatMap {
            g.rules.getValue(it)
        };
        return "start=${g.start} nonterminals=${g.order.size} terminals=${FirstFollow.terminals(g).size} productions=${rows.size} empty=${rows.count{it.isEmpty()}} unit=${rows.count{it.size==1&&GrammarParser.nonterminal(it[0])}}"
    }
    fun listing(g: GrammarParser.Grammar,numbered: Boolean): List<String> {
        val result=mutableListOf<String>();
        val width=g.rules.values.sumOf {
            it.size
        }.toString().length;
        var number=0;
        for(lhs in g.order)for(i in g.rules.getValue(lhs).indices) {
            number++;
            var line=(if(i==0)"$lhs -> " else " ".repeat(lhs.length)+" | ")+GrammarParser.notation(g.rules.getValue(lhs)[i]);
            if(numbered)line=number.toString().padStart(width)+"  "+line;
            result+=line
        };
        return result
    }
    fun stage(out: MutableList<String>,heading: String,log: List<String>?,g: GrammarParser.Grammar,numbered: Boolean) {
        out+=heading;
        if(log!=null)out.addAll(log.ifEmpty {
            listOf("none")
        });
        out+=summary(g);
        out.addAll(listing(g,numbered));
        out+=""
    }
    fun grammarReport(): List<String> {
        val out=mutableListOf<String>();
        stage(out,"== cleaned grammar ==",null,cleaned,false);
        stage(out,"== left recursion elimination ==",eliminationLog,eliminated,false);
        stage(out,"== left factoring ==",factorLog,factored,false);
        stage(out,"== final grammar ==",unreachableLog,grammar,true);
        out+="== cross reference ==";
        for(symbol in grammar.order+sets.terminals) {
            val uses=table.productions.filter {
                symbol in it.rhs
            }.map {
                it.number
            };
            val label=if(GrammarParser.nonterminal(symbol))symbol else "\"$symbol\"";
            out+=if(uses.isEmpty())"$label not used" else list("$label used in",uses)
        };
        return out
    }
    fun setsReport(): List<String> {
        val out=mutableListOf("passes: nullable=${sets.nullablePasses} first=${sets.firstPasses} follow=${sets.followPasses}","");
        for(lhs in grammar.order) {
            out+=lhs;
            out+="  nullable: ${if(sets.nullable.getValue(lhs))"yes" else "no"}";
            out+=list("  first:",FirstFollow.terminalOrder(sets.first.getValue(lhs)));
            out+=list("  follow:",FirstFollow.terminalOrder(sets.follow.getValue(lhs)));
            out+=list("  shortest:",words.getValue(lhs))
        };
        return out
    }
    fun firstPath(number: Int,terminal: String): List<Int> {
        val queue=ArrayDeque<Int>();
        val seen=mutableSetOf(number);
        val parent=mutableMapOf<Int,Int>();
        queue.addLast(number);
        while(queue.isNotEmpty()) {
            val current=queue.removeFirst();
            val p=table.productions[current-1];
            for(symbol in p.rhs) {
                if(symbol==terminal) {
                    val path=mutableListOf<Int>();
                    var q=current;
                    while(q!=number) {
                        path+=q;
                        q=parent.getValue(q)
                    };
                    path.reverse();
                    return path
                };
                if(GrammarParser.nonterminal(symbol))for(next in table.productions)if(next.lhs==symbol&&seen.add(next.number)) {
                    parent[next.number]=current;
                    queue.addLast(next.number)
                };
                if(!GrammarParser.nonterminal(symbol)||!sets.nullable.getValue(symbol))break
            }
        };
        error("FIRST")
    }
    fun followPath(lhs: String,terminal: String): List<Int> {
        val queue=ArrayDeque<String>();
        val paths=mutableMapOf<String,List<Int>>(lhs to emptyList());
        queue.addLast(lhs);
        while(queue.isNotEmpty()) {
            val current=queue.removeFirst();
            if(current==grammar.start&&terminal=="$")return paths.getValue(current);
            for(p in table.productions)for(i in p.rhs.indices)if(p.rhs[i]==current) {
                val suffix=FirstFollow.sequence(p.rhs.drop(i+1),sets);
                val path=paths.getValue(current)+p.number;
                if(terminal in suffix.first)return path;
                if(suffix.empty&&p.lhs !in paths) {
                    paths[p.lhs]=path;
                    queue.addLast(p.lhs)
                }
            }
        };
        error("FOLLOW")
    }
    fun tableReport(): List<String> {
        val out=mutableListOf("== predict sets ==");
        for(p in table.productions) {
            out+="${p.number}: ${p.notation()}";
            out+=list("  predict:",FirstFollow.terminalOrder(p.predict.keys))
        };
        out+="";
        out+="== parse table ==";
        val terminals=sets.terminals+"$";
        val rows=mutableListOf(listOf("")+terminals);
        for(lhs in grammar.order)rows.add(listOf(lhs)+terminals.map {
            val cell=table.cells.getValue(Table.Cell(lhs,it));
            if(cell.isEmpty())"." else cell.joinToString("/")
        });
        val widths=IntArray(rows[0].size) {
            c->rows.maxOf {
                it[c].length
            }
        };
        for(row in rows) {
            var line=row[0].padEnd(widths[0]);
            for(c in 1 until row.size)line+="  "+row[c].padStart(widths[c]);
            out+=line
        };
        out+="";
        out+="== conflicts ==";
        if(table.conflicts.isEmpty())out+="none";
        for(conflict in table.conflicts) {
            val lhs=conflict.cell.lhs;
            val terminal=conflict.cell.terminal;
            out+="conflict $lhs on $terminal: ${conflict.kind}, chosen ${conflict.chosen}";
            for(number in table.cells.getValue(conflict.cell)) {
                val p=table.productions[number-1];
                val reason=p.predict.getValue(terminal);
                val path=if(reason=="FIRST")firstPath(number,terminal) else followPath(lhs,terminal);
                out+="  $number: ${p.notation()} ($reason${if(path.isEmpty())"" else list(" via",path)})"
            }
        };
        out+="LL(1): ${if(table.conflicts.isEmpty())"yes" else "no"}";
        out+="conflicts before transformation: $beforeConflicts";
        return out
    }
    data class EarleyProduction(val lhs: String,val rhs: List<String>)
    data class State(val production: Int,val dot: Int,val origin: Int)
    fun inLanguage(tokens: List<String>): Boolean {
        val productions=mutableListOf(EarleyProduction("",listOf(cleaned.start)));
        for(lhs in cleaned.order)for(rhs in cleaned.rules.getValue(lhs))productions+=EarleyProduction(lhs,rhs);
        val chart=List(tokens.size+1) {
            mutableSetOf<State>()
        };
        chart[0]+=State(0,0,0);
        for(position in chart.indices) {
            var changed: Boolean;
            do {
                changed=false;
                for(state in chart[position].toList()) {
                    val p=productions[state.production];
                    if(state.dot<p.rhs.size) {
                        val symbol=p.rhs[state.dot];
                        if(GrammarParser.nonterminal(symbol)) {
                            for(q in 1 until productions.size)if(productions[q].lhs==symbol&&chart[position].add(State(q,0,position)))changed=true
                        } else if(position<tokens.size&&symbol==tokens[position])chart[position+1].add(State(state.production,state.dot+1,state.origin))
                    } else for(previous in chart[state.origin].toList()) {
                        val parent=productions[previous.production];
                        if(previous.dot<parent.rhs.size&&parent.rhs[previous.dot]==p.lhs&&chart[position].add(State(previous.production,
                            previous.dot+1,previous.origin)))changed=true
                    }
                }
            }
            while(changed)
        };
        return State(0,1,0) in chart.last()
    }
    fun error(event: Driver.Event): String {
        val unexpected=if(event.token=="$")"end of input" else "\"${event.token}\" at token ${event.position}";
        val expected=if(GrammarParser.nonterminal(event.symbol))(sets.terminals+"$").filter {
            Table.Cell(event.symbol,it) in table.choices
        }.joinToString(" ") {
            if(it=="$")it else "\"$it\""
        } else if(event.symbol=="$")"$" else "\"${event.symbol}\"";
        val recovery=when(event.kind) {
            "skip"->"skipped \"${event.token}\"";
            "pop"->"popped ${event.symbol}";
            else->"inserted \"${event.symbol}\""
        };
        return "step ${event.step}: unexpected $unexpected; expected $expected; $recovery"
    }
    fun label(node: Driver.Node)=node.symbol+(node.mark?.let {
        " ($it)"
    }
    ?:"")
    fun branches(node: Driver.Node,prefix: String,last: Boolean,out: MutableList<String>) {
        out+=prefix+(if(last)"`-- " else "|-- ")+label(node);
        val next=prefix+if(last)"    " else "|   ";
        for(i in node.children.indices)branches(node.children[i],next,i==node.children.lastIndex,out)
    }
    fun tree(node: Driver.Node): List<String> {
        val out=mutableListOf(label(node));
        for(i in node.children.indices)branches(node.children[i],"",i==node.children.lastIndex,out);
        return out
    }
    fun compact(node: Driver.Node): Driver.Node {
        val children=mutableListOf<Driver.Node>();
        for(child in node.children) {
            if(child.symbol=="%empty")continue;
            val result=compact(child);
            if(result.mark==null&&GrammarParser.nonterminal(result.symbol)&&result.children.isEmpty())continue;
            if(result.mark==null&&GrammarParser.nonterminal(result.symbol)&&"'" in result.symbol)children.addAll(result.children) else children+=result
        };
        if(children.size==1&&node.mark==null)return children[0];
        return Driver.Node(node.symbol,node.mark,children)
    }
    fun trace(parse: Driver.Result): List<String> {
        val rows=mutableListOf(listOf("step","stack","input","action"));
        for(t in parse.trace)rows.add(listOf(t.step.toString(),t.stack.joinToString(" "),t.input.joinToString(" "),t.action));
        val widths=IntArray(3) {
            c->rows.maxOf {
                it[c].length
            }
        };
        return rows.map {
            row->val prefix=(0..2).joinToString("") {
                row[it].padEnd(widths[it])+"  "
            }
            prefix+row[3]
        }
    }
    fun derivation(leftParse: List<Int>): List<String> {
        val sequence=mutableListOf(grammar.start);
        val out=mutableListOf("  ${grammar.start}");
        for(number in leftParse) {
            val p=table.productions[number-1];
            val index=sequence.indexOfFirst(GrammarParser::nonterminal);
            sequence.removeAt(index);
            sequence.addAll(index,p.rhs);
            out+="  => ${GrammarParser.notation(sequence)}"
        };
        return out
    }
    fun input(tokens: List<String>)=tokens.mapIndexed {
        i,t->Driver.Input(t,i+1)
    }
    fun parsesReport(inputs: List<String>): List<String> {
        val out=mutableListOf<String>();
        val used=mutableSetOf<Int>();
        val mismatches=mutableListOf<Int>();
        var accepted=0;
        var languageCount=0;
        var unknown=0;
        var skip=0;
        var pop=0;
        var missing=0;
        val known=sets.terminals.toSet();
        for(number in 1..inputs.size) {
            val line=inputs[number-1];
            val tokens=if(line.isEmpty())emptyList() else line.split(' ');
            val filtered=mutableListOf<Driver.Input>();
            val errors=mutableListOf<String>();
            for(i in tokens.indices)if(tokens[i] in known)filtered+=Driver.Input(tokens[i],i+1) else {
                unknown++;
                errors+="unknown \"${tokens[i]}\" at token ${i+1}; removed"
            };
            val result=Driver.parse(filtered,grammar,sets,table);
            used.addAll(result.leftParse);
            errors.addAll(result.errors.map(::error));
            val valid=errors.isEmpty();
            val language=inLanguage(tokens);
            if(valid)accepted++;
            if(language)languageCount++;
            if(valid!=language)mismatches+=number;
            skip+=result.skip;
            pop+=result.pop;
            missing+=result.missing;
            out+="== input $number ==";
            out+=list("tokens:",tokens);
            out.addAll(trace(result));
            out+=list("left parse:",result.leftParse);
            out+="stats: steps=${result.trace.size} predicts=${result.predicts} matches=${result.matches} max_stack=${result.maxStack}";
            if(errors.isNotEmpty()) {
                out+="errors:";
                out.addAll(errors.map {
                    "  $it"
                })
            };
            out+=if(valid)"result: accepted" else "result: rejected (errors: ${errors.size})";
            out+="language: ${if(language)"yes" else "no"}";
            if(valid) {
                out+="derivation:";
                out.addAll(derivation(result.leftParse))
            };
            out+="tree:";
            out.addAll(tree(result.root));
            out+="compact tree:";
            out.addAll(tree(compact(result.root)));
            out+=""
        };
        out+="== summary ==";
        out+="inputs=${inputs.size} accepted=$accepted rejected=${inputs.size-accepted} in_language=$languageCount";
        out+=list("mismatches:",mismatches);
        out+="recovery: unknown=$unknown skip=$skip pop=$pop missing=$missing";
        out+="coverage: ${used.size} of ${table.productions.size} productions used";
        val unused=table.productions.filter {
            it.number !in used
        };
        out+=list("unused:",unused.map {
            it.number
        });
        for(p in unused) {
            val example=example(p);
            val result=Driver.parse(input(example),grammar,sets,table);
            out+="  ${p.number}: ${p.notation()}";
            out+=list("    example:",example);
            out+=if(result.errors.isEmpty())"    result: accepted" else "    result: rejected (errors: ${result.errors.size})";
            out+="    used: ${if(p.number in result.leftParse)"yes" else "no"}"
        };
        return out
    }
    @JvmStatic fun main(args: Array<String>) {
        parsed=GrammarParser.parse(lines("grammar.bnf"));
        prepare();
        write("grammar.txt",grammarReport());
        write("sets.txt",setsReport());
        write("table.txt",tableReport());
        write("parses.txt",parsesReport(lines("inputs.txt")));
        diagnostics+=if(table.conflicts.isEmpty())"result: LL(1)" else "result: not LL(1) (conflicts: ${table.conflicts.size})";
        write("diagnostics.txt",diagnostics)
    }
}
