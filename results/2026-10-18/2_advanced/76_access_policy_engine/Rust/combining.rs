pub const NAMES: [&str;6] = ["PERMIT","DENY","NOT_APPLICABLE","INDETERMINATE{D}","INDETERMINATE{P}","INDETERMINATE{DP}"];
#[derive(Clone)] pub struct Decision {
    pub kind: usize,
    pub reason: String
}
impl Decision {
    pub fn new(kind: usize) -> Self {
        Self {
            kind,
            reason: String::new()
        }
    }
    pub fn notation(&self) -> String {
        if self.kind < 3 {
            NAMES[self.kind].to_owned()
        } else {
            format!("{} ({})",NAMES[self.kind],self.reason)
        }
    }
}
#[derive(Clone)] pub struct Target {
    pub kind: usize,
    pub reason: String
}
impl Target {
    pub fn name(&self) -> &str {
        ["MATCH","NO_MATCH","INDETERMINATE"][self.kind]
    }
}
pub trait Evaluator {
    fn evaluate(&mut self, element: usize) -> Decision;
    fn check(&mut self, element: usize) -> Target;
    fn id(&self, element: usize) -> &str;
}
pub struct Combined {
    pub decision: Decision,
    pub evaluated: Vec<usize>
}
pub fn run(evaluator: &mut impl Evaluator, algorithm: &str, children: &[usize]) -> Combined {
    if algorithm == "only-one-applicable" {
        let mut matched = None;
        for &child in children {
            let target = evaluator.check(child);
            if target.kind == 2 {
                return Combined {
                    decision: Decision {
                        kind: 5,
                        reason: target.reason
                    },
                    evaluated: Vec::new()
                };
            }
            if target.kind == 0 {
                if let Some(first) = matched {
                    return Combined {
                        decision: Decision {
                            kind: 5,
                            reason: format!("multiple applicable {} {}",evaluator.id(first),evaluator.id(child))
                        },
                        evaluated: Vec::new()
                    };
                }
                matched = Some(child);
            }
        }
        return if let Some(child) = matched {
            Combined {
                decision: evaluator.evaluate(child),
                evaluated: vec![child]
            }
        } else {
            Combined {
                decision: Decision::new(2),
                evaluated: Vec::new()
            }
        };
    }
    let mut decisions = Vec::new();
    let mut evaluated = Vec::new();
    for &child in children {
        let decision = evaluator.evaluate(child);
        evaluated.push(child);
        let stop = match algorithm {
            "deny-overrides" | "permit-unless-deny" => decision.kind == 1,"permit-overrides" | "deny-unless-permit" => decision.kind == 0,"first-applicable" => decision.kind != 2,_ => false
        };
        if stop {
            return Combined {
                decision,
                evaluated
            };
        }
        decisions.push(decision);
    }
    let has = |kind| decisions.iter().any(|d| d.kind == kind);
    let kind = match algorithm {
        "deny-overrides" => if has(5) || (has(3) && (has(4) || has(0))) {
            5
        } else if has(3) {
            3
        } else if has(0) {
            0
        } else if has(4) {
            4
        } else {
            2
        }, "permit-overrides" => if has(5) || (has(4) && (has(3) || has(1))) {
            5
        } else if has(4) {
            4
        } else if has(1) {
            1
        } else if has(3) {
            3
        } else {
            2
        }, "deny-unless-permit" => 1,"permit-unless-deny" => 0,_ => 2
    };
    let reason = if kind >= 3 {
        decisions.iter().find(|d| d.kind >= 3).unwrap().reason.clone()
    } else {
        String::new()
    };
    Combined {
        decision: Decision {
            kind,
            reason
        },
        evaluated
    }
}
