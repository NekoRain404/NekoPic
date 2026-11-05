import QtQuick
import "."

/*!
    NekoIcon — 24×24 stroked vector icons drawn with Canvas.

    Ports the icon set used by the H5 prototype and the first native shell,
    then adds the small set the design system needs (close, check, chevrons,
    plus/minus, reset, eye). Icons are scaled from a 24-unit canvas, so any
    render size stays crisp and consistent.
*/
Canvas {
    id: root

    /*! Icon identifier, e.g. "adjust", "close", "chevronDown". */
    property string name: ""
    /*! Stroke colour; defaults to secondary text so icons recede quietly. */
    property color color: Theme.textSecondary
    /*! Stroke width in the 24-unit design space. */
    property real strokeWidth: 1.7
    /*! Optional accessible label. Icons are decorative by default. */
    property string accessibleName: ""

    implicitWidth: Theme.iconSize
    implicitHeight: Theme.iconSize
    antialiasing: true

    Accessible.role: Accessible.Graphic
    Accessible.name: accessibleName.length > 0 ? accessibleName : name
    Accessible.ignored: accessibleName.length === 0

    onNameChanged: requestPaint()
    onColorChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const c = getContext("2d")
        c.reset()
        c.scale(width / 24, height / 24)
        c.strokeStyle = root.color
        c.lineWidth = root.strokeWidth
        c.lineCap = "round"
        c.lineJoin = "round"
        c.beginPath()

        switch (root.name) {
        case "logo":
            c.moveTo(4, 18); c.lineTo(4, 5); c.lineTo(12, 12); c.lineTo(20, 5); c.lineTo(20, 18)
            c.moveTo(8, 18); c.lineTo(8, 14)
            c.moveTo(16, 18); c.lineTo(16, 14)
            break
        case "folder":
            c.moveTo(3, 7); c.lineTo(10, 7); c.lineTo(12, 9); c.lineTo(21, 9); c.lineTo(21, 19); c.lineTo(3, 19); c.closePath()
            break
        case "save":
            c.moveTo(4, 3); c.lineTo(17, 3); c.lineTo(21, 7); c.lineTo(21, 21); c.lineTo(3, 21); c.lineTo(3, 3)
            c.moveTo(7, 3); c.lineTo(7, 9); c.lineTo(17, 9); c.lineTo(17, 3)
            c.moveTo(7, 21); c.lineTo(7, 13); c.lineTo(17, 13); c.lineTo(17, 21)
            break
        case "undo":
        case "redo":
            if (root.name === "redo") { c.translate(24, 0); c.scale(-1, 1) }
            c.moveTo(8, 4); c.lineTo(3, 9); c.lineTo(8, 14)
            c.moveTo(3, 9); c.lineTo(14, 9); c.quadraticCurveTo(21, 9, 21, 16); c.lineTo(21, 20)
            break
        case "rotate":
            c.arc(12, 12, 9, -2.9, 2.4)
            c.moveTo(3, 3); c.lineTo(3, 10); c.lineTo(10, 10)
            break
        case "crop":
            c.moveTo(6, 2); c.lineTo(6, 16); c.lineTo(22, 16)
            c.moveTo(2, 6); c.lineTo(18, 6); c.lineTo(18, 22)
            break
        case "adjust":
            c.moveTo(3, 7); c.lineTo(21, 7)
            c.moveTo(3, 17); c.lineTo(21, 17)
            c.moveTo(12, 7); c.arc(9, 7, 3, 0, Math.PI * 2)
            c.moveTo(19, 17); c.arc(16, 17, 3, 0, Math.PI * 2)
            break
        case "filters":
            c.moveTo(12, 3); c.lineTo(14.5, 9.5); c.lineTo(21, 12); c.lineTo(14.5, 14.5)
            c.lineTo(12, 21); c.lineTo(9.5, 14.5); c.lineTo(3, 12); c.lineTo(9.5, 9.5); c.closePath()
            break
        case "brush":
            c.moveTo(11, 12); c.lineTo(19, 3); c.lineTo(21, 5); c.lineTo(13, 14)
            c.moveTo(11, 12); c.lineTo(13, 14)
            c.moveTo(10, 13); c.quadraticCurveTo(4, 12, 4, 17); c.lineTo(2, 21)
            c.quadraticCurveTo(10, 21, 10, 17)
            break
        case "text":
            c.moveTo(4, 6); c.lineTo(4, 3); c.lineTo(20, 3); c.lineTo(20, 6)
            c.moveTo(12, 3); c.lineTo(12, 21)
            c.moveTo(8, 21); c.lineTo(16, 21)
            break
        case "shapes":
            c.rect(3, 3, 12, 12)
            c.moveTo(22, 16); c.arc(16, 16, 6, 0, Math.PI * 2)
            break
        case "mosaic":
            c.rect(3, 3, 7, 7); c.rect(14, 3, 7, 7)
            c.rect(3, 14, 7, 7); c.rect(14, 14, 7, 7)
            break
        case "select":
            c.moveTo(5, 3); c.lineTo(20, 13); c.lineTo(13, 14); c.lineTo(10, 21); c.closePath()
            break
        case "pan":
            c.moveTo(8, 12); c.lineTo(8, 5); c.quadraticCurveTo(10, 2, 12, 5); c.lineTo(12, 11)
            c.lineTo(12, 4); c.quadraticCurveTo(14, 1, 16, 4); c.lineTo(16, 11)
            c.lineTo(16, 6); c.quadraticCurveTo(18, 3, 20, 6); c.lineTo(20, 15)
            c.quadraticCurveTo(20, 22, 13, 22); c.quadraticCurveTo(9, 22, 7, 18)
            c.lineTo(3, 12); c.quadraticCurveTo(4, 9, 6, 11); c.lineTo(8, 13)
            break
        case "close":
            c.moveTo(6, 6); c.lineTo(18, 18)
            c.moveTo(18, 6); c.lineTo(6, 18)
            break
        case "check":
            c.moveTo(5, 12.5); c.lineTo(10, 17.5); c.lineTo(19, 6.5)
            break
        case "chevronDown":
            c.moveTo(6, 9); c.lineTo(12, 15); c.lineTo(18, 9)
            break
        case "chevronUp":
            c.moveTo(6, 15); c.lineTo(12, 9); c.lineTo(18, 15)
            break
        case "chevronLeft":
            c.moveTo(15, 6); c.lineTo(9, 12); c.lineTo(15, 18)
            break
        case "chevronRight":
            c.moveTo(9, 6); c.lineTo(15, 12); c.lineTo(9, 18)
            break
        case "plus":
            c.moveTo(12, 5); c.lineTo(12, 19)
            c.moveTo(5, 12); c.lineTo(19, 12)
            break
        case "minus":
            c.moveTo(5, 12); c.lineTo(19, 12)
            break
        case "reset":
            c.arc(12, 12, 8, -Math.PI * 0.5, Math.PI)
            c.moveTo(4, 8); c.lineTo(4, 12); c.lineTo(8, 12)
            break
        case "eye":
            c.moveTo(2.5, 12)
            c.quadraticCurveTo(7, 5.5, 12, 5.5)
            c.quadraticCurveTo(17, 5.5, 21.5, 12)
            c.quadraticCurveTo(17, 18.5, 12, 18.5)
            c.quadraticCurveTo(7, 18.5, 2.5, 12)
            c.closePath()
            c.moveTo(15, 12); c.arc(12, 12, 3, 0, Math.PI * 2)
            break
        case "eyeOff":
            c.moveTo(2.5, 12)
            c.quadraticCurveTo(7, 5.5, 12, 5.5)
            c.quadraticCurveTo(17, 5.5, 21.5, 12)
            c.quadraticCurveTo(17, 18.5, 12, 18.5)
            c.quadraticCurveTo(7, 18.5, 2.5, 12)
            c.closePath()
            c.moveTo(15, 12); c.arc(12, 12, 3, 0, Math.PI * 2)
            c.moveTo(4, 4); c.lineTo(20, 20)
            break
        case "align-left":
            c.moveTo(4, 3); c.lineTo(4, 21)
            c.rect(7, 6, 13, 4); c.rect(7, 14, 8, 4)
            break
        case "align-hcenter":
            c.moveTo(12, 3); c.lineTo(12, 21)
            c.rect(5, 6, 14, 4); c.rect(8, 14, 8, 4)
            break
        case "align-right":
            c.moveTo(20, 3); c.lineTo(20, 21)
            c.rect(4, 6, 13, 4); c.rect(9, 14, 8, 4)
            break
        case "align-top":
            c.moveTo(3, 4); c.lineTo(21, 4)
            c.rect(6, 7, 4, 13); c.rect(14, 7, 4, 8)
            break
        case "align-vcenter":
            c.moveTo(3, 12); c.lineTo(21, 12)
            c.rect(6, 5, 4, 14); c.rect(14, 8, 4, 8)
            break
        case "align-bottom":
            c.moveTo(3, 20); c.lineTo(21, 20)
            c.rect(6, 4, 4, 13); c.rect(14, 9, 4, 8)
            break
        default:
            // Unknown names intentionally paint nothing rather than guessing.
            break
        }

        c.stroke()
    }
}
