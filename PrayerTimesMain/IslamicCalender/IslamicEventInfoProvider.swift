import Foundation

enum IslamicEventInfoProvider {
    static func description(for title: String) -> String {
        let normalized = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        switch normalized {
        case let t where t.contains("ramadan"):
            return "Ramadan ist der Fastenmonat im Islam. In diesem Monat wird tagsüber gefastet; er erinnert an die Offenbarung des Qurans."

        case let t where t.contains("eid al-fitr"),
             let t where t.contains("eid ul-fitr"),
             let t where t.contains("fitr"):
            return "Eid al-Fitr ist das Fest des Fastenbrechens und markiert das Ende des Ramadan. Der Tag beginnt üblicherweise mit dem Festgebet und wird mit Besuchen, Mahlzeiten und Freude gefeiert."

        case let t where t.contains("eid al-adha"),
             let t where t.contains("eid ul-adha"),
             let t where t.contains("adha"):
            return "Eid al-Adha ist das Opferfest und erinnert an die Bereitschaft Ibrahims zum Opfer. Es fällt in die Zeit des Hadsch und gehört zu den wichtigsten islamischen Festtagen."

        case let t where t.contains("ashura"):
            return "Ashura ist der 10. Tag des Monats Muharram. In der sunnitischen Tradition ist er mit Fasten verbunden; in der schiitischen Tradition ist er besonders mit dem Gedenken an Husayn ibn Ali verbunden."

        case let t where t.contains("mawlid"),
             let t where t.contains("milad"),
             let t where t.contains("birthday of prophet"),
             let t where t.contains("birth of prophet"):
            return "Mawlid an-Nabi bezeichnet das Gedenken an die Geburt des Propheten Muhammad. Die Begehung ist in der muslimischen Welt verbreitet, wird aber nicht in allen Traditionen gleich bewertet."

        case let t where t.contains("laylat al-qadr"),
             let t where t.contains("night of power"),
             let t where t.contains("night of decree"):
            return "Laylat al-Qadr gilt als die Nacht der Bestimmung und wird in den letzten zehn Nächten des Ramadan gesucht. Sie gilt als eine der bedeutendsten Nächte des islamischen Jahres."

        case let t where t.contains("arafah"),
             let t where t.contains("day of arafah"):
            return "Der Tag von Arafah ist der 9. Dhu l-Hijjah und steht in enger Verbindung mit dem Hadsch. Er gilt als besonders bedeutender Tag des islamischen Jahres."

        case let t where t.contains("isra") || t.contains("miraj") || t.contains("mi'raj"):
            return "Isra und Mi'raj bezeichnen die Nachtreise und Himmelfahrt des Propheten Muhammad. Der Tag erinnert an ein zentrales Ereignis der islamischen Überlieferung."

        case let t where t.contains("new year"),
             let t where t.contains("muharram"):
            return "Das islamische Neujahr markiert den Beginn eines neuen Hijri-Jahres im Monat Muharram. Es ist ein Zeitpunkt der Besinnung und des neuen Anfangs."

        default:
            return "Dies ist ein besonderer islamischer Tag. Die App hat dafür noch keinen ausführlichen Beschreibungstext hinterlegt."
        }
    }
}
