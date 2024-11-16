//
//  ViewfinderView.swift
//  Honours Project
//
//  Created by Isaac Lafond on 2024-11-13.
//

/*
See the License.txt file for this sample’s licensing information.
*/

import SwiftUI

struct ViewfinderView: View {
    @Binding var image: Image?
    
    var body: some View {
        if let image = image {
            image
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                
        } else {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                errorTextView
                    .foregroundStyle(Color.white)
                    .background(Color.black)
            }
            
        }
    }
    
    private var errorTextView: some View {
        Text(Image(systemName: "exclamationmark.triangle"))+Text("Viewfinder Unavailable")
    }
}


#Preview {
    ViewfinderView(image: .constant(nil))
}
