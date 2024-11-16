//
//  CameraView.swift
//  Honours Project
//
//  Created by Isaac Lafond on 2024-11-13.
//

/*
See the License.txt file for this sample’s licensing information.
*/

import SwiftUI

struct CameraView: View {
    @StateObject private var model = DataModel()
    
    var body: some View {
        ViewfinderView(image: $model.viewfinderImage)
            .overlay(alignment: .bottom) {
                HStack {
                    Spacer()
                    cameraButtonView()
                    Spacer()
                }
            }
            .task {
                await model.camera.start()
            }
    }
    
    private func cameraButtonView() -> some View {
        Button {
            model.camera.takePhoto()
        } label: {
            Label {
                Text("Take Photo")
            } icon: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 62, height: 62)
                    Circle()
                        .fill(.white)
                        .frame(width: 50, height: 50)
                }
            }
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .padding()
    }
    
}

#Preview {
    CameraView()
}
