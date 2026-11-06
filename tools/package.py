"""Package only this mod; never ship loader files, other mods, or development state."""
from pathlib import Path
import hashlib,json,sys,zipfile
root=Path(__file__).resolve().parents[1]
out=Path(sys.argv[1]).resolve();out.mkdir(parents=True,exist_ok=True)
mod=root/'mod/BeyondDetours'
meta=json.loads((mod/'bmm.json').read_text());version=meta['Version']
prefix='DriveBeyondHorizons/Binaries/Win64/ue4ss/Mods/BeyondDetours/'
files=[p for p in mod.rglob('*') if p.is_file() and (p.parent.name=='Scripts' and p.suffix=='.lua' or p.relative_to(mod).as_posix() in {'bmm.json','enabled.txt','state/.keep'})]
for p in files:
    assert b'Preston' not in p.read_bytes() and b'qa-sockets' not in p.read_bytes(),p
release=out/f'BeyondDetours-{version}-experimental.zip'
with zipfile.ZipFile(release,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(files):z.write(p,prefix+p.relative_to(mod).as_posix())
    for name in ('README.md','TESTING.txt'):
        assert (root/name).is_file(),name
        z.write(root/name,name)
with zipfile.ZipFile(release) as z:
    assert z.testzip() is None
    assert len(z.namelist())==len(set(z.namelist()))
    assert all(n.startswith(prefix) or n in {'README.md','TESTING.txt'} for n in z.namelist())
source=out/f'BeyondDetours-{version}-source.zip'
with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(files):z.write(p,'BeyondDetours/'+p.relative_to(root).as_posix())
    for folder in ('tests','tools'):
        for p in sorted((root/folder).rglob('*')):
            if p.is_file() and p.suffix in {'.py','.lua'}:z.write(p,'BeyondDetours/'+p.relative_to(root).as_posix())
    for name in ('README.md','TESTING.txt'):z.write(root/name,'BeyondDetours/'+name)
(out/'SHA256SUMS.txt').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in (release,source)),encoding='utf-8')
print(release);print(source)
