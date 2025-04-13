#!/bin/bash

# 提示用户输入swap大小（单位MB）
echo "请输入要创建的swap大小（单位MB）："
read swap_size

# 检查输入是否合法
if ! [[ "$swap_size" =~ ^[0-9]+$ ]] || [ "$swap_size" -le 0 ]; then
  echo "无效的大小，请输入一个正整数！"
  exit 1
fi

# 创建一个swap文件
echo "正在创建 ${swap_size}MB 的swap文件..."
sudo fallocate -l ${swap_size}M /swapfile

# 设置swap文件权限
sudo chmod 600 /swapfile

# 设置swap文件
echo "正在设置swap文件..."
sudo mkswap /swapfile

# 启用swap文件
echo "正在启用swap文件..."
sudo swapon /swapfile

# 配置/etc/fstab文件，确保系统重启后自动挂载swap
echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab

# 显示swap信息
echo "swap已成功启用，当前swap信息："
sudo swapon --show

echo "完成！"
