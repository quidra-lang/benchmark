object Analysis {
    data class Domain(val name: String,val values: List<Any>)
    fun points(domains: List<Domain>): List<Map<String,Any>> {
        var points=listOf<Map<String,Any>>(emptyMap());
        for(domain in domains) {
            val following=mutableListOf<Map<String,Any>>();
            for(point in points)for(value in domain.values) {
                val next=point.toMutableMap();
                next[domain.name]=value;
                following.add(next)
            };
            points=following
        };
        return points
    }
    fun dayNotation(days: Collection<Int>): String {
        val ordered=days.toSortedSet().toList();
        var first=ordered.first();
        var last=first;
        val runs=mutableListOf<String>();
        for(day in ordered.drop(1)) {
            if(day!=last+1) {
                runs.add("$first-$last");
                first=day
            };
            last=day
        };
        runs.add("$first-$last");
        return runs.joinToString(",")
    }
    fun blocker(rule: PolicyParser.Element,standalone: Map<String,String>): String? {
        for(earlier in rule.parent!!.children) {
            if(earlier===rule)break;
            if(standalone.getValue(earlier.identifier)!=Combining.NA)return earlier.identifier
        };
        return null
    }
    fun conflictWinner(policy: PolicyParser.Element,earlier: PolicyParser.Element,later: PolicyParser.Element): String {
        if(policy.behavior=="first-applicable")return earlier.identifier;
        val effect=if(policy.behavior in setOf("deny-overrides","permit-unless-deny"))"DENY" else "PERMIT";
        return if(earlier.behavior==effect)earlier.identifier else later.identifier
    }
}
