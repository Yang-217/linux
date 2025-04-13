#!/bin/bash

# 颜色输出
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 默认 swap 大小（单位：G）
SWAP_SIZE=${1:-2}

# 路径和文件名
SWAPFILE="/swapfile"

echo -e "${GREEN}>>> 创建 ${SWAP_SIZE}G 的 swap 文件...${NC}"
sudo fallocate -l ${SWAP_SIZE}G $SWAPFILE || sudo dd if=/dev/zero of=$SWAPFILE bs=1G count=$SWAP_SIZE

echo -e "${GREEN}>>> 设置权限为 600...${NC}"
sudo chmod 600 $SWAPFILE

echo -e "${GREEN}>>> 格式化为 swap 类型...${NC}"
sudo mkswap $SWAPFILE

echo -e "${GREEN}>>> 启用 swap...${NC}"
sudo swapon $SWAPFILE

# 检查是否已在 fstab 中
if ! grep -q "$SWAPFILE" /etc/fstab; then
  echo -e "${GREEN}>>> 添加到 /etc/fstab 以便开机自动挂载...${NC}"
  echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
fi

echo -e "${GREEN}>>> swap 添加完成！当前 swap 状态：${NC}"
sudo swapon --show
free -h
