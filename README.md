# GitHub Issue AI Agent 项目概要

## 已实现
1. URL内容替换
   - 触发：issue评论创建/编辑，issue开启/编辑
   - 功能：将评论中的GitHub链接替换为实际评论内容
   - 使用正则表达式匹配URL
   - 通过GitHub API获取评论内容
2. 文件内容评论

## 技术
GitHub Actions + Python + PyGithub

## 下一步
开发聊天功能，增强代码理解