local program = {"SET A 1","SET B 1","SET D 8","MUL A B","PRINT A","ADD B 1","SUB D 1","JNZ D -4","SET A 1071","SET B 462","SET C A","MOD C B","SET A B","SET B C","JNZ B -4","PRINT A","HALT"}
local registers = {A=0,B=0,C=0,D=0}
local function value(token) return registers[token] or tonumber(token) end
local pc,executed = 0,0
while pc >= 0 and pc < #program do
    local parts = {}
    for part in program[pc+1]:gmatch("%S+") do parts[#parts+1] = part end
    local operation = parts[1]
    executed = executed+1
    if operation == "HALT" then break end
    if operation == "JNZ" then
        pc = pc+(value(parts[2]) ~= 0 and tonumber(parts[3]) or 1)
    else
        if operation == "PRINT" then io.write(string.format("%d\n",value(parts[2])))
        else
            local register,operand = parts[2],value(parts[3])
            if operation == "SET" then registers[register] = operand
            elseif operation == "ADD" then registers[register] = registers[register]+operand
            elseif operation == "SUB" then registers[register] = registers[register]-operand
            elseif operation == "MUL" then registers[register] = registers[register]*operand
            elseif operation == "MOD" then registers[register] = registers[register]%operand end
        end
        pc = pc+1
    end
end
io.write(string.format("executed: %d\n",executed))
