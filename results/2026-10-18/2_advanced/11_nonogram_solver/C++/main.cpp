#include "nonogram.hpp"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <tuple>

template<class... Args> static std::string cat(const Args&... args) { std::ostringstream out; (out << ... << args); return out.str(); }
static std::string join(const Lines& values, const std::string& separator = " ") { std::string result; for (const std::string& value : values) { if (!result.empty()) result += separator; result += value; } return result; }
static void append(Lines& target, const Lines& values) { target.insert(target.end(),values.begin(),values.end()); }
static std::string cellText(int row, int column) { return cat(row + 1,",",column + 1); }
static std::string numberList(const std::vector<int>& values) { Lines numbers; for (int value : values) numbers.push_back(std::to_string(value)); return numbers.empty() ? "-" : join(numbers,","); }
static bool validName(const std::string& name) { return !name.empty() && name.size() <= 20 && std::all_of(name.begin(),name.end(),[](char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'; }); }
static std::vector<Lines> readBlocks(const std::string& path) {
    std::ifstream input(path); std::vector<Lines> blocks; Lines current; bool inside = false; std::string text;
    while (std::getline(input,text)) {
        if (!inside) { if (!text.empty() && text[0] != '#') { inside = true; current = {text}; } }
        else if (text == "END") { blocks.push_back(current); inside = false; } else current.push_back(text);
    } return blocks;
}
static void writeLines(const std::string& name, const Lines& lines) { std::ofstream output("output/" + name); for (const std::string& text : lines) output << text << '\n'; }
static Lines paragraphs(const std::vector<Lines>& blocks) { Lines result; for (const Lines& block : blocks) { if (!result.empty()) result.push_back(""); append(result,block); } return result; }
struct Given { int row, column; char value; bool operator==(const Given& other) const { return row == other.row && column == other.column && value == other.value; } };
struct Puzzle {
    std::string name;
    int width, height;
    Lines rowLines, columnLines, answer;
    bool hasAnswer = false;
    Clues rows, columns;
    std::vector<Given> givens;
    explicit Puzzle(const Lines& block) {
        name = block[0].substr(7); std::istringstream size(block[1]); std::string token; size >> token >> width >> height;
        auto split = std::find(block.begin(),block.end(),"COLUMNS"); rowLines.assign(block.begin() + 3,split); auto position = split + 1;
        while (position != block.end() && isClueLine(*position)) columnLines.push_back(*position++);
        while (position != block.end() && position->rfind("GIVEN ",0) == 0) { std::istringstream given(*position++); Given cell; given >> token >> cell.row >> cell.column >> cell.value; --cell.row; --cell.column; givens.push_back(cell); }
        if (position != block.end()) { hasAnswer = true; answer.assign(position + 1,block.end()); }
    }
    std::string validate(const std::set<std::string>& names) {
        if (!validName(name)) return "bad name"; if (names.count(name)) return "duplicate name";
        if (width < 1 || width > 30 || height < 1 || height > 30) return "bad size";
        if (static_cast<int>(rowLines.size()) != height) return cat("row count ",rowLines.size()," expected ",height);
        if (static_cast<int>(columnLines.size()) != width) return cat("column count ",columnLines.size()," expected ",width);
        for (bool row : {true,false}) { const Lines& texts = row ? rowLines : columnLines; Clues& clues = row ? rows : columns;
            for (int i = 0; i < static_cast<int>(texts.size()); ++i) { auto clue = parseClue(texts[i]); std::string kind = row ? "row " : "column "; if (!clue) return cat("bad clue ",kind,i + 1); if (span(*clue) > (row ? width : height)) return cat(kind,i + 1," too long"); clues.push_back(*clue); }
        }
        int a = 0, b = 0; for (const Clue& clue : rows) a += std::accumulate(clue.begin(),clue.end(),0); for (const Clue& clue : columns) b += std::accumulate(clue.begin(),clue.end(),0); if (a != b) return cat("total mismatch rows=",a," columns=",b);
        std::set<std::pair<int, int>> taken; for (int i = 0; i < static_cast<int>(givens.size()); ++i) { const Given& g = givens[i]; if (g.row < 0 || g.row >= height || g.column < 0 || g.column >= width || (g.value != Filled && g.value != Empty)) return cat("bad given ",i + 1); if (!taken.insert({g.row,g.column}).second) return cat("duplicate given ",i + 1); }
        if (hasAnswer) { if (static_cast<int>(answer.size()) != height) return "bad answer"; for (const std::string& row : answer) if (static_cast<int>(row.size()) != width || row.find_first_not_of("#.?") != std::string::npos) return "bad answer"; } return "";
    }
};
static std::string solvingResult(const Grid& grid, const Propagation& propagation) { if (propagation.conflict) return "contradiction at=" + propagation.conflict->label(); return determined(grid) == static_cast<int>(grid.size() * grid[0].size()) ? "solved" : "stuck"; }
struct Analysis {
    Grid simpleGrid, logicGrid;
    Propagation simple, logic;
    std::string simpleResult, logicResult, status, difficulty = "-";
    std::optional<SearchResult> searchResult;
    std::vector<Grid> solutions;
    int lineSolves, guesses = 0, maxDepth = 0;
    Analysis(const Clues& rows, const Clues& columns, const std::vector<Given>& givens) {
        int h = rows.size(), w = columns.size(); Grid initial(h,std::string(w,Unknown)); for (const Given& g : givens) initial[g.row][g.column] = g.value;
        simpleGrid = initial; logicGrid = initial; simple = propagate(simpleGrid,rows,columns,false,std::vector<bool>(h,true),std::vector<bool>(w,true)); logic = propagate(logicGrid,rows,columns,true,std::vector<bool>(h,true),std::vector<bool>(w,true));
        simpleResult = solvingResult(simpleGrid,simple); logicResult = solvingResult(logicGrid,logic); lineSolves = logic.steps.size();
        if (logic.conflict) status = "contradiction";
        else if (logicResult == "solved") { status = "unique"; solutions.push_back(logicGrid); difficulty = simpleResult == "solved" ? "easy" : "medium"; }
        else { searchResult = search(logicGrid,rows,columns); solutions = searchResult->solutions; status = solutions.empty() ? "none" : solutions.size() == 1 ? "unique" : "multiple"; if (status == "unique") difficulty = "hard"; lineSolves += searchResult->lineSolves; guesses = searchResult->guesses.size(); maxDepth = searchResult->maxDepth; }
    }
};
static std::string clueStatistics(const Clues& rows, const Clues& columns) {
    int rowBlocks = 0, columnBlocks = 0, filled = 0, maximum = 0, fixed = 0;
    for (bool row : {true,false}) for (const Clue& clue : row ? rows : columns) {
        (row ? rowBlocks : columnBlocks) += clue.size(); for (int block : clue) { maximum = std::max(maximum,block); if (row) filled += block; } if (clue.empty() || span(clue) == static_cast<int>(row ? columns.size() : rows.size())) ++fixed;
    } return cat("row_blocks=",rowBlocks," column_blocks=",columnBlocks," filled=",filled," max_block=",maximum," fixed_lines=",fixed);
}
static std::string stepStatistics(const Propagation& propagation) {
    int productive = 0, idle = 0, best = 0; std::string at = "-";
    for (const Step& step : propagation.steps) if (!step.contradiction) { if (step.gain) ++productive; else ++idle; if (step.gain > best) { best = step.gain; at = step.label(); } } return cat("productive=",productive," idle=",idle," best=",best," at=",at);
}
static std::vector<std::pair<int, int>> differences(const Grid& first, const Grid& second) {
    std::vector<std::pair<int, int>> result; for (int r = 0; r < static_cast<int>(first.size()); ++r) for (int c = 0; c < static_cast<int>(first[0].size()); ++c) if (first[r][c] != second[r][c]) result.push_back({r,c}); return result;
}
static std::string features(const Grid& grid) {
    int h = grid.size(), w = grid[0].size(), filled = 0, components = 0, largest = 0, minRow = h, minColumn = w, maxRow = -1, maxColumn = -1; std::vector<std::vector<bool>> seen(h,std::vector<bool>(w));
    for (int r = 0; r < h; ++r) for (int c = 0; c < w; ++c) if (grid[r][c] == Filled) {
        ++filled; minRow = std::min(minRow,r); maxRow = std::max(maxRow,r); minColumn = std::min(minColumn,c); maxColumn = std::max(maxColumn,c); if (seen[r][c]) continue;
        ++components; int size = 0; std::vector<std::pair<int, int>> pending{{r,c}}; seen[r][c] = true;
        while (!pending.empty()) { auto cell = pending.back(); pending.pop_back(); ++size; for (auto delta : {std::pair<int, int>{-1,0},{1,0},{0,-1},{0,1}}) { int row = cell.first + delta.first, column = cell.second + delta.second; if (row >= 0 && row < h && column >= 0 && column < w && grid[row][column] == Filled && !seen[row][column]) { seen[row][column] = true; pending.push_back({row,column}); } } } largest = std::max(largest,size);
    }
    Lines symmetries; for (auto symmetry : {std::tuple<std::string, bool, bool>{"lr",false,true},{"ud",true,false},{"rot180",true,true}}) {
        bool same = true; for (int r = 0; r < h; ++r) for (int c = 0; c < w; ++c) if (grid[r][c] != grid[std::get<1>(symmetry) ? h - 1 - r : r][std::get<2>(symmetry) ? w - 1 - c : c]) same = false; if (same) symmetries.push_back(std::get<0>(symmetry));
    }
    return cat("filled=",filled," components=",components," largest=",largest," bbox=",filled ? cat(minRow + 1,",",minColumn + 1,",",maxRow + 1,",",maxColumn + 1) : "-"," symmetry=",symmetries.empty() ? "none" : join(symmetries,","));
}
static std::string unknownSummary(const Grid& grid, bool row) {
    Lines result; int size = row ? grid.size() : grid[0].size(); for (int i = 0; i < size; ++i) { std::string cells = lineCells(grid,row,i); int count = std::count(cells.begin(),cells.end(),Unknown); if (count) result.push_back(cat(i + 1,":",count)); } return join(result);
}
static std::string evaluateGivens(const Puzzle& puzzle, const Analysis& analysis) {
    if (puzzle.givens.empty() || analysis.status == "multiple") return ""; std::vector<int> accepted;
    for (int i = 0; i < static_cast<int>(puzzle.givens.size()); ++i) { std::vector<Given> others = puzzle.givens; others.erase(others.begin() + i); std::string status = Analysis(puzzle.rows,puzzle.columns,others).status; if (status == "unique" || (analysis.status != "unique" && status == "multiple")) accepted.push_back(i + 1); }
    return "givens " + std::string(analysis.status == "unique" ? "redundant=" : "blame=") + numberList(accepted);
}
struct Grade { std::string result = "-"; Lines lines; };
static Grade gradeAnswer(const Puzzle& puzzle, const Analysis& analysis) {
    if (!puzzle.hasAnswer) return {}; const Grid& answer = puzzle.answer; std::vector<int> rows, columns, givens; Lines mismatches; int known = determined(answer); bool partial = known < puzzle.width * puzzle.height;
    for (bool row : {true,false}) for (int i = 0; i < (row ? puzzle.height : puzzle.width); ++i) {
        std::string cells = lineCells(answer,row,i); const Clue& clue = row ? puzzle.rows[i] : puzzle.columns[i]; if (hasPlacement(cells,clue)) continue;
        (row ? rows : columns).push_back(i + 1); mismatches.push_back(cat("mismatch ",label(row,i)," expected=",clueText(clue,','),partial ? " cells=" : " got=",partial ? stateString(cells) : clueText(runClue(cells),',')));
    }
    std::set<std::pair<int, int>> taken; for (int i = 0; i < static_cast<int>(puzzle.givens.size()); ++i) { const Given& g = puzzle.givens[i]; taken.insert({g.row,g.column}); if (answer[g.row][g.column] != Unknown && answer[g.row][g.column] != g.value) givens.push_back(i + 1); }
    bool mismatch = !rows.empty() || !columns.empty() || !givens.empty(); Grade grade; grade.result = partial ? "partial" : mismatch ? "wrong" : "correct";
    std::string text = cat("answer result=",grade.result," known=",known," rows=",numberList(rows)," columns=",numberList(columns)," givens=",numberList(givens));
    if (partial) { bool extendable = false; if (!mismatch) { std::vector<Given> combined = puzzle.givens; for (int r = 0; r < puzzle.height; ++r) for (int c = 0; c < puzzle.width; ++c) if (answer[r][c] != Unknown && !taken.count({r,c})) combined.push_back({r,c,answer[r][c]}); std::string status = Analysis(puzzle.rows,puzzle.columns,combined).status; extendable = status == "unique" || status == "multiple"; } text += std::string(" extendable=") + (extendable ? "yes" : "no"); }
    if (analysis.status == "unique") { int differs = 0; for (int r = 0; r < puzzle.height; ++r) for (int c = 0; c < puzzle.width; ++c) if (answer[r][c] != Unknown && answer[r][c] != analysis.solutions[0][r][c]) ++differs; text += cat(" differs=",differs); }
    grade.lines = {text}; append(grade.lines,mismatches); return grade;
}
struct Report {
    const Puzzle* puzzle;
    Analysis analysis;
    Grade grade;
    Report(const Puzzle& puzzle) : puzzle(&puzzle), analysis(puzzle.rows,puzzle.columns,puzzle.givens), grade(gradeAnswer(puzzle,analysis)) {}
    int score() const { return analysis.lineSolves + 25 * analysis.guesses; }
    Lines paragraph() const {
        const Puzzle& p = *puzzle; const Analysis& a = analysis;
        Lines result{"PUZZLE " + p.name,cat("size=",p.width,"x",p.height," givens=",p.givens.size()," status=",a.status," difficulty=",a.difficulty),"clues " + clueStatistics(p.rows,p.columns),cat("simple known=",determined(a.simpleGrid)," line_solves=",a.simple.steps.size()," result=",a.simpleResult),cat("logic known=",determined(a.logicGrid)," line_solves=",a.logic.steps.size()," result=",a.logicResult),"steps " + stepStatistics(a.logic)};
        if (p.width * p.height <= 49) result.push_back("trace " + a.logic.record());
        if (a.logicResult == "stuck") result.push_back("stuck rows=" + unknownSummary(a.logicGrid,true) + " columns=" + unknownSummary(a.logicGrid,false));
        if (a.status == "contradiction") { const Step& step = *a.logic.conflict; result.push_back(cat("conflict line=",step.label()," clue=",clueText(step.row ? p.rows[step.index] : p.columns[step.index],',')," cells=",stateString(lineCells(a.logicGrid,step.row,step.index)))); }
        if (a.searchResult) { const SearchResult& s = *a.searchResult; result.push_back(cat("search guesses=",s.guesses.size()," max_depth=",s.maxDepth," backtracks=",s.backtracks," solutions=",s.solutions.size()," line_solves=",s.lineSolves)); for (const Guess& g : s.guesses) result.push_back(cat("guess ",g.number," depth=",g.depth," cell=",cellText(g.row,g.column)," value=",stateChar(g.value)," solves=",g.solves," known=",g.known," result=",g.result)); }
        if (a.status == "multiple") { auto cells = differences(a.solutions[0],a.solutions[1]); Lines text; for (auto cell : cells) text.push_back(cellText(cell.first,cell.second)); result.push_back(cat("differ count=",cells.size()," cells=",join(text))); }
        std::vector<std::pair<std::string, Grid>> display;
        if (a.status == "contradiction") display.push_back({"partial",a.logicGrid}); else { if (a.simpleResult == "stuck") display.push_back({"simple",a.simpleGrid}); if (a.logicResult == "stuck") display.push_back({"logic",a.logicGrid}); if (a.status == "multiple") { display.push_back({"first",a.solutions[0]}); display.push_back({"second",a.solutions[1]}); } } append(result,gridDisplay(display));
        if (a.status == "unique") { result.push_back("sheet"); append(result,answerSheet(p.rows,p.columns,a.solutions[0])); result.push_back("picture " + features(a.solutions[0])); }
        std::string evaluation = evaluateGivens(p,a); if (!evaluation.empty()) result.push_back(evaluation); append(result,grade.lines); return result;
    }
    std::string stats() const { const Puzzle& p = *puzzle; const Analysis& a = analysis; return cat(p.name,",",a.status,",",a.difficulty,",",p.width,",",p.height,",",p.givens.size(),",",determined(a.simpleGrid),",",determined(a.logicGrid),",",a.lineSolves,",",a.guesses,",",a.maxDepth,",",a.solutions.size(),",",grade.result); }
};
static std::vector<Report> processPuzzles(std::vector<Puzzle>& puzzles) {
    std::set<std::string> names; std::vector<Report> reports; std::vector<Lines> output; Lines stats{"puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer"};
    for (Puzzle& puzzle : puzzles) { std::string error = puzzle.validate(names); names.insert(puzzle.name); if (!error.empty()) { output.push_back({"PUZZLE " + puzzle.name,"error " + error}); std::string row = puzzle.name + ",invalid"; for (int i = 0; i < 11; ++i) row += ",-"; stats.push_back(row); } else { reports.emplace_back(puzzle); output.push_back(reports.back().paragraph()); stats.push_back(reports.back().stats()); } }
    std::map<std::string, int> difficulty{{"easy",0},{"medium",1},{"hard",2}}; std::vector<const Report*> ranked; std::map<std::string, int> counts; int solves = 0, guesses = 0;
    for (const Report& report : reports) { if (report.analysis.status == "unique") ranked.push_back(&report); ++counts[report.analysis.status]; ++counts[report.analysis.difficulty]; solves += report.analysis.lineSolves; guesses += report.analysis.guesses; }
    std::sort(ranked.begin(),ranked.end(),[&](const Report* a, const Report* b) { return std::make_tuple(difficulty[a->analysis.difficulty],a->score(),a->puzzle->name) < std::make_tuple(difficulty[b->analysis.difficulty],b->score(),b->puzzle->name); }); Lines ranking{"RANKING"};
    for (int i = 0; i < static_cast<int>(ranked.size()); ++i) { const Report& r = *ranked[i]; ranking.push_back(cat("rank ",i + 1," ",r.puzzle->name," ",r.analysis.difficulty," score=",r.score()," size=",r.puzzle->width,"x",r.puzzle->height)); } output.push_back(ranking);
    output.push_back({cat("SUMMARY puzzles=",puzzles.size()," invalid=",puzzles.size() - reports.size()," contradiction=",counts["contradiction"]," none=",counts["none"]," unique=",counts["unique"]," multiple=",counts["multiple"]," easy=",counts["easy"]," medium=",counts["medium"]," hard=",counts["hard"]," line_solves=",solves," guesses=",guesses)}); writeLines("solutions.txt",paragraphs(output)); writeLines("stats.csv",stats); return reports;
}
struct Generation {
    Grid grid;
    Clues rows, columns;
    std::vector<Given> givens;
    Lines log;
    std::optional<Analysis> initial, final;
    explicit Generation(Grid grid) : grid(std::move(grid)) {
        for (const std::string& row : this->grid) rows.push_back(runClue(row)); for (int c = 0; c < static_cast<int>(this->grid[0].size()); ++c) columns.push_back(runClue(lineCells(this->grid,false,c)));
        initial.emplace(rows,columns,givens); Analysis current = *initial;
        while (current.status == "multiple") { auto cell = differences(current.solutions[0],current.solutions[1])[0]; std::string text = add(cell); current = Analysis(rows,columns,givens); log.push_back(cat("# hint ",givens.size()," ",text," status=",current.status)); }
        std::vector<Given> original = givens; for (const Given& given : original) { std::vector<Given> others; for (const Given& other : givens) if (!(other == given)) others.push_back(other); if (Analysis(rows,columns,others).status == "unique") { givens = others; log.push_back("# drop cell=" + cellText(given.row,given.column)); } }
        final.emplace(rows,columns,givens); int count = 0;
        while (final->difficulty == "hard") { auto cell = guessCell(final->logicGrid); std::string text = add(cell); final.emplace(rows,columns,givens); log.push_back(cat("# logic hint ",++count," ",text," difficulty=",final->difficulty)); }
    }
    std::string add(std::pair<int, int> cell) { char value = grid[cell.first][cell.second]; givens.push_back({cell.first,cell.second,value}); return cat("cell=",cellText(cell.first,cell.second)," value=",stateChar(value)); }
    Lines paragraph(const std::string& name, const std::vector<Report>& reports) const {
        std::string duplicate = "-"; for (const Report& report : reports) if (report.puzzle->rows == rows && report.puzzle->columns == columns) { duplicate = report.puzzle->name; break; }
        Lines result{cat("# picture ",name," size=",columns.size(),"x",rows.size()," ",features(grid)),"# clues " + clueStatistics(rows,columns) + " duplicate_of=" + duplicate,cat("# plain status=",initial->status," difficulty=",initial->difficulty," line_solves=",initial->lineSolves," guesses=",initial->guesses)}; append(result,log); result.push_back(cat("# final status=",final->status," difficulty=",final->difficulty," hints=",givens.size()," line_solves=",final->lineSolves," guesses=",final->guesses));
        append(result,{"PUZZLE " + name,cat("SIZE ",columns.size()," ",rows.size()),"ROWS"}); for (const Clue& clue : rows) result.push_back(clueText(clue)); result.push_back("COLUMNS"); for (const Clue& clue : columns) result.push_back(clueText(clue));
        std::vector<Given> sorted = givens; std::sort(sorted.begin(),sorted.end(),[](const Given& a, const Given& b) { return std::tie(a.row,a.column) < std::tie(b.row,b.column); }); for (const Given& given : sorted) result.push_back(cat("GIVEN ",given.row + 1," ",given.column + 1," ",stateChar(given.value))); result.push_back("END"); return result;
    }
};
static void processPictures(const std::vector<Lines>& pictures, const std::vector<Report>& reports) {
    std::set<std::string> names; std::vector<Lines> output; int valid = 0, unique = 0, logic = 0, hinted = 0, hints = 0;
    for (const Lines& block : pictures) {
        std::string name = block[0].substr(8), error; Grid grid(block.begin() + 1,block.end());
        if (!validName(name)) error = "bad name"; else if (names.count(name)) error = "duplicate name"; else if (grid.empty() || grid.size() > 30) error = "bad height";
        else for (int i = 0; i < static_cast<int>(grid.size()); ++i) if (grid[i].empty() || grid[i].size() > 30 || grid[i].size() != grid[0].size() || grid[i].find_first_not_of("#.") != std::string::npos) { error = cat("bad row ",i + 1); break; }
        names.insert(name); if (!error.empty()) { output.push_back({"# picture " + name + " error " + error}); continue; }
        Generation generation(grid); ++valid; if (generation.initial->status == "unique") ++unique; if (generation.initial->difficulty == "easy" || generation.initial->difficulty == "medium") ++logic; if (!generation.givens.empty()) ++hinted; hints += generation.givens.size(); output.push_back(generation.paragraph(name,reports));
    }
    output.push_back({cat("# SUMMARY pictures=",pictures.size()," invalid=",pictures.size() - valid," unique=",unique," line_logic=",logic," hinted=",hinted," hints=",hints)}); writeLines("generated.txt",paragraphs(output));
}
int main() {
    std::filesystem::create_directories("output"); std::vector<Puzzle> puzzles; for (const Lines& block : readBlocks("input/puzzles.txt")) puzzles.emplace_back(block); std::vector<Report> reports = processPuzzles(puzzles); processPictures(readBlocks("input/pictures.txt"),reports);
}
