include("terms.jl")
include("unify.jl")
include("database.jl")
include("reader.jl")
include("predicates.jl")

const CONTROLS = union(Set{PredicateIndicator}([( ",",2),("!",0),(";",2),("->",2),("\\+",1),("catch",3)]),Set(("call",arity) for arity in 1:8))
const BUILTIN_PREDICATES = union(DETERMINISTIC,Set{PredicateIndicator}([("findall",3),("throw",1),("between",3),("length",2)]))
function goal_conversion(term)
    term = dereference(term)
    term isa VariableTerm && return compound("call",term)
    term isa IntegerTerm && return nothing
    if term isa CompoundTerm && term.name in (",",";","->") && length(term.arguments) == 2
        left = goal_conversion(term.arguments[1])
        left === nothing && return nothing
        right = goal_conversion(term.arguments[2])
        return right === nothing ? nothing : compound(term.name,left,right)
    end
    term
end
function atom_name(name,quoted)
    plain = name in ("[]","!",";") || (!isempty(name) && lowercase_letter(name[1]) && all(alphanumeric,name)) ||
        (!isempty(name) && name != "." && all(character->character in SYMBOLS,name))
    (!quoted || plain) && return name
    "'" * replace(name,"\\"=>"\\\\","'"=>"\\'","\n"=>"\\n","\t"=>"\\t") * "'"
end
mutable struct TermWriter
    names::IdDict{VariableTerm,String}
    next_name::Int
    quoted::Bool
end
TermWriter(names=IdDict{VariableTerm,String}();quoted=true) = TermWriter(copy(names),1,quoted)
function write_term!(writer,term,limit=1200,operand=false)
    term = dereference(term)
    if term isa VariableTerm
        if !haskey(writer.names,term)
            writer.names[term] = "_G$(writer.next_name)"
            writer.next_name += 1
        end
        return writer.names[term]
    elseif term isa IntegerTerm
        return string(term.value)
    elseif term isa AtomTerm
        text = atom_name(term.name,writer.quoted)
        return operand && (haskey(INFIX,term.name) || haskey(PREFIX,term.name)) ? "(" * text * ")" : text
    end
    name,arguments = term.name,term.arguments
    if name == "." && length(arguments) == 2
        elements,tail = list_parts(term)
        text = "[" * join((write_term!(writer,element,999) for element in elements),",")
        !is_atom(tail,"[]") && (text *= "|" * write_term!(writer,tail,999))
        return text * "]"
    elseif length(arguments) == 2 && haskey(INFIX,name)
        priority,left_limit,right_limit = INFIX[name]
        left,right = write_term!(writer,arguments[1],left_limit,true),write_term!(writer,arguments[2],right_limit,true)
        if name == ","
            text = left * "," * right
        elseif lowercase_letter(name[1])
            text = left * " " * name * " " * right
        else
            before = !isempty(left) && left[end] in SYMBOLS ? " " : ""
            after = !isempty(right) && right[1] in SYMBOLS ? " " : ""
            text = left * before * name * after * right
        end
        return priority > limit ? "(" * text * ")" : text
    elseif length(arguments) == 1 && haskey(PREFIX,name)
        priority = PREFIX[name]
        argument = write_term!(writer,arguments[1],priority,true)
        space = !isempty(argument) && (argument[1] in SYMBOLS || digit(argument[1]) || argument[1] == '(') ? " " : ""
        text = name * space * argument
        return priority > limit ? "(" * text * ")" : text
    end
    atom_name(name,writer.quoted) * "(" * join((write_term!(writer,argument,999) for argument in arguments),",") * ")"
end
predicate_name(key) = write_term!(TermWriter(),indicator_term(key))

mutable struct PrologConsultant
    database::PrologDatabase
    lines::Vector{String}
    counts::Dict{String,Vector{Int}}
    last::Dict{String,Union{Nothing,PredicateIndicator}}
    discontiguous::Set{Tuple{String,String,Int}}
end
PrologConsultant() = PrologConsultant(PrologDatabase(),String[],Dict("prelude.pl"=>[0,0,0],"program.pl"=>[0,0,0]),
    Dict{String,Union{Nothing,PredicateIndicator}}("prelude.pl"=>nothing,"program.pl"=>nothing),Set{Tuple{String,String,Int}}())
function warning!(consultant,file,line,message)
    push!(consultant.lines,"$file:$line: warning: $message")
    consultant.counts[file][3] += 1
end
function consult_clause!(consultant,term,file,line,reader)
    head,body = term,nothing
    term isa CompoundTerm && indicator(term) == (":-",2) && ((head,body) = term.arguments)
    error = nothing
    if head isa VariableTerm
        error = AtomTerm("instantiation_error")
    elseif head isa IntegerTerm
        error = type_error("callable",head)
    elseif indicator(head) in CONTROLS || indicator(head) in BUILTIN_PREDICATES
        error = compound("permission_error",AtomTerm("modify"),AtomTerm("static_procedure"),indicator_term(indicator(head)))
    elseif body !== nothing
        converted = goal_conversion(body)
        if converted === nothing
            error = type_error("callable",body)
        else
            body = converted
        end
    end
    if error !== nothing
        push!(consultant.lines,"$file:$line: error: " * write_term!(TermWriter(),error))
        consultant.counts[file][2] += 1
        return
    end
    key = indicator(head)
    previous = get(consultant.database.predicates,key,PrologClause[])
    if file == "program.pl" && any(clause->clause.file == "prelude.pl",previous)
        warning!(consultant,file,line,"redefining prelude procedure " * predicate_name(key))
        empty!(consultant.database.predicates[key])
        previous = PrologClause[]
    end
    report_key = (file,key[1],key[2])
    if any(clause->clause.file == file,previous) && consultant.last[file] != key && !(report_key in consultant.discontiguous)
        warning!(consultant,file,line,"clauses of $(predicate_name(key)) are not together")
        push!(consultant.discontiguous,report_key)
    end
    add_clause!(consultant.database,PrologClause(head,body,file,line))
    consultant.last[file] = key
    consultant.counts[file][1] += 1
    singletons = filter(name->!startswith(name,"_") && reader.counts[name] == 1,reader.count_order)
    repeated = filter(name->length(name) > 1 && startswith(name,"_") && reader.counts[name] > 1,reader.count_order)
    !isempty(singletons) && warning!(consultant,file,line,"singleton variables: " * join(singletons,", "))
    !isempty(repeated) && warning!(consultant,file,line,"variables starting with _ occur more than once: " * join(repeated,", "))
end
function consult!(consultant,file,text)
    reader = PrologReader(text)
    source_lines = split(text,'\n';keepempty=true)
    while reader_token(reader).kind != "eof"
        line = reader_token(reader).line
        try
            term = read_clause!(reader)
            consult_clause!(consultant,term,file,line,reader)
        catch error
            error isa PrologSyntaxError || rethrow()
            token = error.token
            consultant.counts[file][2] += 1
            push!(consultant.lines,"$file:$(token.line):$(token.column): syntax error: $(error.message)")
            token.kind != "eof" && append!(consultant.lines,["    " * source_lines[token.line]," "^(token.column+3) * "^"])
            reader.index = token.index
            while !(reader_token(reader).kind in ("end","eof"))
                take_token!(reader)
            end
            reader_token(reader).kind == "end" && take_token!(reader)
        end
    end
end
function finish_consult!(consultant)
    reported = Set{PredicateIndicator}()
    for source in consultant.database.order,clause in consultant.database.predicates[source]
        pending = clause.body === nothing ? PrologTerm[] : PrologTerm[clause.body]
        while !isempty(pending)
            term = dereference(pop!(pending))
            term isa Union{VariableTerm,IntegerTerm} && continue
            key = indicator(term)
            if key in ((",",2),(";",2),("->",2))
                append!(pending,reverse(term.arguments))
            elseif key in (("\\+",1),("call",1))
                push!(pending,term.arguments[1])
            elseif key == ("findall",3)
                push!(pending,term.arguments[2])
            elseif key == ("catch",3)
                push!(pending,term.arguments[3],term.arguments[1])
            elseif !(key in CONTROLS) && !(key in BUILTIN_PREDICATES) && !haskey(consultant.database.predicates,key) && !(key in reported)
                push!(reported,key)
                warning!(consultant,clause.file,clause.line,"undefined procedure $(predicate_name(key)) called from $(predicate_name(source))")
            end
        end
    end
    for file in ("prelude.pl","program.pl")
        clauses,errors,warnings = consultant.counts[file]
        push!(consultant.lines,"$file: clauses=$clauses errors=$errors warnings=$warnings")
    end
    total = sum(length,values(consultant.database.predicates);init=0)
    push!(consultant.lines,"database: predicates=$(length(consultant.database.order)) clauses=$total")
end
function listing(database)
    lines = String[]
    for key in database.order
        !isempty(lines) && push!(lines,"")
        for clause in database.predicates[key]
            occurrences = variables_in(clause.head,clause.body)
            counts = IdDict{VariableTerm,Int}()
            for variable in occurrences
                counts[variable] = get(counts,variable,0)+1
            end
            names,number = IdDict{VariableTerm,String}(),0
            for variable in occurrences
                haskey(names,variable) && continue
                if counts[variable] == 1
                    names[variable] = "_"
                else
                    suffix = number < 26 ? "" : string(div(number,26))
                    names[variable] = string(Char(Int('A')+mod(number,26))) * suffix
                    number += 1
                end
            end
            writer = TermWriter(names)
            head = write_term!(writer,clause.head)
            if clause.body === nothing
                push!(lines,head * ".")
                continue
            end
            push!(lines,head * " :-")
            goals,body = PrologTerm[],clause.body
            while body isa CompoundTerm && indicator(body) == (",",2)
                push!(goals,body.arguments[1])
                body = body.arguments[2]
            end
            push!(goals,body)
            for (index,goal) in enumerate(goals)
                push!(lines,"    " * write_term!(writer,goal,999) * (index == length(goals) ? "." : ","))
            end
        end
    end
    lines
end
function answer(query_variables)
    names = IdDict{VariableTerm,String}()
    for (name,variable) in query_variables
        value = dereference(variable)
        value isa VariableTerm && !haskey(names,value) && (names[value] = name)
    end
    writer = TermWriter(names)
    previous,items = IdDict{VariableTerm,String}(),String[]
    for (name,variable) in query_variables
        value = dereference(variable)
        if value isa VariableTerm
            haskey(previous,value) && push!(items,"$(previous[value]) = $name")
            previous[value] = name
        else
            push!(items,"$name = " * write_term!(writer,value,699,true))
        end
    end
    isempty(items) ? "true" : join(items,", ")
end

abstract type PrologChoiceBase end
struct PrologMarker
    kind::String
    payload::Union{Int,PrologChoiceBase}
end
struct GoalEntry
    goal::Union{PrologTerm,PrologMarker}
    barrier::Int
    context::Union{Nothing,PrologChoiceBase}
end
struct GoalLink
    entry::GoalEntry
    rest::Union{Nothing,GoalLink}
end
function prepend(continuation,entries...)
    for entry in reverse(entries)
        continuation = GoalLink(entry,continuation)
    end
    continuation
end
Base.@kwdef mutable struct PrologChoicePoint <: PrologChoiceBase
    kind::String
    mark::Int
    resume::Union{Nothing,GoalLink}
    goal::Union{Nothing,PrologTerm} = nothing
    candidates::Vector{PrologClause} = PrologClause[]
    next_candidate::Int = 2
    barrier::Int = 0
    context::Union{Nothing,PrologChoiceBase} = nothing
    catcher::Union{Nothing,PrologTerm} = nothing
    recovery::Union{Nothing,PrologTerm} = nothing
    parent::Union{Nothing,PrologChoiceBase} = nothing
    upper::Int64 = 0
    target::Union{Nothing,PrologTerm} = nothing
    next_value::Int64 = 0
    tail::Union{Nothing,PrologTerm} = nothing
    number::Union{Nothing,PrologTerm} = nothing
    count::Int64 = 0
    template::Union{Nothing,PrologTerm} = nothing
    result::Union{Nothing,PrologTerm} = nothing
    results::Vector{PrologTerm} = PrologTerm[]
end
struct InferenceLimit <: Exception end
Base.@kwdef mutable struct PrologEngine
    database::PrologDatabase
    query_variables::Vector{Tuple{String,VariableTerm}}
    limit::Union{Nothing,Int}
    calls::Dict{PredicateIndicator,Int}
    tries::Dict{PredicateIndicator,Int}
    trail::BindingTrail = BindingTrail()
    goals::Union{Nothing,GoalLink}
    choices::Vector{PrologChoicePoint} = PrologChoicePoint[]
    context::Union{Nothing,PrologChoiceBase} = nothing
    current_key::PredicateIndicator = ("",0)
    solutions::Int = 0
    inferences::Int = 0
    choicepoints::Int = 0
    backtracks::Int = 0
    answers::Vector{String} = String[]
    output::Vector{String} = String[]
end
function PrologEngine(database,query,variables,limit,calls,tries)
    PrologEngine(database=database,query_variables=variables,limit=limit,calls=calls,tries=tries,
        goals=prepend(nothing,GoalEntry(compound("call",query),0,nothing)))
end
function create_choice!(engine,kind,resume;kwargs...)
    choice = PrologChoicePoint(;kind=kind,mark=trail_mark(engine.trail),resume=resume,kwargs...)
    push!(engine.choices,choice)
    engine.choicepoints += 1
    choice
end
function infer!(engine,key)
    engine.inferences == 20000 && throw(InferenceLimit())
    engine.inferences += 1
    engine.calls[key] = get(engine.calls,key,0)+1
end
function try_clause!(engine,clause,goal,barrier,context,continuation)
    key = indicator(goal)
    engine.tries[key] = get(engine.tries,key,0)+1
    head,body = copy_clause(clause)
    unify!(engine.trail,head,goal) || return false
    engine.goals = body === nothing ? continuation : prepend(continuation,GoalEntry(body,barrier,context))
    true
end
function user_call!(engine,goal,context)
    key = indicator(goal)
    haskey(engine.database.predicates,key) || throw(PrologFault(compound("existence_error",AtomTerm("procedure"),indicator_term(key))))
    candidates = candidate_clauses(engine.database,goal)
    isempty(candidates) && return false
    height = length(engine.choices)
    length(candidates) > 1 && create_choice!(engine,"CLAUSES",engine.goals;goal=goal,candidates=candidates,barrier=height,context=context)
    try_clause!(engine,candidates[1],goal,height,context,engine.goals)
end
function control!(engine,goal,barrier,context)
    key = indicator(goal)
    args = goal isa CompoundTerm ? goal.arguments : PrologTerm[]
    continuation,height = engine.goals,length(engine.choices)
    if key == (",",2)
        engine.goals = prepend(continuation,GoalEntry(args[1],barrier,context),GoalEntry(args[2],barrier,context))
    elseif key == ("!",0)
        resize!(engine.choices,barrier)
    elseif key == (";",2)
        create_choice!(engine,"ALT",prepend(continuation,GoalEntry(args[2],barrier,context)))
        left = dereference(args[1])
        if left isa CompoundTerm && indicator(left) == ("->",2)
            condition,then = left.arguments
            engine.goals = prepend(continuation,GoalEntry(condition,height+1,context),
                GoalEntry(PrologMarker("ITE",height),barrier,context),GoalEntry(then,barrier,context))
        else
            engine.goals = prepend(continuation,GoalEntry(left,barrier,context))
        end
    elseif key == ("->",2)
        engine.goals = prepend(continuation,GoalEntry(args[1],height,context),
            GoalEntry(PrologMarker("ITE",height),barrier,context),GoalEntry(args[2],barrier,context))
    elseif key == ("\\+",1)
        create_choice!(engine,"ALT",continuation)
        engine.goals = prepend(continuation,GoalEntry(compound("call",args[1]),barrier,context),GoalEntry(PrologMarker("NAF",height),barrier,context))
    elseif key[1] == "call"
        target = dereference(args[1])
        target isa VariableTerm && throw(PrologFault(AtomTerm("instantiation_error")))
        target isa IntegerTerm && throw(PrologFault(type_error("callable",target)))
        if length(args) > 1
            target = target isa AtomTerm ? CompoundTerm(target.name,args[2:end]) : CompoundTerm(target.name,[target.arguments;args[2:end]])
        end
        converted = goal_conversion(target)
        converted === nothing && throw(PrologFault(type_error("callable",target)))
        engine.goals = prepend(continuation,GoalEntry(converted,height,context))
    else
        frame = create_choice!(engine,"CATCH",continuation;catcher=args[2],recovery=args[3],parent=context)
        engine.goals = prepend(continuation,GoalEntry(compound("call",args[1]),barrier,frame),GoalEntry(PrologMarker("EXIT",frame),barrier,context))
    end
    true
end
function marker!(engine,marker)
    kind,payload = marker.kind,marker.payload
    if kind in ("ITE","NAF")
        resize!(engine.choices,payload)
        return kind == "ITE"
    elseif kind == "EXIT"
        !isempty(engine.choices) && engine.choices[end] === payload && pop!(engine.choices)
        return true
    end
    push!(payload.results,copy_term(payload.template))
    false
end
function between!(engine,args)
    lower = require_integer(args[1])
    upper = require_integer(args[2])
    value = dereference(args[3])
    value isa Union{VariableTerm,IntegerTerm} || throw(PrologFault(type_error("integer",value)))
    value isa IntegerTerm && return lower <= value.value <= upper
    lower > upper && return false
    lower < upper && create_choice!(engine,"BETWEEN",engine.goals;upper=upper,target=value,next_value=lower+1)
    unify!(engine.trail,value,IntegerTerm(lower))
end
function length_predicate!(engine,args)
    sequence,number = args[1],dereference(args[2])
    number isa Union{VariableTerm,IntegerTerm} || throw(PrologFault(type_error("integer",number)))
    number isa IntegerTerm && number.value < 0 && throw(PrologFault(domain_error("not_less_than_zero",number)))
    elements,tail = list_parts(sequence)
    count = length(elements)
    is_atom(tail,"[]") && return unify!(engine.trail,number,IntegerTerm(count))
    tail isa VariableTerm || throw(PrologFault(type_error("list",sequence)))
    if number isa IntegerTerm
        number.value < count && return false
        return unify!(engine.trail,tail,make_list(PrologTerm[VariableTerm() for _ in 1:number.value-count]))
    end
    create_choice!(engine,"LENGTH",engine.goals;tail=tail,number=number,count=count,next_value=count+1)
    unify!(engine.trail,tail,NIL) && unify!(engine.trail,number,IntegerTerm(count))
end
function step!(engine)
    entry = engine.goals.entry
    engine.goals = engine.goals.rest
    goal,barrier,context = entry.goal,entry.barrier,entry.context
    engine.context = context
    goal isa PrologMarker && return marker!(engine,goal)
    goal = dereference(goal)
    key = engine.current_key = indicator(goal)
    key in CONTROLS && return control!(engine,goal,barrier,context)
    infer!(engine,key)
    if key == ("findall",3)
        template,body,result = goal.arguments
        frame = create_choice!(engine,"FINDALL",engine.goals;template=template,result=result)
        engine.goals = prepend(nothing,GoalEntry(compound("call",body),barrier,context),GoalEntry(PrologMarker("COLLECT",frame),barrier,context))
        return true
    elseif key == ("throw",1)
        ball = dereference(goal.arguments[1])
        ball isa VariableTerm && throw(PrologFault(AtomTerm("instantiation_error")))
        throw(PrologBall(ball))
    elseif key == ("between",3)
        return between!(engine,goal.arguments)
    elseif key == ("length",2)
        return length_predicate!(engine,goal.arguments)
    elseif key in DETERMINISTIC
        output = (term,quoted)->push!(engine.output,term === nothing ? "\n" : write_term!(TermWriter(;quoted=quoted),term))
        return execute_deterministic(goal,engine.trail,output)
    end
    user_call!(engine,goal,context)
end
function backtrack!(engine)
    while true
        engine.backtracks += 1
        while !isempty(engine.choices)
            choice = engine.choices[end]
            undo!(engine.trail,choice.mark)
            if choice.kind == "CATCH"
                pop!(engine.choices)
            else
                break
            end
        end
        isempty(engine.choices) && return false
        choice = engine.choices[end]
        if choice.kind == "ALT"
            pop!(engine.choices)
            engine.goals = choice.resume
            return true
        elseif choice.kind == "CLAUSES"
            clause = choice.candidates[choice.next_candidate]
            if choice.next_candidate == length(choice.candidates)
                pop!(engine.choices)
            else
                choice.next_candidate += 1
            end
            try_clause!(engine,clause,choice.goal,choice.barrier,choice.context,choice.resume) && return true
        elseif choice.kind == "BETWEEN"
            infer!(engine,("between",3))
            value = choice.next_value
            value == choice.upper ? pop!(engine.choices) : (choice.next_value += 1)
            if unify!(engine.trail,choice.target,IntegerTerm(value))
                engine.goals = choice.resume
                return true
            end
        elseif choice.kind == "LENGTH"
            infer!(engine,("length",2))
            count = choice.next_value
            choice.next_value += 1
            value = make_list(PrologTerm[VariableTerm() for _ in 1:count-choice.count])
            if unify!(engine.trail,choice.tail,value) && unify!(engine.trail,choice.number,IntegerTerm(count))
                engine.goals = choice.resume
                return true
            end
        else
            pop!(engine.choices)
            if unify!(engine.trail,make_list(choice.results),choice.result)
                engine.goals = choice.resume
                return true
            end
        end
    end
end
function handle_exception!(engine,ball)
    ball = copy_term(ball)
    frame = engine.context
    while frame !== nothing
        index = findfirst(choice->choice === frame,engine.choices)
        resize!(engine.choices,index-1)
        undo!(engine.trail,frame.mark)
        mark = trail_mark(engine.trail)
        if unify!(engine.trail,copy_term(ball),frame.catcher)
            engine.goals = prepend(frame.resume,GoalEntry(compound("call",frame.recovery),length(engine.choices),frame.parent))
            return true
        end
        undo!(engine.trail,mark)
        frame = frame.parent
    end
    push!(engine.answers,"uncaught exception: " * write_term!(TermWriter(),ball))
    false
end
function run_query!(engine)
    while true
        try
            if engine.goals === nothing
                engine.solutions += 1
                text = answer(engine.query_variables)
                if engine.solutions == engine.limit || isempty(engine.choices)
                    push!(engine.answers,text * ".")
                    break
                end
                push!(engine.answers,text * " ;")
                success = backtrack!(engine)
            else
                success = step!(engine)
                !success && (success = backtrack!(engine))
            end
            if !success
                push!(engine.answers,"false.")
                break
            end
        catch error
            if error isa PrologFault
                handle_exception!(engine,compound("error",error.term,indicator_term(engine.current_key))) || break
            elseif error isa PrologBall
                handle_exception!(engine,error.term) || break
            elseif error isa InferenceLimit
                push!(engine.answers,"inference limit exceeded")
                break
            else
                rethrow()
            end
        end
    end
    [engine.solutions,engine.inferences,engine.choicepoints,engine.backtracks]
end
function statistics(prefix,counts)
    solutions,inferences,choices,backtracks = counts
    "$prefix solutions=$solutions inferences=$inferences choicepoints=$choices backtracks=$backtracks"
end
function main()
    consultant = PrologConsultant()
    for file in ("prelude.pl","program.pl")
        consult!(consultant,file,read(joinpath("input",file),String))
    end
    finish_consult!(consultant)
    answers,writes,stats = String[],String[],String[]
    calls,tries = Dict{PredicateIndicator,Int}(),Dict{PredicateIndicator,Int}()
    totals = zeros(Int,4)
    for (number,source) in enumerate(readlines("input/queries.txt"))
        push!(answers,source)
        push!(writes,"== query $number ==\n")
        marker = first(findfirst("?- ",source))
        limit = marker == 1 ? nothing : parse(Int,strip(source[1:marker-1]))
        body_start = marker+3
        reader = PrologReader(source[body_start:end],body_start)
        local query
        try
            query = read_clause!(reader,true)
        catch error
            error isa PrologSyntaxError || rethrow()
            push!(answers,"syntax error at column $(error.token.column): $(error.message)")
            push!(stats,"query $number: syntax error")
            continue
        end
        variables = Tuple{String,VariableTerm}[(name,reader.names[name]) for name in reader.name_order if !startswith(name,"_")]
        engine = PrologEngine(consultant.database,query,variables,limit,calls,tries)
        counts = run_query!(engine)
        totals .+= counts
        append!(answers,engine.answers)
        text = join(engine.output)
        push!(writes,text * (!isempty(text) && !endswith(text,"\n") ? "\n" : ""))
        push!(stats,statistics("query $number:",counts))
    end
    push!(stats,statistics("total:",totals),"== profile ==")
    for key in sort(collect(keys(calls));by=key->(-calls[key],predicate_name(key)))
        line = "$(predicate_name(key)) calls=$(calls[key])"
        haskey(consultant.database.predicates,key) && (line *= " tries=$(get(tries,key,0))")
        push!(stats,line)
    end
    reports = (("consult.txt",consultant.lines),("listing.txt",listing(consultant.database)),("answers.txt",answers),("stats.txt",stats))
    for (name,lines) in reports
        write(joinpath("output",name),join(lines,"\n") * (isempty(lines) ? "" : "\n"))
    end
    write("output/write_output.txt",join(writes))
end
main()
