//
//  SyntaxHighlighting.swift
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 31/08/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//
//  Syntax highlighting support.

import Foundation
import GHCKit


/// Token types distinguished during syntax highlighting.
///
public enum HighlightingTokenKind {
  case Keyword, Keysymbol, VariableWord, VariableSymbol, ConstructorWord, ConstructorSymbol,
       StringLit, CharacterLit, NumberLit, LineComment, BlockComment, Pragma, Other
}

extension HighlightingTokenKind: Printable {
  public var description: String {
    get {
      switch self {
      case .Keyword:           return "Keyword"
      case .Keysymbol:         return "Reserved symbol"
      case .VariableWord:      return "Alphanumeric variable or function"
      case .VariableSymbol:    return "Function operator symbol"
      case .ConstructorWord:   return "Alphanumeric constructor or module name"
      case .ConstructorSymbol: return "Data or type constructor symbol"
      case .StringLit:         return "String constant"
      case .CharacterLit:      return "Character constant"
      case .NumberLit:         return "Numeric constant"
      case .LineComment:       return "Single line or block comment"
      case .BlockComment:      return "Single line or block comment"
      case .Pragma:            return "Compiler pragma"
      case .Other:             return "Default foreground color"
      }
    }
  }
}

/// Map of kinds of highlighting tokens to the foreground colour for tokens of that kind.
///
/// FIXME: Needs to include information concerning underlining, too.
public typealias ThemeDictionary = [HighlightingTokenKind: [NSString: NSColor]]

/// Special highlighting for tab characters.
///
let tabHighlightingAttributes
  = [ NSBackgroundColorAttributeName: NSColor(calibratedRed: 255/255, green: 150/255, blue:  0/255, alpha: 0.5)
    , NSToolTipAttributeName        : "Tab characters should be avoided in Haskell code"]

/// Convert a theme to a dictionary to lookup text attributes by token type.
///
func themeToThemeDictionary(theme: Theme) -> ThemeDictionary {
  return [ .Keyword:           [NSForegroundColorAttributeName: theme.keyword.foreground]
         , .Keysymbol:         [NSForegroundColorAttributeName: theme.keysymbol.foreground]
         , .VariableWord:      [NSForegroundColorAttributeName: theme.varword.foreground]
         , .VariableSymbol:    [NSForegroundColorAttributeName: theme.varsymbol.foreground]
         , .ConstructorWord:   [NSForegroundColorAttributeName: theme.conword.foreground]
         , .ConstructorSymbol: [NSForegroundColorAttributeName: theme.consymbol.foreground]
         , .StringLit:         [NSForegroundColorAttributeName: theme.string.foreground]
         , .CharacterLit:      [NSForegroundColorAttributeName: theme.char.foreground]
         , .NumberLit:         [NSForegroundColorAttributeName: theme.number.foreground]
         , .LineComment:       [NSForegroundColorAttributeName: theme.comment.foreground]
         , .BlockComment:      [NSForegroundColorAttributeName: theme.comment.foreground]
         , .Pragma:            [NSForegroundColorAttributeName: theme.pragma.foreground]
         , .Other:             [NSForegroundColorAttributeName: theme.foreground]
         ]
}

extension Theme {

  /// Update the theme component that corresponds to the given token kind.
  ///
  mutating func setTokenKind(tokenKind: HighlightingTokenKind, colour: NSColor) {
    switch tokenKind {
    case .Keyword:            self.keyword.foreground   = colour
    case .Keysymbol:          self.keysymbol.foreground = colour
    case .VariableWord:       self.varword.foreground   = colour
    case .VariableSymbol:     self.varsymbol.foreground = colour
    case .ConstructorWord:    self.conword.foreground   = colour
    case .ConstructorSymbol:  self.consymbol.foreground = colour
    case .StringLit:          self.string.foreground    = colour
    case .CharacterLit:       self.char.foreground      = colour
    case .NumberLit:          self.number.foreground    = colour
    case .LineComment:        self.comment.foreground   = colour
    case .BlockComment:       self.comment.foreground   = colour
    case .Pragma:             self.pragma.foreground    = colour
    case .Other:              self.foreground           = colour
    }
  }
}


/// Tokens for syntax highlighting.
///
public struct HighlightingToken {
  public let kind: HighlightingTokenKind
  public let span: SrcSpan

  public init (ghcToken: Token) {
    switch ghcToken.kind {
    case .As:                 kind = .Keyword
    case .Case:               kind = .Keyword
    case .Class:              kind = .Keyword
    case .Data:               kind = .Keyword
    case .Default:            kind = .Keyword
    case .Deriving:           kind = .Keyword
    case .Do:                 kind = .Keyword
    case .Else:               kind = .Keyword
    case .Hiding:             kind = .Keyword
    case .If:                 kind = .Keyword
    case .Import:             kind = .Keyword
    case .In:                 kind = .Keyword
    case .Infix:              kind = .Keyword
    case .Infixl:             kind = .Keyword
    case .Infixr:             kind = .Keyword
    case .Instance:           kind = .Keyword
    case .Let:                kind = .Keyword
    case .Module:             kind = .Keyword
    case .Newtype:            kind = .Keyword
    case .Of:                 kind = .Keyword
    case .Qualified:          kind = .Keyword
    case .Then:               kind = .Keyword
    case .Type:               kind = .Keyword
    case .Where:              kind = .Keyword
    case .Forall:             kind = .Keyword
    case .Foreign:            kind = .Keyword
    case .Export:             kind = .Keyword
    case .Label:              kind = .Keyword
    case .Dynamic:            kind = .Keyword
    case .Safe:               kind = .Keyword
    case .Interruptible:      kind = .Keyword
    case .Unsafe:             kind = .Keyword
    case .Stdcallconv:        kind = .Keyword
    case .Ccallconv:          kind = .Keyword
    case .Capiconv:           kind = .Keyword
    case .Primcallconv:       kind = .Keyword
    case .Javascriptcallconv: kind = .Keyword
    case .Mdo:                kind = .Keyword
    case .Family:             kind = .Keyword
    case .Role:               kind = .Keyword
    case .Group:              kind = .Keyword
    case .By:                 kind = .Keyword
    case .Using:              kind = .Keyword
    case .Pattern:            kind = .Keyword
    case .Ctype:              kind = .Keyword

    case .Dotdot:             kind = .Keysymbol
    case .Colon:              kind = .Keysymbol
    case .Dcolon:             kind = .Keysymbol
    case .Equal:              kind = .Keysymbol
    case .Lam:                kind = .Keysymbol
    case .Lcase:              kind = .Keysymbol
    case .Vbar:               kind = .Keysymbol
    case .Larrow:             kind = .Keysymbol
    case .Rarrow:             kind = .Keysymbol
    case .At:                 kind = .Keysymbol
    case .Tilde:              kind = .Keysymbol
    case .Tildehsh:           kind = .Keysymbol
    case .Darrow:             kind = .Keysymbol
    case .Minus:              kind = .Keysymbol
    case .Bang:               kind = .Keysymbol
    case .Star:               kind = .Keysymbol
    case .Dot:                kind = .Keysymbol
    case .Biglam:             kind = .Keysymbol
    case .Ocurly:             kind = .Keysymbol
    case .Ccurly:             kind = .Keysymbol
    case .Vocurly:            kind = .Keysymbol
    case .Vccurly:            kind = .Keysymbol
    case .Obrack:             kind = .Keysymbol
    case .Opabrack:           kind = .Keysymbol
    case .Cpabrack:           kind = .Keysymbol
    case .Cbrack:             kind = .Keysymbol
    case .Oparen:             kind = .Keysymbol
    case .Cparen:             kind = .Keysymbol
    case .Oubxparen:          kind = .Keysymbol
    case .Cubxparen:          kind = .Keysymbol
    case .Semi:               kind = .Keysymbol
    case .Comma:              kind = .Keysymbol
    case .Underscore:         kind = .Keysymbol
    case .Backquote:          kind = .Keysymbol
    case .SimpleQuote:        kind = .Keysymbol

    case .Varsym:             kind = .VariableSymbol
    case .Consym:             kind = .ConstructorSymbol
    case .Varid:              kind = .VariableWord
    case .Conid:              kind = .ConstructorWord
    case .Qvarsym:            kind = .VariableSymbol
    case .Qconsym:            kind = .ConstructorSymbol
    case .Qvarid:             kind = .VariableWord
    case .Qconid:             kind = .ConstructorWord

    case .Integer:            kind = .NumberLit
    case .Rational:           kind = .NumberLit

    case .Char:               kind = .CharacterLit
    case .String:             kind = .StringLit
    case .LineComment:        kind = .LineComment
    case .BlockComment:       kind = .BlockComment
    case .Other:              kind = .Other
    }
    span = ghcToken.span
  }
}

extension HighlightingToken: Equatable {}

public func ==(lhs: HighlightingToken, rhs: HighlightingToken) -> Bool {
  return lhs.kind == rhs.kind && lhs.span == rhs.span
}

/// Map from line numbers to pairs of character index (where the line starts) and tokens on the line.
///
/// Tokens are in column order. If a token spans multiple lines, it occurs as the last token on its first line and as
/// the first (and possibly only) token on all of its subsqeuent lines.
///
public typealias LineTokenMap = StringLineMap<HighlightingToken>

/// Tokeniser functions take source language stings and turn them into tokens for highlighting.
///
// FIXME: need to have a starting location to tokenise partial programs
public typealias HighlightingTokeniser = (Line, Column, String) -> [HighlightingToken]

/// Initialise a line token map from a string.
///
public func lineTokenMap(string: String, tokeniser: HighlightingTokeniser) -> LineTokenMap {
  var lineMap: LineTokenMap = StringLineMap(string: string)
  lineMap.addLineInfo(tokensForLines(tokeniser(1, 1, string)))
  return lineMap
}

/// Compute the line assignment for an array of tokens.
///
private func tokensForLines(tokens: [HighlightingToken]) -> [(Line, HighlightingToken)] {

  // Compute the tokens for every line.
  var lineInfo: [(Line, HighlightingToken)] = []
  for token in tokens {
    for offset in 0..<token.span.lines {
      let lineToken: (Line, HighlightingToken) = (token.span.start.line + offset, token)
      lineInfo.append(lineToken)
    }
  }
  return lineInfo
}

/// For the given line range, determine how many preceeding or succeeding lines are part of multi-line tokens, and
/// hence, need to be rescanned for re-tokenisation.
///
private func lineRangeRescanOffsets(lineTokenMap: LineTokenMap, lines: Range<Line>) -> (UInt, UInt) {
  if lines.isEmpty { return (0, 0) }

    // Scan backwards for a line that is empty or whose first token starts on that line.
  var start: Line = lines.startIndex
  while start > 1 {
    if let line = lineTokenMap.infoOfLine(start).first?.span.start.line {
      if line == start { break }
    }
    else { break }
    start--
  }

    // Scan fowards for a line that is empty or whose last token ends on that line.
  var end: Line = lines.endIndex - 1
  while end < lineTokenMap.lastLine {
    if let srcSpan = lineTokenMap.infoOfLine(end).last?.span {
      if srcSpan.start.line + srcSpan.lines - 1 == end { break }
    }
    else { break }
    end++
  }

  return (lines.startIndex - start, end - (lines.endIndex - 1))
}

/// Check whether the edited characters contain or complete opening or closing brackets of nested comments.
///
private func commentBrackets(string: String, editedRange: Range<Int>) -> (Bool, Bool) {

  var openingBrackets: Bool    = false
  var closingBrackets: Bool    = false

  var range: Range<String.Index>
  if let start = string.intToStringIndex(editedRange.startIndex), end = string.intToStringIndex(editedRange.endIndex) {

      // In case of an empty range, this edit did a deletion => check its context.
    if (start ..< end).isEmpty {
      range = ((start > string.startIndex) ? advance(start, -1) : start) ..< ((end < string.endIndex) ? advance(end, 1) : end)

    } else { range = start ..< end }
  } else { return (false, false) }

  let commentBracketChars = NSCharacterSet(charactersInString: "{-}")
  while !range.isEmpty {
    if let charRange = string.rangeOfCharacterFromSet(commentBracketChars, options: NSStringCompareOptions(0), range: range) {

      var contIndex: String.Index = charRange.startIndex
      switch string.substringWithRange(charRange) {
      case "{":
        contIndex++
        if advance(charRange.startIndex, 1) < string.endIndex && string[advance(charRange.startIndex, 1)] == "-" {
          openingBrackets = true; contIndex++
        }

      case "-":
        // NB: Testing for preceding characters from "{-}" is important as the edited range may start in the middle of
        //     a comment bracket token.
        contIndex++
        if charRange.startIndex > string.startIndex && string[advance(charRange.startIndex, -1)] == "{" {
          openingBrackets = true
        } else if advance(charRange.startIndex, 1) < string.endIndex && string[advance(charRange.startIndex, 1)] == "}" {
          closingBrackets = true; contIndex++
        }

      case "}":
        contIndex++
        if charRange.startIndex > string.startIndex && string[advance(charRange.startIndex, -1)] == "-" {
          closingBrackets = true
        }
      default:
        contIndex++
      }
      range = min(contIndex, range.endIndex) ..< range.endIndex
    } else { break }
  }
  return (openingBrackets, closingBrackets)
}

/// Given an edited string and its old line map as well as the edit range and change in length, update the line map
/// by (1) fixing up all affected start indices and (2) retokenising all possibly affected tokens.
///
/// Also returns the range of lines that need to have their temporary attributes for syntax highlighting fixed.
///
public func tokenMapProcessEdit(lineMap: LineTokenMap,
                                string: String,
                                editedRange: Range<Int>,
                                changeInLength: Int,
                                tokeniser: HighlightingTokeniser) -> (LineTokenMap, Range<Line>)
{
  if count(editedRange) < changeInLength { return (lineMap, 1..<1) }   // Inconsistent arguments

    // Determine range of lines edited according to the old line map.
  let oldEditedRange = editedRange.startIndex ..< editedRange.endIndex - changeInLength
  let oldLineRange   = lineMap.lineRange(oldEditedRange)
  if oldLineRange.isEmpty || editedRange.startIndex < 0 || editedRange.endIndex > count(string.utf16) {
    return (lineMap, 1..<1)
  }

    // Newly added and/or modified text.
  let newString = (string as NSString).substringWithRange(toNSRange(editedRange))

    // (1) Skip the first line of the edited range — that line's start index cannot have changed.
  var idx:          Int   = 0
  var newIndices:   [Int] = []
  idx = NSMaxRange((newString as NSString).lineRangeForRange(NSRange(location: idx, length: 0)))

    // (2) Collect the starting indices of all subsequent lines in the edited range, including a possibly empty last line.
  // Swift 1.1:  while idx < newString.utf16Count {
  while idx < count(newString.utf16) {
    newIndices.append(editedRange.startIndex + idx)
    idx = NSMaxRange((newString as NSString).lineRangeForRange(NSRange(location: idx, length: 0)))
  }
  let newlines = NSCharacterSet.newlineCharacterSet()
  if !newString.isEmpty && newlines.characterIsMember(newString.utf16[newString.utf16.endIndex - 1]) {
    newIndices.append(editedRange.endIndex)
  }

  let changeInLines = newIndices.count + 1 - count(oldLineRange)   // NB: We skipped the first line of the edited range.
  let newLineRange  = oldLineRange.startIndex ..< (Line(Int(oldLineRange.endIndex) + changeInLines))

  var newLineMap: LineTokenMap = lineMap
  // Swift 1.1:  newLineMap.setStartOfLine(0, startIndex: string.utf16Count)   // special case of the end of the string
  newLineMap.setStartOfLine(0, startIndex: count(string.utf16))   // special case of the end of the string

    // Update all edited lines, except the first (whose start index cannot have changed).
  newLineMap.replaceLines(oldLineRange.startIndex + 1 ..< oldLineRange.endIndex, startIndices: newIndices)

    // Update all lines trailing the updated lines.
  let trailingLines = newLineRange.endIndex ..< newLineMap.lastLine + 1
  for line in trailingLines {
    newLineMap.setStartOfLine(line, startIndex: advance(newLineMap.startOfLine(line)!, changeInLength))
  }

    // Now, we need to retokenise all lines that whose tokens may possibly be affected by the edit.
  let offsets        = lineRangeRescanOffsets(lineMap, oldLineRange)
  let newStart       = max(1, Line(advance(Int(newLineRange.startIndex), -Int(offsets.0))))
  let newEnd         = min(Line(advance(Int(newLineRange.endIndex), Int(offsets.1))), newLineMap.lastLine + Line(1))
  let (open, close)  = commentBrackets(string, editedRange)
  let tokenLineRange = (close ? 1 : newStart) ..< (open ? newLineMap.lastLine + Line(1) : newEnd)
  let tokenCharRange = newLineMap.startOfLine(tokenLineRange.startIndex)!
                       ..< newLineMap.endOfLine(tokenLineRange.endIndex - 1)   // there is at least one line
  let rescanString   = (string as NSString).substringWithRange(toNSRange(tokenCharRange))
  newLineMap.replaceLineInfo(tokenLineRange.map{ ($0, []) })       // FIXME: this and next line might be nicer combined
  newLineMap.addLineInfo(tokensForLines(tokeniser(tokenLineRange.startIndex, 1, rescanString)))

  return (newLineMap, tokenLineRange)
}

/// Computes an array of tokens (and their source span) for one line from a `LineTokenMap`.
///
public func tokensAtLine(lineTokenMap: LineTokenMap)(line: Line) -> [(HighlightingToken, Range<Int>)] {
  if let index = lineTokenMap.startOfLine(line) {
    let tokens = lineTokenMap.infoOfLine(line)
    return map(tokens){ token in
      let endLine = token.span.start.line + token.span.lines - 1
      let start   = line == token.span.start.line
                    ? advance(index, Int(token.span.start.column) - 1)   // token starts on this line
                    : index                                              // token started on a previous line
      let end     = line == endLine
                    ? advance(index, Int(token.span.endColumn) - 1)      // token ends on this line
                    : lineTokenMap.endOfLine(line)                       // token ends on a subsequent line
      return (token, start..<end)
    }
  } else {
    return []
  }
}

/// Compute the tokens occuring in this character range at the underlying text storage. If even a single character of
/// a token is in the range, we regard the token to be in the range.
///
public func tokens(lineTokenMap: LineTokenMap, inRange range: Range<Int>) -> [HighlightingToken] {

  func tokenIsInRange(tokenWithRange: (HighlightingToken, Range<Int>)) -> Bool {
    return tokenWithRange.1.startIndex < range.endIndex && tokenWithRange.1.endIndex > range.startIndex
  }

  let lineRange = lineTokenMap.lineRange(range)
  return [].join(lineRange.map(tokensAtLine(lineTokenMap))).filter(tokenIsInRange).map{$0.0}
}

extension CodeView {

  func enableHighlighting(tokeniser: HighlightingTokeniser?) {
    layoutManager?.enableHighlighting(tokeniser)
  }

  /// Perform syntax highlighting for the given line range.
  ///
  func highlight(lineRange: Range<Line>) {
    if let lineMap = self.lineMap { layoutManager?.highlight(lineMap, lineRange: lineRange) }
  }

  /// Perform syntax highlighting for the entire text.
  ///
  func highlight() {
    if let lineMap = self.lineMap { layoutManager?.highlight(lineMap) }
  }
}

extension NSLayoutManager {

  func enableHighlighting(tokeniser: HighlightingTokeniser?) {
    (textStorage?.delegate as? CodeStorageDelegate)?.enableHighlighting(tokeniser)
  }

  /// Perform syntax highlighting for all lines in the line map.
  ///
  func highlight(lineTokenMap: LineTokenMap) {
    highlight(lineTokenMap, lineRange: 1...lineTokenMap.lastLine)
  }

  /// Perform syntax highlighting for the given range of lines in the line map.
  ///
  func highlight(lineTokenMap: LineTokenMap, lineRange: Range<Line>) {
    if lineRange.isEmpty { return }

      // Remove any existing temporary attributes in the entire range and highlight tabs.
    if let start = lineTokenMap.startOfLine(lineRange.startIndex) {

      let end = lineTokenMap.endOfLine(lineRange.endIndex - 1)
      setTemporaryAttributes([:], forCharacterRange: toNSRange(start..<end))

        // Mark all tab characters.
      let tabCharacterSet: NSCharacterSet = NSCharacterSet(charactersInString: "\t")
      let string:          NSString       = textStorage!.string
      let len                             = string.length
      var charIndex:       Int            = start
      while (charIndex != NSNotFound && charIndex < end) {

        if (charIndex < 0 || charIndex >= len || end > len) { break }
        let searchRange = NSRange(location: charIndex, length: end - charIndex)
        let foundRange  = string.rangeOfCharacterFromSet(tabCharacterSet, options: nil, range: searchRange)
        if foundRange.location != NSNotFound {

          addTemporaryAttributes(tabHighlightingAttributes, forCharacterRange: foundRange)
          charIndex = NSMaxRange(foundRange)

        } else { charIndex = NSNotFound }
      }
    }

      // Apply highlighting to all tokens in the affected range.
    for (token, span) in [].join(lineRange.map(tokensAtLine(lineTokenMap))) {
      if let attributes = (textStorage?.delegate as? CodeStorageDelegate)?.themeDict[token.kind] {
        addTemporaryAttributes(attributes, forCharacterRange: toNSRange(span))
      }
    }
  }
}
