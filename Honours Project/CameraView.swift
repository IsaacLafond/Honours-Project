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
    @State private var showSheet = false
    
    var body: some View {
        ViewfinderView(image: $model.viewfinderImage)
            .overlay() {
                VStack {
                    if model.viewfinderImage != nil {
                        Text("Align your food in the target")
                            .padding()
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    
                    Spacer()
                    cameraButtonView()
                }
            }
            .task {
                await model.camera.start()
            }
            .sheet(isPresented: $showSheet, onDismiss: {
                model.camera.capturedImage = nil
            }, content: {
                ResultView(capture: model.camera.capturedImage)
            })
    }
    
    private func cameraButtonView() -> some View {
        Button {
            // capture photo and depth
            model.camera.takePhoto()
            // show result sheet
            showSheet = true
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
