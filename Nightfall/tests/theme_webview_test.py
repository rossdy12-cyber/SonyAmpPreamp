"""Exercise the exact injected WebView script in Chrome; not a WKWebView device test."""
from pathlib import Path
import json
import subprocess
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]

def script(enabled, sites=None):
    args = json.dumps([enabled, sites or []])
    return subprocess.check_output(['bun', '-e', f"import {{gothicScript}} from './packages/mobile/lib/browser'; console.log(gothicScript(...{args}));"], cwd=ROOT, text=True)

FIXTURE = """<!doctype html><html><head><style>
html,body{background:#fff;color:#202124;font:16px Arial;margin:0}
main{background:white;padding:20px}.nested{color:#202124}.query{display:flex;width:300px;height:44px;border:1px solid #ddd;border-radius:24px}
input{color:#202124;background:transparent;border:0;width:240px;font:16px Arial}
button{color:#202124;background:#f8f9fa;border:1px solid #dadce0}a{color:#1a0dab}
.dark{background:#111;color:#eee}.dynamic{color:#121212;background:#fff}
</style></head><body><main><h1>Search</h1><span class='nested'>Nested explicit dark text</span>
<div class='query'><input value='Nightfall search'></div><button>Search</button><a href='/'>Result</a>
<div class='dark'>Already dark block</div><img width='20' height='20' alt='image'></main></body></html>"""

def snapshot(page):
    return page.evaluate("""() => Object.fromEntries(['body','.nested','input','.query','h1','.dark','img'].map(sel=>{const el=document.querySelector(sel),s=getComputedStyle(el),r=el.getBoundingClientRect();return [sel,{color:s.color,bg:s.backgroundColor,font:s.fontFamily,width:r.width,height:r.height,filter:s.filter}]}))""")

def luminance(rgb):
    import re
    vals = [int(n)/255 for n in re.findall(r'\d+', rgb)[:3]]
    vals = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in vals]
    return sum(v*w for v,w in zip(vals,[.2126,.7152,.0722]))

def contrast(a,b):
    light,dark=sorted([luminance(a),luminance(b)],reverse=True)
    return (light+.05)/(dark+.05)

def run():
    on,off,excepted=script(True),script(False),script(True,['www.google.com'])
    with sync_playwright() as pw:
        browser=pw.chromium.launch(executable_path='/usr/bin/google-chrome',args=['--no-sandbox'])
        page=browser.new_page(viewport={'width':390,'height':844})
        page.route('**/*',lambda route:route.fulfill(status=200,content_type='text/html',body=FIXTURE))
        page.goto('https://www.google.com/')
        before=snapshot(page)
        page.evaluate("window.DarkReader={siteOwned:true}")
        page.evaluate(on)
        page.wait_for_function("document.querySelector('.darkreader--sync') && getComputedStyle(document.querySelector('.nested')).color !== 'rgb(32, 33, 36)'")
        after=snapshot(page)
        assert contrast(after['.nested']['color'],after['body']['bg']) >= 4.5,after
        assert contrast(after['input']['color'],after['body']['bg']) >= 4.5,after
        assert contrast(after['.dark']['color'],after['.dark']['bg']) >= 4.5,after
        for sel in ['input','.query','h1','img']:
            for key in ['width','height','font','filter']:
                assert before[sel][key]==after[sel][key],(sel,key,before,after)
        assert page.evaluate('window.DarkReader.siteOwned')
        page.evaluate('window.savedEngine=window.__nightfallThemeEngine')
        page.evaluate(on)
        assert page.evaluate('window.savedEngine===window.__nightfallThemeEngine')
        page.evaluate("const node=document.createElement('p');node.className='dynamic';node.textContent='New explicit dark text';document.querySelector('main').appendChild(node)")
        page.wait_for_function("getComputedStyle(document.querySelector('.dynamic')).color !== 'rgb(18, 18, 18)'")
        dynamic=page.evaluate("() => {let s=getComputedStyle(document.querySelector('.dynamic'));return {color:s.color,bg:s.backgroundColor}}")
        assert contrast(dynamic['color'],dynamic['bg'])>=4.5,dynamic
        page.evaluate("document.querySelector('.dynamic').remove()")
        page.evaluate(off)
        page.wait_for_function("!document.querySelector('style.darkreader')")
        assert snapshot(page)==before,(snapshot(page),before)
        page.evaluate(on)
        page.evaluate(excepted)
        assert snapshot(page)==before
        assert not page.evaluate('window.__nightfallThemeEngine.isEnabled()')
        page.goto('https://www.google.com/search?q=test')
        page.evaluate(excepted)
        assert not page.evaluate('!!window.__nightfallThemeEngine')
        assert snapshot(page)==before
        page.goto('https://example.com/')
        page.evaluate(excepted)
        page.wait_for_function("window.__nightfallThemeEngine && window.__nightfallThemeEngine.isEnabled()")
        page.evaluate(off)
        assert snapshot(page)==before
        browser.close()
    print('PASS: nested/input/dynamic/dark-block contrast; unchanged layout/fonts/images; engine reuse; original-style restoration; hostname exceptions across navigation; site API preserved.')

if __name__ == '__main__':
    run()