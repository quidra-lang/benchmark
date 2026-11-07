seird_rates =: 4 : 0
    'population sigma fatality beta gamma' =. x
    'state multiplier' =. y
    's e infectious' =. 3{.state
    flow =. (((beta*multiplier)*s)*infectious)%population
    progression =. sigma*e
    removal =. gamma*infectious
    recovered =. ((1-fatality)*gamma)*infectious
    deaths =. (fatality*gamma)*infectious
    (-flow),(flow-progression),(progression-removal),recovered,deaths,progression
)
sir_rates =: 4 : 0
    'population beta gamma' =. x
    'state multiplier' =. y
    flow =. (((beta*multiplier)*0{state)*1{state)%population
    removal =. gamma*1{state
    (-flow),(flow-removal),removal,flow
)
age_rates =: 4 : 0
    'populations fatalities sigma beta gamma contacts' =. x
    'state multiplier' =. y
    rates =. i.0
    for_g. i.#populations do.
        start =. 6*g
        pressure =. 0.0
        for_h. i.#populations do.
            term =. ((<g,h){contacts)*((6*h)+2){state
            pressure =. pressure+term%h{populations
        end.
        force =. (beta*multiplier)*pressure
        's e infectious' =. (start+i.3){state
        flow =. force*s
        progression =. sigma*e
        removal =. gamma*infectious
        recovered =. ((1-g{fatalities)*gamma)*infectious
        deaths =. ((g{fatalities)*gamma)*infectious
        rates =. rates,(-flow),(flow-progression),(progression-removal),recovered,deaths,progression
    end.
    rates
)
generation_rates =: 4 : 0
    'sigma gamma' =. x
    state =. 0{::y
    progression =. sigma*0{state
    removal =. gamma*1{state
    (-progression),(progression-removal),removal
)
