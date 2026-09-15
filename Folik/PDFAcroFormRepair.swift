import Foundation

/// Repairs a PDFKit serialization where page widgets exist but the AcroForm field
/// tree does not reference them. The repair is an incremental PDF update, so the
/// original objects and unknown catalog/form keys remain unchanged.
nonisolated enum PDFAcroFormRepair {
    static func repair(_ data: Data) -> Data {
        synchronizeWidgetValues(in: repairFieldTree(in: data))
    }

    private static func repairFieldTree(in data: Data) -> Data {
        guard let source = String(data: data, encoding: .isoLatin1),
              let trailer = finalTrailer(in: source),
              !trailer.isEncrypted,
              let catalog = latestObject(trailer.root, in: source)
        else { return data }

        let objects = objectDefinitions(in: source)
        let existingFormReference = firstReference(after: "/AcroForm", in: catalog.body)
        let target: ObjectDefinition
        var updatedBody: String
        let existingFields: [Reference]
        if let formReference = existingFormReference,
           let formObject = latestObject(formReference, in: source),
           let range = arrayValueRange(after: "/Fields", in: formObject.body) {
            target = formObject
            existingFields = references(in: String(formObject.body[range]))
            updatedBody = formObject.body
            updatedBody.replaceSubrange(range, with: "__FOLIK_FIELDS__")
        } else if let formReference = existingFormReference,
                  let formObject = latestObject(formReference, in: source),
                  let fieldsReference = firstReference(after: "/Fields", in: formObject.body),
                  let fieldsObject = latestObject(fieldsReference, in: source),
                  let range = outerArrayRange(in: fieldsObject.body) {
            target = fieldsObject
            existingFields = references(in: String(fieldsObject.body[range]))
            updatedBody = fieldsObject.body
            updatedBody.replaceSubrange(range, with: "__FOLIK_FIELDS__")
        } else if let dictionaryStart = catalog.body.range(of: "<<") {
            target = catalog
            existingFields = []
            updatedBody = catalog.body
            updatedBody.insert(contentsOf: " /AcroForm << /Fields __FOLIK_FIELDS__ >>", at: dictionaryStart.upperBound)
        } else {
            return data
        }

        let canonicalNames = fieldNameTokens(from: existingFields, objects: objects)
        let widgetReferences = objects.compactMap { definition -> Reference? in
            guard contains(#"/Subtype\s*/Widget\b"#, in: definition.body),
                  existingFormReference == nil || definition.body.contains("Folik form field"),
                  fieldNameToken(in: definition.body).map({ !canonicalNames.contains($0) }) ?? true
            else { return nil }
            var reference = definition.reference
            var visited = Set<Reference>()
            while visited.insert(reference).inserted,
                  let object = objects.last(where: { $0.reference == reference }),
                  let parent = firstReference(after: "/Parent", in: object.body) {
                reference = parent
            }
            return reference
        }
        guard !widgetReferences.isEmpty else { return data }

        var fields = existingFields
        let existing = Set(fields)
        fields.append(contentsOf: widgetReferences.filter { !existing.contains($0) })
        fields = fields.reduce(into: []) { result, reference in
            if !result.contains(reference) { result.append(reference) }
        }
        guard fields.count > existingFields.count else { return data }

        updatedBody = updatedBody.replacingOccurrences(
            of: "__FOLIK_FIELDS__",
            with: "[ \(fields.map(\.description).joined(separator: " ")) ]"
        )
        return appendIncrementalUpdate([(target.reference, updatedBody)], to: data, trailer: trailer, objects: objects)
    }

    private static func synchronizeWidgetValues(in data: Data) -> Data {
        guard let source = String(data: data, encoding: .isoLatin1),
              let trailer = finalTrailer(in: source),
              !trailer.isEncrypted,
              let catalog = latestObject(trailer.root, in: source),
              let formReference = firstReference(after: "/AcroForm", in: catalog.body),
              let form = latestObject(formReference, in: source)
        else { return data }
        let objects = objectDefinitions(in: source)
        let roots: [Reference]
        if let range = arrayValueRange(after: "/Fields", in: form.body) {
            roots = references(in: String(form.body[range]))
        } else if let reference = firstReference(after: "/Fields", in: form.body),
                  let array = latestObject(reference, in: source),
                  let range = outerArrayRange(in: array.body) {
            roots = references(in: String(array.body[range]))
        } else { return data }
        let canonical = fieldValueTokens(from: roots, objects: objects)
        guard !canonical.isEmpty else { return data }
        var updates: [(Reference, String)] = []
        var seen = Set<Reference>()
        for object in objects.reversed() where seen.insert(object.reference).inserted
            && contains(#"/Subtype\s*/Widget\b"#, in: object.body) {
            guard let name = fieldNameToken(in: object.body),
                  let expected = canonical[name],
                  let valueRange = valueTokenRange(after: "/V", in: object.body),
                  String(object.body[valueRange]) != expected else { continue }
            var body = object.body
            body.replaceSubrange(valueRange, with: expected)
            updates.append((object.reference, body))
        }
        guard !updates.isEmpty else { return data }
        return appendIncrementalUpdate(updates, to: data, trailer: trailer, objects: objects)
    }

    private struct Reference: Hashable, CustomStringConvertible {
        let object: Int
        let generation: Int
        var description: String { "\(object) \(generation) R" }
    }

    private struct ObjectDefinition {
        let reference: Reference
        let body: String
    }

    private struct Trailer {
        let size: Int
        let root: Reference
        let startXRef: Int
        let isEncrypted: Bool
    }

    private static func objectDefinitions(in source: String) -> [ObjectDefinition] {
        let matches = regex(#"(?m)(?:^|[\r\n])(\d+)\s+(\d+)\s+obj\b"#, in: source)
        return matches.compactMap { match in
            guard let object = integer(match, group: 1, in: source),
                  let generation = integer(match, group: 2, in: source),
                  let header = Range(match.range, in: source),
                  let end = source.range(of: "endobj", range: header.upperBound..<source.endIndex)
            else { return nil }
            return ObjectDefinition(reference: Reference(object: object, generation: generation),
                                    body: String(source[header.upperBound..<end.lowerBound]))
        }
    }

    private static func latestObject(_ reference: Reference, in source: String) -> ObjectDefinition? {
        objectDefinitions(in: source).last { $0.reference == reference }
    }

    private static func finalTrailer(in source: String) -> Trailer? {
        guard let start = regex(#"startxref\s+(\d+)\s+%%EOF\s*$"#, in: source).last,
              let startXRef = integer(start, group: 1, in: source),
              let trailerRange = source.range(of: "trailer", options: .backwards, range: source.startIndex..<Range(start.range, in: source)!.lowerBound),
              let root = firstReference(after: "/Root", in: String(source[trailerRange.lowerBound...])),
              let sizeMatch = regex(#"/Size\s+(\d+)"#, in: String(source[trailerRange.lowerBound...])).first,
              let size = integer(sizeMatch, group: 1, in: String(source[trailerRange.lowerBound...]))
        else { return nil }
        return Trailer(size: size, root: root, startXRef: startXRef,
                       isEncrypted: source[trailerRange.lowerBound..<Range(start.range, in: source)!.lowerBound].contains("/Encrypt"))
    }

    private static func firstReference(after key: String, in source: String) -> Reference? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let match = regex("\(escaped)\\s+(\\d+)\\s+(\\d+)\\s+R", in: source).first,
              let object = integer(match, group: 1, in: source),
              let generation = integer(match, group: 2, in: source)
        else { return nil }
        return Reference(object: object, generation: generation)
    }

    private static func references(in source: String) -> [Reference] {
        regex(#"(\d+)\s+(\d+)\s+R"#, in: source).compactMap { match in
            guard let object = integer(match, group: 1, in: source),
                  let generation = integer(match, group: 2, in: source) else { return nil }
            return Reference(object: object, generation: generation)
        }
    }

    private static func fieldNameTokens(
        from roots: [Reference],
        objects: [ObjectDefinition]
    ) -> Set<String> {
        var names = Set<String>()
        var pending = roots
        var visited = Set<Reference>()
        while let reference = pending.popLast() {
            guard visited.insert(reference).inserted,
                  let object = objects.last(where: { $0.reference == reference }) else { continue }
            if let name = fieldNameToken(in: object.body) { names.insert(name) }
            if let kids = arrayValueRange(after: "/Kids", in: object.body) {
                pending.append(contentsOf: references(in: String(object.body[kids])))
            }
        }
        return names
    }

    private static func fieldValueTokens(
        from roots: [Reference],
        objects: [ObjectDefinition]
    ) -> [String: String] {
        var values: [String: String] = [:]
        var pending = roots.map { ($0, Optional<String>.none) }
        var visited = Set<Reference>()
        while let (reference, inheritedValue) = pending.popLast() {
            guard visited.insert(reference).inserted,
                  let object = objects.last(where: { $0.reference == reference }) else { continue }
            let ownValue = valueTokenRange(after: "/V", in: object.body).map { String(object.body[$0]) }
            let effectiveValue = ownValue ?? inheritedValue
            if let name = fieldNameToken(in: object.body), let effectiveValue { values[name] = effectiveValue }
            if let kids = arrayValueRange(after: "/Kids", in: object.body) {
                pending.append(contentsOf: references(in: String(object.body[kids])).map { ($0, effectiveValue) })
            }
        }
        return values
    }

    private static func fieldNameToken(in source: String) -> String? {
        guard let match = regex(#"/T\b\s*(\((?:\\.|[^)])*\)|<[0-9A-Fa-f\s]+>)"#, in: source).first,
              let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }

    private static func valueTokenRange(after key: String, in source: String) -> Range<String.Index>? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let token = #"(\((?:\\.|[^)])*\)|/[^\s<>\[\]()]+|<[0-9A-Fa-f\s]+>|\d+\s+\d+\s+R)"#
        guard let match = regex("\(escaped)\\b\\s*\(token)", in: source).first,
              let range = Range(match.range(at: 1), in: source) else { return nil }
        return range
    }

    private static func appendIncrementalUpdate(
        _ updates: [(Reference, String)],
        to data: Data,
        trailer: Trailer,
        objects: [ObjectDefinition]
    ) -> Data {
        var output = data
        if output.last != 0x0A { output.append(0x0A) }
        var offsets: [(Reference, Int)] = []
        for (reference, body) in updates {
            offsets.append((reference, output.count))
            let object = "\(reference.object) \(reference.generation) obj\n\(body)\nendobj\n"
            guard let bytes = object.data(using: .isoLatin1) else { return data }
            output.append(bytes)
        }
        let xrefOffset = output.count
        var xref = "xref\n"
        for (reference, offset) in offsets.sorted(by: { $0.0.object < $1.0.object }) {
            xref += "\(reference.object) 1\n\(String(format: "%010d", offset)) \(String(format: "%05d", reference.generation)) n \n"
        }
        let size = max(trailer.size, (objects.map { $0.reference.object }.max() ?? 0) + 1)
        xref += "trailer\n<< /Size \(size) /Root \(trailer.root.description) /Prev \(trailer.startXRef) >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
        guard let bytes = xref.data(using: .isoLatin1) else { return data }
        output.append(bytes)
        return output
    }

    private static func arrayValueRange(after key: String, in source: String) -> Range<String.Index>? {
        guard let keyRange = source.range(of: key) else { return nil }
        var open = keyRange.upperBound
        while open < source.endIndex, source[open].isWhitespace {
            open = source.index(after: open)
        }
        guard open < source.endIndex, source[open] == "[" else { return nil }
        return balancedArrayRange(from: open, in: source)
    }

    private static func balancedArrayRange(from open: String.Index, in source: String) -> Range<String.Index>? {
        var depth = 0
        for index in source.indices[open...] {
            if source[index] == "[" { depth += 1 }
            if source[index] == "]" {
                depth -= 1
                if depth == 0 { return open..<source.index(after: index) }
            }
        }
        return nil
    }

    private static func outerArrayRange(in source: String) -> Range<String.Index>? {
        guard let open = source.firstIndex(of: "[") else { return nil }
        return balancedArrayRange(from: open, in: source)
    }

    private static func contains(_ pattern: String, in source: String) -> Bool {
        !regex(pattern, in: source).isEmpty
    }

    private static func regex(_ pattern: String, in source: String) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
    }

    private static func integer(_ match: NSTextCheckingResult, group: Int, in source: String) -> Int? {
        guard let range = Range(match.range(at: group), in: source) else { return nil }
        return Int(source[range])
    }
}
