mutable struct Container
    id::String
    message::Union{Nothing,Message}
    parent::Union{Nothing,Container}
    children::Vector{Container}
    subject::Union{Nothing,String}
end
Container(id::String) = Container(id, nothing, nothing, Container[], nothing)
function ancestor_or_self(candidate::Container, other::Container)
    node = other
    while true
        candidate === node && return true
        isnothing(node.parent) && return false
        node = node.parent
    end
end
function adopt!(parent::Container, child::Container)
    child.parent = parent
    push!(parent.children, child)
end
function prune_containers(containers::Vector{Container}, at_root::Bool)
    result = Container[]
    for container in containers
        container.children = prune_containers(container.children, false)
        if !isnothing(container.message) || at_root && length(container.children) >= 2
            push!(result, container)
        else
            for child in container.children
                child.parent = at_root ? nothing : container.parent
            end
            append!(result, container.children)
        end
    end
    result
end
function container_key(container::Container)
    !isnothing(container.message) && return sort_key(container.message)
    minimum(container_key(child) for child in container.children)
end
function sort_containers!(containers::Vector{Container})
    for container in containers
        sort_containers!(container.children)
    end
    sort!(containers; by=container_key)
end
function root_subject(root::Container)
    message = isnothing(root.message) ? root.children[1].message : root.message
    message.base_subject
end
function build_threads(messages::Vector{Message})
    table = Dict{String,Container}()
    containers = Container[]
    function container_of(id::String)
        if !haskey(table, id)
            container = Container(id)
            table[id] = container
            push!(containers, container)
        end
        table[id]
    end
    for message in messages
        if isempty(message.id)
            container = Container("")
            push!(containers, container)
        else
            container = container_of(message.id)
        end
        container.message = message
        references = container_of.(message.references)
        for index in 1:(length(references) - 1)
            current, following = references[index], references[index + 1]
            isnothing(following.parent) && !ancestor_or_self(following, current) && adopt!(current, following)
        end
        if !isnothing(container.parent)
            filter!(child -> child !== container, container.parent.children)
            container.parent = nothing
        end
        !isempty(references) && !ancestor_or_self(container, references[end]) && adopt!(references[end], container)
    end
    roots = prune_containers(filter(container -> isnothing(container.parent), containers), true)
    sort_containers!(roots)
    groups = Dict{String,Vector{Container}}()
    for root in roots
        subject = root_subject(root)
        isempty(subject) || push!(get!(groups, subject, Container[]), root)
    end
    merged = filter(root -> isempty(root_subject(root)) || length(groups[root_subject(root)]) == 1, roots)
    for subject in sort!(collect(keys(groups)))
        group = groups[subject]
        length(group) >= 2 || continue
        missing = filter(root -> isnothing(root.message), group)
        originals = filter(root -> !isnothing(root.message) && !root.message.reply, group)
        target = if !isempty(missing)
            missing[1]
        elseif length(originals) == 1
            originals[1]
        else
            root = Container("")
            root.subject = subject
            root
        end
        for root in group
            root === target && continue
            if !isnothing(root.message)
                adopt!(target, root)
            else
                for child in root.children
                    adopt!(target, child)
                end
            end
        end
        push!(merged, target)
    end
    sort_containers!(merged)
end
