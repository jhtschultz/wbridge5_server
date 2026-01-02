# WBridge5 Wine/VNC Server - Learnings

## What Works

- **VNC access via noVNC** - Browser-based VNC works well
- **Card rendering** - Playing cards display correctly with proper suit symbols
- **Window management** - Auto-maximize fills the screen properly
- **Basic functionality** - WBridge5 is fully playable

## Known Issue: Bidding Panel Suit Symbols

The bidding panel and bid history show squares instead of suit symbols (♠♥♦♣). This is a Wine limitation, not a configuration issue.

### Root Cause

WBridge5's bidding panel uses a **RichEdit control** to display mixed-color text (red for hearts/diamonds, black for spades/clubs). Wine's RichEdit implementation doesn't properly handle symbol font fallback the way native Windows does.

On Windows:
1. App requests "MS Sans Serif" with SYMBOL_CHARSET
2. GDI Font Linking automatically falls back to Symbol.ttf for glyphs not in the primary font
3. Suit symbols render correctly

On Wine:
1. RichEdit control doesn't trigger Font Linking for symbol characters
2. Even with correct fonts installed, the fallback mechanism doesn't work
3. Symbols appear as squares (tofu)

**Note:** The card faces themselves render correctly because they use a different rendering path (likely direct GDI drawing, not RichEdit).

### Fixes Attempted (All Unsuccessful for Bidding Panel)

1. **Font Linking Registry Keys**
   ```
   [HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink]
   "Tahoma"="symbol.ttf"
   "Arial"="symbol.ttf"
   etc.
   ```
   - Wine respects these keys for normal text rendering
   - RichEdit controls bypass this mechanism

2. **Font Substitution Registry Keys**
   ```
   [HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
   "MS Sans Serif"="Microsoft Sans Serif"
   ```
   - Maps legacy bitmap fonts to TrueType equivalents
   - Doesn't solve the RichEdit symbol issue

3. **Native RichEdit DLLs**
   ```bash
   winetricks riched20 riched30
   ```
   - Installs native Windows RichEdit DLLs
   - Still doesn't handle symbol font fallback properly in Wine environment

4. **Microsoft Sans Serif TrueType Font**
   ```bash
   winetricks micross
   ```
   - Proper TrueType font with SYMBOL_CHARSET support
   - Font installs correctly but RichEdit still doesn't use it for symbols

5. **Symbol Font Regeneration**
   ```bash
   fontforge -lang=ff -c 'Open("symbol.ttf"); Generate("symbol_new.sym.ttf")'
   ```
   - Regenerates symbol.ttf with TrueType Symbol encoding
   - Referenced from Wine forums as potential fix
   - No effect on RichEdit rendering

6. **Additional Fonts**
   - `winetricks allfonts` - All available fonts
   - Segoe UI Symbol from GitHub
   - DejaVu fonts (have Unicode suit symbols)
   - None solve the RichEdit issue

7. **Windows Components**
   ```bash
   winetricks windowscodecs oleaut32 msxml6
   ```
   - Various Windows components that might affect rendering
   - No effect on the specific issue

### Conclusion

This appears to be a fundamental limitation of Wine's RichEdit implementation. The issue is tracked in various Wine bug reports but remains unfixed. Possible workarounds:

1. **Accept the limitation** - The game is fully playable; suit symbols in bidding panel are cosmetic
2. **Patch WBridge5** - If source were available, could modify to use direct text rendering instead of RichEdit
3. **Wait for Wine improvements** - Future Wine versions may fix RichEdit font fallback

## Other Gotchas

### noVNC Version
- **Must use GitHub noVNC**, not Debian packages
- Debian's `novnc` package has incompatible `sendString` implementation
- Clone from: `https://github.com/novnc/noVNC.git`

### websockify
- Use standalone `websockify` command, not `novnc_proxy`
- `novnc_proxy` from Debian packages is incompatible

### Resolution
- 1024x768 works well for WBridge5
- Higher resolutions (1280x1024) cause window sizing issues
- Use `wmctrl` to auto-maximize the window after startup

### Wine Architecture
- WBridge5 works with `win64` architecture
- Uses `wine64` command to avoid 32-bit loader issues on gVisor (Cloud Run)

### winetricks Dependencies
- `xz-utils` required for `allfonts` package
- `fontforge` required for symbol font regeneration
- Run winetricks commands with `xvfb-run -a` during Docker build
