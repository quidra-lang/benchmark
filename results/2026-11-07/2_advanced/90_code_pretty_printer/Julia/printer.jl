struct PrintCommand
    indentation::Int
    mode::Symbol
    document::Document
end
function fits(remaining,candidate,rest)
    remaining < 0 && return false
    check = [candidate]
    next_existing = length(rest)
    while true
        if isempty(check)
            next_existing == 0 && return true
            push!(check,rest[next_existing])
            next_existing -= 1
        end
        command = pop!(check)
        indentation,mode,doc = command.indentation,command.mode,command.document
        kind = doc.kind
        if kind == :text
            remaining -= length(doc.value)
        elseif kind == :if_break
            remaining -= length(mode == :break ? doc.broken : doc.flat)
        elseif kind == :line
            mode == :break && return true
            remaining -= 1
        elseif kind == :softline
            mode == :break && return true
        elseif kind == :hardline
            return true
        elseif kind == :concat
            append!(check,[PrintCommand(indentation,mode,child) for child in reverse(doc.children)])
        elseif kind == :group
            push!(check,PrintCommand(indentation,doc.forced ? :break : mode,doc.children[1]))
        elseif kind in (:nest,:align)
            push!(check,PrintCommand(indentation,mode,doc.children[1]))
        end
        remaining < 0 && return false
    end
end
function print_document(document,profile)
    width,column = profile["width"],profile["comment_column"]
    result,pending = String[],String[]
    current = ""
    stack = [PrintCommand(0,:break,document)]
    function finalize()
        output = trim_spaces(current)
        if !isempty(pending)
            comment_text = join(pending," ")
            if column > 0 && length(output) < column-1 && column-1+length(comment_text) <= width
                output *= repeat(" ",column-1-length(output)) * comment_text
            else
                output *= " " * comment_text
            end
            empty!(pending)
        end
        push!(result,output)
    end
    while !isempty(stack)
        command = pop!(stack)
        indentation,mode,doc = command.indentation,command.mode,command.document
        kind = doc.kind
        if kind == :text
            current *= doc.value
        elseif kind == :if_break
            current *= mode == :break ? doc.broken : doc.flat
        elseif kind in (:line,:softline,:hardline)
            if kind == :hardline || mode == :break
                finalize()
                current = repeat(" ",indentation)
            elseif kind == :line
                current *= " "
            end
        elseif kind == :concat
            append!(stack,[PrintCommand(indentation,mode,child) for child in reverse(doc.children)])
        elseif kind == :nest
            push!(stack,PrintCommand(indentation+doc.amount,mode,doc.children[1]))
        elseif kind == :align
            push!(stack,PrintCommand(length(current),mode,doc.children[1]))
        elseif kind == :suffix
            push!(pending,doc.value)
        elseif kind == :group
            next_mode = mode == :flat ? :flat : doc.forced ? :forced :
                fits(width-length(current),PrintCommand(indentation,:flat,doc.children[1]),stack) ? :flat : :break
            doc.mode = next_mode
            push!(stack,PrintCommand(indentation,next_mode == :flat ? :flat : :break,doc.children[1]))
        end
    end
    finalize()
    result
end
