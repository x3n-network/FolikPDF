import PDFKit

@MainActor
enum PDFFormFieldRegistration {
    /// PDFKit registers fields with AcroForm when their value setter runs
    /// after attachment to a page. Adding a widget alone can leave it unlisted.
    static func register(_ annotation: PDFAnnotation) {
        guard annotation.type == "Widget", annotation.page != nil else { return }
        if annotation.widgetFieldType == .text {
            annotation.widgetStringValue = annotation.widgetStringValue
        } else if annotation.widgetFieldType == .button,
                  annotation.widgetControlType == .checkBoxControl {
            annotation.buttonWidgetState = annotation.buttonWidgetState
        } else if annotation.widgetFieldType == .signature,
                  annotation.contents == "Folik form field",
                  annotation.value(forAnnotationKey: .widgetValue) == nil {
            // An unsigned signature has no string value. Register through the text
            // setter, then restore its type; never synthesize a signature /V.
            annotation.widgetFieldType = .text
            annotation.widgetStringValue = nil
            annotation.widgetFieldType = .signature
        }
    }
}
