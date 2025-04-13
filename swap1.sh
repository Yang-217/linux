#!/bin/bash

# ==============================================================================
# 脚本名称: swap.sh
# 脚本功能: 提供菜单式操作，用于在 Linux 系统中添加、删除、查看 Swap 交换文件。
# 特点:    自动检查 root 权限 (提示 sudo), GB 单位输入, fstab 管理, 中文界面。
# ==============================================================================

# --- 全局配置 ---
# 默认管理的 Swap 文件路径 (脚本将主要操作这个文件)
# !! 重要: 如果你要管理其他 swap 文件，需要修改此脚本或手动操作 !!
SWAP_FILE="/swapfile"
FSTAB_FILE="/etc/fstab"

# --- 颜色定义 (需要 tput) ---
# 检查 tput 是否可用，否则禁用颜色
if command -v tput &> /dev/null && tty -s; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    BOLD=""
    RESET=""
fi

# --- 工具函数 ---

# 打印带颜色的消息
# $1: 颜色变量 (e.g., $GREEN)
# $2: 消息文本
print_color() {
    echo -e "${1}${2}${RESET}"
}

# 打印分隔线
print_separator() {
    echo "${BLUE}============================================================${RESET}"
}

# 等待用户按键继续
press_any_key_to_continue() {
    echo ""
    read -n 1 -s -r -p "${YELLOW}按任意键返回主菜单...${RESET}"
    echo ""
}

# --- 核心功能函数 ---

# 1. 添加 Swap 分区 (文件)
add_swap() {
    print_separator
    print_color "$CYAN" "   Swap 添加向导"
    print_separator

    # 检查 Swap 文件是否已存在
    if [[ -e "$SWAP_FILE" ]]; then
        print_color "$YELLOW" "警告: Swap 文件 '$SWAP_FILE' 已经存在。"
        print_color "$YELLOW" "       如果需要重新创建，请先使用菜单中的 '删除 Swap' 功能。"
        press_any_key_to_continue
        return
    fi
    # 检查 fstab 中是否已有此文件的条目 (防止残留配置)
    if grep -qF "$SWAP_FILE" "$FSTAB_FILE"; then
        print_color "$YELLOW" "警告: '$SWAP_FILE' 的配置已存在于 $FSTAB_FILE 中。"
        print_color "$YELLOW" "       请先使用 '删除 Swap' 功能清理配置，或手动编辑 $FSTAB_FILE。"
        press_any_key_to_continue
        return
    fi

    # 获取用户输入的大小 (GB)
    while true; do
        read -p "${GREEN}请输入要创建的 Swap 大小 (单位 GB, 仅整数): ${RESET}" size_gb
        if [[ "$size_gb" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            print_color "$RED" "错误: 请输入一个有效的正整数 (例如: 4 表示 4GB)。"
        fi
    done

    local size_mb=$((size_gb * 1024))
    print_color "$BLUE" "计划创建 Swap 大小: ${size_gb} GB (${size_mb} MB)"
    print_color "$BLUE" "Swap 文件路径: $SWAP_FILE"

    # 检查磁盘空间
    print_color "$MAGENTA" "正在检查磁盘空间..."
    local target_dir=$(dirname "$SWAP_FILE")
    local available_kb=$(df -k "$target_dir" | awk 'NR==2 {print $4}')
    local required_kb=$((size_mb * 1024))

    if [[ "$available_kb" -lt "$required_kb" ]]; then
        local available_mb=$((available_kb / 1024))
        print_color "$RED" "错误: 磁盘空间不足！"
        print_color "$RED" "  需要空间: ${size_mb} MB"
        print_color "$RED" "  可用空间: ${available_mb} MB (在 '$target_dir')"
        press_any_key_to_continue
        return
    fi
    print_color "$GREEN" "磁盘空间充足。"

    # 创建 Swap 文件
    print_color "$MAGENTA" "正在创建 Swap 文件 (大小: ${size_gb} GB)..."
    if command -v fallocate &> /dev/null; then
        print_color "$BLUE" "使用 fallocate (推荐)..."
        fallocate -l "${size_gb}G" "$SWAP_FILE"
        if [[ $? -ne 0 ]]; then
            print_color "$YELLOW" "fallocate 失败，尝试使用 dd (可能较慢)..."
            rm -f "$SWAP_FILE" # 清理失败的 fallocate 文件
            dd if=/dev/zero of="$SWAP_FILE" bs=1G count="$size_gb" status=progress
            if [[ $? -ne 0 ]]; then
                print_color "$RED" "错误: 使用 dd 创建 Swap 文件失败。"
                rm -f "$SWAP_FILE" # 清理失败的 dd 文件
                press_any_key_to_continue
                return
            fi
        fi
    else
        print_color "$YELLOW" "未找到 fallocate，使用 dd (可能较慢)..."
        dd if=/dev/zero of="$SWAP_FILE" bs=1G count="$size_gb" status=progress
         if [[ $? -ne 0 ]]; then
            print_color "$RED" "错误: 使用 dd 创建 Swap 文件失败。"
            rm -f "$SWAP_FILE"
            press_any_key_to_continue
            return
        fi
    fi
    print_color "$GREEN" "Swap 文件创建成功。"

    # 设置权限
    print_color "$MAGENTA" "设置文件权限 (600)..."
    chmod 600 "$SWAP_FILE"
    if [[ $? -ne 0 ]]; then
        print_color "$RED" "错误: 设置权限失败。"
        rm -f "$SWAP_FILE"
        press_any_key_to_continue
        return
    fi
    print_color "$GREEN" "权限设置成功。"

    # 格式化 Swap
    print_color "$MAGENTA" "格式化为 Swap 空间 (mkswap)..."
    mkswap "$SWAP_FILE"
    if [[ $? -ne 0 ]]; then
        print_color "$RED" "错误: mkswap 格式化失败。"
        rm -f "$SWAP_FILE"
        press_any_key_to_continue
        return
    fi
    print_color "$GREEN" "格式化成功。"

    # 启用 Swap
    print_color "$MAGENTA" "启用 Swap (swapon)..."
    swapon "$SWAP_FILE"
    if [[ $? -ne 0 ]]; then
        print_color "$RED" "错误: 启用 Swap (swapon) 失败。"
        # 可能需要手动检查系统日志
        press_any_key_to_continue
        return
    fi
    print_color "$GREEN" "Swap 已启用。"

    # 添加到 fstab 实现持久化
    print_color "$MAGENTA" "添加到 $FSTAB_FILE 实现开机自启..."
    local fstab_entry="$SWAP_FILE none swap sw 0 0"
    # 再次检查，以防万一在操作过程中被其他进程添加
    if grep -qF "$SWAP_FILE" "$FSTAB_FILE"; then
        print_color "$YELLOW" "警告: '$SWAP_FILE' 的条目已存在于 $FSTAB_FILE，跳过添加。"
    else
        # 备份 fstab
        local backup_fstab="${FSTAB_FILE}.bak_swap_$(date +%Y%m%d_%H%M%S)"
        cp "$FSTAB_FILE" "$backup_fstab"
        if [[ $? -eq 0 ]]; then
            print_color "$GREEN" "已备份 $FSTAB_FILE 到 $backup_fstab"
        else
            print_color "$YELLOW" "警告: 备份 $FSTAB_FILE 失败，但仍会尝试添加条目。"
        fi
        # 添加条目
        echo "$fstab_entry" >> "$FSTAB_FILE"
        if [[ $? -ne 0 ]]; then
            print_color "$RED" "错误: 自动添加条目到 $FSTAB_FILE 失败！"
            print_color "$RED" "请手动添加以下行到 $FSTAB_FILE :"
            print_color "$RED" "  $fstab_entry"
        else
            print_color "$GREEN" "成功添加条目到 $FSTAB_FILE。"
        fi
    fi

    print_color "$GREEN" "Swap 添加流程完成！"
    press_any_key_to_continue
}

# 2. 删除 Swap 分区 (文件)
delete_swap() {
    print_separator
    print_color "$CYAN" "  Swap 删除向导"
    print_separator
    print_color "$YELLOW" "本操作将尝试禁用、移除 fstab 配置并删除 Swap 文件: $SWAP_FILE"

    local swap_active=false
    local fstab_configured=false
    local file_exists=false

    # 检查 Swap 是否活动
    if swapon --show | grep -qF "$SWAP_FILE"; then
        swap_active=true
        print_color "$MAGENTA" "检测到 Swap '$SWAP_FILE' 当前处于活动状态。"
    fi

    # 检查 fstab 配置
    if grep -qF "$SWAP_FILE" "$FSTAB_FILE"; then
        fstab_configured=true
        print_color "$MAGENTA" "检测到 '$SWAP_FILE' 的配置存在于 $FSTAB_FILE。"
    fi

    # 检查文件是否存在
    if [[ -e "$SWAP_FILE" ]]; then
        file_exists=true
        print_color "$MAGENTA" "检测到 Swap 文件 '$SWAP_FILE' 存在。"
    fi

    if ! $swap_active && ! $fstab_configured && ! $file_exists; then
        print_color "$GREEN" "指定的 Swap 文件 '$SWAP_FILE' 或其配置似乎不存在，无需删除。"
        press_any_key_to_continue
        return
    fi

    read -p "${BOLD}${RED}确定要执行删除操作吗？(y/N): ${RESET}" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_color "$BLUE" "操作已取消。"
        press_any_key_to_continue
        return
    fi

    # 禁用 Swap
    if $swap_active; then
        print_color "$MAGENTA" "正在禁用 Swap (swapoff)..."
        swapoff "$SWAP_FILE"
        if [[ $? -eq 0 ]]; then
            print_color "$GREEN" "Swap 禁用成功。"
        else
            print_color "$RED" "错误: 禁用 Swap '$SWAP_FILE' 失败。请手动检查。"
            # 即使失败也尝试继续后续清理步骤
        fi
    fi

    # 移除 fstab 条目
    if $fstab_configured; then
        print_color "$MAGENTA" "正在从 $FSTAB_FILE 移除配置..."
        # 备份 fstab
        local backup_fstab="${FSTAB_FILE}.bak_swap_del_$(date +%Y%m%d_%H%M%S)"
        cp "$FSTAB_FILE" "$backup_fstab"
        if [[ $? -eq 0 ]]; then
            print_color "$GREEN" "已备份 $FSTAB_FILE 到 $backup_fstab"
        else
            print_color "$YELLOW" "警告: 备份 $FSTAB_FILE 失败，但仍会尝试移除条目。"
        fi

        # 使用 sed 安全地删除包含 SWAP_FILE 的行 (使用 # 作为分隔符避免路径中的 /)
        sed -i.swap_tmp -e "#^${SWAP_FILE}[[:space:]]#d" "$FSTAB_FILE"
        # -i.swap_tmp 会创建一个备份文件 fstab.swap_tmp
        if [[ $? -eq 0 ]]; then
            print_color "$GREEN" "成功从 $FSTAB_FILE 移除条目。"
            rm -f "${FSTAB_FILE}.swap_tmp" # 删除 sed 创建的临时备份
        else
            print_color "$RED" "错误: 自动从 $FSTAB_FILE 移除条目失败！"
            print_color "$RED" "请手动编辑 $FSTAB_FILE 并删除包含 '$SWAP_FILE' 的行。"
            # 还原备份可能更安全，但这里选择提示用户手动操作
            # mv "${FSTAB_FILE}.swap_tmp" "$FSTAB_FILE" # 还原 sed 的备份
        fi
    fi

    # 删除 Swap 文件
    if $file_exists; then
        print_color "$MAGENTA" "正在删除 Swap 文件 '$SWAP_FILE'..."
        rm -f "$SWAP_FILE"
        if [[ $? -eq 0 ]]; then
            print_color "$GREEN" "Swap 文件删除成功。"
        else
            print_color "$RED" "错误: 删除 Swap 文件 '$SWAP_FILE' 失败。请手动删除。"
        fi
    fi

    print_color "$GREEN" "Swap 删除流程完成！"
    press_any_key_to_continue
}

# 3. 显示 Swap 分区详情
show_swap_info() {
    print_separator
    print_color "$CYAN" "  当前 Swap 状态详情"
    print_separator

    print_color "$BLUE" "--- 活动 Swap 列表 (swapon --show) ---"
    swapon --show
    if [[ $? -ne 0 || -z "$(swapon --show)" ]]; then
        print_color "$YELLOW" "  (当前没有活动的 Swap)"
    fi
    echo ""

    print_color "$BLUE" "--- 内存与 Swap 使用概览 (free -h) ---"
    free -h
    echo ""

    print_color "$BLUE" "--- /proc/swaps 内容 ---"
    if [[ -e /proc/swaps ]]; then
        cat /proc/swaps
    else
        print_color "$YELLOW" "  (/proc/swaps 文件不存在)"
    fi
    echo ""

    print_color "$BLUE" "--- $FSTAB_FILE 中相关的 Swap 配置 ---"
    if grep -i 'swap' "$FSTAB_FILE"; then
        grep -i --color=always 'swap' "$FSTAB_FILE"
    else
         print_color "$YELLOW" "  (在 $FSTAB_FILE 中未找到 'swap' 相关的配置行)"
    fi

    press_any_key_to_continue
}

# --- 主菜单显示函数 ---
display_menu() {
    clear # 清屏
    print_separator
    print_color "$BOLD$CYAN" "    Linux Swap 管理脚本 (管理对象: $SWAP_FILE)"
    print_separator
    print_color "$GREEN" "  1. 创建并启用 Swap (输入大小 GB)"
    print_color "$RED" "  2. 删除 Swap (禁用, 移除配置, 删除文件)"
    print_color "$YELLOW" "  3. 查看当前 Swap 详情"
    print_color "$MAGENTA" "  4. 退出脚本"
    print_separator
    read -p "${BOLD}请输入选项编号 (1-4): ${RESET}" choice
}

# --- 主逻辑 ---

# 首先检查并获取 root 权限
if [[ "$(id -u)" -ne 0 ]]; then
   print_color "$YELLOW" "提示: 需要 root 权限来执行 Swap 操作。"
   # 尝试使用 sudo 重新执行脚本本身
   # "$0" 是当前脚本的路径, "$@" 会传递所有原始参数 (虽然此脚本菜单模式下通常不带参数)
   print_color "$BLUE" "正在尝试使用 sudo 重新运行..."
   sudo "$0" "$@"
   # sudo 执行后的退出码会传递给父进程
   exit $? # 退出原始的非 root 进程
fi

# 如果已经是 root 或 sudo 成功，则继续执行
print_color "$GREEN" "当前用户具有 root 权限，脚本可以继续执行。"
sleep 1 # 短暂停顿

# 主循环
while true; do
    display_menu
    case "$choice" in
        1)
            add_swap
            ;;
        2)
            delete_swap
            ;;
        3)
            show_swap_info
            ;;
        4)
            print_color "$BLUE" "正在退出脚本..."
            print_separator
            break # 跳出 while 循环
            ;;
        *)
            print_color "$RED" "无效的选项 '$choice'，请输入 1 到 4 之间的数字。"
            sleep 1.5 # 给用户时间看错误提示
            ;;
    esac
done

exit 0
