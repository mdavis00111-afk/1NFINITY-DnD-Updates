"""Explicit user-initiated updates from the project's fixed GitHub repository.
Only release-listed code/art files may change; local secrets and saves are excluded.
The manifest and content are fetched over HTTPS from the same trusted publisher.
"""
import hashlib,json,os,re,shutil,sys,tempfile,urllib.request,subprocess,time
from pathlib import Path,PurePosixPath
import config
VERSION='30.13'
ORIGIN='https://raw.githubusercontent.com/mdavis00111-afk/1NFINITY-DnD-Updates/'
CHANNELS=('development','stable')
MAX_BYTES=8*1024*1024
PROTECTED={'prompts.py','content_control.py','credentials.py','config.py','run.bat','setup.ps1'}
def version(v):
    if not isinstance(v,str) or not re.fullmatch(r'\d+(?:\.\d+){1,3}',v):raise ValueError('Invalid release version')
    return tuple((list(map(int,v.split('.')))+[0]*4)[:4])
def fetch(relative):
    if not re.fullmatch(r'[A-Za-z0-9_./-]+',relative) or '..' in PurePosixPath(relative).parts:raise ValueError('Invalid remote path')
    url=ORIGIN+relative
    if relative.startswith('main/updates/'):url+='?fresh='+str(time.time_ns())
    req=urllib.request.Request(url,headers={'User-Agent':'1NFINITY-DnD-Updater','Cache-Control':'no-cache','Pragma':'no-cache'})
    with urllib.request.urlopen(req,timeout=15) as response:
        if not response.geturl().startswith(ORIGIN):raise ValueError('Unexpected update redirect')
        data=response.read(MAX_BYTES+1)
    if len(data)>MAX_BYTES:raise ValueError('Update file exceeds size limit')
    return data

def check(channel='development',reader=fetch):
    if channel not in CHANNELS:raise ValueError('Unknown release channel')
    path='main/updates/manifest.json' if channel=='development' else 'main/updates/stable.json'
    m=json.loads(reader(path))
    if m.get('schema')!=1 or m.get('channel')!=channel:raise ValueError('Invalid update manifest')
    releases=m.get('releases',[])
    if not isinstance(releases,list) or len(releases)>100:raise ValueError('Invalid release history')
    history=[m]+releases
    previous=None
    for step in history:
        v=version(step['version'])
        if step.get('schema')!=1 or step.get('channel')!=channel or (previous is not None and v<=previous):raise ValueError('Invalid release order')
        previous=v
    current=VERSION;steps=[]
    for step in history:
        if version(step['version'])<=version(current):continue
        if step.get('status')!='ready' or current not in step.get('from_versions',[]):raise ValueError('No compatible update path from v'+current+' to v'+step['version'])
        steps.append(step);current=step['version']
    if not steps:return {'schema':1,'channel':channel,'status':'ready','version':VERSION,'notes':'Already up to date.','steps':[]}
    return {'schema':1,'channel':channel,'status':'ready','version':current,'steps':steps,'notes':'\n'.join('v'+s['version']+': '+s.get('notes','') for s in steps)}

def target_path(root,name):
    p=PurePosixPath(name)
    if p.is_absolute() or '..' in p.parts or not p.parts or '\\' in name or ':' in name:raise ValueError('Unsafe update path')
    if len(p.parts)==1:
        if p.suffix!='.py' or not re.fullmatch(r'[a-zA-Z0-9_]+\.py',name) or name.casefold() in PROTECTED:raise ValueError('Protected or unsupported file: '+name)
    elif p.parts[:2]!=('assets','backgrounds') or len(p.parts)!=3 or p.suffix not in ('.jpg','.png','.webp'):raise ValueError('Protected or unsupported path: '+name)
    dest=root.joinpath(*p.parts)
    if not dest.resolve().is_relative_to(root.resolve()) or any(x.is_symlink() for x in [dest,*dest.parents] if x!=root.parent):raise ValueError('Unsafe destination')
    return dest

def apply_delta(base,payload):
    patch=json.loads(payload)
    base=base.replace(b'\r\n',b'\n')
    digest=hashlib.sha256(base).hexdigest()
    if digest==patch['result_sha256']:return base
    if digest!=patch['base_sha256']:raise ValueError('Local source differs from expected version; no files changed. Install a matching full build.')
    lines=base.decode('utf-8').splitlines(keepends=True)
    edits=patch['edits'];previous=0
    if not isinstance(edits,list) or len(edits)>10000:raise ValueError('Invalid delta edits')
    for start,end,replacement in edits:
        if type(start) is not int or type(end) is not int or not previous<=start<=end<=len(lines) or not isinstance(replacement,str):raise ValueError('Invalid delta range')
        previous=end
    for start,end,replacement in reversed(edits):lines[start:end]=[replacement]
    data=''.join(lines).encode('utf-8')
    if hashlib.sha256(data).hexdigest()!=patch['result_sha256']:raise ValueError('Reconstructed source checksum mismatch')
    return data

def prepare(m,root=None,reader=fetch):
    import ast
    root=Path(root or config.BASE_DIR)
    if m.get('status')!='ready' or version(m['version'])<=version(VERSION):return []
    steps=m.get('steps',[m]); current=VERSION; pending={}; total=0
    if not isinstance(steps,list) or not 1<=len(steps)<=100:raise ValueError('Invalid release plan')
    for step in steps:
        if step.get('status')!='ready' or current not in step.get('from_versions',[]) or version(step['version'])<=version(current):raise ValueError('Invalid upgrade path: different base version')
        files=step.get('files'); commit=step.get('commit','')
        if not isinstance(files,list) or not 1<=len(files)<=100 or not re.fullmatch(r'[0-9a-f]{40}',commit):raise ValueError('Incomplete release manifest')
        seen=set()
        for entry in files:
            name=entry['path'];dest=target_path(root,name);key=name.casefold()
            if key in seen or (key in pending and pending[key][0]!=dest):raise ValueError('Duplicate update destination')
            seen.add(key);remote=entry['remote']
            if not remote.startswith('updates/releases/') or '..' in PurePosixPath(remote).parts:raise ValueError('Invalid release location')
            data=reader(commit+'/'+remote);total+=len(data)
            if total>64*1024*1024 or len(data)>MAX_BYTES:raise ValueError('Update exceeds size limit')
            if hashlib.sha256(data).hexdigest()!=entry['sha256']:raise ValueError('Checksum mismatch: '+name)
            mode=entry.get('mode','full')
            if mode=='line_delta':data=apply_delta(pending[key][1] if key in pending else dest.read_bytes(),data)
            elif mode!='full':raise ValueError('Unknown patch mode')
            if len(data)>MAX_BYTES:raise ValueError('Expanded file exceeds size limit')
            if dest.suffix=='.py':compile(data,name,'exec')
            pending[key]=(dest,data)
        if 'connected_update.py' not in seen:raise ValueError('Release must include its versioned updater')
        tree=ast.parse(pending['connected_update.py'][1]); values=[node.value.value for node in tree.body if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='VERSION' for t in node.targets) and isinstance(node.value,ast.Constant)]
        if values!=[step['version']]:raise ValueError('Updater version does not match release')
        current=step['version']
    if current!=m['version']:raise ValueError('Incomplete upgrade path')
    if sum(len(data) for _,data in pending.values())>64*1024*1024:raise ValueError('Expanded update exceeds size limit')
    return list(pending.values())

def install(staged,root=None):
    root=Path(root or config.BASE_DIR); backup=Path(tempfile.mkdtemp(prefix='connected-',dir=root/'backups')) if (root/'backups').exists() else None
    if backup is None:
        (root/'backups').mkdir(exist_ok=True);backup=Path(tempfile.mkdtemp(prefix='connected-',dir=root/'backups'))
    saved=[]
    try:
        for dest,data in staged:
            dest=target_path(root,dest.relative_to(root).as_posix()); rel=dest.relative_to(root); old=backup/rel
            if dest.exists():old.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(dest,old)
            saved.append((dest,old if old.exists() else None))
        (backup/'restore.json').write_text(json.dumps([{'path':d.relative_to(root).as_posix(),'existed':o is not None} for d,o in saved]))
        for dest,data in staged:
            dest.parent.mkdir(parents=True,exist_ok=True);replace(dest,data)
    except BaseException:
        for dest,old in reversed(saved):
            if old is not None:replace(dest,old.read_bytes())
            elif dest.exists():dest.unlink()
        raise
    return backup

def replace(dest,data):
    fd,tmp=tempfile.mkstemp(prefix='.update-',dir=dest.parent)
    try:
        with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
        os.replace(tmp,dest)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)

def restore_backup(backup,root=None):
    root=Path(root or config.BASE_DIR)
    for entry in json.loads((backup/'restore.json').read_text()):
        dest=target_path(root,entry['path'])
        if entry['existed']:replace(dest,(backup/entry['path']).read_bytes())
        elif dest.exists():dest.unlink()

def restart():
    subprocess.Popen([sys.executable,str(config.BASE_DIR/'app.py')],cwd=config.BASE_DIR)
