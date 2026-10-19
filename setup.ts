#!/usr/bin/env npx tsx
/**
 * Setup Wizard for Antigravity (agy) Skills & Infrastructure Template
 *
 * Run from inside this template repo to install into another project:
 *   npx tsx setup.ts ~/my-project
 *
 * Non-interactive:
 *   npx tsx setup.ts ~/my-project --yes
 *   npx tsx setup.ts ~/my-project --yes --mode fallback --provider gemini
 */

import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as readline from 'node:readline/promises';
import { execSync } from 'child_process';
import { parseArgs } from 'node:util';

let rl: readline.Interface | null = null;

function getRl(): readline.Interface {
    if (!rl) {
        rl = readline.createInterface({
            input: process.stdin,
            output: process.stdout,
        });
    }
    return rl;
}

function closeRl(): void {
    if (rl) {
        rl.close();
        rl = null;
    }
}

// ============================================================
// CLI ARGUMENTS
// ============================================================

const VALID_MODES = ['disabled', 'fallback', 'ai-only'];
const VALID_PROVIDERS = ['auto', 'gemini', 'openai', 'anthropic', 'ollama'];
const VALID_CONSERVATIVENESS = ['strict', 'balanced', 'aggressive'];

interface CliOptions {
    yes: boolean;
    mode: string;
    provider: string;
    conservativeness: string;
    editor: boolean;
    targetArg: string | undefined;
}

function printUsage(): void {
    console.log(`
Usage: npx tsx setup.ts [target-project-path] [options]

Interactive (default):
  npx tsx setup.ts ~/my-project

Non-interactive:
  npx tsx setup.ts ~/my-project --yes
  npx tsx setup.ts ~/my-project --yes --mode fallback --provider gemini

Options:
  -y, --yes                  Accept defaults, never prompt
      --mode <m>             disabled | fallback | ai-only                 (default: disabled)
      --provider <p>         auto | gemini | openai | anthropic | ollama   (default: auto)
      --conservativeness <c> strict | balanced | aggressive                (default: balanced)
      --editor               Also install the NeoVim editor config         (default: skip)
  -h, --help                 Show this help
`);
}

function parseCliOptions(): CliOptions {
    let values: { [key: string]: unknown };
    let positionals: string[];
    try {
        ({ values, positionals } = parseArgs({
            args: process.argv.slice(2),
            options: {
                yes: { type: 'boolean', short: 'y', default: false },
                mode: { type: 'string', default: 'disabled' },
                provider: { type: 'string', default: 'auto' },
                conservativeness: { type: 'string', default: 'balanced' },
                editor: { type: 'boolean', default: false },
                help: { type: 'boolean', short: 'h', default: false },
            },
            allowPositionals: true,
        }));
    } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        printUsage();
        process.exit(1);
    }

    if (values.help) {
        printUsage();
        process.exit(0);
    }

    const mode = values.mode as string;
    const provider = values.provider as string;
    const conservativeness = values.conservativeness as string;

    if (!VALID_MODES.includes(mode)) {
        console.error(`Error: invalid --mode "${mode}" (expected: ${VALID_MODES.join(' | ')})`);
        process.exit(1);
    }
    if (!VALID_PROVIDERS.includes(provider)) {
        console.error(`Error: invalid --provider "${provider}" (expected: ${VALID_PROVIDERS.join(' | ')})`);
        process.exit(1);
    }
    if (!VALID_CONSERVATIVENESS.includes(conservativeness)) {
        console.error(`Error: invalid --conservativeness "${conservativeness}" (expected: ${VALID_CONSERVATIVENESS.join(' | ')})`);
        process.exit(1);
    }

    return {
        yes: values.yes as boolean,
        mode,
        provider,
        conservativeness,
        editor: values.editor as boolean,
        targetArg: positionals[0],
    };
}

// ============================================================
// HELPERS
// ============================================================

async function promptChoice(question: string, choices: string[], defaultIdx: number = 0): Promise<number> {
    console.log(`\n${question}`);
    choices.forEach((c, i) => {
        const marker = i === defaultIdx ? ' (default)' : '';
        console.log(`  [${i + 1}] ${c}${marker}`);
    });

    const answer = await getRl().question(`\nChoice [${defaultIdx + 1}]: `);
    const num = parseInt(answer.trim(), 10);
    if (isNaN(num) || num < 1 || num > choices.length) {
        return defaultIdx;
    }
    return num - 1;
}

async function promptString(question: string, defaultVal: string = ''): Promise<string> {
    const suffix = defaultVal ? ` [${defaultVal}]` : '';
    const answer = await getRl().question(`${question}${suffix}: `);
    return answer.trim() || defaultVal;
}

function copyDirRecursive(src: string, dest: string, exclude: string[] = []): number {
    let count = 0;
    if (!fs.existsSync(dest)) {
        fs.mkdirSync(dest, { recursive: true });
    }

    const entries = fs.readdirSync(src, { withFileTypes: true });
    for (const entry of entries) {
        if (exclude.includes(entry.name)) continue;

        const srcPath = path.join(src, entry.name);
        const destPath = path.join(dest, entry.name);

        if (entry.isDirectory()) {
            count += copyDirRecursive(srcPath, destPath, exclude);
        } else {
            fs.copyFileSync(srcPath, destPath);
            count++;
        }
    }
    return count;
}

// ============================================================
// TECH STACK DETECTION
// ============================================================

interface DetectedStack {
    hasReact: boolean;
    hasExpress: boolean;
    hasTypescript: boolean;
    hasPrisma: boolean;
    hasSentry: boolean;
    hasMUI: boolean;
    hasTanStack: boolean;
}

function detectTechStack(projectDir: string): DetectedStack {
    const stack: DetectedStack = {
        hasReact: false,
        hasExpress: false,
        hasTypescript: false,
        hasPrisma: false,
        hasSentry: false,
        hasMUI: false,
        hasTanStack: false,
    };

    const packagePaths = [
        'package.json',
        'frontend/package.json',
        'client/package.json',
        'web/package.json',
        'api/package.json',
        'server/package.json',
        'backend/package.json',
    ];

    for (const pkgPath of packagePaths) {
        const fullPath = path.join(projectDir, pkgPath);
        if (!fs.existsSync(fullPath)) continue;

        try {
            const pkg = JSON.parse(fs.readFileSync(fullPath, 'utf-8'));
            const allDeps = { ...pkg.dependencies, ...pkg.devDependencies };

            if (allDeps['react']) stack.hasReact = true;
            if (allDeps['express']) stack.hasExpress = true;
            if (allDeps['typescript']) stack.hasTypescript = true;
            if (allDeps['prisma'] || allDeps['@prisma/client']) stack.hasPrisma = true;
            if (allDeps['@sentry/node'] || allDeps['@sentry/react']) stack.hasSentry = true;
            if (allDeps['@mui/material']) stack.hasMUI = true;
            if (allDeps['@tanstack/react-query'] || allDeps['@tanstack/react-router']) stack.hasTanStack = true;
        } catch {
            // Skip invalid package.json
        }
    }

    if (fs.existsSync(path.join(projectDir, 'tsconfig.json'))) stack.hasTypescript = true;
    if (fs.existsSync(path.join(projectDir, 'prisma'))) stack.hasPrisma = true;

    return stack;
}

async function validateProvider(provider: string): Promise<boolean> {
    switch (provider) {
        case 'gemini': {
            if (!process.env.GEMINI_API_KEY) {
                console.log('\n  GEMINI_API_KEY not found in environment.');
                console.log('  Get a free key: https://aistudio.google.com/apikey');
                return false;
            }
            console.log('  GEMINI_API_KEY found.');
            return true;
        }
        case 'openai': {
            if (!process.env.OPENAI_API_KEY) {
                console.log('\n  OPENAI_API_KEY not found in environment.');
                return false;
            }
            console.log('  OPENAI_API_KEY found.');
            return true;
        }
        case 'anthropic': {
            if (!process.env.ANTHROPIC_API_KEY) {
                console.log('\n  ANTHROPIC_API_KEY not found in environment.');
                return false;
            }
            console.log('  ANTHROPIC_API_KEY found.');
            return true;
        }
        case 'ollama': {
            console.log('  Checking Ollama availability...');
            try {
                const controller = new AbortController();
                const timeout = setTimeout(() => controller.abort(), 2000);
                const baseUrl = process.env.OLLAMA_BASE_URL || 'http://localhost:11434';
                const response = await fetch(`${baseUrl}/api/tags`, { signal: controller.signal });
                clearTimeout(timeout);
                if (response.ok) {
                    console.log('  Ollama is running.');
                    return true;
                }
            } catch {
                // Fall through
            }
            console.log('\n  Ollama not available at localhost:11434.');
            return false;
        }
        default:
            return false;
    }
}

// ============================================================
// MAIN
// ============================================================

async function main() {
    const opts = parseCliOptions();
    const nonInteractive = opts.yes;

    const nodeMajor = parseInt(process.versions.node, 10);
    if (nodeMajor < 18) {
        console.error(`Error: Node 18+ required (20+ recommended), found v${process.versions.node}`);
        closeRl();
        process.exit(1);
    }

    if (!process.stdin.isTTY && !nonInteractive) {
        console.error('Error: stdin is not a terminal, run with --yes to accept defaults.');
        process.exit(1);
    }

    console.log('');
    console.log('============================================================');
    console.log('  Antigravity (agy) Infrastructure Setup Wizard');
    console.log('============================================================');

    const scriptDir = path.dirname(new URL(import.meta.url).pathname);
    const sourceAgentsDir = path.join(scriptDir, '.agents');

    let targetDir = process.cwd();
    if (opts.targetArg) {
        targetDir = path.resolve(opts.targetArg);
    }

    // Running inside template repo itself: self-verification mode
    const isSelf = path.resolve(targetDir) === path.resolve(scriptDir);
    if (isSelf) {
        console.log('\n  Running inside template repository (Self-Verification Mode).');
        const verifyScript = path.join(scriptDir, '.agents', 'scripts', 'verify-setup.sh');
        if (fs.existsSync(verifyScript)) {
            try {
                execSync(`bash "${verifyScript}"`, {
                    cwd: targetDir,
                    stdio: 'inherit',
                    env: { ...process.env, AGY_PROJECT_DIR: targetDir },
                });
                console.log('\n  Template repository is in perfect working order!');
            } catch {
                console.log('\n  Some verification checks had warnings or failures.');
            }
        }
        closeRl();
        process.exit(0);
    }

    // Target setup
    if (!fs.existsSync(targetDir)) {
        fs.mkdirSync(targetDir, { recursive: true });
        console.log(`\n  Created target directory: ${targetDir}`);
    }

    console.log(`  Source: ${scriptDir}`);
    console.log(`  Target: ${targetDir}`);

    // Detect tech stack
    console.log('\n--- Tech Stack Detection ---');
    const stack = detectTechStack(targetDir);
    const detected: string[] = [];
    if (stack.hasTypescript) detected.push('TypeScript');
    if (stack.hasReact) detected.push('React');
    if (stack.hasExpress) detected.push('Express');
    if (stack.hasPrisma) detected.push('Prisma');
    if (stack.hasMUI) detected.push('MUI');
    if (stack.hasTanStack) detected.push('TanStack');
    if (stack.hasSentry) detected.push('Sentry');

    if (detected.length > 0) {
        console.log(`  Detected: ${detected.join(', ')}`);
    } else {
        console.log('  No specific frameworks detected (using generic config).');
    }

    const selectedMode = opts.mode;
    const selectedProvider = opts.provider;
    const conservativeness = opts.conservativeness;

    console.log('\n--- Installing Antigravity Infrastructure ---');

    const copyExclude = [
        'node_modules',
        'state',
        'data',
        'memory',
        'skill-guard.log',
        'cache',
        'tsc-cache',
    ];

    const dest = path.join(targetDir, '.agents');
    const count = copyDirRecursive(sourceAgentsDir, dest, copyExclude);
    console.log(`  Copied ${count} files to ${dest}`);

    // Copy root AGENTS.md if target doesn't have one
    const rootAgentsMdSrc = path.join(scriptDir, 'AGENTS.md');
    const rootAgentsMdDest = path.join(targetDir, 'AGENTS.md');
    if (fs.existsSync(rootAgentsMdSrc) && !fs.existsSync(rootAgentsMdDest)) {
        fs.copyFileSync(rootAgentsMdSrc, rootAgentsMdDest);
        console.log('  Copied AGENTS.md to project root');
    }

    const hooksDir = path.join(dest, 'hooks');
    if (fs.existsSync(hooksDir)) {
        try {
            execSync('chmod +x *.sh', { cwd: hooksDir, stdio: 'pipe' });
        } catch {}
    }
    const scriptsDir = path.join(dest, 'scripts');
    if (fs.existsSync(scriptsDir)) {
        try {
            execSync('chmod +x *.sh', { cwd: scriptsDir, stdio: 'pipe' });
        } catch {}
    }

    const rulesPath = path.join(dest, 'skills', 'skill-rules.json');
    if (fs.existsSync(rulesPath)) {
        try {
            const rules = JSON.parse(fs.readFileSync(rulesPath, 'utf-8'));
            rules.settings = { skill_activation_mode: selectedMode, conservativeness };
            fs.writeFileSync(rulesPath, JSON.stringify(rules, null, 4));
        } catch {}
    }

    if (fs.existsSync(path.join(hooksDir, 'package.json'))) {
        console.log('  Installing hook dependencies in target project...');
        try {
            execSync('npm install', { cwd: hooksDir, stdio: 'pipe' });
            console.log('  Hook dependencies installed.');
        } catch {
            console.log('  Note: Run cd ' + hooksDir + ' && npm install manually.');
        }
    }

    // Verify
    const verifyScript = path.join(dest, 'scripts', 'verify-setup.sh');
    if (fs.existsSync(verifyScript)) {
        console.log('\n--- Verifying Target Installation ---');
        try {
            execSync(`bash "${verifyScript}"`, {
                cwd: targetDir,
                stdio: 'inherit',
                env: { ...process.env, AGY_PROJECT_DIR: targetDir },
            });
        } catch {}
    }

    console.log('\nSetup Complete for target project!');
    closeRl();
}

main().catch(err => {
    console.error('Setup error:', err);
    closeRl();
    process.exit(1);
});
