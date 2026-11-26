"""Home-screen release checker; download occurs off the UI thread."""
import queue,threading,tkinter as tk
from tkinter import ttk,messagebox
import connected_update as update
import fantasy_ui as fu, theme
class UpdatePage(tk.Frame):
    def __init__(self,parent,app):
        super().__init__(parent,bg=theme.BG);self.pack(fill='both',expand=True);self.app=app;self.results=queue.Queue();self.running=False
        fu.banner(self,'Update centre','One release channel · every workstation');fu.footer(self)
        p=fu.panel(self,padx=24,pady=16);p.pack(fill='both',expand=True,padx=50,pady=12)
        controls=tk.Frame(p,bg=theme.PANEL);controls.pack(side='left',anchor='n',fill='y',padx=(8,24));p=controls
        fu.heading(p,'Connected Edition').pack(fill='x');fu.label(p,'Installed version '+update.VERSION,fg=theme.GILT,font=('Georgia',16,'bold')).pack(anchor='w',pady=14)
        self.channel=tk.StringVar(value='development');ttk.Combobox(p,textvariable=self.channel,values=update.CHANNELS,state='readonly').pack(anchor='w')
        self.status=fu.label(p,'Check GitHub for an update. Your local campaigns and credentials are excluded.',wraplength=430);self.status.pack(anchor='w',pady=15)
        self.check=theme.button(p,'Check & update',self.begin,'gold');self.check.pack(fill='x');self.back=theme.button(p,'Main menu',app.show_start);self.back.pack(fill='x',pady=8);self.after_idle(self.begin)
    def begin(self):
        if self.running:return
        self.running=True;self.check.configure(state='disabled');self.back.configure(state='disabled');self.status.configure(text='Checking the release channel…');channel=self.channel.get()
        def work():
            try:
                m=update.check(channel); staged=update.prepare(m);self.results.put((m,staged,None))
            except Exception as e:self.results.put((None,None,str(e)))
        threading.Thread(target=work,daemon=True).start();self.after(80,self.poll)
    def poll(self):
        try:m,staged,error=self.results.get_nowait()
        except queue.Empty:self.after(80,self.poll);return
        self.running=False;self.check.configure(state='normal');self.back.configure(state='normal')
        if error:self.status.configure(text='Update check failed: '+error);return
        if not staged:self.status.configure(text='No newer installable release. '+str(m.get('notes','')));return
        if not messagebox.askyesno('Install update',f"Install v{m['version']} and restart?\n\n{m.get('notes','')}\n\n{len(staged)} verified files. Local saves are not included.",parent=self):return
        backup=None
        try:
            backup=update.install(staged);update.restart()
        except Exception as e:
            if backup is not None:
                try:update.restore_backup(backup)
                except Exception as rollback_error:self.status.configure(text=f"Update error: {e}; restore from {backup}: {rollback_error}");return
            self.status.configure(text='Update error: '+str(e));return
        self.app.root.destroy()
