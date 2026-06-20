---
name: wiki-backup
description: 个人知识库自动/手动备份与恢复
license: MIT
compatibility: opencode, claude-code
---

## 功能说明

`wiki-backup` 提供知识库数据的备份和恢复能力。备份范围包括 `.wiki/`（排除 `.wiki/cache/` 缓存目录）、`AGENTS.md`、`CLAUDE.md`（如存在）、`.wiki_ignore`。

备份由独立的 `backup.sh`（Linux/Mac）或 `backup.ps1`（Windows）脚本执行，位于当前安装模式的 skills 目录下：

- OpenCode-only 模式：`.opencode/skills/wiki-backup/`
- OpenCode + Claude Code 模式：`.claude/skills/wiki-backup/`

**注意**：会话启动时的自动备份由 AGENTS.md 指令控制，agent 直接调用脚本，不加载本 skill。

## 手动备份

用户可通过以下方式手动触发备份：

OpenCode-only 模式：

```bash
bash .opencode/skills/wiki-backup/backup.sh
```

OpenCode + Claude Code 模式：

```bash
bash .claude/skills/wiki-backup/backup.sh
```

或强制备份（即使当天已备份过）：

```bash
bash <当前 skills 目录>/wiki-backup/backup.sh --manual
```

### 选项

| 选项 | 说明 |
|------|------|
| `--auto` | 自动模式：当天已有备份则跳过 |
| `--manual` | 手动模式：强制执行（默认） |
| `--root PATH` | 临时指定备份根目录，覆盖安装时配置 |
| `--dry-run` | 只显示将要打包的内容，不实际执行 |

## 备份文件命名与位置

备份文件格式：

```
<年-月-日>_<时-分>_<知识库文件夹名>.tar.gz  （Linux/Mac）
<年-月-日>_<时-分>_<知识库文件夹名>.zip      （Windows）
```

文件夹名中的空格替换为下划线。

默认位置：`<USER_HOME>/.knowledge_base/backup/<知识库文件夹名>/`

## Restore

### 查找备份文件

备份文件位于安装时配置的备份根目录下的 `backup/<知识库文件夹名>/` 目录中，按文件名中的日期识别。

### 恢复步骤

1. 停止当前正在操作知识库的 agent 会话
2. 定位目标备份文件（按日期选择要恢复的版本）
3. 备份当前知识库目录（以防恢复出错）：

   Linux/Mac:
   ```bash
   cp -r /path/to/knowledge-base /path/to/knowledge-base.bak
   ```

   Windows:
   ```powershell
   Copy-Item -Path "C:\path\to\knowledge-base" -Destination "C:\path\to\knowledge-base.bak" -Recurse
   ```

4. 解压备份文件：

   Linux/Mac (tar.gz):
   ```bash
   tar -xzf 2026-05-23_14-30_my-kb.tar.gz -C /path/to/knowledge-base
   ```

   Windows (zip):
   ```powershell
   Expand-Archive -Path "2026-05-23_14-30_my-kb.zip" -DestinationPath "C:\path\to\knowledge-base" -Force
   ```

5. 验证 `.wiki/`、`AGENTS.md`、`CLAUDE.md`（如备份中存在）、`.wiki_ignore` 已正确恢复
6. 确认无误后，删除步骤 3 中创建的备份目录

### 注意事项

- 恢复仅覆盖 `.wiki/`、`AGENTS.md`、`CLAUDE.md`、`.wiki_ignore`，不影响知识库中其他文件
- 恢复后建议运行 `/wiki-lint` 检查 wiki 健康状态
- 如需回退到更早的版本，重复上述步骤选择对应日期的备份文件即可

## 与 wiki-capture 的协作

本 skill 执行期间，对话中可能出现对 skill 功能的说明性内容。这些内容属于基础设施域（Layer 0/Layer 1），不应被 wiki-capture 捕获。Agent 在执行本 skill 时应注意：
- 当本 skill 正在处理任务时，抑制 wiki-capture 的自动感知
- 本 skill 完成后，恢复 wiki-capture 的正常监听
