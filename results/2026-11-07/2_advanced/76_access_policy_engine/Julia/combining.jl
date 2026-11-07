const NOT_APPLICABLE = "NOT_APPLICABLE"
const INDETERMINATE_P = "INDETERMINATE{P}"
const INDETERMINATE_D = "INDETERMINATE{D}"
const INDETERMINATE_DP = "INDETERMINATE{DP}"
function combine_children(algorithm,children,evaluate,target,identifier)
    states = Any[nothing for _ in children]
    if algorithm=="only-one-applicable"
        matched = 0
        for (i,child) in enumerate(children)
            checked = target(child)
            states[i] = (kind="checked",target=checked)
            checked[1]=="INDETERMINATE" && return (decision=INDETERMINATE_DP,reason=checked[2],states=states)
            if checked[1]=="MATCH"
                matched!=0 && return (
                    decision=INDETERMINATE_DP,
                    reason="multiple applicable $(identifier(children[matched])) $(identifier(child))",
                    states=states
                )
                matched = i
            end
        end
        matched==0 && return (decision=NOT_APPLICABLE,reason="",states=states)
        result = evaluate(children[matched])
        states[matched] = (kind="evaluated",result=result)
        return (decision=result.decision,reason=result.reason,states=states)
    end
    decisions,first_error = Set{String}(),""
    for (i,child) in enumerate(children)
        result = evaluate(child)
        states[i] = (kind="evaluated",result=result)
        d = result.decision
        push!(decisions,d)
        startswith(d,"INDETERMINATE") && isempty(first_error) && (first_error=result.reason)
        algorithm=="first-applicable" && d!=NOT_APPLICABLE && return (
            decision=d,
            reason=result.reason,
            states=states
        )
        algorithm in ("deny-overrides","permit-unless-deny") && d=="DENY" && return (
            decision="DENY",
            reason="",
            states=states
        )
        algorithm in ("permit-overrides","deny-unless-permit") && d=="PERMIT" && return (
            decision="PERMIT",
            reason="",
            states=states
        )
    end
    if algorithm=="deny-unless-permit"
        d = "DENY"
    elseif algorithm=="permit-unless-deny"
        d = "PERMIT"
    elseif algorithm=="first-applicable"
        d = NOT_APPLICABLE
    elseif algorithm=="deny-overrides"
        d = INDETERMINATE_DP in decisions || (INDETERMINATE_D in decisions && (INDETERMINATE_P in decisions || "PERMIT" in decisions)) ? INDETERMINATE_DP :
            INDETERMINATE_D in decisions ? INDETERMINATE_D : "PERMIT" in decisions ? "PERMIT" : INDETERMINATE_P in decisions ? INDETERMINATE_P : NOT_APPLICABLE
    else
        d = INDETERMINATE_DP in decisions || (INDETERMINATE_P in decisions && (INDETERMINATE_D in decisions || "DENY" in decisions)) ? INDETERMINATE_DP :
            INDETERMINATE_P in decisions ? INDETERMINATE_P : "DENY" in decisions ? "DENY" : INDETERMINATE_D in decisions ? INDETERMINATE_D : NOT_APPLICABLE
    end
    (decision=d,reason=startswith(d,"INDETERMINATE") ? first_error : "",states=states)
end
