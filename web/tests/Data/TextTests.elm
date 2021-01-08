module Data.TextTests exposing (suite)

import Data.Text as Text
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Text test"
        [ describe "isEmpty test"
            [ test "empty" <|
                \() ->
                    Expect.equal (Text.isEmpty Text.empty) True
            , test "not empty" <|
                \() ->
                    Expect.equal (Text.isEmpty (Text.edit Text.empty "test")) False
            ]
        , describe "isChanged test"
            [ test "changed" <|
                \() ->
                    Expect.equal (Text.isChanged (Text.edit Text.empty "test")) True
            , test "not changed" <|
                \() ->
                    Expect.equal (Text.isChanged (Text.edit Text.empty "")) False
            ]
        ]
