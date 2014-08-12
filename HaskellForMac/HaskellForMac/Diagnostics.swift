//
//  Diagnostics.swift
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 8/08/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//
//  Model for diagnostics.

import Foundation
import GHCKit


typealias Line   = UInt
typealias Column = UInt

/// Source code locations
///
struct SrcLoc {
  let file:   String
  let line:   Line
  let column: Column
}

/// Source code spans
///
/// The 'endColumn' is the column *after* the last character included in the span.
///
struct SrcSpan {
  let start:     SrcLoc
  let lines:     UInt
  let endColumn: Column
}

/// Severity of an issue
///
enum Severity {case Warning, Error, Other}

/// Convert a GHCKit severity value into one of ours.
///
func toSeverity(ghcSeverity: GHCSeverity) -> Severity {
  switch ghcSeverity {
  case .Output, .Dump, .Interactive, .Info, .Fatal:
    return .Other
  case .Warning:
    return .Warning
  case .Error:
    return .Error
  }
}

/// A single source code issue.
///
struct Issue {
  let span:     SrcSpan
  let severity: Severity
  let message:  String

  init(severity:  GHCSeverity,
       filename:  String,
       line:      UInt,
       column:    UInt,
       lines:     UInt,
       endColumn: UInt,
       message:   String) {
    switch severity {
    case .Output, .Dump, .Interactive, .Info, .Fatal:
      NSLog("unrecognised GHC diagnostic %@:", message)
    default:
      break
    }
    self.span     = SrcSpan(start: SrcLoc(file: filename, line: line, column: column),
                            lines: lines,
                            endColumn: endColumn)
    self.severity = toSeverity(severity)
    self.message  = message
  }
}

/// Determine the highest severity of all given issues (if any).
///
func maxSeverityOfIssues(issues: [Issue]) -> Severity? {
  return issues.reduce(nil){ acc, issue in
    if let severity = acc {
      return issue.severity
    } else {
      return issue.severity
    }
  }
}

/// A set of issues flagged by the compiler for a single source file can be indexed by line number. All issues
/// appearing on a single line are sorted by their starting column.
///
typealias Issues = [Column: [Issue]]

/// All issues flagged by the compiler for a single source file including the file name.
///
struct IssuesForFile {
  let file:   String
  let issues: Issues
}
