#!/bin/bash

# ==============================================
# 流量消耗脚本 - 终极稳定版
# 功能：
# 1. 保留所有原始资源名称
# 2. 支持国内/海外资源选择
# 3. 可设置流量限制和线程数
# 4. 实时统计显示
# 5. 支持每日定时任务配置与执行
# ==============================================

#声明版本号
VERSION="v0.2"
SCRIPT_PATH=$(readlink -f "$0")
SCHEDULE_CONF="/etc/VPSShua/schedule.conf"
CRON_TAG="# VPSSHUA_DAILY_JOB"

# 定义颜色代码
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PURPLE="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"
RESET="\033[0m"  # 重置颜色

# 初始化变量
TOTAL_BYTES=0
REQUEST_COUNT=0
START_TIME=$(date +%s)
STAT_FILE="/tmp/flow_stats_$$.tmp"
STOP_FILE="/tmp/flow_stop_$$.tmp"
THREADS=1
LIMIT_GB=1
RESOURCE_TYPE="未选择"
SELECTED_URLS=()

check_dependencies() {
    local missing=()
    local deps=(curl awk bc)

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "缺少依赖: ${missing[*]}"
        echo "请先安装后再运行脚本。"
        echo "Debian/Ubuntu: sudo apt update && sudo apt install -y ${missing[*]}"
        echo "CentOS/RHEL:   sudo yum install -y ${missing[*]}"
        echo "Alpine:        sudo apk add ${missing[*]}"
        exit 1
    fi
}

check_cron_dependency() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "未找到 crontab 命令，请先安装 cron/cronie 后再配置定时任务。"
        return 1
    fi
    return 0
}

save_schedule_config() {
    local dir
    dir=$(dirname "$SCHEDULE_CONF")
    mkdir -p "$dir" || return 1

    {
        echo "LIMIT_GB=$LIMIT_GB"
        echo "THREADS=$THREADS"
        echo "RESOURCE_TYPE=$RESOURCE_TYPE"
        printf 'SELECTED_URLS=(\n'
        for url in "${SELECTED_URLS[@]}"; do
            printf '  "%s"\n' "$url"
        done
        printf ')\n'
    } > "$SCHEDULE_CONF"
}

load_schedule_config() {
    if [ ! -f "$SCHEDULE_CONF" ]; then
        echo "未找到定时任务配置: $SCHEDULE_CONF"
        return 1
    fi

    # shellcheck disable=SC1090
    source "$SCHEDULE_CONF"

    if [ -z "$LIMIT_GB" ] || [ -z "$THREADS" ] || [ ${#SELECTED_URLS[@]} -eq 0 ]; then
        echo "定时配置不完整，请重新配置。"
        return 1
    fi

    return 0
}

install_daily_cron() {
    local hour="$1"
    local minute="$2"
    local cron_line
    local tmp_cron

    cron_line="$minute $hour * * * $SCRIPT_PATH --run-scheduled >/tmp/vpsshua-cron.log 2>&1 $CRON_TAG"

    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | sed "/$CRON_TAG/d" > "$tmp_cron"
    echo "$cron_line" >> "$tmp_cron"
    crontab "$tmp_cron"
    rm -f "$tmp_cron"
}

configure_daily_schedule() {
    check_cron_dependency || return 1

    if [ ${#SELECTED_URLS[@]} -eq 0 ]; then
        echo "请先在主菜单选择资源后再配置定时任务。"
        return 1
    fi

    local run_time hour minute
    read -p "请输入每日执行时间 (HH:MM，24小时制): " run_time

    if [[ ! "$run_time" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        echo "时间格式错误，请使用 HH:MM，例如 03:30"
        return 1
    fi

    hour=${run_time%:*}
    minute=${run_time#*:}

    save_schedule_config || {
        echo "写入配置失败: $SCHEDULE_CONF"
        return 1
    }

    install_daily_cron "$hour" "$minute" || {
        echo "写入 crontab 失败。"
        return 1
    }

    echo "每日定时任务已设置：$run_time"
    echo "定时配置文件：$SCHEDULE_CONF"
    echo "日志输出：/tmp/vpsshua-cron.log"
}

remove_daily_schedule() {
    check_cron_dependency || return 1

    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | sed "/$CRON_TAG/d" > "$tmp_cron"
    crontab "$tmp_cron"
    rm -f "$tmp_cron"

    rm -f "$SCHEDULE_CONF"
    echo "已删除每日定时任务和配置文件。"
}

show_daily_schedule_status() {
    check_cron_dependency || return 1

    echo "当前 crontab 中的 VPSShua 定时任务："
    crontab -l 2>/dev/null | grep "$CRON_TAG" || echo "(未配置)"

    if [ -f "$SCHEDULE_CONF" ]; then
        echo "配置文件：$SCHEDULE_CONF"
        sed 's/^/  /' "$SCHEDULE_CONF"
    else
        echo "配置文件：未找到"
    fi
}

run_scheduled_job() {
    check_dependencies
    load_schedule_config || return 1

    echo "[$(date '+%F %T')] 启动定时任务，资源类型: $RESOURCE_TYPE，限制: ${LIMIT_GB}GB，线程: $THREADS"
    start_download
}

# 国内资源（完全保持原始名称）
DOMESTIC=(
    "腾讯:https://www.tencent.com/data/index/index_develop_bg3.jpg"
    "腾讯云:https://qcloudimg.tencent-cloud.cn/raw/a6acc2eb4684190b47a283b636fbe085.png"
    "腾讯视频:https://puui.qpic.cn/vpic_cover/g3346tki83w/g3346tki83w_hz.jpg"
    "WeGame:https://wegame.gtimg.com/g.55555-r.c4663/wegame-home/sc02-03.514d7db8.png"
    "百度网盘:https://nd-static.bdstatic.com/m-static/wp-brand/img/banner.5783471b.png"
    "阿里:https://gw.alicdn.com/tfs/TB1k07QUoY1gK0jSZFCXXcwqXXa-810-450.png"
    "微软:https://cdn.microsoftstore.com.cn/media/product_long_description/3781-00000/2_dupn50xr/4h0yzz2_360.jpg"
    "OPPO:https://dsfs.oppo.com/archives/202505/20250520040508682c3f3436ff8.jpg"
    "VIVO:https://wwwstatic.vivo.com.cn/vivoportal/files/image/home/20250516/0b3ee0e9c797bc3e6756b94f5ddd838b.png"
    "拼多多:https://funimg.pddpic.com/c3affbeb-9b31-4546-b2df-95b62de81639.png.slim.png"
    "斗鱼:https://shark2.douyucdn.cn/front-publish/douyu-web-master/_next/static/media/8.ce6e862f.jpg"
    "字节跳动:https://lf1-cdn-tos.bytescm.com/obj/static/ies/bytedance_official/_next/static/images/8-4@2x-f85835b5e482bccf94c824067caac899.png"
)

# 海外资源（完全保持原始名称）
OVERSEAS=(
    "Cloudflare:https://cf-assets.www.cloudflare.com/dzlvafdwdttg/3NFuZG6yz35QXSBt4ToS9y/920197fd1229641b4d826d9f5d0aa169/globe.webp"
    "GitHub:https://docs.github.com/assets/images/search/copilot-action.png"
    "Vultr:https://www.vultr.com/_images/company/sla-banner-bg.png"
    "Linode:https://www.akamai.com/content/dam/site/en/images/video-thumbnail/2024/learn-akamai-live-api-security.png"
    "BBS中文:https://ichef.bbci.co.uk/ace/ws/800/cpsprodpb/61b3/live/bdc7c940-317f-11f0-96c3-cf669419a2b0.jpg.webp"
    "腾讯云:https://staticintl.cloudcachetci.com/cms/backend-cms/VyhG740_iClick%E5%AE%A2%E6%88%B7%E6%A1%88%E4%BE%8B%E8%A7%86%E9%A2%91%E5%B0%81%E9%9D%A2.png"
    "腾讯视频:https://vfiles.gtimg.cn/vupload/20211124/6d0d431637725495400.png"
    "微软:https://cdn.microsoftstore.com.cn/media/product_long_description/3781-00000/2_dupn50xr/4h0yzz2_360.jpg"
    "OPPO:https://www.oppo.com/content/dam/oppo/common/mkt/v2-2/a5-series-en/v3/topbanner/5120-1280.jpg"
    "VIVO:https://asia-exstatic-vivofs.vivo.com/PSee2l50xoirPK7y/1741005511420/a6938ac9d8aaa342065dc5c9ef1679df.jpg"
    "拼多多:https://funimg.pddpic.com/c3affbeb-9b31-4546-b2df-95b62de81639.png.slim.png"
    "斗鱼:https://shark2.douyucdn.cn/front-publish/douyu-web-master/_next/static/media/8.ce6e862f.jpg"
    "字节跳动:https://lf1-cdn-tos.bytescm.com/obj/static/ies/bytedance_official/_next/static/images/8-4@2x-f85835b5e482bccf94c824067caac899.png"
)

# 清理函数
cleanup() {
    rm -f "$STAT_FILE" "$STOP_FILE" &>/dev/null
    kill $(jobs -p) &>/dev/null
    exit 0
}

# 字节转换
format_bytes() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        echo "$(echo "scale=2; $bytes/1073741824" | bc)GB"
    elif (( bytes >= 1048576 )); then
        echo "$(echo "scale=2; $bytes/1048576" | bc)MB"
    elif (( bytes >= 1024 )); then
        echo "$(echo "scale=2; $bytes/1024" | bc)KB"
    else
        echo "${bytes}B"
    fi
}

# 下载任务
download_task() {
    local url="$1"
    while [ ! -f "$STOP_FILE" ]; do
        # 获取下载字节数
        bytes=$(curl -o /dev/null -s -w "%{size_download}" --connect-timeout 10 "$url" 2>/dev/null)
        
        if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
            # 写入统计文件
            echo "$bytes" >> "$STAT_FILE"
        fi
        
        sleep 0.1
    done
}

# 显示菜单
show_menu() {
    clear
    echo "======================================"
    echo "         VPSShua|VPS刷下行流量         "
    echo "版本: $VERSION | 脚本: $SCRIPT_PATH"
    echo "======================================"
    echo "当前设置:"
    echo "  - 资源类型: $([ -z "$RESOURCE_TYPE" ] && echo "未选择" || echo "$RESOURCE_TYPE")"
    echo "  - 流量限制: ${LIMIT_GB}GB"
    echo "  - 线程数量: ${THREADS}"
    echo "--------------------------------------"
    echo "1. 选择地区 (国内/海外)"
    echo "2. 设置流量限制"
    echo "3. 设置线程数"
    echo "4. 开始运行"
    echo "5. 退出"
    echo "6. 更新 VPSShua"
    echo "7. 配置每日定时任务"
    echo "8. 删除每日定时任务"
    echo "9. 查看定时任务状态"
    echo "======================================"
    echo -e "${RED}VPSShua提醒您："
    echo -e "本脚本仅限交流学习使用|请勿违反使用者当地法律法规的用途"
    echo -e "否则后果自负|我们将不承担任何法律责任${RESET}"
    echo "======================================"
}

# 选择地区
select_region() {
    echo "请选择资源地区:"
    echo "1) 国内资源"
    echo "2) 海外资源"
    read -p "请输入选择(1-2): " choice
    
    case $choice in
        1) RESOURCES=("${DOMESTIC[@]}"); RESOURCE_TYPE="国内" ;;
        2) RESOURCES=("${OVERSEAS[@]}"); RESOURCE_TYPE="海外" ;;
        *) echo "无效选择"; return 1 ;;
    esac
    
    # 显示资源列表
    echo "可用的${RESOURCE_TYPE}资源:"
    for i in "${!RESOURCES[@]}"; do
        echo "$((i+1)). ${RESOURCES[$i]%%:*}"
    done
    
    read -p "选择要使用的资源(默认全部): " res_choice
    if [[ "$res_choice" =~ ^[0-9]+$ ]] && (( res_choice >= 1 && res_choice <= ${#RESOURCES[@]} )); then
        SELECTED_URLS=("${RESOURCES[$((res_choice-1))]#*:}")
    else
        SELECTED_URLS=()
        for res in "${RESOURCES[@]}"; do
            SELECTED_URLS+=("${res#*:}")
        done
    fi
    
    echo "已选择 ${#SELECTED_URLS[@]} 个资源"
}

# 更新 VPSShua
update_vpsshua() {
    echo "正在从 main 分支更新脚本..."
    local update_url="https://raw.githubusercontent.com/CN-Root/VPSShua/main/vpsshua.sh"

    if curl -fsSL "$update_url" -o "$SCRIPT_PATH"; then
        chmod +x "$SCRIPT_PATH"
        echo "更新成功（来源: main 分支）！请重新运行脚本。"
        exit 0
    else
        echo "更新失败，请检查网络或手动更新。"
    fi
}

# 主控制函数
main() {
    if [ "$1" = "--run-scheduled" ]; then
        run_scheduled_job
        exit $?
    fi

    trap cleanup INT TERM
    check_dependencies
    
    while true; do
        show_menu
        read -p "请输入选项(1-9): " option
        
        case $option in
            1) select_region ;;
            2) read -p "输入要消耗的流量(GB): " LIMIT_GB ;;
            3) read -p "输入线程数量: " THREADS ;;
            4) start_download ;;
            5) cleanup ;;  # 退出
            6) update_vpsshua ;;
            7) configure_daily_schedule ;;
            8) remove_daily_schedule ;;
            9) show_daily_schedule_status ;;
            *) echo "无效选项，请重新输入" ;;
        esac
    done
}

# 开始下载
start_download() {
    [ ${#SELECTED_URLS[@]} -eq 0 ] && { echo "请先选择资源！"; return; }
    
    rm -f "$STAT_FILE" "$STOP_FILE"
    TOTAL_BYTES=0
    REQUEST_COUNT=0
    START_TIME=$(date +%s)
    
    echo "开始下载，按Ctrl+C停止..."
    
    # 启动下载线程
    for ((i=0; i<THREADS; i++)); do
        for url in "${SELECTED_URLS[@]}"; do
            download_task "$url" &
        done
    done
    
    # 监控进度
    while true; do
        if [ -f "$STAT_FILE" ]; then
            TOTAL_BYTES=$(awk '{sum+=$1} END{print sum}' "$STAT_FILE" 2>/dev/null || echo 0)
            REQUEST_COUNT=$(wc -l < "$STAT_FILE" 2>/dev/null || echo 0)
            
            # 检查限制
            LIMIT_BYTES=$(echo "$LIMIT_GB * 1073741824" | bc)
            if (( $(echo "$TOTAL_BYTES >= $LIMIT_BYTES" | bc -l) )); then
                touch "$STOP_FILE"
                break
            fi
            
            # 显示状态
            printf "\r状态: %-10s | 请求: %-6d | 线程: %-2d | 运行: %-4ds" \
                "$(format_bytes $TOTAL_BYTES)" \
                "$REQUEST_COUNT" \
                "$THREADS" \
                "$(( $(date +%s) - START_TIME ))"
        fi
        sleep 1
    done
    
    wait
    echo -e "\n\n报告MJJ|流量任务完成！！！"
    echo "总消耗流量: $(format_bytes $TOTAL_BYTES)"
    echo "总请求次数: $REQUEST_COUNT"
    echo "运行时间: $(( $(date +%s) - START_TIME ))秒"
    echo "======================================"
    echo -e "${RED}        感谢使用|VPSShua|在线要饭        "
    echo -e "U(Tron)：TAKzggBPqf3NmnnJRyKXkT7HduRg999999"
    echo -e "U(Polygon)：0x03ee741aA4cEa38Fd96851995271745BE99FF098${RESET}"
    echo "======================================"
    echo "恰饭广告：联系我们投放广告|TG：baolihou"
    echo "速翻翻|因为专注|所以专业：SUFANFAN.COM"
    echo "======================================"
}

# 启动脚本
main "$@"
