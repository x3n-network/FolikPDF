"""Audit PDF attachments from Folik's focused export/repair XCTest fixtures.

Usage: python Tools/check_export_compatibility.py /path/to/exported-attachments
Requires pypdf, pypdfium2, and Pillow. Extract attachments with xcresulttool.
Writes PDFium preview PNGs beside the attachments. Reports separate catalog and
widget objects; matching values do not establish correct cross-viewer editing.
"""
import argparse
import json
from pathlib import Path
from pypdf import PdfReader
import pypdfium2 as pdfium
from PIL import ImageChops, ImageStat
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("attachments", type=Path)
root = parser.parse_args().attachments
checked = 0
images = {}
for test in json.loads((root/'manifest.json').read_text()):
    for entry in test['attachments']:
        file = root/entry['exportedFileName']; name = entry['suggestedHumanReadableName'].split('_0_')[0]
        if file.suffix != '.pdf' or not name.startswith(('compatibility-', 'repaired-', 'Weekly Work')): continue
        checked += 1
        reader = PdfReader(file)
        form = reader.trailer['/Root'].get('/AcroForm', {})
        if hasattr(form, 'get_object'): form = form.get_object()
        reachable = {}; seen = set()
        def visit(ref, inherited=None):
            ident = (ref.idnum, ref.generation) if hasattr(ref, 'idnum') else id(ref)
            if ident in seen: return
            seen.add(ident); obj = ref.get_object()
            effective = obj.get('/V', inherited)
            reachable[ident] = effective
            for child in obj.get('/Kids', []): visit(child, effective)
        for field in form.get('/Fields', []): visit(field)
        widgets = 0
        separate_objects = 0
        canonical = reader.get_fields() or {}
        for page in reader.pages:
            for ref in page.get('/Annots', []):
                obj = ref.get_object()
                if obj.get('/Subtype') != '/Widget': continue
                widgets += 1; ident = (ref.idnum, ref.generation)
                if ident not in reachable:
                    separate_objects += 1
                    field = canonical.get(obj.get('/T'))
                    assert field is not None, (name, obj.get('/T'), 'widget missing from catalog')
                    assert obj.get('/V') == field.get('/V'), (name, 'catalog/widget value mismatch')
                elif '/V' in obj: assert obj['/V'] == reachable[ident], (name, 'value mismatch')
                parent = obj
                while '/FT' not in parent and '/Parent' in parent: parent = parent['/Parent']
                if parent.get('/FT') == '/Sig': assert '/V' not in parent, (name, 'unsigned signature has value')
                ap = obj.get('/AP', {}).get('/N')
                assert ap is not None, (name, 'missing appearance')
                ap = ap.get_object()
                if not hasattr(ap, 'get_data'): ap = ap[obj['/AS']].get_object()
                assert ap.get_data(), (name, 'empty appearance')
        if 'flattened' in name: assert not widgets and not form.get('/Fields')
        print(name, 'catalog fields:', len(reader.get_fields() or {}), 'widgets:', widgets, 'separate catalog/widget objects:', separate_objects)
        doc = pdfium.PdfDocument(file)
        doc.init_forms()
        image = doc[0].render(scale=1.5, may_draw_forms=True).to_pil().convert('RGB')
        image.save(root/(name+'.png'))
        images[name] = image
if 'compatibility-editable' in images:
    a,b = (images[k] for k in ['compatibility-editable','compatibility-flattened'])
    assert a.size == b.size
    difference = sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3
    print('PDFium editable/flattened mean pixel difference:', difference)
    # PDFium can regenerate fonts and checkmarks differently from saved appearances.
    # This diagnostic is not a claim of pixel-identical rendering.

assert checked, "No compatibility fixture PDFs found in attachment manifest"
