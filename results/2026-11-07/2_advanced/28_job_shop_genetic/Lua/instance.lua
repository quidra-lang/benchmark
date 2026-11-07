local M = {}
function M.load_instance(path)
    local handle = assert(io.open(path, "rb"))
    local lines = {}
    for line in handle:lines() do
        lines[#lines + 1] = line
    end
    handle:close()
    local jobs_count, machine_count = lines[1]:match("^(%d+) (%d+)$")
    machine_count = tonumber(machine_count)
    local instance = {machine_count = machine_count, jobs = {}, job_map = {}, operations = {}, machines = {}, errors = {}, durations = {}}
    for number = 1, tonumber(jobs_count) do
        local steps, seen, message, index = {}, {}, nil, 0
        for token in lines[number + 1]:gmatch("%S+") do
            index = index + 1
            local machine, duration = token:match("^(%d+):(%d+)$")
            machine, duration = tonumber(machine), tonumber(duration)
            if machine < 1 or machine > machine_count then
                message = "unknown machine " .. machine
            elseif duration < 1 or duration > 99 then
                message = "bad duration " .. duration
            elseif seen[machine] then
                message = "repeated machine " .. machine
            end
            if message then
                break
            end
            steps[#steps + 1], seen[machine] = {machine = machine, duration = duration}, true
        end
        if message then
            instance.errors[#instance.errors + 1] = "job " .. number .. " operation " .. index .. ": " .. message
        else
            local job = {number = number, operations = {}, work = 0}
            for k, step in ipairs(steps) do
                local ident = #instance.operations + 1
                local operation = {ident = ident, job = number, index = k, machine = step.machine, duration = step.duration, head = job.work, code = "J" .. number .. "-" .. k}
                if k > 1 then
                    operation.job_prev = ident - 1
                    instance.operations[ident - 1].job_next = ident
                end
                job.operations[k], instance.operations[ident], instance.durations[ident] = ident, operation, step.duration
                job.work = job.work + step.duration
            end
            for _, ident in ipairs(job.operations) do
                local operation = instance.operations[ident]
                operation.tail = job.work - operation.head - operation.duration
            end
            instance.jobs[#instance.jobs + 1], instance.job_map[number] = job, job
        end
    end
    for number = 1, machine_count do
        local machine = {number = number, operations = {}, load = 0, head = 2147483647, tail = 2147483647}
        for ident, operation in ipairs(instance.operations) do
            if operation.machine == number then
                machine.operations[#machine.operations + 1] = ident
                machine.load, machine.head, machine.tail = machine.load + operation.duration, math.min(machine.head, operation.head), math.min(machine.tail, operation.tail)
            end
        end
        machine.bound = machine.head + machine.load + machine.tail
        instance.machines[number] = machine
    end
    return instance
end
return M
