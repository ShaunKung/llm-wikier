import { existsSync, readFileSync, writeFileSync, mkdirSync, cpSync, rmSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { createInterface } from 'node:readline';
import chalk from 'chalk';
import {
  error, success, info, warning,
  getSkillsSource, getTemplatesSource,
  LLM_WIKIER_SKILLS, CLAUDE_MANAGED_BEGIN, CLAUDE_MANAGED_END, CODEX_AGENT_MANAGED,
  renderAgentsTemplate, copySkills, removeManagedSkills,
  getActiveSkillsDir, getInactiveSkillsDirs,
  getBackupAutoCommand, hasManagedClaudeSupport, hasManagedCodexSupport,
  detectCurrentMode, getExistingBackupRoot, writeBackupRoot,
} from './utils.js';

function rl() {
  return createInterface({ input: process.stdin, output: process.stdout });
}

function question(query) {
  return new Promise(resolve => {
    const i = rl();
    i.question(query, answer => { i.close(); resolve(answer.trim()); });
  });
}

async function promptUser(message, force) {
  if (force) return true;
  const answer = await question(chalk.yellow(`[询问] ${message} [Y/n] `));
  return !/^[nN](o|O)?$/.test(answer);
}

function getDefaultAgentsContent() {
  return `# AGENTS.md - 知微（zhiwei）配置文件

此文件定义知识库的结构、约定和工作流程。

> ⚠️ **重要提示**：本文档除「用户偏好」和「自定义配置」章节外，其余章节均由工具包在更新安装时从模板自动刷新。请勿在其他章节添加个人内容，否则更新安装时将被覆盖。您的自定义内容请仅存放在「用户偏好」和「自定义配置」章节中。

## 知识库概述

这是一个由知微（zhiwei）管理的个人知识库。

## Wiki 结构

\`\`\`
.wiki/
├── index.md          # 内容索引
├── log.md            # 操作日志
├── entities/         # 实体页面
├── concepts/         # 概念页面
├── sources/          # 源文件摘要
└── analysis/         # 分析与综合页面
\`\`\`

## 页面命名规范

- 使用小写字母和连字符
- 实体页面：\`entities/实体名称.md\`
- 概念页面：\`concepts/概念名称.md\`
- 源文件摘要：\`sources/源文件名-summary.md\`

## 支持的文件格式

文本格式：\`.md\`, \`.txt\`, \`.json\`, \`.yaml\`, \`.yml\`, \`.csv\`, \`.xml\`, \`.html\`, \`.rst\`, \`.org\`, \`.tex\`

办公文档格式：\`.pdf\`, \`.docx\`, \`.doc\`, \`.pptx\`, \`.ppt\`, \`.xlsx\`, \`.xls\`, \`.odt\`, \`.odp\`, \`.ods\`

图片格式：\`.png\`, \`.jpg\`, \`.jpeg\`, \`.gif\`, \`.webp\`, \`.svg\`, \`.bmp\`

网络链接格式：\`.url\`

## 视觉内容处理策略

主 agent 可能是纯文本模型。如已配置 \`vision-reader\` subagent，Agent 会在遇到视觉内容时自动调用。

### 处理流程

**纯图片文件**（\`.png\`, \`.jpg\`, \`.jpeg\`, \`.gif\`, \`.webp\`, \`.svg\`, \`.bmp\`）：
- 调用 \`vision-reader\` subagent 读取（OpenCode 通常使用 Task 工具；Claude Code 使用 Agent/subagent 调用）

**网络链接网页**（\`.url\`）：Read 取文本 + vision-reader 取视觉元素

**办公文档 & 网页**（\`.pptx\`, \`.ppt\`, \`.pdf\`, \`.docx\`, \`.doc\`, \`.html\`）：
- 两段式：Read 取文本 + vision-reader 取视觉元素

**Markdown**：文本优先，按需读取图片

如当前客户端未配置 \`vision-reader\`，Agent 跳过视觉处理。OpenCode 配置路径为 \`.opencode/agents/vision-reader.md\`，Claude Code 配置路径为 \`.claude/agents/vision-reader.md\`，Codex 配置路径为 \`.codex/agents/vision-reader.toml\`。

OpenCode 配置方式：\`zhiwei config-vision-reader <知识库路径>\`。启用 Claude Code 支持时安装器生成 Claude Code 版 \`vision-reader\`；启用 Codex 支持时安装器生成 Codex 版 \`vision-reader\`（不指定 model，由 Codex 自动选择）。

## 文件排除规则

知识库根目录的 \`.wiki_ignore\` 文件定义了被排除的文件和目录。
格式类似 \`.gitignore\`：每行一个模式，\`#\` 开头的行为注释。

### 默认排除项
- \`.opencode/\` — skills 配置目录
- \`.claude/\` — Claude Code 配置目录（仅启用 Claude Code 支持时）
- \`.agents/\` — 共享 skills 配置目录（仅启用 Codex 支持时）
- \`.codex/\` — Codex 配置目录（仅启用 Codex 支持时）
- \`.wiki/\` — wiki 内容本身
- \`.wiki/cache/\` — 链接文档缓存（不计入备份）
- \`.git/\` — 版本控制
- \`AGENTS.md\` — 知识库配置文件
- \`CLAUDE.md\` — Claude Code 入口文件（仅启用 Claude Code 支持时）
- \`output/\` — 用户自产文件（展示文档、报告等），不会被作为源文件处理

### 用户自定义
用户可在 \`.wiki_ignore\` 的「用户自定义规则」区域添加自己的排除项。

### 对技能的影响
所有扫描 raw sources 的技能（wiki-init、wiki-ingest、wiki-update）在扫描文件前
必须读取 \`.wiki_ignore\` 并按其中规则排除匹配的文件和目录。

## 工作流程

1. 用户添加新的源文件到知识库
2. 运行 \`/wiki-ingest\` 处理新文件
3. LLM 更新 wiki 页面、索引和日志
4. 用户可通过 \`/wiki-query\` 查询知识库

## 贡献指南

- 提问时尽量具体
- 定期运行 \`/wiki-lint\` 检查 wiki 健康状态
- 重要的查询答案可以作为新页面沉淀

## 自动备份

每次新会话开始时，Agent 应以自动模式静默执行一次备份：

    __WIKI_BACKUP_AUTO_COMMAND__

- 不向用户显示执行过程和结果
- 同一会话内仅执行一次（自动模式的日级去重机制已覆盖此要求）
- 如脚本不存在，静默跳过

## 用户偏好

<!-- 用户可以在此添加个人偏好 -->

## 自定义配置

<!-- 用户可以在此添加自定义配置 -->
`;
}

// === AGENTS.md management ===
function extractSectionFromTo(content, fromMarker, toMarker) {
  const fromIdx = content.indexOf(fromMarker);
  if (fromIdx === -1) return null;
  const toIdx = content.indexOf(toMarker, fromIdx + fromMarker.length);
  if (toIdx === -1 || toIdx <= fromIdx) return null;
  return content.slice(fromIdx, toIdx);
}

function extractSectionToEnd(content, fromMarker) {
  const idx = content.indexOf(fromMarker);
  if (idx === -1) return null;
  return content.slice(idx);
}

function mergeAgentsFile(oldContent, newTemplate, force) {
  const userSection = extractSectionFromTo(oldContent, '## 用户偏好', '## 自定义配置');
  const customSection = extractSectionToEnd(oldContent, '## 自定义配置');

  if (!userSection || !customSection) {
    warning('现有 AGENTS.md 缺少标准章节');
    const useNew = force || true;
    if (useNew) {
      info('将使用新模板覆盖 AGENTS.md');
      return newTemplate;
    }
    info('保留现有 AGENTS.md 不变');
    return oldContent;
  }

  const newUserIdx = newTemplate.indexOf('## 用户偏好');
  const newCustomIdx = newTemplate.indexOf('## 自定义配置');
  if (newUserIdx === -1 || newCustomIdx === -1) {
    warning('新模板缺少标准章节，保留现有 AGENTS.md');
    return oldContent;
  }

  const header = newTemplate.slice(0, newUserIdx);
  return header + userSection + customSection;
}

function selectClientModeInteractive(isUpdate, currentMode, force) {
  if (force) {
    return isUpdate ? currentMode : 'opencode';
  }
  return new Promise(async (resolve) => {
    console.log('');
    if (isUpdate) {
      const modeLabel = { claude: 'Claude Code', codex: 'Codex', opencode: 'OpenCode-only' };
      info(`检测到当前知识库已支持 ${modeLabel[currentMode]}`);
      console.log(chalk.yellow('[询问]'), '选择客户端模式：');
      console.log(`  1) 保持不变（${modeLabel[currentMode]}）`);
      console.log('  2) OpenCode + Codex');
      console.log('  3) OpenCode + Claude Code');
      console.log('  4) 仅 OpenCode（移除其他支持）');
      const answer = await question(chalk.blue('[选择] 请输入 (1-4): '));
      const map = { '1': currentMode, '2': 'codex', '3': 'claude', '4': 'opencode' };
      resolve(map[answer] || currentMode);
    } else {
      console.log(chalk.yellow('[询问]'), '是否需要支持除 OpenCode 之外的其它客户端？');
      console.log('  1) 仅 OpenCode（默认）');
      console.log('  2) OpenCode + Claude Code');
      console.log('  3) OpenCode + Codex');
      const answer = await question(chalk.blue('[选择] 请输入 (1-3): '));
      const map = { '2': 'claude', '3': 'codex' };
      resolve(map[answer] || 'opencode');
    }
  });
}

// === File creation ===
function createWikiDirectory(targetDir) {
  const dir = resolve(targetDir, '.wiki');
  mkdirSync(dir, { recursive: true });
  success(`创建 wiki 目录: ${dir}`);
}

function createIndexFile(targetDir) {
  const file = resolve(targetDir, '.wiki', 'index.md');
  const content = `# Wiki 索引

这是知微自动生成的 wiki 索引页面。

## 页面列表

### 实体页面
<!-- LLM 将在此添加实体页面链接 -->

### 概念页面
<!-- LLM 将在此添加概念页面链接 -->

### 源文件摘要
<!-- LLM 将在此添加源文件摘要链接 -->

### 分析与综合
<!-- LLM 将在此添加分析页面链接 -->

---
*最后更新: 待初始化*
`;
  writeFileSync(file, content, 'utf-8');
  success(`创建索引文件: ${file}`);
}

function createLogFile(targetDir) {
  const file = resolve(targetDir, '.wiki', 'log.md');
  const content = `# Wiki 操作日志

此文件记录所有 wiki 操作的历史。

---

`;
  writeFileSync(file, content, 'utf-8');
  success(`创建日志文件: ${file}`);
}

function createProcessedFile(targetDir) {
  const file = resolve(targetDir, '.wiki', '.wiki-processed');
  writeFileSync(file, '{"version": 2, "entries": []}\n', 'utf-8');
  success(`创建处理记录文件: ${file}`);
}

function createWikiIgnoreFile(targetDir, mode) {
  const file = resolve(targetDir, '.wiki_ignore');
  const rules = ['.opencode/'];
  if (mode === 'claude') rules.push('.claude/');
  if (mode === 'codex') { rules.push('.agents/'); rules.push('.codex/'); }
  rules.push('.wiki/', '.wiki/cache/', '.git/', 'AGENTS.md');
  if (mode === 'claude') rules.push('CLAUDE.md');
  rules.push('output/');
  const content = `# 知微（zhiwei）— 默认排除规则（由工具包管理，请勿修改此区域）
${rules.join('\n')}

# ——— 用户自定义规则（添加在此区域下方） ———
`;
  writeFileSync(file, content, 'utf-8');
  success(`创建 .wiki_ignore: ${file}`);
}

function mergeWikiIgnore(targetDir, mode) {
  const file = resolve(targetDir, '.wiki_ignore');
  let userCustom = '';
  if (existsSync(file)) {
    const content = readFileSync(file, 'utf-8');
    const marker = '# ——— 用户自定义规则';
    const idx = content.indexOf(marker);
    if (idx !== -1) {
      const after = content.slice(idx + marker.length);
      const nlIdx = after.indexOf('\n');
      userCustom = nlIdx !== -1 ? after.slice(nlIdx + 1) : '';
    }
  }
  createWikiIgnoreFile(targetDir, mode);
  if (userCustom.trim()) {
    writeFileSync(file, readFileSync(file, 'utf-8') + '\n' + userCustom, 'utf-8');
    success('已合并更新 .wiki_ignore（保留用户自定义规则）');
  }
}

function createOutputDirectory(targetDir) {
  const dir = resolve(targetDir, 'output');
  if (existsSync(dir)) {
    info('output/ 目录已存在，跳过创建');
    return;
  }
  mkdirSync(dir, { recursive: true });
  success(`创建 output/ 目录: ${dir}`);
}

function createSkillsDirectory(targetDir, mode) {
  const skillsDir = getActiveSkillsDir(targetDir, mode);
  const existingBackupRoot = getExistingBackupRoot(targetDir);
  mkdirSync(skillsDir, { recursive: true });
  copySkills(getSkillsSource(), skillsDir, LLM_WIKIER_SKILLS);

  for (const inactiveDir of getInactiveSkillsDirs(targetDir, mode)) {
    removeManagedSkills(inactiveDir, LLM_WIKIER_SKILLS);
  }

  if (existingBackupRoot) {
    writeBackupRoot(targetDir, mode, existingBackupRoot);
    info(`已保留既有备份根目录: ${existingBackupRoot}`);
  }
}

function createAgentsFile(targetDir, mode, force) {
  const agentsFile = resolve(targetDir, 'AGENTS.md');
  const templateFile = resolve(getTemplatesSource(), 'AGENTS.md.tmpl');
  const backupCmd = getBackupAutoCommand(mode);

  if (existsSync(templateFile)) {
    const rendered = renderAgentsTemplate(templateFile, backupCmd);
    writeFileSync(agentsFile, rendered, 'utf-8');
    success(`创建 AGENTS.md: ${agentsFile}`);
  } else {
    warning('找不到 AGENTS.md 模板，使用默认内容');
    const defaultContent = getDefaultAgentsContent();
    const rendered = defaultContent.replace(/__WIKI_BACKUP_AUTO_COMMAND__/g, backupCmd);
    writeFileSync(agentsFile, rendered, 'utf-8');
    success(`创建默认 AGENTS.md: ${agentsFile}`);
  }
}

function updateAgentsFile(targetDir, mode) {
  const agentsFile = resolve(targetDir, 'AGENTS.md');
  const templateFile = resolve(getTemplatesSource(), 'AGENTS.md.tmpl');
  const backupCmd = getBackupAutoCommand(mode);

  if (!existsSync(agentsFile)) {
    createAgentsFile(targetDir, mode, true);
    return;
  }

  const oldContent = readFileSync(agentsFile, 'utf-8');
  let newTemplate;

  if (existsSync(templateFile)) {
    newTemplate = renderAgentsTemplate(templateFile, backupCmd);
  } else {
    warning('找不到 AGENTS.md 模板，使用内置默认内容');
    newTemplate = getDefaultAgentsContent().replace(/__WIKI_BACKUP_AUTO_COMMAND__/g, backupCmd);
  }

  const merged = mergeAgentsFile(oldContent, newTemplate, false);
  writeFileSync(agentsFile, merged, 'utf-8');
  success('已合并更新 AGENTS.md');
}

// === Claude / Codex support files ===
function writeClaudeFile(targetDir) {
  const claudeFile = resolve(targetDir, 'CLAUDE.md');
  let existing = '';
  if (existsSync(claudeFile)) {
    existing = readFileSync(claudeFile, 'utf-8');
    const pattern = new RegExp(`${escapeRegex(CLAUDE_MANAGED_BEGIN)}[\\s\\S]*?${escapeRegex(CLAUDE_MANAGED_END)}\\n?`, 'g');
    existing = existing.replace(pattern, '');
  }

  const managedBlock = `${CLAUDE_MANAGED_BEGIN}
@AGENTS.md

## Claude Code

本知识库已启用 Claude Code 支持。知微的 Agent Skills 安装在 \`.claude/skills/\`，OpenCode 也会通过兼容路径读取同一份 skills。
${CLAUDE_MANAGED_END}
`;

  const content = existing.trim() ? existing.trimEnd() + '\n\n' + managedBlock : managedBlock;
  writeFileSync(claudeFile, content, 'utf-8');
  success(`已配置 Claude Code 入口: ${claudeFile}`);
}

function removeClaudeManagedBlock(targetDir) {
  const claudeFile = resolve(targetDir, 'CLAUDE.md');
  if (!existsSync(claudeFile)) return;
  let content = readFileSync(claudeFile, 'utf-8');
  if (!content.includes(CLAUDE_MANAGED_BEGIN)) {
    info('保留用户自定义 CLAUDE.md');
    return;
  }
  const pattern = new RegExp(`${escapeRegex(CLAUDE_MANAGED_BEGIN)}[\\s\\S]*?${escapeRegex(CLAUDE_MANAGED_END)}\\n?`, 'g');
  const remaining = content.replace(pattern, '');
  if (remaining.trim()) {
    writeFileSync(claudeFile, remaining.trimEnd(), 'utf-8');
    success('已移除 CLAUDE.md 中的知微托管区块');
  } else {
    rmSync(claudeFile, { force: true });
    success('已移除知微托管的 CLAUDE.md');
  }
}

function writeClaudeVisionReader(targetDir) {
  const agentDir = resolve(targetDir, '.claude', 'agents');
  const agentFile = resolve(agentDir, 'vision-reader.md');
  if (existsSync(agentFile) && !readFileSync(agentFile, 'utf-8').includes('LLM-WIKIER:CLAUDE-AGENT-MANAGED')) {
    info(`保留用户自定义 Claude Code vision-reader: ${agentFile}`);
    return;
  }
  mkdirSync(agentDir, { recursive: true });
  const content = `---
name: vision-reader
description: 读取图片、图表、截图、幻灯片、PDF 和文档排版等视觉元素，转化为文字描述
model: inherit
tools:
  - Read
---
<!-- LLM-WIKIER:CLAUDE-AGENT-MANAGED -->
你是一个视觉内容读取器。你的职责是读取文件中的视觉元素（图片、图表、截图、幻灯片、页面排版等），并将视觉内容转化为文字描述。

## 核心职责
- 只描述视觉元素（图片、图表、照片、插图、截图、幻灯片视觉内容、排版布局等）
- 不要重复已经由主 agent 处理的纯文本内容
- **兜底规则**：如果发现文档中文本提取明显不完整（如幻灯片缺失文字、表格数据丢失、图表中的数据标签等），请一并补充关键文本信息

## 输出格式
对每个视觉元素：

\`\`\`
### [图片/图表/截图 序号]
**类型**: [图表/照片/截图/插图/排版]
**描述**: [视觉内容的文字描述]
**关键信息**: [图表数据、照片中的人物/场景、截图中的UI元素、幻灯片主题等]
\`\`\`

主 agent 会通过文件路径告知你需要读取的文件，请直接读取并返回描述。
`;
  writeFileSync(agentFile, content, 'utf-8');
  success(`已配置 Claude Code vision-reader: ${agentFile}`);
}

function removeClaudeVisionReader(targetDir) {
  const agentFile = resolve(targetDir, '.claude', 'agents', 'vision-reader.md');
  if (!existsSync(agentFile)) return;
  if (readFileSync(agentFile, 'utf-8').includes('LLM-WIKIER:CLAUDE-AGENT-MANAGED')) {
    rmSync(agentFile, { force: true });
    try { rmSync(resolve(targetDir, '.claude', 'agents'), { recursive: true, force: true }); } catch {}
    try { rmSync(resolve(targetDir, '.claude'), { recursive: true, force: true }); } catch {}
    success('已移除知微托管的 Claude Code vision-reader');
  } else {
    info('保留用户自定义 Claude Code vision-reader');
  }
}

function writeCodexVisionReader(targetDir) {
  const agentDir = resolve(targetDir, '.codex', 'agents');
  const agentFile = resolve(agentDir, 'vision-reader.toml');
  if (existsSync(agentFile) && !readFileSync(agentFile, 'utf-8').includes(CODEX_AGENT_MANAGED)) {
    info(`保留用户自定义 Codex vision-reader: ${agentFile}`);
    return;
  }
  mkdirSync(agentDir, { recursive: true });
  const content = `# ${CODEX_AGENT_MANAGED}
name = "vision-reader"
description = "读取图片、图表、截图、幻灯片、PDF 和文档排版等视觉元素，转化为文字描述"
sandbox_mode = "read-only"

developer_instructions = """
你是一个视觉内容读取器。你的职责是读取文件中的视觉元素（图片、图表、截图、幻灯片、页面排版等），并将视觉内容转化为文字描述。

## 核心职责
- 只描述视觉元素（图片、图表、照片、插图、截图、幻灯片视觉内容、排版布局等）
- 不要重复已经由主 agent 处理的纯文本内容
- **兜底规则**：如果发现文档中文本提取明显不完整（如幻灯片缺失文字、表格数据丢失、图表中的数据标签等），请一并补充关键文本信息

## 输出格式
对每个视觉元素：

### [图片/图表/截图 序号]
**类型**: [图表/照片/截图/插图/排版]
**描述**: [视觉内容的文字描述]
**关键信息**: [图表数据、照片中的人物/场景、截图中的UI元素、幻灯片主题等]

主 agent 会通过文件路径告知你需要读取的文件，请直接读取并返回描述。
"""
`;
  writeFileSync(agentFile, content, 'utf-8');
  success(`已配置 Codex vision-reader: ${agentFile}`);
}

function removeCodexVisionReader(targetDir) {
  const agentFile = resolve(targetDir, '.codex', 'agents', 'vision-reader.toml');
  if (!existsSync(agentFile)) return;
  if (readFileSync(agentFile, 'utf-8').includes(CODEX_AGENT_MANAGED)) {
    rmSync(agentFile, { force: true });
    try { rmSync(resolve(targetDir, '.codex', 'agents'), { recursive: true, force: true }); } catch {}
    try { rmSync(resolve(targetDir, '.codex'), { recursive: true, force: true }); } catch {}
    success('已移除知微托管的 Codex vision-reader');
  } else {
    info('保留用户自定义 Codex vision-reader');
  }
}

function syncClientSupportFiles(targetDir, mode) {
  switch (mode) {
    case 'claude':
      writeClaudeFile(targetDir);
      writeClaudeVisionReader(targetDir);
      removeCodexVisionReader(targetDir);
      break;
    case 'codex':
      writeCodexVisionReader(targetDir);
      removeClaudeManagedBlock(targetDir);
      removeClaudeVisionReader(targetDir);
      break;
    default:
      removeClaudeManagedBlock(targetDir);
      removeClaudeVisionReader(targetDir);
      removeCodexVisionReader(targetDir);
      break;
  }
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// === Migration ===
function migrateOldStructure(targetDir) {
  const oldWiki = resolve(targetDir, 'wiki');
  const newWiki = resolve(targetDir, '.wiki');
  if (!existsSync(oldWiki) || existsSync(newWiki)) return;

  info('检测到旧版 wiki/ 目录，正在自动迁移至 .wiki/...');
  cpSync(oldWiki, newWiki, { recursive: true, force: true });
  rmSync(oldWiki, { recursive: true, force: true });
  success('已迁移 wiki/ → .wiki/');

  const oldProcessed = resolve(targetDir, '.wiki-processed');
  if (existsSync(oldProcessed)) {
    cpSync(oldProcessed, resolve(newWiki, '.wiki-processed'), { force: true });
    rmSync(oldProcessed, { force: true });
    success('已迁移 .wiki-processed → .wiki/.wiki-processed');
  }

  const mdFiles = readdirSync(newWiki, { recursive: true }).filter(f => f.endsWith('.md'));
  for (const f of mdFiles) {
    const fp = resolve(newWiki, f);
    if (existsSync(fp) && statSync(fp).isFile()) {
      let content = readFileSync(fp, 'utf-8');
      if (content.includes('wiki/')) {
        content = content.replace(/wiki\//g, '.wiki/');
        writeFileSync(fp, content, 'utf-8');
      }
    }
  }
  success('已修复 .wiki/ 内所有交叉引用链接');
}

function migrateProcessedFile(targetDir) {
  const processedFile = resolve(targetDir, '.wiki', '.wiki-processed');
  if (!existsSync(processedFile)) return;

  let data;
  try {
    data = JSON.parse(readFileSync(processedFile, 'utf-8'));
  } catch {
    warning('.wiki-processed JSON 解析失败，跳过迁移');
    return;
  }

  // v2 normalization
  if (data.version === 2) {
    let changed = 0;
    for (const entry of (data.entries || [])) {
      if (entry.hash) {
        let normalized = entry.hash.toLowerCase();
        if (normalized.startsWith('sha256:')) normalized = normalized.slice(7);
        if (normalized !== entry.hash) {
          entry.hash = normalized;
          changed++;
        }
      }
    }
    if (changed > 0) {
      writeFileSync(processedFile + '.hash-normalize.bak', JSON.stringify(data, null, 2), 'utf-8');
      writeFileSync(processedFile, JSON.stringify(data, null, 2), 'utf-8');
      success(`已归一化 .wiki-processed hash: ${changed} 条`);
    }
    return;
  }

  if (data.version !== 1) return;
  info('检测到 .wiki-processed v1，正在迁移至 v2...');
  writeFileSync(processedFile + '.bak', JSON.stringify(data, null, 2), 'utf-8');
  info(`已备份: ${processedFile}.bak`);

  const hashMap = {};
  const pathMap = {};
  info('正在扫描知识库文件...');
  walkFiles(targetDir, filePath => {
    const relPath = filePath.slice(targetDir.length + 1).replace(/\\/g, '/');
    const firstDir = relPath.split('/')[0];
    if (['.wiki', '.opencode', '.claude', '.git'].includes(firstDir)) return;
    try {
      const hash = createHash('sha256').update(readFileSync(filePath)).digest('hex');
      hashMap[hash] = relPath;
      pathMap[relPath] = hash;
    } catch {}
  });

  let kept = 0, recovered = 0, removedEntry = 0, filled = 0;
  const now = new Date().toISOString();
  const newEntries = [];

  for (const entry of (data.entries || [])) {
    let path = entry.path;
    let hash = (entry.hash || '').toLowerCase();
    if (hash.startsWith('sha256:')) hash = hash.slice(7);

    const fullPath = resolve(targetDir, path);
    if (!hash && existsSync(fullPath)) {
      hash = pathMap[path] || '';
      if (!hash) {
        try {
          hash = createHash('sha256').update(readFileSync(fullPath)).digest('hex');
        } catch {}
      }
      if (hash) filled++;
    }

    if (existsSync(fullPath)) {
      kept++;
      newEntries.push({ path, hash, processed: entry.processed || now });
    } else if (hash && hashMap[hash]) {
      recovered++;
      newEntries.push({ path: hashMap[hash], hash, processed: entry.processed || now });
    } else {
      removedEntry++;
    }
  }

  const newData = { version: 2, entries: newEntries };
  writeFileSync(processedFile, JSON.stringify(newData, null, 2), 'utf-8');
  success(`迁移完成: 保留 ${kept} 条, 恢复 ${recovered} 条, 移除 ${removedEntry} 条, 补填 ${filled} 条`);
}

function walkFiles(dir, fn) {
  const entries = readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = resolve(dir, entry.name);
    if (entry.isDirectory()) {
      walkFiles(full, fn);
    } else if (entry.isFile()) {
      fn(full);
    }
  }
}

function isUpdateInstall(targetDir) {
  const agentsFile = resolve(targetDir, 'AGENTS.md');
  if (!existsSync(agentsFile)) return false;

  const keySkills = ['wiki-ingest', 'wiki-lint', 'wiki-query'];
  const roots = [
    resolve(targetDir, '.opencode', 'skills'),
    resolve(targetDir, '.claude', 'skills'),
    resolve(targetDir, '.agents', 'skills'),
  ];
  for (const root of roots) {
    const allFound = keySkills.every(s => existsSync(resolve(root, s, 'SKILL.md')));
    if (allFound) return true;
  }
  return false;
}

function checkExistingInstallation(targetDir, force) {
  const hasWiki = existsSync(resolve(targetDir, '.wiki')) || existsSync(resolve(targetDir, 'wiki'));
  const hasOld = existsSync(resolve(targetDir, 'wiki'));
  const hasAgents = existsSync(resolve(targetDir, 'AGENTS.md'));
  const hasSkills = existsSync(resolve(targetDir, '.opencode', 'skills'));
  const hasClaude = hasManagedClaudeSupport(targetDir);
  const hasCodex = hasManagedCodexSupport(targetDir);

  if (hasWiki || hasOld || hasAgents || hasSkills || hasClaude || hasCodex) {
    if (force) {
      warning('检测到已有安装，将强制覆盖');
    } else {
      error('检测到已有文件，若为更新安装请使用 --force，或移除已有文件后重试');
      process.exit(1);
    }
  }
}

// === Backup config ===
async function configureBackup(targetDir, mode, force) {
  const skillsDir = getActiveSkillsDir(targetDir, mode);
  if (force) {
    const backupScript = resolve(skillsDir, 'wiki-backup', 'backup.sh');
    if (existsSync(backupScript)) {
      info('强制安装模式，保留现有备份配置');
    } else {
      info('强制安装模式，备份使用默认路径: ~/.knowledge_base');
    }
    return;
  }

  console.log('');
  info('备份脚本的默认根目录为 ~/.knowledge_base');
  const backupRoot = await question(chalk.blue('[输入] 请输入备份根目录（留空使用默认值）: ')) || resolve(process.env.HOME || process.env.USERPROFILE || '~', '.knowledge_base');

  writeBackupRoot(targetDir, mode, backupRoot);
  const backupSh = resolve(skillsDir, 'wiki-backup', 'backup.sh');
  if (existsSync(backupSh)) {
    success(`已配置备份根目录: ${backupRoot}`);
  } else {
    warning('找不到 backup.sh，跳过备份配置');
  }

  const backupPs1 = resolve(skillsDir, 'wiki-backup', 'backup.ps1');
  if (existsSync(backupPs1)) {
    success('已配置 backup.ps1 备份根目录');
  }
}

// === Vision reader config prompt ===
async function configureVisionReaderPrompt(targetDir, mode, force) {
  if (force) {
    info('强制安装模式，跳过 vision-reader 交互配置');
    info('稍后可手动运行: zhiwei config-vision-reader <知识库路径>');
    if (mode === 'codex') {
      info('Codex 版 vision-reader 已由安装器预生成（.codex/agents/vision-reader.toml）');
    }
    return;
  }
  console.log('');
  if (mode === 'codex') {
    info('Codex 版 vision-reader 已由安装器预生成（.codex/agents/vision-reader.toml），不指定模型由 Codex 自动选择');
  }
  if (!await promptUser('是否配置 OpenCode 版 vision-reader subagent？（用于在 OpenCode 中读取图片/幻灯片/PDF 等视觉内容）', false)) {
    info('已跳过 OpenCode 版 vision-reader 配置');
    return;
  }
  info('正在配置 OpenCode 版 vision-reader...');
  const { configureVisionReader } = await import('./config-vision-reader.js');
  await configureVisionReader(targetDir, { force: true });
}

function printCompletionMessage(targetDir, mode) {
  console.log('');
  console.log('======================================');
  success('知微（zhiwei）安装完成！');
  console.log('======================================');
  console.log('');
  console.log('下一步操作：');
  console.log('');
  console.log(`1. 进入知识库目录：
   cd "${targetDir}"`);
  console.log('');
  console.log(`2. 启动 OpenCode：
   opencode`);
  if (mode === 'claude') {
    console.log(`   或启动 Claude Code：
   claude`);
  } else if (mode === 'codex') {
    console.log(`   或启动 Codex：
   codex`);
  }
  console.log('');
  console.log(`3. 如果知识库已有文件，运行批量初始化：
   OpenCode: /wiki-init`);
  if (mode === 'codex') {
    console.log('   Codex: $wiki-init 或 /skills 选择 wiki-init');
  }
  console.log('');
  console.log(`4. 或者添加新文件后运行增量处理：
   OpenCode: /wiki-ingest`);
  if (mode === 'codex') {
    console.log('   Codex: $wiki-ingest 或 /skills 选择 wiki-ingest');
  }
  console.log('');
  console.log('详细文档请参考 README.md');
}

// === Main entry ===
export async function install(targetDir, options = {}) {
  const force = options.force || false;
  const mode = options.mode || null;

  targetDir = resolve(targetDir);
  if (!existsSync(targetDir)) {
    error(`目标目录不存在: ${targetDir}`);
    process.exit(1);
  }
  info(`目标知识库路径: ${targetDir}`);

  // Check if update install
  if (isUpdateInstall(targetDir)) {
    info('检测到已有安装（AGENTS.md + 关键 skills），进入更新安装模式');
    return updateInstall(targetDir, options);
  }

  checkExistingInstallation(targetDir, force);

  const selectedMode = mode || await selectClientModeInteractive(false, 'opencode', force);
  const modeLabel = { claude: 'OpenCode + Claude Code', codex: 'OpenCode + Codex', opencode: 'OpenCode-only' };
  info(`客户端模式: ${modeLabel[selectedMode]}`);

  info('开始安装知微...');
  createWikiDirectory(targetDir);
  createIndexFile(targetDir);
  createLogFile(targetDir);
  createProcessedFile(targetDir);
  createWikiIgnoreFile(targetDir, selectedMode);
  createOutputDirectory(targetDir);
  createSkillsDirectory(targetDir, selectedMode);
  createAgentsFile(targetDir, selectedMode, force);
  syncClientSupportFiles(targetDir, selectedMode);
  await configureBackup(targetDir, selectedMode, force);
  printCompletionMessage(targetDir, selectedMode);
  await configureVisionReaderPrompt(targetDir, selectedMode, force);
}

export async function updateInstall(targetDir, options = {}) {
  const force = options.force || false;
  const mode = options.mode || null;

  console.log('');
  migrateOldStructure(targetDir);
  migrateProcessedFile(targetDir);

  const previousMode = detectCurrentMode(targetDir);
  const currentMode = mode || previousMode;

  const selectedMode = mode
    ? mode
    : await selectClientModeInteractive(true, previousMode, force);

  const modeChanged = previousMode !== selectedMode;

  console.log('');
  info('更新安装将执行以下操作：');
  info('  (1) 更新 skills — 同步最新 skill 文件');
  info('  (2) 更新 AGENTS.md — 从模板更新，保留您的用户偏好和自定义配置');
  info('  (3) 更新 .wiki_ignore — 从模板更新，保留用户自定义规则');
  info('  (4) 同步客户端配置 — 根据选择创建或移除客户端托管文件');
  info('  (5) 配置备份根目录');

  if (modeChanged) {
    info(`客户端模式已变化（${previousMode} → ${selectedMode}），自动同步 skills 目录`);
    createSkillsDirectory(targetDir, selectedMode);
  } else if (await promptUser("Step (1/5): 是否更新 skills？（将覆盖现有 skill 文件）", force)) {
    createSkillsDirectory(targetDir, selectedMode);
  } else {
    info('已跳过更新 skills');
  }

  if (modeChanged) {
    info('客户端模式已变化，自动更新 AGENTS.md 以修正备份路径');
    updateAgentsFile(targetDir, selectedMode);
  } else if (await promptUser("Step (2/5): 是否更新 AGENTS.md？（模板章节将刷新，用户偏好和自定义配置章节将保留）", force)) {
    updateAgentsFile(targetDir, selectedMode);
  } else {
    info('已跳过更新 AGENTS.md');
  }

  if (await promptUser("Step (3/5): 是否更新 .wiki_ignore？（默认规则将刷新，用户自定义规则将保留）", force)) {
    mergeWikiIgnore(targetDir, selectedMode);
  } else {
    info('已跳过更新 .wiki_ignore');
  }

  info('Step (4/5): 同步客户端配置');
  syncClientSupportFiles(targetDir, selectedMode);

  if (await promptUser("Step (5/5): 是否修改备份根目录？", force)) {
    await configureBackup(targetDir, selectedMode, force);
  } else {
    info('已跳过备份配置');
  }

  console.log('');
  success('更新安装完成！');
  await configureVisionReaderPrompt(targetDir, selectedMode, force);
}
