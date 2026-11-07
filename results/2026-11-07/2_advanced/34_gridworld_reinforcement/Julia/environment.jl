const ACTION_LETTERS = "NESW"
const ROW_STEPS = (-1,0,1,0)
const COLUMN_STEPS = (0,1,0,-1)
struct World
    rows::Int
    cols::Int
    kinds::Vector{Char}
    wind::Vector{Int}
    rewards::Vector{Int}
    states::Vector{Int}
    terminals::Vector{Int}
    state_index::Vector{Int}
    terminal_index::Vector{Int}
    start::Int
    start_state::Int
end
function read_world(path)
    lines = readlines(path)
    rows,cols = parse(Int,split(lines[1])[2]),parse(Int,split(lines[2])[2])
    kinds = collect(join(lines[3:rows+2]))
    wind = [parse(Int,string(digit)) for digit in split(lines[rows+3])[2]]
    rewards = parse.(Int,split(lines[rows+4])[2:end])
    states,terminals = Int[],Int[]
    state_index,terminal_index = zeros(Int,length(kinds)),zeros(Int,length(kinds))
    for (cell,kind) in enumerate(kinds)
        if kind in ('G','P')
            push!(terminals,cell)
            terminal_index[cell] = length(terminals)
        elseif kind != '#'
            push!(states,cell)
            state_index[cell] = length(states)
        end
    end
    start = findfirst(==('S'),kinds)
    World(rows,cols,kinds,wind,rewards,states,terminals,state_index,terminal_index,start,state_index[start])
end
is_terminal(world,cell) = world.terminal_index[cell] != 0
terminal_name(world,cell) = world.kinds[cell] == 'G' ? "goal" : "pit"
function move(world,cell,direction)
    target = cell+ROW_STEPS[direction]*world.cols+COLUMN_STEPS[direction]
    world.kinds[target] == '#' && (target=cell)
    is_terminal(world,target) && return target
    for _ in 1:world.wind[(cell-1)%world.cols+1]
        above = target-world.cols
        world.kinds[above] == '#' && break
        target = above
        is_terminal(world,target) && break
    end
    target
end
mutable struct RandomGenerator
    value::Int
end
function draw!(generator)
    generator.value = mod(48271*generator.value,2147483647)
end
struct Environment
    world::World
    step_reward::Int
    slip_total::Int
    floor_slip::Int
    ice_slip::Int
    moves::Matrix{Int}
    transitions::Matrix{Vector{Tuple{Int,Int}}}
end
function Environment(world,step_reward,total,floor_slip,ice_slip)
    moves = [move(world,cell,direction) for cell in world.states, direction in 1:4]
    transitions = Matrix{Vector{Tuple{Int,Int}}}(undef,length(world.states),4)
    for state in eachindex(world.states), action in 1:4
        slip = world.kinds[world.states[state]] == '~' ? ice_slip : floor_slip
        outcomes = ((action,total-2*slip),(mod1(action+1,4),slip),(mod1(action-1,4),slip))
        transitions[state,action] = [(
            moves[state,direction],
            weight
        ) for (direction,weight) in outcomes if weight > 0]
    end
    Environment(world,step_reward,total,floor_slip,ice_slip,moves,transitions)
end
reward(environment,cell) = is_terminal(
    environment.world,
    cell
) ? environment.world.rewards[environment.world.terminal_index[cell]] : environment.step_reward
function step!(environment,generator,state,action)
    sample = draw!(generator)%environment.slip_total
    slip = environment.world.kinds[environment.world.states[state]] == '~' ? environment.ice_slip : environment.floor_slip
    direction = sample < environment.slip_total-2*slip ? action : sample < environment.slip_total-slip ? mod1(action+1,4) : mod1(
        action-1,
        4
    )
    cell = environment.moves[state,direction]
    cell,reward(environment,cell)
end
