import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { execSync } from 'node:child_process';
import { createInterface } from 'node:readline';
import chalk from 'chalk';
import { error, success, info, warning } from './utils.js';

function rl() {
  return createInterface({ input: process.stdin, output: process.stdout });
}

function question(query) {
  return new Promise(resolve => {
    const i = rl();
    i.question(query, answer => { i.close(); resolve(answer.trim()); });
  });
}

function isKbDir(targetDir) {
  const agentsFile = resolve(targetDir, 'AGENTS.md');
  const wikiDir = resolve(targetDir, '.wiki');
  if (!existsSync(agentsFile)) return false;
  if (!existsSync(wikiDir)) return false;
  return true;
}

function findOpencodeCli() {
  try {
    execSync('opencode --version', { stdio: 'ignore' });
    return 'opencode';
  } catch {}
  const candidates = [
    resolve(process.env.HOME || '', '.opencode', 'opencode'),
    resolve(process.env.HOME || '', '.npm-global', 'bin', 'opencode'),
    resolve(process.env.HOME || '', '.local', 'bin', 'opencode'),
    resolve(process.env.HOME || '', 'bin', 'opencode'),
    '/usr/local/bin/opencode',
    '/opt/homebrew/bin/opencode',
  ];
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }
  return null;
}

function readOpencodeConfigModel(targetDir) {
  const configFiles = [
    resolve(process.env.HOME || '', '.config', 'opencode', 'opencode.json'),
    resolve(process.env.HOME || '', '.config', 'opencode', 'opencode.jsonc'),
  ];
  if (targetDir) {
    configFiles.push(resolve(targetDir, 'opencode.json'));
    configFiles.push(resolve(targetDir, 'opencode.jsonc'));
  }
  for (const f of configFiles) {
    if (!existsSync(f)) continue;
    try {
      const content = readFileSync(f, 'utf-8');
      const m = content.match(/"model"\s*:\s*"([^"]+)"/);
      if (m && m[1] && m[1].includes('/')) return m[1];
    } catch {}
  }
  return null;
}

function parseExistingConfig(configFile) {
  if (!existsSync(configFile)) return null;
  const content = readFileSync(configFile, 'utf-8');
  const m = content.match(/^model:\s*(\S+)/m);
  if (!m || !m[1] || m[1] === '/') return null;
  const model = m[1];

  const apiMatch = content.match(/apiKey:\s*"{env:([^}]+)}"/);
  const apiKeyEnv = apiMatch ? apiMatch[1] : null;

  return { model, apiKeyEnv };
}

function getOpencodeModels() {
  const cli = findOpencodeCli();
  if (!cli) return null;

  info('正在获取可用 provider 和模型列表...');
  try {
    const output = execSync(`${cli} models 2>&1`, { encoding: 'utf-8', timeout: 30000 });
    const models = output.split('\n')
      .map(l => l.trim())
      .filter(l => /^[a-zA-Z0-9_./-]+$/.test(l))
      .slice(0, 30);
    return models.length > 0 ? models : null;
  } catch {
    warning('无法执行 opencode models');
    return null;
  }
}

async function selectModelInteractive(models) {
  const count = models.length;
  console.log('');
  info('检测到以下可用模型:');
  console.log('');
  for (let i = 0; i < count; i++) {
    console.log(`  [${String(i + 1).padStart(2)}] ${models[i]}`);
  }
  console.log('');
  console.log('  [ 0] 手动输入 provider 和 model');

  while (true) {
    const choice = await question(chalk.blue(`[选择] 请输入序号选择模型 (0-${count}): `));
    if (choice === '0') return null;
    const num = parseInt(choice, 10);
    if (num >= 1 && num <= count) {
      const selected = models[num - 1];
      success(`已选择模型: ${selected}`);
      return selected;
    }
    error('无效选择，请重试');
  }
}

async function manualConfig() {
  info('手动配置 vision-reader subagent:');
  console.log('');

  let provider = '';
  while (!provider) {
    provider = await question(chalk.blue('[输入] Provider ID (如 anthropic, openai, deepseek): '));
    if (!provider) error('Provider 不能为空');
  }

  let modelId = '';
  while (!modelId) {
    modelId = await question(chalk.blue('[输入] Model ID (如 claude-sonnet-4-20250514, gpt-4o): '));
    if (!modelId) error('Model ID 不能为空');
  }

  console.log('');
  const apiKeyEnv = await question(chalk.blue('[输入] API Key 环境变量名 (如 ANTHROPIC_API_KEY，如已全局配置可留空): '));
  console.log('');

  const selected = `${provider}/${modelId}`;
  success(`已配置模型: ${selected}`);
  return { model: selected, apiKeyEnv };
}

function writeAgentConfig(targetDir, model, apiKeyEnv) {
  const configDir = resolve(targetDir, '.opencode', 'agents');
  const configFile = resolve(configDir, 'vision-reader.md');
  mkdirSync(configDir, { recursive: true });

  let extraFields = '';
  if (apiKeyEnv) {
    const provider = model.split('/')[0];
    extraFields = `
provider:
  ${provider}:
    options:
      apiKey: "{env:${apiKeyEnv}}"`;
  }

  const content = `---
description: 视觉内容读取器，读取文件中的图片、图表、截图、幻灯片、文档排版等视觉元素，转化为文字描述
mode: subagent
model: ${model}
permission:
  edit: deny
  bash: deny
  task: deny
  webfetch: deny
  skill: deny${extraFields}
---
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

  writeFileSync(configFile, content, 'utf-8');
  success(`已保存配置: ${configFile}`);
  return configFile;
}

function printCompletion(targetDir, model, apiKeyEnv, configFile) {
  console.log('');
  console.log('======================================');
  success('vision-reader subagent 配置完成！');
  console.log('======================================');
  console.log('');
  console.log(`模型: ${model}`);
  if (apiKeyEnv) console.log(`API Key: 环境变量 ${apiKeyEnv}`);
  console.log('');
  console.log(`配置文件: ${configFile}`);
  console.log('');
  console.log('提示: 你可能需要将此文件添加到 .gitignore（如果包含敏感配置）:');
  console.log(`  echo '.opencode/agents/vision-reader.md' >> ${resolve(targetDir, '.gitignore')}`);
  console.log('');
  console.log('配置完成后，使用知识库时 Agent 会自动在遇到视觉内容时调用 vision-reader。');
  console.log('');
  console.log('注：本脚本仅配置 OpenCode 版 vision-reader。Claude Code 版（.claude/agents/vision-reader.md）与 Codex 版（.codex/agents/vision-reader.toml）由安装器在启用对应客户端支持时自动生成。');
  console.log('');
}

export async function configureVisionReader(targetDir, options = {}) {
  const force = options.force || false;

  targetDir = resolve(targetDir);

  if (!existsSync(targetDir)) {
    error(`目标目录不存在: ${targetDir}`);
    process.exit(1);
  }

  if (!isKbDir(targetDir)) {
    error('目标目录不是有效的知微知识库（缺少 AGENTS.md 或 .wiki/ 目录）');
    info('请先运行 zhiwei init 安装知微');
    process.exit(1);
  }

  info(`目标知识库路径: ${targetDir}`);

  const configFile = resolve(targetDir, '.opencode', 'agents', 'vision-reader.md');
  let configExists = false;
  let existingModel = null;
  let existingApiKeyEnv = null;

  // S2: Detect existing config
  if (existsSync(configFile)) {
    configExists = true;
    console.log('');
    info('检测到已有 vision-reader 配置');
    console.log('');
    console.log('当前配置:');
    console.log('----------------------------------------');
    console.log(readFileSync(configFile, 'utf-8'));
    console.log('----------------------------------------');
    console.log('');

    if (!force) {
      const answer = await question(chalk.yellow('[询问] 是否更新此配置？ [Y/n] '));
      if (/^[nN](o|O)?$/.test(answer)) {
        info('已取消，保留现有配置');
        return;
      }
    }

    const parsed = parseExistingConfig(configFile);
    if (parsed) {
      existingModel = parsed.model;
      existingApiKeyEnv = parsed.apiKeyEnv;
    }
  }

  console.log('');
  info('开始配置 vision-reader subagent...');
  console.log('');

  let model = null;
  let apiKeyEnv = null;

  if (configExists) {
    const updateAnswer = await question(chalk.yellow('[询问] 是否更新模型选择？ [Y/n] '));
    const updateModel = !/^[nN](o|O)?$/.test(updateAnswer);

    if (updateModel) {
      // S2.1: full model selection
      const models = getOpencodeModels();
      if (models) {
        model = await selectModelInteractive(models);
      }
      if (!model) {
        const configModel = readOpencodeConfigModel(targetDir);
        if (configModel) {
          info(`从 opencode 配置文件中检测到模型: ${configModel}`);
          model = configModel;
        }
      }
      if (!model) {
        const result = await manualConfig();
        model = result.model;
        apiKeyEnv = result.apiKeyEnv;
      }
    } else if (existingModel) {
      // S2.2: preserve existing model
      info(`保留现有模型: ${existingModel}`);
      model = existingModel;
      apiKeyEnv = existingApiKeyEnv;
    } else {
      warning('无法从现有配置中提取模型，将进入模型选择');
      const models = getOpencodeModels();
      if (models) {
        model = await selectModelInteractive(models);
      }
      if (!model) {
        model = readOpencodeConfigModel(targetDir);
      }
      if (!model) {
        const result = await manualConfig();
        model = result.model;
        apiKeyEnv = result.apiKeyEnv;
      }
    }
  } else {
    // No existing config: always do model selection
    const models = getOpencodeModels();
    if (models) {
      model = await selectModelInteractive(models);
    }
    if (!model) {
      model = readOpencodeConfigModel(targetDir);
    }
    if (!model) {
      const result = await manualConfig();
      model = result.model;
      apiKeyEnv = result.apiKeyEnv;
    }
  }

  // Validate
  if (!model || model === '/') {
    error('配置不完整（模型信息缺失），未保存');
    process.exit(1);
  }

  const savedFile = writeAgentConfig(targetDir, model, apiKeyEnv);
  printCompletion(targetDir, model, apiKeyEnv, savedFile);
}
