## 改动说明
<!-- 简述本次 PR 做了什么、解决了什么问题 -->

## 关联 Issue
<!-- Fixes #xx / Closes #xx -->

## 改动清单
- [ ] `install.sh`：...
- [ ] 文档：...
- [ ] 配置模板：...

## 测试情况
- [ ] `bash -n install.sh` 语法检查通过
- [ ] 完整跑过安装脚本（如适用）
- [ ] README/DEPLOY 文档同步更新

## 检查项（提交前）
- [ ] `pluginMetadata` 保持 15 字段全量（缺 `updatedAt` 会触发 Operit NPE）
- [ ] 无敏感信息（密钥/路径/data/user/0/手机号等）
- [ ] 兼容性：默认路径不破坏已有用户部署

## 截图（可选）