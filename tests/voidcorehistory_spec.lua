dofile("Where2Go/Core/VoidcoreHistory.lua")

assert(Where2GoVoidcoreHistory.ParseItemIdFromLink("|cffa335ee|Hitem:12345::::::::80:::::|h[Sample Item]|h|r") == 12345,
    "should parse the item ID out of a real-shaped item link")

assert(Where2GoVoidcoreHistory.ParseItemIdFromLink("|cffffffff|Hitem:271092:0:0:0:0:0:0:0:80:0:0:0:0:0|h[Janthrazet]|h|r") == 271092,
    "should parse a different item link's ID correctly")

assert(Where2GoVoidcoreHistory.ParseItemIdFromLink(nil) == nil, "nil input should return nil")
assert(Where2GoVoidcoreHistory.ParseItemIdFromLink(12345) == nil, "non-string input should return nil")
assert(Where2GoVoidcoreHistory.ParseItemIdFromLink("not a link") == nil, "unparseable string should return nil")

print("voidcorehistory_spec: OK")
