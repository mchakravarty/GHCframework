//
//  Constants.swift
//  HaskellForMac
//
//  Created by Manuel M T Chakravarty on 18/11/2014.
//  Copyright (c) 2014 Manuel M T Chakravarty. All rights reserved.
//
//  Constants used throughout the app.

import Foundation

@objc class Swift { }     // for bridging

let kPreferenceIndentationWidth   = "IndentationWidth"
let kPreferenceExternalTextEditor = "ExternalTextEditor"
let kPreferenceEnableCloud        = "EnableCloud"
let kPreferenceUsername           = "Username"
let kPreferenceGHCLogLevel        = "GHCLogLevel"             // Must match the key used by 'GHCKit'.
let kPreferenceSpriteKitLogLevel  = "SpriteKitLogLevel"
let kPreferenceCloudLogLevel      = "CloudLogLevel"           // Must match the key used by 'CloudcelerateKit'.

extension Swift {
  class var swift_kPreferenceIndentationWidth:   String { get { return kPreferenceIndentationWidth } }
  class var swift_kPreferenceExternalTextEditor: String { get { return kPreferenceExternalTextEditor } }
  class var swift_kPreferenceEnableCloud:        String { get { return kPreferenceEnableCloud } }
  class var swift_kPreferenceUsername:           String { get { return kPreferenceUsername } }
  class var swift_kPreferenceGHCLogLevel:        String { get { return kPreferenceGHCLogLevel } }
  class var swift_kPreferenceSpriteKitLogLevel:  String { get { return kPreferenceSpriteKitLogLevel } }
  class var swift_kPreferenceCloudLogLevel:      String { get { return kPreferenceCloudLogLevel } }
}
