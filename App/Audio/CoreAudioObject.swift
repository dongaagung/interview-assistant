import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError {
    let status: OSStatus
    let action: String

    var errorDescription: String? { "Core Audio couldn't \(action) (error \(status))." }
}

func checkCoreAudio(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, action: action) }
}

/// Typed property reads on Core Audio objects.
extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    var isValid: Bool { self != Self.unknown }

    func read<T>(
        _ selector: AudioObjectPropertySelector, initial: T,
        qualifier: UInt32? = nil
    ) throws -> T {
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        var qualifierValue = qualifier ?? 0
        let qualifierSize = qualifier == nil ? 0 : UInt32(MemoryLayout<UInt32>.size)
        let status = withUnsafeMutablePointer(to: &value) { valuePointer in
            withUnsafeMutablePointer(to: &qualifierValue) { qualifierPointer in
                AudioObjectGetPropertyData(
                    self, &address, qualifierSize, qualifier == nil ? nil : qualifierPointer,
                    &size, valuePointer)
            }
        }
        try checkCoreAudio(status, "read property \(selector)")
        return value
    }

    func readArray<T>(_ selector: AudioObjectPropertySelector, of _: T.Type, initial: T) throws -> [T] {
        var address = Self.address(selector)
        var size: UInt32 = 0
        try checkCoreAudio(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size), "size property \(selector)")
        guard size >= MemoryLayout<T>.stride else { return [] }
        var values = [T](repeating: initial, count: Int(size) / MemoryLayout<T>.stride)
        let status = values.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, bytes.baseAddress!)
        }
        try checkCoreAudio(status, "read property \(selector)")
        return Array(values.prefix(Int(size) / MemoryLayout<T>.stride))
    }

    func readString(_ selector: AudioObjectPropertySelector) throws -> String {
        // Core Audio hands back a +1 CFString; storing it in a Swift CFString
        // variable transfers that ownership to ARC.
        try read(selector, initial: "" as CFString) as String
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }
}
