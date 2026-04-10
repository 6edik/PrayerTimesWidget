import SwiftUI

// MARK: - Models

struct CalendarLegendItem: Identifiable {
    let id = UUID()
    let color: Color
    let symbol: String
    let title: String
    let description: String
}

struct FastingHadithItem: Identifiable {
    let id = UUID()
    let title: String
    let badge: String
    let summary: String
    let detail: String
    let source: String
}

enum IslamicCalendarInfoData {
    static let legendItems: [CalendarLegendItem] = [
        .init(
            color: .orange,
            symbol: "sparkles",
            title: "Besondere Ereignisse",
            description: "Wichtige islamische Anlässe wie Eid, Mawlid, Laylat al-Qadr, Arafah oder Ashura"
        ),
        .init(
            color: .blue,
            symbol: "moon.stars",
            title: "Sunnah-Fastentage",
            description: "Montag, Donnerstag sowie die weißen Tage 13, 14 und 15 des Hijri-Monats"
        ),
        .init(
            color: .green,
            symbol: "checkmark.circle.fill",
            title: "Heute",
            description: "Der aktuell ausgewählte heutige Tag"
        )
    ]

    static let hadithItems: [FastingHadithItem] = [
        .init(
            title: "Montag",
            badge: "M",
            summary: "Der Prophet fastete montags; es ist der Tag seiner Geburt und der Sendung.",
            detail: "Der Prophet ﷺ erklärte zum Fasten am Montag, dass dies der Tag sei, an dem er geboren wurde und an dem ihm die Offenbarung zuteilwurde.",
            source: "Sahih Muslim 1162b"
        ),
        .init(
            title: "Donnerstag",
            badge: "D",
            summary: "Montag und Donnerstag gehören zu den bekannten Tagen, an denen freiwilliges Fasten empfohlen ist.",
            detail: "Im Kapitel über die empfohlenen Fasttage werden Montag und Donnerstag zusammen mit den drei Tagen jedes Monats genannt. Viele Gelehrte führen daraus die besondere Empfehlung dieser beiden Wochentage an.",
            source: "Sahih Muslim 1162b, Kapitelüberschrift"
        ),
        .init(
            title: "Weiße Tage",
            badge: "13–15",
            summary: "Drei Tage in jedem Monat zu fasten gehört zur etablierten Sunnah.",
            detail: "Der Prophet ﷺ empfahl, regelmäßig drei Tage jedes Monats zu fasten. In den Überlieferungen werden dafür insbesondere die weißen Tage, also der 13., 14. und 15. Tag des Hijri-Monats, genannt.",
            source: "Sahih Muslim 1162b"
        ),
        .init(
            title: "Sechs Tage in Shawwal",
            badge: "6",
            summary: "Wer nach Ramadan noch sechs Tage Shawwal fastet, erhält den Lohn eines ganzjährigen Fastens.",
            detail: "Der Prophet ﷺ sagte, dass jemand, der Ramadan fastet und ihn mit sechs Tagen aus Shawwal ergänzt, so belohnt wird, als hätte er das ganze Jahr gefastet.",
            source: "Sahih Muslim 1164a"
        ),
        .init(
            title: "Fasten in Sha'ban",
            badge: "Sha",
            summary: "Der Prophet fastete in Sha'ban mehr als in anderen Monaten außer Ramadan.",
            detail: "Von ʿAisha رضي الله عنها wird berichtet, dass sie den Propheten ﷺ in keinem Monat so häufig fasten sah wie in Sha'ban; damit zeigt sich die besondere Stellung dieses Monats für freiwilliges Fasten.",
            source: "Sahih al-Bukhari 1970"
        ),
        .init(
            title: "Tag von Arafah",
            badge: "9",
            summary: "Das Fasten an Arafah sühnt nach der Überlieferung Sünden des vergangenen und kommenden Jahres.",
            detail: "Der Prophet ﷺ sagte über das Fasten am Tag von ʿArafah, dass er von Allah erhoffe, dadurch die Sünden des vergangenen und des kommenden Jahres tilgen zu lassen.",
            source: "Sahih Muslim 1162a"
        ),
        .init(
            title: "Ashura",
            badge: "10",
            summary: "Das Fasten an Ashura sühnt nach der Überlieferung die Sünden des vergangenen Jahres.",
            detail: "Zum Fasten am Tag von ʿAshura sagte der Prophet ﷺ, dass er von Allah erhoffe, dadurch die Sünden des vergangenen Jahres tilgen zu lassen.",
            source: "Sahih Muslim 1162a"
        ),
        .init(
            title: "Fasten Dawuds",
            badge: "1/1",
            summary: "Das liebste freiwillige Fasten ist das Fasten Dawuds: einen Tag fasten, einen Tag nicht.",
            detail: "Der Prophet ﷺ sagte zu ʿAbdullah ibn ʿAmr, dass das am meisten geliebte Fasten bei Allah das Fasten Dawuds sei; er fastete jeden zweiten Tag.",
            source: "Sahih al-Bukhari 3420"
        )
    ]
}
