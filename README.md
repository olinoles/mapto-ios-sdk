# MapTo iOS SDK

An iOS implementation of the [MapTo](https://mapto.app) map viewer.

Prerequisites:
- You must have a valid [Mapbox access token](https://docs.mapbox.com/help/getting-started/access-tokens/) (free up to 50,000 loads)

## Example

```
struct ContentView: View {
    var body: some View {

        let accessToken = "YOUR_ACCESS_TOKEN_HERE"
        let mapURL = URL(string: "https://cdn.mapto.app/map/jG076")!
        let cdnURL = URL(string: "https://cdn.mapto.app/")!

        return AnyView(
            MapboxMapView(
                mapFileURL: mapURL,
                accessToken: accessToken,
                cdnBaseURL: cdnURL
            )
        )
    }
}
```
