#!/bin/bash
echo "正在修复 SnapDict 权限..."
sudo xattr -r -d com.apple.quarantine /Applications/SnapDict.app
echo "✅ 完成！现在可以正常打开 SnapDict 了。"
read -p "按回车键关闭..."
