object FirstFollow {
    fun terminalOrder(terminals: Collection<String>)=terminals.filter {
        it!="$"
    }.sorted()+if("$" in terminals)listOf("$") else emptyList()
    fun terminals(g: GrammarParser.Grammar)=g.order.flatMap {
        g.rules.getValue(it)
    }.flatten().filterNot(GrammarParser::nonterminal).toSet()
    data class Sequence(val first: Set<String>,val empty: Boolean)
    class Sets {
        val nullable=mutableMapOf<String,Boolean>();
        val first=mutableMapOf<String,MutableSet<String>>();
        val follow=mutableMapOf<String,MutableSet<String>>();
        var nullablePasses=0;
        var firstPasses=0;
        var followPasses=0;
        var terminals=emptyList<String>()
    }
    fun sequence(rhs: List<String>,sets: Sets): Sequence {
        val result=mutableSetOf<String>();
        for(symbol in rhs) {
            if(!GrammarParser.nonterminal(symbol)) {
                result+=symbol;
                return Sequence(result,false)
            };
            result.addAll(sets.first.getValue(symbol));
            if(!sets.nullable.getValue(symbol))return Sequence(result,false)
        };
        return Sequence(result,true)
    }
    fun analyze(g: GrammarParser.Grammar): Sets {
        val sets=Sets();
        for(lhs in g.order) {
            sets.nullable[lhs]=false;
            sets.first[lhs]=mutableSetOf();
            sets.follow[lhs]=mutableSetOf()
        };
        sets.follow.getValue(g.start).add("$");
        var changed: Boolean;
        do {
            sets.nullablePasses++;
            changed=false;
            for(lhs in g.order)if(!sets.nullable.getValue(lhs))for(rhs in g.rules.getValue(lhs))if(rhs.all {
                GrammarParser.nonterminal(it)&&sets.nullable.getValue(it)
            }) {
                sets.nullable[lhs]=true;
                changed=true;
                break
            }
        }
        while(changed);
        do {
            sets.firstPasses++;
            changed=false;
            for(lhs in g.order)for(rhs in g.rules.getValue(lhs))if(sets.first.getValue(lhs).addAll(sequence(rhs,sets).first))changed=true
        }
        while(changed);
        do {
            sets.followPasses++;
            changed=false;
            for(lhs in g.order)for(rhs in g.rules.getValue(lhs))for(i in rhs.indices) {
                val symbol=rhs[i];
                if(!GrammarParser.nonterminal(symbol))continue;
                val suffix=sequence(rhs.drop(i+1),sets);
                val more=suffix.first.toMutableSet();
                if(suffix.empty)more.addAll(sets.follow.getValue(lhs));
                if(sets.follow.getValue(symbol).addAll(more))changed=true
            }
        }
        while(changed);
        sets.terminals=terminalOrder(terminals(g));
        return sets
    }
}
