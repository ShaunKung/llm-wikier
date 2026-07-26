import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { existsSync, readFileSync, writeFileSync, mkdirSync, cpSync, rmSync, statSync } from 'node:fs';
import chalk from 'chalk';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PKG_ROOT = resolve(__dirname, '..');

export function getSkillsSource() {
  return resolve(PKG_ROOT, 'skills');
}

export function getTemplatesSource() {
  return resolve(PKG_ROOT, 'templates');
}

export const LLM_WIKIER_SKILLS = [
  'wiki-init', 'wiki-ingest', 'wiki-query', 'wiki-lint',
  'wiki-update', 'wiki-prune', 'wiki-capture', 'wiki-backup',
];

export const CLAUDE_MANAGED_BEGIN = '<!-- LLM-WIKIER:CLAUDE-MANAGED:BEGIN -->';
export const CLAUDE_MANAGED_END = '<!-- LLM-WIKIER:CLAUDE-MANAGED:END -->';
export const CODEX_AGENT_MANAGED = 'LLM-WIKIER:CODEX-AGENT-MANAGED';

export function error(msg) { console.error(chalk.red('[错误]'), msg); }
export function success(msg) { console.log(chalk.green('[成功]'), msg); }
export function info(msg) { console.log(chalk.blue('[信息]'), msg); }
export function warning(msg) { console.log(chalk.yellow('[警告]'), msg); }

export function renderAgentsTemplate(inputPath, backupCommand) {
  let content = readFileSync(inputPath, 'utf-8');
  content = content.replace(/__WIKI_BACKUP_AUTO_COMMAND__/g, backupCommand);
  return content;
}

export function copySkills(srcDir, dstDir, skills) {
  mkdirSync(dstDir, { recursive: true });
  for (const skill of skills) {
    const src = resolve(srcDir, skill);
    const dst = resolve(dstDir, skill);
    if (existsSync(src)) {
      mkdirSync(dst, { recursive: true });
      cpSync(src, dst, { recursive: true, force: true });
      success(`安装 skill: ${skill}`);
    } else {
      warning(`找不到 skill 源文件: ${skill}`);
    }
  }
}

export function removeManagedSkills(dstDir, skills) {
  if (!existsSync(dstDir)) return;
  for (const skill of skills) {
    const dir = resolve(dstDir, skill);
    if (existsSync(dir)) {
      rmSync(dir, { recursive: true, force: true });
      info(`已移除旧 skill: ${dir}`);
    }
  }
  try {
    const remaining = readdirSync(dstDir);
    if (remaining.length === 0) {
      rmSync(dstDir, { recursive: true, force: true });
      const parent = resolve(dstDir, '..');
      const parentRemaining = readdirSync(parent);
      if (parentRemaining.length === 0) {
        rmSync(parent, { recursive: true, force: true });
      }
    }
  } catch {}
}

export function getActiveSkillsDir(targetDir, mode) {
  switch (mode) {
    case 'claude': return resolve(targetDir, '.claude', 'skills');
    case 'codex': return resolve(targetDir, '.agents', 'skills');
    default: return resolve(targetDir, '.opencode', 'skills');
  }
}

export function getInactiveSkillsDirs(targetDir, mode) {
  switch (mode) {
    case 'claude':
      return [resolve(targetDir, '.opencode', 'skills'), resolve(targetDir, '.agents', 'skills')];
    case 'codex':
      return [resolve(targetDir, '.opencode', 'skills'), resolve(targetDir, '.claude', 'skills')];
    default:
      return [resolve(targetDir, '.claude', 'skills'), resolve(targetDir, '.agents', 'skills')];
  }
}

export function getBackupAutoCommand(mode) {
  switch (mode) {
    case 'claude': return 'bash .claude/skills/wiki-backup/backup.sh --auto';
    case 'codex': return 'bash .agents/skills/wiki-backup/backup.sh --auto';
    default: return 'bash .opencode/skills/wiki-backup/backup.sh --auto';
  }
}

export function hasManagedClaudeSupport(targetDir) {
  const skillFile = resolve(targetDir, '.claude', 'skills', 'wiki-ingest', 'SKILL.md');
  if (existsSync(skillFile)) return true;
  const claudeFile = resolve(targetDir, 'CLAUDE.md');
  if (existsSync(claudeFile) && readFileSync(claudeFile, 'utf-8').includes(CLAUDE_MANAGED_BEGIN)) return true;
  return false;
}

export function hasManagedCodexSupport(targetDir) {
  const skillFile = resolve(targetDir, '.agents', 'skills', 'wiki-ingest', 'SKILL.md');
  if (existsSync(skillFile)) return true;
  const agentFile = resolve(targetDir, '.codex', 'agents', 'vision-reader.toml');
  if (existsSync(agentFile) && readFileSync(agentFile, 'utf-8').includes(CODEX_AGENT_MANAGED)) return true;
  return false;
}

export function detectCurrentMode(targetDir) {
  if (hasManagedCodexSupport(targetDir)) return 'codex';
  if (hasManagedClaudeSupport(targetDir)) return 'claude';
  return 'opencode';
}

export function getExistingBackupRoot(targetDir) {
  const candidates = [
    resolve(targetDir, '.opencode', 'skills', 'wiki-backup', 'backup.sh'),
    resolve(targetDir, '.claude', 'skills', 'wiki-backup', 'backup.sh'),
    resolve(targetDir, '.agents', 'skills', 'wiki-backup', 'backup.sh'),
    resolve(targetDir, '.opencode', 'skills', 'wiki-backup', 'backup.ps1'),
    resolve(targetDir, '.claude', 'skills', 'wiki-backup', 'backup.ps1'),
    resolve(targetDir, '.agents', 'skills', 'wiki-backup', 'backup.ps1'),
  ];
  for (const file of candidates) {
    if (!existsSync(file)) continue;
    const lines = readFileSync(file, 'utf-8').split('\n');
    for (const line of lines) {
      let m;
      if ((m = line.match(/^BACKUP_ROOT="(.*)"$/)) && m[1] && m[1] !== '__BACKUP_ROOT__') return m[1];
      if ((m = line.match(/^\$script:BackupRoot = "(.*)"$/)) && m[1] && m[1] !== '__BACKUP_ROOT__') return m[1];
    }
  }
  return null;
}

export function writeBackupRoot(targetDir, mode, backupRoot) {
  const skillsDir = getActiveSkillsDir(targetDir, mode);
  const shFile = resolve(skillsDir, 'wiki-backup', 'backup.sh');
  if (existsSync(shFile)) {
    let content = readFileSync(shFile, 'utf-8');
    content = content.replace(/^BACKUP_ROOT=".*"$/m, `BACKUP_ROOT="${backupRoot}"`);
    writeFileSync(shFile, content, 'utf-8');
  }
  const ps1File = resolve(skillsDir, 'wiki-backup', 'backup.ps1');
  if (existsSync(ps1File)) {
    let content = readFileSync(ps1File, 'utf-8');
    content = content.replace(/^\$script:BackupRoot = ".*"$/m, `$script:BackupRoot = "${backupRoot}"`);
    writeFileSync(ps1File, content, 'utf-8');
  }
}

export function replaceConfigLine(file, prefix, replacement) {
  if (!existsSync(file)) return;
  const lines = readFileSync(file, 'utf-8').split('\n');
  const result = lines.map(line => line.startsWith(prefix) ? replacement : line);
  writeFileSync(file, result.join('\n'), 'utf-8');
}

export function isTextFile(filePath) {
  const textExts = ['md','txt','json','yaml','yml','csv','xml','html','rst','org','tex','py','js','ts','java','cpp','c','go','rs','rb','php','css','scss','sql','sh','bash','zsh','conf','ini','log'];
  const ext = filePath.split('.').pop()?.toLowerCase();
  return textExts.includes(ext);
}

export function isImageFile(filePath) {
  const imgExts = ['png','jpg','jpeg','gif','webp','svg','bmp'];
  const ext = filePath.split('.').pop()?.toLowerCase();
  return imgExts.includes(ext);
}

export function isOfficeFile(filePath) {
  const officeExts = ['pdf','docx','doc','pptx','ppt','xlsx','xls','odt','odp','ods'];
  const ext = filePath.split('.').pop()?.toLowerCase();
  return officeExts.includes(ext);
}

export function isLinkFile(filePath) {
  return filePath.toLowerCase().endsWith('.url');
}
