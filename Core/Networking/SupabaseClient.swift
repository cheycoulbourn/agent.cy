import Foundation
import Supabase

enum SupabaseConfig {
    static let url = URL(string: "https://bkfbeghitnpicrmhkkal.supabase.co")!
    static let anonKey = "sb_publishable_NqwkmyLiVY3dTJUA56iGvw_HDmF6rrA"
}

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.anonKey
)
