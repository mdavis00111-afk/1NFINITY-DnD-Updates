"""Smooth wheel movement and reliable tail-follow for the two game journals."""
import tkinter as tk
import tkinter.font as tkfont


def install():
    root = tk._default_root
    if root is None or getattr(root, '_journal_scroll_installed', False):
        return
    root._journal_scroll_installed = True
    root.bind_class('Text', '<Map>', _mapped, add='+')


def _mapped(event):
    w = event.widget
    # Only the adventure and combat journals use all four of these tags.
    if getattr(w, '_journal_scroll', False) or not {'you', 'dm', 'sys', 'err'}.issubset(w.tag_names()):
        return
    w._journal_scroll = True
    w._journal_size = w.index('end-1c')
    w.edit_modified(False)

    def wheel(event):
        delta = getattr(event, 'delta', 0)
        if event.num == 4:
            steps = -1
        elif event.num == 5:
            steps = 1
        elif w.tk.call('tk', 'windowingsystem') == 'aqua':
            steps = -delta / 8
        else:
            steps = -delta / 120
        if steps:
            pixels = max(1, tkfont.Font(root=w, font=w.cget('font')).metrics('linespace'))
            movement = int(steps * pixels)
            if not movement:
                movement = 1 if steps > 0 else -1
            w.yview_scroll(movement, 'pixels')
        return 'break'

    def follow():
        if w.winfo_exists():
            w.yview_moveto(1.0)

    def modified(event):
        if not w.edit_modified():
            return
        end = w.index('end-1c')
        grew = w.compare(end, '>', w._journal_size)
        w._journal_size = end
        w.edit_modified(False)
        if grew:
            w.after_idle(follow)

    for sequence in ('<MouseWheel>', '<Button-4>', '<Button-5>'):
        w.bind(sequence, wheel)
    w.bind('<<Modified>>', modified, add='+')
    w.after_idle(follow)
