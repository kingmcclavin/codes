# StudyOS

A personal academic operating system for iPad. It answers three questions:

1. **What do I need to do?** Assignments, exams, classes.
2. **What do I need to study?** Study sessions and, in later phases, materials and practice.
3. **How am I doing?** Grades, GPA and study time.

StudyOS is a standalone app. It does not read, depend on, or share code with
**Basis**. A later phase adds an optional, explicit import of `BasisStudyPackage`
files that Basis exports, using the Files app, document picker and Share Sheet.

## Opening it on iPad (no Mac needed)

1. Get the `StudyOS.swiftpm` folder onto your iPad, using either option:
   - On GitHub, open the repository, choose **Code → Download ZIP**, then open the
     ZIP in the Files app to unzip it.
   - Clone the repository with a Git app such as Working Copy.
2. In the Files app, tap **`StudyOS/StudyOS.swiftpm`**. It opens in Swift Playgrounds.
3. Press **Run** (▶︎). Swift Playgrounds 4.4 or later is required (iPadOS 17+).

To try the app before entering real data, use **Explore with Sample Data** on the
Dashboard, or go to **More → Load Sample Data**.

## Getting an .ipa

Every push that changes `StudyOS/` runs the **StudyOS** GitHub Actions workflow
(`.github/workflows/studyos.yml`) on GitHub's macOS machines. The workflow:

- runs the logic tests,
- compiles the full app for iPad, and
- uploads **`StudyOS-unsigned.ipa`** as a downloadable artifact on the run's page, and
- launches the app in an iPad simulator, checks it stays running in every section, and
  saves screenshots (light and dark) to the `studyos-screenshots` branch.

To run it yourself, go to the repository's **Actions → StudyOS → Run workflow**. This
works from Safari on iPad. The `.ipa` is unsigned: sideloading tools such as
AltStore or SideStore sign it with your Apple ID when installing.

You can also distribute directly from Swift Playgrounds via **App Settings → Upload
to App Store Connect** (TestFlight). That route needs a paid Apple Developer account.

## Project layout

```
StudyOS/
├── StudyOS.swiftpm/          ← the app (open this in Swift Playgrounds)
│   ├── Package.swift         ← app settings: name, icon, iPadOS 17+
│   ├── App/                  ← app entry point, sidebar, navigation
│   ├── Models/               ← Codable data models
│   ├── Persistence/          ← JSON file storage with backup and recovery
│   ├── Logic/                ← grade, GPA, schedule and study calculations (no UI)
│   ├── Store/                ← AcademicStore: the single source of truth
│   └── UI/                   ← SwiftUI views, one folder per section
└── Tests/                    ← developer-only logic tests (not part of the app)
```

Layering rules that keep later phases manageable:

- `Models`, `Persistence` and `Logic` import only Foundation. They can be tested
  without a device.
- Views never edit data directly. They call `AcademicStore` methods, which save
  automatically.
- Each model decodes missing fields with defaults. Data saved by older versions
  keeps loading as new fields are added.

## Data and privacy

- Everything is stored on the iPad as a readable JSON file:
  `Application Support/StudyOS/StudyOS-Data.json`.
- Each save is atomic, and the previous version is kept as `StudyOS-Data.backup.json`.
- If a data file is ever unreadable, StudyOS moves it aside (it is never overwritten),
  restores the backup and tells you.
- **More → Export All Data** produces a portable JSON copy you can share or keep.
- No account, network connection or server is needed.

## How grades are calculated

These numbers are **actual**: they come only from grades you entered.

- **Course without categories:** total points earned ÷ total points possible.
- **Course with weighted categories:** each category's average is its points earned ÷
  points possible. Category averages are combined by weight, counting only categories
  that have grades so far. That is the running grade most school portals show.
  Graded work with no category is listed but not counted, and StudyOS points it out.
- **Manual grade:** if you type a course's current grade by hand, it is shown instead of
  the calculated one and labelled **Manual**.
- **GPA:**
  - **Actual** cumulative GPA uses only recorded final letter grades, plus any
    earlier credits and GPA entered in More.
  - **Projected** GPA also counts in-progress courses at their current letter grade.
    It is always labelled **Projected**.

## Roadmap

| Phase | Scope | Status |
|---|---|---|
| 1 / MVP | App shell, sidebar, Dashboard, Courses, local persistence, plus the MVP slices of assignments, exams, grades and the study timer | **Done (this version)** |
| 2 | Calendar (month/week/day), richer exams, local notifications | Next |
| 3 | Grade projections ("What do I need?"), hypothetical scenarios, custom grading scales, GPA history | |
| 4 | Study goals, statistics and charts, streaks | |
| 5 | Materials library (PDFs, images, documents), organization, global search | |
| 6 | Flashcards, practice questions, practice exams, quiz mode | |
| 7 | `BasisStudyPackage` import, source tracking, "Open Source" links | |
| 8 | Optional AI study tools behind a replaceable `AIStudyService` | |
| 9 | Polish: charts, animations, accessibility, layouts, full export/import | |

## Developer notes

`Tests/run-logic-tests.sh` compiles `Models`, `Persistence` and `Logic` with
`swiftc` and runs `Tests/LogicTests/main.swift`. It works on Linux and macOS, and
runs automatically in GitHub Actions. You never need it to use or build the app.
