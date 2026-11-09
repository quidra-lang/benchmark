import java.io.File
object RailwayProgram {
    data class Instruction(val command: String,val arguments: List<String>)
    data class OccupiedPart(val section: String,val start: Int,val low: Int,val high: Int)
    data class Timing(val name: String,val location: String,val scheduled: Int,val actual: Int?)
    class Request(val number: Int,val route: String,val time: Int) {
        var reason: String?=null
    }
    class Simulation {
        val layout=Layout();
        val interlocking=Interlocking(layout);
        val routes=interlocking.routes;
        val plans=Trains.readTrains();
        val trains=plans.trains;
        val plannedRequests=plans.requests.groupBy {
            it.time
        };
        val events=mutableMapOf<Int,MutableList<Instruction>>();
        val end: Int;
        val throwTime: Int;
        val overlapTime: Int;
        val snapshotTimes: Set<Int>;
        var time=0;
        var requestCount=0;
        var dropped=0;
        var queue=mutableListOf<Request>();
        val logLines=mutableListOf<String>();
        val snapshots=mutableListOf<String>();
        val safety=Safety()
        init {
            for(line in File("input/events.txt").readLines(Charsets.US_ASCII)) {
                val f=line.split(' ');
                events.getOrPut(f[0].toInt()) {
                    mutableListOf()
                }.add(Instruction(f[1],f.drop(2)))
            };
            val params=File("input/params.txt").readLines(Charsets.US_ASCII);
            end=params[0].split(' ')[1].toInt();
            throwTime=params[1].split(' ')[1].toInt();
            overlapTime=params[2].split(' ')[1].toInt();
            snapshotTimes=params[3].split(' ').drop(1).map {
                it.toInt()
            }.toSet()
        }
        fun log(content: String) {
            logLines.add("$time $content")
        }
        fun occupied(name: String): Boolean {
            val section=layout.sections.getValue(name);
            return section.occupants.isNotEmpty()||section.failed
        }
        fun startThrow(point: Layout.Point,target: String) {
            point.moving=true;
            point.target=target;
            point.completion=time+throwTime;
            log("MOVE ${point.name} $target until ${point.completion}")
        }
        fun completeThrows() {
            for(point in layout.points.values)if(point.moving&&point.completion==time) {
                point.position=point.target;
                point.moving=false;
                point.completion=null;
                log("POINT ${point.name} ${point.position}");
                point.throwsCount++
            }
        }
        fun releaseApproaches() {
            for(route in routes.values)if(route.state=="APPROACH"&&route.releaseTime==time) {
                interlocking.release(route);
                log("TIMEOUT ${route.name}")
            }
        }
        fun addRequest(name: String,requester: String) {
            val request=Request(++requestCount,name,time);
            log("REQUEST q${request.number} $name $requester");
            routes.getValue(name).requests++;
            queue.add(request)
        }
        fun cancel(name: String) {
            val removed=queue.filter {
                it.route==name
            };
            if(removed.isNotEmpty()) {
                for(request in removed) {
                    log("DROP q${request.number} $name");
                    dropped++
                };
                queue.removeAll {
                    it.route==name
                };
                return
            };
            val route=routes.getValue(name);
            if(route.state=="LOCKED") {
                route.cancels++;
                val signal=layout.signals.getValue(route.start);
                if(signal.aspect!="RED"&&occupied(signal.section)) {
                    route.state="APPROACH";
                    route.releaseTime=time+route.approachTime;
                    log("CANCEL $name approach until ${route.releaseTime}")
                }else {
                    interlocking.release(route);
                    log("CANCEL $name released")
                }
            }else log("CANCEL $name "+if(route.state==null)"none" else "refused")
        }
        fun individualThrow(name: String,target: String) {
            val point=layout.points.getValue(name);
            val result=when {
                point.locks.isNotEmpty()->"locked";
                point.failed->"failed";
                point.moving->"moving";
                occupied(point.common)->"occupied";
                point.position==target->"none";
                else->"start"
            };
            log("THROW $name $target $result");
            if(result=="start")startThrow(point,target)
        }
        fun pointFailure(command: String,name: String) {
            val point=layout.points.getValue(name);
            point.failed=command=="POINTFAIL";
            if(point.failed&&point.moving)point.completion=null;
            log("$command $name");
            if(!point.failed&&point.moving)startThrow(point,point.target)
        }
        fun executeEvents() {
            for(instruction in events[time]?:emptyList()) {
                val command=instruction.command;
                val a=instruction.arguments;
                when(command) {
                    "REQUEST"->addRequest(a[0],"OPERATOR");
                    "CANCEL"->cancel(a[0]);
                    "THROW"->individualThrow(a[0],a[1]);
                    "TCFAIL","TCFIX"-> {
                        layout.sections.getValue(a[0]).failed=command=="TCFAIL";
                        log("$command ${a[0]}")
                    };
                    else->pointFailure(command,a[0])
                }
            }
        }
        fun oppositeLock(names: Collection<String>,route: Interlocking.Route)=names.any {
            routes.getValue(it).direction!=route.direction
        }
        fun requestReason(route: Interlocking.Route): String? {
            if(route.state!=null)return "busy";
            for(name in route.conflicts)if(routes.getValue(name).state in listOf("LOCKED","APPROACH"))return "conflict $name";
            for(name in route.sections) {
                val section=layout.sections.getValue(name);
                if(occupied(name))return "occupied $name";
                if(section.routeLock!=null||oppositeLock(section.overlapLocks,route))return "locked $name"
            };
            for(name in route.overlap) {
                val section=layout.sections.getValue(name);
                if(occupied(name))return "occupied $name";
                val locks=section.overlapLocks.toMutableSet();
                section.routeLock?.let {
                    locks.add(it)
                };
                if(oppositeLock(locks,route))return "locked $name"
            };
            for(requirement in route.requirements) {
                val name=requirement.point;
                val target=requirement.position;
                val point=layout.points.getValue(name);
                if(point.locks.any {
                    it.position!=target
                })return "point $name locked";
                if(!point.moving&&point.position==target||point.moving&&point.target==target)continue;
                if(point.failed)return "point $name failed";
                if(point.moving)return "point $name moving";
                if(occupied(point.common))return "point $name occupied"
            };
            return null
        }
        fun judgeRequests() {
            val waiting=mutableListOf<Request>();
            for(request in queue) {
                val route=routes.getValue(request.route);
                val reason=requestReason(route);
                if(reason!=null) {
                    if(reason!=request.reason) {
                        log("WAIT q${request.number} ${route.name} $reason");
                        request.reason=reason
                    };
                    waiting.add(request);
                    continue
                };
                interlocking.lock(route);
                val wait=time-request.time;
                log("GRANT q${request.number} ${route.name} wait $wait");
                route.grants++;
                route.wait+=wait;
                route.maxwait=maxOf(route.maxwait,wait);
                for(requirement in route.requirements) {
                    val point=layout.points.getValue(requirement.point);
                    if(!point.moving&&point.position!=requirement.position)startThrow(point,requirement.position)
                }
            };
            queue=waiting
        }
        fun decideSignals() {
            for(decision in Signals.aspects(interlocking,this::occupied))if(decision.signal.aspect!=decision.aspect) {
                decision.signal.aspect=decision.aspect;
                log("SIGNAL ${decision.signal.name} ${decision.aspect}")
            }
        }
        fun occupiedParts(train: Trains.Train): List<OccupiedPart> {
            val parts=mutableListOf<OccupiedPart>();
            if(train.state=="RUNNING") {
                val tail=train.head-train.length;
                for(path in train.path) {
                    val end=path.start+layout.sections.getValue(path.section).length;
                    if(path.start<train.head&&end>tail)parts.add(OccupiedPart(path.section,path.start,
                        maxOf(tail,path.start),minOf(train.head,end)))
                }
            };
            return parts
        }
        fun headSection(train: Trains.Train)=train.path.lastOrNull {
            it.start<train.head
        }?:train.path.first()
        fun enter(train: Trains.Train,enteredBoundaries: MutableSet<String>): Boolean {
            if(train.state=="EXITED")return false;
            if(train.state=="RUNNING")return true;
            val boundary=layout.boundaries.getValue(train.entry);
            if(time<train.entryTime||occupied(boundary.section)||train.entry in enteredBoundaries)return false;
            train.state="RUNNING";
            train.direction=if(boundary.end=="L")"UP" else "DOWN";
            train.path=mutableListOf(Trains.PathPart(boundary.section,0));
            train.head=0;
            train.speed=train.entrySpeed;
            train.entered=time;
            enteredBoundaries.add(train.entry);
            log("ENTER ${train.name} ${train.entry}");
            return true
        }
        fun reverse(train: Trains.Train,stop: Trains.Stop) {
            val head=headSection(train);
            val end=head.start+layout.sections.getValue(head.section).length;
            train.path=occupiedParts(train).asReversed().map {
                Trains.PathPart(it.section,end-(it.start+layout.sections.getValue(it.section).length))
            }.toMutableList();
            train.head=end-(train.head-train.length);
            train.direction=if(train.direction=="UP")"DOWN" else "UP";
            log("REVERSE ${train.name} ${stop.section}")
        }
        fun finishDwell(train: Trains.Train): Boolean {
            if(!train.dwelling)return true;
            val stop=train.nextStop()!!;
            if(time<stop.arrival!!+stop.dwell||time<stop.scheduledDeparture)return false;
            train.dwelling=false;
            train.awaitingDeparture=stop;
            train.stopIndex++;
            if(stop.kind=="TURN")reverse(train,stop);
            return true
        }
        fun limitDistance(train: Trains.Train): Int? {
            if(train.boundary!=null)return null;
            val head=headSection(train);
            var name=head.section;
            var distance=head.start+layout.sections.getValue(name).length-train.head;
            while(true) {
                val signal=layout.signalsAt[Layout.Key(name,train.direction)];
                if(signal!=null&&signal.aspect=="RED")return distance;
                val stop=train.nextStop();
                if(stop!=null&&stop.section==name)return distance;
                val beyond=layout.beyond(name,train.direction);
                if(beyond.kind=="boundary")return null;
                if(beyond.kind=="buffer"||beyond.kind=="impassable")return distance;
                name=beyond.name!!;
                distance+=layout.sections.getValue(name).length
            }
        }
        fun passSignal(train: Trains.Train,signal: Layout.Signal) {
            val active=routes.values.firstOrNull {
                it.start==signal.name&&it.state in listOf("LOCKED","APPROACH")
            };
            log("PASS ${train.name} ${signal.name} ${signal.aspect} ${active?.name?:"-"}");
            signal.passes++;
            train.passes++;
            if(active!=null) {
                active.state="USED";
                active.uses++
            };
            if(signal.aspect=="RED") {
                log("SPAD ${train.name} ${signal.name}");
                safety.check(time,"SIGNAL_PASSING","${train.name} ${signal.name}");
                train.emergency=true
            }else safety.check(time,"SIGNAL_PASSING",null)
        }
        fun move(train: Trains.Train,distance: Int) {
            val head=headSection(train);
            var name=head.section;
            var start=head.start;
            var remaining=distance;
            while(remaining>0) {
                if(train.boundary!=null) {
                    train.head+=remaining;
                    break
                };
                val end=start+layout.sections.getValue(name).length;
                if(train.head+remaining<=end) {
                    train.head+=remaining;
                    break
                };
                remaining-=end-train.head;
                train.head=end;
                val signal=layout.signalsAt[Layout.Key(name,train.direction)];
                if(signal!=null)passSignal(train,signal);
                val stop=train.awaitingDeparture;
                if(stop!=null&&stop.section==name) {
                    log("DEPART ${train.name} $name");
                    stop.departure=time;
                    train.awaitingDeparture=null
                };
                val beyond=layout.beyond(name,train.direction);
                if(beyond.kind=="boundary") {
                    train.boundary=beyond.name;
                    train.boundaryCoordinate=end
                }else {
                    name=beyond.name!!;
                    start=end;
                    train.path.add(Trains.PathPart(name,start))
                }
            }
        }
        fun afterMovement(train: Trains.Train,speed: Int,previousSpeed: Int) {
            train.speed=speed;
            train.distance+=speed;
            train.maximumSpeed=maxOf(train.maximumSpeed,speed);
            if(speed==0)train.emergency=false;
            val head=headSection(train);
            val stop=train.nextStop();
            val arrived=stop!=null&&speed==0&&head.section==stop.section&&train.head==head.start+layout.sections.getValue(head.section).length;
            if(arrived) {
                train.dwelling=true;
                stop!!.arrival=time;
                log("ARRIVE ${train.name} ${head.section}")
            };
            if(speed==0&&!arrived) {
                train.standing++;
                if(previousSpeed>0)log("HOLD ${train.name} ${head.section}")
            };
            if(train.boundary!=null&&train.head-train.length>=train.boundaryCoordinate) {
                train.state="EXITED";
                train.exited=time;
                log("EXIT ${train.name} ${train.boundary}")
            }
        }
        fun runTrains() {
            val enteredBoundaries=mutableSetOf<String>();
            for(train in trains.values) {
                if(!enter(train,enteredBoundaries)||!finishDwell(train))continue;
                val distance=limitDistance(train);
                val previousSpeed=train.speed;
                val speed=Trains.selectSpeed(train,distance);
                move(train,speed);
                afterMovement(train,speed,previousSpeed)
            }
        }
        fun recomputeOccupancy() {
            for(section in layout.sections.values)section.occupants.clear();
            for(train in trains.values)for(part in occupiedParts(train)) {
                val occupants=layout.sections.getValue(part.section).occupants;
                if(train.name !in occupants)occupants.add(train.name)
            }
        }
        fun sectionalRelease() {
            for(route in routes.values) {
                if(route.state!="USED")continue;
                val remaining=route.sections.filter {
                    layout.sections.getValue(it).routeLock==route.name
                };
                for(name in remaining)if(occupied(name))route.passed.add(name);
                for(name in remaining) {
                    if(name !in route.passed||occupied(name))break;
                    interlocking.unlockSection(route,name);
                    log("RELEASE ${route.name} $name")
                };
                if(route.sections.none {
                    layout.sections.getValue(it).routeLock==route.name
                }) {
                    interlocking.release(route);
                    log("DONE ${route.name}")
                }else if(route.overlap.isNotEmpty()&&route.overlapLocked) {
                    route.overlapCounter=if(occupied(route.sections.last()))route.overlapCounter+1 else 0;
                    if(route.overlapCounter>=overlapTime) {
                        interlocking.unlockOverlap(route);
                        log("OVERLAP ${route.name}")
                    }
                }
            }
        }
        fun recordStatistics() {
            for(route in routes.values)if(route.state!=null)route.lockedSeconds++;
            for(point in layout.points.values) {
                if(point.locks.isNotEmpty())point.lockedSeconds++;
                if(point.moving)point.movingSeconds++
            };
            for(section in layout.sections.values) {
                if(occupied(section.name))section.occupiedSeconds++;
                if(section.routeLock!=null||section.overlapLocks.isNotEmpty())section.lockedSeconds++;
                section.trains.addAll(section.occupants)
            };
            for(signal in layout.signals.values)signal.seconds[signal.aspect]=signal.seconds.getOrDefault(signal.aspect,0)+1
        }
        fun diagram(): List<String> {
            var height=0;
            var width=0;
            for(section in layout.sections.values) {
                height=maxOf(height,section.row+1);
                width=maxOf(width,section.last+1)
            };
            for(point in layout.points.values) {
                height=maxOf(height,point.row+1);
                width=maxOf(width,point.column+1)
            };
            for(signal in layout.signals.values) {
                height=maxOf(height,signal.row+1);
                width=maxOf(width,signal.column+1)
            };
            for(buffer in layout.buffers.values) {
                height=maxOf(height,buffer.row+1);
                width=maxOf(width,buffer.column+1)
            };
            for(label in layout.labels) {
                height=maxOf(height,label.row+1);
                width=maxOf(width,label.column+label.text.length)
            };
            val grid=Array(height) {
                CharArray(width) {
                    ' '
                }
            };
            for(label in layout.labels)for((i,c) in label.text.withIndex())grid[label.row][label.column+i]=c;
            for(section in layout.sections.values) {
                val character=when {
                    section.failed->'#';
                    section.routeLock!=null->'=';
                    section.overlapLocks.isNotEmpty()->'~';
                    else->'-'
                };
                for(column in section.first..section.last)grid[section.row][column]=character
            };
            for(train in trains.values)for(part in occupiedParts(train)) {
                val section=layout.sections.getValue(part.section);
                val length=section.length;
                val cells=section.last-section.first+1;
                val left: Int;
                val right: Int;
                if(train.direction=="UP") {
                    left=part.low-part.start;
                    right=part.high-part.start
                }else {
                    left=length-(part.high-part.start);
                    right=length-(part.low-part.start)
                };
                for(cell in 0 until cells)if(left*cells<(cell+1)*length&&right*cells>cell*length) {
                    val column=section.first+cell;
                    val previous=grid[section.row][column];
                    grid[section.row][column]=if(previous in 'a'..'z'||previous=='*')'*' else train.symbol
                }
            };
            for(buffer in layout.buffers.values)grid[buffer.row][buffer.column]='|';
            for(point in layout.points.values)grid[point.row][point.column]=if(point.detected())point.position[0] else '?';
            for(signal in layout.signals.values)grid[signal.row][signal.column]=when(signal.aspect) {
                "RED"->'X';
                "YELLOW"->'Y';
                else->'G'
            };
            return grid.map {
                it.concatToString().trimEnd(' ')
            }
        }
        fun snapshot(): List<String> {
            val lines=mutableListOf("SNAPSHOT $time");
            lines.addAll(diagram());
            for(train in trains.values)if(train.state=="RUNNING") {
                val body=occupiedParts(train).joinToString(",") {
                    it.section
                };
                lines.add("TRAIN ${train.symbol} ${train.name} ${train.direction} ${train.speed}"+if(body.isEmpty())"" else " $body")
            };
            val active=routes.values.filter {
                it.state!=null
            }.joinToString(" ") {
                "${it.name}/${it.state}"
            }.ifEmpty {
                "-"
            };
            lines.add("ROUTES $active");
            return lines
        }
        fun trainRows(): List<Timing> {
            val rows=mutableListOf<Timing>();
            for(train in trains.values) {
                rows.add(Timing(train.name,"enter:${train.entry}",train.entryTime,train.entered));
                for(stop in train.stops) {
                    rows.add(Timing(train.name,"arr:${stop.section}",stop.scheduledArrival,stop.arrival));
                    rows.add(Timing(train.name,"dep:${stop.section}",stop.scheduledDeparture,stop.departure))
                };
                rows.add(Timing(train.name,"exit:${train.exit}",train.scheduledExit,train.exited))
            };
            return rows
        }
        fun trainReport(rows: List<Timing>): List<String> {
            val lines=mutableListOf("train,location,scheduled,actual,delay");
            for(row in rows) {
                val actual=row.actual;
                val timing=if(actual==null)"-,-" else "$actual,${actual-row.scheduled}";
                lines.add("${row.name},${row.location},${row.scheduled},$timing")
            };
            return lines
        }
        fun punctuality(rows: List<Timing>): String {
            var onTime=0;
            var late=0;
            var missing=0;
            var totalDelay=0;
            var maximum=0;
            for(row in rows) {
                val actual=row.actual;
                if(actual==null) {
                    missing++;
                    continue
                };
                val delay=actual-row.scheduled;
                if(delay<=0)onTime++ else {
                    late++;
                    totalDelay+=delay;
                    maximum=maxOf(maximum,delay)
                }
            };
            return "PUNCTUALITY on_time $onTime late $late missing $missing total_delay $totalDelay max_delay $maximum"
        }
        fun summary(rows: List<Timing>): List<String> {
            val lines=mutableListOf<String>();
            for(route in routes.values)lines.add("ROUTE ${route.name} ${route.start}-${route.finish} requests ${route.requests} grants ${route.grants} uses ${route.uses} cancels ${route.cancels} wait ${route.wait} maxwait ${route.maxwait} locked ${route.lockedSeconds}");
            for(point in layout.points.values) {
                val detectedPosition=if(point.detected())point.position else "?";
                lines.add("POINT ${point.name} throws ${point.throwsCount} locked ${point.lockedSeconds} moving ${point.movingSeconds} final $detectedPosition")
            };
            for(section in layout.sections.values)lines.add("SECTION ${section.name} occupied ${section.occupiedSeconds} locked ${section.lockedSeconds} trains ${section.trains.size}");
            for(signal in layout.signals.values)lines.add("SIGNAL ${signal.name} red ${signal.seconds.getOrDefault("RED",0)} yellow ${signal.seconds.getOrDefault("YELLOW",0)} green ${signal.seconds.getOrDefault("GREEN",0)} passes ${signal.passes}");
            for(train in trains.values)lines.add("TRAIN ${train.name} ${train.symbol} ${train.state} distance ${train.distance} maxspeed ${train.maximumSpeed} standing ${train.standing} passes ${train.passes}");
            val exited=trains.values.count {
                it.state=="EXITED"
            };
            val running=trains.values.count {
                it.state=="RUNNING"
            };
            val waiting=trains.values.count {
                it.state=="WAITING"
            };
            lines.add("TRAINS total ${trains.size} exited $exited running $running waiting $waiting");
            lines.add(punctuality(rows));
            lines.add("REQUESTS total $requestCount granted ${routes.values.sumOf{it.grants}} dropped $dropped pending ${queue.size}");
            return lines
        }
        fun writeReports() {
            val rows=trainRows();
            val reports=linkedMapOf("events.txt" to logLines,"snapshots.txt" to snapshots,"train_log.csv" to trainReport(rows),
                "safety.txt" to safety.report(),"summary.txt" to summary(rows));
            File("output").mkdirs();
            for((name,lines) in reports)File("output/$name").writeText(if(lines.isEmpty())"" else lines.joinToString("\n")+"\n",
                Charsets.US_ASCII)
        }
        fun run() {
            for(t in 0..end) {
                time=t;
                completeThrows();
                releaseApproaches();
                for(request in plannedRequests[time]?:emptyList())addRequest(request.route,request.train);
                executeEvents();
                judgeRequests();
                decideSignals();
                runTrains();
                recomputeOccupancy();
                sectionalRelease();
                safety.inspect(time,layout,routes);
                recordStatistics();
                if(time in snapshotTimes)snapshots.addAll(snapshot())
            };
            writeReports()
        }
    }
    fun run() {
        Simulation().run()
    }
}
fun main() {
    RailwayProgram.run()
}
