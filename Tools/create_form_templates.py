"""Rebuild Folik's offline templates. Development dependency: reportlab."""
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, white

ROOT = Path(__file__).resolve().parents[1] / 'Folik' / 'Resources'
INK, BLUE, MUTED, PALE = map(HexColor, ['#1A2942', '#2E59C7', '#57667A', '#F2F7FF'])

def create(filename, title, subtitle, fields, checks=()):
    pdf = canvas.Canvas(str(ROOT / f'{filename}.pdf'), pagesize=(612, 792), invariant=1)
    pdf.setTitle(title)
    pdf.setAuthor('Folik')
    def text(value, x, top, size=12, bold=False, color=INK):
        pdf.setFillColor(color)
        pdf.setFont('Helvetica-Bold' if bold else 'Helvetica', size)
        pdf.drawString(x, 792 - top - size, value)
    pdf.setFillColor(white)
    pdf.rect(0, 0, 612, 792, fill=1, stroke=0)
    text('FOLIK / FORM TEMPLATES', 40, 30, 10, True, BLUE)
    text(title, 40, 65, 30, True)
    text(subtitle, 40, 111, 13, color=MUTED)
    for name, x, top, width, height in fields:
        text(name, x, top, 12, True)
        pdf.acroForm.textfield(name=name, tooltip=name, x=x, y=792-top-22-height,
            width=width, height=height, value='', fontName='Helvetica', fontSize=12,
            textColor=INK, fillColor=PALE, borderColor=BLUE, borderWidth=0.7,
            borderStyle='solid', fieldFlags='multiline' if height > 40 else '', forceBorder=True)
    for name, top in checks:
        pdf.acroForm.checkbox(name=name, tooltip=name, x=40, y=792-top-22,
            size=22, checked=False, buttonStyle='check', shape='square', textColor=BLUE,
            fillColor=white, borderColor=BLUE, borderWidth=0.7, forceBorder=True)
        text(name, 74, top+3, 12)
    text('Created with Folik', 40, 750, 10, color=MUTED)
    text('1 / 1', 550, 750, 10, color=MUTED)
    pdf.showPage()
    pdf.save()
    print(ROOT / f'{filename}.pdf')

create('WorkOrderTemplate', 'Work Order', 'Keep the request, work performed, and follow-up together.', [
    ('Work order number',40,155,250,32), ('Date',314,155,258,32),
    ('Customer or team',40,223,250,32), ('Contact',314,223,258,32),
    ('Location',40,291,532,32), ('Work requested',40,359,532,78),
    ('Work performed / materials',40,473,532,78), ('Assigned to',40,587,250,32),
    ('Follow-up date',314,587,258,32),
], [('Work completed',665)])
create('InspectionChecklistTemplate', 'Inspection Checklist', 'Record observations and the next steps for a routine inspection.', [
    ('Site or item',40,155,532,32), ('Inspected by',40,223,250,32), ('Date',314,223,258,32),
    ('Observations',40,445,532,78), ('Follow-up actions',40,559,532,70),
    ('Assigned to',40,665,250,32), ('Due date',314,665,258,32),
], [('Condition checked',303), ('Operation checked',345), ('Follow-up needed',387)])
create('MeetingNotesTemplate', 'Meeting Notes', 'Capture the discussion, decisions, and what happens next.', [
    ('Meeting title',40,155,532,32), ('Date',40,223,250,32), ('Facilitator',314,223,258,32),
    ('Attendees',40,291,532,44), ('Discussion notes',40,371,532,96),
    ('Decisions',40,503,532,60), ('Action items / owners / due dates',40,599,532,90),
])
create('ExpenseReportTemplate', 'Expense Report', 'Summarize business expenses, receipts, and reimbursement details.', [
    ('Employee or submitter',40,155,250,32), ('Department or team',314,155,258,32),
    ('Reporting period',40,223,250,32), ('Submitted date',314,223,258,32),
    ('Business purpose',40,291,532,60),
    ('Expenses - date / description / category / amount',40,387,532,100),
    ('Total requested',40,523,250,32), ('Project or client',314,523,258,32),
    ('Notes',40,591,532,70),
], [('Receipts attached',697)])
create('TimesheetTemplate', 'Weekly Timesheet', 'Record daily hours, the week total, and any notes.', [
    ('Employee',40,155,250,32), ('Week ending',314,155,258,32),
    ('Project or client',40,223,532,32),
    ('Monday hours',40,291,250,32), ('Tuesday hours',314,291,258,32),
    ('Wednesday hours',40,359,250,32), ('Thursday hours',314,359,258,32),
    ('Friday hours',40,427,250,32), ('Saturday hours',314,427,258,32),
    ('Sunday hours',40,495,250,32), ('Total hours',314,495,258,32),
    ('Notes',40,563,532,64),
], [('Hours verified',665)])
create('ProjectBriefTemplate', 'Project Brief', 'Define the goal, scope, deliverables, and ownership.', [
    ('Project name',40,155,532,32),
    ('Owner',40,223,250,32), ('Target date',314,223,258,32),
    ('Goal and success measure',40,291,532,60),
    ('Audience or stakeholders',40,387,532,44),
    ('In scope',40,467,250,70), ('Out of scope',314,467,258,70),
    ('Deliverables',40,573,250,70), ('Risks or dependencies',314,573,258,70),
], [('Brief reviewed',681)])
create('InventoryCountTemplate', 'Inventory Count', 'Record stock levels, discrepancies, and follow-up actions.', [
    ('Location',40,155,250,32), ('Count date',314,155,258,32),
    ('Counted by',40,223,250,32), ('Reference or area',314,223,258,32),
    ('Items - name / identifier / expected / counted',40,291,532,120),
    ('Discrepancies',40,447,532,78),
    ('Restock or follow-up actions',40,561,532,70),
], [('Recount completed',667), ('Inventory finalized',709)])
