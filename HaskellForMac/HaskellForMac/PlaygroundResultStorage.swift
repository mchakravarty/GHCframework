//
//  PlaygroundResultStorage.swift
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 19/10/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//
//  This class is the view model for the results displayed in a playground and serves as the data source of the table
//  view displaying the results.

import Cocoa


/// Represents the result for a single command.
///
struct Result {
  // FIXME: for now, it's all strings, but we want to be more flexible in the future.

  let value: String
  let type:  String
  let stale: Bool         // a result is stale while it is being recomputed
}

class PlaygroundResultStorage: NSObject {

  // The results for all commands in the playground if successfully computed.
  //
  // NB: The length of the array always equals the number of commands in the playground.
  //
  private var results: [Result?] = []

  /// Reports a result at a specific index. Allocates new results slots if needed.
  ///
  func reportResult(result: String, type: String, atCommandIndex idx: Int) {

      // Extend the array to include the reported index if necessary.
    if idx >= results.endIndex {
      for i in results.endIndex...idx { results.append(nil) }
    }
    results[idx] = Result(value: result, type: type, stale: false)
  }

  /// Discard all entries from the given index on.
  ///
  func pruneAt(idx: Int) {
    if idx < advance(results.endIndex, -1) {
      results.removeRange(idx..<results.endIndex)
    }
  }

  /// Marks all current results as stale.
  ///
  func invalidate() {
    results = results.map{ result in
      if let result = result {
        return Result(value: result.value, type: result.type, stale: true)
      } else { return nil }
    }
  }
}

extension PlaygroundResultStorage: NSTableViewDataSource {

  func numberOfRowsInTableView(_tableView: NSTableView) -> Int {
    return results.count
  }

  func tableView(_tableView: NSTableView, column: NSTableColumn, row: Int) -> String {
    return "x"
  }
}