import { Command } from 'commander';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { install } from './install.js';
import { configureVisionReader } from './config-vision-reader.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const pkgPath = resolve(__dirname, '..', 'package.json');

function getVersion() {
  try {
    const pkg = JSON.parse(readFileSync(pkgPath, 'utf-8'));
    return pkg.version;
  } catch {
    return '1.0.0';
  }
}

export function runCli() {
  const program = new Command();

  program
    .name('zhiwei')
    .description('知微（zhiwei）—— Agent Skills 驱动的个人知识库构建工具')
    .version(getVersion());

  program
    .command('init')
    .description('初始化安装或更新知微到指定的知识库目录')
    .argument('<target-dir>', '要安装知微的知识库目录路径')
    .option('-f, --force', '强制覆盖（更新安装时自动确认所有步骤）')
    .option('-m, --mode <mode>', '客户端模式: opencode, claude, codex')
    .action(async (targetDir, options) => {
      await install(targetDir, options);
    });

  program
    .command('config-vision-reader')
    .description('配置 OpenCode 版 vision-reader subagent')
    .argument('<target-dir>', '已安装知微的知识库目录路径')
    .option('-f, --force', '更新模式跳过确认')
    .action(async (targetDir, options) => {
      await configureVisionReader(targetDir, options);
    });

  program.parse(process.argv);
}
