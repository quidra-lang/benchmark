using Printf

function real_text(value::Real)
    text = @sprintf("%.4f", Float64(value))
    text == "-0.0000" ? "0.0000" : text
end
rounded(value::Real) = round(Int, value * 10000)
proportion_text(numerator::Int, denominator::Int) = "$numerator/$denominator $(real_text(numerator / denominator))"
function fraction_text(numerator::Int, denominator::Int)
    denominator == 0 && return "- -"
    divisor = gcd(numerator, denominator)
    proportion_text(numerator ÷ divisor, denominator ÷ divisor)
end
struct Evaluation
    matrix::Matrix{Int}
    total::Int
    correct::Int
    micro_f1::Float64
    macro_f1::Float64
end
function Evaluation(class_count::Int, truths::Vector{Int}, predictions::Vector{Int})
    matrix = zeros(Int, class_count, class_count)
    for (truth, predicted) in zip(truths, predictions)
        matrix[truth, predicted] += 1
    end
    correct = sum(matrix[label, label] for label in 1:class_count)
    f1_sum = 0.0
    scored = 0
    for label in 1:class_count
        denominator = sum(matrix[label, :]) + sum(matrix[:, label])
        if denominator > 0
            f1_sum += (2 * matrix[label, label]) / denominator
            scored += 1
        end
    end
    Evaluation(matrix, length(truths), correct, correct / length(truths), f1_sum / scored)
end
evaluation_fields(evaluation::Evaluation) = "$(evaluation.correct),$(real_text(evaluation.micro_f1)),$(real_text(evaluation.macro_f1))"
function evaluation_lines(evaluation::Evaluation, names::Vector{String})
    lines = ["true\\predicted " * join(names, ' ')]
    for (label, name) in enumerate(names)
        push!(lines, name * " " * join(evaluation.matrix[label, :], ' '))
    end
    for (label, name) in enumerate(names)
        hits = evaluation.matrix[label, label]
        predicted = sum(evaluation.matrix[:, label])
        support = sum(evaluation.matrix[label, :])
        push!(lines, "class $name precision $(fraction_text(hits, predicted)) recall $(fraction_text(hits, support)) f1 $(fraction_text(2 * hits, predicted + support)) support $support")
    end
    push!(lines, "micro_f1 $(real_text(evaluation.micro_f1)) macro_f1 $(real_text(evaluation.macro_f1))")
    lines
end
