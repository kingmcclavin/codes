#if canImport(SwiftUI) && canImport(UIKit)
import Combine
import SwiftUI

/// Developer view of the emulated machine: registers, disassembly,
/// breakpoints, memory, I/O ports, interrupts, LCD and keypad state.
struct DebuggerView: View {
    @ObservedObject var model: EmulatorViewModel
    @State private var snapshot: DebugSnapshot?
    @State private var memoryAddress = "8000"
    @State private var breakpointAddress = ""
    @State private var memoryRows: [(address: UInt16, bytes: [UInt8])] = []

    private let refresh = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            controls
            if let s = snapshot {
                registers(s)
                disassembly(s)
                breakpoints
                stack(s)
                memory
                hardware(s)
                ports(s)
            } else {
                Text("Emulator not running").foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .font(.system(.footnote, design: .monospaced))
        .navigationTitle("Debugger")
        .onAppear(perform: update)
        .onReceive(refresh) { _ in
            if model.status == .running { update() }
        }
        .onChange(of: model.status) { _ in update() }
    }

    private func update() {
        snapshot = model.snapshot()
        if let address = UInt16(memoryAddress, radix: 16) {
            memoryRows = model.memoryDump(at: address, rows: 8)
        }
    }

    // MARK: Sections

    private var controls: some View {
        Section {
            HStack {
                Button { model.resume(); update() } label: { Label("Run", systemImage: "play.fill") }
                    .disabled(model.status == .running)
                Spacer()
                Button { model.pause(); update() } label: { Label("Pause", systemImage: "pause.fill") }
                    .disabled(model.status != .running)
                Spacer()
                Button { model.step(); update() } label: { Label("Step", systemImage: "forward.frame.fill") }
                    .disabled(model.status == .running)
                Spacer()
                Button { model.resetCalculator(); update() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .font(.title3)
            Text(statusText).foregroundColor(.secondary)
        }
    }

    private var statusText: String {
        switch model.status {
        case .running: return "Running"
        case .paused: return "Paused"
        case let .breakpoint(address): return "Breakpoint hit at \(hex(address))h"
        case .stopped: return "Stopped"
        }
    }

    private func registers(_ s: DebugSnapshot) -> some View {
        let r = s.registers
        let rows: [(String, String, String, String)] = [
            ("PC", hex(r.pc), "SP", hex(r.sp)),
            ("AF", hex(r.af), "AF'", hex(r.altAF)),
            ("BC", hex(r.bc), "BC'", hex(r.altBC)),
            ("DE", hex(r.de), "DE'", hex(r.altDE)),
            ("HL", hex(r.hl), "HL'", hex(r.altHL)),
            ("IX", hex(r.ix), "IY", hex(r.iy)),
            ("I", hex(r.i), "R", hex(r.r)),
        ]
        return Section("CPU") {
            ForEach(0..<rows.count, id: \.self) { index in
                let row = rows[index]
                HStack {
                    Text(row.0).foregroundColor(.secondary).frame(width: 34, alignment: .leading)
                    Text(row.1)
                    Spacer()
                    Text(row.2).foregroundColor(.secondary).frame(width: 34, alignment: .leading)
                    Text(row.3)
                }
            }
            HStack {
                Text("Flags").foregroundColor(.secondary)
                Text(r.flagString)
                Spacer()
                Text("IM \(s.interruptMode) IFF1=\(s.iff1 ? 1 : 0)\(s.halted ? " HALT" : "")")
            }
            HStack {
                Text("Cycles").foregroundColor(.secondary)
                Text("\(s.cycles)")
                Spacer()
                Text(s.cpuSpeed == .mhz15 ? "15 MHz" : "6 MHz")
            }
        }
    }

    private func disassembly(_ s: DebugSnapshot) -> some View {
        let breakpoints = Set(model.breakpoints)
        return Section("Disassembly (tap to toggle breakpoint)") {
            ForEach(s.upcoming, id: \.address) { instruction in
                HStack(spacing: 6) {
                    Image(systemName: breakpoints.contains(instruction.address) ? "circle.fill" : "circle")
                        .foregroundColor(breakpoints.contains(instruction.address) ? Color.red : Color.secondary.opacity(0.4))
                        .font(.caption2)
                    Text(hex(instruction.address))
                        .foregroundColor(instruction.address == s.registers.pc ? Color.yellow : Color.secondary)
                    Text(instruction.hexBytes).foregroundColor(.secondary).frame(width: 96, alignment: .leading)
                    Text(instruction.text)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    model.toggleBreakpoint(instruction.address)
                    update()
                }
            }
        }
    }

    private var breakpoints: some View {
        Section("Breakpoints") {
            HStack {
                TextField("Address (hex)", text: $breakpointAddress)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Add") {
                    if let address = UInt16(breakpointAddress.trimmingCharacters(in: .whitespaces), radix: 16) {
                        model.toggleBreakpoint(address)
                        breakpointAddress = ""
                    }
                }
            }
            ForEach(model.breakpoints, id: \.self) { address in
                HStack {
                    Text("Breakpoint: 0x\(hex(address))")
                    Spacer()
                    Button(role: .destructive) { model.toggleBreakpoint(address) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func stack(_ s: DebugSnapshot) -> some View {
        Section("Stack") {
            ForEach(Array(s.stack.enumerated()), id: \.offset) { index, value in
                HStack {
                    Text("SP+\(index * 2)").foregroundColor(.secondary)
                    Spacer()
                    Text(hex(value))
                }
            }
        }
    }

    private var memory: some View {
        Section("Memory") {
            HStack {
                Text("Address").foregroundColor(.secondary)
                TextField("8000", text: $memoryAddress)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit(update)
            }
            ForEach(0..<memoryRows.count, id: \.self) { index in
                let row = memoryRows[index]
                Text("\(hex(row.address)): " + row.bytes.map { hex($0) }.joined(separator: " "))
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private func hardware(_ s: DebugSnapshot) -> some View {
        Section("Hardware") {
            row("Memory map", "mode \(s.memoryMode): " + s.banks.map(\.description).joined(separator: ", "))
            row("Interrupt mask (03h)", hex(s.interruptMask))
            row("Pending", pendingText(s.pendingInterrupts))
            row("IRQ line", s.irqLine ? "asserted" : "idle")
            row("Flash", s.flashUnlocked ? "unlocked" : "locked")
            row("LCD", "\(s.lcdOn ? "on" : "off"), \(s.lcdEightBit ? "8" : "6")-bit, row \(s.lcdCursor.row) col \(s.lcdCursor.column), contrast \(s.lcdContrast)")
            row("Key group mask", hex(s.keyGroupMask))
            row("Keys down", s.pressedKeys.isEmpty ? "none" : s.pressedKeys.map(\.rawValue).joined(separator: " "))
            row("Emulated time", String(format: "%.2f s", s.emulatedSeconds))
        }
    }

    private func ports(_ s: DebugSnapshot) -> some View {
        let interesting: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x10, 0x11, 0x14, 0x20, 0x21, 0x27, 0x28]
        return Section("I/O ports (last read / last written)") {
            ForEach(interesting, id: \.self) { port in
                HStack {
                    Text("\(hex(port))h").foregroundColor(.secondary)
                    Spacer()
                    Text("in \(hex(s.portsRead[Int(port)]))  out \(hex(s.portsWritten[Int(port)]))")
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func pendingText(_ p: InterruptSource) -> String {
        var names: [String] = []
        if p.contains(.onKey) { names.append("ON") }
        if p.contains(.timer1) { names.append("timer1") }
        if p.contains(.timer2) { names.append("timer2") }
        if p.contains(.linkActivity) { names.append("link") }
        if p.contains(.crystal1) { names.append("xtal1") }
        if p.contains(.crystal2) { names.append("xtal2") }
        if p.contains(.crystal3) { names.append("xtal3") }
        return names.isEmpty ? "none" : names.joined(separator: " ")
    }
}
#endif
