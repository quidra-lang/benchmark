object Driver {
    data class Input(val name: String,val position: Int)
    class Node(val symbol: String,var mark: String?=null,var children: MutableList<Node> = mutableListOf())
    data class StackEntry(val symbol: String,val node: Node?)
    data class Trace(val step: Int,val stack: List<String>,val input: List<String>,val action: String)
    data class Event(val step: Int,val kind: String,val symbol: String,val token: String,val position: Int)
    class Result(val root: Node) {
        val trace=mutableListOf<Trace>();
        val leftParse=mutableListOf<Int>();
        val errors=mutableListOf<Event>();
        var predicts=0;
        var matches=0;
        var skip=0;
        var pop=0;
        var missing=0;
        var maxStack=0
    }
    fun parse(original: List<Input>,g: GrammarParser.Grammar,sets: FirstFollow.Sets,table: Table.Result): Result {
        val input=original+Input("$",original.size+1);
        val result=Result(Node(g.start));
        val stack=mutableListOf(StackEntry("$",null),StackEntry(g.start,result.root));
        var cursor=0;
        var step=0;
        while(true) {
            step++;
            val entry=stack.last();
            val top=entry.symbol;
            val token=input[cursor];
            val current=token.name;
            result.maxStack=maxOf(result.maxStack,stack.size);
            val beforeStack=stack.map {
                it.symbol
            };
            val beforeInput=input.drop(cursor).map {
                it.name
            };
            val action: String;
            var terminate=false;
            var event: Event?=null;
            when {
                top=="$"&&current=="$"-> {
                    action="accept";
                    terminate=true
                };
                top=="$"-> {
                    action="error: skip $current";
                    event=Event(step,"skip",top,current,token.position);
                    cursor++;
                    result.skip++
                };
                !GrammarParser.nonterminal(top)-> {
                    if(top==current) {
                        action="match $current";
                        stack.removeLast();
                        cursor++;
                        result.matches++
                    } else {
                        action="error: missing $top";
                        entry.node!!.mark="missing";
                        stack.removeLast();
                        result.missing++;
                        event=Event(step,"missing",top,current,token.position)
                    }
                };
                Table.Cell(top,current) in table.choices-> {
                    val number=table.choices.getValue(Table.Cell(top,current));
                    val p=table.productions[number-1];
                    action="predict $number: ${p.notation()}";
                    result.leftParse+=number;
                    stack.removeLast();
                    val children=if(p.rhs.isEmpty())listOf(Node("%empty")) else p.rhs.map {
                        Node(it)
                    };
                    entry.node!!.children.addAll(children);
                    if(p.rhs.isNotEmpty())for(child in children.asReversed())stack+=StackEntry(child.symbol,child);
                    result.predicts++
                };
                current=="$"||current in sets.follow.getValue(top)-> {
                    action="error: pop $top";
                    entry.node!!.mark="error";
                    stack.removeLast();
                    result.pop++;
                    event=Event(step,"pop",top,current,token.position)
                };
                else-> {
                    action="error: skip $current";
                    cursor++;
                    result.skip++;
                    event=Event(step,"skip",top,current,token.position)
                }
            };
            result.trace+=Trace(step,beforeStack,beforeInput,action);
            if(event!=null)result.errors+=event;
            if(terminate)return result
        }
    }
}
