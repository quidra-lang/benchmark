const DETERMINISTIC = Set{PredicateIndicator}([("true",0),("fail",0),("false",0),("=",2),("\\=",2),("==",2),("\\==",2),
    ("var",1),("nonvar",1),("atom",1),("number",1),("integer",1),("atomic",1),("compound",1),("callable",1),("is_list",1),
    ("is",2),("=:=",2),("=\\=",2),("<",2),(">",2),("=<",2),(">=",2),("functor",3),("arg",3),("=..",2),
    ("copy_term",2),("atom_length",2),("atom_chars",2),("write",1),("writeq",1),("nl",0)])
const EVALUABLE = Set{PredicateIndicator}([("+",2),("-",2),("*",2),("//",2),("mod",2),("rem",2),("-",1),("abs",1),("min",2),("max",2)])
function checked_integer(value)
    -2147483648 <= value <= 2147483647 || throw(PrologFault(compound("evaluation_error",AtomTerm("int_overflow"))))
    value
end
function evaluate_arithmetic(term)
    term = dereference(term)
    term isa VariableTerm && throw(PrologFault(AtomTerm("instantiation_error")))
    term isa IntegerTerm && return term.value
    key = indicator(term)
    (term isa AtomTerm || !(key in EVALUABLE)) && throw(PrologFault(type_error("evaluable",indicator_term(key))))
    values = [evaluate_arithmetic(argument) for argument in term.arguments]
    name = term.name
    if length(values) == 1
        result = name == "-" ? -values[1] : abs(values[1])
    else
        a,b = values
        name in ("//","mod","rem") && b == 0 && throw(PrologFault(compound("evaluation_error",AtomTerm("zero_divisor"))))
        result = name == "+" ? a+b : name == "-" ? a-b : name == "*" ? a*b : name == "//" ? div(a,b) : name == "mod" ? mod(a,b) : name == "rem" ? rem(a,b) : name == "min" ? min(a,b) : max(a,b)
    end
    checked_integer(result)
end
function require_integer(term)
    term = dereference(term)
    term isa VariableTerm && throw(PrologFault(AtomTerm("instantiation_error")))
    term isa IntegerTerm || throw(PrologFault(type_error("integer",term)))
    term.value
end
function require_atom(term)
    term = dereference(term)
    term isa VariableTerm && throw(PrologFault(AtomTerm("instantiation_error")))
    term isa AtomTerm || throw(PrologFault(type_error("atom",term)))
    term.name
end
function require_list(term)
    elements,tail = list_parts(term)
    tail isa VariableTerm && throw(PrologFault(AtomTerm("instantiation_error")))
    is_atom(tail,"[]") || throw(PrologFault(type_error("list",term)))
    elements
end
function execute_deterministic(goal,trail,output)
    name,arity = indicator(goal)
    args = goal isa CompoundTerm ? dereference.(goal.arguments) : PrologTerm[]
    name == "true" && return true
    name in ("fail","false") && return false
    name == "=" && return unify!(trail,args...)
    if name == "\\="
        mark = trail_mark(trail)
        result = unify!(trail,args...)
        undo!(trail,mark)
        return !result
    elseif name in ("==","\\==")
        result = identical_terms(args...)
        return name == "==" ? result : !result
    elseif name in ("var","nonvar","atom","number","integer","atomic","compound","callable","is_list")
        term = args[1]
        name == "var" && return term isa VariableTerm
        name == "nonvar" && return !(term isa VariableTerm)
        name == "atom" && return term isa AtomTerm
        name in ("number","integer") && return term isa IntegerTerm
        name == "atomic" && return term isa Union{AtomTerm,IntegerTerm}
        name == "compound" && return term isa CompoundTerm
        name == "callable" && return term isa Union{AtomTerm,CompoundTerm}
        return is_atom(list_parts(term)[2],"[]")
    elseif name == "is"
        return unify!(trail,args[1],IntegerTerm(evaluate_arithmetic(args[2])))
    elseif name in ("=:=","=\\=","<",">","=<",">=")
        left = evaluate_arithmetic(args[1])
        right = evaluate_arithmetic(args[2])
        return name == "=:=" ? left == right : name == "=\\=" ? left != right : name == "<" ? left < right : name == ">" ? left > right : name == "=<" ? left <= right : left >= right
    elseif name == "functor"
        term,functor,count = args
        if !(term isa VariableTerm)
            term isa CompoundTerm && return unify!(trail,functor,AtomTerm(term.name)) && unify!(trail,count,IntegerTerm(length(term.arguments)))
            return unify!(trail,functor,term) && unify!(trail,count,IntegerTerm(0))
        end
        (functor isa VariableTerm || count isa VariableTerm) && throw(PrologFault(AtomTerm("instantiation_error")))
        functor isa CompoundTerm && throw(PrologFault(type_error("atomic",functor)))
        count isa IntegerTerm || throw(PrologFault(type_error("integer",count)))
        count.value < 0 && throw(PrologFault(domain_error("not_less_than_zero",count)))
        count.value > 255 && throw(PrologFault(compound("representation_error",AtomTerm("max_arity"))))
        count.value == 0 && return unify!(trail,term,functor)
        functor isa IntegerTerm && throw(PrologFault(type_error("atom",functor)))
        return unify!(trail,term,CompoundTerm(functor.name,PrologTerm[VariableTerm() for _ in 1:count.value]))
    elseif name == "arg"
        number,term,value = args
        (number isa VariableTerm || term isa VariableTerm) && throw(PrologFault(AtomTerm("instantiation_error")))
        number isa IntegerTerm || throw(PrologFault(type_error("integer",number)))
        term isa CompoundTerm || throw(PrologFault(type_error("compound",term)))
        return 1 <= number.value <= length(term.arguments) && unify!(trail,term.arguments[number.value],value)
    elseif name == "=.."
        term,sequence = args
        term isa CompoundTerm && return unify!(trail,make_list(PrologTerm[AtomTerm(term.name);term.arguments]),sequence)
        !(term isa VariableTerm) && return unify!(trail,make_list([term]),sequence)
        elements = require_list(sequence)
        isempty(elements) && throw(PrologFault(domain_error("non_empty_list",NIL)))
        head = dereference(elements[1])
        head isa VariableTerm && throw(PrologFault(AtomTerm("instantiation_error")))
        if length(elements) == 1
            head isa CompoundTerm && throw(PrologFault(type_error("atomic",head)))
            return unify!(trail,term,head)
        end
        head isa AtomTerm || throw(PrologFault(type_error("atom",head)))
        length(elements) > 256 && throw(PrologFault(compound("representation_error",AtomTerm("max_arity"))))
        return unify!(trail,term,CompoundTerm(head.name,elements[2:end]))
    elseif name == "copy_term"
        return unify!(trail,copy_term(args[1]),args[2])
    elseif name == "atom_length"
        atom = require_atom(args[1])
        args[2] isa Union{VariableTerm,IntegerTerm} || throw(PrologFault(type_error("integer",args[2])))
        return unify!(trail,IntegerTerm(length(atom)),args[2])
    elseif name == "atom_chars"
        atom,sequence = args
        if !(atom isa VariableTerm)
            text = require_atom(atom)
            return unify!(trail,sequence,make_list(PrologTerm[AtomTerm(string(character)) for character in text]))
        end
        characters = String[]
        for element in require_list(sequence)
            character = dereference(element)
            character isa VariableTerm && throw(PrologFault(AtomTerm("instantiation_error")))
            (character isa AtomTerm && length(character.name) == 1) || throw(PrologFault(type_error("character",character)))
            push!(characters,character.name)
        end
        return unify!(trail,atom,AtomTerm(join(characters)))
    elseif name in ("write","writeq")
        output(args[1],name == "writeq")
    else
        output(nothing,false)
    end
    true
end
