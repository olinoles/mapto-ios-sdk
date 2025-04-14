// Sources/MyMapboxWrapper/Views/MapboxMapView.swift

import SwiftUI
import MapboxMaps
import CoreLocation

public struct MapToMapView: View {

    @StateObject private var dataLoader = MapDataLoader()

    private let mapFileURL: URL
    private let accessToken: String
    private let cdnBaseURL: URL

    /// Creates a MapTo map view that loads its configuration asynchronously.
    ///
    /// - Parameters:
    ///   - mapFileURL: The URL pointing to the JSON map configuration file.
    ///   - accessToken: Your public Mapbox access token. Must be valid and non-empty.
    ///   - cdnBaseURL: The base URL for loading icon assets.

    public init(mapFileURL: URL, accessToken: String, cdnBaseURL: URL) {
        self.mapFileURL = mapFileURL
        self.cdnBaseURL = cdnBaseURL
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

// MARK: - SwiftUI Previews

#if DEBUG
struct MapToMapView_Previews: PreviewProvider {
    static var previews: some View {
        
        let accessToken = ProcessInfo.processInfo.environment["MAPBOX_ACCESS_TOKEN"] ?? ""
        
        let previewURL = URL(string: "https://cdn.mapto.app/map/jG076")!
        let previewCdnURL = URL(string: "https://cdn.mapto.app/")!

        guard !accessToken.isEmpty else {
             return AnyView(ErrorView(message: "Preview requires a valid Mapbox Access Token.", retryAction: nil))
         }

        return AnyView(
            MapToMapView(
                mapFileURL: previewURL,
                accessToken: accessToken,
                cdnBaseURL: previewCdnURL
            )
        )
    }
}
#endif
