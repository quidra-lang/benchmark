#include <algorithm>
#include <cmath>
#include <cctype>
#include <cstdint>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
using namespace std;
struct Rational {
    int64_t p, q;
    Rational(int64_t n = 0, int64_t d = 1) {
        if (!d) throw runtime_error("division by zero");
        if (d<0) {
            n = -n;
            d = -d;
        }
        int64_t g = gcd(n, d);
        p = n/g;
        q = d/g;
    }
    Rational operator+(Rational b) const {
        return {
            p*b.q+b.p*q, q*b.q
        };
    }
    Rational operator*(Rational b) const {
        return {
            p*b.p, q*b.q
        };
    }
    Rational operator-() const {
        return {
            -p, q
        };
    }
    bool operator == (Rational b) const {
        return p == b.p && q == b.q;
    }
    bool operator<(Rational b) const {
        return p*b.q<b.p*q;
    }
};
enum Kind {
    Variable, Sum, Product, Power, Function, Number
};
struct Expr {
    Kind kind;
    Rational q;
    string name;
    vector<Expr> args;
};
Expr num(Rational q) {
    return {
        Number, q, "", {
        }
    };
}
Expr node(Kind k, vector<Expr> a = {
}, string s = "") {
    return {
        k, {
        }, s, a
    };
}
const Expr zero = num(0), one = num(1), minusOne = num(-1), half = num({
    1, 2
});
int compare(const Expr&a, const Expr&b) {
    if (a.kind != b.kind) return int(a.kind)-int(b.kind);
    if (a.kind == Number) return a.q == b.q?0:a.q<b.q?-1:1;
    if (a.name != b.name) return a.name<b.name?-1:1;
    for (size_t i = 0; i<min(a.args.size(), b.args.size()); ++i) {
        int c = compare(a.args[i], b.args[i]);
        if (c) return c;
    }
    return a.args.size() == b.args.size()?0:a.args.size()<b.args.size()?-1:1;
}
bool operator == (const Expr&a, const Expr&b) {
    return compare(a, b) == 0;
}
bool integer(const Expr&f) {
    return f.kind == Number && f.q.q == 1;
}
bool negative(const Expr&f) {
    return f.kind == Power && f.args[1].kind == Number && f.args[1].q.p<0;
}
Expr base(const Expr&f) {
    return f.kind == Power?f.args[0]:f;
}
Expr exponent(const Expr&f) {
    return f.kind == Power?f.args[1]:one;
}
pair<Rational, vector<Expr>> coefficient(const Expr&f) {
    if (f.kind == Number) return {
        f.q, {
        }
    };
    if (f.kind == Product) {
        if (f.args[0].kind == Number) return {
            f.args[0].q, {
                f.args.begin()+1, f.args.end()
            }
        };
        return {
            1, f.args
        };
    }
    return {
        1, {
            f
        }
    };
}
Expr product(Rational c, vector<Expr>a) {
    if (a.empty()) return num(c);
    if (!(c == Rational(1))) a.insert(a.begin(), num(c));
    return a.size() == 1?a[0]:node(Product, a);
}
int exponentCompare(const Expr&a, const Expr&b) {
    if (a.kind == Number && b.kind != Number) return -1;
    if (a.kind != Number && b.kind == Number) return 1;
    return compare(a, b);
}
int termCompare(const Expr&a, const Expr&b) {
    vector<Expr>x = coefficient(a).second, y = coefficient(b).second, bases;
    for (const Expr&f:x) bases.push_back(base(f));
    for (const Expr&f:y) bases.push_back(base(f));
    sort(bases.begin(), bases.end(), [](const Expr&s, const Expr&t) {
        return compare(s, t)<0;
    });
    bases.erase(unique(bases.begin(), bases.end()), bases.end());
    for (const Expr&f:bases) {
        Expr u = zero, v = zero;
        for (const Expr&t:x) if (base(t) == f) u = exponent(t);
        for (const Expr&t:y) if (base(t) == f) v = exponent(t);
        int c = exponentCompare(v, u);
        if (c) return c;
    }
    return 0;
}
Expr add(vector<Expr>);
Expr mul(vector<Expr>);
Expr power(Expr, Expr);
Expr fn(string, Expr);
Expr add(vector<Expr>operands) {
    vector<Expr>terms, monomials;
    vector<vector<Expr>>keys;
    vector<Rational>values;
    for (const Expr&f:operands) {
        if (f.kind == Sum) terms.insert(terms.end(), f.args.begin(), f.args.end());
        else if (f.kind == Product && f.args.size() == 2 && f.args[0].kind == Number && f.args[1].kind == Sum) {
            for (const Expr&t:f.args[1].args) terms.push_back(mul({
                f.args[0], t
            }));
        } else terms.push_back(f);
    }
    for (const Expr&f:terms) {
        auto [c, m] = coefficient(f);
        size_t i = 0;
        while (i<keys.size() && keys[i] != m)++i;
        if (i == keys.size()) {
            keys.push_back(m);
            values.push_back(c);
        } else values[i] = values[i]+c;
    }
    vector<Expr>built;
    for (size_t i = 0; i<keys.size(); ++i) if (values[i].p) built.push_back(product(values[i], keys[i]));
    sort(built.begin(), built.end(), [](const Expr&a, const Expr&b) {
        return termCompare(a, b)<0;
    });
    return built.empty()?zero:built.size() == 1?built[0]:node(Sum, built);
}
Expr mul(vector<Expr>operands) {
    vector<Expr>factors, bases;
    vector<vector<Expr>>groups;
    Rational c(1);
    for (const Expr&f:operands) if (f.kind == Product) factors.insert(factors.end(), f.args.begin(), f.args.end());
    else factors.push_back(f);
    for (const Expr&f:factors) if (f.kind == Number) c = c*f.q;
    else {
        Expr b = base(f);
        size_t i = 0;
        while (i<bases.size() && !(bases[i] == b))++i;
        if (i == bases.size()) {
            bases.push_back(b);
            groups.push_back({
            });
        }
        groups[i].push_back(f);
    }
    if (!c.p) return zero;
    vector<Expr>r;
    for (size_t i = 0; i<groups.size(); ++i) {
        vector<Expr>xs;
        for (const Expr&f:groups[i]) xs.push_back(exponent(f));
        r.push_back(groups[i].size() == 1?groups[i][0]:power(bases[i], add(xs)));
    }
    bool regroup = false;
    for (size_t i = 0; i<r.size(); ++i) {
        if (r[i].kind == Number || r[i].kind == Product) regroup = true;
        for (size_t j = 0; j<i; ++j) if (base(r[i]) == base(r[j])) regroup = true;
    }
    if (regroup) {
        r.insert(r.begin(), num(c));
        return mul(r);
    }
    sort(r.begin(), r.end(), [](const Expr&a, const Expr&b) {
        return compare(base(a), base(b))<0;
    });
    return product(c, r);
}
int64_t root(int64_t v, int64_t d) {
    if (v == 1) return 1;
    if (d>20) return -1;
    int64_t r = llround(pow(double(v), 1.0/d));
    for (int64_t s = max<int64_t>(0, r-1); s <= r+1; ++s) {
        int64_t a = 1;
        for (int64_t i = 0; i<d && a <= v; ++i) a *= s;
        if (a == v) return s;
    }
    return -1;
}
Expr rationalPower(Rational b, int64_t n) {
    if (n<0) {
        b = Rational(b.q, b.p);
        n = -n;
    }
    Rational r(1);
    while (n) {
        if (n%2) r = r*b;
        n /= 2;
        if (n) b = b*b;
    }
    return num(r);
}
Expr power(Expr b, Expr x) {
    if (x == zero) return one;
    if (x == one) return b;
    if (b.kind == Number) {
        if (b == one) return one;
        if (x.kind != Number) return node(Power, {
            b, x
        });
        if (!b.q.p) {
            if (x.q.p>0) return zero;
            throw runtime_error("division by zero");
        }
        if (integer(x)) return rationalPower(b.q, x.q.p);
        if (b.q.p>0) {
            int64_t s = root(b.q.p, x.q.q), t = root(b.q.q, x.q.q);
            if (s >= 0 && t >= 0) return rationalPower({
                s, t
            }, x.q.p);
        }
    }
    else if (integer(x)) {
        if (b.kind == Power) return power(b.args[0], mul({
            b.args[1], x
        }));
        if (b.kind == Product) {
            vector<Expr>a;
            for (const Expr&f:b.args) a.push_back(power(f, x));
            return mul(a);
        }
    }
    return node(Power, {
        b, x
    });
}
Expr fn(string s, Expr a) {
    if (s == "sqrt") return power(a, half);
    if (a == zero && (s == "sin" || s == "tan")) return zero;
    if (a == zero && (s == "cos" || s == "exp")) return one;
    if (a == one && s == "ln") return zero;
    if ((s == "sin" || s == "cos" || s == "tan") && coefficient(a).first.p<0) {
        Expr r = fn(s, mul({
            minusOne, a
        }));
        return s == "cos"?r:mul({
            minusOne, r
        });
    }
    if (a.kind == Function && ((s == "exp" && a.name == "ln") || (s == "ln" && a.name == "exp"))) return a.args[0];
    return node(Function, {
        a
    }, s);
}
set<string>variables(const Expr&f) {
    set<string>r;
    if (f.kind == Variable) r.insert(f.name);
    for (const Expr&a:f.args) {
        set<string>s = variables(a);
        r.insert(s.begin(), s.end());
    }
    return r;
}
Expr derivative(const Expr&f, const string&v) {
    if (f.kind == Number) return zero;
    if (f.kind == Variable) return f.name == v?one:zero;
    if (f.kind == Sum) {
        vector<Expr>a;
        for (const Expr&t:f.args) a.push_back(derivative(t, v));
        return add(a);
    }
    if (f.kind == Product) {
        vector<Expr>a;
        for (size_t i = 0; i<f.args.size(); ++i) {
            vector<Expr>p = f.args;
            p[i] = derivative(p[i], v);
            a.push_back(mul(p));
        }
        return add(a);
    }
    if (f.kind == Power) {
        Expr b = f.args[0], x = f.args[1];
        if (!variables(x).count(v)) return mul({
            x, power(b, add({
                x, minusOne
            })), derivative(b, v)
        });
        if (!variables(b).count(v)) return mul({
            f, fn("ln", b), derivative(x, v)
        });
        return mul({
            f, add({
                mul({
                    derivative(x, v), fn("ln", b)
                }), mul({
                    x, derivative(b, v), power(b, minusOne)
                })
            })
        });
    }
    Expr a = f.args[0], h = f.name == "sin"?fn("cos", a):f.name == "cos"?mul({
        minusOne, fn("sin", a)
    }):f.name == "tan"?power(fn("cos", a), num(-2)):f.name == "exp"?f:power(a, minusOne);
    return mul({
        h, derivative(a, v)
    });
}
Expr rebuild(const Expr&f, vector<Expr>a) {
    return f.kind == Sum?add(a):f.kind == Product?mul(a):f.kind == Power?power(a[0], a[1]):fn(f.name, a[0]);
}
Expr substitute(const Expr&f, const map<string, Expr>&m) {
    if (f.kind == Variable) {
        auto i = m.find(f.name);
        return i == m.end()?f:i->second;
    }
    if (f.kind == Number) return f;
    vector<Expr>a;
    for (const Expr&t:f.args) a.push_back(substitute(t, m));
    return rebuild(f, a);
}
vector<Expr>terms(const Expr&f) {
    return f.kind == Sum?f.args:vector<Expr> {
        f
    };
}
Expr distribute(const Expr&a, const Expr&b) {
    vector<Expr>r;
    for (const Expr&x:terms(a)) for (const Expr&y:terms(b)) r.push_back(mul({
        x, y
    }));
    return add(r);
}
Expr expand(const Expr&f) {
    if (f.kind == Variable || f.kind == Number) return f;
    vector<Expr>a;
    for (const Expr&t:f.args) a.push_back(expand(t));
    if (f.kind == Product) {
        Expr r = a[0];
        for (size_t i = 1; i<a.size(); ++i) r = distribute(r, a[i]);
        return r;
    }
    if (f.kind == Power && a[0].kind == Sum && integer(a[1]) && a[1].q.p>0) {
        Expr r = a[0];
        for (int64_t i = 1; i<a[1].q.p; ++i) r = distribute(r, a[0]);
        return r;
    }
    return rebuild(f, a);
}
double numeric(const Expr&f) {
    if (f.kind == Number) return double(f.q.p)/f.q.q;
    if (f.kind == Sum || f.kind == Product) {
        double r = f.kind == Sum?0:1;
        for (const Expr&t:f.args) {
            double x = numeric(t);
            if (f.kind == Sum) r += x;
            else r *= x;
        }
        return r;
    }
    if (f.kind == Power) {
        double u = numeric(f.args[0]), z = numeric(f.args[1]);
        bool integral = f.args[1].kind == Number?integer(f.args[1]):z == trunc(z);
        if (u<0 && !integral) throw runtime_error("domain error");
        return f.args[1] == half?sqrt(u):pow(u, z);
    }
    double a = numeric(f.args[0]);
    if (f.name == "ln") {
        if (a <= 0) throw runtime_error("domain error");
        return log(a);
    }
    return f.name == "sin"?sin(a):f.name == "cos"?cos(a):f.name == "tan"?tan(a):exp(a);
}
string show(const Expr&);
string showPower(const Expr&, const Expr&);
bool atomic(const Expr&f) {
    return f.kind == Variable || f.kind == Function || (integer(f) && f.q.p >= 0) || (f.kind == Power && f.args[1] == half);
}
string atom(const Expr&f) {
    return atomic(f)?show(f):"("+show(f)+")";
}
string showPower(const Expr&b, const Expr&x) {
    return x == half?"sqrt("+show(b)+")":atom(b)+"^"+atom(x);
}
string factor(const Expr&f) {
    return f.kind == Sum?"("+show(f)+")":f.kind == Power?showPower(f.args[0], f.args[1]):show(f);
}
string join(const vector<string>&a, string sep) {
    string r;
    for (const string&s:a) {
        if (!r.empty()) r += sep;
        r += s;
    }
    return r;
}
string quotient(Rational c, const vector<Expr>&a) {
    vector<string>top, bottom;
    if (abs(c.p) != 1) top.push_back(to_string(abs(c.p)));
    if (c.q != 1) bottom.push_back(to_string(c.q));
    for (const Expr&f:a) if (negative(f)) {
        Expr r = num(-f.args[1].q);
        bottom.push_back(r == one?factor(f.args[0]):showPower(f.args[0], r));
    } else top.push_back(factor(f));
    string s = top.empty()?"1":join(top, "*");
    if (bottom.size() == 1) s += "/"+bottom[0];
    else if (!bottom.empty()) s += "/("+join(bottom, "*")+")";
    return c.p<0?"-"+s:s;
}
string show(const Expr&f) {
    if (f.kind == Number) return to_string(f.q.p)+(f.q.q == 1?"":"/"+to_string(f.q.q));
    if (f.kind == Variable) return f.name;
    if (f.kind == Function) return f.name+"("+show(f.args[0])+")";
    if (f.kind == Power) return negative(f)?quotient(1, {
        f
    }):showPower(f.args[0], f.args[1]);
    if (f.kind == Product) {
        auto [c, a] = coefficient(f);
        return quotient(c, a);
    }
    string r = show(f.args[0]);
    for (size_t i = 1; i<f.args.size(); ++i) {
        string s = show(f.args[i]);
        r += s[0] == '-'?" - "+s.substr(1):" + "+s;
    }
    return r;
}
const set<string>functions = {
    "sin", "cos", "tan", "exp", "ln", "sqrt"
};
struct Syntax {
    string op;
    Expr value;
    vector<Syntax>args;
};
class Parser {
    vector<string>tokens;
    size_t position = 0;
    const map<string, Expr>&names;
    string peek() {
        return position<tokens.size()?tokens[position]:"";
    }
    [[noreturn]] void unexpected() {
        throw runtime_error(position == tokens.size()?"unexpected end of expression":"unexpected '"+peek()+"'");
    }
    bool accept(string s) {
        if (peek() != s) return false;
        ++position;
        return true;
    }
    void expect(string s) {
        if (!accept(s)) unexpected();
    }
    Syntax atomTree() {
        string t = peek();
        if (t.empty()) unexpected();
        if (accept("(")) {
            Syntax a = expression();
            expect(")");
            return a;
        }
        if (!isalnum(t[0])) unexpected();
        ++position;
        if (isdigit(t[0])) return {
            "", num(stoll(t)), {
            }
        };
        if (isupper(t[0])) {
            auto i = names.find(t);
            if (i == names.end()) throw runtime_error("undefined name '"+t+"'");
            return {
                "", i->second, {
                }
            };
        }
        if (!functions.count(t)) return {
            "", node(Variable, {
            }, t), {
            }
        };
        expect("(");
        Syntax a = expression();
        expect(")");
        return {
            t, zero, {
                a
            }
        };
    }
    Syntax unary() {
        if (accept("-")) return {
            "neg", zero, {
                unary()
            }
        };
        Syntax a = atomTree();
        if (accept("^")) return {
            "^", zero, {
                a, unary()
            }
        };
        return a;
    }
    Syntax term() {
        Syntax a = unary();
        while (peek() == "*" || peek() == "/") {
            string op = tokens[position++];
            a = {
                op, zero, {
                    a, unary()
                }
            };
        }
        return a;
    }
    Syntax expression() {
        Syntax a = term();
        while (peek() == "+" || peek() == "-") {
            string op = tokens[position++];
            a = {
                op, zero, {
                    a, term()
                }
            };
        }
        return a;
    }
    Expr evaluate(const Syntax&t) {
        if (t.op.empty()) return t.value;
        vector<Expr>a;
        for (const Syntax&s:t.args) a.push_back(evaluate(s));
        if (t.op == "+") return add(a);
        if (t.op == "-") return add({
            a[0], mul({
                minusOne, a[1]
            })
        });
        if (t.op == "*") return mul(a);
        if (t.op == "/") return mul({
            a[0], power(a[1], minusOne)
        });
        if (t.op == "^") return power(a[0], a[1]);
        if (t.op == "neg") return mul({
            minusOne, a[0]
        });
        return fn(t.op, a[0]);
    }
    public:
    Parser(const string&text, const map<string, Expr>&n):names(n) {
        for (size_t p = 0; p<text.size(); ) {
            char c = text[p];
            if (c == ' ') {
                ++p;
                continue;
            }
            size_t start = p++;
            if (isdigit(c)) {
                while (p<text.size() && isdigit(text[p]))++p;
            } else if (islower(c)) {
                while (p<text.size() && (islower(text[p]) || isdigit(text[p])))++p;
            } else if (isupper(c)) {
                while (p<text.size() && (isupper(text[p]) || isdigit(text[p])))++p;
            } else if (string("+-*/^()").find(c) == string::npos) throw runtime_error(string("invalid character '")+c+"'");
            tokens.push_back(text.substr(start, p-start));
        }
    }
    Expr parse() {
        Syntax t = expression();
        if (position<tokens.size()) unexpected();
        return evaluate(t);
    }
};
string trim(string s) {
    size_t b = s.find_first_not_of(' ');
    return b == string::npos?"":s.substr(b, s.find_last_not_of(' ')-b+1);
}
vector<string>split(const string&s, char delim) {
    vector<string>r;
    size_t start = 0;
    for (size_t i = 0; i <= s.size(); ++i) if (i == s.size() || s[i] == delim) {
        r.push_back(s.substr(start, i-start));
        start = i+1;
    }
    return r;
}
bool variable(string s) {
    if (s.empty() || !islower(s[0]) || functions.count(s)) return false;
    return all_of(s.begin(), s.end(), [](char c) {
        return islower(c) || isdigit(c);
    });
}
bool digits(string s) {
    return !s.empty() && all_of(s.begin(), s.end(), [](char c) {
        return isdigit(c);
    });
}
bool rationalLiteral(string s) {
    if (!s.empty() && s[0] == '-') s = s.substr(1);
    vector<string>a = split(s, '/');
    return (a.size() == 1 || a.size() == 2) && digits(a[0]) && (a.size() == 1 || digits(a[1]));
}
Expr literal(string s) {
    if (!rationalLiteral(s)) throw runtime_error("invalid number '"+s+"'");
    vector<string>a = split(s, '/');
    return num(Rational(stoll(a[0]), a.size() == 1?1:stoll(a[1])));
}
const map<string, string>signatures = {
    {
        "SIMPLIFY", "e"
    }, {
        "EXPAND", "e"
    }, {
        "DIFF", "ev"
    }, {
        "DIFFN", "evn"
    }, {
        "GRAD", "e"
    }, {
        "HESSIAN", "e"
    }, {
        "IMPLICIT", "evv"
    }, {
        "SUBST", "eve"
    }, {
        "EVAL", "ea"
    }, {
        "TANGENT", "evc"
    }, {
        "LIMIT", "evc"
    }, {
        "TAYLOR", "evcn"
    }
};
vector<string>command(string line, map<string, Expr>&names) {
    size_t p = line.find(' ');
    string c = line.substr(0, p), arg = p == string::npos?"":line.substr(p+1);
    if (c == "LET") {
        size_t i = arg.find('=');
        if (i == string::npos) throw runtime_error("wrong number of arguments");
        string s = trim(arg.substr(0, i));
        if (s.empty() || !isupper(s[0]) || !all_of(s.begin(), s.end(), [](char ch) {
            return isupper(ch) || isdigit(ch);
        })) throw runtime_error("invalid name '"+s+"'");
        Expr f = Parser(trim(arg.substr(i+1)), names).parse();
        names[s] = f;
        return {
            s+" = "+show(f)
        };
    }
    auto sig = signatures.find(c);
    if (sig == signatures.end()) throw runtime_error("unknown command "+c);
    vector<string>fields = p == string::npos?vector<string> {
    }:split(arg, ';');
    for (string&s:fields) s = trim(s);
    if (c == "EVAL"?(fields.size() != 1 && fields.size() != 2):fields.size() != sig->second.size()) throw runtime_error("wrong number of arguments");
    vector<Expr>forms(fields.size(), zero);
    int n = 0;
    for (size_t i = 0; i<fields.size(); ++i) {
        char k = sig->second[i];
        string s = fields[i];
        if (k == 'e') forms[i] = Parser(s, names).parse();
        else if (k == 'v' && !variable(s)) throw runtime_error("invalid variable '"+s+"'");
        else if (k == 'n') {
            if (s.size() != 1 || s[0]<'1' || s[0]>'8') throw runtime_error("invalid order '"+s+"'");
            n = s[0]-'0';
        } else if (k == 'c') forms[i] = literal(s);
    }
    Expr f = forms[0];
    string v = fields.size()>1?fields[1]:"";
    vector<string>out;
    if (c == "SIMPLIFY") return {
        "simplified: "+show(f)
    };
    if (c == "EXPAND") return {
        "expanded: "+show(expand(f))
    };
    if (c == "DIFF") return {
        "d/d"+v+" = "+show(derivative(f, v))
    };
    if (c == "DIFFN") {
        for (int k = 1; k <= n; ++k) {
            f = derivative(f, v);
            out.push_back("d^"+to_string(k)+"/d"+v+"^"+to_string(k)+" = "+show(f));
        }
        return out;
    }
    if (c == "GRAD" || c == "HESSIAN") {
        set<string>vs = variables(f);
        if (vs.empty()) return {
            "no variables"
        };
        for (auto i = vs.begin(); i != vs.end(); ++i) {
            Expr d = derivative(f, *i);
            if (c == "GRAD") out.push_back("d/d"+*i+" = "+show(d));
            else for (auto j = i; j != vs.end(); ++j) out.push_back("d2/d"+*i+"d"+*j+" = "+show(derivative(d, *j)));
        }
        return out;
    }
    if (c == "IMPLICIT") {
        string w = fields[2];
        if (v == w) throw runtime_error("same variable");
        return {
            "d"+w+"/d"+v+" = "+show(mul({
                minusOne, derivative(f, v), power(derivative(f, w), minusOne)
            }))
        };
    }
    if (c == "SUBST") return {
        "substituted: "+show(substitute(f, {
            {
                v, forms[2]
            }
        }))
    };
    if (c == "EVAL") {
        map<string, Expr>values;
        for (const string&word:fields.size() == 2?split(fields[1], ' '):vector<string> {
        }) {
            if (word.empty()) continue;
            size_t i = word.find('=');
            string s = word.substr(0, i), t = i == string::npos?"":word.substr(i+1);
            if (i == string::npos || !variable(s) || !rationalLiteral(t)) throw runtime_error("invalid assignment '"+word+"'");
            Expr q = literal(t);
            if (values.count(s)) throw runtime_error("duplicate variable "+s);
            values[s] = q;
        }
        for (const string&s:variables(f)) if (!values.count(s)) throw runtime_error("no value for "+s);
        Expr r = substitute(f, values);
        if (r.kind == Number) return {
            "exact: "+show(r)
        };
        ostringstream s;
        s<<fixed<<setprecision(6)<<numeric(r);
        return {
            "approx: "+s.str()
        };
    }
    Expr x = forms[2];
    map<string, Expr>point = {
        {
            v, x
        }
    };
    if (c == "TANGENT") {
        Expr slope = substitute(derivative(f, v), point), y = substitute(f, point), z = node(Variable, {
        }, v);
        string t = "tangent: y = "+show(add({
            mul({
                slope, z
            }), y, mul({
                num(-x.q), slope
            })
        }));
        if (slope == zero) return {
            t, "normal: "+v+" = "+show(x)
        };
        Expr k = power(slope, minusOne);
        return {
            t, "normal: y = "+show(add({
                mul({
                    minusOne, k, z
                }), y, mul({
                    x, k
                })
            }))
        };
    }
    if (c == "LIMIT") {
        vector<Expr>top, bottom;
        for (const Expr&t:f.kind == Product?f.args:vector<Expr> {
            f
        }) if (negative(t)) bottom.push_back(power(t.args[0], num(-t.args[1].q)));
        else top.push_back(t);
        Expr g = mul(top), h = mul(bottom);
        for (int i = 0; i <= 5; ++i) {
            Expr u = substitute(g, point), b = substitute(h, point);
            if (!(b == zero)) return {
                "limit: "+show(mul({
                    u, power(b, minusOne)
                }))
            };
            if (!(u == zero)) return {
                "limit: unbounded"
            };
            if (i<5) {
                g = derivative(g, v);
                h = derivative(h, v);
            }
        }
        return {
            "limit: unknown"
        };
    }
    vector<Expr>ds = {
        f
    }, ps;
    for (int i = 0; i<n; ++i) ds.push_back(derivative(ds.back(), v));
    int factorial = 1;
    for (int i = 0; i <= n; ++i) {
        if (i) factorial *= i;
        Expr co = mul({
            substitute(ds[i], point), num(Rational(1, factorial))
        });
        ps.push_back(mul({
            co, power(add({
                node(Variable, {
                }, v), num(-x.q)
            }), num(i))
        }));
    }
    return {
        "taylor: "+show(expand(add(ps)))
    };
}
int main() {
    int n;
    cin>>n;
    string line;
    getline(cin, line);
    map<string, Expr>names;
    while (n-- && getline(cin, line)) {
        try {
            for (const string&s:command(line, names)) cout<<s<<'\n';
        } catch (const runtime_error&e) {
            cout<<"error: "<<e.what()<<'\n';
        }
    }
}
