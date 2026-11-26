"""Shared illustrated surfaces for the live Tk interface (not screenshot controls)."""
import tkinter as tk
from tkinter import ttk
from functools import lru_cache
from PIL import Image, ImageTk, ImageOps, ImageDraw, ImageFilter
import theme, ui_art

def scene(kind,w,h,strength):
    import ui_preferences
    choice=ui_preferences.load().get('background','varied')
    return _scene(choice if choice in ('castle','forest','lake','ruins') else kind,w,h,strength)

@lru_cache(maxsize=32)
def _scene(kind,w,h,strength):
    import fantasy_ui as fu
    im = ImageOps.fit(fu._scene(kind), (w,h), centering=(.5,.58))
    return Image.blend(im, Image.new('RGB',(w,h),'#06191e'), strength/100)

def frame_art(im, bright=False):
    w,h=im.size
    if min(w,h)<18:return im
    d=ImageDraw.Draw(im)
    gold='#ffe1a0' if bright else '#d6aa60'
    glow=Image.new('RGB',(w,h)); g=ImageDraw.Draw(glow)
    g.rounded_rectangle((3,3,w-4,h-4),radius=9,outline='#a96620',width=3)
    from PIL import ImageChops
    im=ImageChops.add(im,glow.filter(ImageFilter.GaussianBlur(4)));d=ImageDraw.Draw(im)
    d.rounded_rectangle((2,2,w-3,h-3),radius=8,outline=gold,width=1)
    d.rounded_rectangle((5,5,w-6,h-6),radius=6,outline='#916531',width=1)
    for x,y,s,t in [(6,6,1,1),(w-7,6,-1,1),(6,h-7,1,-1),(w-7,h-7,-1,-1)]:
        n=min(27,w//5,h//2-5)
        if n<4:continue
        d.line([(x,y+t*n),(x+s*2,y+t*9),(x+s*9,y+t*2),(x+s*n,y)],fill=gold,width=2)
        d.line([(x+s*3,y+t*n),(x+s*8,y+t*8),(x+s*n,y+t*3)],fill='#bc8948')
        d.polygon([(x+s*2,y+t*2),(x+s*9,y+t*4),(x+s*4,y+t*9)],outline=gold)
    for y in (4,h-5):
        x=w//2;d.polygon([(x-6,y),(x,y-3),(x+6,y),(x,y+3)],fill=gold)
    return im

@lru_cache(maxsize=128)
def plate(w,h,base='#292b30',ornate=True):
    from PIL import ImageColor
    im=scene('castle',w,h,83).copy()
    im=Image.blend(im,Image.new('RGB',(w,h),ImageColor.getrgb(base)),.40)
    return frame_art(im,base in ('#4c3718','#3d514d','#b85d65')) if ornate else im

def kind_for(w):
    import fantasy_ui as fu
    p=w
    while p is not None:
        if hasattr(p,'_scene_kind'):return p._scene_kind
        name=type(p).__name__.lower()
        if 'combat' in name:return 'ruins'
        if 'character' in name or 'wizard' in name:return 'forest'
        if 'campaign' in name:return 'lake'
        p=getattr(p,'master',None)
    return 'castle'

def surface(w):
    if not w.winfo_exists() or not w.winfo_ismapped() or isinstance(w.master,(tk.Tk,tk.Toplevel)):return
    width,height=w.winfo_width(),w.winfo_height()
    if width<140 or height<85:return
    if str(w.cget('bg')) not in (theme.PANEL,theme.BG):return
    kind=kind_for(w); sig=(width,height,kind)
    label=getattr(w,'_scenic_surface',None)
    if label is not None and label.winfo_exists() and getattr(w,'_scenic_sig',None)==sig:return
    if label is None or not label.winfo_exists():
        label=tk.Label(w,bd=0,highlightthickness=0,takefocus=False)
        w._scenic_surface=label
    border=int(w.cget('highlightthickness'))>0
    im=scene(kind,width,height,49 if border else 38).copy()
    if border:im=frame_art(im)
    label.photo=ImageTk.PhotoImage(im,master=w);label.configure(image=label.photo)
    label.place(x=0,y=0,relwidth=1,relheight=1);label.lower();w._scenic_sig=sig
    if str(w.cget('cursor'))=='hand2':
        label.configure(cursor='hand2');label.bind('<Button-1>',lambda e:w.event_generate('<Button-1>'))

def on_frame(event):
    w=event.widget
    if getattr(w,'_scenic_job',None):w.after_cancel(w._scenic_job)
    def draw():
        w._scenic_job=None
        if w.winfo_exists():surface(w)
    w._scenic_job=w.after_idle(draw)

def ribbon(parent,title,height=36,kind='lake',subtitle=''):
    c=tk.Canvas(parent,height=height,bg=theme.INK,highlightthickness=0)
    def draw(e):
        w,h=max(1,e.width),max(1,e.height)
        im=frame_art(scene(kind,w,h,35 if subtitle else 65).copy(),True)
        c.photo=ImageTk.PhotoImage(im,master=c);c.delete('all');c.create_image(0,0,image=c.photo,anchor='nw')
        y=h*.40 if subtitle else h/2
        size=min(25,max(10,h//3),max(10,int(w/max(1,len(title))/.68)))
        font=('Georgia',size,'bold')
        c.create_text(w/2+1,y+2,text=title,fill='#080d10',font=font)
        c.create_text(w/2,y,text=title,fill='#ffe0a0',font=font)
        if subtitle:c.create_text(w/2,h*.76,text=subtitle,fill=theme.PARCH,font=('Georgia',12,'italic'))
    c.bind('<Configure>',draw);return c

def heading(parent,text):
    return ribbon(parent,'✦  '+text.upper()+'  ✦',34,kind_for(parent))

def scroll(parent):
    shell=tk.Frame(parent,bg=theme.PANEL);shell.pack(fill='both',expand=True)
    c=tk.Canvas(shell,bg=theme.PANEL,highlightthickness=0);c.pack(side='left',fill='both',expand=True)
    sb=ttk.Scrollbar(shell,command=c.yview);sb.pack(side='right',fill='y');c.configure(yscrollcommand=sb.set)
    body=tk.Frame(c,bg=theme.PANEL);win=c.create_window(0,0,anchor='nw',window=body)
    art=c.create_image(0,0,anchor='nw');c.tag_lower(art)
    def extent(e=None):c.configure(scrollregion=(0,0,c.winfo_width(),max(c.winfo_height(),body.winfo_reqheight())))
    def resize(e):
        c.itemconfigure(win,width=e.width)
        c.photo=ImageTk.PhotoImage(scene(kind_for(parent),max(1,e.width),max(1,e.height),35),master=c)
        c.itemconfigure(art,image=c.photo);extent()
    body.bind('<Configure>',extent);c.bind('<Configure>',resize);return body

def install(root):
    import fantasy_ui as fu
    if getattr(root,'_immersive_installed',False):return
    root._immersive_installed=True
    ui_art.plate=plate
    if not getattr(fu,'_immersive_patched',False):
        original=fu.banner
        def banner(parent,title,*args,**kw):
            parent._scene_kind=fu.scene_for(title)
            return original(parent,title,*args,**kw)
        fu.banner=banner;fu.heading=heading;fu.ribbon=ribbon;fu.scroll=scroll;fu._immersive_patched=True
    root.bind_class('Frame','<Map>',on_frame,add='+')
    root.bind_class('Frame','<Configure>',on_frame,add='+')
    root.bind_class('Text','<Map>',journal,add='+')

def journal(event):
    w=event.widget
    if getattr(w,'_journal_scroll',False) or not {'you','dm','sys','err'}.issubset(w.tag_names()):return
    w._journal_scroll=True;w.edit_modified(False)
    def wheel(e):
        delta=getattr(e,'delta',0)
        n=-1 if e.num==4 else 1 if e.num==5 else -delta/(8 if w.tk.call('tk','windowingsystem')=='aqua' else 120)
        if n:w.yview_scroll(max(1,round(abs(n)*18))*(1 if n>0 else -1),'pixels')
        return 'break'
    def follow(e):
        if w.edit_modified():
            w.edit_modified(False);w.after_idle(lambda:w.yview_moveto(1.0) if w.winfo_exists() else None)
    for seq in ('<MouseWheel>','<Button-4>','<Button-5>'):w.bind(seq,wheel)
    w.bind('<<Modified>>',follow,add='+');w.after_idle(lambda:w.yview_moveto(1.0) if w.winfo_exists() else None)
