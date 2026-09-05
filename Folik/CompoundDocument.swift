import Foundation

/// Bounded CFB stream reader. Only streams reachable in the root directory are
/// exposed; embedded storages and macros are never interpreted or executed.
nonisolated struct CompoundDocument {
    private let data: Data
    private let sectorSize: Int
    private let fat: [UInt32]
    private let miniFat: [UInt32]
    private let miniStream: Data
    private let streams: [String: (UInt32, Int)]
    private static let end: UInt32 = 0xfffffffe

    init(_ data: Data) throws {
        guard data.count <= OfficePackage.maximumFileBytes else { throw OfficeConversionError.tooLarge }
        guard data.starts(with: [0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1]),
              try data.office16(28) == 0xfffe else { throw OfficeConversionError.invalidPackage }
        let version = try data.office16(26)
        let shift = try data.office16(30)
        guard (version == 3 && shift == 9) || (version == 4 && shift == 12),
              try data.office16(32) == 6, try data.office32(56) == 4096 else { throw OfficeConversionError.unsupportedPackage }
        let size = 1 << Int(shift)
        guard data.count >= size, data.count % size == 0 else { throw OfficeConversionError.invalidPackage }
        let sectors = data.count / size - 1
        let fatCount = Int(try data.office32(44))
        guard fatCount > 0, fatCount <= sectors else { throw OfficeConversionError.invalidPackage }
        func sector(_ id: UInt32) throws -> Data {
            guard Int(id) < sectors else { throw OfficeConversionError.invalidPackage }
            return try data.officeSlice((Int(id) + 1) * size, size)
        }
        var ids: [UInt32] = []
        for offset in stride(from: 76, to: 512, by: 4) {
            let id = try data.office32(offset)
            if id != 0xffffffff { ids.append(id) }
        }
        var difat = try data.office32(68)
        let difatCount = Int(try data.office32(72))
        guard difatCount <= sectors else { throw OfficeConversionError.invalidPackage }
        var seen: Set<UInt32> = []
        for _ in 0..<difatCount {
            try Task.checkCancellation()
            guard seen.insert(difat).inserted else { throw OfficeConversionError.invalidPackage }
            let bytes = try sector(difat)
            for offset in stride(from: 0, to: size - 4, by: 4) {
                let id = try bytes.office32(offset)
                if id != 0xffffffff { ids.append(id) }
            }
            difat = try bytes.office32(size - 4)
        }
        guard ids.count == fatCount, Set(ids).count == ids.count else { throw OfficeConversionError.invalidPackage }
        var allocation: [UInt32] = []
        for id in ids {
            let bytes = try sector(id)
            for offset in stride(from: 0, to: size, by: 4) { allocation.append(try bytes.office32(offset)) }
        }
        func regular(_ start: UInt32, maximum: Int) throws -> Data {
            try Self.chain(start, allocation: allocation, size: size, maximum: maximum, read: sector)
        }
        let directory = try regular(data.office32(48), maximum: min(data.count, 4096 * 128))
        guard directory.count >= 128, directory[66] == 5 else { throw OfficeConversionError.invalidPackage }
        func entrySize(_ offset: Int) throws -> Int {
            let low = Int(try directory.office32(offset + 120))
            let high = try directory.office32(offset + 124)
            guard version == 3 || high == 0,
                  low <= OfficePackage.maximumFileBytes else { throw OfficeConversionError.tooLarge }
            return low
        }
        let rootSize = try entrySize(0)
        let rootData = rootSize == 0 ? Data() : try regular(directory.office32(116), maximum: ((rootSize + size - 1) / size) * size)
        guard rootData.count >= rootSize else { throw OfficeConversionError.invalidPackage }
        let miniCount = Int(try data.office32(64))
        guard miniCount <= sectors else { throw OfficeConversionError.invalidPackage }
        let miniBytes = miniCount == 0 ? Data() : try regular(data.office32(60), maximum: miniCount * size)
        guard miniBytes.count == miniCount * size else { throw OfficeConversionError.invalidPackage }
        var mini: [UInt32] = []
        for offset in stride(from: 0, to: miniBytes.count, by: 4) { mini.append(try miniBytes.office32(offset)) }
        var entries: [String: (UInt32, Int)] = [:]
        var pending = [try directory.office32(76)]
        var visited: Set<UInt32> = []
        while let id = pending.popLast() {
            try Task.checkCancellation()
            if id == 0xffffffff { continue }
            guard id > 0, Int(id) < directory.count / 128, visited.insert(id).inserted else { throw OfficeConversionError.invalidPackage }
            let offset = Int(id) * 128
            pending += [try directory.office32(offset + 68), try directory.office32(offset + 72)]
            guard directory[offset + 66] == 2 else { continue }
            let length = Int(try directory.office16(offset + 64))
            guard (2...64).contains(length), length % 2 == 0,
                  let name = String(data: try directory.officeSlice(offset, length - 2), encoding: .utf16LittleEndian),
                  entries[name] == nil else { throw OfficeConversionError.invalidPackage }
            entries[name] = (try directory.office32(offset + 116), try entrySize(offset))
        }
        self.data = data; sectorSize = size; fat = allocation
        miniFat = mini; miniStream = Data(rootData.prefix(rootSize)); streams = entries
    }
    func read(_ name: String) throws -> Data {
        guard let (start, length) = streams[name] else { throw OfficeConversionError.missingPart }
        if length == 0 { return Data() }
        let small = length < 4096
        let size = small ? 64 : sectorSize
        let result = try Self.chain(start, allocation: small ? miniFat : fat, size: size,
                                    maximum: ((length + size - 1) / size) * size) { id in
            if small { return try miniStream.officeSlice(Int(id) * 64, 64) }
            return try data.officeSlice((Int(id) + 1) * sectorSize, sectorSize)
        }
        guard result.count >= length else { throw OfficeConversionError.invalidPackage }
        return Data(result.prefix(length))
    }
    private static func chain(_ start: UInt32, allocation: [UInt32], size: Int, maximum: Int,
                              read: (UInt32) throws -> Data) throws -> Data {
        var result = Data(); var id = start; var seen: Set<UInt32> = []
        while id != end {
            try Task.checkCancellation()
            guard Int(id) < allocation.count, seen.insert(id).inserted,
                  result.count <= maximum - size else { throw OfficeConversionError.invalidPackage }
            result.append(try read(id)); id = allocation[Int(id)]
        }
        return result
    }
}

nonisolated extension Data {
    func officeSlice(_ offset: Int, _ length: Int) throws -> Data {
        guard offset >= 0, length >= 0, offset <= count, length <= count - offset else { throw OfficeConversionError.invalidPackage }
        return subdata(in: (startIndex + offset)..<(startIndex + offset + length))
    }
    func office16(_ offset: Int) throws -> UInt16 {
        guard offset >= 0, count >= 2, offset <= count - 2 else { throw OfficeConversionError.invalidPackage }
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }
    func office32(_ offset: Int) throws -> UInt32 {
        guard offset >= 0, count >= 4, offset <= count - 4 else { throw OfficeConversionError.invalidPackage }
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}
