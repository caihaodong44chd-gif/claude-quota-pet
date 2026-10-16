#!/bin/bash
# 云端会话（claude.ai/code）启动时跑一次；本机直接退出，什么都不改。
# 1. 启用 .githooks 的提交前隐私检查（新 clone 默认没开）
# 2. 提交身份换成仓库主人的 GitHub noreply 地址：云端默认是 noreply@anthropic.com，会被隐私检查和 CI 拦下
# 3. 宠物设计脚本（design/painted/*.py）要 Pillow 和 numpy，缺了就装
# 云端没有 Swift（download.swift.org 不通），Swift 改动推上去看 CI，见 CLAUDE.md
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"

git config core.hooksPath .githooks

# 只在主人自己的仓库里换身份：fork 出去的 clone 用各自的身份
email=$(git config user.email || true)
case "$email" in
  *@users.noreply.github.com) ;;
  *)
    if git remote get-url origin 2>/dev/null | grep -q 'caihaodong44chd-gif/claude-quota-pet'; then
      git config user.name caihaodong44chd-gif
      git config user.email 327893803+caihaodong44chd-gif@users.noreply.github.com
    fi
    ;;
esac

if ! python3 -c 'import PIL, numpy' 2>/dev/null; then
  python3 -m pip install --quiet --user pillow numpy 2>/dev/null ||
    python3 -m pip install --quiet --user --break-system-packages pillow numpy
fi

# stdout 会进会话的上下文，只说一句现在的状态
echo "QuotaPet 云端环境：隐私钩子已启用，提交身份 $(git config user.email)；这里没有 Swift，改了 Swift 推上去用 CI 验证（见 CLAUDE.md）。"
