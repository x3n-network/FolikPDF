"""macOS textutil supplies independently generated binary Word fixtures."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).parent
with tempfile.TemporaryDirectory() as temporary:
    for name, text in [("LegacyUnicode", "Legacy Word sample\nCafé — € quotes “hello”\nΕλληνικά 日本語 😀\nFINAL LEGACY MARKER\n"), ("LegacyLong", "Legacy pagination\n" + "".join(f"Legacy line {i:03d} must survive conversion.\n" for i in range(180)))]:
        source = Path(temporary) / (name + ".txt")
        source.write_text(text)
        subprocess.run(["/usr/bin/textutil", "-convert", "doc", "-inputencoding", "UTF-8", "-strip", "-output", str(root / (name + ".doc")), str(source)], check=True)

# Explicit MS-CFB/MS-DOC edge fixtures complement the native-exported files.
import struct
from zipfile import ZipFile, ZIP_DEFLATED

def u16(data, offset, value): struct.pack_into('<H', data, offset, value)
def u32(data, offset, value): struct.pack_into('<I', data, offset, value)
def compound(word, table):
    header=bytearray(512)
    header[:8]=bytes.fromhex('d0cf11e0a1b11ae1')
    for offset,value in [(24,0x3e),(26,3),(28,0xfffe),(30,9),(32,6)]: u16(header,offset,value)
    for offset,value in [(44,1),(48,1),(56,4096),(60,0xfffffffe),(68,0xfffffffe)]: u32(header,offset,value)
    for offset in range(76,512,4): u32(header,offset,0xffffffff)
    u32(header,76,0)
    fat=bytearray(b'\xff'*512);u32(fat,0,0xfffffffd);u32(fat,4,0xfffffffe)
    for start in [2,10]:
        for sid in range(start,start+8): u32(fat,sid*4,sid+1 if sid<start+7 else 0xfffffffe)
    directory=bytearray(512)
    for index,name,kind,start,size in [(0,'Root Entry',5,0xfffffffe,0),(1,'WordDocument',2,2,4096),(2,'1Table',2,10,4096)]:
        base=index*128; encoded=(name+'\0').encode('utf-16le');directory[base:base+len(encoded)]=encoded
        u16(directory,base+64,len(encoded));directory[base+66]=kind;directory[base+67]=1
        for offset in [68,72,76]:u32(directory,base+offset,0xffffffff)
        u32(directory,base+116,start);u32(directory,base+120,size)
    u32(directory,76,1);u32(directory,128+68,2)
    return bytes(header+fat+directory+word+table)

word=bytearray(4096);table=bytearray(4096)
u16(word,0,0xa5ec);u16(word,2,0xc1);u16(word,10,0x200);u16(word,32,14);u16(word,62,22);u16(word,152,93)
parts=[(b'Compressed caf\xe9 \x80 \x93quotes\x94\r',True),('Unicode 日本語 😀\r'.encode('utf-16le'),False),(b'Field \x13HYPERLINK secret\x14VISIBLE RESULT\x15\rCell A\x07Cell B\x07\rLAST PIECE\r',True)]
cp=[0]; descriptors=[];offset=2048
for text, compressed in parts:
    word[offset:offset+len(text)]=text
    cp.append(cp[-1]+len(text)//(1 if compressed else 2))
    descriptors.append(struct.pack('<HIH',0,(offset*2|0x40000000) if compressed else offset,0))
    offset+=len(text)+8
plc=b''.join(struct.pack('<I',n) for n in cp)+b''.join(descriptors)
clx=b'\x02'+struct.pack('<I',len(plc))+plc
table[:len(clx)]=clx;u32(word,76,cp[-1]);u32(word,418,0);u32(word,422,len(clx))
(root/'LegacyPieces.doc').write_bytes(compound(word,table))
encrypted=bytearray(word);u16(encrypted,10,0x300)
(root/'LegacyEncrypted.doc').write_bytes(compound(encrypted,table))
bad=bytearray(table);u32(bad,5+4,0xffffffff)
(root/'LegacyBadPieces.doc').write_bytes(compound(word,bad))

# Standalone two-page PDF, with independent PDF syntax and xref generation.
objects=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Count 2 /Kids [3 0 R 4 0 R] >>']
for stream in [6,7]: objects.append(f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents {stream} 0 R >>'.encode())
objects.append(b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
for marker in ['PAGES FIRST PAGE','PAGES FINAL PAGE']:
    content=f'BT /F1 18 Tf 72 720 Td ({marker}) Tj ET'.encode()
    objects.append(f'<< /Length {len(content)} >>\nstream\n'.encode()+content+b'\nendstream')
pdf=bytearray(b'%PDF-1.4\n');offsets=[0]
for index,obj in enumerate(objects,1):
    offsets.append(len(pdf));pdf+=f'{index} 0 obj\n'.encode()+obj+b'\nendobj\n'
xref=len(pdf);pdf+=f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode()
for offset in offsets[1:]:pdf+=f'{offset:010d} 00000 n \n'.encode()
pdf+=f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
for name,parts in [('PagesSavedPreview',{'QuickLook/Preview.pdf':pdf}),('PagesThumbnailOnly',{'preview.jpg':b'thumbnail is not a PDF'})]:
    with ZipFile(root/(name+'.pages'),'w',ZIP_DEFLATED) as archive:
        for path,contents in parts.items():archive.writestr(path,contents)
