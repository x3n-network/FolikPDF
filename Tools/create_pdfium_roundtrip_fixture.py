"""Edit the compatibility fixture through PDFium's form event API.

Usage: python Tools/create_pdfium_roundtrip_fixture.py EXTRACTED_ATTACHMENTS OUTPUT.pdf
Requires pypdfium2 and pypdf. Use attachments from FormTemplateTests.
Only disposable test documents should be passed to this script.
"""
import argparse
import ctypes
import json
from pathlib import Path
import pypdfium2 as pdfium
from pypdf import PdfReader

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("attachments", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
entry = next(entry for test in json.loads((args.attachments / "manifest.json").read_text())
             for entry in test["attachments"]
             if entry["suggestedHumanReadableName"].startswith("compatibility-editable_"))
source = args.attachments / entry["exportedFileName"]
assert source.resolve() != args.output.resolve()
document = pdfium.PdfDocument(source)
document.init_forms()
page = document[0]
raw = pdfium.raw
for x, y, text in [(100, 500, "Edited in PDFium"), (306, 250, "Updated added field")]:
    assert raw.FORM_OnFocus(document.formenv, page, 0, x, y)
    assert raw.FORM_SelectAllText(document.formenv, page)
    encoded = ctypes.create_string_buffer(text.encode("utf-16-le") + b"\0\0")
    raw.FORM_ReplaceSelection(document.formenv, page,
                              ctypes.cast(encoded, ctypes.POINTER(ctypes.c_ushort)))
    assert raw.FORM_ForceToKillFocus(document.formenv)
raw.FORM_OnMouseMove(document.formenv, page, 0, 54, 334)
raw.FORM_OnLButtonDown(document.formenv, page, 0, 54, 334)
raw.FORM_OnLButtonUp(document.formenv, page, 0, 54, 334)
raw.FORM_ForceToKillFocus(document.formenv)
document.save(args.output)
page.close()
document.close()
reader = PdfReader(args.output)
fields = reader.get_fields()
assert fields["Name"]["/V"] == "Edited in PDFium"
assert fields["Added text"]["/V"] == "Updated added field"
assert fields["I have tried a PDF checkbox"]["/V"] == "/Off"
# Retain the catalog/widget disagreement that exercises PDFKit's value resolution.
widgets = {ref.get_object().get("/T"): ref.get_object() for ref in reader.pages[0]["/Annots"]}
assert widgets["Name"]["/V"] == "Saved answer"
assert widgets["Added text"]["/V"] == "Saved answer"
print("Saved PDFium-edited fixture:", args.output)
