import SwiftUI

/// Developer debugger: registers, disassembly, stack, memory, I/O ports, interrupt,
/// LCD, keypad and timer state, with run / pause / step / reset and breakpoints.
struct DebuggerView: View {
    @EnvironmentObject private var controller: EmulatorController
    let runner: EmulatorRunner

    @State private var snapshot: DebugSnapshot?
    @State private var memoryText = "D00000"
    @State private var portText = "5000"
    @State private var breakpointText = ""
    @State private var breakpoints: [UInt32] = []

    private let refresh = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            controls
            if let s = snapshot {
                cpuSection(s)
                disassemblySection(s)
                breakpointSection
                memorySection(s)
                ioSection(s)
                table("Interrupts", s.interrupts)
                table("LCD", s.lcd)
                table("Keypad", s.keypad)
                table("Timers", s.timers)
                table("Stack", s.stack)
                if let u = s.lastUnsupported {
                    Section("Last diagnostic") { Text(u).font(.caption.monospaced()).foregroundColor(.orange) }
                }
            } else {
                Text("Reading state…").foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Debugger")
        .onAppear(perform: update)
        .onReceive(refresh) { _ in if !controller.isPaused { update() } }
        .onChange(of: controller.isPaused) { _ in update() }
    }

    // MARK: Sections

    private var controls: some View {
        Section {
            HStack(spacing: 10) {
                button(controller.isPaused ? "Run" : "Pause", controller.isPaused ? "play.fill" : "pause.fill") {
                    controller.togglePause()
                }
                button("Step", "arrow.down.to.line") {
                    if !controller.isPaused { controller.togglePause() }
                    runner.step { update() }
                }
                .disabled(!controller.isPaused)
                button("Reset", "arrow.counterclockwise") {
                    controller.resetCalculator()
                    update()
                }
            }
            .buttonStyle(.bordered)
            if let pc = controller.breakpointAddress {
                Text(String(format: "Stopped at breakpoint %06X", pc)).foregroundColor(.orange).font(.caption)
            }
        }
    }

    private func button(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity) }
    }

    private func cpuSection(_ s: DebugSnapshot) -> some View {
        let r = s.registers
        let rows: [(String, String)] = [
            ("PC", hex(r.pc)), ("SP", hex(s.sp)),
            ("AF", String(format: "%04X", r.af)), ("BC", hex(r.bc)),
            ("DE", hex(r.de)), ("HL", hex(r.hl)),
            ("IX", hex(r.ix)), ("IY", hex(r.iy)),
            ("AF'", String(format: "%02X%02X", r.a_, r.f_)), ("BC'", hex(r.bc_)),
            ("DE'", hex(r.de_)), ("HL'", hex(r.hl_)),
            ("SPS", String(format: "%04X", r.sps)), ("SPL", hex(r.spl)),
            ("I", String(format: "%04X", r.i)), ("R", String(format: "%02X", r.r)),
            ("MBASE", String(format: "%02X", r.mbase)), ("Flags", s.flags),
        ]
        return Section("CPU") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.0) { row in
                    HStack {
                        Text(row.0).foregroundColor(.secondary)
                        Spacer()
                        Text(row.1)
                    }
                    .font(.caption.monospaced())
                }
            }
            Text("ADL \(s.adl ? 1 : 0)  MADL \(s.madl ? 1 : 0)  IEF1 \(s.ief1 ? 1 : 0)  IEF2 \(s.ief2 ? 1 : 0)  IM \(s.interruptMode)\(s.halted ? "  HALT" : "")")
                .font(.caption.monospaced())
            Text("Cycles \(s.cycles)  •  \(s.cpuHz / 1_000_000) MHz  •  \(String(format: "%.2f", s.emulatedSeconds)) s")
                .font(.caption.monospaced()).foregroundColor(.secondary)
            Text("Opcode: \(s.currentInstruction)").font(.caption.monospaced())
        }
    }

    private func disassemblySection(_ s: DebugSnapshot) -> some View {
        Section("Disassembly") {
            ForEach(s.disassembly) { line in
                HStack(spacing: 8) {
                    Text(breakpoints.contains(line.address) ? "●" : " ").foregroundColor(.red)
                    Text(hex(line.address)).foregroundColor(line.isCurrent ? .accentColor : .secondary)
                    Text(line.bytes).foregroundColor(.secondary).frame(width: 110, alignment: .leading)
                    Text(line.text)
                }
                .font(.caption.monospaced())
                .contentShape(Rectangle())
                .onTapGesture { toggleBreakpoint(line.address) }
            }
        }
    }

    private var breakpointSection: some View {
        Section {
            HStack {
                TextField("Address (hex)", text: $breakpointText)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Add") {
                    if let a = UInt32(breakpointText.trimmingCharacters(in: .whitespaces), radix: 16) {
                        if !breakpoints.contains(a) { breakpoints.append(a) }
                        breakpointText = ""
                        applyBreakpoints()
                    }
                }
            }
            ForEach(breakpoints, id: \.self) { a in
                HStack {
                    Text("Breakpoint: 0x" + hex(a)).font(.caption.monospaced())
                    Spacer()
                    Button(role: .destructive) { toggleBreakpoint(a) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Breakpoints")
        } footer: {
            Text("Tap a disassembly line to toggle a breakpoint. Execution pauses when the CPU reaches it.")
        }
    }

    private func memorySection(_ s: DebugSnapshot) -> some View {
        Section("Memory") {
            TextField("Address (hex)", text: $memoryText)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit(update)
            ForEach(0..<16, id: \.self) { row in
                let bytes = s.memory[(row * 16)..<(row * 16 + 16)]
                Text(hex(s.memoryBase + UInt32(row * 16)) + "  " + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private func ioSection(_ s: DebugSnapshot) -> some View {
        Section("I/O ports") {
            TextField("Port (hex)", text: $portText)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit(update)
            Text(String(format: "%04X  ", s.ioPort) + s.ioBytes.map { String(format: "%02X", $0) }.joined(separator: " "))
                .font(.system(size: 11, design: .monospaced))
            Text(IOBus.deviceNames[Int(s.ioPort >> 12)]).font(.caption).foregroundColor(.secondary)
        }
    }

    private func table(_ title: String, _ values: [DebugSnapshot.NamedValue]) -> some View {
        Section(title) {
            ForEach(values) { v in
                HStack(alignment: .top) {
                    Text(v.name).foregroundColor(.secondary)
                    Spacer()
                    Text(v.value).multilineTextAlignment(.trailing)
                }
                .font(.caption.monospaced())
            }
        }
    }

    // MARK: Actions

    private func update() {
        let address = UInt32(memoryText.trimmingCharacters(in: .whitespaces), radix: 16) ?? 0xD00000
        let port = UInt16(portText.trimmingCharacters(in: .whitespaces), radix: 16) ?? 0x5000
        runner.query({ $0.debugSnapshot(memoryAddress: address, ioPort: port) }) { snapshot = $0 }
    }

    private func toggleBreakpoint(_ a: UInt32) {
        if let i = breakpoints.firstIndex(of: a) { breakpoints.remove(at: i) } else { breakpoints.append(a) }
        applyBreakpoints()
    }

    private func applyBreakpoints() {
        let set = Set(breakpoints)
        runner.perform { $0.cpu.breakpoints = set }
    }

    private func hex(_ v: UInt32) -> String { String(format: "%06X", v) }
}
