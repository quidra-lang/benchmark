object Combining {
    const val NA="NOT_APPLICABLE";
    const val IP="INDETERMINATE{P}";
    const val ID="INDETERMINATE{D}";
    const val IDP="INDETERMINATE{DP}"
    data class State(val evaluated: PolicyEngine.Evaluation?,val checked: PolicyEngine.Target?)
    data class Result(val decision: String,val reason: String?,val states: List<State?>)
    fun combine(algorithm: String,children: List<PolicyParser.Element>,evaluate: (PolicyParser.Element)->PolicyEngine.Evaluation,
        target: (PolicyParser.Element)->PolicyEngine.Target): Result {
        val states=MutableList<State?>(children.size) {
            null
        };
        if(algorithm=="only-one-applicable") {
            var matched=-1;
            for((i,child) in children.withIndex()) {
                val result=target(child);
                states[i]=State(null,result);
                if(result.result=="INDETERMINATE")return Result(IDP,result.reason,states);
                if(result.result=="MATCH") {
                    if(matched>=0)return Result(IDP,"multiple applicable ${children[matched].identifier} ${child.identifier}",
                        states);
                    matched=i
                }
            };
            if(matched<0)return Result(NA,null,states);
            val result=evaluate(children[matched]);
            states[matched]=State(result,null);
            return Result(result.decision,result.reason,states)
        };
        val decisions=mutableSetOf<String>();
        var firstError: String?=null;
        for((i,child) in children.withIndex()) {
            val result=evaluate(child);
            states[i]=State(result,null);
            val decision=result.decision;
            decisions.add(decision);
            if(decision.startsWith("INDETERMINATE")&&firstError==null)firstError=result.reason;
            if(algorithm=="first-applicable"&&decision!=NA)return Result(decision,result.reason,states);
            if(algorithm in setOf("deny-overrides","permit-unless-deny")&&decision=="DENY")return Result("DENY",
                null,states);
            if(algorithm in setOf("permit-overrides","deny-unless-permit")&&decision=="PERMIT")return Result("PERMIT",
                null,states)
        };
        val decision=when(algorithm) {
            "deny-unless-permit"->"DENY";
            "permit-unless-deny"->"PERMIT";
            "first-applicable"->NA;
            "deny-overrides"->when {
                IDP in decisions||ID in decisions&&(IP in decisions||"PERMIT" in decisions)->IDP;
                ID in decisions->ID;
                "PERMIT" in decisions->"PERMIT";
                IP in decisions->IP;
                else->NA
            };
            else->when {
                IDP in decisions||IP in decisions&&(ID in decisions||"DENY" in decisions)->IDP;
                IP in decisions->IP;
                "DENY" in decisions->"DENY";
                ID in decisions->ID;
                else->NA
            }
        };
        return Result(decision,if(decision.startsWith("INDETERMINATE"))firstError else null,states)
    }
}
