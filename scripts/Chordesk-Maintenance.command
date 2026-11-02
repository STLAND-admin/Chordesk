#!/bin/zsh
# Chordesk project maintenance tool. No Xcode, Python, sudo, TCC database edits,
# password extraction, global permission reset, or Gatekeeper changes.
# Default actions require an interactive terminal and an exact confirmation.
set -euo pipefail

readonly chordesk_bundle_id='dev.iphoneduo.workbench'
readonly chordesk_tailnet_service='dev.chordesk.embedded-tailnet'
readonly chordesk_pairing_service='dev.iphoneduo.remote-pairing'
readonly chordesk_home="$HOME"
chordesk_apps=()
chordesk_failed=0
chordesk_trash=''

say() { print -r -- "$*"; }
fail() { say "未执行／未完成：$*" >&2; return 1; }
find_apps() {
    chordesk_apps=()
    local candidate identifier
    for candidate in /Applications/Chordesk.app /Applications/DuoWorkbench.app \
        "$chordesk_home/Applications/Chordesk.app" "$chordesk_home/Applications/DuoWorkbench.app"; do
        [[ -e "$candidate" ]] || continue
        identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist" 2>/dev/null) || continue
        if [[ "$identifier" == "$chordesk_bundle_id" ]]; then chordesk_apps+=("$candidate"); fi
    done
}
plan() {
    find_apps
    say 'Chordesk Maintenance / 维护与卸载'
    say '应用身份：dev.iphoneduo.workbench（仅此 App）'
    say '系统授权：tccutil reset All dev.iphoneduo.workbench'
    say '公网登录：dev.chordesk.embedded-tailnet / node-state-v1'
    say '完整清理另含：dev.iphoneduo.remote-pairing 的已知 Chordesk 配对记录'
    say "本地数据：$chordesk_home/Library/Application Support/Chordesk"
    say "本地偏好：$chordesk_home/Library/Preferences/dev.iphoneduo.workbench.plist"
    say '标准安装位置中匹配此身份的 App：'
    if (( ${#chordesk_apps} )); then printf '  %s\n' "${chordesk_apps[@]}"; else say '  未找到（应用可能已删除或放在其他位置）'; fi
    say '应用／文件移入废纸篓，可恢复。删除钥匙串记录及重置授权需要重新登录／配对／授权。'
    say '不读取密码、私钥、桌面内容；不更改其他 App、系统安全设置或整个登录钥匙串。'
}
stopped() {
    if /usr/bin/pgrep -f '/(Chordesk|DuoWorkbench)\.app/Contents/MacOS/DuoWorkbench([[:space:]]|$)' >/dev/null; then
        fail '请先从 Chordesk 菜单正常退出，恢复原显示模式后再运行工具。不会强制结束应用。'; return 1
    fi
}
confirm() {
    local answer
    say "$1"
    printf '输入 %s 确认（其他输入取消）：' "$2"
    IFS= read -r answer
    [[ "$answer" == "$2" ]] || { say '已取消，无修改。'; return 1; }
}
reset_permissions() {
    if /usr/bin/tccutil reset All "$chordesk_bundle_id"; then
        say '已重置本 App 的系统授权决定；重新打开后逐项允许。系统设置可能仍显示应用条目。'
    else
        fail '系统拒绝重置。请在隐私设置中手动移除旧 Chordesk 条目；其他 App 授权未改。'
        return 1
    fi
}
delete_item() {
    local result=0
    /usr/bin/security delete-generic-password -s "$1" -a "$2" >/dev/null 2>&1 || result=$?
    # security returns 44 for errSecItemNotFound; absence is already clean.
    if (( result != 0 && result != 44 )); then
        say "钥匙串清理未完成：$1 / $2（代码 $result）" >&2
        say '请在“钥匙串访问”搜索此服务，仅删除所列条目；不要重置整个登录钥匙串。' >&2
        return 1
    fi
}
reset_tailnet() {
    delete_item "$chordesk_tailnet_service" node-state-v1
    say '已清除本机 Chordesk 公网登录。重新登录后可能要重新扫码；旧节点仍可在 Tailscale 管理页移除。'
}
make_trash() {
    [[ ! -L "$chordesk_home/.Trash" ]] || { fail '用户废纸篓是符号链接，请手动检查。'; return 1; }
    if [[ ! -e "$chordesk_home/.Trash" ]]; then /bin/mkdir -m 700 "$chordesk_home/.Trash" || return 1; fi
    [[ -d "$chordesk_home/.Trash" ]] || { fail '用户废纸篓不可用。'; return 1; }
    chordesk_trash=$(/usr/bin/mktemp -d "$chordesk_home/.Trash/Chordesk-removed.XXXXXX")
}
trash_apps() {
    local candidate n=0
    find_apps
    for candidate in "${chordesk_apps[@]}"; do
        (( n += 1 ))
        # mv moves a compatibility symlink itself, never its target.
        /bin/mv "$candidate" "$chordesk_trash/app-$n-$(/usr/bin/basename "$candidate")" || chordesk_failed=1
    done
}
full_remove() {
    local support="$chordesk_home/Library/Application Support/Chordesk"
    local preferences="$chordesk_home/Library/Preferences/$chordesk_bundle_id.plist"
    local cache="$chordesk_home/Library/Caches/$chordesk_bundle_id"
    local saved="$chordesk_home/Library/Saved Application State/$chordesk_bundle_id.savedState"
    local target account has_preferences=0
    # Refuse redirected data paths instead of following links outside Chordesk.
    for target in "$support" "$preferences" "$cache" "$saved"; do
        [[ ! -L "$target" ]] || { fail 'Chordesk 数据路径是符号链接，请手动检查；未开始完整清理。'; return 1; }
    done
    make_trash
    if /usr/bin/defaults export "$chordesk_bundle_id" "$chordesk_trash/preferences-backup.plist" >/dev/null 2>&1; then
        has_preferences=1
    elif [[ -e "$preferences" ]]; then
        fail '偏好备份失败，未开始完整清理。'; return 1
    fi
    # Stop on a security reset failure; never pretend a partial cleanup is done.
    reset_permissions || return 1
    reset_tailnet || return 1
    for account in host-pairing-v2-signed host-pairing-v1 remembered-macs-v2 remembered-mac-v1; do
        delete_item "$chordesk_pairing_service" "$account" || return 1
    done
    if (( has_preferences )); then /usr/bin/defaults delete "$chordesk_bundle_id" >/dev/null || return 1; fi
    if [[ -e "$support" ]]; then /bin/mv "$support" "$chordesk_trash/Chordesk-data" || return 1; fi
    if [[ -e "$cache" ]]; then /bin/mv "$cache" "$chordesk_trash/Chordesk-cache" || return 1; fi
    if [[ -e "$saved" ]]; then /bin/mv "$saved" "$chordesk_trash/Chordesk-window-state" || return 1; fi
    trash_apps
    (( chordesk_failed == 0 )) || { fail '部分 App 未能移入废纸篓，请用 Finder 手动处理。'; return 1; }
    say "清理完成。可恢复的 App／数据备份：$chordesk_trash"
    say '重装后需重新授权、配对和登录；Tailscale 旧节点请到自己的管理页移除。'
}

if [[ "${1:-}" == '--plan' && $# == 1 ]]; then plan; exit 0; fi
if (( $# != 0 )); then say '用法：Chordesk-Maintenance.command [--plan]'; exit 2; fi
[[ -t 0 && -t 1 ]] || { say '修改操作必须在交互式终端中手动确认。--plan 仅检查。'; exit 2; }
[[ "$(/usr/bin/id -u)" != 0 && -O "$chordesk_home" ]] || { fail '请用本人的普通登录账户运行，不使用 sudo。'; exit 1; }
plan
say ''
say '1 仅检查（不修改）'
say '2 重置 Chordesk 系统授权（配对／登录保留）'
say '3 清除本机公网登录，重新绑定（系统权限／局域网配对保留）'
say '4 卸载 App，保留数据和授权（用于暂时移除）'
say '5 彻底卸载：清理本 App 授权、登录、配对与偏好，App／数据移入废纸篓'
say 'q 退出'
printf '选择：'
IFS= read -r chordesk_choice
case "$chordesk_choice" in
    1|q|'') exit 0 ;;
    2) confirm '下次打开将重新申请本 App 的系统权限。' RESET || exit 0; stopped; reset_permissions ;;
    3) confirm '仅清除本机 Chordesk 公网身份；需重新登录，可能要重新扫码。' REBIND || exit 0; stopped; reset_tailnet ;;
    4) confirm '仅把匹配身份的 App 移入废纸篓；升级通常直接替换即可。' UNINSTALL || exit 0; stopped; make_trash; trash_apps
       (( chordesk_failed == 0 )) || exit 1; say "App 已移入：$chordesk_trash" ;;
    5) confirm '本 App 的授权／登录／配对将清除；先确认已恢复原显示模式。' REMOVE || exit 0; stopped; full_remove ;;
    *) say '未知选择，无修改。'; exit 2 ;;
esac
