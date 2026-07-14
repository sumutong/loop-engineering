#!/usr/bin/env node
// loop-engineering install CLI
// 将 loop-engineering skill 安装到 Claude Code 项目

import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync, copyFileSync, lstatSync, realpathSync, rmSync } from 'fs';
import { resolve, dirname, join, relative } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PKG = JSON.parse(readFileSync(resolve(__dirname, '..', 'package.json'), 'utf8'));
const SKILL_SRC = resolve(__dirname, '..', 'skills', 'loop-engineering');
const PROJECT_DIR = process.cwd();

// ============================================================
// 递归复制目录（跨平台）
// ============================================================
function copyDirSync(src, dest) {
  let realSrc = src;
  try { realSrc = realpathSync(src); } catch {}

  mkdirSync(dest, { recursive: true });
  const entries = readdirSync(realSrc, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = join(realSrc, entry.name);
    const destPath = join(dest, entry.name);
    let stat;
    try { stat = lstatSync(srcPath); } catch { continue; }
    if (stat.isDirectory()) {
      copyDirSync(srcPath, destPath);
    } else if (stat.isFile()) {
      copyFileSync(srcPath, destPath);
    }
  }
}

function countDirs(dir) {
  try {
    return readdirSync(dir, { withFileTypes: true })
      .filter(e => e.isDirectory()).length;
  } catch { return 0; }
}

function detectTarget() {
  if (existsSync(join(PROJECT_DIR, '.claude'))) {
    return { name: 'Claude Code', dir: '.claude/skills/loop-engineering', desc: '.claude' };
  }
  if (existsSync(join(PROJECT_DIR, '.hermes'))) {
    return { name: 'Hermes Agent', dir: '.hermes/skills/loop-engineering', desc: '.hermes' };
  }
  return null;
}

function updateClaudeMd() {
  const mdPath = join(PROJECT_DIR, 'CLAUDE.md');
  const bootstrap = `\n## Loop Engineering\n\n本项目已安装 [loop-engineering](https://github.com/jnMetaCode/loop-engineering) skill — AI 编程第四层范式（Prompt → Context → Harness → Loop）。\n\n设计一个自收敛循环：\`帮我设计一个 CI 自动修复 loop\`\n`;

  if (existsSync(mdPath)) {
    const content = readFileSync(mdPath, 'utf8');
    if (content.includes('loop-engineering')) return;
    writeFileSync(mdPath, content + bootstrap, 'utf8');
    console.log('  ✅ CLAUDE.md 已追加 loop-engineering 引用');
  } else {
    writeFileSync(mdPath, bootstrap.trim() + '\n', 'utf8');
    console.log('  ✅ 已创建 CLAUDE.md（含 loop-engineering 引用）');
  }
}

function uninstall() {
  const target = detectTarget();
  if (!target) {
    console.log('  ⚠️ 未检测到支持的 AI 编程工具目录');
    return;
  }
  const dest = resolve(PROJECT_DIR, target.dir);
  if (existsSync(dest)) {
    rmSync(dest, { recursive: true, force: true });
    console.log(`  ✅ 已从 ${target.name} 卸载 loop-engineering`);
  } else {
    console.log(`  ℹ️ ${target.name} 中未安装 loop-engineering`);
  }
}

function showHelp() {
  console.log(`
  loop-engineering v${PKG.version} — AI 编程第四层范式

  用法：
    npx loop-engineering                 自动检测工具并安装
    npx loop-engineering --uninstall     卸载
    npx loop-engineering --help          显示帮助
    npx loop-engineering --version       显示版本

  支持的 AI 编程工具：
    Claude Code (`.claude/`)
    Hermes Agent (`.hermes/`)

  安装后使用：
    设计循环：在 Claude Code 中说 "帮我设计一个 CI 自动修复 loop"
    执行循环：在 Claude Code 中说 "运行 .loop/contracts/xxx.yaml"
    审查契约：在 Claude Code 中说 "审查 .loop/contracts/xxx.yaml"

  文档：https://github.com/jnMetaCode/loop-engineering
`);
}

// ============================================================
// 主流程
// ============================================================
const args = process.argv.slice(2);

if (args.includes('--help') || args.includes('-h')) {
  showHelp();
  process.exit(0);
}

if (args.includes('--version') || args.includes('-v')) {
  console.log(`v${PKG.version}`);
  process.exit(0);
}

if (args.includes('--uninstall')) {
  console.log(`\n  loop-engineering v${PKG.version} — 卸载`);
  uninstall();
  console.log();
  process.exit(0);
}

console.log(`\n  loop-engineering v${PKG.version} — AI 编程第四层范式`);
console.log(`  目标项目: ${PROJECT_DIR}\n`);

const target = detectTarget();
if (!target) {
  console.log('  ⚠️ 未检测到 .claude/ 或 .hermes/ 目录。');
  console.log('  请确认当前目录是 Claude Code 或 Hermes Agent 项目的根目录。\n');
  process.exit(1);
}

const dest = resolve(PROJECT_DIR, target.dir);
console.log(`  ${target.name}: 安装 loop-engineering -> ${relative(PROJECT_DIR, dest)}`);

copyDirSync(SKILL_SRC, dest);

const fileCount = readdirSync(dest, { recursive: true, withFileTypes: true })
  .filter(e => e.isFile()).length;
console.log(`  ✅ ${target.name}: ${fileCount} 个文件 -> ${relative(PROJECT_DIR, dest)}`);

updateClaudeMd();

// 检查 superpowers-zh 依赖
const SP_SKILL = '.claude/skills/superpowers-zh/SKILL.md';
if (!existsSync(join(PROJECT_DIR, SP_SKILL))) {
  console.log(`\n  ⚠️  依赖缺失: superpowers-zh（loop-engineering 运行时需要）`);
  console.log(`  正在安装: npx superpowers-zh`);
  const { execSync } = require('child_process');
  try {
    execSync('npx superpowers-zh', { cwd: PROJECT_DIR, stdio: 'inherit' });
    console.log(`  ✅ superpowers-zh 安装完成`);
  } catch {
    console.log(`  ⚠️  npx superpowers-zh 失败，请手动安装:\n     npx superpowers-zh`);
  }
}

console.log(`\n  安装完成！重启 Claude Code 即可使用。\n`);
console.log(`  快速体验：在 Claude Code 中说 "帮我设计一个 CI 自动修复 loop"\n`);
