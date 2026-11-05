#!/bin/sh
# Copyright (c) Tailscale Inc & contributors
# SPDX-License-Identifier: BSD-3-Clause
#
# OpenWrt (x86_64) 更新 Tailscale：从 GitHub Release 固定地址重新下载
# tailscale / tailscaled 到 /usr/sbin/ 并授予可执行权限（仅替换二进制，
# 不修改 procd init 脚本与开机自启，逻辑与 scripts/install-openwrt.sh 同构）。
#
# 用法:
#   wget -O- https://raw.githubusercontent.com/agogo233/tailscale/main/scripts/update-openwrt.sh | sh
# 环境变量:
#   REPO: GitHub 仓库（默认 agogo233/tailscale）
# 更新后不会自动重启服务，请手动执行:
#   /etc/init.d/tailscaled restart

set -eu

# 所有逻辑包在 main 函数中、底部调用，防止下载截断时执行半截脚本
# （与 scripts/installer.sh 的防御设计一致）。
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
        echo "已更新 /usr/sbin/${name} (0755)"
    }

    install_bin tailscaled
    install_bin tailscale

    # --- 提示手动重启（Linux 原子替换不打断运行中的守护进程，需重启生效） ---

    echo ""
    echo "二进制更新完成，但旧进程仍在运行。请手动重启服务:"
    echo "  /etc/init.d/tailscaled restart"
    echo "验证版本:"
    echo "  tailscale version"
    echo "如需回滚可重新执行一键安装:"
    echo "  wget -O- https://raw.githubusercontent.com/${REPO}/main/scripts/install-openwrt.sh | sh"
}

main