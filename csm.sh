#!/bin/bash

# Alpine 等系统默认只有 ash, 若被 sh 调用则自动切换到 bash 执行
if [ -z "${BASH_VERSION:-}" ]; then
    if [ -f "$0" ] && command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    echo -e "\033[31m本脚本需要 bash, 请先安装 (Alpine: apk add bash)\033[0m"
    exit 1
fi

shopt -s expand_aliases

# 本项目目录: 优先取环境变量 CSM_DIR, 其次脚本所在目录, 最后回落到 $HOME
# 所有配置文件 / 检测报告均保存在该目录下, 便于自定义安装位置
if [ -n "${CSM_DIR:-}" ]; then
    :
elif [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    CSM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    CSM_DIR="${HOME}"
fi
mkdir -p "${CSM_DIR}"

Font_Black="\033[30m"
Font_Red="\033[31m"
Font_Green="\033[32m"
Font_Yellow="\033[33m"
Font_Blue="\033[34m"
Font_Purple="\033[35m"
Font_SkyBlue="\033[36m"
Font_White="\033[37m"
Font_Suffix="\033[0m"

while getopts ":I:M:EX:P:" optname; do
    case "$optname" in
    "I")
        iface="$OPTARG"
        useNIC="--interface $iface"
        ;;
    "M")
        if [[ "$OPTARG" == "4" ]]; then
            NetworkType=4
        elif [[ "$OPTARG" == "6" ]]; then
            NetworkType=6
        fi
        ;;
    "E")
        language="e"
        ;;
    "X")
        XIP="$OPTARG"
        xForward="--header X-Forwarded-For:$XIP"
        ;;
    "P")
        proxy="$OPTARG"
        usePROXY="-x $proxy"
        ;;
    ":")
        echo "Unknown error while processing options"
        exit 1
        ;;
    esac

done

if [ -z "$iface" ]; then
    useNIC=""
fi

if [ -z "$XIP" ]; then
    xForward=""
fi

if [ -z "$proxy" ]; then
    usePROXY=""
elif [ -n "$proxy" ]; then
    NetworkType=4
fi

if ! mktemp -u --suffix=RRC &>/dev/null; then
    is_busybox=1
fi

# 与上游 lmc999/RegionRestrictionCheck (check.sh) 保持一致的 UA
UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
UA_Android="Mozilla/5.0 (Linux; Android 10; Pixel 4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36"
UA_SEC_CH_UA='"Google Chrome";v="125", "Chromium";v="125", "Not.A/Brand";v="24"'
UA_Dalvik="Dalvik/2.1.0 (Linux; U; Android 9; ALP-AL00 Build/HUAWEIALP-AL00)"

# busybox grep 不支持 -P, 统一走本函数取值: grep_json_value <key>
if echo 'a' | grep -P 'a' >/dev/null 2>&1; then
    HAS_PCRE=1
else
    HAS_PCRE=0
fi

grep_json_value() {
    local key="$1"
    if [ "${HAS_PCRE}" = "1" ]; then
        grep -woP "\"${key}\"\s{0,}:\s{0,}\"?\K[^\",]+" | head -n 1
    else
        sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\).*/\1/p" | head -n 1 | tr -d '[:space:]'
    fi
}
# 优先使用本项目仓库内的资源, 拉取失败时回落到上游 lmc999/RegionRestrictionCheck
CSM_REPO_RAW="https://raw.githubusercontent.com/RyanRaw/check-stream-media-forsspanel/main"
Media_Cookie=$(curl -s --retry 3 --max-time 10 "${CSM_REPO_RAW}/cookies")
if [ -z "${Media_Cookie}" ]; then
    Media_Cookie=$(curl -s --retry 3 --max-time 10 "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/cookies")
fi
IATACode=$(curl -s --retry 3 --max-time 10 "${CSM_REPO_RAW}/reference/IATACode.txt")
if [ -z "${IATACode}" ]; then
    IATACode=$(curl -s --retry 3 --max-time 10 "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/reference/IATACode.txt")
fi
WOWOW_Cookie=$(echo "$Media_Cookie" | awk 'NR==3')
TVer_Cookie="Accept: application/json;pk=BCpkADawqM0_rzsjsYbC1k1wlJLU4HiAtfzjxdUmfvvLUQB-Ax6VA-p-9wOEZbCEm3u95qq2Y1CQQW1K9tPaMma9iAqUqhpISCmyXrgnlpx9soEmoVNuQpiyGsTpePGumWxSs1YoKziYB6Wz"

blue()
{
    echo -e "\033[34m[input]\033[0m"
}

countRunTimes() {
    if [ "$is_busybox" == 1 ]; then
        count_file=$(mktemp)
    else
        count_file=$(mktemp --suffix=RRC)
    fi
    RunTimes=$(curl -s --max-time 10 "https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fcheck.unclock.media&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=visit&edge_flat=false" >"${count_file}")
    TodayRunTimes=$(cat "${count_file}" | tail -3 | head -n 1 | awk '{print $5}')
    TotalRunTimes=$(($(cat "${count_file}" | tail -3 | head -n 1 | awk '{print $7}') + 2527395))
}
countRunTimes

checkOS() {
    ifTermux=$(echo $PWD | grep termux)
    ifMacOS=$(uname -a | grep Darwin)
    if [ -n "$ifTermux" ]; then
        os_version=Termux
        is_termux=1
    elif [ -n "$ifMacOS" ]; then
        os_version=MacOS
        is_macos=1
    elif [ -f /etc/alpine-release ] || grep -qi "alpine" /etc/os-release 2>/dev/null; then
        os_version=Alpine
        is_alpine=1
    else
        os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
    fi

    if [[ "$os_version" == "2004" ]] || [[ "$os_version" == "10" ]] || [[ "$os_version" == "11" ]]; then
        is_windows=1
        ssll="-k --ciphers DEFAULT@SECLEVEL=1"
    fi

    if [ "$(which apk 2>/dev/null)" ] && [ "$is_alpine" == 1 ]; then
        InstallMethod="apk"
    elif [ "$(which apt 2>/dev/null)" ]; then
        InstallMethod="apt"
        is_debian=1
    elif [ "$(which dnf 2>/dev/null)" ] || [ "$(which yum 2>/dev/null)" ]; then
        InstallMethod="yum"
        is_redhat=1
    elif [[ "$os_version" == "Termux" ]]; then
        InstallMethod="pkg"
    elif [[ "$os_version" == "MacOS" ]]; then
        InstallMethod="brew"
    fi
}

checkCPU() {
    CPUArch=$(uname -m)
    if [[ "$CPUArch" == "aarch64" ]]; then
        arch=_arm64
    elif [[ "$CPUArch" == "i686" ]]; then
        arch=_i686
    elif [[ "$CPUArch" == "arm" ]]; then
        arch=_arm
    elif [[ "$CPUArch" == "x86_64" ]] && [ -n "$ifMacOS" ]; then
        arch=_darwin
    fi
}

checkDependencies() {

    # os_detail=$(cat /etc/os-release 2> /dev/null)

    if ! command -v python &>/dev/null; then
        if command -v python3 &>/dev/null; then
            alias python="python3"
        else
            if [ "$is_debian" == 1 ]; then
                echo -e "${Font_Green}Installing python${Font_Suffix}"
                $InstallMethod update >/dev/null 2>&1
                $InstallMethod install python -y >/dev/null 2>&1
            elif [ "$is_redhat" == 1 ]; then
                echo -e "${Font_Green}Installing python${Font_Suffix}"
                if [[ "$os_version" -gt 7 ]]; then
                    $InstallMethod makecache >/dev/null 2>&1
                    $InstallMethod install python3 -y >/dev/null 2>&1
                    alias python="python3"
                else
                    $InstallMethod makecache >/dev/null 2>&1
                    $InstallMethod install python -y >/dev/null 2>&1
                fi

            elif [ "$is_termux" == 1 ]; then
                echo -e "${Font_Green}Installing python${Font_Suffix}"
                $InstallMethod update -y >/dev/null 2>&1
                $InstallMethod install python -y >/dev/null 2>&1

            elif [ "$is_macos" == 1 ]; then
                echo -e "${Font_Green}Installing python${Font_Suffix}"
                $InstallMethod install python
            elif [ "$is_alpine" == 1 ]; then
                echo -e "${Font_Green}Installing python3${Font_Suffix}"
                apk add --no-cache python3 >/dev/null 2>&1
                alias python="python3"
            fi
        fi
    fi

    if ! command -v dig &>/dev/null; then
        if [ "$is_debian" == 1 ]; then
            echo -e "${Font_Green}Installing dnsutils${Font_Suffix}"
            $InstallMethod update >/dev/null 2>&1
            $InstallMethod install dnsutils -y >/dev/null 2>&1
        elif [ "$is_redhat" == 1 ]; then
            echo -e "${Font_Green}Installing bind-utils${Font_Suffix}"
            $InstallMethod makecache >/dev/null 2>&1
            $InstallMethod install bind-utils -y >/dev/null 2>&1
        elif [ "$is_termux" == 1 ]; then
            echo -e "${Font_Green}Installing dnsutils${Font_Suffix}"
            $InstallMethod update -y >/dev/null 2>&1
            $InstallMethod install dnsutils -y >/dev/null 2>&1
        elif [ "$is_macos" == 1 ]; then
            echo -e "${Font_Green}Installing bind${Font_Suffix}"
            $InstallMethod install bind
        elif [ "$is_alpine" == 1 ]; then
            echo -e "${Font_Green}Installing bind-tools${Font_Suffix}"
            apk add --no-cache bind-tools >/dev/null 2>&1
        fi
    fi

    if [ "$is_macos" == 1 ]; then
        if ! command -v md5sum &>/dev/null; then
            echo -e "${Font_Green}Installing md5sha1sum${Font_Suffix}"
            $InstallMethod install md5sha1sum
        fi
    fi

    # Alpine(busybox) 可能缺少 base64 / bash, 检测脚本上报时依赖 base64
    if [ "$is_alpine" == 1 ]; then
        if ! command -v base64 &>/dev/null; then
            echo -e "${Font_Green}Installing coreutils${Font_Suffix}"
            apk add --no-cache coreutils >/dev/null 2>&1
        fi
        if ! command -v bash &>/dev/null; then
            echo -e "${Font_Yellow}建议安装 bash: apk add bash${Font_Suffix}"
        fi
    fi

}
checkDependencies

local_ipv4=$(curl $useNIC $usePROXY -4 -s --max-time 10 api64.ipify.org)
local_ipv4_asterisk=$(awk -F"." '{print $1"."$2".*.*"}' <<<"${local_ipv4}")
local_ipv6=$(curl $useNIC -6 -s --max-time 20 api64.ipify.org)
local_ipv6_asterisk=$(awk -F":" '{print $1":"$2":"$3":*:*"}' <<<"${local_ipv6}")
local_isp4=$(curl $useNIC -s -4 --max-time 10 --user-agent "${UA_Browser}" "https://api.ip.sb/geoip/${local_ipv4}" | grep organization | cut -f4 -d '"')
local_isp6=$(curl $useNIC -s -6 --max-time 10 --user-agent "${UA_Browser}" "https://api.ip.sb/geoip/${local_ipv6}" | grep organization | cut -f4 -d '"')

ShowRegion() {
    echo -e "${Font_Yellow} ---${1}---${Font_Suffix}"
}

###########################################
#                                         #
#           required check item           #
#                                         #
###########################################

MediaUnlockTest_BBCiPLAYER() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -${1} ${ssll} -fsL --max-time 10 "https://open.live.bbc.co.uk/mediaselector/6/select/version/2.0/mediaset/pc/vpid/bbc_one_london/format/json/jsfunc/JS_callbacks0" 2>&1)
    if [ "${tmpresult}" = "000" ]; then
        echo -n -e "\r BBC iPLAYER:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        return
    fi

    if [ -z "$tmpresult" ]; then
        echo -n -e "\r BBC iPLAYER:\t\t\t\t${Font_Red}Failed${Font_Suffix}\n"
        modifyJsonTemplate 'BBC_result' 'Unknow'
        return
    fi

    local isBlocked=$(echo "$tmpresult" | grep -i 'geolocation')
    local isOK=$(echo "$tmpresult" | grep -i 'vs-hls-push-uk')

    if [ -z "$isBlocked" ] && [ -z "$isOK" ]; then
        echo -n -e "\r BBC iPLAYER:\t\t\t\t${Font_Red}Failed${Font_Suffix}\n"
        modifyJsonTemplate 'BBC_result' 'Unknow'
    elif [ -n "$isBlocked" ]; then
        echo -n -e "\r BBC iPLAYER:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        modifyJsonTemplate 'BBC_result' 'No'
    else
        echo -n -e "\r BBC iPLAYER:\t\t\t\t${Font_Green}Yes${Font_Suffix}\n"
        modifyJsonTemplate 'BBC_result' 'Yes' 'UK'
    fi
}

MediaUnlockTest_MyTVSuper() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward -s -${1} ${ssll} --user-agent "${UA_Browser}" --max-time 10 "https://www.mytvsuper.com/api/auth/getSession/self/" 2>&1)

    if [ -z "$tmpresult" ]; then
        echo -n -e "\r MyTVSuper:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        modifyJsonTemplate 'MyTVSuper_result' 'Unknow'
        return
    fi

    local result=$(echo "$tmpresult" | grep_json_value 'country_code')
    if [ "$result" == 'HK' ]; then
        echo -n -e "\r MyTVSuper:\t\t\t\t${Font_Green}Yes${Font_Suffix}\n"
        modifyJsonTemplate 'MyTVSuper_result' 'Yes' 'HK'
    else
        echo -n -e "\r MyTVSuper:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        modifyJsonTemplate 'MyTVSuper_result' 'No' "${result}"
    fi
}

MediaUnlockTest_BilibiliHKMCTW() {
    local randsession="$(cat /dev/urandom | head -n 32 | md5sum | head -c 32)"
    # 尝试获取成功的结果
    local result=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -${1} -fsSL --max-time 10 "https://api.bilibili.com/pgc/player/web/playurl?avid=18281381&cid=29892777&qn=0&type=&otype=json&ep_id=183799&fourk=1&fnver=0&fnval=16&session=${randsession}&module=bangumi" 2>&1)
    if [[ "$result" != "curl"* ]]; then
        local result="$(echo "${result}" | grep_json_value 'code')"
        if [ "${result}" = "0" ]; then
            echo -n -e "\r BiliBili Hongkong/Macau/Taiwan:\t${Font_Green}Yes${Font_Suffix}\n"
            modifyJsonTemplate 'BilibiliHKMCTW_result' 'Yes' 'HK/MC/TW'
        elif [ "${result}" = "-10403" ]; then
            echo -n -e "\r BiliBili Hongkong/Macau/Taiwan:\t${Font_Red}No${Font_Suffix}\n"
            modifyJsonTemplate 'BilibiliHKMCTW_result' 'No'
        else
            echo -n -e "\r BiliBili Hongkong/Macau/Taiwan:\t${Font_Red}Failed${Font_Suffix} ${Font_SkyBlue}(${result})${Font_Suffix}\n"
            modifyJsonTemplate 'BilibiliHKMCTW_result' 'Unknow'
        fi
    else
        echo -n -e "\r BiliBili Hongkong/Macau/Taiwan:\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        modifyJsonTemplate 'BilibiliHKMCTW_result' 'Unknow'
    fi
}

MediaUnlockTest_BilibiliTW() {
    local randsession="$(cat /dev/urandom | head -n 32 | md5sum | head -c 32)"
    # 尝试获取成功的结果
    local result=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -${1} -fsSL --max-time 10 "https://api.bilibili.com/pgc/player/web/playurl?avid=50762638&cid=100279344&qn=0&type=&otype=json&ep_id=268176&fourk=1&fnver=0&fnval=16&session=${randsession}&module=bangumi" 2>&1)
    if [[ "$result" != "curl"* ]]; then
        local result="$(echo "${result}" | grep_json_value 'code')"
        if [ "${result}" = "0" ]; then
            echo -n -e "\r Bilibili Taiwan Only:\t\t\t${Font_Green}Yes${Font_Suffix}\n"
            modifyJsonTemplate 'BilibiliTW_result' 'Yes' 'TW'
        elif [ "${result}" = "-10403" ]; then
            echo -n -e "\r Bilibili Taiwan Only:\t\t\t${Font_Red}No${Font_Suffix}\n"
            modifyJsonTemplate 'BilibiliTW_result' 'No'
        else
            echo -n -e "\r Bilibili Taiwan Only:\t\t\t${Font_Red}Failed${Font_Suffix} ${Font_SkyBlue}(${result})${Font_Suffix}\n"
            modifyJsonTemplate 'BilibiliTW_result' 'Unknow'
        fi
    else
        echo -n -e "\r Bilibili Taiwan Only:\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        modifyJsonTemplate 'BilibiliTW_result' 'Unknow'
    fi
}

MediaUnlockTest_AbemaTV_IPTest() {
    # 注意: Abema 对机房/匿名 IP 会直接返回 403 {"message":"anonymous_ip"},
    # 因此这里不能用 curl -f(会把 403 当成网络失败), 与上游一致用 -sL
    local tmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Android}" -${1} ${ssll} -sL --max-time 10 "https://api.abema.io/v1/ip/check?device=android" 2>&1)
    if [ -z "$tmpresult" ]; then
        echo -n -e "\r Abema.TV:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        modifyJsonTemplate 'AbemaTV_result' 'Unknow'
        return
    fi

    local region=$(echo "$tmpresult" | grep_json_value 'isoCountryCode')
    if [ -n "$region" ]; then
        if [ "$region" == 'JP' ]; then
            echo -n -e "\r Abema.TV:\t\t\t\t${Font_Green}Yes${Font_Suffix}\n"
            modifyJsonTemplate 'AbemaTV_result' 'Yes' 'JP'
        else
            echo -n -e "\r Abema.TV:\t\t\t\t${Font_Yellow}Oversea Only (Region: ${region})${Font_Suffix}\n"
            modifyJsonTemplate 'AbemaTV_result' 'Yes' 'oversea'
        fi
    elif echo "$tmpresult" | grep -q 'anonymous_ip'; then
        echo -n -e "\r Abema.TV:\t\t\t\t${Font_Red}No${Font_Suffix} ${Font_SkyBlue}(Anonymous IP)${Font_Suffix}\n"
        modifyJsonTemplate 'AbemaTV_result' 'No' 'anonymous'
    else
        echo -n -e "\r Abema.TV:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        modifyJsonTemplate 'AbemaTV_result' 'No'
    fi
}

MediaUnlockTest_Netflix() {
    # 与上游同步: LEGO Ninjago + Breaking bad, 从页面内容判定是否为自制剧 / 区服
    local netflix_cookie='flwssn=d2c72c47-49e9-48da-b7a2-2dc6d7ca9fcf; nfvdid=BQFmAAEBEMZa4XMYVzVGf9-kQ1HXumtAKsCyuBZU4QStC6CGEGIVznjNuuTerLAG8v2-9V_kYhg5uxTB5_yyrmqc02U5l1Ts74Qquezc9AE-LZKTo3kY3g%3D%3D; SecureNetflixId=v%3D3%26mac%3DAQEAEQABABSQHKcR1d0sLV0WTu0lL-BO63TKCCHAkeY.%26dt%3D1745376277212; NetflixId=v%3D3%26ct%3DBgjHlOvcAxLAAZuNS4_CJHy9NKJPzUV-9gElzTlTsmDS1B59TycR-fue7f6q7X9JQAOLttD7OnlldUtnYWXL7VUfu9q4pA0gruZKVIhScTYI1GKbyiEqKaULAXOt0PHQzgRLVTNVoXkxcbu7MYG4wm1870fZkd5qrDOEseZv2WIVk4xIeNL87EZh1vS3RZU3e-qWy2tSmfSNUC-FVDGwxbI6-hk3Zg2MbcWYd70-ghohcCSZp5WHAGXg_xWVC7FHM3aOUVTGwRCU1RgGIg4KDKGr_wsTRRw6HWKqeA..; gsid=09bb180e-fbb1-4bf6-adcb-a3fa1236e323'

    local tmpresult1=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} --user-agent "${UA_Browser}" -fsL --max-time 20 'https://www.netflix.com/title/81280792' -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' -H 'accept-language: en-US,en;q=0.9' -b "${netflix_cookie}" -H "sec-ch-ua: ${UA_SEC_CH_UA}" -H 'sec-ch-ua-mobile: ?0' -H 'sec-ch-ua-platform: "Windows"' -H 'upgrade-insecure-requests: 1' 2>&1)
    local tmpresult2=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} --user-agent "${UA_Browser}" -fsL --max-time 20 'https://www.netflix.com/title/70143836' -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' -H 'accept-language: en-US,en;q=0.9' -b "${netflix_cookie}" -H "sec-ch-ua: ${UA_SEC_CH_UA}" -H 'sec-ch-ua-mobile: ?0' -H 'sec-ch-ua-platform: "Windows"' -H 'upgrade-insecure-requests: 1' 2>&1)

    if [ -z "${tmpresult1}" ] || [ -z "${tmpresult2}" ]; then
        echo -n -e "\r Netflix:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        modifyJsonTemplate 'Netflix_result' 'Unknow'
        return
    fi

    local result1=$(echo ${tmpresult1} | grep 'Oh no!')
    local result2=$(echo ${tmpresult2} | grep 'Oh no!')

    if [ -n "${result1}" ] && [ -n "${result2}" ]; then
        echo -n -e "\r Netflix:\t\t\t\t${Font_Yellow}Originals Only${Font_Suffix}\n"
        modifyJsonTemplate 'Netflix_result' 'No' 'Originals Only'
        return
    fi

    local region=$(echo "$tmpresult1" | sed -n 's/.*"id":"\([^"]*\)".*"countryName":"[^"]*".*/\1/p' | head -n 1)
    if [ -z "${region}" ]; then
        # 与 IPQuality 一致: 第一个页面取不到区服时用第二个页面兜底
        region=$(echo "$tmpresult2" | sed -n 's/.*"id":"\([^"]*\)".*"countryName":"[^"]*".*/\1/p' | head -n 1)
    fi
    if [ -z "${region}" ]; then
        region="US"
    fi
    echo -n -e "\r Netflix:\t\t\t\t${Font_Green}Yes (Region: ${region})${Font_Suffix}\n"
    modifyJsonTemplate 'Netflix_result' 'Yes' "${region}"
}

MediaUnlockTest_DisneyPlus() {
    local PreAssertion=$(curl $useNIC $usePROXY $xForward -${1} --user-agent "${UA_Browser}" -s --max-time 10 -X POST "https://disney.api.edge.bamgrid.com/devices" -H "authorization: Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -H "content-type: application/json; charset=UTF-8" -d '{"deviceFamily":"browser","applicationRuntime":"chrome","deviceProfile":"windows","attributes":{}}' 2>&1)
    if [[ "$PreAssertion" == "curl"* ]] && [[ "$1" == "6" ]]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}IPv6 Not Support${Font_Suffix}\n"
        return
    elif [[ "$PreAssertion" == "curl"* ]]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        modifyJsonTemplate 'DisneyPlus_result' 'Unknow'
        return
    fi

    local is403=$(echo "$PreAssertion" | grep -i '403 ERROR')
    if [ -n "$is403" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}No (IP Banned By Disney+)${Font_Suffix}\n"
        modifyJsonTemplate 'DisneyPlus_result' 'No' 'IP Banned'
        return
    fi

    local assertion=$(echo "$PreAssertion" | grep_json_value 'assertion')
    if [ -z "$assertion" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}Failed${Font_Suffix}\n"
        modifyJsonTemplate 'DisneyPlus_result' 'Unknow'
        return
    fi

    local PreDisneyCookie=$(echo "$Media_Cookie" | sed -n '1p')
    local disneycookie=$(echo $PreDisneyCookie | sed "s/DISNEYASSERTION/${assertion}/g")
    local TokenContent=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} --user-agent "${UA_Browser}" -s --max-time 10 -X POST "https://disney.api.edge.bamgrid.com/token" -H "authorization: Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -d "$disneycookie" 2>&1)
    local isBanned=$(echo "$TokenContent" | grep -i 'forbidden-location')
    local is403=$(echo "$TokenContent" | grep -i '403 ERROR')

    if [ -n "$isBanned" ] || [ -n "$is403" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}No (IP Banned By Disney+)${Font_Suffix}\n"
        modifyJsonTemplate 'DisneyPlus_result' 'No' 'IP Banned'
        return
    fi

    local fakecontent=$(echo "$Media_Cookie" | sed -n '8p')
    local refreshToken=$(echo "$TokenContent" | grep_json_value 'refresh_token')
    local disneycontent=$(echo $fakecontent | sed "s/ILOVEDISNEY/${refreshToken}/g")
    local tmpresult=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} --user-agent "${UA_Browser}" -X POST -sSL --max-time 10 "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql" -H "authorization: ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -d "$disneycontent" 2>&1)
    local previewcheck=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} --user-agent "${UA_Browser}" -s -o /dev/null -L --max-time 10 -w '%{url_effective}\n' "https://disneyplus.com" 2>&1)
    local isUnavailable=$(echo "$previewcheck" | grep -E 'preview|unavailable')
    local region=$(echo "$tmpresult" | grep_json_value 'countryCode')
    local inSupportedLocation=$(echo "$tmpresult" | grep_json_value 'inSupportedLocation')

    if [ -z "$region" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        modifyJsonTemplate 'DisneyPlus_result' 'No'
        return
    elif [ "$region" == "JP" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Green}Yes (Region: JP)${Font_Suffix}\n"
        modifyJsonTemplate 'DisneyPlus_result' 'Yes' 'JP'
        return
    elif [ -n "$isUnavailable" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        modifyJsonTemplate 'DisneyPlus_result' 'No' "${region}"
        return
    elif [ "$inSupportedLocation" == "false" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Yellow}Available For [Disney+ $region] Soon${Font_Suffix}\n"
        modifyJsonTemplate 'DisneyPlus_result' 'Soon' "${region}"
        return
    elif [ "$inSupportedLocation" == "true" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Green}Yes (Region: $region)${Font_Suffix}\n"
        modifyJsonTemplate 'DisneyPlus_result' 'Yes' "${region}"
        return
    else
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}Failed${Font_Suffix}\n"
        modifyJsonTemplate 'DisneyPlus_result' 'Unknow'
        return
    fi

}

MediaUnlockTest_YouTube_Premium() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -${1} ${ssll} --max-time 20 -sSL -H 'accept-language: en-US,en;q=0.9' -H 'cookie: YSC=FSCWhKo2Zgw; VISITOR_PRIVACY_METADATA=CgJERRIEEgAgYQ%3D%3D; PREF=f7=4000; __Secure-YEC=CgtRWTBGTFExeV9Iayjele2yBjIKCgJERRIEEgAgYQ%3D%3D; SOCS=CAISOAgDEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjQwNTI2LjAxX3AwGgV6aC1DTiACGgYIgMnpsgY; VISITOR_INFO1_LIVE=Di84mAIbgKY; __Secure-BUCKET=CGQ' "https://www.youtube.com/premium" 2>&1)

    if [ -z "$tmpresult" ]; then
        echo -n -e "\r YouTube Premium:\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        modifyJsonTemplate 'YouTube_Premium_result' 'Unknow'
        return
    fi

    local isCN=$(echo "$tmpresult" | grep 'www.google.cn')
    if [ -n "$isCN" ]; then
        echo -n -e "\r YouTube Premium:\t\t\t${Font_Red}No${Font_Suffix} ${Font_Green} (Region: CN)${Font_Suffix} \n"
        modifyJsonTemplate 'YouTube_Premium_result' 'No' 'CN'
        return
    fi

    local isNotAvailable=$(echo "$tmpresult" | grep -i 'Premium is not available in your country')
    # IPQuality 做法: contentRegion 比 INNERTUBE_CONTEXT_GL 更贴近真实区服
    local region=$(echo "$tmpresult" | grep_json_value 'contentRegion')
    if [ -z "$region" ]; then
        region=$(echo "$tmpresult" | grep_json_value 'INNERTUBE_CONTEXT_GL')
    fi
    local isAvailable=$(echo "$tmpresult" | grep -i 'ad-free')

    if [ -n "$isNotAvailable" ]; then
        echo -n -e "\r YouTube Premium:\t\t\t${Font_Red}No${Font_Suffix}\n"
        modifyJsonTemplate 'YouTube_Premium_result' 'No' "${region}"
        return
    fi
    if [ -z "$region" ] && [ -n "$isAvailable" ]; then
        region='UNKNOWN'
    fi
    if [ -n "$isAvailable" ]; then
        echo -n -e "\r YouTube Premium:\t\t\t${Font_Green}Yes (Region: ${region})${Font_Suffix}\n"
        modifyJsonTemplate 'YouTube_Premium_result' 'Yes' "${region}"
        return
    fi

    echo -n -e "\r YouTube Premium:\t\t\t${Font_Red}Failed${Font_Suffix}\n"
    modifyJsonTemplate 'YouTube_Premium_result' 'Unknow'
}

###
 # ChatGPT 检测: 同步自上游 lmc999/RegionRestrictionCheck (check.sh WebTest_OpenAI)
 # 原实现参考 https://github.com/missuo/OpenAI-Checker
###

OpenAiUnlockTest()
{
    local tmpresult1=$(curl $useNIC $usePROXY $xForward -s ${ssll} --max-time 20 'https://api.openai.com/compliance/cookie_requirements' -H 'authority: api.openai.com' -H 'accept: */*' -H 'accept-language: en-US,en;q=0.9' -H 'authorization: Bearer null' -H 'content-type: application/json' -H 'origin: https://platform.openai.com' -H 'referer: https://platform.openai.com/' -H "sec-ch-ua: ${UA_SEC_CH_UA}" -H 'sec-ch-ua-mobile: ?0' -H 'sec-ch-ua-platform: "Windows"' -H 'sec-fetch-dest: empty' -H 'sec-fetch-mode: cors' -H 'sec-fetch-site: same-site' --user-agent "${UA_Browser}" 2>&1)
    local tmpresult2=$(curl $useNIC $usePROXY $xForward -s ${ssll} --max-time 20 'https://ios.chat.openai.com/' -H 'authority: ios.chat.openai.com' -H 'accept: */*;q=0.8,application/signed-exchange;v=b3;q=0.7' -H 'accept-language: en-US,en;q=0.9' -H "sec-ch-ua: ${UA_SEC_CH_UA}" -H 'sec-ch-ua-mobile: ?0' -H 'sec-ch-ua-platform: "Windows"' -H 'sec-fetch-dest: document' -H 'sec-fetch-mode: navigate' -H 'sec-fetch-site: none' -H 'sec-fetch-user: ?1' -H 'upgrade-insecure-requests: 1' --user-agent "${UA_Browser}" 2>&1)

    if [ -z "$tmpresult1" ] || [ -z "$tmpresult2" ]; then
        echo -n -e "\r ChatGPT:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        modifyJsonTemplate 'OpenAI_result' 'Unknow'
        return
    fi

    local result1=$(echo "$tmpresult1" | grep -i 'unsupported_country')
    local result2=$(echo "$tmpresult2" | grep -i 'VPN')

    # 地区码取自出口 IP
    local ip="${local_ipv4}"
    [ -z "${ip}" ] && ip=$(getPublicIP 4)
    local region=$(getCountryCode "${ip}")

    if [ -z "$result1" ] && [ -z "$result2" ]; then
        echo -n -e "\r ChatGPT:\t\t\t\t${Font_Green}Yes (Region: ${region})${Font_Suffix}\n"
        modifyJsonTemplate 'OpenAI_result' 'Yes' "${region}"
        return
    fi
    if [ -n "$result1" ] && [ -n "$result2" ]; then
        echo -n -e "\r ChatGPT:\t\t\t\t${Font_Red}No (Region: ${region})${Font_Suffix}\n"
        modifyJsonTemplate 'OpenAI_result' 'No' "${region}"
        return
    fi
    if [ -z "$result1" ] && [ -n "$result2" ]; then
        echo -n -e "\r ChatGPT:\t\t\t\t${Font_Yellow}Web Only (Region: ${region})${Font_Suffix}\n"
        modifyJsonTemplate 'OpenAI_result' 'Web' "${region}"
        return
    fi

    echo -n -e "\r ChatGPT:\t\t\t\t${Font_Yellow}APP Only (Region: ${region})${Font_Suffix}\n"
    modifyJsonTemplate 'OpenAI_result' 'APP' "${region}"
}


###########################################
#                                         #
#   extra unlock check (ref: IPQuality)   #
#                                         #
###########################################

# 以下 3 项检测参考 https://github.com/xykt/IPQuality 的实现

MediaUnlockTest_TikTok() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -${1} ${ssll} -sL --max-time 15 "https://www.tiktok.com/" 2>&1)
    if [[ "$tmpresult" == *"Please wait..."* ]]; then
        tmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -${1} ${ssll} -sL --max-time 15 "https://www.tiktok.com/explore" 2>&1)
    fi

    if [ -z "$tmpresult" ]; then
        echo -n -e "\r TikTok:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        modifyJsonTemplate 'TikTok_result' 'Unknow'
        return
    fi

    local region=$(echo "$tmpresult" | grep -oE '"region"[[:space:]]*:[[:space:]]*"[A-Z]{2}"' | head -n 1 | cut -d '"' -f4)
    if [ -n "$region" ]; then
        echo -n -e "\r TikTok:\t\t\t\t${Font_Green}Yes (Region: ${region})${Font_Suffix}\n"
        modifyJsonTemplate 'TikTok_result' 'Yes' "${region}"
    else
        echo -n -e "\r TikTok:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        modifyJsonTemplate 'TikTok_result' 'No'
    fi
}

MediaUnlockTest_PrimeVideo() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -${1} ${ssll} -sL --max-time 15 "https://www.primevideo.com" 2>&1)

    if [ -z "$tmpresult" ]; then
        echo -n -e "\r Amazon Prime Video:\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        modifyJsonTemplate 'AmazonPV_result' 'Unknow'
        return
    fi

    local region=$(echo "$tmpresult" | grep -oE '"currentTerritory"[[:space:]]*:[[:space:]]*"[A-Z]{2}"' | head -n 1 | cut -d '"' -f4)
    if [ -n "$region" ]; then
        echo -n -e "\r Amazon Prime Video:\t\t\t${Font_Green}Yes (Region: ${region})${Font_Suffix}\n"
        modifyJsonTemplate 'AmazonPV_result' 'Yes' "${region}"
    else
        echo -n -e "\r Amazon Prime Video:\t\t\t${Font_Red}No${Font_Suffix}\n"
        modifyJsonTemplate 'AmazonPV_result' 'No'
    fi
}

MediaUnlockTest_Reddit() {
    local resp=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -${1} ${ssll} -fsL --max-time 15 --write-out '\n%{http_code}' "https://www.reddit.com/svc/shreddit/reddit-chat" 2>&1)
    local http_code=$(printf '%s' "$resp" | tail -n 1 | tr -d '\r')
    local html=$(printf '%s' "$resp" | sed '$d')

    case "$http_code" in
        "200")
            local region=$(printf '%s' "$html" | grep -oE 'country="[^"]+"' | head -n 1 | cut -d '"' -f2)
            echo -n -e "\r Reddit:\t\t\t\t${Font_Green}Yes (Region: ${region})${Font_Suffix}\n"
            modifyJsonTemplate 'Reddit_result' 'Yes' "${region}"
            ;;
        "403")
            echo -n -e "\r Reddit:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
            modifyJsonTemplate 'Reddit_result' 'No'
            ;;
        *)
            echo -n -e "\r Reddit:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
            modifyJsonTemplate 'Reddit_result' 'Unknow'
            ;;
    esac
}

###########################################
#                                         #
#   ip attribute check (ref: IPQuality)   #
#                                         #
###########################################

# 域名解析: dig 优先, 回退 nslookup
dnsLookup() {
    if command -v dig >/dev/null 2>&1; then
        dig +short "$1" 2>/dev/null | head -n 1
        return
    fi
    if command -v nslookup >/dev/null 2>&1; then
        nslookup "$1" 2>/dev/null | awk '/^Name:/{f=1;next} f && /^Address/{print $NF; exit}'
    fi
}

# 与 IPQuality 的 Get_Unlock_Type 一致: 随机子域若被解析出结果, 说明 DNS 被劫持/污染
MediaUnlockTest_UnlockType() {
    local domains="netflix.com www.youtube.com"
    local bad="" d answer
    for d in ${domains}; do
        answer=$(dnsLookup "test${RANDOM}${RANDOM}.${d}")
        if [ -n "${answer}" ]; then
            bad="${bad}${bad:+, }${d}"
        fi
    done

    if [ -z "${bad}" ]; then
        UNLOCK_TYPE="native"
        echo -n -e "\r Unlock Type:\t\t\t\t${Font_Green}Native${Font_Suffix}\n"
        modifyJsonTemplate 'UnlockType_result' 'Native'
    else
        UNLOCK_TYPE="dns"
        echo -n -e "\r Unlock Type:\t\t\t\t${Font_Yellow}DNS Hijack${Font_Suffix} ${Font_SkyBlue}(${bad})${Font_Suffix}\n"
        modifyJsonTemplate 'UnlockType_result' 'DNS Hijack' "${bad}"
    fi
}

# 出口 IP 多源兜底(部分节点访问单一接口会失败)
getPublicIP() {
    local ip=""
    local src
    for src in "https://api64.ipify.org" "https://api.ip.sb/ip" "https://ipinfo.io/ip" "https://ifconfig.me/ip" "http://ip-api.com/line?fields=query"; do
        ip=$(curl -s -${1:-4} ${ssll} --max-time 8 "${src}" 2>/dev/null | tr -d '\r\n ')
        if [ -n "${ip}" ] && echo "${ip}" | grep -Eq '^[0-9a-fA-F:.]{7,45}$'; then
            echo "${ip}"
            return
        fi
    done
    echo ""
}

# 出口 IP 所属地区码(国家/地区二位码), 用于按地区上报的检测项
getCountryCode() {
    local ip="$1"
    local cc=""
    if [ -n "${ip}" ]; then
        cc=$(curl -s --max-time 8 "https://api.country.is/${ip}" 2>/dev/null | grep_json_value 'country')
    fi
    if [ -z "${cc}" ] && [ -n "${ip}" ]; then
        cc=$(curl -s --max-time 8 "http://ip-api.com/json/${ip}?fields=status,countryCode" 2>/dev/null | grep_json_value 'countryCode')
    fi
    echo "${cc}"
}

# IP 属性与定性风险:
#   源1 ipinfo.io widget(无需 token) -> 源2 ip-api.com(免费, IPv4) -> 源3 ip.sb(仅运营商信息)
MediaUnlockTest_IPAttribute() {
    local ip="${local_ipv4}"
    if [ -z "${ip}" ]; then
        ip=$(getPublicIP 4)
    fi
    local family=4
    if [ -z "${ip}" ]; then
        ip="${local_ipv6}"
        family=6
    fi
    if [ -z "${ip}" ]; then
        ip=$(getPublicIP 6)
        family=6
    fi

    local resp asn_type="" hosting="" vpn="" proxy="" tor="" mobile="" ok=0

    if [ -n "${ip}" ]; then
        # 源1: ipinfo.io widget
        resp=$(curl -s --max-time 10 -${family} ${ssll} --user-agent "${UA_Browser}" "https://ipinfo.io/widget/demo/${ip}" 2>/dev/null)
        if echo "${resp}" | grep -q '"privacy"'; then
            ok=1
            asn_type=$(echo "${resp}" | grep_json_value 'type')
            hosting=$(echo "${resp}" | grep_json_value 'hosting')
            vpn=$(echo "${resp}" | grep_json_value 'vpn')
            proxy=$(echo "${resp}" | grep_json_value 'proxy')
            tor=$(echo "${resp}" | grep_json_value 'tor')
            mobile=$(echo "${resp}" | grep_json_value 'is_mobile')
        fi
    fi

    if [ "${ok}" != "1" ] && [ -n "${ip}" ] && [ "${family}" = "4" ]; then
        # 源2: ip-api.com 免费接口(仅 IPv4)
        resp=$(curl -s --max-time 10 -4 ${ssll} "http://ip-api.com/json/${ip}?fields=status,proxy,hosting,mobile" 2>/dev/null)
        if echo "${resp}" | grep -q '"status":"success"'; then
            ok=1
            hosting=$(echo "${resp}" | grep_json_value 'hosting')
            proxy=$(echo "${resp}" | grep_json_value 'proxy')
            mobile=$(echo "${resp}" | grep_json_value 'mobile')
            if [ "${hosting}" = "true" ]; then
                asn_type="hosting"
            elif [ "${mobile}" = "true" ]; then
                asn_type="mobile"
            else
                asn_type="isp"
            fi
        fi
    fi

    if [ "${ok}" != "1" ] && [ -n "${ip}" ]; then
        # 源3: ip.sb 兜底, 只能拿到运营商/组织
        resp=$(curl -s --max-time 10 -${family} ${ssll} --user-agent "${UA_Browser}" "https://api.ip.sb/geoip/${ip}" 2>/dev/null)
        if echo "${resp}" | grep -q '"isp"'; then
            ok=2
            asn_type=$(echo "${resp}" | grep_json_value 'isp')
        fi
    fi

    if [ "${ok}" = "0" ]; then
        echo -n -e "\r IP Type:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        echo -n -e "\r IP Risk:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        modifyJsonTemplate 'IPType_result' 'Unknow'
        modifyJsonTemplate 'IPRisk_result' 'Unknow'
        return
    fi

    local iptype="Other"
    if [ "${ok}" = "2" ]; then
        # 兜底数据源只提供运营商/组织名
        iptype="${asn_type}"
    else
        case "${asn_type}" in
            hosting) iptype="Hosting" ;;
            isp) iptype="ISP" ;;
            business) iptype="Business" ;;
            education) iptype="Education" ;;
            government) iptype="Government" ;;
        esac
        if [ "${mobile}" = "true" ] && [ "${asn_type}" != "hosting" ]; then
            iptype="Mobile"
        fi
    fi

    local tags=""
    [ "${vpn}" = "true" ] && tags="${tags}${tags:+, }VPN"
    [ "${proxy}" = "true" ] && tags="${tags}${tags:+, }Proxy"
    [ "${tor}" = "true" ] && tags="${tags}${tags:+, }Tor"

    local risk="Low"
    if [ "${ok}" = "2" ]; then
        risk="unknown"
    elif [ "${tor}" = "true" ] || [ "${proxy}" = "true" ] || [ "${vpn}" = "true" ]; then
        risk="High"
    elif [ "${hosting}" = "true" ]; then
        risk="Medium"
    fi

    local color="${Font_Green}"
    [ "${risk}" = "Medium" ] && color="${Font_Yellow}"
    [ "${risk}" = "High" ] && color="${Font_Red}"
    [ "${risk}" = "unknown" ] && color="${Font_SkyBlue}"

    modifyJsonTemplate 'IPType_result' "${iptype}" "${tags}"
    modifyJsonTemplate 'IPRisk_result' "${risk}"

    if [ -n "${tags}" ]; then
        echo -n -e "\r IP Type:\t\t\t\t${color}${iptype} (${tags})${Font_Suffix}\n"
    else
        echo -n -e "\r IP Type:\t\t\t\t${color}${iptype}${Font_Suffix}\n"
    fi
    echo -n -e "\r IP Risk:\t\t\t\t${color}${risk}${Font_Suffix}\n"
}

###########################################
#                                         #
#   sspanel unlock check function code    #
#                                         #
###########################################

createJsonTemplate() {
    echo '{
    "YouTube": YouTube_Premium_result,
    "Netflix": Netflix_result,
    "DisneyPlus": DisneyPlus_result,
    "BilibiliHKMCTW": BilibiliHKMCTW_result,
    "BilibiliTW": BilibiliTW_result,
    "MyTVSuper": MyTVSuper_result,
    "BBC": BBC_result,
    "Abema": AbemaTV_result,
    "OpenAI": OpenAI_result,
    "TikTok": TikTok_result,
    "AmazonPV": AmazonPV_result,
    "Reddit": Reddit_result,
    "UnlockType": "UnlockType_result",
    "IPType": "IPType_result",
    "IPRisk": "IPRisk_result"
}' > "${CSM_DIR}/media_test_tpl.json"
}

# 上报值转换:
#   流媒体项 -> 对象 {"status":"yes","region":"MY","type":"native"}
#   UnlockType / IPType / IPRisk -> 字符串
modifyJsonTemplate() {
    local key_word=$1
    local result=$2
    local region=$3
    local value=""

    case "${key_word}" in
        UnlockType_result | IPType_result | IPRisk_result)
            # 模板中这三项本身已带引号, 此处只替换引号内的内容
            if [[ "${region}" == "" ]]; then
                value="${result}"
            else
                value="${result} (${region})"
            fi
            ;;
        *)
            local status=""
            case "${result}" in
                Yes) status="yes" ;;
                No) status="no" ;;
                Soon) status="soon" ;;
                Web) status="web" ;;
                APP) status="app" ;;
                Unknow) status="unknown" ;;
                *) status="$(echo "${result}" | tr '[:upper:]' '[:lower:]')" ;;
            esac

            # 兼容旧调用的描述性参数, 统一为面板端约定的取值
            case "${region}" in
                "Oversea Only") region="oversea" ;;
                "Originals Only") region="originals" ;;
                "IP Banned") region="banned" ;;
            esac

            value="{\"status\":\"${status}\""
            if [[ "${region}" != "" ]]; then
                value="${value},\"region\":\"${region}\""
            fi
            if [[ "${UNLOCK_TYPE:-}" != "" ]]; then
                value="${value},\"type\":\"${UNLOCK_TYPE}\""
            fi
            value="${value}}"
            ;;
    esac

    sed -i "s#${key_word}#${value}#g" "${CSM_DIR}/media_test_tpl.json"
}

setCronTask() {
    addTask() {
        execution_time_interval=$1

        local bash_bin
        bash_bin="$(command -v bash 2>/dev/null || echo /bin/bash)"
        crontab -l >"${CSM_DIR}/crontab.list"
        echo "0 */${execution_time_interval} * * * ${bash_bin} ${CSM_DIR}/csm.sh" >>"${CSM_DIR}/crontab.list"
        crontab "${CSM_DIR}/crontab.list"
        rm -rf "${CSM_DIR}/crontab.list"
        echo -e "$(green) The scheduled task is added successfully."
    }

    crontab -l | grep "csm.sh" >/dev/null
    if [[ "$?" != "0" ]]; then
        echo "[1] 1 hour"
        echo "[2] 2 hour"
        echo "[3] 3 hour"
        echo "[4] 4 hour"
        echo "[5] 6 hour"
        echo "[6] 8 hour"
        echo "[7] 12 hour"
        echo "[8] 24 hour"
        echo
        read -p "$(blue) Please select the detection frequency and enter the serial number (eg: 1):" time_interval_id

        if [[ "${time_interval_id}" == "5" ]];then
            time_interval=6
        elif [[ "${time_interval_id}" == "6" ]];then
            time_interval=8
        elif [[ "${time_interval_id}" == "7" ]];then
            time_interval=12
        elif [[ "${time_interval_id}" == "8" ]];then
            time_interval=24
        else
            time_interval=$time_interval_id
        fi

        case "${time_interval_id}" in
            [1-8])
                addTask ${time_interval};;
            *)
                echo -e "$(red) Choose one from the list given and enter the sequence number."
                exit;;
        esac
    fi
}

checkConfig() {
    getConfig() {
        read -p "$(blue) Please enter the panel address (eg: https://demo.sspanel.org):" panel_address
        read -p "$(blue) Please enter the mu key:" mu_key
        read -p "$(blue) Please enter the node id:" node_id
        read -p "$(blue) Please enter the X-Node-Token (optional, press enter to use mu key):" node_token

        if [[ "${panel_address}" = "" ]] || [[ "${mu_key}" = "" ]];then
            echo -e "$(red) Complete all necessary parameter entries."
            exit
        fi

        curl -s "${panel_address}/mod_mu/nodes?key=${mu_key}" | grep "invalid" > /dev/null
        if [[ "$?" = "0" ]];then
            echo -e "$(red) Wrong website address or mukey error, please try again."
            exit
        fi

        echo "${panel_address}" > "${CSM_DIR}/.csm.config"
        echo "${mu_key}" >> "${CSM_DIR}/.csm.config"
        echo "${node_id}" >> "${CSM_DIR}/.csm.config"
        echo "${node_token}" >> "${CSM_DIR}/.csm.config"
    }

    if [[ ! -e "${CSM_DIR}/.csm.config" ]];then
        getConfig
    fi
}

postData() {
    if [[ ! -e "${CSM_DIR}/.csm.config" ]];then
        echo -e "$(red) Missing configuration file."
        exit
    fi
    if [[ ! -e "${CSM_DIR}/media_test_tpl.json" ]];then
        echo -e "$(red) Missing detection report."
        exit
    fi

    panel_address=$(sed -n 1p "${CSM_DIR}/.csm.config")
    mu_key=$(sed -n 2p "${CSM_DIR}/.csm.config")
    node_id=$(sed -n 3p "${CSM_DIR}/.csm.config")
    node_token=$(sed -n 4p "${CSM_DIR}/.csm.config")
    # 旧配置没有第 4 行时, X-Node-Token 回退使用 mu key
    [[ -z "${node_token}" ]] && node_token="${mu_key}"

    local content
    content=$(cat "${CSM_DIR}/media_test_tpl.json" | base64 | xargs echo -n | sed 's# ##g')

    # 鉴权: URL 查询参数 key 必填(面板不读请求头); 同时附带节点 X-Node-Token 头
    # content 用 --data-urlencode 提交, base64 中的 + 会被正确编码并在面板侧还原
    curl -s -X POST \
        -H "X-Node-Token: ${node_token}" \
        --data-urlencode "content=${content}" \
        "${panel_address}/mod_mu/media/save_report?key=${mu_key}&node_id=${node_id}" > "${CSM_DIR}/.csm.response"
    if [[ "$(cat "${CSM_DIR}/.csm.response")" != "ok" ]];then
        curl -s -X POST \
            -H "X-Node-Token: ${node_token}" \
            --data-urlencode "content=${content}" \
            "${panel_address}/mod_mu/media/saveReport?key=${mu_key}&node_id=${node_id}" > "${CSM_DIR}/.csm.response"
    fi

    rm -rf "${CSM_DIR}/media_test_tpl.json" "${CSM_DIR}/.csm.response"
}

printInfo() {
    green_start='\033[32m'
    color_end='\033[0m'

    echo
    echo -e "${green_start}The code for this script to detect streaming media unlocking is all from the open source project https://github.com/lmc999/RegionRestrictionCheck , and the open source protocol is AGPL-3.0. This script is open source as required by the open source license. Thanks to the original author @lmc999 and everyone who made the pull request for this project for their contributions.${color_end}"
    echo
    echo -e "${green_start}Project: https://github.com/RyanRaw/check-stream-media-forsspanel${color_end}"
    echo -e "${green_start}Version: 2026-09-21 v.2.3.0${color_end}"
    echo -e "${green_start}Detect logic synced with upstream check.sh v1.0.1${color_end}"
    echo -e "${green_start}Extra checks (TikTok / Amazon Prime Video / Reddit) ref: https://github.com/xykt/IPQuality${color_end}"
    echo -e "${green_start}Author: @iamsaltedfish, fork by @RyanRaw${color_end}"
}

runCheck() {
    createJsonTemplate
    # 先判定 DNS 解锁方式(native/dns), 供后续各项上报的 type 字段使用
    MediaUnlockTest_UnlockType
    MediaUnlockTest_BBCiPLAYER 4
    MediaUnlockTest_MyTVSuper 4
    MediaUnlockTest_BilibiliHKMCTW 4
    MediaUnlockTest_BilibiliTW 4
    MediaUnlockTest_AbemaTV_IPTest 4
    MediaUnlockTest_Netflix 4
    MediaUnlockTest_YouTube_Premium 4
    MediaUnlockTest_DisneyPlus 4
    OpenAiUnlockTest
    MediaUnlockTest_TikTok 4
    MediaUnlockTest_PrimeVideo 4
    MediaUnlockTest_Reddit 4
    MediaUnlockTest_IPAttribute
}

checkData()
{
    counter=0
    max_check_num=3
    cat "${CSM_DIR}/media_test_tpl.json" | grep "_result" > /dev/null
    until [ $? != '0' ]  || [[ ${counter} -ge ${max_check_num} ]]
    do
        sleep 1
        runCheck > /dev/null
        echo -e "\033[33mThere is something wrong with the data and it is being retested for the ${counter} time...\033[0m"
        counter=$(expr ${counter} + 1)
    done
}

main() {
    echo
    checkOS
    checkCPU
    checkDependencies
    setCronTask
    checkConfig
    runCheck
    checkData
    postData
    printInfo
}

main
