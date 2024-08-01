import 'dart:async';
import 'frame_sdk.dart';

enum Alignment2D {
  topLeft(Alignment.leading, Alignment.leading),
  topCenter(Alignment.leading, Alignment.center),
  topRight(Alignment.leading, Alignment.trailing),
  middleLeft(Alignment.center, Alignment.leading),
  middleCenter(Alignment.center, Alignment.center),
  middleRight(Alignment.center, Alignment.trailing),
  bottomLeft(Alignment.trailing, Alignment.leading),
  bottomCenter(Alignment.trailing, Alignment.center),
  bottomRight(Alignment.trailing, Alignment.trailing);

  const Alignment2D(this.vertical, this.horizontal);
  final Alignment vertical;
  final Alignment horizontal;
}

enum Alignment {
  leading,
  center,
  trailing,
}

enum Colors {
  voidBlack(0, "VOID"),
  white(1, "WHITE"),
  gray(2, "GRAY"),
  red(3, "RED"),
  pink(4, "PINK"),
  darkBrown(5, "DARKBROWN"),
  brown(6, "BROWN"),
  orange(7, "ORANGE"),
  yellow(8, "YELLOW"),
  darkGreen(9, "DARKGREEN"),
  green(10, "GREEN"),
  lightGreen(11, "LIGHTGREEN"),
  nightBlue(12, "NIGHTBLUE"),
  seaBlue(13, "SEABLUE"),
  skyBlue(14, "SKYBLUE"),
  cloudBlue(15, "CLOUDBLUE");

  const Colors(this.paletteIndex, this.name);
  final int paletteIndex;
  final String name;
}

class Display {
  final Frame frame;
  int _lineHeight = 60;

  Display(this.frame);

  int get lineHeight => _lineHeight;

  set lineHeight(int value) {
    if (value < 1) {
      throw ArgumentError("lineHeight must be a positive integer");
    }
    _lineHeight = value;
  }

  static const Map<int, int> _charWidthMapping = {
    0x000020: 13,
    0x000021: 5,
    0x000022: 13,
    0x000023: 19,
    0x000024: 17,
    0x000025: 34,
    0x000026: 20,
    0x000027: 5,
    0x000028: 10,
    0x000029: 11,
    0x00002A: 21,
    0x00002B: 19,
    0x00002C: 8,
    0x00002D: 17,
    0x00002E: 6,
    0x000030: 18,
    0x000031: 16,
    0x000032: 16,
    0x000033: 15,
    0x000034: 18,
    0x000035: 15,
    0x000036: 17,
    0x000037: 15,
    0x000038: 18,
    0x000039: 17,
    0x00003A: 6,
    0x00003B: 8,
    0x00003C: 19,
    0x00003D: 19,
    0x00003E: 19,
    0x00003F: 14,
    0x000040: 31,
    0x000041: 22,
    0x000042: 18,
    0x000043: 16,
    0x000044: 19,
    0x000045: 17,
    0x000046: 17,
    0x000047: 18,
    0x000048: 19,
    0x000049: 12,
    0x00004A: 14,
    0x00004B: 19,
    0x00004C: 16,
    0x00004D: 23,
    0x00004E: 19,
    0x00004F: 20,
    0x000050: 18,
    0x000051: 22,
    0x000052: 20,
    0x000053: 17,
    0x000054: 20,
    0x000055: 19,
    0x000056: 21,
    0x000057: 23,
    0x000058: 21,
    0x000059: 23,
    0x00005A: 17,
    0x00005B: 9,
    0x00005C: 15,
    0x00005D: 10,
    0x00005E: 20,
    0x00005F: 25,
    0x000060: 11,
    0x000061: 19,
    0x000062: 18,
    0x000063: 13,
    0x000064: 18,
    0x000065: 16,
    0x000066: 15,
    0x000067: 20,
    0x000068: 18,
    0x000069: 5,
    0x00006A: 11,
    0x00006B: 18,
    0x00006C: 8,
    0x00006D: 28,
    0x00006E: 18,
    0x00006F: 18,
    0x000070: 18,
    0x000071: 18,
    0x000072: 11,
    0x000073: 15,
    0x000074: 14,
    0x000075: 17,
    0x000076: 19,
    0x000077: 30,
    0x000078: 20,
    0x000079: 20,
    0x00007A: 16,
    0x00007B: 12,
    0x00007C: 5,
    0x00007D: 12,
    0x00007E: 17,
    0x0000A1: 6,
    0x0000A2: 14,
    0x0000A3: 18,
    0x0000A5: 22,
    0x0000A9: 28,
    0x0000AB: 17,
    0x0000AE: 29,
    0x0000B0: 15,
    0x0000B1: 20,
    0x0000B5: 17,
    0x0000B7: 6,
    0x0000BB: 17,
    0x0000BF: 14,
    0x0000C0: 22,
    0x0000C1: 23,
    0x0000C2: 23,
    0x0000C3: 23,
    0x0000C4: 23,
    0x0000C5: 23,
    0x0000C6: 32,
    0x0000C7: 16,
    0x0000C8: 17,
    0x0000C9: 16,
    0x0000CA: 17,
    0x0000CB: 17,
    0x0000CC: 12,
    0x0000CD: 11,
    0x0000CE: 16,
    0x0000CF: 15,
    0x0000D0: 22,
    0x0000D1: 19,
    0x0000D2: 20,
    0x0000D3: 20,
    0x0000D4: 20,
    0x0000D5: 20,
    0x0000D6: 20,
    0x0000D7: 18,
    0x0000D8: 20,
    0x0000D9: 19,
    0x0000DA: 19,
    0x0000DB: 19,
    0x0000DC: 19,
    0x0000DD: 22,
    0x0000DE: 18,
    0x0000DF: 19,
    0x0000E0: 19,
    0x0000E1: 19,
    0x0000E2: 19,
    0x0000E3: 19,
    0x0000E4: 19,
    0x0000E5: 19,
    0x0000E6: 29,
    0x0000E7: 14,
    0x0000E8: 17,
    0x0000E9: 16,
    0x0000EA: 17,
    0x0000EB: 17,
    0x0000EC: 11,
    0x0000ED: 11,
    0x0000EE: 16,
    0x0000EF: 15,
    0x0000F0: 18,
    0x0000F1: 16,
    0x0000F2: 18,
    0x0000F3: 18,
    0x0000F4: 18,
    0x0000F5: 17,
    0x0000F6: 18,
    0x0000F7: 19,
    0x0000F8: 18,
    0x0000F9: 17,
    0x0000FA: 17,
    0x0000FB: 16,
    0x0000FC: 17,
    0x0000FD: 20,
    0x0000FE: 18,
    0x0000FF: 20,
    0x000131: 5,
    0x000141: 19,
    0x000142: 10,
    0x000152: 30,
    0x000153: 30,
    0x000160: 17,
    0x000161: 15,
    0x000178: 22,
    0x00017D: 18,
    0x00017E: 17,
    0x000192: 16,
    0x0020AC: 18,
    0x0F0000: 70,
    0x0F0001: 70,
    0x0F0002: 70,
    0x0F0003: 70,
    0x0F0004: 91,
    0x0F0005: 70,
    0x0F0006: 70,
    0x0F0007: 70,
    0x0F0008: 70,
    0x0F0009: 70,
    0x0F000A: 70,
    0x0F000B: 70,
    0x0F000C: 70,
    0x0F000D: 70,
    0x0F000E: 77,
    0x0F000F: 76,
    0x0F0010: 70,
  };

  int charSpacing = 4;

  Future<void> showText(
    String text, {
    int x = 1,
    int y = 1,
    int? maxWidth = 640,
    int? maxHeight,
    Alignment2D align = Alignment2D.topLeft,
  }) async {
    await writeText(
      text,
      x: x,
      y: y,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      align: align,
    );
    await show();
  }

  Future<void> writeText(
    String text, {
    int x = 1,
    int y = 1,
    int? maxWidth = 640,
    int? maxHeight,
    Alignment2D align = Alignment2D.topLeft,
  }) async {
    if (maxWidth != null) {
      text = wrapText(text, maxWidth);
    }

    final totalHeightOfText = getTextHeight(text);
    int verticalOffset = 0;
    if (align.vertical == Alignment.center) {
      verticalOffset = (maxHeight ?? (400 - y)) ~/ 2 - totalHeightOfText ~/ 2;
    } else if (align.vertical == Alignment.trailing) {
      verticalOffset = (maxHeight ?? (400 - y)) - totalHeightOfText;
    }

    for (final line in text.split("\n")) {
      int thisLineX = x;
      if (align.horizontal == Alignment.center) {
        thisLineX = x + (maxWidth ?? (640 - x)) ~/ 2 - getTextWidth(line) ~/ 2;
      } else if (align.horizontal == Alignment.trailing) {
        thisLineX = x + (maxWidth ?? (640 - x)) - getTextWidth(line);
      }
      await frame.runLua(
        'frame.display.text("${frame.escapeLuaString(line)}",$thisLineX,${y + verticalOffset})',
        checked: true,
      );
      y += lineHeight;
      if (maxHeight != null && y > maxHeight || y + verticalOffset > 640) {
        break;
      }
    }
  }

  Future<void> scrollText(
    String text, {
    int linesPerFrame = 5,
    double delay = 0.12,
  }) async {
    text = wrapText(text, 640);
    final totalHeight = getTextHeight(text);
    if (totalHeight < 400) {
      await writeText(text);
      return;
    }
    await frame.runLua(
      'scrollText("${frame.escapeLuaString(text)}",$lineHeight,$totalHeight,$linesPerFrame,$delay)',
      checked: true,
      timeout: Duration(
        seconds: (totalHeight / linesPerFrame * (delay + 0.1) + 5).toInt(),
      ),
    );
  }

  String wrapText(String text, int maxWidth) {
    final lines = text.split("\n");
    var output = "";
    for (final line in lines) {
      if (getTextWidth(line) <= maxWidth) {
        output += "$line\n";
      } else {
        var thisLine = "";
        final words = line.split(" ");
        for (final word in words) {
          if (getTextWidth("$thisLine $word") > maxWidth) {
            output += "$thisLine\n";
            thisLine = word;
          } else if (thisLine.isEmpty) {
            thisLine = word;
          } else {
            thisLine += " $word";
          }
        }
        if (thisLine.isNotEmpty) {
          output += "$thisLine\n";
        }
      }
    }
    return output.trimRight();
  }

  int getTextHeight(String text) {
    final numLines = text.split("\n").length;
    return numLines * lineHeight;
  }

  int getTextWidth(String text) {
    var width = 0;
    for (final char in text.runes) {
      width += _charWidthMapping[char] ?? 25 + charSpacing;
    }
    return width;
  }

  Future<void> show() async {
    await frame.runLua("frame.display.show()", checked: true);
  }

  Future<void> clear() async {
    await frame.runLua('frame.display.bitmap(1,1,4,2,15,"\\xFF")');
    await show();
  }

  Future<void> setPalette(int index, int red, int green, int blue) async {
    if (index < 0 || index > 15) {
      throw ArgumentError("Index out of range, must be between 0 and 15");
    }
    throw UnimplementedError(
        "assign_color is not yet working in the Frame firmware");
  }

  Future<void> drawRect(int x, int y, int w, int h, {Colors color = Colors.white}) async {
    w = (w ~/ 8) * 8;
    await frame.runLua(
      'frame.display.bitmap($x,$y,$w,2,${color.paletteIndex},string.rep("\\xFF",${(w ~/ 8) * h}))',
    );
  }

  Future<void> drawRectFilled(
    int x,
    int y,
    int w,
    int h,
    int borderWidth,
    Colors borderColor,
    Colors fillColor,
  ) async {
    w = (w ~/ 8) * 8;
    if (borderWidth > 0) {
      borderWidth = (borderWidth ~/ 8) * 8;
      if (borderWidth == 0) {
        borderWidth = 8;
      }
    } else {
      await drawRect(x, y, w, h, color: fillColor);
      return;
    }

    await drawRect(x, y, w, h, color: borderColor);
    await drawRect(
      x + borderWidth,
      y + borderWidth,
      w - borderWidth * 2,
      h - borderWidth * 2,
      color: fillColor,
    );
  }
}
