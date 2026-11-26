"""Select a compatible release before downloading or installing."""
import queue, threading, tkinter as tk
from tkinter import ttk,messagebox
import connected_update as update
import fantasy_ui as fu, theme
class UpdatePage(tk.Frame):
    def __init__(self,parent,app):
        super().__init__(parent,bg=theme.BG);self.pack(fill='both',expand=True);self.app=app;self.results=queue.Queue();self.running=False
        fu.banner(self,'Update centre','Choose a compatible release');fu.footer(self)
        p=fu.panel(self,padx=24,pady=16);p.pack(fill='both',expand=True,padx=24,pady=12)
        fu.heading(p,'Connected Edition').pack(fill='x')
        fu.label(p,'Installed version '+update.VERSION,fg=theme.GILT).pack(anchor='w',pady=8)
        self.channel=tk.StringVar(value='development')
        self.channels=ttk.Combobox(p,textvariable=self.channel,values=update.CHANNELS,state='readonly');self.channels.pack(anchor='w');self.channels.bind('<<ComboboxSelected>>',lambda e:self.begin(False))
        self.selected=tk.StringVar(value=update.VERSION)
        self.versions=ttk.Combobox(p,textvariable=self.selected,values=[update.VERSION],state='readonly');self.versions.pack(anchor='w',pady=8)
        self.status=fu.label(p,'Checking available versions...',wraplength=650);self.status.pack(anchor='w',pady=10)
        self.refresh=theme.button(p,'Refresh versions',lambda:self.begin(False));self.refresh.pack(fill='x')
        self.check=theme.button(p,'Install selected version',lambda:self.begin(True),'gold');self.check.pack(fill='x',pady=5)
        self.back=theme.button(p,'Main menu',app.show_start);self.back.pack(fill='x');self.after_idle(lambda:self.begin(False))
    def begin(self,install):
        if self.running:return
        self.running=True
        for w in (self.check,self.back,self.refresh,self.channels,self.versions):w.configure(state='disabled')
        channel=self.channel.get();target=self.selected.get()
        self.status.configure(text='Checking release manifest...')
        def work():
            try:
                m=update.check(channel,target=target if install else None)
                staged=update.prepare(m) if install else None
                self.results.put((install,m,staged,None))
            except Exception as e:self.results.put((install,None,None,str(e)))
        threading.Thread(target=work,daemon=True).start();self.after(80,self.poll)
    def poll(self):
        try:install,m,staged,error=self.results.get_nowait()
        except queue.Empty:self.after(80,self.poll);return
        self.running=False
        for w in (self.check,self.back,self.refresh):w.configure(state='normal')
        for w in (self.channels,self.versions):w.configure(state='readonly')
        if error:self.status.configure(text='Update check failed: '+error);return
        if not install:
            choices=[update.VERSION]+[s['version'] for s in m.get('steps',[])]
            self.versions.configure(values=choices);self.selected.set(choices[-1])
            self.status.configure(text='Latest compatible version: '+choices[-1]);return
        if not staged:self.status.configure(text='Already installed.');return
        if not messagebox.askyesno('Install update',f"Install v{m['version']} and restart?\n\n{m.get('notes','')}\n\nLocal saves are not included.",parent=self):return
        backup=None
        try:backup=update.install(staged);update.restart()
        except Exception as e:
            if backup is not None:
                try:update.restore_backup(backup)
                except Exception as rollback_error:self.status.configure(text=f"Update error: {e}; restore from {backup}: {rollback_error}");return
            self.status.configure(text='Update error: '+str(e));return
        self.app.root.destroy()
