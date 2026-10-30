#!/usr/bin/env bash
# =============================================================================
#  mac-ajuste.sh — Alterna o visual entre CLARO e ESCURO (após o instalador)
#
#   light → tema claro, barra superior clara, maçã preta, wallpaper 4K claro
#   dark  → tema escuro, barra superior preta, maçã branca, wallpaper 4K escuro
#
#  Uso:  ./mac-ajuste.sh light     ou     ./mac-ajuste.sh dark     (sem sudo)
#  Dica: o papel de parede troca sozinho, porque o GNOME guarda um para cada modo.
# =============================================================================
set -uo pipefail
MODO="${1:-light}"
case "$MODO" in
  light) GTK="WhiteSur-Light"; ICONES="WhiteSur-light" ;;
  dark)  GTK="WhiteSur-Dark";  ICONES="WhiteSur-dark"  ;;
  *) echo "Uso: $0 light|dark"; exit 1 ;;
esac
[[ $EUID -eq 0 ]] && { echo "Não use sudo."; exit 1; }
[[ -d ~/.themes/$GTK || -d /usr/share/themes/$GTK ]] || {
  echo "Tema $GTK não encontrado. Rode primeiro o instalador do repositório."; exit 1; }

echo -e "\e[32m==>\e[0m Aplicando visual $MODO"
gsettings set org.gnome.desktop.interface gtk-theme    "$GTK"
gsettings set org.gnome.desktop.interface icon-theme   "$ICONES"
gsettings set org.gnome.desktop.interface color-scheme "prefer-$MODO"
gsettings set org.gnome.shell.extensions.user-theme name "$GTK" 2>/dev/null || \
  dconf write /org/gnome/shell/extensions/user-theme/name "'$GTK'"
echo -e "\e[32m==>\e[0m Pronto! Barra, maçã e papel de parede no modo $MODO."
echo "   Se algum app não mudar, feche e abra de novo (ou faça logout/login)."
