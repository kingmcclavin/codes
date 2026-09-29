/// Something plugged into the 2.5 mm link jack (another emulated calculator,
/// a file-transfer engine, ...). Lines are open-collector: each side can only
/// pull a line low.
public protocol LinkPeer: AnyObject {
    /// Lines the peer is pulling low (bit 0 = tip, bit 1 = ring).
    var linesPulledLow: UInt8 { get }
    /// Called when the calculator changes the lines it pulls low.
    func calculatorLinesChanged(_ pulledLow: UInt8)
}

/// The I/O link port (port 00h) plus the link-assist registers (08h–0Dh).
///
/// Port 00h: writing bits 0–1 pulls tip/ring low; reading returns the actual
/// line levels in bits 0–1 (1 = high) and the calculator's own drive in bits
/// 4–5. With nothing connected both lines float high.
///
/// The link assist is a hardware byte transceiver. The OS disables it
/// (port 08h bit 7) for normal bit-banged transfers; it is modelled here as
/// idle with no data, which is what the OS sees without a cable.
public final class LinkPort: IODevice {
    public private(set) var driven: UInt8 = 0
    public weak var peer: LinkPeer? {
        didSet { lineStateChanged() }
    }

    public private(set) var assistControl: UInt8 = 0x80
    private var assistRegisters = [UInt8](repeating: 0, count: 6)

    unowned let interrupts: InterruptController

    init(interrupts: InterruptController) {
        self.interrupts = interrupts
    }

    public func reset() {
        driven = 0
        assistControl = 0x80
        assistRegisters = [UInt8](repeating: 0, count: 6)
        peer?.calculatorLinesChanged(0)
    }

    /// Actual line levels, 1 = high.
    public var lineLevels: UInt8 {
        ~(driven | (peer?.linesPulledLow ?? 0)) & 0x03
    }

    /// The peer calls this when it changes its lines.
    public func lineStateChanged() {
        if interrupts.linkEnabled && lineLevels != 0x03 {
            interrupts.raise(.linkActivity)
        }
    }

    public func read(port: UInt8) -> UInt8 {
        switch port {
        case 0x00:
            return lineLevels | (driven << 4)
        case 0x08:
            return assistControl
        case 0x09:
            // Assist idle: not busy, nothing received, no error.
            return 0x20
        case 0x0A:
            return assistRegisters[2]
        default:
            return 0x00
        }
    }

    public func write(port: UInt8, value: UInt8) {
        switch port {
        case 0x00:
            driven = value & 0x03
            peer?.calculatorLinesChanged(driven)
        case 0x08:
            assistControl = value
        case 0x09...0x0D:
            assistRegisters[Int(port - 0x08)] = value
        default:
            break
        }
    }

    var snapshot: LinkState { LinkState(driven: driven, assistControl: assistControl) }
    func restore(_ s: LinkState) {
        driven = s.driven
        assistControl = s.assistControl
    }
}

public struct LinkState: Codable, Equatable, Sendable {
    var driven: UInt8
    var assistControl: UInt8
}
