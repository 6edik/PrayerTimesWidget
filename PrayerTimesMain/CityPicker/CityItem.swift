import Foundation

struct CityItem: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let state: String
    let district: String
    let area: Double?
    let population: Int?
    let latitude: Double?
    let longitude: Double?

    var admin1: String? { state }
    var admin2: String? { district }

    var subtitle: String {
        [district, state]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private enum CodingKeys: String, CodingKey {
        case area
        case coords
        case district
        case name
        case population
        case state
    }

    private enum CoordsKeys: String, CodingKey {
        case lat
        case lon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decode(String.self, forKey: .name)
        state = try container.decode(String.self, forKey: .state)
        district = try container.decode(String.self, forKey: .district)

        let areaString = try container.decodeIfPresent(String.self, forKey: .area)
        let populationString = try container.decodeIfPresent(String.self, forKey: .population)

        if let coords = try? container.nestedContainer(keyedBy: CoordsKeys.self, forKey: .coords) {
            let latString = try coords.decodeIfPresent(String.self, forKey: .lat)
            let lonString = try coords.decodeIfPresent(String.self, forKey: .lon)

            latitude = latString.flatMap(Double.init)
            longitude = lonString.flatMap(Double.init)
        } else {
            latitude = nil
            longitude = nil
        }

        area = areaString.flatMap(Double.init)
        population = populationString.flatMap(Int.init)

        id = "\(name)-\(district)-\(state)"
    }
}

