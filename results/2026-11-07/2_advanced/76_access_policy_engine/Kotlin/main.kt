import java.io.File
object PolicyEngine {
    lateinit var rbac: Rbac;
    lateinit var root: PolicyParser.Element;
    lateinit var elements: List<PolicyParser.Element>;
    lateinit var rules: List<PolicyParser.Element>;
    val subjects=sortedMapOf<String,Map<String,Any>>();
    val resources=sortedMapOf<String,Resource>();
    val domains=mutableListOf<Analysis.Domain>();
    lateinit var reference: Map<String,Any>;
    val requests=mutableListOf<Request>();
    val coverage=mutableMapOf<String,StringBuilder>();
    val grantCounts=mutableMapOf<Rbac.Grant,Int>();
    val decisions=mutableMapOf<String,Int>();
    val decisiveCounts=mutableMapOf<String,Int>();
    val obligationCounts=sortedMapOf<String,Int>();
    val adviceCounts=sortedMapOf<String,Int>();
    var refused=0
    data class Failure(val reason: String)
    data class Target(val result: String,val reason: String?=null)
    data class Item(val identifier: String,val text: String)
    data class Resource(val type: String,val attributes: Map<String,Any>)
    data class Request(val identifier: String,val user: String,val roles: String,val action: String,val resource: String,
        val environment: Map<String,Any>,val explain: Boolean)
    data class Activation(val role: String,val reason: String?)
    data class Prepared(val activations: List<Activation>,val roles: List<String>,val grant: String?,
        val values: Map<String,Any>)
    data class ConflictPair(val policy: PolicyParser.Element,val earlier: PolicyParser.Element,val later: PolicyParser.Element)
    class Evaluation(val element: PolicyParser.Element,val target: Target) {
        var decisive: PolicyParser.Element?=null;
        var decision=Combining.NA;
        var reason: String?=null;
        var condition: Any?=null;
        var children: List<Combining.State?> = emptyList();
        val obligations=mutableListOf<Item>();
        val advice=mutableListOf<Item>()
    }
    fun definite(decision: String)=decision=="PERMIT"||decision=="DENY"
    fun inputValue(text: String): Any=when {
        text=="true"||text=="false"->text=="true";
        text.startsWith('[')->if(text=="[]")emptyList<String>() else text.substring(1,text.length-1).split(',');
        text.matches(Regex("-?[0-9]+"))->text.toInt();
        else->text
    }
    fun attributes(fields: List<String>)=fields.associate {
        val equals=it.indexOf('=');
        it.substring(0,equals) to inputValue(it.substring(equals+1))
    }
    fun valueNotation(value: Any): String=when(value) {
        is Boolean->if(value)"true" else "false";
        is Int->value.toString();
        is String->"\"$value\"";
        else->"["+(value as List<*>).joinToString(",") {
            valueNotation(it!!)
        }+"]"
    }
    fun firstError(values: List<Any>)=values.firstOrNull {
        it is Failure
    }
    as Failure?
    fun booleanResult(values: List<Any>,veto: Boolean,name: String): Any {
        var first: Failure?=null;
        var found=false;
        for(value in values)if(value is Boolean) {
            if(value==veto)found=true
        } else if(first==null)first=if(value is Failure)value else Failure("type $name");
        return if(found)veto else first?:!veto
    }
    fun operation(name: String,values: List<Any>): Any {
        val error=firstError(values);
        if(error!=null)return error;
        if(name in setOf("+","-","*","<","<=",">",">=")) {
            if(values.all {
                it is Int
            }) {
                val a=values[0] as Int;
                if(values.size==1)return -a;
                val b=values[1] as Int;
                return when(name) {
                    "+"->a+b;
                    "-"->a-b;
                    "*"->a*b;
                    "<"->a<b;
                    "<="->a<=b;
                    ">"->a>b;
                    else->a>=b
                }
            }
        } else if(name=="=="||name=="!=") {
            val a=values[0];
            val b=values[1];
            if(a::class==b::class&&(a is Int||a is String||a is Boolean))return (name=="==")==a.equals(b)
        } else if(name=="in") {
            val a=values[0];
            val b=values[1];
            if(a is String&&b is List<*>)return a in b
        } else if(name=="not") {
            val flag=values.first();
            if(flag is Boolean)return !flag
        } else if(name=="starts_with"||name=="^=") {
            val a=values[0];
            val b=values[1];
            if(a is String&&b is String)return a.startsWith(b)
        } else if(name=="size") {
            val bag=values.first();
            if(bag is List<*>)return bag.size
        };
        return Failure("type $name")
    }
    fun expression(tree: Expressions.Expr,values: Map<String,Any>,current: String?=null): Any {
        when(tree) {
            is Expressions.Literal->return tree.value;
            is Expressions.Reference->return values[tree.name]?:Failure("missing ${tree.name}");
            Expressions.Current->return current!!;
            is Expressions.Operation-> {
                val name=tree.name;
                val arguments=tree.arguments;
                if(name=="present")return (arguments.first() as Expressions.Reference).name in values;
                if(name=="any_of"||name=="all_of") {
                    val bag=expression(arguments[0],values,current);
                    if(bag is Failure)return bag;
                    if(bag !is List<*>)return Failure("type $name");
                    val predicates=bag.map {
                        expression(arguments[1],values,it as String)
                    };
                    return booleanResult(predicates,name=="any_of",name)
                };
                val operands=arguments.map {
                    expression(it,values,current)
                };
                return if(name=="and"||name=="or")booleanResult(operands,name=="or",name) else operation(name,
                    operands)
            }
        }
    }
    fun targetGroup(results: List<Target>,conjunction: Boolean): Target {
        if(conjunction) {
            if(results.any {
                it.result=="NO_MATCH"
            })return Target("NO_MATCH");
            if(results.all {
                it.result=="MATCH"
            })return Target("MATCH")
        } else if(results.any {
            it.result=="MATCH"
        })return Target("MATCH");
        return results.firstOrNull {
            it.result=="INDETERMINATE"
        }?:Target("NO_MATCH")
    }
    fun matchClause(clause: PolicyParser.Clause,values: Map<String,Any>): Target {
        val reference=clause.reference;
        val source=values[reference]?:return if(clause.mandatory)Target("INDETERMINATE","missing $reference") else Target("NO_MATCH");
        val items=if(source is List<*>)source.map {
            it!!
        } else listOf(source);
        val comparison=expression(clause.literal,values);
        val results=items.map {
            operation(clause.operator,listOf(it,comparison))
        };
        if(results.any {
            it==true
        })return Target("MATCH");
        val error=firstError(results);
        return if(error==null)Target("NO_MATCH") else Target("INDETERMINATE",error.reason)
    }
    fun decisionNotation(decision: String,reason: String?)=if(decision.startsWith("INDETERMINATE"))"$decision ($reason)" else decision
    fun finalNotation(result: Evaluation)=decisionNotation(result.decision,result.reason)+(if(definite(result.decision))" by ${result.decisive!!.identifier}" else "")
    class Evaluator(val values: Map<String,Any>,val coverage: MutableMap<String,Char>?=null) {
        fun target(element: PolicyParser.Element)=targetGroup(element.targets.map {
            line->targetGroup(line.map {
                alternative->targetGroup(alternative.map {
                    matchClause(it,values)
                },true)
            },false)
        },true)
        fun attachments(result: Evaluation,supporters: List<Evaluation>) {
            for(supporter in supporters) {
                result.obligations.addAll(supporter.obligations);
                result.advice.addAll(supporter.advice)
            };
            val effect=result.decision;
            for(kind in 0..1)for(definition in if(kind==0)result.element.obligations else result.element.advice)if(definition.effect==effect) {
                val evaluated=definition.arguments.map {
                    expression(it.expression,values)
                };
                val error=firstError(evaluated);
                if(error!=null) {
                    if(kind==0) {
                        result.decision=if(effect=="DENY")Combining.ID else Combining.IP;
                        result.reason="obligation ${definition.identifier}: ${error.reason}";
                        result.decisive=null;
                        result.obligations.clear();
                        result.advice.clear();
                        return
                    };
                    continue
                };
                val item=definition.identifier+evaluated.indices.joinToString("") {
                    i->" ${definition.arguments[i].name}=${valueNotation(evaluated[i])}"
                };
                (if(kind==0)result.obligations else result.advice).add(Item(definition.identifier,item))
            }
        }
        fun rule(element: PolicyParser.Element,obligations: Boolean=true): Evaluation {
            val result=Evaluation(element,target(element));
            val target=result.target.result;
            val indeterminate=if(element.behavior=="DENY")Combining.ID else Combining.IP;
            if(target=="INDETERMINATE") {
                result.decision=indeterminate;
                result.reason=result.target.reason
            } else if(target=="MATCH") {
                val tree=element.condition;
                val condition=if(tree==null)true else expression(tree,values);
                val checked=if(condition is Boolean||condition is Failure)condition else Failure("type condition");
                result.condition=checked;
                if(checked is Failure) {
                    result.decision=indeterminate;
                    result.reason=checked.reason
                } else if(checked==true) {
                    result.decision=element.behavior;
                    result.decisive=element;
                    if(obligations)attachments(result,emptyList())
                }
            };
            coverage?.set(element.identifier,when(result.decision) {
                "PERMIT"->'P';
                "DENY"->'D';
                Combining.NA->'-';
                else->'I'
            });
            return result
        }
        fun evaluate(element: PolicyParser.Element): Evaluation {
            if(element.kind=="rule")return rule(element);
            val result=Evaluation(element,target(element));
            val target=result.target.result;
            if(target=="NO_MATCH")return result;
            val combined=Combining.combine(element.behavior,element.children,this::evaluate,this::target);
            result.decision=combined.decision;
            result.reason=combined.reason;
            result.children=combined.states;
            if(target=="INDETERMINATE") {
                if(definite(result.decision))result.decision=if(result.decision=="DENY")Combining.ID else Combining.IP;
                if(result.decision.startsWith("INDETERMINATE"))result.reason=result.target.reason
            };
            if(definite(result.decision)) {
                val supporters=result.children.mapNotNull {
                    it?.evaluated
                }.filter {
                    it.decision==result.decision
                };
                result.decisive=if(supporters.isEmpty())element else supporters.first().decisive;
                attachments(result,supporters)
            };
            return result
        }
    }
    fun treeLines(result: Evaluation,depth: Int=0): List<String> {
        val element=result.element;
        val target=result.target.result;
        val prefix=" ".repeat(2+2*depth);
        var line="$prefix${element.kind} ${element.identifier} ${element.behavior} target $target";
        if(element.kind=="rule"&&target=="MATCH")line+=" condition "+if(result.condition is Failure)"INDETERMINATE" else if(result.condition==true)"TRUE" else "FALSE";
        val lines=mutableListOf(line+" -> "+decisionNotation(result.decision,result.reason));
        if(element.kind!="rule"&&target!="NO_MATCH")for((i,child) in element.children.withIndex()) {
            val state=result.children[i];
            val evaluated=state?.evaluated;
            if(evaluated!=null)lines.addAll(treeLines(evaluated,depth+1)) else if(state==null)lines.add("$prefix  ${child.kind} ${child.identifier} skipped") else {
                val checked=state.checked!!;
                lines.add("$prefix  ${child.kind} ${child.identifier} ${child.behavior} target ${checked.result}"+if(checked.result=="INDETERMINATE")" (${checked.reason})" else "")
            }
        };
        return lines
    }
    fun <K> add(counts: MutableMap<K,Int>,key: K,amount: Int) {
        counts[key]=counts.getOrDefault(key,0)+amount
    }
    fun checkRequest(request: Request): String? {
        if(request.user !in subjects)return "unknown user ${request.user}";
        if(request.resource !in resources)return "unknown resource ${request.resource}";
        val day=request.environment["day"];
        return if(day is Int&&day in 1..365)null else "bad day"
    }
    fun prepare(request: Request): Prepared {
        val day=request.environment.getValue("day") as Int;
        val authorized=rbac.authorized(request.user,day);
        val candidates=when(request.roles) {
            "-"->emptyList();
            "*"->authorized.toList();
            else->request.roles.split(',')
        };
        val active=mutableListOf<String>();
        val seen=mutableSetOf<String>();
        val activations=mutableListOf<Activation>();
        for(candidate in candidates) {
            var reason: String?=null;
            if(candidate !in rbac.roles)reason="unknown" else if(candidate in seen)reason="duplicate" else if(candidate !in authorized)reason="unauthorized" else {
                val closure=rbac.closure(active+candidate);
                val constraint=rbac.dsd.firstOrNull {
                    closure.intersect(it.roles).size>=it.cardinality
                };
                if(constraint!=null)reason="dsd ${constraint.name}"
            };
            seen.add(candidate);
            if(reason==null)active.add(candidate);
            activations.add(Activation(candidate,reason))
        };
        val roles=rbac.closure(active).toList();
        val resource=resources.getValue(request.resource);
        val grant=roles.firstOrNull {
            Rbac.Permission(request.action,resource.type) in rbac.permissions.getValue(it)
        };
        val values=mutableMapOf<String,Any>();
        for((name,value) in subjects.getValue(request.user))values["subject.$name"]=value;
        values["subject.id"]=request.user;
        values["subject.role"]=roles;
        values["subject.rbac"]=grant!=null;
        for((name,value) in resource.attributes)values["resource.$name"]=value;
        values["resource.id"]=request.resource;
        values["resource.type"]=resource.type;
        values["action.id"]=request.action;
        for((name,value) in request.environment)values["environment.$name"]=value;
        return Prepared(activations,roles,grant,values)
    }
    fun trace(request: Request,prepared: Prepared,result: Evaluation): List<String> {
        val lines=mutableListOf("request ${request.identifier}","  user ${request.user} resource ${request.resource} type ${resources.getValue(request.resource).type} action ${request.action} day ${request.environment.getValue("day")}");
        for(activation in prepared.activations)lines.add("  activate ${activation.role}"+if(activation.reason==null)" ok" else " refused ${activation.reason}");
        lines.add("  roles "+prepared.roles.joinToString(",").ifEmpty {
            "-"
        });
        lines.add("  rbac "+if(prepared.grant==null)"no" else "yes ${prepared.grant}");
        lines.addAll(treeLines(result));
        lines.add("  decision "+finalNotation(result));
        return lines
    }
    fun joinBlocks(blocks: List<List<String>>): List<String> {
        val lines=mutableListOf<String>();
        for(block in blocks) {
            if(lines.isNotEmpty())lines.add("");
            lines.addAll(block)
        };
        return lines
    }
    fun processRequests(): List<List<String>> {
        val lines=mutableListOf<String>();
        val explanations=mutableListOf<List<String>>();
        for(request in requests) {
            val symbols=rules.associate {
                it.identifier to '.'
            }.toMutableMap();
            val error=checkRequest(request);
            if(error!=null) {
                lines.add("${request.identifier} ERROR $error");
                add(decisions,"ERROR",1);
                if(request.explain)explanations.add(listOf("request ${request.identifier}","  error $error"))
            } else {
                val prepared=prepare(request);
                val result=Evaluator(prepared.values,symbols).evaluate(root);
                lines.add("${request.identifier} ${finalNotation(result)}");
                for(activation in prepared.activations)if(activation.reason!=null) {
                    lines.add("  refused ${activation.role} ${activation.reason}");
                    refused++
                };
                for(item in result.obligations) {
                    lines.add("  obligation ${item.text}");
                    add(obligationCounts,item.identifier,1)
                };
                for(item in result.advice) {
                    lines.add("  advice ${item.text}");
                    add(adviceCounts,item.identifier,1)
                };
                prepared.grant?.let {
                    add(grantCounts,Rbac.Grant(it,request.action,resources.getValue(request.resource).type),
                        1)
                };
                add(decisions,if(result.decision.startsWith("INDETERMINATE"))"INDETERMINATE" else result.decision,
                    1);
                if(definite(result.decision))add(decisiveCounts,result.decisive!!.identifier,1);
                if(request.explain)explanations.add(trace(request,prepared,result))
            };
            for(rule in rules)coverage.getValue(rule.identifier).append(symbols.getValue(rule.identifier))
        };
        return listOf(lines,joinBlocks(explanations))
    }
    fun permissionReport(): List<String> {
        val blocks=mutableListOf<List<String>>();
        val users=rbac.assignments.map {
            it.user
        }.toSortedSet();
        for(user in users) {
            val assigned=sortedMapOf<String,MutableSet<Int>>();
            val authorized=sortedMapOf<String,MutableSet<Int>>();
            for(assignment in rbac.assignments)if(assignment.user==user)assigned.getOrPut(assignment.role) {
                sortedSetOf()
            }.addAll(assignment.first..assignment.last);
            for((role,days) in assigned)for(inherited in rbac.closure(listOf(role)))authorized.getOrPut(inherited) {
                sortedSetOf()
            }.addAll(days);
            val lines=mutableListOf("user $user");
            for((role,days) in assigned)lines.add("  assigned $role ${Analysis.dayNotation(days)}");
            for((role,days) in authorized)lines.add("  authorized $role ${Analysis.dayNotation(days)}");
            val via=sortedMapOf<Rbac.Permission,MutableList<String>>();
            for(role in authorized.keys)for(permission in rbac.permissions.getValue(role))via.getOrPut(permission) {
                mutableListOf()
            }.add(role);
            for((permission,roles) in via) {
                val days=roles.flatMap {
                    authorized.getValue(it)
                }.toSet();
                var effective="-";
                if(user in subjects) {
                    val matching=resources.filterValues {
                        it.type==permission.type
                    };
                    var permitted=0;
                    for(resource in matching.keys) {
                        val request=Request("",user,"*",permission.action,resource,reference,false);
                        val prepared=prepare(request);
                        if(Evaluator(prepared.values).evaluate(root).decision=="PERMIT")permitted++
                    };
                    effective="$permitted/${matching.size}"
                };
                lines.add("  permission ${permission.action} ${permission.type} ${Analysis.dayNotation(days)} via ${roles.joinToString(",")} effective $effective")
            };
            blocks.add(lines)
        };
        return joinBlocks(blocks)
    }
    fun domainAnalysis(): List<String> {
        val counts=mutableMapOf<String,Int>();
        val examples=mutableMapOf<String,String>();
        val conflictCounts=mutableMapOf<ConflictPair,Int>();
        val shadowed=rules.filter {
            it.parent!!.behavior=="first-applicable"
        }.map {
            it.identifier
        }.toMutableSet();
        val blockers=mutableMapOf<String,MutableSet<String>>();
        val pairs=mutableListOf<ConflictPair>();
        for(policy in elements)if(policy.kind=="policy")for(i in policy.children.indices)for(j in i+1 until policy.children.size) {
            val earlier=policy.children[i];
            val later=policy.children[j];
            if(earlier.behavior!=later.behavior)pairs.add(ConflictPair(policy,earlier,later))
        };
        var pointCount=0;
        for(values in Analysis.points(domains)) {
            pointCount++;
            val evaluator=Evaluator(values);
            val targets=elements.filter {
                it.kind!="rule"
            }.associate {
                it.identifier to evaluator.target(it).result
            };
            val standalone=rules.associate {
                it.identifier to evaluator.rule(it,false).decision
            };
            val applying=mutableSetOf<String>();
            for(rule in rules) {
                val identifier=rule.identifier;
                if(!definite(standalone.getValue(identifier)))continue;
                var parent=rule.parent;
                var ancestors=true;
                while(parent!=null) {
                    if(targets.getValue(parent.identifier)!="MATCH")ancestors=false;
                    parent=parent.parent
                };
                if(!ancestors)continue;
                applying.add(identifier);
                add(counts,identifier,1);
                examples.getOrPut(identifier) {
                    domains.filter {
                        it.values.size>=2
                    }.joinToString(" ") {
                        "${it.name}=${valueNotation(values.getValue(it.name))}"
                    }
                };
                if(identifier in shadowed) {
                    val earlier=Analysis.blocker(rule,standalone);
                    if(earlier==null)shadowed.remove(identifier) else blockers.getOrPut(identifier) {
                        mutableSetOf()
                    }.add(earlier)
                }
            };
            for(pair in pairs)if(pair.earlier.identifier in applying&&pair.later.identifier in applying)add(conflictCounts,
                pair,1)
        };
        val lines=mutableListOf("applicability $pointCount");
        for(rule in rules)lines.add("  ${rule.identifier} ${counts.getOrDefault(rule.identifier,0)} ${examples[rule.identifier]?:"-"}");
        val dead=rules.filter {
            counts.getOrDefault(it.identifier,0)==0
        }.map {
            it.identifier
        };
        lines.add("dead ${dead.size}");
        lines.addAll(dead.map {
            "  $it"
        });
        shadowed.removeAll(dead.toSet());
        lines.add("shadowed ${shadowed.size}");
        for(rule in rules)if(rule.identifier in shadowed) {
            val names=rules.filter {
                it.identifier in (blockers[rule.identifier]?:emptySet())
            }.map {
                it.identifier
            };
            lines.add("  ${rule.identifier} by ${names.joinToString(",")}")
        };
        val conflicts=pairs.filter {
            conflictCounts.getOrDefault(it,0)>0
        };
        lines.add("conflicts ${conflicts.size}");
        for(pair in conflicts)lines.add("  ${pair.policy.identifier} ${pair.earlier.identifier} ${pair.later.identifier} ${conflictCounts.getValue(pair)} ${Analysis.conflictWinner(pair.policy,pair.earlier,pair.later)}");
        return lines
    }
    fun analysisReport(): List<String> {
        val lines=mutableListOf("rbac ${rbac.diagnostics.size}");
        for(diagnostic in rbac.diagnostics)lines.add("  line ${diagnostic.line} ${diagnostic.keyword} ${diagnostic.message}");
        lines.add("grants ${rbac.grants.size}");
        for(grant in rbac.grants)lines.add("  ${grant.role} ${grant.action} ${grant.type} ${grantCounts.getOrDefault(grant,0)}");
        lines.addAll(domainAnalysis());
        lines.add("coverage ${requests.size}");
        val uncovered=mutableListOf<String>();
        for(rule in rules) {
            val symbols=coverage.getValue(rule.identifier).toString();
            val count=symbols.count {
                it=='P'||it=='D'
            };
            lines.add("  ${rule.identifier} $symbols $count");
            if(count==0)uncovered.add(rule.identifier)
        };
        lines.add("uncovered ${uncovered.size}");
        lines.addAll(uncovered.map {
            "  $it"
        });
        lines.add("summary");
        for(name in listOf("PERMIT","DENY",Combining.NA,"INDETERMINATE","ERROR"))lines.add("  decision $name ${decisions.getOrDefault(name,0)}");
        lines.add("  refused $refused");
        for(element in elements) {
            val count=decisiveCounts.getOrDefault(element.identifier,0);
            if(count>0)lines.add("  decisive ${element.identifier} $count")
        };
        for((identifier,count) in obligationCounts)lines.add("  obligation $identifier $count");
        for((identifier,count) in adviceCounts)lines.add("  advice $identifier $count");
        return lines
    }
    fun readInputs() {
        rbac=Rbac();
        val policies=PolicyParser.read();
        root=policies.root;
        elements=policies.elements;
        rules=elements.filter {
            it.kind=="rule"
        };
        for(rule in rules)coverage[rule.identifier]=StringBuilder();
        for(line in File("input/attributes.txt").readLines()) {
            val fields=line.split(' ');
            when(fields.first()) {
                "SUBJECT"->subjects[fields[1]]=attributes(fields.drop(2));
                "RESOURCE"->resources[fields[1]]=Resource(fields[2],attributes(fields.drop(3)));
                "DOMAIN"->domains.add(Analysis.Domain(fields[1],fields.drop(2).map {
                    inputValue(it)
                }));
                else->reference=attributes(fields.drop(1))
            }
        };
        for(line in File("input/requests.txt").readLines()) {
            var fields=line.split(' ');
            val explain=fields.last()=="EXPLAIN";
            if(explain)fields=fields.dropLast(1);
            requests.add(Request(fields[0],fields[1],fields[2],fields[3],fields[4],attributes(fields.drop(5)),
                explain))
        }
    }
    fun write(name: String,lines: List<String>) {
        File("output",name).writeText(lines.joinToString("\n")+if(lines.isEmpty())"" else "\n")
    }
    fun run() {
        readInputs();
        val reports=processRequests();
        File("output").mkdirs();
        write("decisions.txt",reports[0]);
        write("traces.txt",reports[1]);
        write("permissions.txt",permissionReport());
        write("analysis.txt",analysisReport())
    }
}
fun main()=PolicyEngine.run()
