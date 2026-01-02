# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    DISPLAY=:0 \
    NOVNC_LISTEN=6080 \
    TTYD_PORT=7681 \
    WINEPREFIX=/opt/wbridge5/wineprefix \
    WINEARCH=win64 \
    WB5_INSTALL_DIR="C:\\Wbridge5"

ARG WB5_URL="http://www.wbridge5.com/Wbridge5_setup.exe"
ARG TTYD_VERSION=1.7.7

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        locales \
        xvfb \
        fluxbox \
        x11vnc \
        websockify \
        nginx \
        procps \
        curl \
        ca-certificates \
        cabextract \
        unzip \
        xauth \
        winbind \
        fonts-wine \
        git \
        xz-utils \
        xdotool \
        wmctrl \
        fontforge \
        wine \
        wine32 \
        wine64 \
    && arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
        amd64) ttyd_asset="ttyd.x86_64" ;; \
        arm64) ttyd_asset="ttyd.aarch64" ;; \
        *) echo "Unsupported architecture: $arch" && exit 1 ;; \
    esac \
    && curl -L -o /usr/local/bin/ttyd "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/${ttyd_asset}" \
    && curl -L -o /usr/local/bin/winetricks "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" \
    && chmod +x /usr/local/bin/ttyd /usr/local/bin/winetricks \
    && ln -s /usr/lib/wine/wine64 /usr/bin/wine64 \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen

# Clone noVNC from GitHub (Debian packages are incompatible - sendString error)
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/noVNC

RUN mkdir -p /opt/wbridge5 \
    && curl -L "${WB5_URL}" -o /opt/wbridge5/Wbridge5_setup.exe

RUN mkdir -p "${WINEPREFIX}" \
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" wineboot --init \
    && sleep 5 \
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" winetricks -q corefonts \
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" winetricks -q ie8 \
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" winetricks -q gdiplus tahoma fontsmooth=rgb \
    # Additional fonts including Symbol for card suits
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" winetricks -q allfonts \
    # Visual C++ runtimes
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" winetricks -q vcrun2015 \
    # Windows components for proper UI rendering
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" winetricks -q windowscodecs riched20 riched30 oleaut32 msxml6 \
    # Microsoft Sans Serif TrueType (handles SYMBOL_CHARSET properly)
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" winetricks -q micross \
    # Fix for icon transparency issues
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" winetricks comctl32=builtin \
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" wine64 "/opt/wbridge5/Wbridge5_setup.exe" /SP- /VERYSILENT /SUPPRESSMSGBOXES /NOCANCEL /DIR="${WB5_INSTALL_DIR}" \
    && rm /opt/wbridge5/Wbridge5_setup.exe

# Copy system Wine fonts and download Segoe UI Symbol for suit symbols
RUN cp /usr/share/wine/fonts/*.ttf "${WINEPREFIX}/drive_c/windows/Fonts/" 2>/dev/null || true \
    # Download Segoe UI Symbol font (needed for card suit symbols in bidding panel)
    && curl -L -o "${WINEPREFIX}/drive_c/windows/Fonts/seguisym.ttf" \
       "https://github.com/mrbvrz/segoe-ui-linux/raw/master/font/seguisym.ttf" \
    # Also get full Segoe UI family for better rendering
    && curl -L -o "${WINEPREFIX}/drive_c/windows/Fonts/segoeui.ttf" \
       "https://github.com/mrbvrz/segoe-ui-linux/raw/master/font/segoeui.ttf" \
    && curl -L -o "${WINEPREFIX}/drive_c/windows/Fonts/segoeuib.ttf" \
       "https://github.com/mrbvrz/segoe-ui-linux/raw/master/font/segoeuib.ttf" \
    && curl -L -o "${WINEPREFIX}/drive_c/windows/Fonts/segoeuil.ttf" \
       "https://github.com/mrbvrz/segoe-ui-linux/raw/master/font/segoeuil.ttf" \
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" winetricks -q win10 2>/dev/null || true

# Regenerate symbol.ttf with proper TrueType Symbol encoding (required for Wine)
# See: https://forum.winehq.org/viewtopic.php?t=1826
RUN cd "${WINEPREFIX}/drive_c/windows/Fonts" \
    && if [ -f symbol.ttf ]; then \
         fontforge -lang=ff -c 'Open("symbol.ttf"); Generate("symbol_new.sym.ttf")' 2>/dev/null || true; \
         if [ -f symbol_new.sym.ttf ]; then mv symbol_new.sym.ttf symbol.ttf; fi; \
       fi

# Install fonts with Unicode card suit symbols (U+2660-2667) into Wine
RUN apt-get update && apt-get install -y --no-install-recommends fonts-dejavu-core \
    && cp /usr/share/fonts/truetype/dejavu/*.ttf "${WINEPREFIX}/drive_c/windows/Fonts/" \
    && rm -rf /var/lib/apt/lists/*

# Fix Font Linking - Wine doesn't automatically fall back to Symbol font like Windows does
# This tells Wine: when Tahoma/Arial can't render a glyph (like ♠), check symbol.ttf
RUN echo 'REGEDIT4' > /tmp/fontlink.reg \
    && echo '' >> /tmp/fontlink.reg \
    && echo '[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink]' >> /tmp/fontlink.reg \
    && echo '"Segoe UI"="symbol.ttf"' >> /tmp/fontlink.reg \
    && echo '"Tahoma"="symbol.ttf"' >> /tmp/fontlink.reg \
    && echo '"Microsoft Sans Serif"="symbol.ttf"' >> /tmp/fontlink.reg \
    && echo '"Arial"="symbol.ttf"' >> /tmp/fontlink.reg \
    && echo '"Lucida Sans Unicode"="symbol.ttf"' >> /tmp/fontlink.reg \
    && echo '"MS Sans Serif"="symbol.ttf"' >> /tmp/fontlink.reg \
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" wine regedit /tmp/fontlink.reg \
    && rm /tmp/fontlink.reg

# Font substitutions - map legacy fonts to Microsoft Sans Serif (TrueType with SYMBOL_CHARSET support)
RUN echo 'REGEDIT4' > /tmp/fontsub.reg \
    && echo '' >> /tmp/fontsub.reg \
    && echo '[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes]' >> /tmp/fontsub.reg \
    && echo '"MS Sans Serif"="Microsoft Sans Serif"' >> /tmp/fontsub.reg \
    && echo '"MS Shell Dlg"="Microsoft Sans Serif"' >> /tmp/fontsub.reg \
    && echo '"MS Shell Dlg 2"="Microsoft Sans Serif"' >> /tmp/fontsub.reg \
    && echo '"Helv"="Microsoft Sans Serif"' >> /tmp/fontsub.reg \
    && xvfb-run -a env WINEPREFIX="${WINEPREFIX}" wine regedit /tmp/fontsub.reg \
    && rm /tmp/fontsub.reg

WORKDIR /app

COPY start.sh /app/start.sh
COPY nginx.conf /etc/nginx/nginx.conf
COPY fluxbox.menu /root/.fluxbox/menu
COPY wbridge5.desktop /usr/share/applications/wbridge5.desktop

RUN chmod +x /app/start.sh

EXPOSE 8080

ENTRYPOINT ["/app/start.sh"]
