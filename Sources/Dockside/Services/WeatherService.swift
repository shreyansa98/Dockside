import Foundation
import Combine

struct WeatherDay: Identifiable {
    let id = UUID()
    let date: Date
    let code: Int
    let high: Int
    let low: Int
    var symbol: String { WeatherService.symbol(for: code, isDay: true) }
    var weekday: String { date.formatted(.dateTime.weekday(.abbreviated)) }
}

struct WeatherSnapshot {
    var city: String
    var temperature: Int
    var feelsLike: Int
    var code: Int
    var isDay: Bool
    var humidity: Int
    var wind: Int
    var days: [WeatherDay]
    var updated: Date

    var symbol: String { WeatherService.symbol(for: code, isDay: isDay) }
    var condition: String { WeatherService.description(for: code) }
}

/// Weather from Open-Meteo (no API key). Location comes from a city name in Settings, or IP geolocation.
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    @Published var current: WeatherSnapshot?
    @Published var error: String?
    @Published var loading = false

    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in self?.refresh() }
        Store.shared.$settings
            .map { "\($0.weatherCity)|\($0.fahrenheit)" }
            .removeDuplicates().dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &bag)
    }

    func refresh() {
        loading = true
        let s = Store.shared.settings
        Task {
            do {
                let loc = try await locate(city: s.weatherCity)
                let snap = try await forecast(lat: loc.lat, lon: loc.lon, city: loc.name, fahrenheit: s.fahrenheit)
                await MainActor.run { self.current = snap; self.error = nil; self.loading = false }
            } catch {
                await MainActor.run { self.error = "Couldn't load weather"; self.loading = false }
            }
        }
    }

    private struct Location { var lat: Double; var lon: Double; var name: String }

    private func locate(city: String) async throws -> Location {
        let trimmed = city.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            c.queryItems = [.init(name: "name", value: trimmed), .init(name: "count", value: "1")]
            let (data, _) = try await URLSession.shared.data(from: c.url!)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let r = (json?["results"] as? [[String: Any]])?.first,
               let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double {
                return Location(lat: lat, lon: lon, name: r["name"] as? String ?? trimmed)
            }
        }
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://ipwho.is/")!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let lat = json?["latitude"] as? Double, let lon = json?["longitude"] as? Double else {
            throw URLError(.badServerResponse)
        }
        return Location(lat: lat, lon: lon, name: json?["city"] as? String ?? "")
    }

    private func forecast(lat: Double, lon: Double, city: String, fahrenheit: Bool) async throws -> WeatherSnapshot {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "6"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            .init(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh"),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = json["current"] as? [String: Any],
              let daily = json["daily"] as? [String: Any] else { throw URLError(.cannotParseResponse) }

        let times = daily["time"] as? [String] ?? []
        let codes = daily["weather_code"] as? [Int] ?? []
        let highs = daily["temperature_2m_max"] as? [Double] ?? []
        let lows = daily["temperature_2m_min"] as? [Double] ?? []
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        var days: [WeatherDay] = []
        for i in times.indices where i < codes.count && i < highs.count && i < lows.count {
            days.append(WeatherDay(date: df.date(from: times[i]) ?? Date(), code: codes[i],
                                   high: Int(highs[i].rounded()), low: Int(lows[i].rounded())))
        }
        func num(_ k: String) -> Double { (cur[k] as? Double) ?? Double(cur[k] as? Int ?? 0) }
        return WeatherSnapshot(
            city: city,
            temperature: Int(num("temperature_2m").rounded()),
            feelsLike: Int(num("apparent_temperature").rounded()),
            code: cur["weather_code"] as? Int ?? 0,
            isDay: (cur["is_day"] as? Int ?? 1) == 1,
            humidity: Int(num("relative_humidity_2m")),
            wind: Int(num("wind_speed_10m").rounded()),
            days: days,
            updated: Date())
    }

    static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: "cloud.rain.fill"
        case 65, 67, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(for code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly Clear"
        case 2: "Partly Cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing Drizzle"
        case 61, 63: "Rain"
        case 65: "Heavy Rain"
        case 66, 67: "Freezing Rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Showers"
        case 85, 86: "Snow Showers"
        case 95, 96, 99: "Thunderstorm"
        default: "—"
        }
    }
}
