#!/bin/bash

# 配置部分
SWAP_FILE="/swapfile"
SWAP_SIZE=0  # 默认 swap 文件大小为 0，用户可以指定

# 检查是否存在 swap 文件
check_swap() {
  if swapon --show | grep -q "$SWAP_FILE"; then
    echo "Swap 文件已经存在。"
    return 0
  else
    echo "Swap 文件不存在。"
    return 1
  fi
}

# 创建 swap 文件
create_swap() {
  if [ $SWAP_SIZE -eq 0 ]; then
    echo "请输入希望创建的 swap 文件大小 (单位 MB)："
    read SWAP_SIZE
  fi

  if check_swap; then
    echo "Swap 文件已经存在，跳过创建步骤。"
  else
    echo "正在创建 $SWAP_SIZE MB 的 swap 文件..."
    dd if=/dev/zero of=$SWAP_FILE bs=1M count=$SWAP_SIZE status=progress
    chmod 600 $SWAP_FILE
    mkswap $SWAP_FILE
    swapon $SWAP_FILE
    echo "$SWAP_FILE swap 文件已经创建并启用。"
    # 将 swap 设置为开机自启
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    echo "Swap 已设置为开机自动挂载。"
  fi
}

# 删除 swap 文件
delete_swap() {
  if ! check_swap; then
    echo "没有找到 swap 文件，无法删除。"
  else
    swapoff $SWAP_FILE
    rm -f $SWAP_FILE
    sed -i "/$SWAP_FILE/d" /etc/fstab
    echo "Swap 文件已删除，并从 fstab 中移除。"
  fi
}

# 主菜单
menu() {
  echo "欢迎使用 Swap 管理脚本"
  echo "1. 创建或修改 Swap 文件"
  echo "2. 删除 Swap 文件"
  echo "3. 退出"
  echo "请输入您的选择："
  read choice
  case $choice in
    1)
      echo "请输入 Swap 文件大小 (MB)："
      read SWAP_SIZE
      create_swap
      ;;
    2)
      delete_swap
      ;;
    3)
      echo "退出程序"
      exit 0
      ;;
    *)
      echo "无效选择，请重新选择！"
      menu
      ;;
  esac
}

# 执行菜单
menu
