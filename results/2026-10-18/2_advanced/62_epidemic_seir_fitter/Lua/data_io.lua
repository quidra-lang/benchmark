local D = {}
local function words(line)
    local result = {}
    for word in line:gmatch("%S+") do result[#result + 1] = word end
    return result
end
local function real(word) return tonumber(word) + 0.0 end
function D.read()
    local result = { cases = {}, deaths = {}, groups = {}, contacts = {}, interventions = {}, params = { scenario = {}, contact_change = {} } }
    local cases = assert(io.open("input/cases.csv", "r"))
    cases:read("*l")
    for line in cases:lines() do
        local _, count, deaths = line:match("^(%d+),(%d+),(%d+)$")
        result.cases[#result.cases + 1], result.deaths[#result.deaths + 1] = tonumber(count), tonumber(deaths)
    end
    cases:close()
    for line in io.lines("input/population.txt") do
        local values = words(line)
        if values[1] == "group" then result.groups[#result.groups + 1] = { values[2], tonumber(values[3]), real(values[4]) }
        else local row = {}; for i = 2, #values do row[#row + 1] = real(values[i]) end; result.contacts[#result.contacts + 1] = row end
    end
    for line in io.lines("input/interventions.txt") do local values = words(line); result.interventions[#result.interventions + 1] = { tonumber(values[1]), real(values[2]) } end
    for line in io.lines("input/params.txt") do
        local values = words(line)
        local name, params = values[1], result.params
        if name == "scenario" then params.scenario[#params.scenario + 1] = { values[2], real(values[3]) }
        elseif name == "contact_change" then params.contact_change[#params.contact_change + 1] = { values[2], values[3], real(values[4]) }
        elseif name == "holdout" or name == "death_lag" or name == "generation" or name == "horizon" then params[name] = tonumber(values[2])
        elseif name == "milestones" or name == "golden" then
            params[name] = {}; for i = 2, #values do params[name][#params[name] + 1] = tonumber(values[i]) end
        elseif name == "beta_grid" or name == "rho_grid" then params[name] = { real(values[2]), real(values[3]), tonumber(values[4]) }
        elseif name == "nelder_mead" then params[name] = { real(values[2]), real(values[3]), real(values[4]), real(values[5]), tonumber(values[6]) }
        elseif name == "initial" or name == "simplex" then params[name] = { real(values[2]), real(values[3]) }
        else params[name] = real(values[2]) end
    end
    return result
end
function D.write(outputs)
    for name, lines in pairs(outputs) do
        local output = assert(io.open("output/" .. name, "w"))
        if #lines > 0 then output:write(table.concat(lines, "\n"), "\n") end
        output:close()
    end
end
return D
