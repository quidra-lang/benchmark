struct FormulaToken
    kind::String
    value::String
    column::Int
end
struct FormulaError <: Exception
    column::Int
    message::String
end
formula_error(column,message) = throw(FormulaError(column,message))
const GREEK = Set(split("alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega"))
const FUNCTIONS = ["sin","cos","tan","log","ln","exp","det","lim","max","min"]
const LARGE_OPERATORS = ["sum","prod","int"]
const ACCENTS = Set(["overline","hat","vec","dot","tilde","overbrace","underbrace"])
const CONSTRUCTS = Set(["frac","binom","overset","underset","sqrt","left","right"])
const RAW_COMMANDS = Set(["text","begin","end","tag","label","eqref"])
const ENVIRONMENTS = Set(["matrix","pmatrix","bmatrix","vmatrix","cases"])
const SYMBOLS = Set("+-*/=<>:()[],;.!|'")
const SYMBOL_COMMANDS = let table = Dict{String,Tuple{String,String}}()
    for name in GREEK
        table["\\" * name] = (name,"ordinary")
    end
    for name in [FUNCTIONS;LARGE_OPERATORS]
        table["\\" * name] = (name,"operator")
    end
    for (name,display,kind) in [("cdot","*","binary"),("times","x","binary"),("pm","+-","binary"),
        ("mp","-+","binary"),("leq","<=","relation"),("geq",">=","relation"),("neq","!=","relation"),
        ("approx","~=","relation"),("to","->","relation"),("infty","oo","ordinary"),
        ("ldots","...","ordinary"),("cdots","...","ordinary"),("quad","  ","ordinary"),
        (","," ","ordinary"),("{","{","open"),("}","}","close")]
        table["\\" * name] = (display,kind)
    end
    table
end
const COMMAND_NAMES = Set(name[2:end] for name in keys(SYMBOL_COMMANDS) if occursin(r"^[A-Za-z]+$",name[2:end]))
letter(c) = 'A' <= c <= 'Z' || 'a' <= c <= 'z'
digit(c) = '0' <= c <= '9'
character_at(text,i) = 1 <= i <= length(text) ? text[i] : '\0'
substring(text,a,b) = a <= b ? String(text[a:b]) : ""
function tokenize(text)
    tokens = FormulaToken[]
    position = 1
    while position <= length(text)
        c,column = text[position],position
        if c == ' '
            position += 1
        elseif letter(c)
            first = position
            while letter(character_at(text,position))
                position += 1
            end
            push!(tokens,FormulaToken("identifier",substring(text,first,position-1),column))
        elseif digit(c)
            first = position
            while digit(character_at(text,position))
                position += 1
            end
            if character_at(text,position) == '.' && digit(character_at(text,position+1))
                position += 2
                while digit(character_at(text,position))
                    position += 1
                end
            end
            push!(tokens,FormulaToken("number",substring(text,first,position-1),column))
        elseif c in SYMBOLS || c in "{}^_&"
            push!(tokens,FormulaToken(c in SYMBOLS ? "symbol" : string(c),string(c),column))
            position += 1
        elseif c == '\\'
            position += 1
            c = character_at(text,position)
            if c in "\\{},"
                push!(tokens,FormulaToken(c == '\\' ? "newline" : "command","\\" * string(c),column))
                position += 1
                continue
            end
            first = position
            while letter(character_at(text,position))
                position += 1
            end
            name = substring(text,first,position-1)
            isempty(name) && formula_error(column,"invalid command")
            if name in RAW_COMMANDS
                while character_at(text,position) == ' '
                    position += 1
                end
                character_at(text,position) == '{' || formula_error(position,"expected {")
                last = findnext(==('}'),text,position+1)
                last === nothing && formula_error(column,"unterminated argument")
                argument = substring(text,position+1,last-1)
                name in ("begin","end") && !(argument in ENVIRONMENTS) &&
                    formula_error(column,"unknown environment \"$argument\"")
                push!(tokens,FormulaToken(name,argument,column))
                position = last+1
            elseif haskey(SYMBOL_COMMANDS,"\\" * name)
                push!(tokens,FormulaToken("command","\\" * name,column))
            elseif name in ACCENTS
                push!(tokens,FormulaToken("accent",name,column))
            elseif name in CONSTRUCTS
                push!(tokens,FormulaToken(name,name,column))
            else
                formula_error(column,"unknown command \\" * name)
            end
        else
            formula_error(column,"invalid character " * string(c))
        end
    end
    push!(tokens,FormulaToken("eof","",length(text)+1))
    tokens
end
