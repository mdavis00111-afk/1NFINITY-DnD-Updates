"""Local presentation settings; never part of a release patch."""
import json
import config
DEFAULTS={'background':'varied','journal_size':13,'panes':[.24,.72],'fullscreen':True}
CHOICES={'varied':'Varied by screen','castle':'Castle at dawn','lake':'Misty lake','ruins':'Ancient ruins','forest':'Enchanted forest'}
def load():
    try:
        value=json.loads((config.BASE_DIR/'.ui_preferences.json').read_text())
        return {**DEFAULTS,**{k:v for k,v in value.items() if k in DEFAULTS}}
    except (OSError,ValueError,AttributeError):return dict(DEFAULTS)
def save(**values):
    prefs={**load(),**values}; p=config.BASE_DIR/'.ui_preferences.json';t=p.with_suffix('.tmp');t.write_text(json.dumps(prefs));t.replace(p)

# Install shared visuals before the first live page is created.
import theme
_original_style = theme.style_app
def _style(root):
    _original_style(root)
    import immersive_ui
    immersive_ui.install(root)
    install_fullscreen(root)
theme.style_app = _style


def install_fullscreen(root):
    """Use the existing single window, preserving its windowed geometry."""
    if getattr(root, '_fullscreen_installed', False):return
    root._fullscreen_installed=True
    root._fullscreen_enabled=False
    def set_mode(enabled,remember=True):
        try:root.attributes('-fullscreen',bool(enabled))
        except theme.tk.TclError:return False
        root._fullscreen_enabled=bool(enabled)
        if remember:
            try:save(fullscreen=bool(enabled))
            except OSError:pass
        return True
    def toggle(event=None):
        set_mode(not root._fullscreen_enabled)
        return 'break'
    def escape(event=None):
        if root._fullscreen_enabled:
            set_mode(False)
            return 'break'
    root.bind('<F11>',toggle,add='+')
    root.bind('<Escape>',escape,add='+')
    root.after_idle(lambda:set_mode(load().get('fullscreen',True),remember=False))
