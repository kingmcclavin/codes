/// Calculator models whose ROMs this emulator can run. All of them use the
/// Z80-based "SE-class" ASIC with a T6A04 LCD driver; they differ in Flash
/// size and a few identification bits the OS reads at boot.
public enum CalculatorModel: String, Codable, CaseIterable, Sendable {
    case ti84Plus = "TI-84 Plus"
    case ti84PlusSE = "TI-84 Plus Silver Edition"
    case ti83PlusSE = "TI-83 Plus Silver Edition"
}

/// One erase sector of the Flash chip.
public struct FlashSector: Equatable, Sendable {
    public var start: Int
    public var size: Int
    /// Non-zero groups are write-protected unless port 21h unlocks the group.
    public var protectionGroup: UInt8
}

/// Everything about the target hardware that varies between models.
/// The emulator is configured from this table instead of scattering model
/// checks through the hardware code.
public struct HardwareProfile: Equatable, Sendable {
    public var model: CalculatorModel
    public var flashSize: Int
    public var ramPages: Int = 8
    public var flashSectors: [FlashSector]

    /// Value of port 02h bits 7..5 (model identification) and bit 0 (battery OK).
    public var statusPortBase: UInt8
    /// Port 15h (ASIC version).
    public var asicVersion: UInt8
    public var hasUSB: Bool
    public var hasClock: Bool

    // Power-on values of the protected configuration ports.
    public var port21Reset: UInt8
    public var port23Reset: UInt8
    public var flashOverrideGroupReset: UInt8

    public var flashPages: Int { flashSize / MemoryBus.bankSize }
    public var flashPageMask: UInt8 { UInt8(flashPages - 1) }
    /// The boot code lives in the last Flash page and runs from 8000h at reset.
    public var bootPage: Int { flashPages - 1 }
    /// The certificate page is read-protected while Flash is locked.
    public var certificatePage: Int { flashPages - 2 }

    /// Flash pages allowed to perform the privileged unlock sequence
    /// (the protected sector group and the boot sector group).
    public func isPrivilegedPage(_ page: Int) -> Bool {
        let top = flashPages
        return (page >= top - 20 && page < top - 16) || page >= top - 4
    }

    public static func profile(for model: CalculatorModel) -> HardwareProfile {
        switch model {
        case .ti84Plus:
            return HardwareProfile(
                model: model, flashSize: 0x100000,
                flashSectors: sectors(size: 0x100000, group: 1),
                statusPortBase: 0xE1, asicVersion: 0x45, hasUSB: true, hasClock: true,
                port21Reset: 0x00, port23Reset: 0x29, flashOverrideGroupReset: 0)
        case .ti84PlusSE:
            return HardwareProfile(
                model: model, flashSize: 0x200000,
                flashSectors: sectors(size: 0x200000, group: 2),
                statusPortBase: 0xE1, asicVersion: 0x45, hasUSB: true, hasClock: true,
                port21Reset: 0x01, port23Reset: 0x69, flashOverrideGroupReset: 1)
        case .ti83PlusSE:
            return HardwareProfile(
                model: model, flashSize: 0x200000,
                flashSectors: sectors(size: 0x200000, group: 2),
                statusPortBase: 0xC1, asicVersion: 0x33, hasUSB: false, hasClock: false,
                port21Reset: 0x01, port23Reset: 0x69, flashOverrideGroupReset: 1)
        }
    }

    /// 64 KB uniform sectors, except the top 64 KB which is split
    /// 32K/8K/8K/16K (boot block layout). The sector 0x50000 below the top
    /// and the 16 KB boot sector are protected.
    private static func sectors(size: Int, group: UInt8) -> [FlashSector] {
        var result: [FlashSector] = []
        let protectedSector = size - 0x50000
        var address = 0
        while address < size - 0x10000 {
            result.append(FlashSector(start: address, size: 0x10000,
                                      protectionGroup: address == protectedSector ? group : 0))
            address += 0x10000
        }
        result.append(FlashSector(start: address, size: 0x8000, protectionGroup: 0))
        result.append(FlashSector(start: address + 0x8000, size: 0x2000, protectionGroup: 0))
        result.append(FlashSector(start: address + 0xA000, size: 0x2000, protectionGroup: 0))
        result.append(FlashSector(start: address + 0xC000, size: 0x4000, protectionGroup: group))
        return result
    }
}
