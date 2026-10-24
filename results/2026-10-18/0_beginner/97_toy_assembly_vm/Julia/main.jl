function main()
    program = ["SET A 1","SET B 1","SET D 8","MUL A B","PRINT A","ADD B 1","SUB D 1","JNZ D -4","SET A 1071","SET B 462","SET C A","MOD C B","SET A B","SET B C","JNZ B -4","PRINT A","HALT"]
    registers = Dict("A"=>0,"B"=>0,"C"=>0,"D"=>0)
    value(token) = haskey(registers,token) ? registers[token] : parse(Int,token)
    pc,executed = 0,0
    while 0 <= pc < length(program)
        parts = split(program[pc+1])
        operation = parts[1]
        executed += 1
        operation == "HALT" && break
        if operation == "JNZ"
            pc += value(parts[2]) != 0 ? parse(Int,parts[3]) : 1
            continue
        elseif operation == "PRINT"
            println(value(parts[2]))
        else
            register,operand = parts[2],value(parts[3])
            if operation == "SET"
                registers[register] = operand
            elseif operation == "ADD"
                registers[register] += operand
            elseif operation == "SUB"
                registers[register] -= operand
            elseif operation == "MUL"
                registers[register] *= operand
            elseif operation == "MOD"
                registers[register] %= operand
            end
        end
        pc += 1
    end
    println("executed: ",executed)
end
main()
