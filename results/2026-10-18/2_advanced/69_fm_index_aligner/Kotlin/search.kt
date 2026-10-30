import java.util.ArrayDeque
object Search {
    data class State(val position: Int,val remaining: Int,val lower: Int,val upper: Int)
    data class Leaf(val lower: Int,val upper: Int,val mismatches: Int)
    data class Result(val nodes: Int,val leaves: List<Leaf>,val positions: Int)
    fun bounds(sequence: String,reverse: FmIndex): IntArray {
        val values=IntArray(sequence.length);
        var mismatches=0;
        var range=FmIndex.Interval(0,reverse.size);
        for((i,base) in sequence.withIndex()) {
            range=reverse.extend(range.lower,range.upper,base);
            if(range.empty()) {
                mismatches++;
                range=FmIndex.Interval(0,reverse.size)
            };
            values[i]=mismatches
        };
        return values
    }
    fun backtrack(sequence: String,maximum: Int,forward: FmIndex,reverse: FmIndex): Result {
        val lowerBounds=bounds(sequence,reverse);
        val stack=ArrayDeque<State>();
        stack.push(State(sequence.lastIndex,maximum,0,forward.size));
        var nodes=0;
        var positions=0;
        val leaves=mutableListOf<Leaf>();
        while(stack.isNotEmpty()) {
            val state=stack.pop();
            nodes++;
            if(state.remaining<(if(state.position<0)0 else lowerBounds[state.position]))continue;
            if(state.position==-1) {
                leaves.add(Leaf(state.lower,state.upper,maximum-state.remaining));
                positions+=state.upper-state.lower;
                continue
            };
            for(base in "TGCA") {
                val range=forward.extend(state.lower,state.upper,base);
                if(range.empty())continue;
                val mismatch=if(base==sequence[state.position])0 else 1;
                if(mismatch==0||state.remaining>=1)stack.push(State(state.position-1,state.remaining-mismatch,
                    range.lower,range.upper))
            }
        };
        return Result(nodes,leaves,positions)
    }
}
