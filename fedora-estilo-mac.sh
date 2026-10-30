#!/usr/bin/env bash
# =============================================================================
#  fedora-estilo-mac.sh — Deixa o Fedora (GNOME) com visual de macOS
#  Tema WhiteSur (GTK + GNOME Shell + ícones + cursor), maçã na barra
#  superior, dock no estilo macOS com transparência, botões à esquerda,
#  fonte Inter e papéis de parede 4K que trocam sozinhos no claro/escuro.
#
#  Uso:   chmod +x fedora-estilo-mac.sh
#         ./fedora-estilo-mac.sh           (claro: barra clara + maçã preta)
#         ./fedora-estilo-mac.sh dark      (escuro: barra preta + maçã branca)
#  Rode como seu usuário normal (NÃO use sudo), dentro da sessão GNOME.
#  Reverter: dconf load /org/gnome/ < ~/mac-look-backup/gnome.dconf
# =============================================================================
set -uo pipefail

# ---------------------------- CONFIGURAÇÃO -----------------------------------
MODO="${1:-light}"            # light (padrão) ou dark
PAPEL_LIGHT="Sonoma-light"    # Sonoma | Ventura | Monterey | WhiteSur  + -light
PAPEL_DARK="Sonoma-dark"      # Sonoma | Ventura | Monterey | WhiteSur  + -dark
TAMANHO_ICONES_DOCK=48
# -----------------------------------------------------------------------------

VERDE='\e[32m'; AMARELO='\e[33m'; VERMELHO='\e[31m'; NC='\e[0m'
info() { echo -e "${VERDE}==>${NC} $*"; }
warn() { echo -e "${AMARELO}[aviso]${NC} $*"; }
erro() { echo -e "${VERMELHO}[erro]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] && erro "Não rode com sudo. Execute como seu usuário: ./fedora-estilo-mac.sh"
command -v dnf >/dev/null || erro "Este script é para Fedora (dnf)."
[[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] || \
  warn "Ambiente '${XDG_CURRENT_DESKTOP:-desconhecido}' detectado. O script é feito para o GNOME."

case "$MODO" in
  light) GTK="WhiteSur-Light"; ICONES="WhiteSur-light" ;;
  dark)  GTK="WhiteSur-Dark";  ICONES="WhiteSur-dark"  ;;
  *) erro "Uso: $0 [light|dark]" ;;
esac
CURSOR="WhiteSur-cursors"
TMP="$(mktemp -d)"

sudo -v || erro "Precisa da senha de administrador."
( while true; do sudo -n true; sleep 50; done ) 2>/dev/null &
SUDO_KEEP=$!
trap 'kill $SUDO_KEEP 2>/dev/null; rm -rf "$TMP"' EXIT

# ----------------------------- 0. BACKUP -------------------------------------
info "Fazendo backup das configurações atuais em ~/mac-look-backup"
mkdir -p ~/mac-look-backup
dconf dump /org/gnome/ > ~/mac-look-backup/gnome.dconf 2>/dev/null || true

# ----------------------------- 1. PACOTES ------------------------------------
info "Atualizando e instalando dependências"
sudo dnf install -y git curl unzip dconf sassc glib2-devel libxml2 python3 \
  gnome-tweaks gnome-extensions-app gnome-shell-extension-user-theme \
  || erro "Falha ao instalar dependências."
sudo dnf install -y gnome-shell-extension-dash-to-dock || warn "Dash to Dock via dnf indisponível; tentando pelo site."
sudo dnf install -y rsms-inter-fonts || warn "Fonte Inter indisponível; mantendo a fonte atual."
sudo dnf install -y gnome-shell-extension-blur-my-shell >/dev/null 2>&1 || true

GS_VER="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -n1)"

# Ativa uma extensão (agora, se possível; senão no próximo login)
ativar_ext() {
  local uuid="$1"
  gsettings set org.gnome.shell disable-user-extensions false
  gnome-extensions enable "$uuid" 2>/dev/null && return 0
  python3 - "$uuid" <<'PY'
import ast, subprocess, sys
uuid = sys.argv[1]
cur = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"],
                     capture_output=True, text=True).stdout.strip().replace("@as ", "")
lst = ast.literal_eval(cur) if cur else []
if uuid not in lst:
    lst.append(uuid)
    subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(lst)])
PY
}

# Instala uma extensão direto do extensions.gnome.org (para a versão do GNOME)
instalar_ext() {
  local uuid="$1" url
  [[ -d ~/.local/share/gnome-shell/extensions/$uuid || -d /usr/share/gnome-shell/extensions/$uuid ]] \
    && { ativar_ext "$uuid"; return 0; }
  url="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${GS_VER}" \
        | python3 -c 'import sys,json; print(json.load(sys.stdin).get("download_url",""))' 2>/dev/null)"
  if [[ -n "$url" ]] && curl -fsSL "https://extensions.gnome.org${url}" -o "$TMP/$uuid.zip"; then
    gnome-extensions install --force "$TMP/$uuid.zip" && ativar_ext "$uuid"
  else
    warn "Não consegui instalar a extensão $uuid"
    return 1
  fi
}

# ----------------------------- 2. TEMAS --------------------------------------
clonar() { git clone --depth=1 "https://github.com/vinceliuice/$1.git" "$TMP/$1" >/dev/null 2>&1 \
           || { warn "Não consegui baixar $1"; return 1; }; }

info "Instalando tema WhiteSur (GTK, libadwaita e GNOME Shell com a maçã)"
if clonar WhiteSur-gtk-theme; then
  # --black: barra clara com texto e maçã pretos no modo light
  # --shell -i apple: troca o botão Atividades pela maçã
  ( cd "$TMP/WhiteSur-gtk-theme" && yes | ./install.sh -c light -c dark -l --black --shell -i apple ) \
    || warn "Instalação do tema retornou erro (verifique ~/.themes)."
fi

info "Instalando ícones WhiteSur"
clonar WhiteSur-icon-theme && ( cd "$TMP/WhiteSur-icon-theme" && ./install.sh ) \
  || warn "Ícones não instalados."

info "Instalando cursor WhiteSur"
clonar WhiteSur-cursors && ( cd "$TMP/WhiteSur-cursors" && ./install.sh ) \
  || warn "Cursor não instalado."

# ----------------------------- 3. EXTENSÕES ----------------------------------
info "Ativando extensões (temas da barra, dock e transparência)"
ativar_ext user-theme@gnome-shell-extensions.gcampax.github.com
if rpm -q gnome-shell-extension-dash-to-dock >/dev/null 2>&1; then
  ativar_ext dash-to-dock@micxgx.gmail.com
else
  instalar_ext dash-to-dock@micxgx.gmail.com || true
fi
instalar_ext blur-my-shell@aunetx || true

# ----------------------------- 4. APARÊNCIA ----------------------------------
info "Aplicando tema $MODO, ícones, cursor e fontes"
gsettings set org.gnome.desktop.interface gtk-theme    "$GTK"
gsettings set org.gnome.desktop.interface icon-theme   "$ICONES"
gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR"
gsettings set org.gnome.desktop.interface color-scheme "prefer-$MODO"
gsettings set org.gnome.shell.extensions.user-theme name "$GTK" 2>/dev/null || \
  dconf write /org/gnome/shell/extensions/user-theme/name "'$GTK'"

# Botões da janela à esquerda (fechar, minimizar, maximizar)
gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'

if fc-list | grep -qi "Inter"; then
  gsettings set org.gnome.desktop.interface font-name          'Inter 11'
  gsettings set org.gnome.desktop.interface document-font-name 'Inter 11'
  gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Inter Bold 11'
fi

# Apps Flatpak também seguem o tema (libadwaita / GTK4)
if command -v flatpak >/dev/null; then
  flatpak override --user --filesystem=xdg-config/gtk-4.0:ro --filesystem=xdg-config/gtk-3.0:ro 2>/dev/null || true
fi

# ----------------------------- 5. PAPÉIS DE PAREDE ---------------------------
info "Baixando papéis de parede 4K (Sonoma, Ventura, Monterey, Big Sur)"
WDIR="$(xdg-user-dir PICTURES 2>/dev/null || echo ~/Pictures)/Wallpapers-Mac"
mkdir -p "$WDIR"
if clonar WhiteSur-wallpapers; then
  cp -f "$TMP/WhiteSur-wallpapers/4k/"*.jpg "$WDIR"/ 2>/dev/null
fi
# O GNOME guarda um papel para o claro e outro para o escuro: troca sozinho
[[ -f "$WDIR/$PAPEL_LIGHT.jpg" ]] && \
  gsettings set org.gnome.desktop.background picture-uri      "file://$WDIR/$PAPEL_LIGHT.jpg"
[[ -f "$WDIR/$PAPEL_DARK.jpg" ]] && \
  gsettings set org.gnome.desktop.background picture-uri-dark "file://$WDIR/$PAPEL_DARK.jpg"
gsettings set org.gnome.desktop.background picture-options 'zoom'
[[ -f "$WDIR/$PAPEL_LIGHT.jpg" ]] && \
  gsettings set org.gnome.desktop.screensaver picture-uri "file://$WDIR/$PAPEL_LIGHT.jpg" 2>/dev/null

# ----------------------------- 6. DOCK ---------------------------------------
info "Configurando o dock no estilo macOS"
D="org.gnome.shell.extensions.dash-to-dock"
GS=(gsettings)
if ! gsettings list-keys "$D" >/dev/null 2>&1; then
  SD=~/.local/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com/schemas
  [[ -d "$SD" ]] && GS=(gsettings --schemadir "$SD")
fi
if "${GS[@]}" list-keys "$D" >/dev/null 2>&1; then
  "${GS[@]}" set $D dock-position        'BOTTOM'
  "${GS[@]}" set $D extend-height        false
  "${GS[@]}" set $D dock-fixed           false
  "${GS[@]}" set $D autohide             true
  "${GS[@]}" set $D intellihide          true
  "${GS[@]}" set $D dash-max-icon-size   "$TAMANHO_ICONES_DOCK"
  "${GS[@]}" set $D transparency-mode    'FIXED'
  "${GS[@]}" set $D background-opacity   0.35
  "${GS[@]}" set $D running-indicator-style 'DOTS'
  "${GS[@]}" set $D click-action         'minimize-or-previews'
  "${GS[@]}" set $D show-trash           false 2>/dev/null
  "${GS[@]}" set $D show-mounts          false 2>/dev/null
  "${GS[@]}" set $D show-apps-at-top     false
  "${GS[@]}" set $D custom-theme-shrink  true
else
  warn "Configurações do dock ainda não disponíveis; rode o script de novo após o login."
fi

# Apps fixados no dock (só os que existem no sistema)
python3 - <<'PY'
import os, subprocess
dirs = ["/usr/share/applications", "/var/lib/snapd/desktop/applications",
        "/var/lib/flatpak/exports/share/applications",
        os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
        os.path.expanduser("~/.local/share/applications")]
want = [["org.gnome.Nautilus.desktop"],
        ["google-chrome.desktop", "com.google.Chrome.desktop"],
        ["firefox_firefox.desktop", "firefox.desktop", "org.mozilla.firefox.desktop"],
        ["org.gnome.Ptyxis.desktop", "org.gnome.Terminal.desktop", "org.gnome.Console.desktop"],
        ["org.gnome.TextEditor.desktop", "org.gnome.gedit.desktop"],
        ["org.gnome.Calculator.desktop"],
        ["code.desktop", "code_code.desktop", "com.visualstudio.code.desktop"],
        ["snap-store_snap-store.desktop", "org.gnome.Software.desktop"],
        ["org.gnome.Settings.desktop", "gnome-control-center.desktop"]]
fav = []
for opts in want:
    for o in opts:
        if any(os.path.exists(os.path.join(d, o)) for d in dirs):
            fav.append(o); break
if fav:
    subprocess.run(["gsettings", "set", "org.gnome.shell", "favorite-apps", str(fav)])
PY

# ----------------------------- 7. FINALIZA -----------------------------------
echo
info "Pronto! Faça LOGOUT e LOGIN para ver a maçã, o dock e a transparência."
echo "   Buscar apps estilo Spotlight: tecla Super (Windows) e digite."
echo "   Alternar claro/escuro depois: ./mac-ajuste.sh light | dark"
echo "   Backup das configs antigas: ~/mac-look-backup"
echo "   Para voltar ao visual anterior:"
echo "     dconf load /org/gnome/ < ~/mac-look-backup/gnome.dconf"
