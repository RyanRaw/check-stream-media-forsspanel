#!/usr/bin/env bash
# ==============================================================================
# install.sh —— check-stream-media-forsspanel (csm.sh) 一键安装 / 更新脚本
#
# 仓库: https://github.com/RyanRaw/check-stream-media-forsspanel
#
# 功能:
#   1. 检测系统并安装依赖 (curl / coreutils / cron / python)
#   2. 下载(或使用本地) csm.sh 到安装目录
#   3. 写入面板配置 (面板地址 / mu key / 节点 ID)
#   4. 添加定时检测任务
#   5. 立即执行一次检测并上报结果
#
# 用法:
#   bash install.sh
#   bash install.sh -a https://demo.sspanel.org -k <mu_key> -n <node_id> -i 1
# ==============================================================================

set -u

# Alpine 默认只有 ash, 若被 sh 调用则自动切换到 bash 执行
if [ -z "${BASH_VERSION:-}" ]; then
    if [ -f "$0" ] && command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    echo -e "\033[31m本脚本需要 bash, 请先安装 (Alpine: apk add bash)\033[0m"
    exit 1
fi

Font_Red="\033[31m"
Font_Green="\033[32m"
Font_Yellow="\033[33m"
Font_SkyBlue="\033[36m"
Font_Suffix="\033[0m"

REPO="RyanRaw/check-stream-media-forsspanel"
BRANCH="main"
CSM_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/csm.sh"

CSM_DIR="${CSM_DIR:-${HOME}}"
CSM_SCRIPT="${CSM_DIR}/csm.sh"
CSM_CONFIG="${CSM_DIR}/.csm.config"

PANEL_ADDRESS=""
MU_KEY=""
NODE_ID=""
INTERVAL=""

info() { echo -e "${Font_Green}${1}${Font_Suffix}"; }
warn() { echo -e "${Font_Yellow}${1}${Font_Suffix}"; }
error() { echo -e "${Font_Red}${1}${Font_Suffix}" >&2; }
input() { echo -e "${Font_SkyBlue}[input]${Font_Suffix} ${1}"; }

usage() {
    cat <<EOF
用法: bash install.sh [选项]

  -a <面板地址>    例如: https://demo.sspanel.org
  -k <mu key>      节点通讯密钥
  -n <节点 ID>     面板中的节点 ID
  -i <间隔小时>    定时检测间隔, 1-24, 默认 1
  -d <安装目录>    csm.sh 安装位置, 默认 \$HOME
  -h               显示本帮助

不带参数运行时会交互式询问所需信息。
EOF
}

while getopts ":a:k:n:i:d:h" opt; do
    case "${opt}" in
        a) PANEL_ADDRESS="${OPTARG%/}" ;;
        k) MU_KEY="${OPTARG}" ;;
        n) NODE_ID="${OPTARG}" ;;
        i) INTERVAL="${OPTARG}" ;;
        d) CSM_DIR="${OPTARG}" ;;
        h) usage; exit 0 ;;
        *) error "未知参数: -${OPTARG}"; usage; exit 1 ;;
    esac
done

CSM_SCRIPT="${CSM_DIR}/csm.sh"
CSM_CONFIG="${CSM_DIR}/.csm.config"

getPackageManager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt-get"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    elif command -v brew >/dev/null 2>&1; then
        echo "brew"
    else
        echo ""
    fi
}

installPackages() {
    local pm="$1"
    shift
    case "${pm}" in
        apt-get) apt-get update -qq >/dev/null 2>&1; apt-get install -y "$@" >/dev/null 2>&1 ;;
        dnf | yum) "${pm}" install -y "$@" >/dev/null 2>&1 ;;
        apk) apk add --no-cache "$@" >/dev/null 2>&1 ;;
        brew) brew install "$@" >/dev/null 2>&1 ;;
    esac
}

# Alpine: busybox 环境, 一次性装齐缺失组件 (默认没有 bash / python / curl)
installDependenciesAlpine() {
    local pkgs=""

    command -v bash >/dev/null 2>&1 || pkgs="${pkgs} bash"
    command -v curl >/dev/null 2>&1 || pkgs="${pkgs} curl"
    command -v base64 >/dev/null 2>&1 || pkgs="${pkgs} coreutils"
    command -v dig >/dev/null 2>&1 || pkgs="${pkgs} bind-tools"
    command -v crontab >/dev/null 2>&1 || pkgs="${pkgs} busybox"
    if ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
        pkgs="${pkgs} python3"
    fi

    if [ -z "${pkgs}" ]; then
        info "依赖已齐全 (Alpine), 跳过安装"
        return
    fi

    info "安装依赖 (Alpine):${pkgs}"
    if ! apk add --no-cache ${pkgs} >/dev/null 2>&1; then
        warn "部分依赖安装失败, 请检查 apk 源后重试"
    fi
}

installDependencies() {
    local pm
    pm="$(getPackageManager)"

    if [ -z "${pm}" ]; then
        warn "未识别到包管理器, 请自行确认 curl / cron / python / bash 已安装"
        return
    fi

    if [ "${pm}" = "apk" ]; then
        installDependenciesAlpine
        return
    fi

    if ! command -v curl >/dev/null 2>&1; then
        info "安装 curl ..."
        installPackages "${pm}" curl
    fi

    if ! command -v bash >/dev/null 2>&1; then
        info "安装 bash ..."
        installPackages "${pm}" bash
    fi

    if ! command -v base64 >/dev/null 2>&1; then
        info "安装 coreutils ..."
        installPackages "${pm}" coreutils
    fi

    if ! command -v crontab >/dev/null 2>&1; then
        info "安装 cron ..."
        case "${pm}" in
            apt-get) installPackages "${pm}" cron ;;
            dnf | yum) installPackages "${pm}" cronie crontabs ;;
            *) installPackages "${pm}" cron ;;
        esac
    fi

    if ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
        info "安装 python3 ..."
        installPackages "${pm}" python3
    fi
}

downloadCsm() {
    mkdir -p "${CSM_DIR}"

    local tmp="${CSM_SCRIPT}.tmp"
    local local_csm=""

    # 若 install.sh 与 csm.sh 在同一目录(本地克隆/离线安装), 直接使用本地文件
    if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
        local self_dir
        self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "${self_dir}/csm.sh" ]; then
            local_csm="${self_dir}/csm.sh"
        fi
    fi

    if [ -n "${local_csm}" ] && [ "${local_csm}" != "${CSM_SCRIPT}" ]; then
        info "使用本地 csm.sh: ${local_csm}"
        cp -f "${local_csm}" "${tmp}"
    else
        info "下载 csm.sh: ${CSM_URL}"
        if ! curl -fsSL --retry 3 --max-time 30 -o "${tmp}" "${CSM_URL}"; then
            error "下载失败, 请检查网络后重试, 或手动下载: ${CSM_URL}"
            exit 1
        fi
    fi

    if [ -f "${CSM_SCRIPT}" ]; then
        cp -f "${CSM_SCRIPT}" "${CSM_SCRIPT}.bak"
        info "已备份旧版本: ${CSM_SCRIPT}.bak"
    fi

    mv -f "${tmp}" "${CSM_SCRIPT}"
    chmod +x "${CSM_SCRIPT}"
    info "已安装: ${CSM_SCRIPT}"
}

writeConfig() {
    if [ -e "${CSM_CONFIG}" ]; then
        info "配置文件已存在: ${CSM_CONFIG} (如需修改请直接编辑该文件)"
        return
    fi

    while [ -z "${PANEL_ADDRESS}" ]; do
        read -r -p "$(input '请输入面板地址 (eg: https://demo.sspanel.org):')" PANEL_ADDRESS
        PANEL_ADDRESS="${PANEL_ADDRESS%/}"
    done
    while [ -z "${MU_KEY}" ]; do
        read -r -p "$(input '请输入 mu key:')" MU_KEY
    done
    while [ -z "${NODE_ID}" ]; do
        read -r -p "$(input '请输入节点 ID:')" NODE_ID
    done

    local resp
    resp="$(curl -s --max-time 15 "${PANEL_ADDRESS}/mod_mu/nodes?key=${MU_KEY}")"
    if echo "${resp}" | grep -q "invalid"; then
        error "面板地址或 mu key 有误, 请检查后重试"
        exit 1
    fi

    printf '%s\n%s\n%s\n' "${PANEL_ADDRESS}" "${MU_KEY}" "${NODE_ID}" >"${CSM_CONFIG}"
    chmod 600 "${CSM_CONFIG}"
    info "配置已写入: ${CSM_CONFIG}"
}

# 确保 cron 守护进程在运行: Alpine 用 OpenRC(crond), 常见发行版用 systemd/service
startCronService() {
    if command -v rc-service >/dev/null 2>&1; then
        rc-update add crond default >/dev/null 2>&1
        rc-service crond start >/dev/null 2>&1 || rc-service crond restart >/dev/null 2>&1
        info "已通过 OpenRC 启动 crond 并设置开机自启"
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now cron >/dev/null 2>&1 ||
            systemctl enable --now crond >/dev/null 2>&1 ||
            systemctl enable --now cronie >/dev/null 2>&1
    elif command -v service >/dev/null 2>&1; then
        service cron start >/dev/null 2>&1 || service crond start >/dev/null 2>&1
    elif command -v crond >/dev/null 2>&1; then
        pgrep crond >/dev/null 2>&1 || crond
    fi
}

getBashBin() {
    command -v bash 2>/dev/null || echo "/bin/bash"
}

setupCron() {
    if ! command -v crontab >/dev/null 2>&1; then
        warn "未检测到 crontab, 跳过定时任务配置 (可手动执行: bash ${CSM_SCRIPT})"
        return
    fi

    if crontab -l 2>/dev/null | grep -q "csm.sh"; then
        info "定时任务已存在, 跳过"
        startCronService
        return
    fi

    if [ -z "${INTERVAL}" ]; then
        cat <<'EOF'
[1] 1 小时    [2] 2 小时    [3] 3 小时    [4] 4 小时
[5] 6 小时    [6] 8 小时    [7] 12 小时   [8] 24 小时
EOF
        local interval_id
        read -r -p "$(input '请选择检测频率并输入序号 (eg: 1):')" interval_id
        case "${interval_id}" in
            1) INTERVAL=1 ;;
            2) INTERVAL=2 ;;
            3) INTERVAL=3 ;;
            4) INTERVAL=4 ;;
            5) INTERVAL=6 ;;
            6) INTERVAL=8 ;;
            7) INTERVAL=12 ;;
            8) INTERVAL=24 ;;
            *)
                error "请输入列表中的序号 (1-8)"
                exit 1
                ;;
        esac
    else
        if ! [[ "${INTERVAL}" =~ ^([1-9]|1[0-9]|2[0-4])$ ]]; then
            error "间隔小时数需在 1-24 之间"
            exit 1
        fi
    fi

    ( crontab -l 2>/dev/null; echo "0 */${INTERVAL} * * * $(getBashBin) ${CSM_SCRIPT}" ) | crontab -
    info "定时任务已添加: 每 ${INTERVAL} 小时检测一次"

    startCronService
}

main() {
    echo
    info "check-stream-media-forsspanel 安装脚本"
    info "仓库: https://github.com/${REPO}"
    echo

    installDependencies
    downloadCsm
    writeConfig
    setupCron

    echo
    info "开始首次检测, 结果将上报至面板 ..."
    "$(getBashBin)" "${CSM_SCRIPT}"

    echo
    info "安装完成"
    echo -e "  脚本位置: ${CSM_SCRIPT}"
    echo -e "  配置文件: ${CSM_CONFIG}"
    echo -e "  手动检测: bash ${CSM_SCRIPT}"
}

main
