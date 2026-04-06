enum CityInputMode: String, CaseIterable, Identifiable {
    case picker = "Aus Liste"
    case manual = "Manuell"

    var id: String { rawValue }
}
