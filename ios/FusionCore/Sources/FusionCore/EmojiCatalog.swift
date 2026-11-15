import Foundation

public enum EmojiCatalog {
    public struct Group:Decodable,Identifiable {
        public let id:String
        public let items:[[String]]
        public var symbol:String { items.first?.first ?? "☺︎" }
    }
    public static let groups:[Group] = {
        let url=Bundle.module.url(forResource:"emoji",withExtension:"json",subdirectory:"Resources")!
        return try! JSONDecoder().decode([Group].self,from:Data(contentsOf:url))
    }()
    private static let variantsByEmoji:[String:[String]] = {
        var result:[String:[String]]=[:]
        for group in groups { for variants in group.items { for emoji in variants { result[emoji]=variants } } }
        return result
    }()
    public static func variants(of text:String) -> [String] { variantsByEmoji[text] ?? [text] }
}
