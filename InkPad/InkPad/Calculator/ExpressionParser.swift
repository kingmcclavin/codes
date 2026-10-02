import Foundation

// MARK: - Errors

/// Every way a calculation can fail. Malformed input never crashes; it
/// produces one of these with a readable message.
enum CalcError: Error, Equatable, LocalizedError {
    case invalidExpression(String)
    case missingVariable(String)
    case divisionByZero
    case domain(String)
    case unknownFunction(String)
    case argumentCount(function: String, expected: String)
    case circularDependency([String])
    case notFinite

    var errorDescription: String? {
        switch self {
        case let .invalidExpression(m): return "Invalid expression: \(m)"
        case let .missingVariable(n): return "Missing variable: \(n)"
        case .divisionByZero: return "Division by zero"
        case let .domain(m): return m
        case let .unknownFunction(n): return "Unknown function: \(n)"
        case let .argumentCount(f, e): return "\(f) expects \(e)"
        case let .circularDependency(chain): return "Circular formula dependency detected: \(chain.joined(separator: " → "))"
        case .notFinite: return "Result is too large or undefined"
        }
    }
}

// MARK: - Tokens

enum Token: Equatable {
    case number(Double)
    case identifier(String)
    case op(Character)          // + - * / ^
    case lparen, rparen, comma, pipe, equals
    case sqrt, cbrt
    case postfix(Character)     // ! % °
}

/// Converts text into tokens. Accepts calculator-style input: × ÷ − · ² ³ ½ √ π,
/// scientific notation (1.2e-3), subscripts (x₁) and `**` for powers.
enum Lexer {
    private static let superscripts: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
        "⁻": "-",
    ]
    private static let fractions: [Character: Double] = ["½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75, "⅛": 0.125]
    private static let subscripts: Set<Character> = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉", "ₓ", "ᵢ", "ₙ"]

    static func isIdentifierStart(_ c: Character) -> Bool {
        (c.isLetter || c == "_") && superscripts[c] == nil && !subscripts.contains(c) && fractions[c] == nil
    }

    static func isIdentifierBody(_ c: Character) -> Bool {
        isIdentifierStart(c) || c.isASCII && c.isNumber || subscripts.contains(c) || c == "'"
    }

    static func tokenize(_ text: String) throws -> [Token] {
        let chars = Array(text)
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }

            // Numbers (with scientific notation).
            if c.isASCII && c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isASCII && chars[i + 1].isNumber) {
                var s = ""
                while i < chars.count, chars[i].isASCII && (chars[i].isNumber || chars[i] == ".") {
                    s.append(chars[i]); i += 1
                }
                if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                    var j = i + 1
                    var exp = "e"
                    if j < chars.count, chars[j] == "+" || chars[j] == "-" || chars[j] == "−" {
                        exp.append(chars[j] == "+" ? "+" : "-"); j += 1
                    }
                    if j < chars.count, chars[j].isASCII && chars[j].isNumber {
                        while j < chars.count, chars[j].isASCII && chars[j].isNumber { exp.append(chars[j]); j += 1 }
                        s += exp
                        i = j
                    }
                }
                guard s.filter({ $0 == "." }).count <= 1, let v = Double(s) else {
                    throw CalcError.invalidExpression("bad number \"\(s)\"")
                }
                tokens.append(.number(v))
                continue
            }

            if let v = fractions[c] { tokens.append(.number(v)); i += 1; continue }

            // Superscript powers: x² → x ^ 2, 10⁻³ → 10 ^ -3
            if superscripts[c] != nil {
                var s = ""
                while i < chars.count, let d = superscripts[chars[i]] {
                    s.append(d); i += 1
                }
                guard let v = Double(s) else { throw CalcError.invalidExpression("bad exponent") }
                tokens.append(.op("^"))
                tokens.append(.number(v))
                continue
            }

            if isIdentifierStart(c) {
                var s = ""
                while i < chars.count, isIdentifierBody(chars[i]) { s.append(chars[i]); i += 1 }
                tokens.append(.identifier(s))
                continue
            }

            switch c {
            case "+": tokens.append(.op("+"))
            case "-", "−", "–": tokens.append(.op("-"))
            case "*":
                if i + 1 < chars.count, chars[i + 1] == "*" { tokens.append(.op("^")); i += 1 } else { tokens.append(.op("*")) }
            case "×", "·", "⋅", "∙": tokens.append(.op("*"))
            case "/", "÷": tokens.append(.op("/"))
            case "^": tokens.append(.op("^"))
            case "(", "[", "{": tokens.append(.lparen)
            case ")", "]", "}": tokens.append(.rparen)
            case ",", ";": tokens.append(.comma)
            case "|": tokens.append(.pipe)
            case "=": tokens.append(.equals)
            case "√": tokens.append(.sqrt)
            case "∛": tokens.append(.cbrt)
            case "!", "%", "°": tokens.append(.postfix(c))
            default:
                throw CalcError.invalidExpression("unexpected character \"\(c)\"")
            }
            i += 1
        }
        return tokens
    }
}

// MARK: - Syntax tree

indirect enum Expr: Equatable {
    case number(Double)
    case variable(String)
    case negate(Expr)
    case binary(Character, Expr, Expr)
    case call(String, [Expr])
    case postfix(Character, Expr)

    /// Free identifiers in order of first appearance.
    var variables: [String] {
        var seen: [String] = []
        func walk(_ e: Expr) {
            switch e {
            case .number: break
            case let .variable(n): if !seen.contains(n) { seen.append(n) }
            case let .negate(x), let .postfix(_, x): walk(x)
            case let .binary(_, l, r): walk(l); walk(r)
            case let .call(_, args): args.forEach(walk)
            }
        }
        walk(self)
        return seen
    }
}

/// One line of input: `name = expression` or a bare expression.
struct Statement: Equatable {
    var target: String?
    var expression: Expr
}

/// Recursive-descent parser.
///
/// Precedence (low → high): + −, × ÷ (and implicit multiplication), unary −,
/// ^ (right associative), postfix (! % °), primary.
/// `-2^2 = -4`, `2^3^2 = 512`, `2a(b+1)` = `2*a*(b+1)`.
struct ExpressionParser {
    /// Names that must never be split into single-letter products (declared
    /// variables, saved variables, formula outputs).
    var knownNames: Set<String> = []

    func parseStatement(_ text: String) throws -> Statement {
        let tokens = try Lexer.tokenize(text)
        guard !tokens.isEmpty else { throw CalcError.invalidExpression("empty expression") }
        if tokens.count >= 2, case let .identifier(name) = tokens[0], tokens[1] == .equals {
            guard tokens.count > 2 else { throw CalcError.invalidExpression("nothing after \"=\"") }
            var p = Cursor(tokens: Array(tokens.dropFirst(2)), knownNames: knownNames)
            let e = try p.parseAll()
            return Statement(target: name, expression: e)
        }
        var p = Cursor(tokens: tokens, knownNames: knownNames)
        return Statement(target: nil, expression: try p.parseAll())
    }

    func parseExpression(_ text: String) throws -> Expr {
        let s = try parseStatement(text)
        guard s.target == nil else { throw CalcError.invalidExpression("unexpected \"=\"") }
        return s.expression
    }

    private struct Cursor {
        let tokens: [Token]
        let knownNames: Set<String>
        var index = 0

        init(tokens: [Token], knownNames: Set<String>) {
            self.tokens = tokens
            self.knownNames = knownNames
        }

        var peek: Token? { index < tokens.count ? tokens[index] : nil }

        mutating func next() -> Token? {
            defer { index += 1 }
            return peek
        }

        mutating func parseAll() throws -> Expr {
            let e = try parseAdditive()
            if let t = peek {
                if t == .equals { throw CalcError.invalidExpression("only one \"=\" is allowed, as in \"name = expression\"") }
                if t == .rparen { throw CalcError.invalidExpression("unmatched \")\"") }
                throw CalcError.invalidExpression("unexpected \(Self.describe(t))")
            }
            return e
        }

        mutating func parseAdditive() throws -> Expr {
            var lhs = try parseMultiplicative()
            while case let .op(o)? = peek, o == "+" || o == "-" {
                index += 1
                lhs = .binary(o, lhs, try parseMultiplicative())
            }
            return lhs
        }

        mutating func parseMultiplicative() throws -> Expr {
            var lhs = try parseUnary()
            while true {
                if case let .op(o)? = peek, o == "*" || o == "/" {
                    index += 1
                    lhs = .binary(o, lhs, try parseUnary())
                } else if startsImplicitOperand(peek) {
                    lhs = .binary("*", lhs, try parsePower())
                } else {
                    return lhs
                }
            }
        }

        func startsImplicitOperand(_ t: Token?) -> Bool {
            switch t {
            case .number?, .identifier?, .lparen?, .sqrt?, .cbrt?: return true
            default: return false
            }
        }

        mutating func parseUnary() throws -> Expr {
            if case let .op(o)? = peek, o == "-" || o == "+" {
                index += 1
                let operand = try parseUnary()
                return o == "-" ? .negate(operand) : operand
            }
            return try parsePower()
        }

        mutating func parsePower() throws -> Expr {
            let base = try parsePostfix()
            if case .op("^")? = peek {
                index += 1
                return .binary("^", base, try parseUnary())   // right associative, allows 2^-1
            }
            return base
        }

        mutating func parsePostfix() throws -> Expr {
            var e = try parsePrimary()
            while case let .postfix(c)? = peek {
                index += 1
                e = .postfix(c, e)
            }
            return e
        }

        mutating func parsePrimary() throws -> Expr {
            guard let t = next() else { throw CalcError.invalidExpression("expression ends too early") }
            switch t {
            case let .number(v):
                return .number(v)
            case .lparen:
                let e = try parseAdditive()
                guard next() == .rparen else { throw CalcError.invalidExpression("missing \")\"") }
                return e
            case .pipe:
                let e = try parseAdditive()
                guard next() == .pipe else { throw CalcError.invalidExpression("missing closing \"|\"") }
                return .call("abs", [e])
            case .sqrt:
                return .call("sqrt", [try parsePower()])
            case .cbrt:
                return .call("cbrt", [try parsePower()])
            case let .identifier(name):
                if peek == .lparen, MathFunctions.isFunction(name) {
                    index += 1
                    var args: [Expr] = []
                    if peek != .rparen {
                        args.append(try parseAdditive())
                        while peek == .comma {
                            index += 1
                            args.append(try parseAdditive())
                        }
                    }
                    guard next() == .rparen else { throw CalcError.invalidExpression("missing \")\" after \(name)(") }
                    return .call(MathFunctions.canonicalName(name), args)
                }
                if MathFunctions.isFunction(name) && !knownNames.contains(name) {
                    // Function written without parentheses: sin x, ln 2
                    guard startsImplicitOperand(peek) else {
                        throw CalcError.invalidExpression("\(name) needs an argument, e.g. \(name)(x)")
                    }
                    return .call(MathFunctions.canonicalName(name), [try parsePower()])
                }
                return Self.splitIdentifier(name, known: knownNames)
            case .rparen:
                throw CalcError.invalidExpression("unexpected \")\"")
            case .equals:
                throw CalcError.invalidExpression("unexpected \"=\"")
            case .comma:
                throw CalcError.invalidExpression("unexpected \",\"")
            case let .op(o):
                throw CalcError.invalidExpression("missing number before \"\(o)\"")
            case let .postfix(c):
                throw CalcError.invalidExpression("unexpected \"\(c)\"")
            }
        }

        /// Short all-lowercase names like `ac`, `mv`, `mgh` are read as
        /// products of single-letter variables (so `4ac` and `½mv²` work), unless
        /// they are known names, functions, constants or Greek letter names.
        static func splitIdentifier(_ name: String, known: Set<String>) -> Expr {
            let letters = Array(name)
            let splittable = (2...3).contains(letters.count)
                && letters.allSatisfy { $0.isASCII && $0.isLowercase }
                && !known.contains(name)
                && !Constants.isConstant(name)
                && !greekNames.contains(name)
                && !reservedWords.contains(name)
            guard splittable else { return .variable(name) }
            var e: Expr = .variable(String(letters[0]))
            for c in letters.dropFirst() { e = .binary("*", e, .variable(String(c))) }
            return e
        }

        static let greekNames: Set<String> = ["mu", "nu", "xi", "pi", "rho", "tau", "phi", "chi", "psi", "eta", "ans"]
        static let reservedWords: Set<String> = ["max", "min", "deg", "rad"]

        static func describe(_ t: Token) -> String {
            switch t {
            case let .number(v): return "number \(v)"
            case let .identifier(n): return "\"\(n)\""
            case let .op(o): return "\"\(o)\""
            case .lparen: return "\"(\""
            case .rparen: return "\")\""
            case .comma: return "\",\""
            case .pipe: return "\"|\""
            case .equals: return "\"=\""
            case .sqrt: return "\"√\""
            case .cbrt: return "\"∛\""
            case let .postfix(c): return "\"\(c)\""
            }
        }
    }
}
