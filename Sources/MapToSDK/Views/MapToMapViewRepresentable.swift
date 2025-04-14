// Sources/MyMapboxWrapper/Views/MapToMapViewRepresentable.swift

import SwiftUI
import MapboxMaps
import Combine // Needed for AnyCancellable

struct MapToMapViewRepresentable: UIViewRepresentable {

    let accessToken: String
    let cameraOptions: CameraOptions
    let styleURI: StyleURI
    let features: [Feature] // <-- Pass features data
    let cdnBaseURL: URL // <-- Pass CDN URL for icons

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
        context.coordinator.mapView = mapView // Give coordinator access to mapView
        context.coordinator.setupEventObservation() // Start listening for map events

        // Ornaments setup
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.scaleBar.visibility = .hidden

        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        print("MapToMapViewRepresentable: updateUIView called.")

        // Update coordinator's reference to parent state if needed (structs are value types)
        context.coordinator.parent = self
        context.coordinator.mapView = uiView // Ensure coordinator has the current view instance

        // Basic checks to update map for dynamic changes
        if styleURI != uiView.mapboxMap.style.uri {
            print("Updating style URI to: \(styleURI.rawValue)")
            uiView.mapboxMap.style.uri = styleURI
            // Style change will trigger coordinator's onStyleLoaded again
        } else if !areCameraOptionsSimilar(uiView.cameraState, cameraOptions) {
             print("Updating camera state.")
             uiView.camera.fly(to: cameraOptions, duration: 0.5)
        } else {
            // If only features changed, tell the coordinator to update them
            // This requires comparing feature arrays, which can be complex.
            // For simplicity now, we rely on onStyleLoaded to add features initially.
            // A more robust solution might involve diffing features.
            // context.coordinator.updateFeaturesIfNeeded()
        }
    }

    // Helper function (keep as is)
    private func areCameraOptionsSimilar(_ current: CameraState, _ new: CameraOptions) -> Bool {
        // ... (implementation from previous step) ...
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
        weak var mapView: MapView? // Use weak reference to avoid retain cycles
        private var cancellables = Set<AnyCancelable>()
        private var iconManager: IconManager
        private var isSourceLayerSetup = false // Flag to prevent duplicate setup

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

            // Observe style loaded event
            map.onStyleLoaded.observe { [weak self] _ in
                print("Coordinator: Style loaded.")
                self?.isSourceLayerSetup = false // Reset flag on style change
                self?.setupDataSourceAndLayer()
                self?.loadIconsAndFeatures()
            }.store(in: &cancellables)

            // Observe map loaded event (useful for initial setup if style is already loaded)
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

            // Add other observers (map idle, render frame, etc.) if needed later
        }

        /// Sets up the GeoJSON source and Symbol layer for features if not already done.
        func setupDataSourceAndLayer() {
            guard let map = mapView?.mapboxMap, !isSourceLayerSetup else {
                 if isSourceLayerSetup { print("Coordinator: Source and layer already set up.") }
                 return
            }
            print("Coordinator: Setting up source and layer...")

            // 1. Create GeoJSON Source
            var source = GeoJSONSource(id: featureSourceId)
            // Initialize with empty feature collection
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
                return // Stop if source setup fails
            }

            // 2. Create Symbol Layer
            var layer = SymbolLayer(id: featureLayerId, source: featureSourceId)

            // Configure layout properties using Expressions (mirroring React code)
            layer.iconImage = .expression(
                Exp(.switchCase) {
                    Exp(.eq) { Exp(.get) { "iconType" }; "dynamic" } // If iconType is dynamic...
                    Exp(.get) { "featureId" } // ...use the feature's unique ID (placeholder for dynamic icon name)
                    Exp(.get) { "icon" } // ...otherwise use the 'icon' property value
                }
            )
            layer.iconAllowOverlap = .constant(true)
            layer.textAllowOverlap = .constant(true) // If using text later
            layer.iconAnchor = .expression(Exp(.get, "iconAnchor"))
            layer.iconIgnorePlacement = .constant(true)
            layer.textIgnorePlacement = .constant(true) // If using text later

            // Icon size interpolation (matching React example)
            layer.iconSize = .expression(
                Exp(.interpolate) {
                    Exp(.exponential) { 2 }
                    Exp(.zoom) // Input is the current zoom level
                    // Stops: zoom level, output size
                    0 // At zoom 0
                    Exp(.switchCase) { // Output size at zoom 0
                        Exp(.eq) { Exp(.get) { "type" }; "icon" } // Check feature type (using "icon" as example type)
                        Exp(.get) { "zoomEffect" } // Use zoomEffect value if type is "icon"
                        0.0 // Default size 0 if not type "icon"
                    }
                    24 // At zoom 24 (or other high zoom level)
                    Exp(.get) { "size" } // Output size is the 'size' property value
                }
            )

            // Configure paint properties
            layer.iconOpacity = .expression(Exp(.get) { "opacity" })

            // Add layer to the style
            do {
                if !map.style.layerExists(withId: featureLayerId) {
                    try map.style.addLayer(layer) // Add below labels potentially: .below("symbol-layer-id-of-labels")
                    print("Coordinator: Added symbol layer '\(featureLayerId)'.")
                } else {
                     print("Coordinator: Layer '\(featureLayerId)' already exists.")
                     // If it exists, maybe update its properties? For now, assume it's correct.
                }
                isSourceLayerSetup = true // Mark setup as complete
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

            Task { // Perform async operations
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
                    // Handle error appropriately (e.g., show alert, log)
                }
            }
        }

        // Optional: Method to update features if the input array changes
        // func updateFeaturesIfNeeded() { ... }
    }
}
