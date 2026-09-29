/// Uppercase hexadecimal with a width matching the integer size.
@inlinable
public func hex<T: FixedWidthInteger>(_ value: T) -> String {
    let s = String(value, radix: 16, uppercase: true)
    let width = T.bitWidth / 4
    return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
}
