// Internal ASCII byte-level helpers shared across LexiconStringFormat validators. Only generic
// byte tests live here; format-specific punctuation sets and predicates stay with their owning
// format file.

func isDigit(_ b: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b) }
func isLowerAlpha(_ b: UInt8) -> Bool { (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(b) }
func isUpperAlpha(_ b: UInt8) -> Bool { (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(b) }
func isAlpha(_ b: UInt8) -> Bool { isLowerAlpha(b) || isUpperAlpha(b) }
func isAlphanumeric(_ b: UInt8) -> Bool { isAlpha(b) || isDigit(b) }
