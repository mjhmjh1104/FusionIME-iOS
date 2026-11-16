import SwiftUI
import CoreText

/// A tiny bundled fallback covers the supplementary ideographs in our Korean
/// and Mozc dictionaries, including U+2012C and U+30EDE, which can be missing
/// on iOS font cascades.
enum CandidateTypography {
    private static let fallback:CTFont? = {
        guard let url=Bundle.main.url(forResource:"FusionCandidateFallback",withExtension:"otf",subdirectory:"Fonts") else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
        return CTFontCreateWithName("FusionCandidateFallback-Regular" as CFString,20,nil)
    }()
    private static let coverage:CFCharacterSet? = fallback.map(CTFontCopyCharacterSet)
    static func usesFallback(_ scalar:Unicode.Scalar)->Bool {
        scalar.value>0xffff && coverage.map{CFCharacterSetIsLongCharacterMember($0,scalar.value)} == true
    }
    static func text(_ value:String,size:CGFloat)->Text {
        guard value.unicodeScalars.contains(where:usesFallback) else { return Text(value).font(.system(size:size)) }
        return value.reduce(Text("")) { text,character in
            let fallback=character.unicodeScalars.contains(where:usesFallback)
            return text+Text(String(character)).font(fallback ? .custom("FusionCandidateFallback-Regular",fixedSize:size):.system(size:size))
        }
    }
}
