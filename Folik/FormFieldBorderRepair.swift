import PDFKit
import UIKit

@MainActor
enum FormFieldBorderRepair {
    /// Repairs only the appearance omitted by older Folik versions, preserving field data.
    static func repair(in document: PDFDocument, fields: [PDFAnnotation], sourceURL: URL) -> Bool {
        guard !document.isLocked, document.allowsCommenting, document.allowsFormFieldEntry else { return false }
        guard fields.contains(where: needsRepair) else { return false }
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        // Rewriting a digitally signed document would invalidate its signature.
        guard let data = try? Data(contentsOf: sourceURL),
              let report = try? PDFPrivacy.inspect(data), report.signedSignatureCount == 0,
              !pages.flatMap(\.annotations).contains(where: {
                  $0.widgetFieldType == .signature && $0.value(forAnnotationKey: .widgetValue) != nil
              }) else { return false }

        for page in pages {
            let originals = page.annotations
            var replacements: [PDFAnnotation] = []
            var replacedField = false
            for original in originals {
                guard needsRepair(original) else { replacements.append(original); continue }
                // Drop the cached blank appearance while preserving the complete field dictionary.
                var properties = original.annotationKeyValues
                properties.removeValue(forKey: PDFAnnotationKey.appearanceDictionary.rawValue)
                properties.removeValue(forKey: PDFAnnotationKey.page.rawValue)
                let annotation: PDFAnnotation = original.widgetFieldType == .signature
                    ? VisibleSignatureField(bounds: original.bounds, forType: .widget, withProperties: properties)
                    : PDFAnnotation(bounds: original.bounds, forType: .widget, withProperties: properties)
                replacedField = true
                let appearance = PDFAppearanceCharacteristics()
                appearance.backgroundColor = original.backgroundColor ?? .white
                appearance.borderColor = FolikTheme.annotationBlue
                if original.widgetFieldType == .button { appearance.controlType = original.widgetControlType }
                annotation.setValue(appearance, forAnnotationKey: .widgetAppearanceDictionary)
                let border = annotation.border ?? PDFBorder()
                if border.lineWidth <= 0 { border.lineWidth = 1.5 }
                annotation.border = border
                replacements.append(annotation)
            }
            if replacedField {
                // Keep annotation order, including external widgets and non-field annotations.
                for annotation in originals { page.removeAnnotation(annotation) }
                for annotation in replacements {
                    page.addAnnotation(annotation)
                    PDFFormFieldRegistration.register(annotation)
                }
            }
        }
        return true
    }

    private static func needsRepair(_ annotation: PDFAnnotation) -> Bool {
        guard annotation.type == "Widget", annotation.contents == "Folik form field",
              !annotation.isReadOnly, annotation.shouldDisplay, annotation.shouldPrint else { return false }
        if let kind = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "FolikFieldKind")) as? String {
            guard FormFieldPlacementKind(rawValue: kind) != nil else { return false }
        }
        // Earlier releases used only the contents marker, before FolikFieldKind existed.
        guard annotation.widgetFieldType == .text || annotation.widgetFieldType == .signature
            || (annotation.widgetFieldType == .button && annotation.widgetControlType == .checkBoxControl) else { return false }
        let appearance = annotation.value(forAnnotationKey: .widgetAppearanceDictionary)
        if let characteristics = appearance as? PDFAppearanceCharacteristics {
            return characteristics.borderColor == nil
        }
        if let dictionary = appearance as? NSDictionary {
            return dictionary["BC"] == nil && dictionary["/BC"] == nil
        }
        return appearance == nil
    }
}
