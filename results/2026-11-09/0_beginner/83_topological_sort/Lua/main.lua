local function topological(courses, edges)
    local indegree, adjacency = {}, {}
    for _, course in ipairs(courses) do
        indegree[course] = 0
        adjacency[course] = {}
    end
    for _, edge in ipairs(edges) do
        local source, target = table.unpack(edge)
        adjacency[source][#adjacency[source] + 1] = target
        indegree[target] = indegree[target] + 1
    end
    table.sort(courses)
    local order, taken = {}, {}
    while true do
        local ready
        for _, course in ipairs(courses) do
            if not taken[course] and indegree[course] == 0 then
                ready = course
                break
            end
        end
        if not ready then break end
        order[#order + 1] = ready
        taken[ready] = true
        for _, target in ipairs(adjacency[ready]) do indegree[target] = indegree[target] - 1 end
    end
    local remaining = {}
    for _, course in ipairs(courses) do
        if not taken[course] then remaining[#remaining + 1] = course end
    end
    return order, remaining
end

local courses1 = {"physics", "algebra", "graphics", "programming", "statistics", "calculus", "databases", "algorithms"}
local edges1 = {
    {"calculus", "physics"}, {"algebra", "calculus"}, {"programming", "algorithms"},
    {"algebra", "statistics"}, {"algorithms", "databases"}, {"statistics", "databases"},
    {"calculus", "graphics"}, {"algorithms", "graphics"}, {"physics", "graphics"},
}
local courses2 = {"music", "ecology", "art", "geology", "biology", "chemistry"}
local edges2 = {
    {"music", "art"}, {"art", "ecology"}, {"biology", "chemistry"}, {"chemistry", "ecology"},
    {"ecology", "geology"}, {"geology", "chemistry"},
}
local first = topological(courses1, edges1)
local second, remaining = topological(courses2, edges2)
io.write("order: ", table.concat(first, " -> "), "\norder: ", table.concat(second, " -> "),
    "\ncycle: ", table.concat(remaining, " "), "\n")
