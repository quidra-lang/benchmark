function seird(population,sigma,fatality,beta,gamma)
    function rates(state,multiplier)
        susceptible,exposed,infectious = state[1:3]
        flow = beta*multiplier*susceptible*infectious/population
        progression,removal = sigma*exposed,gamma*infectious
        [
            -flow,
            flow-progression,
            progression-removal,
            (1-fatality)*gamma*infectious,
            fatality*gamma*infectious,
            progression
        ]
    end
end
function sir(population,beta,gamma)
    function rates(state,multiplier)
        susceptible,infectious = state[1:2]
        flow = beta*multiplier*susceptible*infectious/population
        removal = gamma*infectious
        [-flow,flow-removal,removal,flow]
    end
end
function age_seird(populations,fatalities,sigma,beta,gamma,contacts)
    function rates(state,multiplier)
        result = Float64[]
        for (g,population) in enumerate(populations)
            start = 6(g-1)
            susceptible,exposed,infectious = state[start+1:start+3]
            pressure = 0.0
            for (h,other_population) in enumerate(populations)
                pressure += contacts[g,h]*state[6(h-1)+3]/other_population
            end
            force = beta*multiplier*pressure
            flow = force*susceptible
            progression,removal = sigma*exposed,gamma*infectious
            append!(
                result,
                [
                    -flow,
                    flow-progression,
                    progression-removal,
                    (1-fatalities[g])*gamma*infectious,
                    fatalities[g]*gamma*infectious,
                    progression
                ]
            )
        end
        result
    end
end
function generation(sigma,gamma)
    function rates(state,multiplier)
        exposed,infectious = state[1:2]
        progression,removal = sigma*exposed,gamma*infectious
        [-progression,progression-removal,removal]
    end
end
