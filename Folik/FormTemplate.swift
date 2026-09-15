import Foundation

/// Bundled blank masters. Starting a form always imports an independent copy.
nonisolated enum FormTemplate: String, CaseIterable, Identifiable {
    case workOrder, inspectionChecklist, meetingNotes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .workOrder: "Work Order"
        case .inspectionChecklist: "Inspection Checklist"
        case .meetingNotes: "Meeting Notes"
        }
    }
    var subtitle: String {
        switch self {
        case .workOrder: "Track requests, completed work, and follow-up."
        case .inspectionChecklist: "Check conditions and record observations and actions."
        case .meetingNotes: "Capture attendees, decisions, and action items."
        }
    }
    var icon: String {
        switch self {
        case .workOrder: "wrench.and.screwdriver"
        case .inspectionChecklist: "checklist"
        case .meetingNotes: "person.2"
        }
    }
    var url: URL? {
        let filename: String = switch self {
        case .workOrder: "WorkOrderTemplate"
        case .inspectionChecklist: "InspectionChecklistTemplate"
        case .meetingNotes: "MeetingNotesTemplate"
        }
        return Bundle.main.url(forResource: filename, withExtension: "pdf")
    }
    func data() throws -> Data {
        guard let url else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
