#import "VCKeyDecoder.h"

#import "BridgeInternal.h"

#include <cctype>
#include <cstdlib>
#include <string_view>
#include <vector>

namespace {

// xterm modifier parameter: 1 + bitmask(shift=1, alt=2, ctrl=4); meta (8) counts as alt.
NSString *WithModifiers(NSString *base, unsigned parameter) {
  unsigned mask = parameter > 0 ? parameter - 1 : 0;
  NSMutableString *name = [NSMutableString string];
  if (mask & 4) [name appendString:@"Ctrl-"];
  if (mask & (2 | 8)) [name appendString:@"Alt-"];
  if (mask & 1) [name appendString:@"Shift-"];
  [name appendString:base];
  return name;
}

NSString *CodepointName(unsigned code) {
  switch (code) {
    case 9: return @"Tab";
    case 13: return @"Enter";
    case 27: return @"Esc";
    case 32: return @"Space";
    case 127: return @"Backspace";
    default: break;
  }
  if (code == 0 || code >= 0x110000 || (code >= 0xD800 && code <= 0xDFFF)) return nil;
  uint32_t le = code;
  return [[NSString alloc] initWithBytes:&le length:4 encoding:NSUTF32LittleEndianStringEncoding];
}

// Name for a codepoint with xterm modifiers, as sent by CSI-u / modifyOtherKeys.
NSString *CodepointWithModifiers(unsigned code, unsigned parameter) {
  NSString *base = CodepointName(code);
  if (!base) return nil;
  unsigned mask = parameter > 0 ? parameter - 1 : 0;
  // Shift alone on a letter is just the capital letter.
  if (mask == 1 && code < 128 && isalpha((int)code)) {
    return [NSString stringWithFormat:@"%c", toupper((int)code)];
  }
  // Ctrl/Alt names use the lowercase letter; Shift stays explicit.
  if (code < 128 && isupper((int)code) && (mask & ~1u)) {
    base = [NSString stringWithFormat:@"%c", tolower((int)code)];
    mask |= 1;
  }
  return WithModifiers(base, mask + 1);
}

// Name of a single C0 control byte or DEL, without Alt.
NSString *ControlName(unsigned char c) {
  switch (c) {
    case 0x00: return @"Ctrl-Space";
    case 0x08: return @"Backspace";  // Ctrl-H; FTXUI maps it to DEL anyway
    case 0x09: return @"Tab";
    case 0x0a:
    case 0x0d: return @"Enter";  // FTXUI maps CR to LF
    case 0x1b: return @"Esc";
    case 0x1c: return @"Ctrl-\\";
    case 0x1d: return @"Ctrl-]";
    case 0x1e: return @"Ctrl-^";
    case 0x1f: return @"Ctrl-_";
    case 0x7f: return @"Backspace";
    default: break;
  }
  if (c >= 0x01 && c <= 0x1a) return [NSString stringWithFormat:@"Ctrl-%c", 'a' + c - 1];
  return nil;
}

// Splits "1;5" into numbers. Returns false on anything that isn't digits and ';'.
bool Parameters(std::string_view text, std::vector<unsigned> &out) {
  out.clear();
  unsigned value = 0;
  bool any = false;
  for (char c : text) {
    if (c >= '0' && c <= '9') {
      value = value * 10 + unsigned(c - '0');
      any = true;
      if (value > 0x10FFFF) return false;
    } else if (c == ';') {
      out.push_back(any ? value : 1);
      value = 0;
      any = false;
    } else {
      return false;
    }
  }
  out.push_back(any ? value : 1);
  return true;
}

NSString *TildeKey(unsigned code) {
  switch (code) {
    case 1: return @"Home";
    case 2: return @"Insert";
    case 3: return @"Delete";
    case 4: return @"End";
    case 5: return @"PageUp";
    case 6: return @"PageDown";
    case 11: return @"F1";
    case 12: return @"F2";
    case 13: return @"F3";
    case 14: return @"F4";
    case 15: return @"F5";
    case 17: return @"F6";
    case 18: return @"F7";
    case 19: return @"F8";
    case 20: return @"F9";
    case 21: return @"F10";
    case 23: return @"F11";
    case 24: return @"F12";
    default: return nil;
  }
}

NSString *LetterKey(char final) {
  switch (final) {
    case 'A': return @"ArrowUp";
    case 'B': return @"ArrowDown";
    case 'C': return @"ArrowRight";
    case 'D': return @"ArrowLeft";
    case 'H': return @"Home";
    case 'F': return @"End";
    case 'P': return @"F1";
    case 'Q': return @"F2";
    case 'R': return @"F3";
    case 'S': return @"F4";
    default: return nil;
  }
}

// ESC [ … final
NSString *CSIName(std::string_view body) {
  if (body.empty()) return nil;
  char final = body.back();
  std::string_view params = body.substr(0, body.size() - 1);
  if (final == 'Z' && params.empty()) return @"Shift-Tab";
  std::vector<unsigned> p;
  if (!Parameters(params, p)) return nil;
  if (final == 'u') {  // CSI-u: code ; mods u
    return CodepointWithModifiers(p[0], p.size() > 1 ? p[1] : 1);
  }
  if (final == '~') {
    if (p[0] == 27 && p.size() == 3) {  // xterm modifyOtherKeys: 27 ; mods ; code ~
      return CodepointWithModifiers(p[2], p[1]);
    }
    NSString *base = TildeKey(p[0]);
    return base ? WithModifiers(base, p.size() > 1 ? p[1] : 1) : nil;
  }
  if (NSString *base = LetterKey(final)) {
    if (params.empty()) return base;
    return WithModifiers(base, p.size() > 1 ? p[1] : 1);
  }
  return nil;
}

NSString *Utf8Character(const std::string &in) {
  NSString *s = VCToNS(in);
  if (s.length == 0) return nil;
  // Exactly one composed character (e.g. "é", "日", "🎙️").
  NSRange first = [s rangeOfComposedCharacterSequenceAtIndex:0];
  if (first.length != s.length) return nil;
  return [s isEqualToString:@" "] ? @"Space" : s;
}

}  // namespace

NSString *VCKeyName(const std::string &in) {
  if (in.empty()) return @"?";
  if (in.size() == 1) {
    unsigned char c = in[0];
    if (NSString *name = ControlName(c)) return name;
    if (c == ' ') return @"Space";
    if (c >= 0x21 && c < 0x7f) return [NSString stringWithFormat:@"%c", c];
  }
  if (in[0] == 0x1b && in.size() >= 2) {
    if (in[1] == '[' && in.size() >= 3) {
      if (NSString *name = CSIName(std::string_view(in).substr(2))) return name;
    } else if (in[1] == 'O' && in.size() == 3) {  // SS3: application-mode arrows, F1–F4
      if (NSString *name = LetterKey(in[2])) return name;
    } else {
      // ESC + key = Alt-key.
      std::string rest = in.substr(1);
      NSString *base = nil;
      if (rest.size() == 1) {
        unsigned char c = rest[0];
        if (NSString *control = ControlName(c)) {
          base = control;
        } else if (c == ' ') {
          base = @"Space";
        } else if (c >= 0x21 && c < 0x7f) {
          base = [NSString stringWithFormat:@"%c", c];
        }
      } else {
        base = Utf8Character(rest);
      }
      if (base) {
        if ([base hasPrefix:@"Ctrl-"]) return [@"Ctrl-Alt-" stringByAppendingString:[base substringFromIndex:5]];
        return [@"Alt-" stringByAppendingString:base];
      }
    }
  }
  if ((unsigned char)in[0] >= 0x80) {
    if (NSString *character = Utf8Character(in)) return character;
  }
  return [@"?" stringByAppendingString:VCHexOf(in)];
}

@implementation VCKeyDecoder

+ (NSString *)keyNameForBytes:(NSData *)bytes {
  return VCKeyName(std::string(static_cast<const char *>(bytes.bytes), bytes.length));
}

+ (NSString *)keyNameForInput:(NSString *)input {
  return [self keyNameForBytes:[input dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]];
}

@end
