//
//  PrayerTimesWidgetSymbolBundle.swift
//  PrayerTimesWidgetSymbol
//
//  Created by Mert Gedik on 10.03.26.
//

import WidgetKit
import SwiftUI

@main
struct PrayerTimesWidgetSymbolBundle: WidgetBundle {
    var body: some Widget {
        PrayerTimesWidgetSymbol()
        PrayerTimesWidgetSymbolControl()
        PrayerTimesWidgetSymbolLiveActivity()
    }
}
