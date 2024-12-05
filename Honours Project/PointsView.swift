//
//  PointsView.swift
//  Honours Project
//
//  Created by Isaac Lafond on 2024-12-04.
//

import SwiftUI

struct PointsView: View {
    let image: Image
    let imageWidth: CGFloat = 3024
    let imageHeight: CGFloat = 4032
    
    @State private var point: CGPoint? = nil
    @Binding public var pixel: CGPoint?

    
    var body: some View {
        VStack {
            GeometryReader { geometry in
                ZStack {
                    // Display the image
                    image
                        .resizable()
                        .scaledToFit() // Ensures the image fits the available space while maintaining aspect ratio
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    
                    // Display the point if it's placed
                    if let point = point {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .position(point)
                    }
                }
                .onTapGesture { location in
                    // Calculate the pixel coordinates when the user taps
                    let imageX = location.x / geometry.size.width * imageWidth
                    let imageY = location.y / geometry.size.height * imageHeight
                    
                    // Update the point position in terms of the image
                    point = CGPoint(x: location.x, y: location.y)
                    
                    pixel = CGPoint(x: imageX, y: imageY)
                }
            }
            .frame(height: 400) // Set a fixed height for the image view (you can change it as needed)
            
//            Text(point?.debugDescription ?? CGPoint.zero.debugDescription)
//            Text(pixel?.debugDescription ?? CGPoint.zero.debugDescription)
        }
    }
}

#Preview {
    PointsView(image: Image(systemName: "target"), pixel: .constant(.zero))
}
