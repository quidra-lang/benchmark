import java.util.TreeSet
object Elimination {
    data class Step(val variable: Int,val fill: Int,val scope: List<Int>,val size: Int)
    data class Plan(val steps: List<Step>,val maximum: Int,val total: Int)
    data class Product(val variable: Int,val factor: Factors.Factor)
    data class Outcome(val factor: Factors.Factor,val products: List<Product>)
    fun interaction(factors: List<Factors.Factor>,size: Int): Array<BooleanArray> {
        val graph=Array(size) {
            BooleanArray(size)
        };
        for(factor in factors)for(a in factor.variables)for(b in factor.variables)if(a!=b)graph[a][b]=true;
        return graph
    }
    fun plan(factors: List<Factors.Factor>,eliminate: List<Int>,method: String,order: List<Int>,
        sizes: IntArray): Plan {
        val graph=interaction(factors,sizes.size);
        val remaining=TreeSet(eliminate);
        val rank=IntArray(sizes.size);
        for((i,v) in order.withIndex())rank[v]=i;
        val steps=mutableListOf<Step>();
        var maximum=0;
        var total=0;
        while(remaining.isNotEmpty()) {
            var selected=-1;
            var bestFill=Int.MAX_VALUE;
            var bestDegree=Int.MAX_VALUE;
            for(v in remaining) {
                val neighbors=sizes.indices.filter {
                    graph[v][it]
                };
                var fill=0;
                for(i in neighbors.indices)for(j in i+1 until neighbors.size)if(!graph[neighbors[i]][neighbors[j]])fill++;
                val better=selected<0||(if(method=="GIVEN")rank[v]<rank[selected] else fill<bestFill||(fill==bestFill&&neighbors.size<bestDegree));
                if(better) {
                    selected=v;
                    bestFill=fill;
                    bestDegree=neighbors.size
                }
            };
            val neighbors=sizes.indices.filter {
                graph[selected][it]
            };
            val scope=sizes.indices.filter {
                it==selected||graph[selected][it]
            };
            val size=Factors.entries(scope,sizes);
            steps.add(Step(selected,bestFill,scope,size));
            maximum=maxOf(maximum,size);
            total+=size;
            for(a in neighbors)for(b in neighbors)if(a!=b)graph[a][b]=true;
            for(u in sizes.indices) {
                graph[u][selected]=false;
                graph[selected][u]=false
            };
            remaining.remove(selected)
        };
        return Plan(steps,maximum,total)
    }
    fun execute(initial: List<Factors.Factor>,plan: Plan,sizes: IntArray,maximize: Boolean=false): Outcome {
        var factors=initial.toList();
        val products=mutableListOf<Product>();
        for(step in plan.steps) {
            val selected=factors.filter {
                step.variable in it.variables
            };
            val remaining=factors.filter {
                step.variable !in it.variables
            }.toMutableList();
            val product=Factors.multiply(selected,sizes);
            remaining.add(product.eliminate(step.variable,maximize));
            factors=remaining;
            if(maximize)products.add(Product(step.variable,product))
        };
        return Outcome(Factors.multiply(factors,sizes),products)
    }
    fun traceback(products: List<Product>,sizes: IntArray): IntArray {
        val assignment=IntArray(sizes.size);
        for(product in products.asReversed()) {
            val variable=product.variable;
            var best=0;
            var maximum=-1.0;
            for(state in 0 until sizes[variable]) {
                assignment[variable]=state;
                val value=product.factor.value(assignment);
                if(value>maximum) {
                    maximum=value;
                    best=state
                }
            };
            assignment[variable]=best
        };
        return assignment
    }
}
