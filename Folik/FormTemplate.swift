import Foundation

/// Bundled blank masters. Starting a form always imports an independent copy.
nonisolated enum FormTemplate: String, CaseIterable, Identifiable {
    case workOrder, inspectionChecklist, meetingNotes
    case expenseReport, timesheet, projectBrief, inventoryCount
    var id: String { rawValue }
    var title: String {
        switch self {
        case .workOrder: "Work Order"
        case .inspectionChecklist: "Inspection Checklist"
        case .meetingNotes: "Meeting Notes"
        case .expenseReport: "Expense Report"
        case .timesheet: "Weekly Timesheet"
        case .projectBrief: "Project Brief"
        case .inventoryCount: "Inventory Count"
        }
    }
    var subtitle: String {
        switch self {
        case .workOrder: "Track requests, completed work, and follow-up."
        case .inspectionChecklist: "Check conditions and record observations and actions."
        case .meetingNotes: "Capture attendees, decisions, and action items."
        case .expenseReport: "Summarize expenses, receipts, and reimbursement details."
        case .timesheet: "Record daily hours, the weekly total, and notes."
        case .projectBrief: "Define a project’s goal, scope, deliverables, and ownership."
        case .inventoryCount: "Track stock counts, discrepancies, and follow-up actions."
        }
    }
    var icon: String {
        switch self {
        case .workOrder: "wrench.and.screwdriver"
        case .inspectionChecklist: "checklist"
        case .meetingNotes: "person.2"
        case .expenseReport: "dollarsign.circle"
        case .timesheet: "clock"
        case .projectBrief: "target"
        case .inventoryCount: "shippingbox"
        }
    }
    var url: URL? {
        let filename: String = switch self {
        case .workOrder: "WorkOrderTemplate"
        case .inspectionChecklist: "InspectionChecklistTemplate"
        case .meetingNotes: "MeetingNotesTemplate"
        case .expenseReport: "ExpenseReportTemplate"
        case .timesheet: "TimesheetTemplate"
        case .projectBrief: "ProjectBriefTemplate"
        case .inventoryCount: "InventoryCountTemplate"
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
