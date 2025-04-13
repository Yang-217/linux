#!/bin/bash

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请使用 root 权限运行此脚本，或使用 sudo 执行脚本."
        exit 1
    fi
}

# 创建swap文件
create_swap() {
    echo "请输入要创建的swap大小（单位GB）："
    read swap_size
    if [[ ! "$swap_size" =~ ^[0-9]+$ ]]; then
        echo "请输入有效的数字（单位GB）"
        return
    fi

    swap_file="/swapfile"
    
    # 检查是否已有swap文件
    if [ -f "$swap_file" ]; then
        echo "Swap文件已存在，正在删除..."
        swapoff -v "$swap_file"
        rm -f "$swap_file"
        echo "已删除现有swap文件."
    fi

    # 创建swap文件
    echo "正在创建 $swap_size GB 的 swap 文件..."
    dd if=/dev/zero of="$swap_file" bs=1M count=$((swap_size * 1024)) status=progress
    chmod 600 "$swap_file"
    mkswap "$swap_file"
    
    # 启用swap文件
    swapon "$swap_file"
    
    # 挂载swap文件到 /etc/fstab
    echo "$swap_file none swap sw 0 0" >> /etc/fstab
    
    # 开机自动挂载
    echo "swap文件创建并挂载成功，已设置为开机自动挂载."
}

# 删除swap文件
delete_swap() {
    swap_file="/swapfile"
    
    # 检查swap文件是否存在
    if [ ! -f "$swap_file" ]; then
        echo "没有找到 swap 文件."
        return
    fi
    
    # 停用 swap
    swapoff -v "$swap_file"
    
    # 删除 swap 文件
    rm -f "$swap_file"
    
    # 从 fstab 中删除
    sed -i "/$swap_file/d" /etc/fstab
    
    echo "Swap 文件已删除."
}

# 查看swap信息
view_swap() {
    swapon --show
}

# 显示菜单
show_menu() {
    clear
    echo "======================================"
    echo "      Linux Swap 管理脚本"
    echo "======================================"
    echo "1. 创建Swap分区"
    echo "2. 删除Swap分区"
    echo "3. 查看Swap分区详情"
    echo "4. 退出"
    echo "======================================"
    echo -n "请选择操作："
    read choice
    case $choice in
        1)
            create_swap
            ;;
        2)
            delete_swap
            ;;
        3)
            view_swap
            ;;
        4)
            echo "退出程序..."
            exit 0
            ;;
        *)
            echo "无效的选项，请重新选择."
            ;;
    esac
}

# 主程序
check_root

# 循环显示菜单直到退出
while true; do
    show_menu
    echo "按任意键返回菜单..."
    read -n 1 -s
done
