"""Rendered deck audit; screenshots/report/PDF go outside the repository by default.

Usage: python presentation/tools/qa_deck.py URL /tmp/deck-qa
Requires Playwright, Pillow, OpenCV and pypdf (QA only; deck stays static).
"""
import json
from pathlib import Path
import sys
import cv2
from PIL import Image
from pypdf import PdfReader
from playwright.sync_api import sync_playwright

URL = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:8769/'
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else '/tmp/deck-qa')
OUT.mkdir(parents=True, exist_ok=True)
AUDIT = r'''() => {
 const s=document.querySelector('.slide.active'), sr=s.getBoundingClientRect(), issues=[];
 const overlaps=(a,b)=>a.left<b.right-1&&a.right>b.left+1&&a.top<b.bottom-1&&a.bottom>b.top+1;
 const overlays=[...document.querySelectorAll('#chrome,#source-chip,#progress')];
 const walker=document.createTreeWalker(s,NodeFilter.SHOW_TEXT);
 while(walker.nextNode()){
  const n=walker.currentNode,e=n.parentElement;
  if(!n.textContent.trim()||e.closest('.speaker-notes,svg')||!e.getClientRects().length)continue;
  const range=document.createRange();range.selectNode(n);
  for(const r of range.getClientRects()){
   if(r.left<sr.left-1||r.right>sr.right+1||r.top<sr.top-1||r.bottom>sr.bottom+1)issues.push(['slide-text-bounds',n.textContent]);
   for(const o of overlays)if(overlaps(r,o.getBoundingClientRect()))issues.push(['overlay:'+o.id,n.textContent]);
  }
 }
 for(const e of s.querySelectorAll('*')){
  if(e instanceof HTMLElement&&!e.closest('.speaker-notes')&&e.clientWidth&&e.scrollWidth>e.clientWidth+2)issues.push(['element-overflow',e.className,e.scrollWidth-e.clientWidth]);
 }
 for(const g of s.querySelectorAll('g.node')){
  const r=g.querySelector('rect').getBBox();
  for(const t of g.querySelectorAll('text')){const b=t.getBBox();if(b.x<r.x||b.x+b.width>r.x+r.width+1||b.y+b.height>r.y+r.height+1)issues.push(['svg-node-bounds',t.textContent]);}
 }
 for(const svg of s.querySelectorAll('svg')){const b=svg.getBBox(),v=svg.viewBox.baseVal;if(b.x<v.x-1||b.y<v.y-1||b.x+b.width>v.x+v.width+1||b.y+b.height>v.y+v.height+1)issues.push(['svg-viewbox-bounds']);}
 for(const img of s.querySelectorAll('img'))if(!img.complete||!img.naturalWidth)issues.push(['broken-image',img.getAttribute('src')]);
 if(document.documentElement.scrollWidth>innerWidth||document.documentElement.scrollHeight>innerHeight||scrollX||scrollY)issues.push(['page-scroll']);
 return issues;
}'''
with sync_playwright() as p:
 browser=p.chromium.launch()
 page=browser.new_page(reduced_motion='reduce')
 errors=[]
 page.on('pageerror',lambda error:errors.append(str(error)))
 page.on('console',lambda msg:errors.append(msg.text) if msg.type=='error' else None)
 page.on('response',lambda response:errors.append(f'HTTP {response.status}: {response.url}') if response.status>=400 else None)
 page.goto(URL+'#title',wait_until='networkidle')
 slides=page.locator('.slide').evaluate_all('ss=>ss.map(s=>({id:s.id,appendix:s.classList.contains("appendix-slide")}))')
 rows=[]
 for width,height in [(1920,1080),(1366,768),(1280,720)]:
  page.set_viewport_size({'width':width,'height':height})
  for i,slide in enumerate(slides):
   sid=slide['id']
   page.evaluate('(id)=>location.hash=id',sid)
   page.wait_for_function('(id)=>document.querySelector(".slide.active").id===id',arg=sid)
   page.wait_for_timeout(35)
   idle=page.evaluate(AUDIT)
   page.locator('#chrome').hover()
   hover=page.evaluate(AUDIT)
   path=OUT/f'{width}-{i+1:02}-{sid}.png'
   page.screenshot(path=str(path))
   row={'viewport':[width,height],'slide':sid,'idle':idle,'hover':hover}
   if sid=='closing':
    qr=OUT/f'qr-{width}.png'
    page.locator('.qr-card img').screenshot(path=str(qr))
    row['qr_decoded']=cv2.QRCodeDetector().detectAndDecode(cv2.imread(str(qr)))[0]
    assert row['qr_decoded']=='https://github.com/yinon-mitin/Status-Page',row
   rows.append(row)
   page.keyboard.press('n')
   page.wait_for_timeout(35)
   notes=page.locator('#notes-panel').bounding_box()
   deck=page.locator('#deck').bounding_box()
   assert deck['x']+deck['width']<=notes['x']+1,(sid,'notes cover slide')
   page.keyboard.press('n')
  page.keyboard.press('?')
  page.screenshot(path=str(OUT/f'help-{width}.png'))
  page.keyboard.press('Escape')
  page.keyboard.press('n')
  page.screenshot(path=str(OUT/f'notes-{width}.png'))
  page.keyboard.press('Escape')
  thumbs=[]
  for file in sorted(OUT.glob(f'{width}-[0-9]*.png')):
   img=Image.open(file).convert('RGB');img.thumbnail((640,360));thumbs.append(img)
  for part in range(0,len(thumbs),6):
   sheet=Image.new('RGB',(1280,1080),'#030914')
   for n,img in enumerate(thumbs[part:part+6]):sheet.paste(img,((n%2)*640,(n//2)*360))
   sheet.save(OUT/f'contact-{width}-{part//6+1}.png')
 page.pdf(path=str(OUT/'deck.pdf'),prefer_css_page_size=True,print_background=True)
 pdf=PdfReader(OUT/'deck.pdf')
 report={'url':URL,'main':sum(not s['appendix'] for s in slides),'appendix':sum(s['appendix'] for s in slides),'slides':rows,'errors':errors,'pdf_pages':len(pdf.pages),'pdf_size':list(pdf.pages[0].mediabox)}
 (OUT/'report.json').write_text(json.dumps(report,indent=2))
 print(json.dumps({**{k:v for k,v in report.items() if k!='slides'},'issues':[r for r in rows if r['idle'] or r['hover']]},indent=2))
 assert len(pdf.pages)==len(slides),'Wrong PDF page count'
 assert not errors,'Browser errors'
 assert not any(r['idle'] or r['hover'] for r in rows),'Layout issues (see report)'
 browser.close()
