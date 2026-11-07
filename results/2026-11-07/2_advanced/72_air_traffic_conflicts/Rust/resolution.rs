use crate::flight_plans::{AircraftType, Params, Plan};
pub struct Manoeuvre {
    pub name: String,
    pub kind: usize,
    pub amount: i64
}
pub fn manoeuvres(maximum: i64) -> Vec<Manoeuvre> {
    let mut result = vec![Manoeuvre {
        name: "level_up".to_owned(),kind: 0,amount: 10
    },Manoeuvre {
        name: "level_down".to_owned(),kind: 0,amount: -10
    },Manoeuvre {
        name: "speed_down".to_owned(),kind: 1,amount: 0
    }];
    let mut amount = 60;
    while amount <= maximum {
        result.push(Manoeuvre {
            name: format!("delay_{}",amount),
            kind: 2,
            amount
        });
        amount += 60;
    }
    result
}
pub fn apply(plan: &Plan, manoeuvre: &Manoeuvre, aircraft: &AircraftType, params: &Params) -> Option<Plan> {
    let mut next = plan.clone();
    match manoeuvre.kind {
        0 => next.offset += manoeuvre.amount,1 => next.speed = next.speed*9/10,_ => next.delay += manoeuvre.amount
    }
    if next.speed < aircraft.minimum || next.levels().iter().any(|&l| l < params.levels[0] || l > params.levels[1]) {
        None
    } else {
        next.manoeuvres.push(manoeuvre.name.clone());
        Some(next)
    }
}
pub fn lower_priority(a: &Plan, b: &Plan) -> bool {
    (a.departure+a.delay,&a.callsign) > (b.departure+b.delay,&b.callsign)
}
