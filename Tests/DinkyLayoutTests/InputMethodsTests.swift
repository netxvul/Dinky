import Testing
@testable import DinkyLayout

struct InputMethodsTests {
    @Test func `Apps in an Input Methods folder are input methods`() {
        #expect(isInputMethodBundle("/Library/Input Methods/Squirrel.app", home: "/Users/a"))
        #expect(isInputMethodBundle("/System/Library/Input Methods/PressAndHold.app", home: "/Users/a"))
        #expect(isInputMethodBundle("/Users/a/Library/Input Methods/Squirrel.app", home: "/Users/a"))
    }

    @Test func `Others are not, a build of one elsewhere included`() {
        #expect(!isInputMethodBundle("/Applications/Safari.app", home: "/Users/a"))
        #expect(!isInputMethodBundle("/Users/a/Developer/squirrel/build/Release/Squirrel.app", home: "/Users/a"))
        #expect(!isInputMethodBundle("/Users/b/Library/Input Methods/Squirrel.app", home: "/Users/a"))
        #expect(!isInputMethodBundle("/Library/Input MethodsX/Squirrel.app", home: "/Users/a"))
    }
}
