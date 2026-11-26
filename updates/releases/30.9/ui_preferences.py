"""Local presentation settings; never part of a release patch."""
import json
import config
DEFAULTS={'background':'varied','journal_size':13,'panes':[.24,.72]}
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
theme.style_app = _style
