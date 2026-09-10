"""Rebuild the bundled practice PDF. Development dependency: reportlab."""
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, white

DESTINATION = Path(__file__).resolve().parents[1] / "Folik" / "Resources" / "SampleForm.pdf"
DESTINATION.parent.mkdir(parents=True, exist_ok=True)
pdf = canvas.Canvas(str(DESTINATION), pagesize=(612, 792), invariant=1)
pdf.setTitle("Try a Sample Form")
pdf.setAuthor("Folik")
INK = HexColor("#1A2942")
BLUE = HexColor("#2E59C7")
MUTED = HexColor("#57667A")
PALE = HexColor("#F2F7FF")

def text(value, x, top, size=14, bold=False, color=INK):
    pdf.setFillColor(color)
    pdf.setFont("Helvetica-Bold" if bold else "Helvetica", size)
    pdf.drawString(x, 792 - top - size, value)

pdf.setFillColor(white)
pdf.rect(0, 0, 612, 792, fill=1, stroke=0)
pdf.setFillColor(BLUE)
pdf.rect(40, 747, 34, 5, fill=1, stroke=0)
text("FOLIK / PRACTICE DOCUMENT", 86, 33, 11, True, BLUE)
text("Make yourself at home.", 40, 79, 30, True)
text("Try filling, signing, and sharing a PDF. This sample stays on your", 40, 134, 15, color=MUTED)
text("device, and you can delete it whenever you like.", 40, 155, 15, color=MUTED)
text("01  FILL A FEW DETAILS", 40, 209, 12, True, BLUE)
text("Name", 40, 246, bold=True)
text("Date", 382, 246, bold=True)
text("What will you use Folik for?", 40, 328, bold=True)
text("I have tried a PDF checkbox.", 82, 448)
text("02  ADD YOUR SIGNATURE", 40, 510, 12, True, BLUE)
text("Open Forms, choose Sign, then place your signature below.", 40, 543, 13, color=MUTED)
pdf.setStrokeColor(MUTED)
pdf.setLineWidth(1)
pdf.line(40, 160, 572, 160)
text("03  SHARE WHEN YOU ARE READY", 40, 670, 12, True, BLUE)
text("Use Share at the top of the reader. You choose where the copy goes.", 40, 699, 13, color=MUTED)
text("Free. Private. On your device.", 40, 754, 11, color=MUTED)

for name, x, top, width, height, flags in [
    ("Name", 40, 272, 318, 38, ""),
    ("Date", 382, 272, 190, 38, ""),
    ("What will you use Folik for?", 40, 354, 532, 66, "multiline"),
]:
    pdf.acroForm.textfield(name=name, tooltip=name, x=x, y=792-top-height,
        width=width, height=height, value="", fontName="Helvetica", fontSize=16,
        textColor=INK, fillColor=PALE, borderColor=BLUE, borderWidth=1,
        borderStyle="solid", fieldFlags=flags, forceBorder=True)
pdf.acroForm.checkbox(name="I have tried a PDF checkbox", tooltip="I have tried a PDF checkbox",
    x=40, y=320, size=28, checked=False, buttonStyle="check", shape="square",
    textColor=BLUE, fillColor=white, borderColor=BLUE, borderWidth=1, forceBorder=True)
pdf.showPage()
pdf.save()
print(DESTINATION)
