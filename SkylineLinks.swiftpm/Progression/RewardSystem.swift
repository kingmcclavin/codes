import Foundation

struct HoleScore {
    let par: Int
    let strokes: Int

    var toPar: Int { strokes - par }
}

struct RoundResult {
    let courseIndex: Int
    let courseID: String
    let courseName: String
    let length: RoundLength
    let difficulty: Int
    let target: Int
    let scores: [HoleScore]

    var toPar: Int { scores.reduce(0) { $0 + $1.toPar } }
    var totalStrokes: Int { scores.reduce(0) { $0 + $1.strokes } }
    var targetBeaten: Bool { toPar <= target }

    var holesInOne: Int { scores.filter { $0.strokes == 1 }.count }
    var albatrosses: Int { scores.filter { $0.toPar <= -3 && $0.strokes != 1 }.count }
    var eagles: Int { scores.filter { $0.toPar == -2 && $0.strokes != 1 }.count }
    var birdies: Int { scores.filter { $0.toPar == -1 && $0.strokes != 1 }.count }
}

struct RewardLine: Identifiable {
    let id = UUID()
    let label: String
    let coins: Int
}

struct RewardBreakdown {
    var lines: [RewardLine] = []
    var xp: Int = 0
    var firstTimeBeaten = false
    var unlockedCourseName: String? = nil
    var newBest = false

    var totalCoins: Int { lines.reduce(0) { $0 + $1.coins } }
}

enum RewardSystem {
    static let perHole = 15
    static let perBirdie = 40
    static let perEagle = 120
    static let perAlbatross = 300
    static let perHoleInOne = 500

    static func calculate(_ r: RoundResult, alreadyBeaten: Bool) -> RewardBreakdown {
        var b = RewardBreakdown()
        let holes = r.scores.count
        let scale = Double(holes) / 3.0
        let difficultyBonus = 1.0 + Double(r.difficulty - 1) * 0.15

        b.lines.append(RewardLine(label: "\(holes) holes completed", coins: perHole * holes))
        b.lines.append(RewardLine(label: "Round complete", coins: Int(40 * scale)))
        if r.targetBeaten {
            b.lines.append(RewardLine(label: "Target beaten", coins: Int(100 * scale * difficultyBonus)))
            if !alreadyBeaten {
                b.firstTimeBeaten = true
                b.lines.append(RewardLine(label: "First victory bonus", coins: Int(250 * difficultyBonus)))
            }
        }
        if r.birdies > 0 { b.lines.append(RewardLine(label: "\(r.birdies) Birdie\(r.birdies == 1 ? "" : "s")", coins: r.birdies * perBirdie)) }
        if r.eagles > 0 { b.lines.append(RewardLine(label: "\(r.eagles) Eagle\(r.eagles == 1 ? "" : "s")", coins: r.eagles * perEagle)) }
        if r.albatrosses > 0 { b.lines.append(RewardLine(label: "\(r.albatrosses) Albatross", coins: r.albatrosses * perAlbatross)) }
        if r.holesInOne > 0 { b.lines.append(RewardLine(label: "\(r.holesInOne) Hole-in-One!", coins: r.holesInOne * perHoleInOne)) }

        b.xp = holes * 10 + (r.birdies + r.eagles * 2 + r.holesInOne * 4) * 20 + (r.targetBeaten ? Int(50 * scale) : 0)
        return b
    }

    /// Applies a finished round to the save data and returns what was earned.
    static func apply(_ r: RoundResult, to p: inout PlayerProgress) -> RewardBreakdown {
        let key = PlayerProgress.scoreKey(courseID: r.courseID, length: r.length)
        var b = calculate(r, alreadyBeaten: p.beatenTargets.contains(key))
        p.coins += b.totalCoins
        p.xp += b.xp
        p.roundsPlayed += 1
        p.holesInOne += r.holesInOne
        p.birdiesOrBetter += r.birdies + r.eagles + r.albatrosses + r.holesInOne

        if let best = p.bestScores[key] {
            if r.toPar < best {
                p.bestScores[key] = r.toPar
                b.newBest = true
            }
        } else {
            p.bestScores[key] = r.toPar
            b.newBest = true
        }

        if r.targetBeaten {
            p.beatenTargets.insert(key)
            p.completedChallenges.insert("beat-\(r.courseID)")
            let next = r.courseIndex + 1
            if next < CourseDatabase.count && p.unlockedCourses <= next {
                p.unlockedCourses = next + 1
                b.unlockedCourseName = CourseDatabase.infos[next].name
            }
        }
        return b
    }
}
