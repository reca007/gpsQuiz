import CoreLocation
import MapKit
import SwiftUI

struct CourseMapPoint: Identifiable {
    let id: UUID
    let title: String
    let coordinate: CLLocationCoordinate2D

    init(id: UUID = UUID(), title: String, latitude: Double, longitude: Double) {
        self.id = id
        self.title = title
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct CourseMapPreview: View {
    let points: [CourseMapPoint]
    let title: String
    let subtitle: String

    private var coordinates: [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: .constant(.region(region))) {
                ForEach(points) { point in
                    Annotation(point.title, coordinate: point.coordinate) {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 30, height: 30)
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                        .shadow(radius: 3, y: 2)
                    }
                }

                if coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates + [coordinates[0]])
                        .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .allowsHitTesting(false)

            LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.84))
            }
            .padding(14)
        }
        .frame(minHeight: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
    }

    private var region: MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 59.3293, longitude: 18.0686),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLatitude = latitudes.min() ?? first.latitude
        let maxLatitude = latitudes.max() ?? first.latitude
        let minLongitude = longitudes.min() ?? first.longitude
        let maxLongitude = longitudes.max() ?? first.longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.006, (maxLatitude - minLatitude) * 1.8),
                longitudeDelta: max(0.006, (maxLongitude - minLongitude) * 1.8)
            )
        )
    }
}
