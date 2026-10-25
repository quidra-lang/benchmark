#include "traffic.hpp"
#include <algorithm>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <memory>
#include <numeric>
#include <sstream>
#include <tuple>
#include <utility>

template<class... Args> static std::string line(const Args&... args) {
    std::ostringstream out; bool first = true; ((out << (first ? "" : " ") << args,first = false),...); return out.str();
}
static std::string join(const Lines& values, const std::string& separator = " ") {
    std::string result; for (const std::string& value : values) { if (!result.empty()) result += separator; result += value; } return result;
}
static void append(Lines& target, const Lines& source) { target.insert(target.end(),source.begin(),source.end()); }
static Lines split(const std::string& text, char separator = ' ') {
    Lines values; std::istringstream stream(text); std::string value; while (std::getline(stream,value,separator)) values.push_back(value); return values;
}
static std::string timeText(int step) { std::ostringstream out; out << std::setfill('0') << std::setw(4) << step; return out.str(); }
static std::string optional(int value) { return value ? std::to_string(value) : "-"; }
struct Source {
    std::string node;
    std::vector<std::pair<Integer, Integer>> rates;
    Segment* segment;
    std::deque<Vehicle*> queue;
    int start = 0, maximum = 0;
    Integer rate(int step) const { for (const auto& period : rates) if (step <= period.second) return period.first; return 0; }
};
struct Detector { std::string name; Segment* segment; int cell, width; };
struct Diagram { Segment* segment; int lane, start, end; Lines lines; };
struct Ring { int number, length, vmax, warmup, measure; Integer seed; std::vector<int> counts; };
struct Interval {
    Integer arrivals = 0, insertions = 0, exits = 0, vehicleSteps = 0, speedSum = 0;
    std::vector<Integer> passing, occupancy, occupancySpeed;
    explicit Interval(int detectors) : passing(detectors), occupancy(detectors), occupancySpeed(detectors) {}
};
struct Move { Vehicle* vehicle; Segment* segment; int cell, speed = 0; };
struct Share {
    Integer numerator, denominator;
    Share(Integer n = 0, Integer d = 1) { Integer divisor = std::gcd(n,d); numerator = n / divisor; denominator = d / divisor; }
    Share times(Integer n, Integer d) const { return {numerator * n,denominator * d}; }
    Share plus(Share other) const { return {numerator * other.denominator + other.numerator * denominator,denominator * other.denominator}; }
    std::string text() const { return frac(numerator,denominator); }
};
struct Route { Lines segments; Share share; };
static Integer runRing(const Ring& ring, int count, int dawdle, int stopped) {
    Minstd rng{ring.seed}; std::vector<int> positions(count), speeds(count); Integer total = 0;
    for (int j = 0; j < count; ++j) positions[j] = j * ring.length / count;
    for (int step = 1; step <= ring.warmup + ring.measure; ++step) {
        std::vector<int> order(count), updated(count); std::iota(order.begin(),order.end(),0);
        std::sort(order.begin(),order.end(),[&](int a, int b) { return positions[a] > positions[b]; });
        for (int rank = 0; rank < count; ++rank) {
            int index = order[rank], ahead = order[rank == 0 ? count - 1 : rank - 1];
            int gap = (positions[ahead] - positions[index] - 1 + ring.length) % ring.length;
            int speed = std::min({speeds[index] + 1,ring.vmax,gap}); updated[index] = randomSlowdown(speed,speeds[index],rng.draw(),dawdle,stopped);
        }
        for (int j = 0; j < count; ++j) positions[j] = (positions[j] + updated[j]) % ring.length;
        speeds = updated; if (step > ring.warmup) for (int speed : speeds) total += speed;
    }
    return total;
}

class Simulation {
    std::vector<std::unique_ptr<Segment>> segments;
    std::map<std::string, Segment*> segmentById;
    std::vector<std::unique_ptr<Junction>> junctions;
    std::vector<Incident> incidents;
    std::vector<std::unique_ptr<BusStop>> stops;
    std::vector<VehicleClass> classes;
    std::vector<Source> sources;
    Lines sinks;
    Integer seed = 1, binWidth = 1;
    int steps = 0, dawdle = 0, stopped = 0, intervalLength = 1;
    std::vector<Detector> detectors;
    std::vector<Diagram> diagrams;
    std::vector<Integer> trackNumbers;
    std::vector<Ring> rings;
    Minstd rng{1};
    std::vector<std::unique_ptr<Vehicle>> ownedVehicles;
    std::vector<Vehicle*> vehicles;
    std::vector<Interval> intervals;
    Lines events;
    std::map<Integer, Lines> tracks;
    void loadLine(const Lines& p) {
        const std::string& kind = p[0]; auto number = [&](int index) { return std::stoll(p[index]); }; auto integer = [&](int index) { return static_cast<int>(number(index)); };
        if (kind == "SEGMENT") {
            auto segment = std::make_unique<Segment>(p[1],p[2],p[3],integer(4),integer(5),integer(6)); segmentById[p[1]] = segment.get(); segments.push_back(std::move(segment));
        } else if (kind == "JUNCTION") {
            auto junction = std::make_unique<Junction>(p[1],integer(2),Lines(p.begin() + 3,p.end()));
            for (const auto& segment : segments) if (segment->end == p[1]) { segment->junction = junction.get(); junction->incoming.push_back(segment.get()); } junctions.push_back(std::move(junction));
        } else if (kind == "INCIDENT") incidents.push_back({segmentById.at(p[1]),integer(2),integer(3),number(4),number(5)});
        else if (kind == "STOP") {
            auto stop = std::make_unique<BusStop>(BusStop{segmentById.at(p[1]),integer(2),integer(3)}); stop->segment->stop = stop.get(); stops.push_back(std::move(stop));
        } else if (kind == "CLASS") classes.push_back({p[1],integer(2),number(3),p[4] == "Y",p[5] == "Y"});
        else if (kind == "SOURCE") {
            Source source; source.node = p[1];
            for (int j = 2; j < static_cast<int>(p.size()); ++j) { Lines pair = split(p[j],':'); source.rates.push_back({std::stoll(pair[0]),std::stoll(pair[1])}); }
            for (const auto& segment : segments) if (segment->start == p[1]) { source.segment = segment.get(); break; } sources.push_back(source);
        } else if (kind == "SINK") sinks.push_back(p[1]);
        else if (kind == "TURN") segmentById.at(p[1])->turns.push_back({segmentById.at(p[2]),number(3)});
        else if (kind == "seed") seed = number(1);
        else if (kind == "steps") steps = integer(1);
        else if (kind == "dawdle") { dawdle = integer(1); stopped = integer(2); }
        else if (kind == "interval") intervalLength = integer(1);
        else if (kind == "bin") binWidth = number(1);
        else if (kind == "detector") detectors.push_back({p[1],segmentById.at(p[2]),integer(3),integer(4)});
        else if (kind == "diagram") diagrams.push_back({segmentById.at(p[1]),integer(2),integer(3),integer(4),{}});
        else if (kind == "track") for (int j = 1; j < static_cast<int>(p.size()); ++j) { trackNumbers.push_back(number(j)); tracks[number(j)] = {}; }
        else if (kind == "ring") {
            Ring ring{static_cast<int>(rings.size()) + 1,integer(1),integer(2),integer(3),integer(4),number(5),{}};
            for (int j = 6; j < static_cast<int>(p.size()); ++j) ring.counts.push_back(integer(j)); rings.push_back(ring);
        }
    }
    void record(int step, const std::string& text) { events.push_back(timeText(step) + " " + text); }
    void enter(Vehicle* vehicle, Segment* segment) {
        vehicle->route.push_back(segment->id); ++segment->entered;
        if (segment->junction) { std::vector<Integer> weights; for (const Turn& turn : segment->turns) weights.push_back(turn.weight); vehicle->turn = &segment->turns[select(weights,rng.draw())]; }
        else vehicle->turn = nullptr;
    }
    std::vector<Vehicle*> vehiclesOn(const Segment& segment) const {
        std::vector<Vehicle*> result; for (int lane = 1; lane <= segment.lanes; ++lane) for (int number : segment.numbers(lane)) result.push_back(vehicles[number - 1]); return result;
    }
    void arrive(int step) {
        std::vector<Integer> weights; for (const VehicleClass& kind : classes) weights.push_back(kind.weight);
        for (Source& source : sources) if (rng.draw() % 1000 < source.rate(step)) {
            const VehicleClass* kind = &classes[select(weights,rng.draw())]; auto vehicle = std::make_unique<Vehicle>(Vehicle{static_cast<int>(vehicles.size()) + 1,kind,source.node,step});
            Vehicle* pointer = vehicle.get(); ownedVehicles.push_back(std::move(vehicle)); vehicles.push_back(pointer); source.queue.push_back(pointer); ++intervals.back().arrivals;
        }
    }
    void insert(int step) {
        for (Source& source : sources) {
            Segment* segment = source.segment;
            while (!source.queue.empty()) {
                int best = 0, first = -1;
                for (int lane = 1; lane <= segment->lanes; ++lane) if (segment->empty(lane,0) && segment->first(lane) > first) { best = lane; first = segment->first(lane); }
                if (!best) break; Vehicle* vehicle = source.queue.front(); source.queue.pop_front(); vehicle->place(segment,best,0); vehicle->inserted = step; enter(vehicle,segment); ++intervals.back().insertions;
            }
            if (!source.queue.empty() && source.start == 0) { source.start = step; source.maximum = 0; }
            if (source.start) {
                source.maximum = std::max<int>(source.maximum,source.queue.size());
                if (source.queue.empty()) { record(step,line("QUEUE",source.node,"from",source.start,"max",source.maximum)); source.start = 0; }
            }
        }
    }
    std::pair<int, int> desiredLane(const Vehicle& vehicle) const {
        const Segment& s = *vehicle.segment; int lane = vehicle.lane, cell = vehicle.cell, top = vehicle.maxSpeed(), here = s.free(lane,cell,top + 1), want = std::min(vehicle.speed + 1,top), ahead = cell + here + 1;
        if (here < top + 1 && ahead < s.length && s.cells[lane - 1][ahead] == -1)
            for (int target : {lane + 1,lane - 1}) if (target >= 1 && target <= s.lanes && s.free(target,cell,top + 1) > here && s.safe(target,cell)) return {target,2};
        if (vehicle.headingForStop()) return lane >= 2 && s.safe(lane - 1,cell) ? std::pair<int, int>{lane - 1,1} : std::pair<int, int>{lane,-1};
        if (vehicle.kind->overtakes && lane + 1 <= s.lanes && here < want && s.free(lane + 1,cell,top + 1) > here && s.safe(lane + 1,cell)) return {lane + 1,0};
        if (lane >= 2 && s.free(lane - 1,cell,top + 1) > want && s.safe(lane - 1,cell)) return {lane - 1,1}; return {lane,-1};
    }
    void changeLanes() {
        std::vector<std::tuple<Vehicle*, int, int>> changes;
        for (const auto& segment : segments) if (segment->lanes >= 2) {
            std::set<std::pair<int, int>> reserved;
            for (int lane = 1; lane <= segment->lanes; ++lane) for (int number : segment->numbers(lane)) {
                Vehicle* vehicle = vehicles[number - 1]; if (vehicle->dwell) continue; auto desired = desiredLane(*vehicle);
                if (desired.first != lane && reserved.insert({desired.first,vehicle->cell}).second) changes.push_back({vehicle,desired.first,desired.second});
            }
        }
        for (const auto& change : changes) { Vehicle* vehicle = std::get<0>(change); Segment* segment = vehicle->segment; vehicle->place(segment,std::get<1>(change),vehicle->cell); ++vehicle->laneChanges; ++segment->changes[std::get<2>(change)]; }
    }
    int determineSpeed(Vehicle& vehicle, int step) {
        Segment* segment = vehicle.segment; int accelerated = std::min(vehicle.speed + 1,vehicle.maxSpeed()), gap = segment->free(vehicle.lane,vehicle.cell,accelerated);
        if (gap < accelerated && vehicle.cell + gap == segment->length - 1) {
            if (!segment->junction) gap = accelerated;
            else if (segment->junction->green(segment->id,step)) { Segment* target = vehicle.turn->target; gap += target->free(std::min(vehicle.lane,target->lanes),-1,accelerated - gap); }
        }
        if (vehicle.headingForStop()) gap = std::min(gap,segment->stop->cell - vehicle.cell);
        int speed = randomSlowdown(std::min(accelerated,gap),vehicle.speed,rng.draw(),dawdle,stopped);
        if (vehicle.dwell) { speed = 0; --vehicle.dwell; } return speed;
    }
    std::vector<Move> processingOrder() const {
        std::vector<Move> result;
        for (const auto& segment : segments) for (int lane = 1; lane <= segment->lanes; ++lane) {
            std::vector<int> numbers = segment->numbers(lane); for (auto number = numbers.rbegin(); number != numbers.rend(); ++number) { Vehicle* vehicle = vehicles[*number - 1]; result.push_back({vehicle,segment.get(),vehicle->cell}); }
        }
        return result;
    }
    std::vector<Move*> moveVehicles(std::vector<Move>& moves, int step) {
        std::vector<Move*> passing;
        for (Move& move : moves) {
            Vehicle* vehicle = move.vehicle; Segment* segment = move.segment;
            if (move.cell + move.speed < segment->length) vehicle->place(segment,vehicle->lane,move.cell + move.speed);
            else if (!segment->junction) { vehicle->leave(); vehicle->exited = step; vehicle->sink = segment->end; ++intervals.back().exits; }
            else passing.push_back(&move);
        }
        return passing;
    }
    void passJunctions(const std::vector<Move*>& passing) {
        for (Move* move : passing) {
            Vehicle* vehicle = move->vehicle; Segment* segment = move->segment; Segment* target = vehicle->turn->target;
            int lane = std::min(vehicle->lane,target->lanes), overshoot = move->cell + move->speed - segment->length, cell = std::min(overshoot,target->first(lane) - 1);
            if (cell < overshoot) ++segment->blocked;
            if (cell >= 0) { vehicle->place(target,lane,cell); move->speed = segment->length - move->cell + cell; ++segment->passed; ++vehicle->turn->vehicles; enter(vehicle,target); }
            else { vehicle->place(segment,vehicle->lane,segment->length - 1); move->speed = segment->length - 1 - move->cell; }
        }
    }
    void aggregateVehicle(const Move& move, int step) {
        Vehicle* vehicle = move.vehicle; Interval& interval = intervals.back(); ++vehicle->steps; vehicle->distance += move.speed;
        if (!move.speed) { ++vehicle->stoppedSteps; if (vehicle->speed > 0) ++vehicle->stopCount; } vehicle->speed = move.speed;
        ++interval.vehicleSteps; interval.speedSum += move.speed;
        if (vehicle->headingForStop() && vehicle->lane == 1 && vehicle->cell == vehicle->segment->stop->cell) {
            BusStop* stop = vehicle->segment->stop; vehicle->completedStops.insert(vehicle->segment->id); vehicle->dwell = stop->dwell; ++stop->buses;
            record(step,line("BUS_STOP",vehicle->number,vehicle->segment->id,"cell",stop->cell));
        }
        auto track = tracks.find(vehicle->number);
        if (track != tracks.end()) track->second.push_back(timeText(step) + " " + (vehicle->segment ? line(vehicle->segment->id,vehicle->lane,vehicle->cell,vehicle->speed) : line("EXIT",vehicle->speed)));
        for (std::size_t j = 0; j < detectors.size(); ++j) if (move.segment == detectors[j].segment && move.cell < detectors[j].cell && (vehicle->segment != detectors[j].segment || vehicle->cell >= detectors[j].cell)) ++interval.passing[j];
    }
    void aggregateState(int step) {
        Interval& interval = intervals.back();
        for (std::size_t j = 0; j < detectors.size(); ++j) for (Vehicle* vehicle : vehiclesOn(*detectors[j].segment)) if (vehicle->cell >= detectors[j].cell && vehicle->cell < detectors[j].cell + detectors[j].width) { ++interval.occupancy[j]; interval.occupancySpeed[j] += vehicle->speed; }
        for (const auto& segment : segments) {
            std::vector<Vehicle*> present = vehiclesOn(*segment); segment->vehicleSum += present.size(); segment->maxVehicles = std::max<Integer>(segment->maxVehicles,present.size()); Integer queued = 0;
            for (Vehicle* vehicle : present) { segment->speedSum += vehicle->speed; if (!vehicle->speed) ++queued; }
            if (!segment->junction) continue; bool green = segment->junction->green(segment->id,step); if (green) ++segment->greenSteps;
            segment->queueSum += queued; segment->maxQueue = std::max(segment->maxQueue,queued);
            if (step < steps && queued && green && !segment->junction->green(segment->id,step + 1)) ++segment->failures;
        }
        for (Diagram& diagram : diagrams) if (diagram.start <= step && step <= diagram.end) {
            Segment* segment = diagram.segment; std::string signal = !segment->junction ? "E" : segment->junction->green(segment->id,step) ? "G" : "R";
            diagram.lines.push_back(timeText(step) + " " + segment->text(diagram.lane,vehicles) + " " + signal);
        }
    }
    std::vector<Route> enumerateRoutes(Segment* segment) const {
        if (!segment->junction) return {{{segment->id},Share(1)}}; Integer total = 0; for (const Turn& turn : segment->turns) total += turn.weight; std::vector<Route> result;
        for (const Turn& turn : segment->turns) for (Route route : enumerateRoutes(turn.target)) { route.segments.insert(route.segments.begin(),segment->id); route.share = route.share.times(turn.weight,total); result.push_back(route); } return result;
    }
    Lines travelBlock(const std::string& heading, const std::vector<Vehicle*>& group) const {
        std::vector<Integer> times; Integer total = 0; for (Vehicle* vehicle : group) { times.push_back(vehicle->travelTime()); total += times.back(); }
        if (times.empty()) return {heading + " exited 0"}; std::sort(times.begin(),times.end());
        Lines result{line(heading,"exited",times.size(),"min",times.front(),"p50",percentile(times,50),"p90",percentile(times,90),"max",times.back(),"mean",dec(total,times.size(),2))}; append(result,histogramLines(times,binWidth)); return result;
    }
    std::string outcome(const std::vector<Vehicle*>& group, Integer total) const {
        Integer travel = 0; for (Vehicle* vehicle : group) travel += vehicle->travelTime(); return line("vehicles",group.size(),"share",frac(group.size(),total),"mean",dec(travel,group.size(),2));
    }
    Lines travelLines() const {
        std::vector<Vehicle*> exited; for (Vehicle* vehicle : vehicles) if (vehicle->exited) exited.push_back(vehicle); Lines result;
        for (const VehicleClass& kind : classes) { std::vector<Vehicle*> group; for (Vehicle* vehicle : exited) if (vehicle->kind == &kind) group.push_back(vehicle); append(result,travelBlock("CLASS " + kind.name,group)); }
        append(result,travelBlock("ALL",exited));
        for (const Source& source : sources) {
            std::vector<Vehicle*> group; for (Vehicle* vehicle : exited) if (vehicle->source == source.node) group.push_back(vehicle); result.push_back(line("SOURCE",source.node,"exited",group.size())); auto routes = enumerateRoutes(source.segment);
            for (const Route& route : routes) { std::vector<Vehicle*> matched; for (Vehicle* vehicle : group) if (vehicle->route == route.segments) matched.push_back(vehicle); result.push_back("  ROUTE " + join(route.segments,",") + " expected " + route.share.text() + " " + outcome(matched,group.size())); }
            for (const std::string& sink : sinks) {
                Share expected(0); bool found = false; for (const Route& route : routes) if (segmentById.at(route.segments.back())->end == sink) { found = true; expected = expected.plus(route.share); }
                if (!found) continue; std::vector<Vehicle*> matched; for (Vehicle* vehicle : group) if (vehicle->sink == sink) matched.push_back(vehicle); result.push_back("  SINK " + sink + " expected " + expected.text() + " " + outcome(matched,group.size()));
            }
        }
        return result;
    }
    Lines classBlock(const std::string& heading, const std::vector<Vehicle*>& group) const {
        Integer inserted = 0, count = 0, vehicleSteps = 0, distance = 0, travel = 0, delay = 0, stoppedSteps = 0, stopCount = 0, changes = 0;
        for (Vehicle* vehicle : group) {
            if (vehicle->inserted) ++inserted; vehicleSteps += vehicle->steps; distance += vehicle->distance;
            if (vehicle->exited) { ++count; travel += vehicle->travelTime(); delay += vehicle->inserted - vehicle->arrival; stoppedSteps += vehicle->stoppedSteps; stopCount += vehicle->stopCount; changes += vehicle->laneChanges; }
        }
        return {heading,"  " + line("generated",group.size(),"inserted",inserted,"exited",count,"in_network",inserted - count,"queued",group.size() - inserted),"  " + line("vehicle_steps",vehicleSteps,"distance",distance,"mean_speed",frac(distance,vehicleSteps),"=",dec(distance,vehicleSteps,3)),"  " + line("travel",dec(travel,count,2),"entry_delay",dec(delay,count,2),"stopped",dec(stoppedSteps,count,2),"stops",dec(stopCount,count,2),"lane_changes",dec(changes,count,2))};
    }
    Lines classLines() const {
        Lines result; for (const VehicleClass& kind : classes) { std::vector<Vehicle*> group; for (Vehicle* vehicle : vehicles) if (vehicle->kind == &kind) group.push_back(vehicle); append(result,classBlock(line("CLASS",kind.name,"vmax",kind.vmax,"weight",kind.weight,"overtake",kind.overtakes ? "Y" : "N","stops",kind.stops ? "Y" : "N"),group)); } append(result,classBlock("ALL",vehicles)); return result;
    }
    Lines networkLines() const {
        Lines result;
        for (const auto& s : segments) result.push_back(line("SEGMENT",s->id,s->start,s->end,"length",s->length,"lanes",s->lanes,"limit",s->limit,"entered",s->entered,"mean_vehicles",dec(s->vehicleSum,steps,3),"density",dec(s->vehicleSum,Integer(steps) * s->length * s->lanes,4),"mean_speed",dec(s->speedSum,s->vehicleSum,2),"max_vehicles",s->maxVehicles,"changes",std::to_string(s->changes[0]) + "/" + std::to_string(s->changes[1]) + "/" + std::to_string(s->changes[2])));
        for (const auto& junction : junctions) {
            append(result,junction->planLines());
            for (Segment* s : junction->incoming) { result.push_back("  " + line("IN",s->id,"green",s->greenSteps,"passed",s->passed,"blocked",s->blocked,"max_queue",s->maxQueue,"mean_queue",dec(s->queueSum,steps,3),"failures",s->failures)); for (const Turn& turn : s->turns) result.push_back("    " + line("TURN",turn.target->id,"weight",turn.weight,"vehicles",turn.vehicles)); }
        }
        for (const auto& stop : stops) result.push_back(line("STOP",stop->segment->id,"cell",stop->cell,"dwell",stop->dwell,"buses",stop->buses));
        for (const Incident& incident : incidents) result.push_back(line("INCIDENT",incident.segment->id,"lane",incident.lane,"cell",incident.cell,"planned",std::to_string(incident.start) + "-" + std::to_string(incident.end),"active",incident.activeStart ? std::to_string(incident.activeStart) + "-" + std::to_string(incident.activeEnd) : "none")); return result;
    }
    Lines detectorLines() const {
        Lines result{"detector,interval,flow,density,speed"};
        for (std::size_t j = 0; j < detectors.size(); ++j) for (std::size_t k = 0; k < intervals.size(); ++k) { const Interval& interval = intervals[k]; result.push_back(detectors[j].name + "," + std::to_string(k + 1) + "," + std::to_string(interval.passing[j]) + "," + dec(interval.occupancy[j],Integer(intervalLength) * detectors[j].width * detectors[j].segment->lanes,4) + "," + dec(interval.occupancySpeed[j],interval.occupancy[j],2)); } return result;
    }
    Lines timelineLines() const {
        Lines result{"interval,arrived,inserted,exited,in_network,queued,mean_speed"}; Integer arrived = 0, inserted = 0, exited = 0;
        for (std::size_t j = 0; j < intervals.size(); ++j) { const Interval& interval = intervals[j]; arrived += interval.arrivals; inserted += interval.insertions; exited += interval.exits; result.push_back(join({std::to_string(j + 1),std::to_string(interval.arrivals),std::to_string(interval.insertions),std::to_string(interval.exits),std::to_string(inserted - exited),std::to_string(arrived - inserted),dec(interval.speedSum,interval.vehicleSteps,2)},",")); } return result;
    }
    Lines trackLines() const {
        Lines result; for (Integer number : trackNumbers) {
            if (number > static_cast<Integer>(vehicles.size())) { result.push_back(line("VEHICLE",number,"none")); continue; }
            Vehicle* vehicle = vehicles[number - 1]; result.push_back(line("VEHICLE",number,"class",vehicle->kind->name,"source",vehicle->source,"arrival",vehicle->arrival,"inserted",optional(vehicle->inserted),"exited",optional(vehicle->exited),"sink",vehicle->sink.empty() ? "-" : vehicle->sink)); result.push_back("ROUTE " + (vehicle->route.empty() ? "-" : join(vehicle->route," "))); append(result,tracks.at(number));
        } return result;
    }
    Lines fundamentalLines() const {
        Lines result{"ring,vehicles,density,flow,speed"}; for (const Ring& ring : rings) for (int count : ring.counts) { Integer total = runRing(ring,count,dawdle,stopped); result.push_back(join({std::to_string(ring.number),std::to_string(count),dec(count,ring.length,4),dec(total,Integer(ring.length) * ring.measure,4),dec(total,Integer(count) * ring.measure,3)},",")); } return result;
    }
public:
    Simulation() {
        for (const char* name : {"network.txt","demand.txt","params.txt"}) { std::ifstream input(std::string("input/") + name); std::string text; while (std::getline(input,text)) loadLine(split(text)); }
    }
    void run() {
        rng.state = seed;
        for (int step = 1; step <= steps; ++step) {
            for (Incident& incident : incidents) { std::string event = incident.update(step); if (!event.empty()) record(step,line(event,incident.segment->id,"lane",incident.lane,"cell",incident.cell)); }
            if ((step - 1) % intervalLength == 0) intervals.emplace_back(detectors.size()); arrive(step); insert(step); changeLanes(); std::vector<Move> moves = processingOrder();
            for (Move& move : moves) move.speed = determineSpeed(*move.vehicle,step); passJunctions(moveVehicles(moves,step)); for (const Move& move : moves) aggregateVehicle(move,step); aggregateState(step);
        }
        for (const Source& source : sources) if (source.start) record(steps,line("QUEUE",source.node,"from",source.start,"max",source.maximum,"open"));
    }
    void write() const {
        Lines spacetime; for (const Diagram& diagram : diagrams) { spacetime.push_back(line("DIAGRAM",diagram.segment->id,"lane",diagram.lane,"steps",std::to_string(diagram.start) + "-" + std::to_string(diagram.end))); append(spacetime,diagram.lines); }
        std::filesystem::create_directories("output");
        const std::vector<std::pair<std::string, Lines>> outputs{{"spacetime.txt",spacetime},{"detectors.csv",detectorLines()},{"travel_times.txt",travelLines()},{"class_stats.txt",classLines()},{"network_stats.txt",networkLines()},{"timeline.csv",timelineLines()},{"tracks.txt",trackLines()},{"fundamental.csv",fundamentalLines()},{"events.txt",events}};
        for (const auto& output : outputs) { std::ofstream file("output/" + output.first); for (const std::string& text : output.second) file << text << '\n'; }
    }
};

int main() { Simulation simulation; simulation.run(); simulation.write(); }
