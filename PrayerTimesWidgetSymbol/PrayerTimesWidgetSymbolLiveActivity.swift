//
//  PrayerTimesWidgetSymbolLiveActivity.swift
//  PrayerTimesWidgetSymbol
//
//  Created by Mert Gedik on 10.03.26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct PrayerTimesWidgetSymbolAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct PrayerTimesWidgetSymbolLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerTimesWidgetSymbolAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension PrayerTimesWidgetSymbolAttributes {
    fileprivate static var preview: PrayerTimesWidgetSymbolAttributes {
        PrayerTimesWidgetSymbolAttributes(name: "World")
    }
}

extension PrayerTimesWidgetSymbolAttributes.ContentState {
    fileprivate static var smiley: PrayerTimesWidgetSymbolAttributes.ContentState {
        PrayerTimesWidgetSymbolAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: PrayerTimesWidgetSymbolAttributes.ContentState {
         PrayerTimesWidgetSymbolAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: PrayerTimesWidgetSymbolAttributes.preview) {
   PrayerTimesWidgetSymbolLiveActivity()
} contentStates: {
    PrayerTimesWidgetSymbolAttributes.ContentState.smiley
    PrayerTimesWidgetSymbolAttributes.ContentState.starEyes
}
