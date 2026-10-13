import QtQuick
import qs.Common
import qs.Modules.Plugins

// Часы Umbrella Corporation. Геометрия — в условных единицах 380×380 (как в макете),
// масштабируется под размер виджета. Секундной стрелки нет, перерисовка раз в минуту.
DesktopPluginComponent {
    id: root

    readonly property real defaultWidth: 300
    readonly property real defaultHeight: 300
    readonly property bool forceSquare: true
    minWidth: 160
    minHeight: 160

    // Цвета (можно переопределить в config экземпляра: handColor, handCore, digitColor)
    readonly property color handColor: pluginData.handColor ?? "#ff2438"
    readonly property color handCore: pluginData.handCore ?? "#ffd2d6"
    readonly property color digitColor: pluginData.digitColor ?? "#19b5ff"

    // Язык даты: "auto" (русский при ru-локали, иначе английский), "ru" или "en" — config: dateLanguage
    readonly property string dateLanguage: pluginData.dateLanguage ?? "auto"
    readonly property bool useRussian: dateLanguage === "ru" || (dateLanguage === "auto" && Qt.locale().name.substring(0, 2) === "ru")
    readonly property var days: useRussian ? ["ВС", "ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ"] : ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    readonly property var months: useRussian ? ["ЯНВ", "ФЕВ", "МАР", "АПР", "МАЙ", "ИЮН", "ИЮЛ", "АВГ", "СЕН", "ОКТ", "НОЯ", "ДЕК"] : ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    property date now: new Date()

    readonly property real side: Math.min(width, height)
    readonly property real k: side / 380
    readonly property real ox: (width - side) / 2
    readonly property real oy: (height - side) / 2

    onKChanged: {
        staticLayer.requestPaint();
        logoFallback.requestPaint();
        plateLayer.requestPaint();
        dynLayer.requestPaint();
    }
    onNowChanged: dynLayer.requestPaint()
    onHandColorChanged: dynLayer.requestPaint()
    onDigitColorChanged: {
        plateLayer.requestPaint();
        dynLayer.requestPaint();
    }

    // Тик ровно на смене минуты
    Timer {
        id: minuteTimer
        running: true
        repeat: false
        interval: 1000
        onTriggered: {
            root.now = new Date();
            const n = root.now;
            interval = 60000 - (n.getSeconds() * 1000 + n.getMilliseconds()) + 30;
            restart();
        }
        Component.onCompleted: triggered()
    }

    readonly property real cc: 190

    // ---------- 7-сегментные цифры ----------
    readonly property var segMap: ({
            "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
            "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg"
        })

    function segPolys(x, y, w, h, t) {
        const sk = 0.10 * h;
        const m = y + h / 2;
        const g = 1.2;
        const hz = yy => {
            const l = x + t * 0.55, r = x + w - t * 0.55;
            return [[l, yy], [l + t / 2, yy - t / 2], [r - t / 2, yy - t / 2], [r, yy], [r - t / 2, yy + t / 2], [l + t / 2, yy + t / 2]];
        };
        const vt = (xx, y0, y1) => [[xx, y0], [xx + t / 2, y0 + t / 2], [xx + t / 2, y1 - t / 2], [xx, y1], [xx - t / 2, y1 - t / 2], [xx - t / 2, y0 + t / 2]];
        const raw = {
            a: hz(y + t / 2), g: hz(m), d: hz(y + h - t / 2),
            f: vt(x + t / 2, y + t / 2 + g, m - g), b: vt(x + w - t / 2, y + t / 2 + g, m - g),
            e: vt(x + t / 2, m + g, y + h - t / 2 - g), c: vt(x + w - t / 2, m + g, y + h - t / 2 - g)
        };
        const out = {};
        for (const key in raw)
            out[key] = raw[key].map(p => [p[0] + sk * (1 - (p[1] - y) / h), p[1]]);
        return out;
    }

    function polyPath(ctx, pts) {
        ctx.beginPath();
        ctx.moveTo(pts[0][0], pts[0][1]);
        for (let i = 1; i < pts.length; i++)
            ctx.lineTo(pts[i][0], pts[i][1]);
        ctx.closePath();
    }

    // Геометрия пары цифр (h — высота цифр)
    function pairGeom(cx, h) {
        const w = h * 0.52, t = h * 0.13, gap = h * 0.16, total = 2 * w + gap;
        return {
            w: w, t: t, gap: gap, total: total,
            x: cx - total / 2,
            y: cc - h / 2,
            h: h
        };
    }

    function drawPairOff(ctx, cx, h) {
        const p = pairGeom(cx, h);
        ctx.fillStyle = Qt.rgba(2 / 255, 10 / 255, 16 / 255, 0.72);
        ctx.strokeStyle = Qt.rgba(25 / 255, 181 / 255, 255 / 255, 0.30);
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.roundedRect(p.x - 10, p.y - 10, p.total + 20, p.h + 20, 10, 10);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = Qt.rgba(25 / 255, 181 / 255, 255 / 255, 0.07);
        for (let d = 0; d < 2; d++) {
            const polys = segPolys(p.x + d * (p.w + p.gap), p.y, p.w, p.h, p.t);
            for (const key in polys) {
                polyPath(ctx, polys[key]);
                ctx.fill();
            }
        }
    }

    function drawPairOn(ctx, cx, h, value) {
        const p = pairGeom(cx, h);
        const digits = [Math.floor(value / 10), value % 10];
        for (let d = 0; d < 2; d++) {
            const s = segMap[String(digits[d])];
            const polys = segPolys(p.x + d * (p.w + p.gap), p.y, p.w, p.h, p.t);
            for (const key in polys) {
                if (s.indexOf(key) < 0)
                    continue;
                polyPath(ctx, polys[key]);
                ctx.fill();
            }
        }
    }

    // ---------- запасной логотип (если нет umbrella-logo.png) ----------
    function drawUmbrella(ctx, r) {
        const rad = deg => (deg - 90) * Math.PI / 180;
        const gap = 1.3;
        for (let i = 0; i < 8; i++) {
            const isRed = i % 2 === 0;
            const mid = i * 45;
            const a0 = mid - 22.5 + gap * 100 / r * 0.55;
            const a1 = mid + 22.5 - gap * 100 / r * 0.55;
            const R = isRed ? r : r * 0.97;
            const pt = (rr, deg) => [cc + rr * Math.cos(rad(deg)), cc + rr * Math.sin(rad(deg))];
            const p0 = pt(R, a0), p1 = pt(R, a1), pc = pt(R * 0.80, mid);
            const s0 = pt(r * 0.035, a0), s1 = pt(r * 0.035, a1);
            const xs = [s0[0], p0[0], pc[0], p1[0], s1[0]], ys = [s0[1], p0[1], pc[1], p1[1], s1[1]];
            const minX = Math.min.apply(null, xs), maxX = Math.max.apply(null, xs);
            const minY = Math.min.apply(null, ys), maxY = Math.max.apply(null, ys);
            let grad;
            if (isRed) {
                grad = ctx.createLinearGradient(0, minY, 0, maxY);
                grad.addColorStop(0, "#e0141c");
                grad.addColorStop(0.6, "#c10f18");
                grad.addColorStop(1, "#9e0b13");
            } else {
                grad = ctx.createLinearGradient(minX, minY, maxX, maxY);
                grad.addColorStop(0, "#d6d6da");
                grad.addColorStop(0.5, "#a9a9ae");
                grad.addColorStop(1, "#8f8f95");
            }
            ctx.fillStyle = grad;
            ctx.beginPath();
            ctx.moveTo(s0[0], s0[1]);
            ctx.lineTo(p0[0], p0[1]);
            ctx.quadraticCurveTo(pc[0], pc[1], p1[0], p1[1]);
            ctx.lineTo(s1[0], s1[1]);
            ctx.closePath();
            ctx.fill();
        }
    }

    // ---------- циферблат (статика, перерисовка только при ресайзе) ----------
    Canvas {
        id: staticLayer
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            ctx.translate(root.ox, root.oy);
            ctx.scale(root.k, root.k);
            const C = root.cc;

            // безель
            let g = ctx.createLinearGradient(C - 186, C - 186, C + 186, C + 186);
            g.addColorStop(0, "#e6e6ec");
            g.addColorStop(0.35, "#5a5a60");
            g.addColorStop(0.6, "#9a9aa2");
            g.addColorStop(1, "#2a2a2e");
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(C, C, 186, 0, Math.PI * 2);
            ctx.fill();

            // тёмный циферблат
            const fy = C - 178 + 0.42 * 356;
            g = ctx.createRadialGradient(C, fy, 0, C, fy, 0.62 * 356);
            g.addColorStop(0, "#1e1e22");
            g.addColorStop(0.7, "#0c0c0e");
            g.addColorStop(1, "#040405");
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(C, C, 178, 0, Math.PI * 2);
            ctx.fill();
            ctx.strokeStyle = Qt.rgba(184 / 255, 16 / 255, 26 / 255, 0.55);
            ctx.lineWidth = 1.2;
            ctx.stroke();

            // деления
            ctx.lineCap = "round";
            for (let i = 0; i < 60; i++) {
                const hour = i % 5 === 0;
                const a = (i * 6 - 90) * Math.PI / 180;
                const r1 = hour ? 152 : 164;
                ctx.strokeStyle = hour ? "#d8191f" : Qt.rgba(185 / 255, 185 / 255, 194 / 255, 0.45);
                ctx.lineWidth = hour ? (i % 15 === 0 ? 5 : 3.2) : 1.3;
                ctx.beginPath();
                ctx.moveTo(C + r1 * Math.cos(a), C + r1 * Math.sin(a));
                ctx.lineTo(C + 172 * Math.cos(a), C + 172 * Math.sin(a));
                ctx.stroke();
            }

            ctx.restore();
        }
    }

    // Логотип: свой файл umbrella-logo.png (положите рядом с этим файлом), иначе — вектор
    Image {
        id: logoImage
        source: "umbrella-logo.png"
        smooth: true
        mipmap: true
        width: 237 * root.k
        height: width
        x: root.ox + (root.cc - 118.5) * root.k
        y: root.oy + (root.cc - 118.5) * root.k
    }
    Canvas {
        id: logoFallback
        anchors.fill: parent
        visible: logoImage.status !== Image.Ready
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            ctx.translate(root.ox, root.oy);
            ctx.scale(root.k, root.k);
            root.drawUmbrella(ctx, 112);
            ctx.restore();
        }
    }

    // Подложки под цифры и «погашенные» сегменты (поверх логотипа)
    Canvas {
        id: plateLayer
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            ctx.translate(root.ox, root.oy);
            ctx.scale(root.k, root.k);
            root.drawPairOff(ctx, 108, 58);
            root.drawPairOff(ctx, 272, 58);
            ctx.restore();
        }
    }

    // ---------- время: цифры и стрелки ----------
    Canvas {
        id: dynLayer
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            ctx.translate(root.ox, root.oy);
            ctx.scale(root.k, root.k);
            const C = root.cc;
            const hh = root.now.getHours(), mm = root.now.getMinutes();

            // цифры с неоновым свечением
            ctx.fillStyle = root.digitColor;
            ctx.shadowColor = root.digitColor;
            ctx.shadowBlur = 8 * root.k;
            root.drawPairOn(ctx, 108, 58, hh);
            root.drawPairOn(ctx, 272, 58, mm);
            ctx.shadowBlur = 0;

            // стрелки
            function hand(len, width, tail, deg) {
                ctx.save();
                ctx.translate(C, C);
                ctx.rotate(deg * Math.PI / 180);
                ctx.beginPath();
                ctx.moveTo(-width / 2, tail);
                ctx.lineTo(-width * 0.32, -len + width);
                ctx.lineTo(0, -len);
                ctx.lineTo(width * 0.32, -len + width);
                ctx.lineTo(width / 2, tail);
                ctx.closePath();
                ctx.lineJoin = "round";
                ctx.strokeStyle = Qt.rgba(5 / 255, 5 / 255, 6 / 255, 0.75);
                ctx.lineWidth = 3.2;
                ctx.stroke();
                ctx.shadowColor = root.handColor;
                ctx.shadowBlur = 9 * root.k;
                ctx.fillStyle = root.handColor;
                ctx.fill();
                ctx.fill();
                ctx.shadowBlur = 0;
                ctx.strokeStyle = root.handCore;
                ctx.lineWidth = Math.max(1, width * 0.22);
                ctx.lineCap = "round";
                ctx.globalAlpha = 0.9;
                ctx.beginPath();
                ctx.moveTo(0, tail * 0.4);
                ctx.lineTo(0, -len + width * 1.2);
                ctx.stroke();
                ctx.restore();
            }
            hand(78, 11, 14, ((hh % 12) + mm / 60) * 30);
            hand(124, 8, 16, mm * 6);

            // колпачок
            ctx.fillStyle = "#0b0b0d";
            ctx.strokeStyle = "#5a5a60";
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(C, C, 9, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            ctx.fillStyle = root.handColor;
            ctx.beginPath();
            ctx.arc(C, C, 3.5, 0, Math.PI * 2);
            ctx.fill();
            ctx.restore();
        }
    }

    // ---------- подписи ----------
    Text {
        id: dateText
        x: root.ox
        width: root.side
        y: root.oy + 58 * root.k - height / 2
        horizontalAlignment: Text.AlignHCenter
        text: root.days[root.now.getDay()] + " · " + root.now.getDate() + " " + root.months[root.now.getMonth()]
        color: "#d9d9de"
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(8, 20 * root.k)
        font.weight: Font.DemiBold
        font.letterSpacing: 2 * root.k
    }
    Text {
        x: root.ox
        width: root.side
        y: root.oy + 310 * root.k - height / 2
        horizontalAlignment: Text.AlignHCenter
        text: "UMBRELLA"
        color: "#b9b9c2"
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(6, 17 * root.k)
        font.weight: Font.ExtraBold
        font.letterSpacing: 4 * root.k
    }
    Text {
        x: root.ox
        width: root.side
        y: root.oy + 325 * root.k - height / 2
        horizontalAlignment: Text.AlignHCenter
        text: "CORPORATION"
        color: "#8c8c92"
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(4, 9 * root.k)
        font.weight: Font.DemiBold
        font.letterSpacing: 4.5 * root.k
    }
}
