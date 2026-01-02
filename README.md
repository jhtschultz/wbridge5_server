# WBridge5 on Cloud Run

This folder contains a container image that installs WBridge5 inside a Wine-powered X11 desktop and exposes it through noVNC (plus a ttyd web shell) so the game can run on Google Cloud Run or any Docker host.

## Contents

| File | Purpose |
| --- | --- |
| `Dockerfile` | Builds the Debian-based image, installs Wine/Fluxbox/noVNC/nginx, downloads the official WBridge5 installer, and performs a silent install inside a dedicated Wine prefix (64-bit to satisfy Cloud Run's gVisor runtime). Includes extensive font configuration for proper rendering. |
| `LEARNINGS.md` | Documents Wine limitations, troubleshooting attempts, and known issues. |
| `start.sh` | Launches Xvfb, Fluxbox, WBridge5 (via Wine), x11vnc, noVNC, ttyd, and nginx. |
| `nginx.conf` | Serves noVNC’s static assets from `/` and proxies `/websockify` plus `/shell/`. |
| `fluxbox.menu` / `wbridge5.desktop` | Make WBridge5 discoverable from the desktop’s right-click menu or any XDG-aware menu. |

## Building Locally

```bash
chmod +x start.sh
docker build -t wbridge5-novnc .
docker run --rm -p 8080:8080 wbridge5-novnc   # use -p 8082:8080 if 8080 is occupied
```

Open http://localhost:8080 for the desktop (right-click → “WBridge5” if you ever close it) and http://localhost:8080/shell for ttyd.

## Publishing for Cloud Run

Cloud Run requires `linux/amd64`. If you’re on Apple Silicon, use Buildx:

```bash
PROJECT_ID="<YOUR_PROJECT>"
REGION="us-central1"
IMAGE="gcr.io/${PROJECT_ID}/wbridge5-novnc"

docker buildx create --use --name wbridge5-builder || docker buildx use wbridge5-builder
docker buildx build \
  --platform linux/amd64 \
  -t "${IMAGE}" \
  --push .

gcloud run deploy wbridge5-novnc \
  --image "${IMAGE}" \
  --platform managed \
  --region "${REGION}" \
  --allow-unauthenticated \
  --memory 2Gi \
  --port 8080
```

## Known Limitations

**Bidding panel suit symbols appear as squares.** The bidding history panel uses a RichEdit control to display colored text. Wine's RichEdit implementation doesn't properly trigger Font Linking for symbol characters, so ♠♥♦♣ render as squares. The playing cards themselves render correctly (they use direct GDI drawing). This is a Wine limitation, not a configuration issue. See `LEARNINGS.md` for all attempted fixes.

## Notes & Requirements

- **noVNC must be cloned from GitHub**, not installed from Debian packages. The Debian `novnc` package has an incompatible `sendString` implementation that breaks keyboard input.
- The Dockerfile downloads `Wbridge5_setup.exe` from `http://www.wbridge5.com/Wbridge5_setup.exe`. If that URL changes or requires authentication, update `WB5_URL`.
- Wine runs in a 64-bit prefix at `/opt/wbridge5/wineprefix` so the Cloud Run sandbox (gVisor) never has to execute Linux i386 binaries. 32-bit Windows support still works via WoW64, and winetricks installs `corefonts`, `ie8`, `gdiplus`, `tahoma`, and `fontsmooth=rgb` so the UI/fonts look native.
- The WBridge5 installer must support silent switches (the provided command uses `/SP- /VERYSILENT /SUPPRESSMSGBOXES /NOCANCEL /DIR="C:\Wbridge5"`). If the options change, adjust the `wine` command in the Dockerfile.
- ALSA/sound warnings are expected on Cloud Run (no sound hardware).
- nginx serves `/vnc.html` directly and proxies `/websockify`. A healthy deployment returns `400 Bad Request` when you `curl -I https://SERVICE/websockify`.

With these assets you can clone, build, and deploy WBridge5 the same way as the GNUBG service, just swap the image name/project references as needed.
