#!/bin/bash

# MacsyZones 上游同步脚本
# 用于将上游仓库的更新合并到自定义版本

set -e  # 遇到错误立即退出

echo "🔄 开始同步上游更新..."

# 检查是否有未提交的更改
if ! git diff --quiet HEAD; then
    echo "⚠️  检测到未提交的更改，请先提交或暂存"
    git status --short
    exit 1
fi

# 获取上游更新
echo "📥 获取上游更新..."
git fetch upstream

# 检查是否有新提交
UPSTREAM_COUNT=$(git rev-list HEAD..upstream/main --count)
if [ "$UPSTREAM_COUNT" -eq 0 ]; then
    echo "✅ 已是最新版本，无需更新"
    exit 0
fi

echo "📊 发现 $UPSTREAM_COUNT 个新提交"

# 更新 main 分支
echo "📥 更新 main 分支..."
git checkout main
git pull upstream main

# 切换到 custom 分支
echo "🔀 切换到 custom 分支..."
git checkout custom

# 执行 rebase
echo "⚙️  应用自定义改造..."
if git rebase main; then
    echo "✅ 同步完成！无冲突"
else
    echo "⚠️  检测到冲突，请手动解决冲突后执行："
    echo "   git add <resolved-files>"
    echo "   git rebase --continue"
    echo ""
    echo "冲突文件列表："
    git diff --name-only --diff-filter=U
    exit 1
fi

echo ""
echo "🎉 同步成功！"
echo "   现在可以构建并替换 app 了"
echo "   Xcode → Product → Archive → 导出"
