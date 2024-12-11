module Utils.Error exposing (view)

{-|

@docs view

-}

import Elm.Error as Error
import Html exposing (..)
import Html.Attributes exposing (..)
import String


{-| -}
view : Error.Error -> Html msg
view error =
    div
        [ style "display" "inline-block"
        , style "box-sizing" "border-box"
        , style "width" "600px"
        , style "color" "rgb(233, 235, 235)"
        , style "font-family" "monospace"
        , style "white-space" "pre-wrap"
        , style "background-color" "black"
        , style "padding" "2em .5em"
        , style "margin-top" "40px"
        ]
        (viewErrorHelp error)


viewErrorHelp : Error.Error -> List (Html msg)
viewErrorHelp error =
    case error of
        Error.GeneralProblem { path, title, message } ->
            viewHeader title path :: viewMessage message

        Error.ModuleProblems badModules ->
            viewBadModules badModules



-- VIEW HEADER


viewHeader : String -> Maybe String -> Html msg
viewHeader title maybeFilePath =
    let
        left =
            "-- " ++ title ++ " "

        right =
            case maybeFilePath of
                Nothing ->
                    ""

                Just filePath ->
                    " " ++ filePath
    in
    span [ style "color" "rgb(51,187,200)" ] [ text (fill left right ++ "\n\n") ]


fill : String -> String -> String
fill left right =
    left ++ String.repeat (80 - String.length left - String.length right) "-" ++ right



-- VIEW BAD MODULES


viewBadModules : List Error.BadModule -> List (Html msg)
viewBadModules badModules =
    case badModules of
        [] ->
            []

        [ badModule ] ->
            [ viewBadModule badModule ]

        a :: b :: cs ->
            viewBadModule a :: viewSeparator a.name b.name :: viewBadModules (b :: cs)


viewBadModule : Error.BadModule -> Html msg
viewBadModule { path, problems } =
    span [] (List.map (viewProblem path) problems)


viewProblem : String -> Error.Problem -> Html msg
viewProblem filePath problem =
    span [] (viewHeader problem.title (Just filePath) :: viewMessage problem.message)


viewSeparator : String -> String -> Html msg
viewSeparator before after =
    span [ style "color" "rgb(211,56,211)" ]
        [ text <|
            String.padLeft 80 ' ' (before ++ "  ↑    ")
                ++ "\n"
                ++ "====o======================================================================o====\n"
                ++ "    ↓  "
                ++ after
                ++ "\n\n\n"
        ]



-- VIEW MESSAGE


viewMessage : List Error.Chunk -> List (Html msg)
viewMessage chunks =
    case chunks of
        [] ->
            [ text "\n\n\n" ]

        chunk :: others ->
            let
                htmlChunk =
                    case chunk of
                        Error.Unstyled string ->
                            text string

                        Error.Styled style string ->
                            span (styleToAttrs style) [ text string ]
            in
            htmlChunk :: viewMessage others


styleToAttrs : Error.Style -> List (Attribute msg)
styleToAttrs { bold, underline, color } =
    addBold bold <| addUnderline underline <| addColor color []


addBold : Bool -> List (Attribute msg) -> List (Attribute msg)
addBold bool attrs =
    if bool then
        style "font-weight" "bold" :: attrs

    else
        attrs


addUnderline : Bool -> List (Attribute msg) -> List (Attribute msg)
addUnderline bool attrs =
    if bool then
        style "text-decoration" "underline" :: attrs

    else
        attrs


addColor : Maybe Error.Color -> List (Attribute msg) -> List (Attribute msg)
addColor maybeColor attrs =
    case maybeColor of
        Nothing ->
            attrs

        Just color ->
            style "color" (colorToCss color) :: attrs


colorToCss : Error.Color -> String
colorToCss color =
    case color of
        Error.Red ->
            "rgb(194,54,33)"

        Error.RED ->
            "rgb(252,57,31)"

        Error.Magenta ->
            "rgb(211,56,211)"

        Error.MAGENTA ->
            "rgb(249,53,248)"

        Error.Yellow ->
            "rgb(173,173,39)"

        Error.YELLOW ->
            "rgb(234,236,35)"

        Error.Green ->
            "rgb(37,188,36)"

        Error.GREEN ->
            "rgb(49,231,34)"

        Error.Cyan ->
            "rgb(51,187,200)"

        Error.CYAN ->
            "rgb(20,240,240)"

        Error.Blue ->
            "rgb(73,46,225)"

        Error.BLUE ->
            "rgb(88,51,255)"

        Error.White ->
            "rgb(203,204,205)"

        Error.WHITE ->
            "rgb(233,235,235)"

        Error.Black ->
            "rgb(0,0,0)"

        Error.BLACK ->
            "rgb(129,131,131)"
