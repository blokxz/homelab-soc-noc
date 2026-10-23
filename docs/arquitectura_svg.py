# Genera el diagrama de arquitectura del README.
# Requisitos: pip install diagrams (solo se usan sus íconos).
# Uso: python arquitectura_svg.py ../img/arquitectura.svg  y exportar a PNG (abrir el SVG en el navegador y capturar, o con Inkscape).
import base64, math, os, sys
import diagrams
RES = os.path.join(os.path.dirname(os.path.dirname(diagrams.__file__)), "resources")
ICON = {
    "internet": "onprem/network/internet.png", "router": "generic/network/router.png",
    "opnsense": "onprem/network/opnsense.png", "windows": "generic/os/windows.png",
    "linux": "generic/os/linux-general.png", "zabbix": "onprem/monitoring/zabbix.png",
}
W, H = 1620, 1250
FONT = "Helvetica, Arial, sans-serif"
out = []
def add(s): out.append(s)

def img(key, cx, cy, size=92, opacity=1):
    data = base64.b64encode(open(os.path.join(RES, ICON[key]), "rb").read()).decode()
    add(f'<image href="data:image/png;base64,{data}" x="{cx-size/2}" y="{cy-size/2}" width="{size}" height="{size}" opacity="{opacity}"/>')

def text(x, y, s, size=14, weight=400, color="#2C2C2A", anchor="middle"):
    add(f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" fill="{color}" text-anchor="{anchor}">{s}</text>')

def node(key, cx, cy, lines, pending=False):
    img(key, cx, cy, opacity=0.45 if pending else 1)
    y = cy + 66
    for i, l in enumerate(lines):
        text(cx, y + i*18, l, size=14 if i == 0 else 13, weight=700 if i == 0 else 400,
             color="#888780" if pending else ("#2C2C2A" if i == 0 else "#5F5E5A"))

def cluster(x, y, w, h, title, subtitle, stroke, fill, dash=False):
    d = ' stroke-dasharray="7 5"' if dash else ""
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="16" fill="{fill}" stroke="{stroke}" stroke-width="1.6"{d}/>')
    text(x+20, y+28, title, size=15, weight=700, color=stroke, anchor="start")
    if subtitle:
        text(x+20, y+48, subtitle, size=13, color=stroke, anchor="start")

def path(pts, color, width=2.4, dash=None, arrow=False, r=14):
    d = f"M{pts[0][0]},{pts[0][1]}"
    for i in range(1, len(pts)-1):
        p0, p1, p2 = pts[i-1], pts[i], pts[i+1]
        rr = min(r, math.dist(p0, p1)/2, math.dist(p1, p2)/2)
        t = lambda a, b: (a[0]+(b[0]-a[0])*rr/math.dist(a, b), a[1]+(b[1]-a[1])*rr/math.dist(a, b))
        a, b = t(p1, p0), t(p1, p2)
        d += f" L{a[0]:.1f},{a[1]:.1f} Q{p1[0]},{p1[1]} {b[0]:.1f},{b[1]:.1f}"
    d += f" L{pts[-1][0]},{pts[-1][1]}"
    da = f' stroke-dasharray="{dash}"' if dash else ""
    mk = f' marker-end="url(#a{color[1:]})"' if arrow else ""
    add(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round"{da}{mk}/>')

def label(x, y, s, color, anchor="middle"):
    w = len(s) * 7.1 + 14
    x0 = x - w/2 if anchor == "middle" else x - 7
    add(f'<rect x="{x0:.0f}" y="{y-15}" width="{w:.0f}" height="21" rx="10" fill="#FFFFFF" opacity="0.92"/>')
    text(x, y, s, size=13, color=color, anchor=anchor)

NET, MON, PEND = "#3D3D3A", "#1D9E75", "#B4B2A9"
add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
add('<defs>' + "".join(
    f'<marker id="a{c[1:]}" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
    f'<path d="M1,1 L9,5 L1,9 Z" fill="{c}"/></marker>' for c in (MON,)) + '</defs>')
add(f'<rect width="{W}" height="{H}" fill="#FFFFFF"/>')
text(W/2, 52, "Homelab SOC/NOC · Arquitectura", size=26, weight=700)

# Contenedores
cluster(40, 400, 1070, 700, "PC principal · VMware Workstation", "Windows 11 · Ryzen 5 5600X · 16 GB", "#5F5E5A", "#F7F6F2")
cluster(70, 680, 640, 330, "Red CORP · 172.16.0.0/24", "gateway 172.16.0.1 · em1", "#534AB7", "#EEEDFE")
cluster(740, 680, 340, 330, "Red ATTACK", "172.16.66.0/24 · em2 · pendiente", "#D85A30", "#FDF4F0", dash=True)
cluster(1150, 400, 430, 700, "Netbook · Linux Mint", "192.168.1.39 · Docker Compose", "#0F6E56", "#E1F5EE")

# Líneas (debajo de los íconos)
path([(800, 172), (800, 226)], NET)                                         # Internet - router
path([(780, 330), (780, 430), (520, 430), (520, 446)], NET)                 # router - FW01
path([(820, 330), (820, 370), (1365, 370), (1365, 446)], NET)               # router - netbook
path([(520, 600), (520, 640), (300, 640), (300, 770)], NET)                 # FW01 - WS01
path([(520, 640), (520, 770)], NET)                                         # FW01 - DC01
path([(570, 545), (980, 545), (980, 770)], PEND, dash="2 7")                # FW01 - KALI
path([(1316, 495), (574, 495)], MON, width=2, dash="8 6", arrow=True)       # Zabbix -> FW01 (pasivo)
path([(300, 955), (300, 1050), (520, 1050)], MON, width=2, dash="8 6")      # WS01 -> bus
path([(520, 955), (520, 1050), (1250, 1050), (1250, 540), (1312, 540)], MON, width=2, dash="8 6", arrow=True)  # DC01 -> Zabbix

label(650, 435, "cable · bridged (WAN em0)", NET)
label(1090, 362, "Wi-Fi", NET)
label(960, 488, "agente pasivo · TCP 10050", MON)
label(905, 1043, "agentes activos · TCP 10051 · salen por el NAT de FW01", MON)

# Nodos
node("internet", 800, 96, [])
text(800, 158, "Internet", size=14, weight=700)
node("router", 800, 278, [], )
text(735, 272, "Router de casa", size=14, weight=700, anchor="end")
text(735, 292, "192.168.1.1 · LAN 192.168.1.0/24", size=13, color="#5F5E5A", anchor="end")
node("opnsense", 520, 495, ["FW01 · OPNsense", "WAN em0 · 192.168.1.59"])
node("windows", 300, 820, ["WS01", "Windows 11 Enterprise", "DHCP .100 – .200"])
node("windows", 520, 820, ["DC01", "Windows Server 2022", "172.16.0.10", "AD DS · DNS · DHCP"])
node("linux", 980, 820, ["KALI01", "Kali Linux · 172.16.66.10"], pending=True)
node("zabbix", 1365, 500, ["Zabbix 7.0 LTS", "consola NOC · :8080"])
node("linux", 1365, 820, ["Wazuh", "consola SOC · pendiente"], pending=True)

# Referencias
add('<rect x="40" y="1125" width="1540" height="90" rx="14" fill="#FFFFFF" stroke="#D3D1C7" stroke-width="1.2"/>')
text(64, 1155, "Referencias", size=14, weight=700, anchor="start")
items = [(NET, None, "Conexión de red"), (MON, "8 6", "Monitoreo Zabbix"), (PEND, "2 7", "Componente pendiente")]
x = 64
for c, d, s in items:
    da = f' stroke-dasharray="{d}"' if d else ""
    add(f'<line x1="{x}" y1="1188" x2="{x+54}" y2="1188" stroke="{c}" stroke-width="2.6" stroke-linecap="round"{da}/>')
    text(x+66, 1193, s, size=13, color="#444441", anchor="start")
    x += 300
text(1556, 1193, "Las redes CORP y ATTACK solo salen al exterior a través de FW01", size=13, color="#5F5E5A", anchor="end")
add('</svg>')
open(sys.argv[1] if len(sys.argv) > 1 else "arquitectura.svg", "w", encoding="utf-8").write("\n".join(out))
