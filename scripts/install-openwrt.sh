#!/bin/sh
# Copyright (c) Tailscale Inc & contributors
# SPDX-License-Identifier: BSD-3-Clause
#
# OpenWrt (x86_64) 一键安装 Tailscale：从 GitHub Release 固定地址下载
# tailscale / tailscaled 到 /usr/sbin/ 并授予可执行权限，同时配置
# procd init 脚本与开机自启。
#
# 用法:
#   wget -O- https://raw.githubusercontent.com/agogo233/tailscale/main/scripts/install-openwrt.sh | sh
# 环境变量:
#   REPO: GitHub 仓库（默认 agogo233/tailscale）

set -eu

# 所有逻辑包在 main 函数中、底部调用，防止下载截断时执行半截脚本
# （与上游 scripts/installer.sh 的防御设计一致）。
main() {
    REPO="${REPO:-agogo233/tailscale}"
    BASE_URL="https://github.com/${REPO}/releases/download/latest"

    die() {
        echo "ERROR: $*" >&2
        exit 1
    }

    cleanup() {
        rm -f /usr/sbin/.tailscale.new /usr/sbin/.tailscaled.new
    }
    trap cleanup EXIT

    # --- 预检 ---

    [ "$(id -u)" -eq 0 ] || die "请以 root 运行（当前用户非 root）"

    [ "$(uname -m)" = "x86_64" ] || die "本脚本仅支持 x86_64（当前架构 $(uname -m)）"

    [ -f /etc/openwrt_version ] || die "未检测到 OpenWrt（缺少 /etc/openwrt_version），本脚本仅支持 OpenWrt"

    command -v wget >/dev/null 2>&1 || die "缺少 wget，请先: opkg install wget"

    CA_FOUND=0
    for f in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem /etc/pki/tls/certs/ca-bundle.crt; do
        [ -s "$f" ] && CA_FOUND=1 && break
    done
    [ "$CA_FOUND" -eq 1 ] || die "缺少 HTTPS CA 证书，请先: opkg install ca-bundle ca-certificates"

    # --- 下载并原子替换二进制 ---

    # 检查文件为合法 ELF 二进制（防止错误页/HTML 被当作二进制安装）
    # 使用 BusyBox 默认自带的 hexdump（默认固件无 od）
    check_elf() {
        magic=$(hexdump -n 4 -e '4/1 "%02x"' "$1" 2>/dev/null | tr -d '\n')
        [ "$magic" = "7f454c46" ] || die "$1 不是有效的 ELF 二进制（下载可能损坏）"
    }

    # install_bin <名称>: 下载到隐藏临时文件，校验后原子替换
    install_bin() {
        name="$1"
        tmp="/usr/sbin/.${name}.new"
        url="${BASE_URL}/${name}"
        echo "下载 ${url}"
        wget -q -O "$tmp" "$url" || die "下载失败: ${url}"
        [ -s "$tmp" ] || die "下载内容为空: ${url}"
        check_elf "$tmp"
        chmod 0755 "$tmp"
        mv -f "$tmp" "/usr/sbin/${name}"
        echo "已安装 /usr/sbin/${name} (0755)"
    }

    install_bin tailscale
    install_bin tailscaled

    # --- procd init 脚本与开机自启 ---

    mkdir -p /etc/tailscale

    cat > /etc/init.d/tailscaled <<'INIT'
#!/bin/sh /etc/rc.common
START=95
STOP=01
USE_PROCD=1
start_service() {
    procd_open_instance
    procd_set_param command /usr/sbin/tailscaled --state /etc/tailscale/tailscaled.state
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
stop_service() {
    /usr/sbin/tailscale down
}
INIT

    chmod +x /etc/init.d/tailscaled
    /etc/init.d/tailscaled enable

    echo ""
    echo "安装完成！启动服务:"
    echo "  /etc/init.d/tailscaled start"
    echo "登录 Tailscale:"
    echo "  tailscale up"
}

main
