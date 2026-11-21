#!/usr/bin/env python3
"""Build the screenshot-based, two-page Chinese guide (reportlab + Pillow)."""
from pathlib import Path
from html import escape
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.platypus import Paragraph

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'docs/manual/screenshots'
VERSION = (ROOT / 'VERSION').read_text().strip()
OUTPUT = ROOT / f'output/pdf/DockCounts-{VERSION}-Quick-Guide-zh-CN.pdf'
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
pdfmetrics.registerFont(TTFont('Guide', '/System/Library/Fonts/Supplemental/Arial Unicode.ttf'))
pdfmetrics.registerFont(TTFont('GuideBold', '/System/Library/Fonts/STHeiti Medium.ttc', subfontIndex=0))
W,H = A4
M=42
CW=W-2*M
INK=colors.HexColor('#172433')
MUTED=colors.HexColor('#5C6B7A')
BLUE=colors.HexColor('#1677E8')
PALE=colors.HexColor('#EFF6FF')
LINE=colors.HexColor('#E1E7EF')
TEAL=colors.HexColor('#167A72')
RELEASE=f'https://github.com/whdichrn/DockCounts/releases/tag/v{VERSION}'
c=canvas.Canvas(str(OUTPUT),pagesize=A4,pageCompression=1)
c.setTitle(f'DockCounts {VERSION} 实机图解与简明手册')
c.setAuthor('DockCounts')
c.setSubject('真实安装版截图、窗口计数、窗口选择与安装说明')

def text(s,x,y,size=11,font='Guide',color=INK):
    c.setFont(font,size); c.setFillColor(color); c.drawString(x,y,s)

def centered(s,x,y,size=11,font='Guide',color=INK):
    c.setFont(font,size); c.setFillColor(color); c.drawCentredString(x,y,s)

def para(s,x,top,width,size=11.2,leading=17,color=INK,font='Guide'):
    p=Paragraph(escape(s).replace('\n','<br/>'),ParagraphStyle('p',fontName=font,fontSize=size,leading=leading,textColor=color,wordWrap='CJK',spaceAfter=0))
    _,h=p.wrap(width,1000); p.drawOn(c,x,top-h)
    return top-h

def photo(name,x,bottom,width):
    im=ImageReader(str(ASSETS/name)); iw,ih=im.getSize(); height=width*ih/iw
    c.setFillColor(colors.white); c.setStrokeColor(LINE); c.setLineWidth(.6)
    c.roundRect(x-1,bottom-1,width+2,height+2,5,fill=1,stroke=1)
    c.drawImage(im,x,bottom,width=width,height=height,mask='auto')
    return height

def footer(page):
    c.setStrokeColor(LINE); c.setLineWidth(.7); c.line(M,61,W-M,61)
    text('实机截图  2026-11-21  |  截图机 macOS 27.2.1',M,43,8.5,color=MUTED)
    c.setFont('Guide',8.5); c.setFillColor(MUTED); c.drawRightString(W-M,43,f'{page} / 2')

def number(n,y):
    c.setFillColor(BLUE); c.circle(M+10,y+3,10,fill=1,stroke=0)
    centered(str(n),M+10,y-.2,10,'GuideBold',colors.white)

# Page 1: actual appearance and before/after state.
text('DockCounts',M,796,29,'GuideBold')
c.drawImage(ImageReader(str(ROOT/'Sources/DockCounts/Resources/AppIcon.png')),W-M-62,748,width=62,height=62,mask='auto')
text('实机图解 · 窗口计数与选择',M,769,16,'GuideBold',BLUE)
text(f'v{VERSION}  |  SwiftUI  |  macOS 15+  |  私有测试版',M,748,9.5,color=MUTED)
c.setFillColor(PALE); c.roundRect(M,675,CW,54,9,fill=1,stroke=0)
text('3 · 1',M+16,691,27,'GuideBold',BLUE)
text('窗口总数 · 已最小化数',M+130,707,12,'GuideBold')
text('总数包含已经最小化的窗口。',M+130,687,10.5,color=MUTED)
text('01  点击图标，只看这个应用的窗口',M,646,15,'GuideBold')
photo('02-window-menu.png',(W-480)/2,424,480)
text('图 1  窗口列表样式沿用 0.2；本轮已回归验证相同界面。',M,404,9,color=MUTED)
para('菜单中只有窗口名称与最小化状态。示例应用有三个窗口，Beta 标为“已最小化”；选择它即可恢复并切换。',M,384,CW,11.2,18)
text('02  角标会随状态更新',M,320,15,'GuideBold')
photo('01-badge-before.png',M+24,228,108)
photo('03-badge-after.png',W-M-132,228,108)
centered('3·1：恢复前',M+78,209,11,'GuideBold')
centered('3·0：恢复后',W-M-78,209,11,'GuideBold')
c.setStrokeColor(BLUE); c.setLineWidth(1.7); c.line(218,265,377,265)
p=c.beginPath(); p.moveTo(377,265); p.lineTo(368,270); p.lineTo(368,260); p.close()
c.setFillColor(BLUE); c.drawPath(p,fill=1,stroke=0)
centered('选择 Beta',W/2,286,10.5,'GuideBold',BLUE)
centered('恢复并切换窗口',W/2,244,10,color=MUTED)
c.setFillColor(colors.HexColor('#F5F8FB')); c.roundRect(M,116,CW,61,8,fill=1,stroke=0)
text('总窗口数仍为 3；已最小化数从 1 变为 0。',M+14,151,11.5,'GuideBold')
text('图片为真实画面裁切，未重绘界面；使用专用测试窗口保护业务内容。',M+14,131,9.2,color=MUTED)
footer(1)
c.showPage()

# Page 2: installation and day-to-day operation.
text('安装与日常使用',M,796,25,'GuideBold')
text('按以下三步即可使用',M,772,11,color=MUTED)
number(1,731); text('下载、解压并放到固定位置',M+30,731,12,'GuideBold')
para('从私有发布页下载通用版 ZIP，解压后将 DockCounts.app 放到 ~/Applications，双击启动。',M+30,716,CW-30,11.2,17)
text(f'打开 v{VERSION} 发布页',M+30,670,10.5,color=BLUE)
c.linkURL(RELEASE,(M+30,667,M+180,682),relative=0,thickness=0)
number(2,637); text('完成两项系统设置',M+30,637,12,'GuideBold')
para('系统设置 → 隐私与安全性 → 辅助功能：允许 DockCounts。\n系统设置 → 桌面与程序坞：开启“将窗口最小化至应用程序图标”。',M+30,622,CW-30,10.7,17)
text('当前这台电脑已完成上述设置。',M+30,577,9.5,color=TEAL)
number(3,547); text('点击 Dock 图标并选择窗口',M+30,547,12,'GuideBold')
para('选择带“已最小化”标记的 Beta 后，它会恢复并切换到前台。下面是恢复后的实机窗口。',M+30,531,CW-30,11.2,17)
photo('04-restored-window.png',(W-350)/2,281,350)
centered('图 2  Beta 已恢复，测试窗口内容可见。',W/2,263,9,color=MUTED)
text('常用操作',M,234,12,'GuideBold')
c.setFillColor(colors.HexColor('#F5F8FB')); c.roundRect(M,170,CW,53,7,fill=1,stroke=0)
text('↑ / ↓  选择窗口',M+13,204,10.8)
text('回车  恢复 / 切换',M+CW/2+8,204,10.8)
text('Esc  关闭菜单',M+13,183,10.8)
text('点击外部  关闭菜单',M+CW/2+8,183,10.8)
text('右键和带修饰键的点击保留系统原有行为。',M,152,9.5,color=MUTED)
photo('05-menubar-icon.png',M+2,108,30)
para('菜单栏的双窗口与 Dock 托盘图标：可暂停、打开设置或退出。',M+46,137,CW-46,10.5,16)
para('本地签名，未做 Developer ID 公证。macOS 26+ 使用系统玻璃；macOS 15 沿用兼容磨砂，减弱透明效果由系统控制。',M,95,CW,8.8,13,color=MUTED)
footer(2)
c.save()
print(OUTPUT)
