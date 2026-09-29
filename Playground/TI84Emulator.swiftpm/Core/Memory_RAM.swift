/// Static RAM made of 16 KB pages, stored contiguously.
public final class RAM: MemoryDevice {
    public let pageCount: Int
    public let storage: UnsafeMutableBufferPointer<UInt8>

    public init(pageCount: Int, fill: UInt8 = 0x00) {
        self.pageCount = pageCount
        storage = .allocate(capacity: pageCount * MemoryBus.bankSize)
        storage.initialize(repeating: fill)
    }

    deinit {
        storage.deallocate()
    }

    public var size: Int { storage.count }

    public func pagePointer(_ page: Int) -> UnsafeMutablePointer<UInt8> {
        storage.baseAddress! + (page % pageCount) * MemoryBus.bankSize
    }

    /// Device-path access (only used when a bus maps RAM without direct
    /// pointers). Treats the RAM as a flat 64 KB space.
    public func read(_ address: UInt16) -> UInt8 {
        storage[Int(address) % storage.count]
    }

    public func write(_ address: UInt16, value: UInt8) {
        storage[Int(address) % storage.count] = value
    }

    public subscript(physical offset: Int) -> UInt8 {
        get { storage[offset] }
        set { storage[offset] = newValue }
    }

    public func fill(_ value: UInt8) {
        storage.update(repeating: value)
    }

    public var bytes: [UInt8] { Array(storage) }

    public func load(_ bytes: [UInt8]) {
        let count = min(bytes.count, storage.count)
        for i in 0..<count { storage[i] = bytes[i] }
    }
}
