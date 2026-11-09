mod rbac;
mod policy_parser;
mod expressions;
mod combining;
mod analysis;
use std::collections::{BTreeMap,BTreeSet};
use std::fs;
use expressions::{Expr,Value};
use combining::{Decision,Target};
use policy_parser::Element;
type Attributes = BTreeMap<String,Value>;
fn value(source: &str) -> Value {
    if source == "true" || source == "false" {
        Value::Boolean(source == "true")
    } else if source.starts_with('[') {
        let inside = &source[1..source.len()-1];
        Value::Bag(if inside.is_empty() {
            Vec::new()
        } else {
            inside.split(',').map(str::to_owned).collect()
        })
    } else if let Ok(integer) = source.parse::<i64>() {
        Value::Integer(integer)
    } else {
        Value::String(source.to_owned())
    }
}
fn attributes(words: &[&str]) -> Attributes {
    words.iter().filter_map(|word| word.split_once('=')).map(|(name,source)| (name.to_owned(),value(source))).collect()
}
fn type_error(operation: &str) -> String {
    format!("type {}",operation)
}
fn boolean(result: Result<Value,String>, operation: &str) -> Result<bool,String> {
    match result {
        Ok(Value::Boolean(v)) => Ok(v),Ok(_) => Err(type_error(operation)),Err(error) => Err(error)
    }
}
fn expression(expr: &Expr, attributes: &Attributes, it: Option<&str>) -> Result<Value,String> {
    match expr {
        Expr::Literal(value) => Ok(value.clone()),Expr::Attribute(name) => attributes.get(name).cloned().ok_or_else(|| format!("missing {}",name)),Expr::It => Ok(Value::String(it.unwrap().to_owned())), Expr::Unary(operator,operand) => {
            let operand = expression(operand,attributes,it)?;
            match (operator.as_str(),operand) {
                ("-",Value::Integer(v)) => Ok(Value::Integer(-v)),("not",Value::Boolean(v)) => Ok(Value::Boolean(!v)),_ => Err(type_error(operator))
            }
        }
        Expr::Binary(operator,left,right) => {
            let left = expression(left,attributes,it);
            let right = expression(right,attributes,it);
            if operator == "and" || operator == "or" {
                let left = boolean(left,operator);
                let right = boolean(right,operator);
                let decisive = operator == "or";
                if left.as_ref().map_or(false,|&v| v == decisive) || right.as_ref().map_or(false,|&v| v == decisive) {
                    return Ok(Value::Boolean(decisive));
                }
                return Ok(Value::Boolean(if operator == "and" {
                    left? && right?
                } else {
                    left? || right?
                }));
            }
            let left = left?;
            let right = right?;
            match (operator.as_str(),left,right) {
                ("+",Value::Integer(a),Value::Integer(b)) => Ok(Value::Integer(a+b)),("-",Value::Integer(a),Value::Integer(b)) => Ok(Value::Integer(a-b)),("*",Value::Integer(a),Value::Integer(b)) => Ok(Value::Integer(a*b)), ("==",a,b) | ("!=",a,b) => {
                    let equal = match (a,b) {
                        (Value::Integer(a),Value::Integer(b)) => a == b,(Value::String(a),Value::String(b)) => a == b,(Value::Boolean(a),Value::Boolean(b)) => a == b,_ => return Err(type_error(operator))
                    };
                    Ok(Value::Boolean(if operator == "==" {
                        equal
                    } else {
                        !equal
                    }))
                }
                ("<",Value::Integer(a),Value::Integer(b)) => Ok(Value::Boolean(a < b)),("<=",Value::Integer(a),Value::Integer(b)) => Ok(Value::Boolean(a <= b)),(">",Value::Integer(a),Value::Integer(b)) => Ok(Value::Boolean(a > b)),(">=",Value::Integer(a),Value::Integer(b)) => Ok(Value::Boolean(a >= b)),("in",Value::String(a),Value::Bag(b)) => Ok(Value::Boolean(b.contains(&a))),_ => Err(type_error(operator))
            }
        }
        Expr::Call(name,arguments) => {
            if name == "present" {
                if let Expr::Attribute(reference) = &arguments[0] {
                    return Ok(Value::Boolean(attributes.contains_key(reference)));
                }
                unreachable!();
            }
            if name == "any_of" || name == "all_of" {
                let input = expression(&arguments[0],attributes,it)?;
                let Value::Bag(values) = input else {
                    return Err(type_error(name));
                };
                let decisive = name == "any_of";
                let mut error = None;
                let mut found = false;
                for item in values {
                    match boolean(expression(&arguments[1],attributes,Some(&item)),name) {
                        Ok(v) => found |= v == decisive,Err(reason) => if error.is_none() {
                            error = Some(reason);
                        }
                    }
                }
                if found {
                    return Ok(Value::Boolean(decisive));
                }
                if let Some(error) = error {
                    return Err(error);
                }
                return Ok(Value::Boolean(!decisive));
            }
            let values: Vec<_> = arguments.iter().map(|a| expression(a,attributes,it)).collect();
            let mut evaluated = Vec::new();
            for value in values {
                evaluated.push(value?);
            }
            match (name.as_str(),evaluated.as_slice()) {
                ("size",[Value::Bag(bag)]) => Ok(Value::Integer(bag.len() as i64)),("starts_with",[Value::String(a),Value::String(b)]) => Ok(Value::Boolean(a.starts_with(b))),_ => Err(type_error(name))
            }
        }
    }
}
fn target_combine(results: Vec<Target>, all: bool) -> Target {
    let decisive = if all {
        1
    } else {
        0
    };
    if results.iter().any(|r| r.kind == decisive) {
        return Target {
            kind: decisive,
            reason: String::new()
        };
    }
    if let Some(error) = results.iter().find(|r| r.kind == 2) {
        return error.clone();
    }
    Target {
        kind: usize::from(!all),
        reason: String::new()
    }
}
fn target(element: &Element, attributes: &Attributes) -> Target {
    let mut lines = Vec::new();
    for line in &element.targets {
        let mut alternatives = Vec::new();
        for alternative in line {
            let mut clauses = Vec::new();
            for clause in alternative {
                let literal = expression(&clause.literal,attributes,None).unwrap();
                let present = attributes.get(&clause.reference);
                let items = match present {
                    Some(Value::Bag(values)) => values.iter().cloned().map(Value::String).collect(),Some(value) => vec![value.clone()],None => Vec::new()
                };
                let mut matched = false;
                let mut error = None;
                for item in items {
                    let result = match (clause.operator.as_str(),item,&literal) {
                        ("==",Value::Integer(a),Value::Integer(b)) => Some(a == *b),("==",Value::String(a),Value::String(b)) => Some(a == *b),("==",Value::Boolean(a),Value::Boolean(b)) => Some(a == *b), ("<",Value::Integer(a),Value::Integer(b)) => Some(a < *b),("<=",Value::Integer(a),Value::Integer(b)) => Some(a <= *b),(">",Value::Integer(a),Value::Integer(b)) => Some(a > *b),(">=",Value::Integer(a),Value::Integer(b)) => Some(a >= *b),("^=",Value::String(a),Value::String(b)) => Some(a.starts_with(b)),_ => None
                    };
                    if let Some(result) = result {
                        matched |= result;
                    } else if error.is_none() {
                        error = Some(type_error(&clause.operator));
                    }
                }
                clauses.push(if matched {
                    Target {
                        kind: 0,
                        reason: String::new()
                    }
                } else if let Some(reason) = error {
                    Target {
                        kind: 2,
                        reason
                    }
                } else if present.is_none() && clause.mandatory {
                    Target {
                        kind: 2,
                        reason: format!("missing {}",clause.reference)
                    }
                } else {
                    Target {
                        kind: 1,
                        reason: String::new()
                    }
                });
            }
            alternatives.push(target_combine(clauses,true));
        }
        lines.push(target_combine(alternatives,false));
    }
    target_combine(lines,true)
}
fn condition(element: &Element, attributes: &Attributes) -> Result<bool,String> {
    element.condition.as_ref().map_or(Ok(true),|e| boolean(expression(e,attributes,None),"condition"))
}
fn standalone(element: &Element, attributes: &Attributes) -> usize {
    let target = target(element,attributes);
    if target.kind == 1 {
        2
    } else if target.kind == 2 {
        if element.effect == 0 {
            4
        } else {
            3
        }
    } else {
        match condition(element,attributes) {
            Ok(true) => element.effect,Ok(false) => 2,Err(_) => if element.effect == 0 {
                4
            } else {
                3
            }
        }
    }
}
#[derive(Clone)] struct Outcome {
    decision: Decision,
    decisive: Option<usize>,
    obligations: Vec<String>,
    advice: Vec<String>
}
#[derive(Clone)] enum Record {
    Checked(Target),
    Evaluated {
        target: Target,
        condition: Option<String>,
        outcome: Outcome
    }
}
struct Evaluation<'a> {
    elements: &'a [Element],
    attributes: &'a Attributes,
    records: Vec<Option<Record>>
}
impl<'a> Evaluation<'a> {
    fn new(elements: &'a [Element], attributes: &'a Attributes) -> Self {
        Self {
            elements,
            attributes,
            records: vec![None;elements.len()]
        }
    }
    fn outcome(&self, index: usize) -> &Outcome {
        if let Some(Record::Evaluated {
            outcome,..
        }) = &self.records[index] {
            outcome
        } else {
            unreachable!()
        }
    }
    fn element(&mut self, index: usize) -> Outcome {
        let target = target(&self.elements[index],self.attributes);
        let mut condition_text = None;
        let mut decisive = None;
        let mut supporters = Vec::new();
        let decision = if self.elements[index].kind == "rule" {
            let effect = self.elements[index].effect;
            if target.kind == 1 {
                Decision::new(2)
            } else if target.kind == 2 {
                Decision {
                    kind: if effect == 0 {
                        4
                    } else {
                        3
                    },
                    reason: target.reason.clone()
                }
            } else {
                match condition(&self.elements[index],self.attributes) {
                    Ok(true) => {
                        condition_text = Some("TRUE".to_owned());
                        decisive = Some(index);
                        Decision::new(effect)
                    },Ok(false) => {
                        condition_text = Some("FALSE".to_owned());
                        Decision::new(2)
                    },Err(reason) => {
                        condition_text = Some("INDETERMINATE".to_owned());
                        Decision {
                            kind: if effect == 0 {
                                4
                            } else {
                                3
                            },
                            reason
                        }
                    }
                }
            }
        } else if target.kind == 1 {
            Decision::new(2)
        } else {
            let algorithm = self.elements[index].algorithm.clone();
            let children = self.elements[index].children.clone();
            let combined = combining::run(self,&algorithm,&children);
            let mut decision = combined.decision;
            if target.kind == 2 && decision.kind != 2 {
                if decision.kind < 2 {
                    decision.kind = if decision.kind == 0 {
                        4
                    } else {
                        3
                    };
                }
                decision.reason = target.reason.clone();
            }
            if decision.kind < 2 {
                supporters = combined.evaluated.into_iter().filter(|&child| self.outcome(child).decision.kind == decision.kind).collect();
                decisive = supporters.first().and_then(|&child| self.outcome(child).decisive).or(Some(index));
            }
            decision
        };
        let mut outcome = Outcome {
            decision,
            decisive,
            obligations: Vec::new(),
            advice: Vec::new()
        };
        if outcome.decision.kind < 2 {
            for supporter in supporters {
                outcome.obligations.extend(self.outcome(supporter).obligations.clone());
                outcome.advice.extend(self.outcome(supporter).advice.clone());
            }
            let effect = outcome.decision.kind;
            for advice in [false,true].iter().copied() {
                for attachment in self.elements[index].attachments.iter().filter(|a| a.advice == advice && a.effect == effect) {
                    let values: Vec<_> = attachment.arguments.iter().map(|(_,expr)| expression(expr,self.attributes,None)).collect();
                    if let Some(error) = values.iter().find_map(|value| value.as_ref().err()) {
                        if !advice {
                            outcome.decision = Decision {
                                kind: if outcome.decision.kind == 0 {
                                    4
                                } else {
                                    3
                                },
                                reason: format!("obligation {}: {}",attachment.id,error)
                            };
                            outcome.decisive = None;
                            outcome.obligations.clear();
                            outcome.advice.clear();
                            break;
                        }
                    } else {
                        let mut item = attachment.id.clone();
                        for ((name,_),value) in attachment.arguments.iter().zip(values) {
                            item.push_str(&format!(" {}={}",name,value.unwrap().notation()));
                        }
                        if advice {
                            outcome.advice.push(item);
                        } else {
                            outcome.obligations.push(item);
                        }
                    }
                }
                if outcome.decision.kind >= 3 {
                    break;
                }
            }
        }
        self.records[index] = Some(Record::Evaluated {
            target,
            condition: condition_text,
            outcome: outcome.clone()
        });
        outcome
    }
    fn tree(&self, index: usize, depth: usize, lines: &mut Vec<String>) {
        let e = &self.elements[index];
        let indent = " ".repeat(2+2*depth);
        match &self.records[index] {
            None => lines.push(format!("{}{} {} skipped",indent,e.kind,e.id)), Some(Record::Checked(target)) => lines.push(format!("{}{} {} {} target {}{}",indent,e.kind,e.id,e.algorithm,target.name(),if target.kind == 2 {
                format!(" ({})",target.reason)
            } else {
                String::new()
            })), Some(Record::Evaluated {
                target,condition,outcome
            }) => {
                if e.kind == "rule" {
                    lines.push(format!("{}rule {} {} target {}{} -> {}",indent,e.id,combining::NAMES[e.effect],target.name(),condition.as_ref().map_or_else(String::new,|c| format!(" condition {}",c)),outcome.decision.notation()));
                } else {
                    lines.push(format!("{}{} {} {} target {} -> {}",indent,e.kind,e.id,e.algorithm,target.name(),outcome.decision.notation()));
                    if target.kind != 1 {
                        for &child in &e.children {
                            self.tree(child,depth+1,lines);
                        }
                    }
                }
            }
        }
    }
}
impl combining::Evaluator for Evaluation<'_> {
    fn evaluate(&mut self, element: usize) -> Decision {
        self.element(element).decision
    }
    fn check(&mut self, element: usize) -> Target {
        let target = target(&self.elements[element],self.attributes);
        self.records[element] = Some(Record::Checked(target.clone()));
        target
    }
    fn id(&self, element: usize) -> &str {
        &self.elements[element].id
    }
}
struct Resource {
    kind: String,
    attributes: Attributes
}
struct Data {
    subjects: BTreeMap<String,Attributes>,
    resources: BTreeMap<String,Resource>,
    domains: Vec<(String,Vec<Value>)>,
    reference: Attributes
}
impl Data {
    fn read() -> Self {
        let mut data = Self {
            subjects: BTreeMap::new(),
            resources: BTreeMap::new(),
            domains: Vec::new(),
            reference: BTreeMap::new()
        };
        for line in fs::read_to_string("input/attributes.txt").unwrap().lines() {
            let w: Vec<_> = line.split_whitespace().collect();
            match w[0] {
                "SUBJECT" => {
                    data.subjects.insert(w[1].to_owned(),attributes(&w[2..]));
                },"RESOURCE" => {
                    data.resources.insert(w[1].to_owned(),Resource {
                        kind: w[2].to_owned(),
                        attributes: attributes(&w[3..])
                    });
                },"DOMAIN" => data.domains.push((w[1].to_owned(),w[2..].iter().map(|s| value(s)).collect())),_ => data.reference = attributes(&w[1..])
            }
        }
        data
    }
}
struct Request {
    id: String,
    user: String,
    roles: String,
    action: String,
    resource: String,
    environment: Attributes,
    explain: bool
}
fn requests() -> Vec<Request> {
    fs::read_to_string("input/requests.txt").unwrap().lines().map(|line| {
        let w: Vec<_> = line.split_whitespace().collect();
        Request {
            id: w[0].to_owned(),
            user: w[1].to_owned(),
            roles: w[2].to_owned(),
            action: w[3].to_owned(),
            resource: w[4].to_owned(),
            environment: attributes(&w[5..]),
            explain: w.last() == Some(&"EXPLAIN")
        }
    }).collect()
}
struct Activation {
    candidates: Vec<(String,Option<String>)>,
    session: BTreeSet<String>,
    granting: Option<String>,
    attributes: Attributes
}
fn activate(request: &Request, data: &Data, rbac: &rbac::Rbac, day: usize) -> Activation {
    let authorized = rbac.authorized(&request.user,day);
    let candidates: Vec<_> = if request.roles == "-" {
        Vec::new()
    } else if request.roles == "*" {
        authorized.iter().cloned().collect()
    } else {
        request.roles.split(',').map(str::to_owned).collect()
    };
    let mut seen = BTreeSet::new();
    let mut active = BTreeSet::new();
    let mut recorded = Vec::new();
    for candidate in candidates {
        let reason = if !rbac.roles.contains(&candidate) {
            Some("unknown".to_owned())
        } else if seen.contains(&candidate) {
            Some("duplicate".to_owned())
        } else if !authorized.contains(&candidate) {
            Some("unauthorized".to_owned())
        } else {
            let mut trial = active.clone();
            trial.insert(candidate.clone());
            let closure = rbac.closure(&trial);
            rbac.dsd.iter().find(|c| closure.intersection(&c.roles).count() >= c.cardinality).map(|c| format!("dsd {}",c.name))
        };
        seen.insert(candidate.clone());
        if reason.is_none() {
            active.insert(candidate.clone());
        }
        recorded.push((candidate,reason));
    }
    let session = rbac.closure(&active);
    let resource = &data.resources[&request.resource];
    let granting = session.iter().find(|role| rbac.permissions.contains(&((*role).clone(),request.action.clone(),resource.kind.clone()))).cloned();
    let mut attributes = Attributes::new();
    for (name,value) in &data.subjects[&request.user] {
        attributes.insert(format!("subject.{}",name),value.clone());
    }
    attributes.insert("subject.id".to_owned(),Value::String(request.user.clone()));
    attributes.insert("subject.role".to_owned(),Value::Bag(session.iter().cloned().collect()));
    attributes.insert("subject.rbac".to_owned(),Value::Boolean(granting.is_some()));
    for (name,value) in &resource.attributes {
        attributes.insert(format!("resource.{}",name),value.clone());
    }
    attributes.insert("resource.id".to_owned(),Value::String(request.resource.clone()));
    attributes.insert("resource.type".to_owned(),Value::String(resource.kind.clone()));
    attributes.insert("action.id".to_owned(),Value::String(request.action.clone()));
    for (name,value) in &request.environment {
        attributes.insert(format!("environment.{}",name),value.clone());
    }
    Activation {
        candidates: recorded,
        session,
        granting,
        attributes
    }
}
fn day(environment: &Attributes) -> Option<usize> {
    if let Some(Value::Integer(day)) = environment.get("day") {
        if (1..=365).contains(day) {
            return Some(*day as usize);
        }
    }
    None
}
fn decision_line(outcome: &Outcome, elements: &[Element]) -> String {
    format!("{}{}",outcome.decision.notation(),outcome.decisive.map_or_else(String::new,|i| format!(" by {}",elements[i].id)))
}
fn permission_report(data: &Data, rbac: &rbac::Rbac, elements: &[Element]) -> Vec<String> {
    let users: BTreeSet<_> = rbac.assignments.iter().map(|a| a.user.clone()).collect();
    let mut blocks = Vec::new();
    for user in users {
        let mut lines = vec![format!("user {}",user)];
        let mut assigned = BTreeMap::<String,BTreeSet<usize>>::new();
        let mut authorized = BTreeMap::<String,BTreeSet<usize>>::new();
        for assignment in rbac.assignments.iter().filter(|a| a.user == user) {
            assigned.entry(assignment.role.clone()).or_default().extend(assignment.first..=assignment.last);
        }
        for (role,days) in &assigned {
            lines.push(format!("  assigned {} {}",role,analysis::days(days)));
            for child in rbac.closure(&std::iter::once(role.clone()).collect()) {
                authorized.entry(child).or_default().extend(days);
            }
        }
        for (role,days) in &authorized {
            lines.push(format!("  authorized {} {}",role,analysis::days(days)));
        }
        let mut permissions = BTreeMap::<(String,String),(BTreeSet<usize>,BTreeSet<String>)>::new();
        for (role,action,kind) in &rbac.permissions {
            if let Some(days) = authorized.get(role) {
                let entry = permissions.entry((action.clone(),kind.clone())).or_default();
                entry.0.extend(days);
                entry.1.insert(role.clone());
            }
        }
        for ((action,kind),(days,via)) in permissions {
            let effective = if !data.subjects.contains_key(&user) {
                "-".to_owned()
            } else {
                let resources: Vec<_> = data.resources.iter().filter(|(_,r)| r.kind == kind).map(|(id,_)| id).collect();
                let mut count = 0;
                for resource in &resources {
                    let request = Request {
                        id: String::new(),
                        user: user.clone(),
                        roles: "*".to_owned(),
                        action: action.clone(),
                        resource: (*resource).clone(),
                        environment: data.reference.clone(),
                        explain: false
                    };
                    let activation = activate(&request,data,rbac,day(&data.reference).unwrap());
                    let mut evaluation = Evaluation::new(elements,&activation.attributes);
                    count += usize::from(evaluation.element(0).decision.kind == 0);
                }
                format!("{}/{}",count,resources.len())
            };
            lines.push(format!("  permission {} {} {} via {} effective {}",action,kind,analysis::days(&days),via.into_iter().collect::<Vec<_>>().join(","),effective));
        }
        blocks.push(lines.join("\n"));
    }
    if blocks.is_empty() {
        Vec::new()
    } else {
        vec![blocks.join("\n\n")]
    }
}
fn domain_analysis(data: &Data, elements: &[Element], rules: &[usize]) -> Vec<String> {
    let points = analysis::points(&data.domains);
    let mut counts = vec![0usize;elements.len()];
    let mut examples = vec![None;elements.len()];
    let mut blockers = vec![BTreeSet::new();elements.len()];
    let mut unblocked = vec![false;elements.len()];
    let mut pairs = Vec::new();
    for (p,policy) in elements.iter().enumerate().filter(|(_,p)| p.kind == "policy") {
        for (i,&a) in policy.children.iter().enumerate() {
            for &b in &policy.children[i+1..] {
                if elements[a].effect != elements[b].effect {
                    pairs.push((p,a,b,0usize));
                }
            }
        }
    }
    for attributes in &points {
        let mut standalone_values = vec![2;elements.len()];
        let mut applies = vec![false;elements.len()];
        for &rule in rules {
            standalone_values[rule] = standalone(&elements[rule],attributes);
            if standalone_values[rule] >= 2 {
                continue;
            }
            let mut parent = elements[rule].parent;
            let mut matched = true;
            while let Some(index) = parent {
                if target(&elements[index],attributes).kind != 0 {
                    matched = false;
                }
                parent = elements[index].parent;
            }
            applies[rule] = matched;
        }
        for &rule in rules {
            if !applies[rule] {
                continue;
            }
            counts[rule] += 1;
            if examples[rule].is_none() {
                examples[rule] = Some(data.domains.iter().filter(|(_,values)| values.len() >= 2).map(|(reference,_)| format!("{}={}",reference,attributes[reference].notation())).collect::<Vec<_>>().join(" "));
            }
            let parent = elements[rule].parent.unwrap();
            if elements[parent].algorithm == "first-applicable" {
                let children = &elements[parent].children;
                let position = children.iter().position(|&i| i == rule).unwrap();
                if let Some(blocker) = analysis::blocker(&children[..position],&standalone_values) {
                    blockers[rule].insert(blocker);
                } else {
                    unblocked[rule] = true;
                }
            }
        }
        for pair in &mut pairs {
            if applies[pair.1] && applies[pair.2] {
                pair.3 += 1;
            }
        }
    }
    let mut lines = vec![format!("applicability {}",points.len())];
    for &rule in rules {
        lines.push(format!("  {} {} {}",elements[rule].id,counts[rule],examples[rule].as_deref().unwrap_or("-")));
    }
    let dead: Vec<_> = rules.iter().copied().filter(|&r| counts[r] == 0).collect();
    lines.push(format!("dead {}",dead.len()));
    for r in dead {
        lines.push(format!("  {}",elements[r].id));
    }
    let shadowed: Vec<_> = rules.iter().copied().filter(|&r| counts[r] > 0 && elements[elements[r].parent.unwrap()].algorithm == "first-applicable" && !unblocked[r]).collect();
    lines.push(format!("shadowed {}",shadowed.len()));
    for r in shadowed {
        lines.push(format!("  {} by {}",elements[r].id,blockers[r].iter().map(|&b| elements[b].id.as_str()).collect::<Vec<_>>().join(",")));
    }
    let conflicts: Vec<_> = pairs.into_iter().filter(|p| p.3 > 0).collect();
    lines.push(format!("conflicts {}",conflicts.len()));
    for (p,a,b,count) in conflicts {
        let winner = analysis::winner(&elements[p].algorithm,a,b,elements[a].effect);
        lines.push(format!("  {} {} {} {} {}",elements[p].id,elements[a].id,elements[b].id,count,elements[winner].id));
    }
    lines
}
fn main() {
    let rbac = rbac::Rbac::read();
    let elements = policy_parser::read();
    let data = Data::read();
    let requests = requests();
    let rules: Vec<_> = elements.iter().enumerate().filter(|(_,e)| e.kind == "rule").map(|(i,_)| i).collect();
    let mut coverage = vec![String::new();elements.len()];
    let mut decisions = Vec::new();
    let mut traces = Vec::new();
    let mut decision_counts = [0usize;5];
    let mut refused = 0;
    let mut decisive = vec![0;elements.len()];
    let mut obligations = BTreeMap::<String,usize>::new();
    let mut advice = BTreeMap::<String,usize>::new();
    let mut grants = BTreeMap::<(String,String,String),usize>::new();
    for request in &requests {
        let error = if !data.subjects.contains_key(&request.user) {
            Some(format!("unknown user {}",request.user))
        } else if !data.resources.contains_key(&request.resource) {
            Some(format!("unknown resource {}",request.resource))
        } else if day(&request.environment).is_none() {
            Some("bad day".to_owned())
        } else {
            None
        };
        let mut trace = vec![format!("request {}",request.id)];
        if let Some(error) = error {
            decisions.push(format!("{} ERROR {}",request.id,error));
            trace.push(format!("  error {}",error));
            decision_counts[4] += 1;
            for &rule in &rules {
                coverage[rule].push('.');
            }
        } else {
            let day = day(&request.environment).unwrap();
            let activation = activate(request,&data,&rbac,day);
            let mut evaluation = Evaluation::new(&elements,&activation.attributes);
            let outcome = evaluation.element(0);
            let first = decision_line(&outcome,&elements);
            decisions.push(format!("{} {}",request.id,first));
            for (role,reason) in &activation.candidates {
                if let Some(reason) = reason {
                    refused += 1;
                    decisions.push(format!("  refused {} {}",role,reason));
                }
            }
            for (items,counts,label) in [(&outcome.obligations,&mut obligations,"obligation"),(&outcome.advice,&mut advice,"advice")].iter_mut() {
                for item in *items {
                    decisions.push(format!("  {} {}",label,item));
                    let id = item.split_whitespace().next().unwrap().to_owned();
                    *counts.entry(id).or_insert(0) += 1;
                }
            }
            decision_counts[if outcome.decision.kind >= 3 {
                3
            } else {
                outcome.decision.kind
            }] += 1;
            if let Some(index) = outcome.decisive {
                decisive[index] += 1;
            }
            if let Some(role) = &activation.granting {
                *grants.entry((role.clone(),request.action.clone(),data.resources[&request.resource].kind.clone())).or_insert(0) += 1;
            }
            for &rule in &rules {
                let symbol = match &evaluation.records[rule] {
                    Some(Record::Evaluated {
                        outcome,..
                    }) => match outcome.decision.kind {
                        0 => 'P',1 => 'D',2 => '-',_ => 'I'
                    },_ => '.'
                };
                coverage[rule].push(symbol);
            }
            trace.push(format!("  user {} resource {} type {} action {} day {}",request.user,request.resource,data.resources[&request.resource].kind,request.action,day));
            for (role,reason) in &activation.candidates {
                trace.push(format!("  activate {} {}",role,reason.as_ref().map_or_else(|| "ok".to_owned(),|r| format!("refused {}",r))));
            }
            trace.push(format!("  roles {}",if activation.session.is_empty() {
                "-".to_owned()
            } else {
                activation.session.iter().cloned().collect::<Vec<_>>().join(",")
            }));
            trace.push(activation.granting.as_ref().map_or_else(|| "  rbac no".to_owned(),|r| format!("  rbac yes {}",r)));
            evaluation.tree(0,0,&mut trace);
            trace.push(format!("  decision {}",first));
        }
        if request.explain {
            traces.push(trace.join("\n"));
        }
    }
    let mut analysis_lines = vec![format!("rbac {}",rbac.diagnostics.len())];
    for (line,keyword,message) in &rbac.diagnostics {
        analysis_lines.push(format!("  line {} {} {}",line,keyword,message));
    }
    analysis_lines.push(format!("grants {}",rbac.permissions.len()));
    for (role,action,kind) in &rbac.permissions {
        analysis_lines.push(format!("  {} {} {} {}",role,action,kind,grants.get(&(role.clone(),action.clone(),kind.clone())).unwrap_or(&0)));
    }
    analysis_lines.extend(domain_analysis(&data,&elements,&rules));
    analysis_lines.push(format!("coverage {}",requests.len()));
    let mut uncovered = Vec::new();
    for &rule in &rules {
        let count = coverage[rule].bytes().filter(|&c| c == b'P' || c == b'D').count();
        analysis_lines.push(format!("  {} {} {}",elements[rule].id,coverage[rule],count));
        if count == 0 {
            uncovered.push(rule);
        }
    }
    analysis_lines.push(format!("uncovered {}",uncovered.len()));
    for rule in uncovered {
        analysis_lines.push(format!("  {}",elements[rule].id));
    }
    analysis_lines.push("summary".to_owned());
    for (name,count) in ["PERMIT","DENY","NOT_APPLICABLE","INDETERMINATE","ERROR"].iter().zip(decision_counts.iter()) {
        analysis_lines.push(format!("  decision {} {}",name,count));
    }
    analysis_lines.push(format!("  refused {}",refused));
    for (i,&count) in decisive.iter().enumerate() {
        if count > 0 {
            analysis_lines.push(format!("  decisive {} {}",elements[i].id,count));
        }
    }
    for (id,count) in obligations {
        analysis_lines.push(format!("  obligation {} {}",id,count));
    }
    for (id,count) in advice {
        analysis_lines.push(format!("  advice {} {}",id,count));
    }
    let permissions = permission_report(&data,&rbac,&elements);
    fs::create_dir_all("output").unwrap();
    for (file,lines) in [("decisions.txt",decisions),("traces.txt",if traces.is_empty() {
        Vec::new()
    } else {
        vec![traces.join("\n\n")]
    }),("permissions.txt",permissions),("analysis.txt",analysis_lines)] {
        let contents = if lines.is_empty() {
            String::new()
        } else {
            lines.join("\n")+"\n"
        };
        fs::write(format!("output/{}",file),contents).unwrap();
    }
}
