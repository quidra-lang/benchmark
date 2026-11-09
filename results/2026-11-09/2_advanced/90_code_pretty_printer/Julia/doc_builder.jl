mutable struct Document
    kind::Symbol
    value::String
    children::Vector{Document}
    amount::Int
    broken::String
    flat::String
    forced::Bool
    mode::Symbol
end
function new_doc(kind;value="",children=Document[],amount=0,broken="",flat="",forced=false)
    Document(kind,value,children,amount,broken,flat,forced,:unset)
end
doc_text(value) = new_doc(:text;value=String(value))
const LINE = new_doc(:line)
const SOFTLINE = new_doc(:softline)
const HARDLINE = new_doc(:hardline)
const BREAK_PARENT = new_doc(:break_parent)
suffix(value) = new_doc(:suffix;value=value)
if_break(broken,flat) = new_doc(:if_break;broken=broken,flat=flat)
function concat(parts...)
    elements = Document[]
    function add(part)
        part === nothing && return
        part isa AbstractString && (part = doc_text(part))
        if part isa AbstractVector || part isa Tuple
            foreach(add,part)
        elseif part.kind == :concat
            foreach(add,part.children)
        elseif part.kind == :text
            isempty(part.value) && return
            if !isempty(elements) && elements[end].kind == :text
                elements[end] = doc_text(elements[end].value * part.value)
            else
                push!(elements,doc_text(part.value))
            end
        else
            push!(elements,part)
        end
    end
    foreach(add,parts)
    isempty(elements) && return doc_text("")
    length(elements) == 1 ? elements[1] : new_doc(:concat;children=elements)
end
function force_broken(document)
    document.kind in (:hardline,:break_parent) && return true
    any(force_broken,document.children)
end
function group(child)
    normalized = concat(child)
    new_doc(:group;children=[normalized],forced=force_broken(normalized))
end
nest(amount,child) = new_doc(:nest;children=[concat(child)],amount=amount)
align_doc(child) = new_doc(:align;children=[concat(child)])
function all_groups(document)
    document === nothing && return Document[]
    groups = document.kind == :group ? [document] : Document[]
    for child in document.children
        append!(groups,all_groups(child))
    end
    groups
end
