#!/bin/bash

#=================================================================================
# Linux Swap 内存管理脚本 (V4)
# 功能: 创建、删除、查看 Swap 分区（使用文件），自动处理权限、挂载和开机启动。
# 修改: 默认不进行任何备份。仅在删除 Swap 文件时，询问是否备份该文件。
#=================================================================================

# --- 配置 ---
readonly SWAP_FILE="/swapfile"

# --- 颜色定义 ---
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD_WHITE='\033[1;37m'

# --- 辅助函数 ---

print_message() { local color="$1"; local message="$2"; echo -e "${color}${message}${COLOR_RESET}"; }
print_step() { local current=$1; local total=$2; local description=$3; print_message "$COLOR_CYAN" "[${current}/${total}] ${description}..."; }
print_success() { print_message "$COLOR_GREEN" "✅ 操作成功: $1"; }
print_error() { print_message "$COLOR_RED" "❌ 操作失败: $1"; }
print_warning() { print_message "$COLOR_YELLOW" "⚠️ 警告: $1"; }

# 确认操作函数 (默认 No)
confirm_action() {
    local prompt="$1"
    local choice
    while true; do
        # 默认是 N (No)
        read -p "$(print_message "$COLOR_YELLOW" "${prompt} [y/N]: ")" choice
        choice="${choice:-N}" # 如果用户直接回车，默认为 N

        if [[ "$choice" =~ ^[Yy]$ ]]; then
            return 0 # Yes
        elif [[ "$choice" =~ ^[Nn]$ ]]; then
            return 1 # No
        else
            print_error "输入无效，请输入 'y' 或 'n'."
        fi
    done
}

# 检查 Root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_warning "当前用户非 root，脚本需要 root 权限执行。"
        print_message "$COLOR_YELLOW" "尝试使用 sudo 权限重新运行..."
        exec sudo bash "$0" "$@"
        print_error "无法获取 root 权限，脚本终止。"
        exit 1
    fi
}

# 检查 Swap 状态
check_swap_status() {
    print_message "$COLOR_BLUE" "\n--- 当前 Swap 状态 ---"
    local swap_info
    swap_info=$(swapon --show)
    if [[ -z "$swap_info" ]]; then
        print_warning "当前系统没有检测到活动的 Swap 分区或文件。"
        return 1
    else
        print_message "$COLOR_GREEN" "检测到活动的 Swap:"
        swapon --show | column -t
        echo ""
        print_message "$COLOR_GREEN" "Swap 内存使用情况:"
        free -h | grep -i swap
        return 0
    fi
}

# 检查 fstab 条目
check_fstab() {
    local file_to_check="$1"
    # 精确匹配 fstab 中的 swap 条目
    if grep -q "^\s*${file_to_check}\s\+none\s\+swap\s\+sw\s\+0\s\+0" /etc/fstab; then
        return 0 # 存在
    else
        return 1 # 不存在
    fi
}

# --- 主要功能函数 ---

# 创建 Swap 文件
create_swap() {
    print_message "$COLOR_BOLD_WHITE" "\n--- 1. 创建 Swap 分区 ($SWAP_FILE) ---"
    # 检查存在性和活动状态
    if [[ -f "$SWAP_FILE" ]]; then print_error "'$SWAP_FILE' 已存在。"; return 1; fi
    if swapon --show | grep -q "$SWAP_FILE"; then print_error "'$SWAP_FILE' 已激活。"; return 1; fi

    # 获取大小并验证
    local size_gb
    while true; do
        read -p "$(print_message "$COLOR_YELLOW" "请输入要创建的 Swap 大小（单位 G，例如输入 2 表示 2G）: ")" size_gb
        if [[ "$size_gb" =~ ^[1-9][0-9]*$ ]]; then
            # 检查磁盘空间
            local required_kb=$((size_gb * 1024 * 1024))
            local target_dir=$(dirname "$SWAP_FILE")
            local available_kb=$(df "$target_dir" | awk 'NR==2 {print $4}')
            if [[ "$available_kb" -lt "$required_kb" ]]; then
                 local available_gb=$(awk "BEGIN {printf \"%.2f\", $available_kb / 1024 / 1024}")
                 print_warning "目标路径 '$target_dir' 磁盘空间不足 (需 ${size_gb}G, 可用 ~${available_gb}G)。"
                 confirm_action "是否仍尝试创建？" || { print_message "$COLOR_YELLOW" "操作取消。"; return 1; }
            fi
            break # 输入有效，空间足够或用户确认继续
        else print_error "输入无效，请输入正整数。"; fi
    done

    print_message "$COLOR_CYAN" "准备创建 ${size_gb}G Swap 文件 '$SWAP_FILE'..."
    local total_steps=6 # 更新总步骤数

    # 1. 分配空间
    print_step 1 $total_steps "分配空间"
    if ! fallocate -l "${size_gb}G" "$SWAP_FILE"; then
        print_warning "fallocate 失败，尝试 dd (可能较慢)"
        local count=$((size_gb * 1024))
        if ! dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$count" status=progress; then
             print_error "dd 创建失败。"; rm -f "$SWAP_FILE"; return 1; fi
    fi; print_success "空间分配成功。"

    # 2. 设置权限
    print_step 2 $total_steps "设置权限 (600)"
    if ! chmod 600 "$SWAP_FILE"; then print_error "权限设置失败。"; rm -f "$SWAP_FILE"; return 1; fi
    print_success "权限设置成功。"

    # 3. 格式化
    print_step 3 $total_steps "格式化 (mkswap)"
    if ! mkswap "$SWAP_FILE"; then print_error "格式化失败。"; rm -f "$SWAP_FILE"; return 1; fi
    print_success "格式化成功。"

    # 4. 启用
    print_step 4 $total_steps "启用 (swapon)"
    if ! swapon "$SWAP_FILE"; then print_error "启用失败。"; rm -f "$SWAP_FILE"; return 1; fi
    print_success "启用成功。"

    # 5. 添加到 fstab (无备份提示)
    print_step 5 $total_steps "配置开机自启 (/etc/fstab)"
    if check_fstab "$SWAP_FILE"; then
        print_warning "'$SWAP_FILE' 的条目已存在于 /etc/fstab，跳过添加。"
    else
        print_message "$COLOR_CYAN" "正在将 Swap 条目添加到 /etc/fstab..."
        # 直接添加，不备份
        if echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab; then
            print_success "成功添加 Swap 条目到 /etc/fstab。"
        else
            print_error "无法写入 /etc/fstab。请检查权限或手动添加以下行："
            print_message "$COLOR_YELLOW" "$SWAP_FILE none swap sw 0 0"
            print_warning "Swap 当前已激活，但开机自启配置失败。"
        fi
    fi

    # 6. 显示状态
    print_step 6 $total_steps "操作完成"
    check_swap_status
    print_message "$COLOR_BOLD_WHITE" "\n🎉 Swap 文件 '$SWAP_FILE' (${size_gb}G) 创建并启用成功！"
}

# 删除 Swap 文件
delete_swap() {
    print_message "$COLOR_BOLD_WHITE" "\n--- 2. 删除 Swap 分区 ($SWAP_FILE) ---"

    # 检查文件是否存在
    if [[ ! -f "$SWAP_FILE" ]]; then
        print_error "指定的 Swap 文件 '$SWAP_FILE' 不存在。"
        # 检查是否有残留 fstab 条目 (不提示备份，直接询问是否移除)
        if check_fstab "$SWAP_FILE"; then
            print_warning "'$SWAP_FILE' 的条目仍存在于 /etc/fstab 中。"
            if confirm_action "是否尝试自动从 /etc/fstab 中移除该残留条目？"; then
                print_message "$COLOR_CYAN" "正在尝试移除残留的 fstab 条目..."
                # 使用 sed 直接删除，不备份
                if sed -i "\|^\s*${SWAP_FILE}\s\+none\s\+swap\s\+sw\s\+0\s\+0|d" /etc/fstab; then
                    print_success "成功移除残留的 fstab 条目。"
                else
                    print_error "自动移除残留 fstab 条目失败，请手动编辑。"
                fi
            else
                print_message "$COLOR_YELLOW" "请手动编辑 /etc/fstab 清理残留条目。"
            fi
        fi
        return 1
    fi

    # --- 询问是否备份 Swap 文件本身 ---
    local backup_swap_file_path="" # 用于存储备份路径
    print_message "$COLOR_BLUE" "\n--- Swap 文件备份确认 (可选) ---"
    print_warning "Swap 文件通常包含临时数据，备份它一般没有必要。"
    if confirm_action "删除操作会移除 '$SWAP_FILE'。是否要在删除前对其进行备份？"; then
        # 用户选择备份
        local default_backup_path="/tmp/swapfile_backup_$(date +%Y%m%d_%H%M%S)"
        read -p "$(print_message "$COLOR_YELLOW" "请输入备份文件的完整路径 [${default_backup_path}]: ")" backup_path
        backup_path="${backup_path:-$default_backup_path}" # 使用默认或用户输入

        # 尝试创建备份目录
        local backup_dir=$(dirname "$backup_path")
        if [[ ! -d "$backup_dir" ]]; then
            if ! mkdir -p "$backup_dir"; then
                print_error "创建备份目录 '$backup_dir' 失败。"
                # 备份失败，询问是否继续删除
                confirm_action "备份失败，是否仍要继续删除 Swap 文件（不备份）？" || {
                     print_message "$COLOR_YELLOW" "删除操作已取消。"; return 1;
                }
                # 如果继续，则 backup_swap_file_path 保持为空
            fi
        fi

        # 如果目录创建成功或已存在，尝试备份
        if [[ -d "$backup_dir" ]]; then
             print_message "$COLOR_CYAN" "尝试将 '$SWAP_FILE' 备份到 '$backup_path'..."
             if cp -a "$SWAP_FILE" "$backup_path"; then
                 print_success "Swap 文件已成功备份到 '$backup_path'"
                 backup_swap_file_path="$backup_path" # 记录成功的备份路径
             else
                 print_error "备份 Swap 文件到 '$backup_path' 失败。"
                 # 备份失败，询问是否继续删除
                 confirm_action "备份失败，是否仍要继续删除 Swap 文件（不备份）？" || {
                      print_message "$COLOR_YELLOW" "删除操作已取消。"; return 1;
                 }
                 # 如果继续，则 backup_swap_file_path 保持为空
             fi
        fi
    else
        # 用户选择不备份
        print_message "$COLOR_YELLOW" "已选择不备份 Swap 文件。"
    fi
    # --- 备份询问结束 ---

    # 最终确认删除
    print_message "$COLOR_BLUE" "\n--- 执行删除确认 ---"
    print_warning "即将执行以下删除步骤："
    print_warning "  1. 停用 Swap 文件 '$SWAP_FILE' (如果活动)。"
    print_warning "  2. 从 /etc/fstab 中移除自动挂载条目 (如果存在)。"
    print_warning "  3. 删除 Swap 文件 '$SWAP_FILE'。"
    print_warning "确保系统有足够的物理内存容纳 Swap 内容，否则可能导致系统不稳定。"
    confirm_action "确定要继续执行删除操作吗？" || {
        print_message "$COLOR_YELLOW" "删除操作已取消。"
        # 如果之前意外备份成功了，提醒一下
        if [[ -n "$backup_swap_file_path" ]]; then
            print_warning "请注意：之前创建的 Swap 文件备份位于: $backup_swap_file_path"
        fi
        return 1
    }

    local total_steps=3
    local success=true

    # 1. 停用 Swap
    print_step 1 $total_steps "停用 Swap (swapoff)"
    if swapon --show | grep -q "$SWAP_FILE"; then
        if ! swapoff "$SWAP_FILE"; then
            print_error "停用 Swap '$SWAP_FILE' 失败 (可能内存不足)。"
            print_warning "删除操作中止以保护系统。"
             if [[ -n "$backup_swap_file_path" ]]; then print_warning "Swap 文件备份位于: $backup_swap_file_path"; fi
            return 1 # 停用失败是严重问题，中止
        fi
        print_success "Swap 文件已停用。"
    else
        print_message "$COLOR_YELLOW" "'$SWAP_FILE' 当前未激活。"
    fi

    # 2. 从 fstab 移除条目 (无备份提示)
    print_step 2 $total_steps "处理 /etc/fstab 条目"
    if check_fstab "$SWAP_FILE"; then
        print_message "$COLOR_CYAN" "正在从 /etc/fstab 移除 '$SWAP_FILE' 条目..."
        # 直接移除，不备份
        if sed -i "\|^\s*${SWAP_FILE}\s\+none\s\+swap\s\+sw\s\+0\s\+0|d" /etc/fstab; then
            print_success "成功从 /etc/fstab 移除条目。"
        else
            print_error "自动移除 fstab 条目失败，请手动编辑。"
            success=false # 标记操作有部分失败
        fi
    else
        print_message "$COLOR_YELLOW" "/etc/fstab 中未找到 '$SWAP_FILE' 条目，无需移除。"
    fi

    # 3. 删除物理文件
    print_step 3 $total_steps "删除 Swap 文件 (rm)"
    if rm -f "$SWAP_FILE"; then
        print_success "Swap 文件 '$SWAP_FILE' 已删除。"
    else
        print_error "删除 Swap 文件 '$SWAP_FILE' 失败。请检查权限或手动删除。"
        success=false # 标记操作有部分失败
    fi

    # 总结
    print_message "$COLOR_CYAN" "\n--- 删除操作总结 ---"
    if [[ "$success" = true ]]; then
         print_message "$COLOR_BOLD_WHITE" "✅ Swap 删除操作已完成。"
    else
         print_warning "⚠️ Swap 删除操作已完成，但过程中遇到问题。请检查日志。"
    fi
    # 如果用户之前选择了备份且成功了，提醒路径
    if [[ -n "$backup_swap_file_path" ]]; then
        print_message "$COLOR_YELLOW" "之前请求的 Swap 文件备份位于: $backup_swap_file_path"
    fi
    check_swap_status # 显示最终状态
}

# 显示 Swap 详情 (与 V3 相同)
show_details() {
    print_message "$COLOR_BOLD_WHITE" "\n--- 3. 查看 Swap 详情 ---"
    check_swap_status
    print_message "$COLOR_BLUE" "\n--- /etc/fstab 中的 Swap 配置 ---"
    if grep -P '^\s*[^#].*\s+swap\s+' /etc/fstab > /dev/null; then
        print_message "$COLOR_GREEN" "fstab 中找到的 Swap 配置行:"
        grep --color=always -P '^\s*[^#].*\s+swap\s+' /etc/fstab
    else
        print_warning "fstab 中未找到活动的 'swap' 配置。"
    fi
    print_message "$COLOR_BLUE" "\n--- 脚本管理的 Swap 文件 '$SWAP_FILE' 状态 ---"
    if [[ -f "$SWAP_FILE" ]]; then print_message "$COLOR_GREEN" "'$SWAP_FILE' 文件存在。"; ls -lh "$SWAP_FILE";
    else print_warning "'$SWAP_FILE' 文件不存在。"; fi
    if check_fstab "$SWAP_FILE"; then print_message "$COLOR_GREEN" "'$SWAP_FILE' 的 fstab 条目存在。";
    else print_warning "'$SWAP_FILE' 的 fstab 条目不存在。"; fi
    echo
}

# 显示主菜单 (与 V3 相同)
show_menu() {
    clear
    print_message "$COLOR_CYAN" "==============================================="
    print_message "$COLOR_BOLD_WHITE" "  Linux Swap 内存管理脚本 (管理: $SWAP_FILE)"
    print_message "$COLOR_CYAN" "==============================================="
    print_message "$COLOR_GREEN" "  1. 创建 Swap 分区"
    print_message "$COLOR_RED"   "  2. 删除 Swap 分区"
    print_message "$COLOR_BLUE"  "  3. 查看 Swap 详情"
    print_message "$COLOR_YELLOW" "  4. 退出脚本"
    print_message "$COLOR_CYAN" "-----------------------------------------------"
    # 状态显示
    if [[ -f "$SWAP_FILE" ]]; then
        local size=$(ls -lh "$SWAP_FILE" 2>/dev/null | awk '{print $5}') size=${size:-未知}
        local status_fstab="未配置自启"; if check_fstab "$SWAP_FILE"; then status_fstab="已配置自启"; fi
        local status_active="未激活"; if swapon --show | grep -q "$SWAP_FILE"; then status_active="活动中"; fi
        print_message "$COLOR_GREEN" "  当前 '$SWAP_FILE': 存在 ($size), $status_active, $status_fstab"
    else
         print_message "$COLOR_YELLOW" "  当前 '$SWAP_FILE': 不存在"
    fi
     print_message "$COLOR_CYAN" "-----------------------------------------------"
}

# --- 主逻辑 ---
check_root "$@" # 检查 root 权限

while true; do
    show_menu
    read -p "$(print_message "$COLOR_YELLOW" "请输入选项 [1-4]: ")" choice
    case "$choice" in
        1) create_swap ;;
        2) delete_swap ;;
        3) show_details ;;
        4) print_message "$COLOR_CYAN" "\n脚本退出。"; exit 0 ;;
        *) print_error "无效选项。" ;;
    esac
    # 等待用户按键继续
    read -n 1 -s -r -p "$(print_message "$COLOR_YELLOW" "\n按任意键返回主菜单...")"; echo
done

exit 0
