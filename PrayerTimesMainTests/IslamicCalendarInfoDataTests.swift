import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers Block 1 of the hadith-source review: every entry in
/// `IslamicCalendarInfoData.hadithItems` must cite a real, checkable
/// collection + number — never a chapter heading, never a reused citation
/// for a claim that specific hadith doesn't actually make.
@MainActor
struct IslamicCalendarInfoDataTests {
    private func item(_ title: String) -> FastingHadithItem {
        let match = IslamicCalendarInfoData.hadithItems.first { $0.title == title }
        precondition(match != nil, "expected a hadith item titled \(title)")
        return match!
    }

    @Test func noSourceCitesOnlyAChapterHeading() async throws {
        for entry in IslamicCalendarInfoData.hadithItems {
            #expect(!entry.source.localizedCaseInsensitiveContains("Kapitelüberschrift"))
        }
    }

    @Test func thursdayCitesItsOwnHadithNotTheMondayOneAboutBirthAndRevelation() async throws {
        let thursday = item("Donnerstag")
        // The old, invalid citation reused Monday's "Sahih Muslim 1162"
        // family for a claim that hadith never makes about Thursday.
        #expect(!thursday.source.contains("Muslim 1162"))
        #expect(thursday.source.contains("Tirmidhi"))
    }

    @Test func whiteDaysCiteADedicatedSourceNamingTheDaysNotTheGenericThreeDaysHadith() async throws {
        let whiteDays = item("Weiße Tage")
        // The old citation ("Sahih Muslim 1162b") never mentions day
        // numbers 13/14/15 at all.
        #expect(!whiteDays.source.contains("Muslim 1162"))
        #expect(whiteDays.source.contains("Abi Dawud") || whiteDays.source.contains("Abu Dawud"))
    }

    @Test func mondayCitesTheIsolatedMondayVariant() async throws {
        let monday = item("Montag")
        #expect(monday.source.contains("1162e"))
    }

    @Test func everyHadithItemHasANonEmptySource() async throws {
        for entry in IslamicCalendarInfoData.hadithItems {
            #expect(!entry.source.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
