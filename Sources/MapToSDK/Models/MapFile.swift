// Sources/MyMapboxWrapper/Models/MapFile.swift

import Foundation
import CoreLocation
import MapboxMaps // Needed for IconAnchor
import Turf

// MARK: - MapFile

struct MapFile: Decodable, Identifiable {
    let id: String
    let style: String
    let center: [CLLocationDegrees] // [longitude, latitude]
    let bearing: CLLocationDegrees
    let zoom: Double
    let features: [Feature] // <-- Add features array
    // Add other fields like 'title', 'polygons' here later if needed

    var centerCoordinate: CLLocationCoordinate2D? {
        guard center.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: center[1], longitude: center[0])
    }
}

// MARK: - Feature

struct Feature: Decodable, Identifiable {
    let id = UUID()
    let type: String
    let icon: String
    let iconType: String
    let iconAnchor: String
    let coordinates: String
    let size: Double
    let opacity: Double
    let zoomEffect: Double
    let title: String?
    let subtitle: String?
    let enableInteraction: Bool?

    // CodingKeys to map JSON keys to Swift properties if needed (optional here as names match well)
    // enum CodingKeys: String, CodingKey {
    //     case type, icon, iconType, iconAnchor, coordinates, size, opacity, zoomEffect, title, subtitle, description, enableInteraction
    // }

    /// Parses the coordinate string into CLLocationCoordinate2D.
    var coordinate2D: CLLocationCoordinate2D? {
        let parts = coordinates.split(separator: ",").map(String.init).compactMap(Double.init)
        guard parts.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: parts[1], longitude: parts[0])
    }

    /// Generates the properties dictionary for the GeoJSON feature.
    func makeGeoJSONProperties() -> Turf.JSONObject { // Return type is correct
            var properties: Turf.JSONObject = [:] // Initialize empty dictionary

            // Assign values using explicit Turf.JSONValue cases
            properties["type"] = Turf.JSONValue.string(type)
            properties["icon"] = Turf.JSONValue.string(icon)
            properties["iconType"] = Turf.JSONValue.string(iconType)
            properties["iconAnchor"] = Turf.JSONValue.string(iconAnchor.lowercased())
            properties["size"] = Turf.JSONValue.number(size)
            properties["opacity"] = Turf.JSONValue.number(opacity)
            properties["zoomEffect"] = Turf.JSONValue.number(zoomEffect)
            properties["featureId"] = Turf.JSONValue.string(id.uuidString)

            // Add optional properties using explicit Turf.JSONValue cases
            if let title = title, !title.isEmpty {
                properties["title"] = Turf.JSONValue.string(title)
            }
            if let subtitle = subtitle, !subtitle.isEmpty {
                properties["subtitle"] = Turf.JSONValue.string(subtitle)
            }
            if let enableInteraction = enableInteraction {
                properties["enableInteraction"] = Turf.JSONValue.boolean(enableInteraction)
            }

            return properties
        }
}
