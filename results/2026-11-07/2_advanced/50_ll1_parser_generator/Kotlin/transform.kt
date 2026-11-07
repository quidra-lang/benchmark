object Transform {
    data class Result(val grammar: GrammarParser.Grammar,val log: List<String>)
    fun fresh(lhs: String,g: GrammarParser.Grammar): String {
        var name=lhs.dropLast(1)+"'>";
        while(name in g.rules)name=name.dropLast(1)+"'>";
        return name
    }
    fun reaches(g: GrammarParser.Grammar,source: String,target: String): Boolean {
        val seen=mutableSetOf(source);
        val queue=ArrayDeque<String>();
        queue.addLast(source);
        while(queue.isNotEmpty()) {
            val current=queue.removeFirst();
            for(rhs in g.rules.getValue(current))if(rhs.isNotEmpty()&&GrammarParser.nonterminal(rhs[0])) {
                val next=rhs[0];
                if(next==target)return true;
                if(seen.add(next))queue.addLast(next)
            }
        };
        return false
    }
    fun eliminate(source: GrammarParser.Grammar): Result {
        val g=GrammarParser.copy(source);
        val original=g.order.toList();
        val log=mutableListOf<String>();
        for(i in original.indices) {
            val lhs=original[i];
            for(j in 0 until i) {
                val earlier=original[j];
                if(g.rules.getValue(lhs).none {
                    it.firstOrNull()==earlier
                }
                ||!reaches(g,earlier,lhs))continue;
                val rows=mutableListOf<List<String>>();
                for(rhs in g.rules.getValue(lhs))if(rhs.firstOrNull()==earlier) {
                    for(delta in g.rules.getValue(earlier))rows.add(delta+rhs.drop(1))
                } else rows.add(rhs);
                g.rules[lhs]=rows.distinct().toMutableList();
                log+="substitute $earlier into $lhs"
            };
            val recursive=mutableListOf<List<String>>();
            val nonrecursive=mutableListOf<List<String>>();
            for(rhs in g.rules.getValue(lhs)) {
                if(rhs==listOf(lhs)) {
                    log+="remove cycle ${GrammarParser.production(lhs,rhs)}";
                    continue
                };
                if(rhs.firstOrNull()==lhs)recursive.add(rhs.drop(1)) else nonrecursive.add(rhs)
            };
            if(recursive.isEmpty()) {
                g.rules[lhs]=nonrecursive;
                continue
            };
            val created=fresh(lhs,g);
            g.rules[lhs]=nonrecursive.map {
                it+created
            }.toMutableList();
            g.rules[created]=recursive.map {
                it+created
            }.toMutableList();
            g.rules.getValue(created).add(emptyList());
            g.order.add(g.order.indexOf(lhs)+1,created);
            log+="eliminate left recursion in $lhs with $created"
        };
        return Result(g,log)
    }
    fun factor(source: GrammarParser.Grammar): Result {
        val g=GrammarParser.copy(source);
        val log=mutableListOf<String>();
        var position=0;
        while(position<g.order.size) {
            val lhs=g.order[position];
            var current=g.rules.getValue(lhs);
            val insertions=mutableListOf<String>();
            var index=0;
            while(index<current.size) {
                val row=current[index];
                if(row.isEmpty()) {
                    index++;
                    continue
                };
                val group=current.indices.filter {
                    current[it].firstOrNull()==row[0]
                };
                if(group.size==1) {
                    index++;
                    continue
                };
                val length=group.minOf {
                    current[it].size
                };
                var prefix=0;
                while(prefix<length&&group.all {
                    current[it][prefix]==row[prefix]
                })prefix++;
                val common=row.take(prefix);
                val created=fresh(lhs,g);
                g.rules[created]=group.map {
                    current[it].drop(prefix)
                }.toMutableList();
                val replacement=mutableListOf<List<String>>();
                for(i in current.indices)if(i==group[0])replacement.add(common+created) else if(i !in group)replacement.add(current[i]);
                g.rules[lhs]=replacement;
                current=replacement;
                insertions+=created;
                log+="left factor $lhs on ${GrammarParser.notation(common)} with $created";
                index=group[0]+1
            };
            g.order.addAll(position+1,insertions);
            position++
        };
        return Result(g,log)
    }
}
