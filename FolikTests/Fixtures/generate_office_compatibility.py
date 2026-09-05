"""Small explicit OOXML/ODF fixtures for compatibility regressions. No private data."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).parent
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'

def write(name, parts):
    with ZipFile(root / name, 'w', ZIP_DEFLATED) as z:
        for key, value in parts.items():
            z.writestr(key, value)

def p(text, level=None):
    props = f'<w:pPr><w:numPr><w:ilvl w:val="{level}"/><w:numId w:val="1"/></w:numPr></w:pPr>' if level is not None else ''
    return f'<w:p>{props}<w:r><w:t>{text}</w:t></w:r></w:p>'

with ZipFile(root / 'OfficePreview.docx') as z:
    docx = {n: z.read(n) for n in z.namelist()}
docx['word/document.xml'] = f'''<w:document xmlns:w="{W}" xmlns:r="{R}" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" xmlns:v="urn:schemas-microsoft-com:vml"><w:body>
{p('Compatibility sample')}
<w:p><w:r><w:t>Styled: </w:t></w:r><w:r><w:rPr><w:strike/></w:rPr><w:t>removed</w:t></w:r><w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:t>super</w:t></w:r><w:r><w:rPr><w:vertAlign w:val="subscript"/></w:rPr><w:t>sub</w:t></w:r></w:p>
<w:p><w:hyperlink r:id="web"><w:r><w:t>Visit example</w:t></w:r></w:hyperlink><w:r><w:footnoteReference w:id="1"/><w:endnoteReference w:id="2"/></w:r></w:p>
{p('Outer first',0)}{p('Nested first',1)}{p('Nested second',1)}{p('Outer second',0)}{p('Nested reset',1)}
<w:p><mc:AlternateContent><mc:Choice Requires="wps"><w:r><w:drawing><wps:wsp><wps:txbx><w:txbxContent>{p('BOX ONCE')}</w:txbxContent></wps:txbx></wps:wsp></w:drawing></w:r></mc:Choice><mc:Fallback><w:r><w:pict><v:shape><v:textbox><w:txbxContent>{p('DUPLICATE FALLBACK')}</w:txbxContent></v:textbox></v:shape></w:pict></w:r></mc:Fallback></mc:AlternateContent></w:p>
<w:tbl><w:tblGrid><w:gridCol w:w="1800"/><w:gridCol w:w="5400"/></w:tblGrid><w:tr><w:tc>{p('Narrow')}</w:tc><w:tc>{p('Wide cell')}</w:tc></w:tr></w:tbl>
<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1200" w:bottom="1440" w:left="1800" w:right="1080"/></w:sectPr>
</w:body></w:document>'''
docx['word/numbering.xml'] = f'''<w:numbering xmlns:w="{W}"><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="upperLetter"/><w:lvlText w:val="%1."/></w:lvl><w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="lowerRoman"/><w:lvlText w:val="%1.%2)"/></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="3"/></w:lvlOverride></w:num></w:numbering>'''
docx['word/_rels/document.xml.rels'] = f'''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="num" Type="{R}/numbering" Target="numbering.xml"/><Relationship Id="web" Type="{R}/hyperlink" Target="https://example.com/compatibility" TargetMode="External"/><Relationship Id="notes" Type="{R}/footnotes" Target="footnotes.xml"/><Relationship Id="ends" Type="{R}/endnotes" Target="endnotes.xml"/></Relationships>'''
for kind, ident, text in [('footnote',1,'FOOTNOTE CONTENT'),('endnote',2,'ENDNOTE CONTENT')]:
    docx[f'word/{kind}s.xml'] = f'<w:{kind}s xmlns:w="{W}"><w:{kind} w:id="{ident}">{p(text)}</w:{kind}></w:{kind}s>'
write('OfficeCompatibility.docx', docx)

ns = ' '.join(f'xmlns:{p}="{u}"' for p,u in {
'office':'urn:oasis:names:tc:opendocument:xmlns:office:1.0', 'text':'urn:oasis:names:tc:opendocument:xmlns:text:1.0','style':'urn:oasis:names:tc:opendocument:xmlns:style:1.0','table':'urn:oasis:names:tc:opendocument:xmlns:table:1.0','draw':'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0','fo':'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0','svg':'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0','xlink':'http://www.w3.org/1999/xlink'}.items())
styles = '''<style:style style:name="strike" style:family="text"><style:text-properties style:text-line-through-style="solid"/></style:style><style:style style:name="super" style:family="text"><style:text-properties style:text-position="super 58%"/></style:style><style:style style:name="sub" style:family="text"><style:text-properties style:text-position="sub 58%"/></style:style><style:style style:name="narrow" style:family="table-column"><style:table-column-properties style:column-width="90pt"/></style:style><style:style style:name="wide" style:family="table-column"><style:table-column-properties style:column-width="270pt"/></style:style>
<text:list-style style:name="letters"><text:list-level-style-number text:level="1" style:num-format="A" style:num-suffix="." text:start-value="3"/><text:list-level-style-number text:level="2" style:num-format="i" style:num-suffix=")"/></text:list-style>'''
body = '''<text:p>Compatibility sample</text:p><text:p>Styled: <text:span text:style-name="strike">removed</text:span><text:span text:style-name="super">super</text:span><text:span text:style-name="sub">sub</text:span></text:p>
<text:p><text:a xlink:href="https://example.com/compatibility">Visit example</text:a><text:note text:id="f1" text:note-class="footnote"><text:note-citation>1</text:note-citation><text:note-body><text:p>FOOTNOTE CONTENT</text:p></text:note-body></text:note><text:note text:id="e2" text:note-class="endnote"><text:note-citation>2</text:note-citation><text:note-body><text:p>ENDNOTE CONTENT</text:p></text:note-body></text:note></text:p>
<text:list text:style-name="letters" xml:id="first"><text:list-item><text:p>Outer first</text:p><text:list><text:list-item><text:p>Nested first</text:p></text:list-item><text:list-item><text:p>Nested second</text:p></text:list-item></text:list></text:list-item></text:list>
<text:p>Between lists</text:p><text:list text:style-name="letters" text:continue-list="first"><text:list-item><text:p>Outer second</text:p></text:list-item></text:list>
<text:list text:style-name="letters" text:continue-numbering="true"><text:list-item><text:p>Outer third</text:p></text:list-item></text:list>
<draw:frame><draw:text-box><text:p>BOX ONCE</text:p></draw:text-box></draw:frame>
<table:table table:name="Widths"><table:table-column table:style-name="narrow"/><table:table-column table:style-name="wide"/><table:table-row><table:table-cell><text:p>Narrow</text:p></table:table-cell><table:table-cell><text:p>Wide cell</text:p></table:table-cell></table:table-row></table:table>'''
odt={'mimetype':'application/vnd.oasis.opendocument.text', 'content.xml':f'<office:document-content {ns} office:version="1.3"><office:automatic-styles>{styles}</office:automatic-styles><office:body><office:text>{body}</office:text></office:body></office:document-content>', 'styles.xml':f'''<office:document-styles {ns} office:version="1.3"><office:automatic-styles><style:page-layout style:name="unused"><style:page-layout-properties fo:page-width="500pt" fo:page-height="600pt"/></style:page-layout><style:page-layout style:name="active"><style:page-layout-properties fo:page-width="612pt" fo:page-height="792pt" fo:margin-top="60pt" fo:margin-bottom="72pt" fo:margin-left="90pt" fo:margin-right="54pt"/></style:page-layout></office:automatic-styles><office:master-styles><style:master-page style:name="Standard" style:page-layout-name="active"/></office:master-styles></office:document-styles>'''}
write('OfficeCompatibility.odt',odt)
for name, attr in [('OfficeHugeRows','table:number-rows-repeated'),('OfficeHugeCells','table:number-columns-repeated')]:
    bad=odt.copy()
    tag='table:table-row' if name.endswith('Rows') else 'table:table-cell'
    bad['content.xml']=bad['content.xml'].replace(f'<{tag}>',f'<{tag} {attr}="9223372036854775807">',1)
    write(name+'.odt',bad)
