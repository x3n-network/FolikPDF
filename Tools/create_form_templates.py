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
