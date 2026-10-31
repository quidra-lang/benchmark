function main()
    commands = [
        "undo",
        "type hello world",
        "delete 5",
        "type there",
        "undo",
        "undo",
        "redo",
        "type friend",
        "redo",
        "delete 20",
        "undo",
        "redo",
        "redo",
        "type see you",
    ]
    buffer = ""
    undo_stack, redo_stack = String[], String[]
    for command in commands
        if command == "undo"
            if isempty(undo_stack)
                println(command, " => nothing to undo")
                continue
            end
            push!(redo_stack, buffer)
            buffer = pop!(undo_stack)
        elseif command == "redo"
            if isempty(redo_stack)
                println(command, " => nothing to redo")
                continue
            end
            push!(undo_stack, buffer)
            buffer = pop!(redo_stack)
        else
            push!(undo_stack, buffer)
            empty!(redo_stack)
            if startswith(command, "type ")
                buffer *= command[6:end]
            else
                amount = parse(Int, command[8:end])
                buffer = first(buffer, max(0, length(buffer)-amount))
            end
        end
        println(command, " => \"", buffer, '"')
    end
end

main()
