#!/bin/bash

echo "✨ 准备更新系统与安装基本环境..."

# 更新系统包
sudo apt update && sudo apt install -y curl gnupg2 ca-certificates lsb-release

# 安装 Node.js 20 LTS
echo "✨ 安装 Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# 安装 pnpm
echo "✨ 安装 pnpm 包管理器..."
sudo npm install -g pnpm

# 创建项目目录
echo "✨ 创建 /opt/fetchIAP-server ..."
sudo mkdir -p /opt/fetchIAP-server
sudo chown $USER:$USER /opt/fetchIAP-server
cd /opt/fetchIAP-server

# 初始化项目
echo "✨ 初始化 Node.js 项目..."
pnpm init

# 安装依赖
echo "✨ 安装项目依赖..."
pnpm add puppeteer express dotenv cors

# 安装浏览器
echo "✨ 检测服务器架构并安装浏览器..."

ARCH=$(uname -m)

if [[ "$ARCH" == "x86_64" ]]; then
  echo "✅ 检测到 x86_64 架构，安装 Puppeteer内置 Chrome..."
  npx puppeteer browsers install chrome
  export CHROME_EXECUTABLE_PATH=""
elif [[ "$ARCH" == "aarch64" ]]; then
  echo "✅ 检测到 ARM64 架构，安装系统 Chromium..."
  sudo apt update
  sudo apt install -y chromium chromium-driver
  # 检查实际安装路径
  if [[ -x "$(command -v chromium)" ]]; then
    export CHROME_EXECUTABLE_PATH="$(command -v chromium)"
  elif [[ -x "$(command -v chromium-browser)" ]]; then
    export CHROME_EXECUTABLE_PATH="$(command -v chromium-browser)"
  else
    echo "❌ Chromium 安装失败，找不到可执行文件！"
    exit 1
  fi
else
  echo "⚠️ 未知架构: $ARCH，请手动安装浏览器！"
  exit 1
fi

echo "✨ 记录浏览器路径：$CHROME_EXECUTABLE_PATH"

# 把实际路径保存到 .env 文件
echo "CHROME_EXECUTABLE_PATH=\"$CHROME_EXECUTABLE_PATH\"" > /opt/fetchIAP-server/.env

# 安装 PM2 全局守护
echo "✨ 安装 PM2 进程守护工具..."
npm add pm2 -g

# 写入 fetchIAP.js（最新并发版）
cat > fetchIAP.js << 'EOF'
/*
 * @Author: Lao Qiao
 * @Date: 2025-04-28
 * 小美出品，必属精品 ✨
 */

const puppeteer = require('puppeteer');
require('dotenv').config(); // 加载环境变量

async function launchBrowser() {
  const executablePath = process.env.CHROME_EXECUTABLE_PATH || undefined;

  return puppeteer.launch({
    headless: 'new',
    executablePath: executablePath || undefined, // undefined 表示用 Puppeteer自带Chrome
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });
}

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// 国家-语言映射
const purchaseLabelMap = {
  us: 'In-App Purchases',
  cn: 'App 内购买项目',
  jp: 'アプリ内課金有り',
  kr: '앱 내 구입',
  fr: 'Achats intégrés',
  de: 'In‑App‑Käufe',
  it: 'Acquisti In-App',
  es: 'Compras dentro de la app',
  ru: 'Встроенные покупки',
};

// 智能滚动
async function autoScrollUntil(page, selector, timeout = 10000) {
  const start = Date.now();
  while ((Date.now() - start) < timeout) {
    const found = await page.evaluate(sel => !!document.querySelector(sel), selector);
    if (found) break;
    await page.evaluate(() => window.scrollBy(0, window.innerHeight / 2));
    await sleep(100);
  }
}

async function fetchIAP({ appId, country = 'us' }) {
  const url =  `https://apps.apple.com/${country}/app/id${appId}`;

 const browser = await launchBrowser();

  const page = await browser.newPage();

  try {
    await page.setExtraHTTPHeaders({ 'Accept-Language': 'en-US,en;q=0.9' });
    await page.setUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36');
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });

    await autoScrollUntil(page, 'dt.information-list__item__term');
    await sleep(500);

    const purchaseLabel = purchaseLabelMap[country.toLowerCase()] || 'In-App Purchases';

    const items = await page.evaluate(label => {
      const sections = Array.from(document.querySelectorAll('dt.information-list__item__term'));
      let matchedSection = null;

      for (const dt of sections) {
        if (dt.textContent.trim() === label) {
          matchedSection = dt.closest('.information-list__item');
          break;
        }
      }

      if (!matchedSection) return [];

      const results = [];
      matchedSection.querySelectorAll('li.list-with-numbers__item').forEach(li => {
        const name = li.querySelector('.list-with-numbers__item__title')?.textContent.trim();
        const price = li.querySelector('.list-with-numbers__item__price')?.textContent.trim();
        if (name && price) results.push({ name, price });
      });
      return results;
    }, purchaseLabel);

    return items;
  } finally {
    await browser.close();
  }
}

module.exports = { fetchIAP };
EOF

# 写入 server.js（最新并发+超时版）
cat > server.js << 'EOF'
/*
 * @Author: Lao Qiao
 * @Date: 2025-04-28
 * @FilePath: /fetchIAP-multi/server.js
 * 小美出品，必属精品 ✨
 */

const express = require('express');
const cors = require('cors');
const { fetchIAP } = require('./fetchIAP');

const app = express();
const port = 3000;
const TIMEOUT_PER_COUNTRY = 30000; // 每个国家超时时间(ms)

// CORS 配置选项
const corsOptions = {
  origin: '*', // 允许所有来源的请求 
  //origin: ['http://localhost:8080', 'http://yourfrontend.com'], // 允许的前端域名
  methods: ['GET', 'POST'],  // 允许的 HTTP 方法
  allowedHeaders: ['Content-Type', 'Authorization'], // 允许的请求头
  credentials: false // 由于使用了 origin: '*'，credentials 必须设为 false
};

// 启用 CORS，使用配置选项
app.use(cors(corsOptions));

app.use(express.json());

// 健康检查接口
app.get('/', (req, res) => {
  res.send('✨ FetchIAP Server 正常运行中！');
});

// 单国家查询，附带超时保护
const fetchIAPWithTimeout = (params, timeoutMs = 30000) => {
  return Promise.race([
    fetchIAP(params),
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error('抓取超时')), timeoutMs)
    ),
  ]);
};

app.post('/iap', async (req, res) => {
  const { appId, countries = [] } = req.body;

  if (!appId || !Array.isArray(countries) || countries.length === 0) {
    return res.status(400).json({ success: false, error: '请求必须包含 appId 和 countries 列表！' });
  }

  const isValidCountryCode = (code) => /^[a-z]{2}$/i.test(code);

  const invalidCountries = countries.filter(c => !isValidCountryCode(c));
  if (invalidCountries.length > 0) {
    return res.status(400).json({ success: false, error: `国家代码格式错误：${invalidCountries.join(', ')}` });
  }
  const results = {};

  try {
    for (const country of countries) {
      console.log(`✨ 查询 ${country.toUpperCase()}...`);

      try {
        const items = await fetchIAPWithTimeout({ appId, country }, TIMEOUT_PER_COUNTRY);
        results[country] = items;
      } catch (err) {
        console.error(`⚠️ 查询 ${country.toUpperCase()} 失败：${err.message}`);
        results[country] = { error: err.message };
      }
    }

    res.json({ success: true, data: results });
  } catch (err) {
    console.error('❌ 总体查询失败:', err);
    res.status(500).json({ success: false, error: '服务器内部错误', details: err.message });
  }
});

// 启动服务器
app.listen(port, () => {
  console.log(`🚀 FetchIAP Server 已启动，监听端口 ${port}`);
});
EOF

# 启动 PM2 守护
echo "✨ 使用 PM2 启动服务器..."
sudo pm2 start server.js --name fetchIAP-server
sudo pm2 save
sudo pm2 startup

echo "✅ 部署完成！API服务运行在 3000端口，由 PM2守护中！"