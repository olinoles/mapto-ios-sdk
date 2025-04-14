// Sources/MyMapboxWrapper/Views/MapboxMapView.swift

import SwiftUI
import MapboxMaps
import CoreLocation

public struct MapToMapView: View {

    @StateObject private var dataLoader = MapDataLoader()

    private let mapFileURL: URL
    private let accessToken: String
    private let cdnBaseURL: URL

    /// Creates a Mapbox map view that loads its configuration asynchronously.
    ///
    /// - Parameters:
    ///   - mapFileURL: The URL pointing to the JSON map configuration file.
    ///   - accessToken: Your public Mapbox access token. Must be valid and non-empty.
    ///   - cdnBaseURL: The base URL for loading icon assets.
    public init(mapFileURL: URL, accessToken: String, cdnBaseURL: URL) {
        self.mapFileURL = mapFileURL
        self.cdnBaseURL = cdnBaseURL // <-- Store it
        guard !accessToken.isEmpty else {
            fatalError("Mapbox Access Token provided to MapToMapView cannot be empty.")
        }
        self.accessToken = accessToken
    }

    public var body: some View {
        ZStack {
            switch dataLoader.state {
            case .idle:
                ProgressView()
                    .onAppear {
                        dataLoader.loadMapFile(from: mapFileURL)
                    }
            case .loading:
                ProgressView()

            case .success(let mapFile):
                // Data loaded, now extract config and features for the representable
                if let centerCoord = mapFile.centerCoordinate,
                   let style = StyleURI(rawValue: mapFile.style) {

                    let cameraOptions = CameraOptions(
                        center: centerCoord,
                        zoom: mapFile.zoom,
                        bearing: mapFile.bearing
                    )

                    MapToMapViewRepresentable(
                        accessToken: accessToken,
                        cameraOptions: cameraOptions,
                        styleURI: style,
                        features: mapFile.features,
                        cdnBaseURL: cdnBaseURL
                    )
                    .ignoresSafeArea()

                } else {
                    ErrorView(message: "Failed to configure map from loaded data. Invalid center or style URI.") {
                         dataLoader.loadMapFile(from: mapFileURL)
                    }
                }

            case .failed(let error):
                ErrorView(message: "Failed to load map data: \(error.localizedDescription)") {
                    dataLoader.loadMapFile(from: mapFileURL)
                }
            }
        }
        .onDisappear {
             dataLoader.cancel()
        }
    }
}

// ErrorView struct remains the same...

// MARK: - SwiftUI Previews

#if DEBUG
struct MapToMapView_Previews: PreviewProvider {
    static var previews: some View {
        // !! WARNING !! Avoid committing real tokens.
        let previewAccessToken = "pk.eyJ1IjoibWFwdG8tcHJvZCIsImEiOiJjbTd2cnQzdG0wM3AyMmtwaGFoamx0eHd5In0.HLpfGxAUjAgh9F2qAjcgvA" // Replace if needed

        let previewURL = URL(string: "https://cdn.mapto.app/map/jG076")!
        // Define the CDN base URL for previews (adjust if different from production)
        let previewCdnURL = URL(string: "https://cdn.mapto.app/")! // Assuming this is the base

        guard !previewAccessToken.isEmpty, !previewAccessToken.starts(with: "YOUR_") else {
             return AnyView(ErrorView(message: "Preview requires a valid Mapbox Access Token.", retryAction: nil))
         }

        return AnyView(
            MapToMapView(
                mapFileURL: previewURL,
                accessToken: previewAccessToken,
                cdnBaseURL: previewCdnURL
            )
        )
    }
}
#endif
