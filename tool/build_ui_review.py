"""Build the local screenshot review gallery without external resources."""

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROUTES = [
    ("dashboard", "今日"), ("words", "单词本"), ("words1", "词条详情"),
    ("study", "复习"), ("add", "添加"), ("article", "文章提词"),
    ("import", "CSV 导入"), ("initialize", "内容补全"),
    ("statistics", "统计"), ("settings", "设置"), ("games", "小游戏"),
    ("match", "配对"), ("phonetics", "音标"),
]

PAGE = """<!doctype html>
<html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>词环 · 彩色分区预览</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#edf3fb;color:#242a27;
font:15px system-ui,sans-serif;padding:24px}h1{font-size:26px;margin:0 0 8px}
p,small{color:#52645c}nav{display:flex;gap:12px;flex-wrap:wrap;margin:24px 0}
select{font:inherit;padding:8px 12px;border:1px solid #bbcbdc;background:white;
border-radius:10px;color:inherit}main{display:grid;
grid-template-columns:repeat(auto-fit,minmax(min(100%,400px),1fr));gap:24px}
article{background:white;border-radius:18px;padding:16px}h2{font-size:17px;
margin:0 0 12px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:8px}
img{width:100%;height:auto;display:block;border-radius:8px;border:1px solid #dce5ef}
small{display:block;margin-bottom:6px}a{color:#137a57}details{margin-top:32px}
.states{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr));
gap:16px;margin-top:16px}
</style>
<h1>词环 · 彩色分区预览</h1>
<p>薄荷绿、浅蓝、淡紫与杏色区分内容层级。选择设备和外观，点击图片查看原图。
改前为改版基线，改后为当前配色；全部使用本地内存演示数据。</p>
<nav><select id="device" aria-label="设备"><option value="desktop">桌面</option>
<option value="phone">手机</option></select><select id="mode" aria-label="外观">
<option value="light">浅色</option><option value="dark">深色</option></select></nav>
<main id="pages"></main>
<details><summary>关键交互状态</summary><div class="states">__STATES__</div></details>
<script>
const routes=__ROUTES__;
const device=document.querySelector('#device');
const mode=document.querySelector('#mode');
const pages=document.querySelector('#pages');
function picture(source,label) {
  const box=document.createElement('div');
  const caption=document.createElement('small');caption.textContent=label;
  const link=document.createElement('a');link.href=source;
  const img=document.createElement('img');img.src=source;img.alt=label;img.loading='lazy';
  link.append(img);box.append(caption,link);return box;
}
function render() {
  pages.replaceChildren();
  const suffix=(device.value==='phone'?'_phone':'')+(mode.value==='dark'?'_dark':'');
  for(const [name,label] of routes) {
    const card=document.createElement('article');
    const heading=document.createElement('h2');heading.textContent=label;
    const pair=document.createElement('div');pair.className='pair';
    pair.append(picture('screens_before/'+name+suffix+'.png','改前'),
      picture('screens/'+name+suffix+'.png','改后'));
    card.append(heading,pair);pages.append(card);
  }
}
device.addEventListener('change',render);mode.addEventListener('change',render);render();
</script></html>
"""


def main():
    states = []
    for path in sorted((ROOT / "build/screens/states").glob("*.png")):
        source = html.escape(path.relative_to(ROOT / "build").as_posix(), quote=True)
        label = html.escape(path.stem)
        states.append(
            f'<article><small>{label}</small><a href="{source}">'
            f'<img loading="lazy" src="{source}" alt="{label}"></a></article>'
        )
    output = PAGE.replace("__ROUTES__", json.dumps(ROUTES, ensure_ascii=False))
    output = output.replace("__STATES__", "".join(states))
    (ROOT / "build/ui-review.html").write_text(output, encoding="utf-8")


if __name__ == "__main__":
    main()
