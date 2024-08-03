import 'dart:async';
import 'dart:ui';
import 'frame_sdk.dart';

/// Enum for text alignment options.
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

/// Enum for alignment options.
enum Alignment {
  leading,
  center,
  trailing,
}

/// Enum for palette colors.
enum PaletteColors {
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

  const PaletteColors(this.paletteIndex, this.name);
  final int paletteIndex;
  final String name;

  /// Returns the PaletteColor corresponding to the given index.
  static PaletteColors fromIndex(int index) {
    return PaletteColors.values.firstWhere(
      (color) => color.paletteIndex == index,
      orElse: () =>
          throw ArgumentError('No PaletteColor found for index $index'),
    );
  }

  /// Operator overload to add an integer value to a PaletteColor.
  PaletteColors operator +(int value) => fromIndex(value);
}

/// Class for displaying text and graphics on the Frame display.
class Display {
  final Frame frame;
  int _lineHeight = 60;

  Display(this.frame);

  /// Gets the height of each line of text in pixels.
  int get lineHeight => _lineHeight;

  /// Sets the height of each line of text in pixels.
  set lineHeight(int value) {
    if (value < 1) {
      throw ArgumentError("lineHeight must be a positive integer");
    }
    _lineHeight = value;
  }

  static final Map<PaletteColors, Color> colorPaletteMapping = {
    PaletteColors.voidBlack: const Color.fromARGB(255, 0, 0, 0),
    PaletteColors.white: const Color.fromARGB(255, 255, 255, 255),
    PaletteColors.gray: const Color.fromARGB(255, 157, 157, 157),
    PaletteColors.red: const Color.fromARGB(255, 190, 38, 51),
    PaletteColors.pink: const Color.fromARGB(255, 224, 111, 139),
    PaletteColors.darkBrown: const Color.fromARGB(255, 73, 60, 43),
    PaletteColors.brown: const Color.fromARGB(255, 164, 100, 34),
    PaletteColors.orange: const Color.fromARGB(255, 235, 137, 49),
    PaletteColors.yellow: const Color.fromARGB(255, 247, 226, 107),
    PaletteColors.darkGreen: const Color.fromARGB(255, 47, 72, 78),
    PaletteColors.green: const Color.fromARGB(255, 68, 137, 26),
    PaletteColors.lightGreen: const Color.fromARGB(255, 163, 206, 39),
    PaletteColors.nightBlue: const Color.fromARGB(255, 27, 38, 50),
    PaletteColors.seaBlue: const Color.fromARGB(255, 0, 87, 132),
    PaletteColors.skyBlue: const Color.fromARGB(255, 49, 162, 242),
    PaletteColors.cloudBlue: const Color.fromARGB(255, 178, 220, 239),
  };

  static const Map<int, int> _charWidthMapping = {
    0x000041: 22,
    0x000055: 19,
    0x0000CD: 11,
    0x00005C: 15,
    0x000069: 5,
    0x0000C2: 23,
    0x0F0003: 70,
    0x0F000E: 77,
    0x0F000D: 70,
    0x0F0002: 70,
    0x000068: 18,
    0x00005B: 9,
    0x0000C3: 23,
    0x0000B7: 6,
    0x00004F: 20,
    0x000054: 20,
    0x0000CE: 16,
    0x000040: 31,
    0x000056: 21,
    0x000042: 18,
    0x0000A9: 28,
    0x0000C1: 23,
    0x00004D: 23,
    0x0000B5: 17,
    0x0F0000: 70,
    0x0F000F: 76,
    0x0F0001: 70,
    0x00004E: 19,
    0x0000C0: 22,
    0x00005A: 17,
    0x000043: 16,
    0x0000BB: 17,
    0x0000CF: 15,
    0x000057: 23,
    0x00005E: 20,
    0x0000C4: 23,
    0x0000B0: 15,
    0x00004A: 14,
    0x000053: 17,
    0x0000CB: 17,
    0x0000BF: 14,
    0x000047: 18,
    0x0F000C: 70,
    0x0F0005: 70,
    0x0F0004: 91,
    0x0F0010: 70,
    0x0F000B: 70,
    0x000046: 17,
    0x000052: 20,
    0x0000CC: 12,
    0x0000B1: 20,
    0x00005D: 10,
    0x0000C5: 23,
    0x000078: 20,
    0x00004B: 19,
    0x0000C7: 16,
    0x00005F: 25,
    0x000044: 19,
    0x0000CA: 17,
    0x000050: 18,
    0x0F0006: 70,
    0x000131: 5,
    0x0F0007: 70,
    0x0F000A: 70,
    0x000051: 22,
    0x000045: 17,
    0x0000C6: 32,
    0x00004C: 16,
    0x000079: 20,
    0x000022: 13,
    0x0000DC: 19,
    0x000036: 17,
    0x00002D: 17,
    0x0000D5: 20,
    0x0000E1: 19,
    0x000142: 10,
    0x0000E0: 19,
    0x00003A: 6,
    0x00002E: 6,
    0x0000D4: 20,
    0x0000EF: 15,
    0x000037: 15,
    0x000023: 19,
    0x0000DB: 19,
    0x000035: 15,
    0x0000ED: 11,
    0x000021: 5,
    0x00003C: 19,
    0x0000E2: 19,
    0x0000D6: 20,
    0x000141: 19,
    0x0000D7: 18,
    0x00003B: 8,
    0x0000E3: 19,
    0x0000DA: 19,
    0x000020: 13,
    0x000034: 18,
    0x0000EE: 16,
    0x0000E7: 14,
    0x00003F: 14,
    0x00002B: 19,
    0x0000D3: 20,
    0x0000EA: 17,
    0x000030: 18,
    0x000024: 17,
    0x0000DE: 18,
    0x000178: 22,
    0x000192: 16,
    0x000025: 34,
    0x0000DD: 22,
    0x000031: 16,
    0x00002C: 8,
    0x0000D2: 20,
    0x0000E6: 29,
    0x0000D0: 22,
    0x00002A: 21,
    0x00003E: 19,
    0x0000E4: 19,
    0x0000DF: 19,
    0x000027: 5,
    0x000033: 15,
    0x0000EB: 17,
    0x0000F8: 18,
    0x000153: 30,
    0x000152: 30,
    0x000032: 16,
    0x0000F9: 17,
    0x0000EC: 11,
    0x000026: 20,
    0x00003D: 19,
    0x0000E5: 19,
    0x0000D1: 19,
    0x0000E8: 17,
    0x0000FB: 16,
    0x0000F4: 18,
    0x0000F5: 17,
    0x0000FC: 17,
    0x0000E9: 16,
    0x0000FA: 17,
    0x000028: 10,
    0x0000F7: 19,
    0x000160: 17,
    0x000161: 15,
    0x0000F6: 18,
    0x000029: 11,
    0x000039: 17,
    0x0000F2: 18,
    0x0000FD: 20,
    0x0000FE: 18,
    0x000038: 18,
    0x0000F3: 18,
    0x0000F1: 16,
    0x0000D9: 19,
    0x00017D: 18,
    0x00017E: 17,
    0x0000D8: 20,
    0x0000FF: 20,
    0x0000F0: 18,
    0x000060: 11,
    0x000074: 14,
    0x0000AE: 29,
    0x00006F: 18,
    0x00007B: 12,
    0x000048: 19,
    0x0000A3: 18,
    0x000049: 12,
    0x00007C: 5,
    0x0000A2: 14,
    0x000075: 17,
    0x000061: 19,
    0x000077: 30,
    0x000063: 13,
    0x0000C8: 17,
    0x00007A: 16,
    0x00006E: 18,
    0x0020AC: 18,
    0x0F0009: 70,
    0x0F0008: 70,
    0x00006D: 28,
    0x0000A1: 6,
    0x000062: 18,
    0x0000C9: 16,
    0x000076: 19,
    0x00007D: 12,
    0x0000A5: 22,
    0x000072: 11,
    0x000066: 15,
    0x000067: 20,
    0x000073: 15,
    0x0000AB: 17,
    0x00006A: 11,
    0x00007E: 17,
    0x000059: 23,
    0x00006C: 8,
    0x000065: 16,
    0x000071: 18,
    0x000070: 18,
    0x000064: 18,
    0x00006B: 18,
    0x000058: 21
  };

  int charSpacing = 4;

  /// Shows text on the display.
  ///
  /// Args:
  ///   text (String): The text to display.
  ///   x (int): The left pixel position to start the text. Defaults to 1.
  ///   y (int): The top pixel position to start the text. Defaults to 1.
  ///   maxWidth (int?): The maximum width for the text bounding box. Defaults to 640.
  ///   maxHeight (int?): The maximum height for the text bounding box.
  ///   color (PaletteColors?): The color of the text.
  ///   align (Alignment2D): The alignment of the text. Defaults to Alignment2D.topLeft.
  Future<void> showText(String text,
      {int x = 1,
      int y = 1,
      int? maxWidth = 640,
      int? maxHeight,
      PaletteColors? color,
      Alignment2D align = Alignment2D.topLeft}) async {
    await _writeText(text, true,
        x: x,
        y: y,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        color: color,
        align: align);
  }

  /// Writes text to the display buffer.
  ///
  /// Args:
  ///   text (String): The text to write.
  ///   x (int): The left pixel position to start the text. Defaults to 1.
  ///   y (int): The top pixel position to start the text. Defaults to 1.
  ///   maxWidth (int?): The maximum width for the text bounding box. Defaults to 640.
  ///   maxHeight (int?): The maximum height for the text bounding box.
  ///   color (PaletteColors?): The color of the text.
  ///   align (Alignment2D): The alignment of the text. Defaults to Alignment2D.topLeft.
  Future<void> writeText(String text,
      {int x = 1,
      int y = 1,
      int? maxWidth = 640,
      int? maxHeight,
      PaletteColors? color,
      Alignment2D align = Alignment2D.topLeft}) async {
    await _writeText(text, false,
        x: x,
        y: y,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        color: color,
        align: align);
  }

  /// Internal method to write text to the display buffer.
  ///
  /// Args:
  ///   text (String): The text to write.
  ///   show (bool): Whether to show the text immediately.
  ///   x (int): The left pixel position to start the text. Defaults to 1.
  ///   y (int): The top pixel position to start the text. Defaults to 1.
  ///   maxWidth (int?): The maximum width for the text bounding box. Defaults to 640.
  ///   maxHeight (int?): The maximum height for the text bounding box.
  ///   color (PaletteColors?): The color of the text.
  ///   align (Alignment2D): The alignment of the text. Defaults to Alignment2D.topLeft.
  Future<void> _writeText(
    String text,
    bool show, {
    int x = 1,
    int y = 1,
    int? maxWidth = 640,
    int? maxHeight,
    PaletteColors? color,
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
    String luaToSend = '';
    for (final line in text.split("\n")) {
      int thisLineX = x;
      if (align.horizontal == Alignment.center) {
        thisLineX = x + (maxWidth ?? (640 - x)) ~/ 2 - getTextWidth(line) ~/ 2;
      } else if (align.horizontal == Alignment.trailing) {
        thisLineX = x + (maxWidth ?? (640 - x)) - getTextWidth(line);
      }
      luaToSend +=
          'frame.display.text("${frame.escapeLuaString(line)}",$thisLineX,${y + verticalOffset}';
      if (charSpacing != 4 || color != null) {
        luaToSend += ',{';
        if (charSpacing != 4) {
          luaToSend += 'spacing=$charSpacing';
        }
        if (charSpacing != 4 && color != null) {
          luaToSend += ',';
        }
        if (color != null) {
          luaToSend += 'color="${color.name}"';
        }
        luaToSend += '}';
      }
      luaToSend += ');';

      y += lineHeight;
      if (maxHeight != null && y > maxHeight || y + verticalOffset > 640) {
        break;
      }
    }
    if (show) {
      luaToSend += 'frame.display.show()';
    }
    await frame.runLua(
      luaToSend,
      checked: true,
    );
  }

  /// Scrolls text on the display.
  ///
  /// Args:
  ///   text (String): The text to scroll.
  ///   linesPerFrame (int): The number of lines to scroll per frame. Defaults to 5.
  ///   delay (double): The delay between frames in seconds. Defaults to 0.12.
  ///   textColor (PaletteColors?): The color of the text.
  Future<void> scrollText(String text,
      {int linesPerFrame = 5,
      double delay = 0.12,
      PaletteColors? textColor}) async {
    text = wrapText(text, 640);
    final totalHeight = getTextHeight(text);
    if (totalHeight < 400) {
      await writeText(text, x: 1, y:1, color: textColor);
      return;
    }
    String textColorName = textColor?.name ?? PaletteColors.white.name;
    await frame.runLua(
      'scrollText("${frame.escapeLuaString(text)}",$lineHeight,$totalHeight,$linesPerFrame,$delay,"$textColorName",$charSpacing)',
      checked: true,
      timeout: Duration(
        seconds: (totalHeight / linesPerFrame * (delay + 0.1) + 5).toInt(),
      ),
    );
  }

  /// Wraps text to fit within a given width.
  ///
  /// Args:
  ///   text (String): The text to wrap.
  ///   maxWidth (int): The maximum width for the text bounding box.
  ///
  /// Returns:
  ///   String: The wrapped text.
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

  /// Calculates the total height of the given text in pixels.
  ///
  /// Args:
  ///   text (String): The text to calculate the height for.
  ///
  /// Returns:
  ///   int: The total height of the text in pixels.
  int getTextHeight(String text) {
    final numLines = text.split("\n").length;
    return numLines * lineHeight;
  }

  /// Calculates the width of the given text in pixels.
  ///
  /// Args:
  ///   text (String): The text to calculate the width for.
  ///
  /// Returns:
  ///   int: The width of the text in pixels.
  int getTextWidth(String text) {
    var width = 0;
    for (final char in text.runes) {
      width += (_charWidthMapping[char] ?? 25) + charSpacing;
    }
    return width;
  }

  /// Shows the display buffer on the screen.
  Future<void> show() async {
    await frame.runLua("frame.display.show()", checked: true);
  }

  /// Clears the display buffer.
  Future<void> clear() async {
    await frame.runLua(
      'frame.display.text(" ",1,1);frame.display.show()',
      checked: false,
    );
  }

  /// Sets a custom color in the palette.
  ///
  /// Args:
  ///   paletteIndex (PaletteColors): The palette index to set the color for.
  ///   newColor (Color): The new color to set.
  Future<void> setPalette(PaletteColors paletteIndex, Color newColor) async {
    colorPaletteMapping[paletteIndex] = newColor;
    await frame.runLua(
        "frame.display.assign_color(${paletteIndex.name},${newColor.red},${newColor.green},${newColor.blue})",
        checked: true);
  }

  /// Generates Lua code to draw a rectangle.
  ///
  /// Args:
  ///   x (int): The left pixel position of the rectangle.
  ///   y (int): The top pixel position of the rectangle.
  ///   w (int): The width of the rectangle.
  ///   h (int): The height of the rectangle.
  ///   color (PaletteColors): The color of the rectangle.
  ///
  /// Returns:
  ///   String: The Lua code to draw the rectangle.
  String _drawRectLua(int x, int y, int w, int h, PaletteColors color) {
    w = (w ~/ 8) * 8;
    return 'frame.display.bitmap($x,$y,$w,2,${color.paletteIndex},string.rep("\\xFF",${(w ~/ 8) * h}))';
  }

  /// Draws a rectangle on the display.
  ///
  /// Args:
  ///   x (int): The left pixel position of the rectangle.
  ///   y (int): The top pixel position of the rectangle.
  ///   w (int): The width of the rectangle.
  ///   h (int): The height of the rectangle.
  ///   color (PaletteColors): The color of the rectangle.
  Future<void> drawRect(int x, int y, int w, int h, PaletteColors color) async {
    await frame.runLua(
      _drawRectLua(x, y, w, h, color),
      checked: true,
    );
  }

  /// Draws a filled rectangle with a border on the display.
  ///
  /// Args:
  ///   x (int): The left pixel position of the rectangle.
  ///   y (int): The top pixel position of the rectangle.
  ///   w (int): The width of the rectangle.
  ///   h (int): The height of the rectangle.
  ///   borderWidth (int): The width of the border.
  ///   borderColor (PaletteColors): The color of the border.
  ///   fillColor (PaletteColors): The fill color of the rectangle.
  Future<void> drawRectFilled(
    int x,
    int y,
    int w,
    int h,
    int borderWidth,
    PaletteColors borderColor,
    PaletteColors fillColor,
  ) async {
    String luaToSend = '';
    w = (w ~/ 8) * 8;
    if (borderWidth > 0) {
      borderWidth = (borderWidth ~/ 8) * 8;
      if (borderWidth == 0) {
        borderWidth = 8;
      }
    } else {
      await frame.runLua(_drawRectLua(x, y, w, h, fillColor), checked: true);
      return;
    }

    luaToSend += _drawRectLua(x, y, w, h, borderColor);
    luaToSend += _drawRectLua(
      x + borderWidth,
      y + borderWidth,
      w - borderWidth * 2,
      h - borderWidth * 2,
      fillColor,
    );
    await frame.runLua(luaToSend, checked: true);
  }
}
