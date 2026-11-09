object GrammarParser {
    class Grammar {
        val order=mutableListOf<String>();
        val rules=linkedMapOf<String,MutableList<List<String>>>();
        var start="";
        val declared=mutableSetOf<String>();
        var hasDeclaration=false;
        val words=mutableMapOf<String,Int>();
        val diagnostics=mutableListOf<String>()
    }
    data class Token(val kind: String,val value: String,val start: Int,val end: Int)
    data class Parsed(val kind: String="",val lhs: String="",val alternatives: List<List<String>> = emptyList(),
        val words: List<String> = emptyList(),val error: Int=0)
    fun nonterminal(s: String)=s.startsWith("<")&&s.endsWith(">")
    fun letter(c: Char)=c in 'A'..'Z'||c in 'a'..'z'
    fun word(c: Char)=letter(c)||c in '0'..'9'||c=='_'
    fun lex(line: String): List<Token> {
        val tokens=mutableListOf<Token>();
        var i=0;
        while(i<line.length) {
            val c=line[i];
            if(c==' ') {
                i++;
                continue
            };
            if(c=='#')break;
            val start=i;
            var kind="invalid";
            var value=c.toString();
            when {
                c=='<'-> {
                    var j=i+1;
                    if(j<line.length&&letter(line[j])) {
                        j++;
                        while(j<line.length&&word(line[j]))j++;
                        if(j<line.length&&line[j]=='>') {
                            kind="nonterminal";
                            i=j+1;
                            value=line.substring(start,i)
                        }
                    }
                };
                c=='"'-> {
                    var j=i+1;
                    while(j<line.length&&line[j]!=' '&&line[j]!='"')j++;
                    if(j>i+1&&j<line.length&&line[j]=='"') {
                        kind="terminal";
                        value=line.substring(i+1,j);
                        i=j+1
                    }
                };
                letter(c)-> {
                    var j=i+1;
                    while(j<line.length&&word(line[j]))j++;
                    kind="word";
                    i=j;
                    value=line.substring(start,i)
                };
                line.startsWith("::=",i)-> {
                    kind="definition";
                    value="::=";
                    i+=3
                };
                c=='|'-> {
                    kind="separator";
                    value="|";
                    i++
                };
                c=='%'-> {
                    var j=i+1;
                    while(j<line.length&&letter(line[j]))j++;
                    val directive=line.substring(i+1,j);
                    if(directive in listOf("empty","start","token")) {
                        kind="directive";
                        value="%$directive";
                        i=j
                    }
                }
            };
            if(kind=="invalid")i=start+1;
            tokens+=Token(kind,value,start+1,i);
            if(kind=="invalid")break
        };
        return tokens
    }
    fun bad(tokens: List<Token>,cursor: Int)=Parsed(error=if(cursor<tokens.size)tokens[cursor].start else tokens.last().end+1)
    fun symbol(t: Token)=t.kind in listOf("nonterminal","terminal","word")
    fun alternatives(tokens: List<Token>,begin: Int,kind: String,lhs: String): Parsed {
        var cursor=begin;
        val alternatives=mutableListOf<List<String>>();
        while(true) {
            if(cursor>=tokens.size)return bad(tokens,cursor);
            val first=tokens[cursor];
            val row=mutableListOf<String>();
            if(first.kind=="directive"&&first.value=="%empty") {
                cursor++;
                if(cursor<tokens.size&&tokens[cursor].kind!="separator")return bad(tokens,cursor)
            } else if(symbol(first)) {
                while(cursor<tokens.size&&symbol(tokens[cursor]))row+=tokens[cursor++].value
            } else return bad(tokens,cursor);
            alternatives+=row.toList();
            if(cursor>=tokens.size)return Parsed(kind,lhs,alternatives);
            if(tokens[cursor].kind!="separator")return bad(tokens,cursor);
            cursor++
        }
    }
    fun line(tokens: List<Token>): Parsed {
        if(tokens.isEmpty())return Parsed("blank");
        val first=tokens[0];
        if(first.kind=="nonterminal") {
            if(tokens.size<2)return bad(tokens,tokens.size);
            if(tokens[1].kind!="definition")return bad(tokens,1);
            return alternatives(tokens,2,"rule",first.value)
        };
        if(first.kind=="separator")return alternatives(tokens,1,"continuation","");
        if(first.kind=="directive"&&first.value=="%start") {
            if(tokens.size<2)return bad(tokens,tokens.size);
            if(tokens[1].kind!="nonterminal")return bad(tokens,1);
            if(tokens.size>2)return bad(tokens,2);
            return Parsed("start",tokens[1].value)
        };
        if(first.kind=="directive"&&first.value=="%token") {
            if(tokens.size<2)return bad(tokens,tokens.size);
            val words=mutableListOf<String>();
            for(i in 1 until tokens.size) {
                if(tokens[i].kind!="word")return bad(tokens,i);
                words+=tokens[i].value
            };
            return Parsed("declaration",words=words)
        };
        return bad(tokens,0)
    }
    fun notation(symbols: List<String>)=if(symbols.isEmpty())"%empty" else symbols.joinToString(" ")
    fun production(lhs: String,rhs: List<String>)="$lhs -> ${notation(rhs)}"
    fun parse(lines: List<String>): Grammar {
        val g=Grammar();
        var attachment="";
        for(i in lines.indices) {
            val number=i+1;
            val tokens=lex(lines[i]);
            val parsed=line(tokens);
            if(parsed.error>0) {
                g.diagnostics+="line $number: syntax error at column ${parsed.error}";
                attachment="";
                continue
            };
            if(parsed.kind=="blank")continue;
            var lhs=parsed.lhs;
            when(parsed.kind) {
                "rule"-> {
                    attachment=lhs;
                    if(lhs !in g.rules) {
                        g.order+=lhs;
                        g.rules[lhs]=mutableListOf()
                    }
                };
                "continuation"-> {
                    if(attachment.isEmpty()) {
                        g.diagnostics+="line $number: continuation without a rule";
                        continue
                    };
                    lhs=attachment
                };
                "start"-> {
                    attachment="";
                    if(g.start.isEmpty())g.start=lhs else g.diagnostics+="line $number: duplicate %start"
                };
                else-> {
                    attachment="";
                    g.hasDeclaration=true;
                    g.declared.addAll(parsed.words)
                }
            };
            if(parsed.kind=="rule"||parsed.kind=="continuation") {
                for(token in tokens)if(token.kind=="word")g.words.putIfAbsent(token.value,number);
                for(row in parsed.alternatives) {
                    if(row in g.rules.getValue(lhs))g.diagnostics+="line $number: duplicate alternative ${production(lhs,row)}" else g.rules.getValue(lhs).add(row)
                }
            }
        };
        if(g.start.isEmpty())g.start=g.order[0];
        return g
    }
    fun copy(original: Grammar): Grammar {
        val result=Grammar();
        result.order.addAll(original.order);
        result.start=original.start;
        for(lhs in original.order)result.rules[lhs]=original.rules.getValue(lhs).map {
            it.toList()
        }.toMutableList();
        return result
    }
}
