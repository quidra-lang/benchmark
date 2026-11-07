module Linter

using ..ScriptLoader: Diagnostic, isreference
using ..Matcher: wildcard, covers

const CODES = ("SYNTAX", "ORPHAN", "DUPLICATE", "KEY_NO_DECOMP", "KEY_UNREACHABLE", "SYNON_UNUSED", "PRE_CHAIN", "SYNON_UNKNOWN", "RULE_NO_REASM", "RULE_SHADOWED", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE")
const ERRORS = Set(("SYNTAX", "ORPHAN", "DUPLICATE", "SYNON_UNKNOWN", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE"))
const MOVES = ("GOTO", "RESTATE")

unknown(pattern, groups) = [element[2:end] for element in pattern if startswith(element, "@") && !haskey(groups, element[2:end])]

function references(item)
    if item.kind == "REASM"
        return [Int(item.text[i + 1] - '0') for i in 1:max(0, ncodeunits(item.text) - 2) if isreference(item.text[i:i + 2])]
    elseif item.kind == "RESTATE"
        return [Int(argument[2] - '0') for argument in item.arguments[2:end] if isreference(argument)]
    end
    return Int[]
end

function lint(script)
    found = copy(script.diagnostics)
    add(line, code, message) = push!(found, Diagnostic(line, code, message))
    replacements = Set(word for pre in script.pres for word in pre.replacement)
    targets = Set(item.arguments[1] for item in script.items if item.kind in MOVES)
    used = Set(element[2:end] for rule in script.rules for element in rule.pattern if startswith(element, "@"))
    for keyword in script.keywords
        word = keyword.word
        isempty(keyword.decomps) && add(keyword.line, "KEY_NO_DECOMP", "keyword $word has no DECOMP")
        haskey(script.pre, word) && word ∉ replacements && word ∉ targets && add(keyword.line, "KEY_UNREACHABLE", "keyword $word is replaced by PRE")
    end
    for group in script.groups
        group.name ∉ used && add(group.line, "SYNON_UNUSED", "group $(group.name) is never used")
    end
    for pre in script.pres, word in pre.replacement
        haskey(script.pre, word) && add(pre.line, "PRE_CHAIN", "replacement $word is itself replaced by PRE")
    end
    count = length(script.keywords)
    reach = falses(count, count)
    for i in 1:count
        reach[i, i] = true
    end
    for keyword in script.keywords, ruleid in keyword.decomps, itemid in script.rules[ruleid].items
        item = script.items[itemid]
        if item.kind in MOVES && haskey(script.keywordmap, item.arguments[1])
            reach[keyword.id, script.keywordmap[item.arguments[1]]] = true
        end
    end
    for k in 1:count, i in 1:count, j in 1:count
        reach[i, j] |= reach[i, k] && reach[k, j]
    end
    for keyword in script.keywords, rules in (keyword.memories, keyword.decomps)
        for (position, ruleid) in enumerate(rules)
            rule = script.rules[ruleid]
            missing = unknown(rule.pattern, script.groupwords)
            for name in missing
                add(rule.line, "SYNON_UNKNOWN", "unknown group $name")
            end
            isempty(rule.items) && add(rule.line, "RULE_NO_REASM", "rule has no reassembly")
            if isempty(missing)
                for earlierid in rules[1:position - 1]
                    earlier = script.rules[earlierid]
                    if isempty(unknown(earlier.pattern, script.groupwords)) && covers(earlier.pattern, rule.pattern, script.groupwords)
                        add(rule.line, "RULE_SHADOWED", "pattern is shadowed by line $(earlier.line)")
                        break
                    end
                end
            end
            wildcards = Base.count(wildcard, rule.pattern)
            for itemid in rule.items
                item = script.items[itemid]
                for number in references(item)
                    (number == 0 || number > wildcards) && add(item.line, "REF_UNBOUND", "reference ($number) is not bound")
                end
                item.kind ∉ MOVES && continue
                target = item.arguments[1]
                if !haskey(script.keywordmap, target)
                    add(item.line, "TARGET_UNDEFINED", "target $target is not a keyword")
                elseif reach[script.keywordmap[target], keyword.id]
                    add(item.line, "TARGET_CYCLE", "edge $(keyword.word) -> $target is on a cycle")
                end
            end
        end
    end
    sort!(found; by=diagnostic -> (diagnostic.line, findfirst(==(diagnostic.code), CODES)), alg=MergeSort)
    return found
end

end
