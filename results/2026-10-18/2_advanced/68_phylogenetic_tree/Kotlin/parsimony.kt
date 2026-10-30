object Parsimony {
    data class Merge(val set: Int,val changes: Int)
    data class Provisional(val sets: IntArray,val changes: Int)
    data class Branch(val mask: Int,val first: Int,val second: Int)
    data class Candidate(val mask: Int,val swap: Int,val tree: TreeBuilding.Tree)
    data class Ends(val first: Int,val second: Int) {
        companion object {
            fun of(a: Int,b: Int)=Ends(minOf(a,b),maxOf(a,b))
        }
    }
    data class Reconstruction(val ancestors: Map<Int,String>,val branchChanges: Map<Ends,Int>,
        val siteChanges: IntArray)
    fun merge(a: Int,b: Int): Merge {
        val common=a and b;
        return if(common!=0)Merge(common,0) else Merge(a or b,1)
    }
    fun provisional(rooted: TreeBuilding.Rooted,pattern: IntArray): Provisional {
        val sets=IntArray(rooted.tree.nextNode);
        var changes=0;
        for(node in rooted.order.asReversed())if(node<rooted.tree.size)sets[node]=pattern[node] else {
            val children=rooted.children[node].filter {
                it!=rooted.outgroup
            };
            val m=merge(sets[children[0]],sets[children[1]]);
            sets[node]=m.set;
            changes+=m.changes;
            if(node==rooted.root)changes+=merge(sets[node],sets[rooted.outgroup]).changes
        };
        return Provisional(sets,changes)
    }
    fun patternScores(tree: TreeBuilding.Tree,patterns: Alignment.Patterns,outgroup: Int): IntArray {
        val rooted=tree.rooted(outgroup);
        return IntArray(patterns.patterns.size) {
            provisional(rooted,patterns.encoded[it]).changes
        }
    }
    fun score(tree: TreeBuilding.Tree,patterns: Alignment.Patterns,outgroup: Int): Int {
        val scores=patternScores(tree,patterns,outgroup);
        var total=0;
        for(i in scores.indices)total+=scores[i]*patterns.weights[i];
        return total
    }
    fun reconstruct(tree: TreeBuilding.Tree,patterns: Alignment.Patterns,outgroup: Int): Reconstruction {
        val rooted=tree.rooted(outgroup);
        val byPattern=tree.internals().associateWith {
            StringBuilder()
        };
        val changes=tree.edges().associate {
            Ends.of(it.first,it.second) to 0
        }.toMutableMap();
        val scores=IntArray(patterns.patterns.size);
        for(i in scores.indices) {
            val p=provisional(rooted,patterns.encoded[i]);
            val sets=p.sets;
            val states=IntArray(tree.nextNode);
            scores[i]=p.changes;
            val combined=merge(sets[rooted.root],sets[outgroup]).set;
            val first=combined and -combined;
            for(node in listOf(rooted.root,outgroup))states[node]=if((sets[node] and first)!=0)first else sets[node] and -sets[node];
            for(node in rooted.order)if(node!=rooted.root&&node!=outgroup) {
                val parent=states[rooted.parents[node]];
                states[node]=if((sets[node] and parent)!=0)parent else sets[node] and -sets[node]
            };
            for(node in tree.internals())byPattern.getValue(node).append(Alignment.BASES[Integer.numberOfTrailingZeros(states[node])]);
            for(edge in changes.keys.toList())if(states[edge.first]!=states[edge.second])changes[edge]=changes.getValue(edge)+patterns.weights[i]
        };
        val ancestors=byPattern.mapValues {
            (_,value)->patterns.columns.map {
                value[it]
            }.joinToString("")
        };
        return Reconstruction(ancestors,changes,IntArray(patterns.columns.size) {
            scores[patterns.columns[it]]
        })
    }
    fun branches(tree: TreeBuilding.Tree,outgroup: Int): List<Branch> {
        val rooted=tree.rooted(outgroup);
        return rooted.order.filter {
            it!=rooted.root
        }.map {
            Branch(if(it==outgroup)rooted.ingroup else rooted.masks[it],rooted.parents[it],
                it)
        }.sortedBy {
            it.mask
        }
    }
    fun insert(tree: TreeBuilding.Tree,first: Int,second: Int,taxon: Int): TreeBuilding.Tree {
        val result=tree.copy();
        result.disconnect(first,second);
        val node=result.internal();
        result.connect(first,node);
        result.connect(second,node);
        result.connect(taxon,node);
        return result
    }
    fun nni(tree: TreeBuilding.Tree,outgroup: Int): List<Candidate> {
        val rooted=tree.rooted(outgroup);
        val result=mutableListOf<Candidate>();
        for(edge in branches(tree,outgroup)) {
            val u=edge.first;
            val v=edge.second;
            if(u<tree.size||v<tree.size)continue;
            val sibling=rooted.children[u].first {
                it!=v&&it!=outgroup
            };
            val children=rooted.children[v].sortedBy {
                rooted.masks[it]
            };
            for((i,child) in children.withIndex()) {
                val candidate=tree.copy();
                val a=candidate.disconnect(u,sibling);
                val b=candidate.disconnect(v,child);
                candidate.connect(u,child,b);
                candidate.connect(v,sibling,a);
                result.add(Candidate(edge.mask,i+1,candidate))
            }
        };
        return result
    }
}
