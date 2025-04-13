#!/bin/bash

# 用法提示
if [ -z "$1" ]; then
  echo "用法: sudo $0 <Swap大小，例如：1G 或 1024M>"
  exit 1
fi

SWAP_SIZE=$1
SWAP_FILE="/swapfile"

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 检查是否已有 swapfile
if grep -q "$SWAP_FILE" /etc/fstab; then
  echo "Swap 文件已存在！"
  exit 1
fi

echo "创建 $SWAP_SIZE 大小的 Swap 文件..."

# 创建 swap 文件
fallocate -l $SWAP_SIZE $SWAP_FILE || dd if=/dev/zero of=$SWAP_FILE bs=1M count=${SWAP_SIZE%[GM]}000

# 设置权限
chmod 600 $SWAP_FILE

# 格式化为 swap
mkswap $SWAP_FILE

# 启用 swap
swapon $SWAP_FILE

# 添加到 /etc/fstab 实现开机自动挂载
echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab

# 优化 swap 参数（可选）
sysctl vm.swappiness=10
echo "vm.swappiness=10" >> /etc/sysctl.conf

echo "Swap 添加成功！当前 swap 使用情况："
swapon --show
free -h
