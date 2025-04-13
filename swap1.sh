#!/bin/bash

#=================================================================================
# Linux Swap 内存管理脚本 (V3)
# 功能: 创建、删除、查看 Swap 分区（使用文件），自动处理权限、挂载和开机启动。
# 修改: 移除 fstab 自动备份，改为操作前询问是否备份 fstab。
# 保留: 删除前询问是否备份 Swap 文件本身。
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

# 确认操作函数
# $1: 提示信息
# $2: 默认选项 (可选, Y 或 N)
confirm_action() {
    local prompt="$1"
    local default_choice="$2"
    local choice
    local options="[y/N]" # 默认不执行
    local default_return=1 # 默认返回 1 (No)

    if [[ "$default_choice" =~ ^[Yy]$ ]]; then
        options="[Y/n]"
        default_return=0 # 默认返回 0 (Yes)
    fi

    while true; do
        read -p "$(print_message "$COLOR_YELLOW" "${prompt} ${options}: ")" choice
        choice="${choice:-$default_choice}" # 如果用户直接回车，使用默认值

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
    if grep -q "^\s*${file_to_check}\s\+none\s\+swap\s\+sw\s\+" /etc/fstab; then
        return 0 # 存在
    else
        return 1 # 不存在
    fi
}

# 备份文件函数
# $1: 要备份的文件
# $2: 备份文件名前缀 (可选)
backup_file() {
    local file_to_backup="$1"
    local prefix="${2:-backup}" # 默认前缀为 backup
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${file_to_backup}.${prefix}_${timestamp}"

    if cp -a "$file_to_backup" "$backup_path"; then
        print_success "文件 '$file_to_backup' 已成功备份到 '$backup_path'"
        return 0
    else
        print_error "备份文件 '$file_to_backup' 到 '$backup_path' 失败。"
        return 1
    fi
}

# --- 主要功能函数 ---

# 创建 Swap 文件
create_swap() {
    print_message "$COLOR_BOLD_WHITE" "\n--- 1. 创建 Swap 分区 ($SWAP_FILE) ---"
    # ... (检查文件存在、活动状态、获取大小、检查磁盘空间的代码与 V2 相同) ...
    if [[ -f "$SWAP_FILE" ]]; then print_error "'$SWAP_FILE' 已存在。"; return 1; fi
    if swapon --show | grep -q "$SWAP_FILE"; then print_error "'$SWAP_FILE' 已激活。"; return 1; fi
    local size_gb
    while true; do
        read -p "$(print_message "$COLOR_YELLOW" "请输入 Swap 大小 (GB): ")" size_gb
        if [[ "$size_gb" =~ ^[1-9][0-9]*$ ]]; then
            local required_kb=$((size_gb * 1024 * 1024))
            local available_kb=$(df "$(dirname "$SWAP_FILE")" | awk 'NR==2 {print $4}')
            if [[ "$available_kb" -lt "$required_kb" ]]; then
                 local available_gb=$(awk "BEGIN {printf \"%.2f\", $available_kb / 1024 / 1024}")
                 print_warning "磁盘空间不足 (需 ${size_gb}G, 可用 ~${available_gb}G)。"
                 confirm_action "是否仍尝试创建？" "N" || { print_message "$COLOR_YELLOW" "操作取消。"; return 1; }
            fi
            break
        else print_error "输入无效，请输入正整数。"; fi
    done
    print_message "$COLOR_CYAN" "准备创建 ${size_gb}G Swap 文件 '$SWAP_FILE'..."
    local total_steps=6

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

    # 5. 处理 fstab (修改点)
    print_step 5 $total_steps "配置开机自启 (/etc/fstab)"
    if check_fstab "$SWAP_FILE"; then
        print_warning "'$SWAP_FILE' 的条目已存在于 /etc/fstab，跳过添加。"
    else
        print_message "$COLOR_YELLOW" "检测到 '$SWAP_FILE' 的条目不存在于 /etc/fstab。"
        if confirm_action "是否要将此 Swap 添加到 /etc/fstab 以实现开机自动挂载？" "Y"; then
            # 确认添加后，询问是否备份 fstab
            if confirm_action "是否在修改 /etc/fstab 前对其进行备份？(推荐)" "Y"; then
                if ! backup_file "/etc/fstab" "fstab"; then
                    # 如果备份失败，让用户决定是否继续
                    confirm_action "备份 /etc/fstab 失败，是否仍要继续添加条目？" "N" || {
                        print_warning "已取消向 /etc/fstab 添加条目。Swap 当前已激活，但重启后不会自动挂载。"
                        # 注意：这里不 return，只是不添加 fstab 条目，前面步骤已完成
                        return 0 # 算创建成功，只是没加fstab
                    }
                     print_warning "继续在未备份的情况下添加 fstab 条目..."
                fi
            else
                 print_message "$COLOR_YELLOW" "已选择不备份 /etc/fstab。"
            fi

            # 执行添加
            if echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab; then
                print_success "成功添加 Swap 条目到 /etc/fstab。"
            else
                print_error "无法写入 /etc/fstab。请检查权限或手动添加。"
                print_warning "Swap 当前已激活，但开机自启配置失败。"
            fi
        else
            print_warning "已跳过向 /etc/fstab 添加条目。Swap 当前已激活，但重启后不会自动挂载。"
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

    if [[ ! -f "$SWAP_FILE" ]]; then
        print_error "指定的 Swap 文件 '$SWAP_FILE' 不存在。"
        if check_fstab "$SWAP_FILE"; then
            print_warning "'$SWAP_FILE' 的条目仍存在于 /etc/fstab 中。"
            if confirm_action "是否尝试自动从 /etc/fstab 中移除该残留条目？" "Y"; then
                # 移除残留条目时也询问备份
                if confirm_action "是否在修改 /etc/fstab 前备份？(推荐)" "Y"; then
                   backup_file "/etc/fstab" "fstab_pre_remove_orphan" || print_warning "备份失败，继续移除..."
                else
                   print_message "$COLOR_YELLOW" "已选择不备份 /etc/fstab。"
                fi
                if sed -i "\|^\s*${SWAP_FILE}\s\+none\s\+swap\s\+sw\s\+|d" /etc/fstab; then
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

    # 询问备份 Swap 文件本身 (保留此功能)
    local backup_swap_file_path=""
    print_message "$COLOR_BLUE" "\n--- Swap 文件备份 (可选) ---"
    print_warning "备份 Swap 文件本身通常没有必要，因为它只包含临时数据。"
    if confirm_action "是否要在删除前备份 '$SWAP_FILE' 文件？" "N"; then
        local default_backup_path="/tmp/swapfile_backup_$(date +%Y%m%d_%H%M%S)"
        read -p "$(print_message "$COLOR_YELLOW" "请输入备份文件的完整路径 [${default_backup_path}]: ")" backup_path
        backup_path="${backup_path:-$default_backup_path}"
        local backup_dir=$(dirname "$backup_path")
        if [[ ! -d "$backup_dir" ]]; then mkdir -p "$backup_dir" || { print_error "创建备份目录失败。"; backup_path=""; }; fi # 如果目录创建失败则不备份

        if [[ -n "$backup_path" ]]; then # 只有目录成功或已存在才尝试备份
           print_message "$COLOR_CYAN" "尝试备份到 '$backup_path'..."
           if cp -a "$SWAP_FILE" "$backup_path"; then
               print_success "Swap 文件已备份到 '$backup_path'"
               backup_swap_file_path="$backup_path" # 记录备份路径
           else
               print_error "备份 Swap 文件失败。"
               confirm_action "备份失败，是否仍要继续删除？" "Y" || { print_message "$COLOR_YELLOW" "删除操作取消。"; return 1; }
           fi
        fi
    else
        print_message "$COLOR_YELLOW" "已跳过备份 Swap 文件。"
    fi

    # 最终确认删除
    print_message "$COLOR_BLUE" "\n--- 删除确认 ---"
    print_warning "即将执行删除步骤（停用 Swap、可选移除 fstab 条目、删除文件）。"
    print_warning "确保有足够物理内存容纳 Swap 内容，否则可能导致系统不稳定。"
    confirm_action "确定要继续执行删除操作吗？" "N" || {
        print_message "$COLOR_YELLOW" "操作已取消。"
        if [[ -n "$backup_swap_file_path" ]]; then
            print_warning "之前创建的 Swap 文件备份位于: $backup_swap_file_path"
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
            return 1
        fi
        print_success "Swap 文件已停用。"
    else
        print_message "$COLOR_YELLOW" "'$SWAP_FILE' 当前未激活。"
    fi

    # 2. 处理 fstab (修改点)
    print_step 2 $total_steps "处理 /etc/fstab 条目"
    if check_fstab "$SWAP_FILE"; then
        print_message "$COLOR_YELLOW" "在 /etc/fstab 中找到 '$SWAP_FILE' 的条目。"
        if confirm_action "是否要从 /etc/fstab 中移除此条目？" "Y"; then
             # 确认移除后，询问是否备份 fstab
             if confirm_action "是否在修改 /etc/fstab 前备份？(推荐)" "Y"; then
                 backup_file "/etc/fstab" "fstab_pre_remove" || print_warning "备份失败，继续移除..."
             else
                 print_message "$COLOR_YELLOW" "已选择不备份 /etc/fstab。"
             fi
             # 执行移除
             if sed -i "\|^\s*${SWAP_FILE}\s\+none\s\+swap\s\+sw\s\+|d" /etc/fstab; then
                 print_success "成功从 /etc/fstab 移除条目。"
             else
                 print_error "自动移除 fstab 条目失败，请手动编辑。"
                 success=false
             fi
        else
            print_warning "已跳过从 /etc/fstab 移除条目。如果文件被删除，此条目可能导致启动问题。"
        fi
    else
        print_message "$COLOR_YELLOW" "/etc/fstab 中未找到 '$SWAP_FILE' 条目。"
    fi

    # 3. 删除文件
    print_step 3 $total_steps "删除 Swap 文件 (rm)"
    if rm -f "$SWAP_FILE"; then
        print_success "Swap 文件 '$SWAP_FILE' 已删除。"
    else
        print_error "删除 Swap 文件 '$SWAP_FILE' 失败。请检查权限或手动删除。"
        success=false
    fi

    # 总结
    print_message "$COLOR_CYAN" "\n--- 删除操作总结 ---"
    if [[ "$success" = true ]]; then
         print_message "$COLOR_BOLD_WHITE" "✅ Swap 删除操作已完成。"
    else
         print_warning "⚠️ Swap 删除操作已完成，但遇到问题。请检查日志。"
    fi
    if [[ -n "$backup_swap_file_path" ]]; then
        print_message "$COLOR_YELLOW" "之前请求的 Swap 文件备份位于: $backup_swap_file_path"
    fi
    check_swap_status
}

# 显示详情 (不变)
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

# 显示菜单 (不变)
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
check_root "$@"
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
    read -n 1 -s -r -p "$(print_message "$COLOR_YELLOW" "\n按任意键返回主菜单...")"; echo
done
exit 0
