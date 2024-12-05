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
            ZStack {
                image
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                Image(systemName: "scope")
                    .foregroundStyle(.red)
                    .fontWeight(.bold)
            }
            
                
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
    ViewfinderView(image: .constant(Image(systemName: "photo")))
}
