// Sources/MyMapboxWrapper/Views/MapToMapViewRepresentable.swift

import SwiftUI
import MapboxMaps
import Combine

struct MapToMapViewRepresentable: UIViewRepresentable {

    let accessToken: String
    let cameraOptions: CameraOptions
    let styleURI: StyleURI
    let features: [Feature]
    let cdnBaseURL: URL

    // MARK: - UIViewRepresentable Lifecycle

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MapView {
        print("MapToMapViewRepresentable: makeUIView called.")
        MapboxOptions.accessToken = self.accessToken

        let mapInitOptions = MapInitOptions(
            cameraOptions: cameraOptions,
            styleURI: styleURI
        )

        let mapView = MapView(frame: .zero, mapInitOptions: mapInitOptions)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.mapView = mapView
        context.coordinator.setupEventObservation()

        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.scaleBar.visibility = .hidden

        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        print("MapToMapViewRepresentable: updateUIView called.")

        context.coordinator.parent = self
        context.coordinator.mapView = uiView

        // Basic checks to update map for dynamic changes
        if styleURI != uiView.mapboxMap.style.uri {
            print("Updating style URI to: \(styleURI.rawValue)")
            uiView.mapboxMap.style.uri = styleURI
        } else if !areCameraOptionsSimilar(uiView.cameraState, cameraOptions) {
             print("Updating camera state.")
             uiView.camera.fly(to: cameraOptions, duration: 0.5)
        }
    }

    // Helper function (keep as is)
    private func areCameraOptionsSimilar(_ current: CameraState, _ new: CameraOptions) -> Bool {
        guard let newCenter = new.center, let newZoom = new.zoom, let newBearing = new.bearing else { return false }
        let tolerance = 0.001
        let zoomTolerance = 0.1
        return abs(current.center.latitude - newCenter.latitude) < tolerance &&
               abs(current.center.longitude - newCenter.longitude) < tolerance &&
               abs(current.zoom - newZoom) < zoomTolerance &&
               abs(current.bearing - newBearing) < tolerance
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject {
        var parent: MapToMapViewRepresentable
        weak var mapView: MapView?
        private var cancellables = Set<AnyCancelable>()
        private var iconManager: IconManager
        private var isSourceLayerSetup = false

        // Constants for source and layer IDs
        let featureSourceId = "scenery-source"
        let featureLayerId = "scenery-layer"

        init(parent: MapToMapViewRepresentable) {
            self.parent = parent
            self.iconManager = IconManager(cdnBaseURL: parent.cdnBaseURL)
            super.init()
        }

        func setupEventObservation() {
            guard let map = mapView?.mapboxMap else { return }

            map.onStyleLoaded.observe { [weak self] _ in
                print("Coordinator: Style loaded.")
                self?.isSourceLayerSetup = false
                self?.setupDataSourceAndLayer()
                self?.loadIconsAndFeatures()
            }.store(in: &cancellables)

            map.onMapLoaded.observe { [weak self] _ in
                 print("Coordinator: Map loaded.")
                 // If style is already loaded by the time map finishes loading,
                 // ensure setup happens. onStyleLoaded might fire first anyway.
                 if self?.mapView?.mapboxMap.style.isLoaded == true && self?.isSourceLayerSetup == false {
                     print("Coordinator: Map loaded, style already loaded, ensuring setup.")
                     self?.setupDataSourceAndLayer()
                     self?.loadIconsAndFeatures()
                 }
            }.store(in: &cancellables)

            // TODO Add other observers (map idle, render frame, etc.) later
        }

        /// Sets up the GeoJSON source and Symbol layer for features if not already done.
        func setupDataSourceAndLayer() {
            guard let map = mapView?.mapboxMap, !isSourceLayerSetup else {
                 if isSourceLayerSetup { print("Coordinator: Source and layer already set up.") }
                 return
            }
            print("Coordinator: Setting up source and layer...")

            var source = GeoJSONSource(id: featureSourceId)

            source.data = .featureCollection(FeatureCollection(features: []))
            do {
                if !map.style.sourceExists(withId: featureSourceId) {
                    try map.style.addSource(source)
                    print("Coordinator: Added GeoJSON source '\(featureSourceId)'.")
                } else {
                    print("Coordinator: Source '\(featureSourceId)' already exists.")
                }
            } catch {
                print("Coordinator: Failed to add source '\(featureSourceId)': \(error)")
                return
            }

            var layer = SymbolLayer(id: featureLayerId, source: featureSourceId)

            layer.iconImage = .expression(
                Exp(.switchCase) {
                    Exp(.eq) { Exp(.get) { "iconType" }; "dynamic" }
                    Exp(.get) { "featureId" }
                    Exp(.get) { "icon" }
                }
            )
            layer.iconAllowOverlap = .constant(true)
            layer.textAllowOverlap = .constant(true)
            layer.iconAnchor = .expression(Exp(.get, "iconAnchor"))
            layer.iconIgnorePlacement = .constant(true)
            layer.textIgnorePlacement = .constant(true)

            layer.iconSize = .expression(
                Exp(.interpolate) {
                    Exp(.exponential) { 2 }
                    Exp(.zoom)
                    0
                    Exp(.switchCase) {
                        Exp(.eq) { Exp(.get) { "type" }; "icon" }
                        Exp(.get) { "zoomEffect" }
                        0.0
                    }
                    24
                    Exp(.get) { "size" }
                }
            )

            layer.iconOpacity = .expression(Exp(.get) { "opacity" })


            do {
                if !map.style.layerExists(withId: featureLayerId) {
                    try map.style.addLayer(layer)
                    print("Coordinator: Added symbol layer '\(featureLayerId)'.")
                } else {
                     print("Coordinator: Layer '\(featureLayerId)' already exists.")
                }
                isSourceLayerSetup = true
            } catch {
                print("Coordinator: Failed to add layer '\(featureLayerId)': \(error)")
            }
        }

        /// Loads required icons and updates the GeoJSON source with features.
        func loadIconsAndFeatures() {
            guard let map = mapView?.mapboxMap, isSourceLayerSetup else {
                print("Coordinator: Cannot load features, source/layer not ready.")
                return
            }
            print("Coordinator: Loading icons and features...")

            let features = parent.features
            guard !features.isEmpty else {
                print("Coordinator: No features to load.")
                // Clear source if needed?
                // try? map.updateGeoJSONSource(withId: featureSourceId, geoJSON: .featureCollection(FeatureCollection(features: [])))
                return
            }

            // Extract unique, non-dynamic icon names
            let standardIconNames = Set(features.filter { $0.iconType != "dynamic" }.map { $0.icon })

            Task {
                do {
                    // Load standard icons
                    if !standardIconNames.isEmpty {
                        print("Coordinator: Loading \(standardIconNames.count) standard icons...")
                        _ = try await iconManager.loadAndAddIcons(names: standardIconNames, to: map)
                        print("Coordinator: Standard icon loading complete.")
                    }

                    // TODO: Handle dynamic icons later (generate image, add with featureId name)

                    // All required icons should now be loaded (or failed), proceed to update source
                    print("Coordinator: Updating GeoJSON source with \(features.count) features...")
                    let mapboxFeatures = features.compactMap { feature -> MapboxMaps.Feature? in
                        guard let coord = feature.coordinate2D else { return nil }
                        var mapboxFeature = MapboxMaps.Feature(geometry: Point(coord))
                        mapboxFeature.properties = feature.makeGeoJSONProperties()
                        // Use the feature's generated UUID as the GeoJSON feature ID if needed,
                        // though Mapbox doesn't strictly require IDs on features themselves.
                        // mapboxFeature.identifier = .string(feature.id.uuidString)
                        return mapboxFeature
                    }

                    // Update the source data
                    try map.updateGeoJSONSource(withId: featureSourceId, geoJSON: .featureCollection(FeatureCollection(features: mapboxFeatures)))
                    print("Coordinator: GeoJSON source '\(featureSourceId)' updated successfully.")

                } catch {
                    print("Coordinator: Failed during icon loading or feature update: \(error)")
                    // TODO handle error appropriately
                }
            }
        }
    }
}
