//
//  ContentView.swift
//  Test
//
//  Created by David Walter on 18.02.23.
//

import SwiftUI
import EmojiText

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    RemoteEmojiView()
                } label: {
                    Text("Remote Emoji")
                }
                
                NavigationLink {
                    SFSymbolEmojiView()
                } label: {
                    Text("SF Symbol Emoji")
                }
            }
            .navigationTitle("EmojiText")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
