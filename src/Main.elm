port module Main exposing (main)

import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Elm.Docs as Docs
import Elm.Type as Type
import Html exposing (Html, a, code, div, h1, input, li, span, text, ul)
import Html.Attributes exposing (class, href, id, multiple, name, src, style, title, type_)
import Html.Events exposing (on)
import Json.Decode as Decode exposing (Decoder)
import Markdown
import Svg exposing (svg)
import Svg.Attributes exposing (d, fill, height, viewBox, width)
import Url exposing (Url)



-- PORTS


port filesSelected : Decode.Value -> Cmd msg


port readmeReceived : (String -> msg) -> Sub msg


port modulesReceived : (Decode.Value -> msg) -> Sub msg



-- TYPES


type Msg
    = FilesSelected Decode.Value
    | ReadmeReceived String
    | ModulesReceived Decode.Value
    | UrlRequested UrlRequest
    | UrlChanged Url


type alias Model =
    { readme : Maybe String
    , modules : List Docs.Module
    , key : Nav.Key
    , page : Page
    }


type Page
    = Readme
    | Module String



-- INIT


init : () -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    ( { readme = Nothing
      , modules = []
      , key = key
      , page = Readme
      }
    , Nav.replaceUrl key url.path
    )



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "Elm Doc Preview"
    , body =
        [ div [ class "center" ]
            [ page model
            , navigation model
            ]
        , footer
        ]
    }


navigation : Model -> Html Msg
navigation model =
    div
        [ class "pkg-nav"
        ]
        [ logo
        , filesInput
        , case model.readme of
            Just _ ->
                links model.page [ Readme ]

            Nothing ->
                text ""
        , model.modules
            |> List.map (\m -> Module m.name)
            |> links model.page
        ]


logo : Html msg
logo =
    div
        [ style "display" "flex" ]
        [ svg
            [ width "50px", height "70px", viewBox "0 0 210 297" ]
            [ Svg.path [ d "M61.8 132v92.7l46.3-46.3-46.3-46.3z", fill "#60b5cc" ] []
            , Svg.path [ d "M83 59.9L62.9 80.2 83 100.5z", fill "#f0ad00" ] []
            , Svg.path [ d "M109 184.1l-65.4 65.5H109v-65.5z", fill "#5a6378" ] []
            , Svg.path [ d "M145 217.6l-32.1 32H143l32-32z", fill "#7fd13b" ] []
            , Svg.path [ d "M59.4 83.5l-22.7 22.7 22.7 22.7 22.7-22.7z", fill "#7fd13b" ] []
            , Svg.path [ d "M35.8 59.9v40.6L56 80.2z", fill "#f0ad00" ] []
            , Svg.path [ d "M57 132l-31 31.2 31 31v-62.1z", fill "#60b5cc" ] []
            ]
        , div
            [ style "color" "#5a6378ff"
            , style "line-height" "16px"
            , style "padding-top" "12px"
            , style "transform" "translateX(-20px)"
            ]
            [ div [] [ text "elm doc" ]
            , div [] [ text "preview" ]
            ]
        ]


page : Model -> Html msg
page model =
    div [ class "block-list" ] <|
        case model.page of
            Readme ->
                case model.readme of
                    Just readme ->
                        [ markdown readme ]

                    Nothing ->
                        if List.isEmpty model.modules then
                            [ markdown howto ]

                        else
                            [ markdown howtoWithModules ]

            Module name ->
                model.modules
                    |> List.filter (\m -> m.name == name)
                    |> List.map doc
                    |> List.concat


howto : String
howto =
    """
# Elm Documentation Previewer

Open a package `README.md`, `docs.json` (generated with `elm make --docs`) or both.

To restart from scratch, just reload the page.
"""


howtoWithModules : String
howtoWithModules =
    """
# Elm Documentation Previewer

Select a module and optionally add a `README.md` file.
"""


doc : Docs.Module -> List (Html msg)
doc docs =
    h1 [ class "block-list-title" ]
        [ text docs.name ]
        :: List.map block (Docs.toBlocks docs)


block : Docs.Block -> Html msg
block b =
    case b of
        Docs.MarkdownBlock string ->
            markdown string

        Docs.UnionBlock union ->
            unionBlock union

        Docs.AliasBlock alias ->
            aliasBlock alias

        Docs.ValueBlock value ->
            valueBlock value

        Docs.BinopBlock binop ->
            binopBlock binop

        Docs.UnknownBlock string ->
            div [] [ text string ]


type ParameterizedTypeStyle
    = WithParentheses
    | WithoutParentheses


unionBlock : Docs.Union -> Html msg
unionBlock union =
    div [ class "docs-block" ]
        [ div [ class "docs-header" ]
            [ span [ class "hljs-keyword" ] [ text "type" ]
            , text " "
            , span [ class "hljs-type" ] [ text union.name ]
            , text " "
            , text (String.join " " union.args)
            , tags union.tags
            ]
        , div [ class "docs-comment" ]
            [ markdown union.comment
            ]
        ]


aliasBlock : Docs.Alias -> Html msg
aliasBlock alias =
    div [ class "docs-block" ]
        [ div [ class "docs-header" ]
            [ span [ class "hljs-keyword" ] [ text "type" ]
            , text " "
            , span [ class "hljs-keyword" ] [ text "alias" ]
            , text " "
            , span [ class "hljs-type" ] [ text alias.name ]
            , text " "
            , if List.length alias.args > 0 then
                text (String.join " " alias.args ++ " = ")

              else
                text "="
            , indent []
                [ tipe WithoutParentheses alias.tipe
                ]
            ]
        , div [ class "docs-comment" ]
            [ markdown alias.comment
            ]
        ]


valueBlock : Docs.Value -> Html msg
valueBlock value =
    div [ class "docs-block" ]
        [ div [ class "docs-header" ]
            [ span
                [ class "hljs-title"
                , style "font-weight" "bold"
                ]
                [ text value.name
                ]
            , text " : "
            , tipe WithoutParentheses value.tipe
            ]
        , div [ class "docs-comment" ]
            [ markdown value.comment
            ]
        ]


binopBlock : Docs.Binop -> Html msg
binopBlock binop =
    div [ class "docs-block" ]
        [ div [ class "docs-header" ]
            [ span
                [ class "hljs-title"
                , style "font-weight" "bold"
                ]
                [ text "("
                , text binop.name
                , text ")"
                ]
            , text " : "
            , tipe WithoutParentheses binop.tipe
            ]
        , div [ class "docs-comment" ]
            [ markdown binop.comment
            ]
        ]


tags : List ( String, List Type.Type ) -> Html msg
tags tags_ =
    case tags_ of
        [] ->
            text ""

        t :: ts ->
            div []
                (tag "=" t :: List.map (tag "|") ts)


tag : String -> ( String, List Type.Type ) -> Html msg
tag prefix ( name, types ) =
    indent []
        [ text (prefix ++ " ")
        , span [ class "hljs-literal" ] [ text name ]
        , text " "
        , tipes WithParentheses " " types
        ]


indent : List (Html.Attribute msg) -> List (Html msg) -> Html msg
indent attributes children =
    div (style "margin-left" "2rem" :: attributes) children


indentIf : Bool -> List (Html.Attribute msg) -> List (Html msg) -> Html msg
indentIf cond attributes children =
    if cond then
        indent attributes children

    else
        span attributes children


tipe : ParameterizedTypeStyle -> Type.Type -> Html msg
tipe typeStyle t =
    case t of
        Type.Var string ->
            var string

        Type.Lambda t1 t2 ->
            lambda t1 t2

        Type.Tuple list ->
            tuple list

        Type.Type name types ->
            typ typeStyle name types

        Type.Record fields_ rowType ->
            record fields_ rowType


tipes : ParameterizedTypeStyle -> String -> List Type.Type -> Html msg
tipes typeStyle separator types =
    List.map (tipe typeStyle) types
        |> List.intersperse (text separator)
        |> span []


var : String -> Html msg
var string =
    text string


lambda : Type.Type -> Type.Type -> Html msg
lambda t1 t2 =
    span []
        [ case t1 of
            Type.Lambda _ _ ->
                span []
                    [ text "("
                    , tipe WithoutParentheses t1
                    , text ")"
                    ]

            _ ->
                tipe WithoutParentheses t1
        , text " -> "
        , tipe WithoutParentheses t2
        ]


tuple : List Type.Type -> Html msg
tuple types =
    if List.isEmpty types then
        text "()"

    else
        span []
            [ text "( "
            , tipes WithoutParentheses ", " types
            , text " )"
            ]


typ : ParameterizedTypeStyle -> String -> List Type.Type -> Html msg
typ typeStyle name types =
    let
        shortName =
            name
                |> String.split "."
                |> List.reverse
                |> List.head
                |> Maybe.withDefault name
    in
    if List.isEmpty types then
        span [ title name, class "hljs-type" ] [ text shortName ]

    else if typeStyle == WithParentheses then
        span []
            [ text "("
            , span [ title name, class "hljs-type" ] [ text shortName ]
            , text " "
            , tipes WithoutParentheses " " types
            , text ")"
            ]

    else
        span []
            [ span [ title name, class "hljs-type" ] [ text shortName ]
            , text " "
            , tipes WithoutParentheses " " types
            ]


record : List ( String, Type.Type ) -> Maybe String -> Html msg
record fields_ rowType =
    case rowType of
        Just r ->
            indentIf (List.length fields_ > 1)
                []
                [ text "{ "
                , text r
                , indentIf (List.length fields_ > 1)
                    []
                    [ fields "|" fields_
                    ]
                , text "}"
                ]

        Nothing ->
            indentIf (List.length fields_ > 1)
                []
                [ fields "{" fields_
                , text "}"
                ]


fields : String -> List ( String, Type.Type ) -> Html msg
fields prefix list =
    case list of
        f :: fs ->
            span []
                (field span prefix f
                    :: List.map (field div ",") fs
                )

        [] ->
            text prefix


field :
    (List (Html.Attribute msg) -> List (Html msg) -> Html msg)
    -> String
    -> ( String, Type.Type )
    -> Html msg
field element prefix ( fieldName, fieldType ) =
    element []
        [ text (prefix ++ " ")
        , text fieldName
        , text " : "
        , tipe WithoutParentheses fieldType
        ]


markdownOptions : Markdown.Options
markdownOptions =
    { githubFlavored = Just { tables = False, breaks = False }
    , defaultHighlighting = Just "elm"
    , sanitize = True
    , smartypants = True
    }


markdown : String -> Html msg
markdown string =
    Markdown.toHtmlWith markdownOptions [] string



-- Side navigation bar


filesInput : Html Msg
filesInput =
    div
        [ style "display" "flex"
        , style "align-items" "center"
        , style "height" "38px"
        ]
        [ input
            [ type_ "file"
            , multiple True
            , on "change"
                (Decode.at [ "target", "files" ] Decode.value
                    |> Decode.map FilesSelected
                )
            ]
            []
        ]


links : Page -> List Page -> Html msg
links currentPage pages =
    ul [ style "margin-top" "20px" ]
        (List.map (link currentPage) pages)


link : Page -> Page -> Html msg
link currentPage targetPage =
    li []
        [ a
            [ class "pkg-nav-module"
            , case targetPage of
                Readme ->
                    href ""

                Module name ->
                    href ("#/" ++ name)
            , if currentPage == targetPage then
                style "font-weight" "bold"

              else
                style "" ""
            , if currentPage == targetPage then
                style "text-decoration" "underline"

              else
                style "" ""
            ]
            [ case targetPage of
                Readme ->
                    text "README"

                Module name ->
                    text name
            ]
        ]



-- Footer


footer : Html msg
footer =
    div [ class "footer" ]
        [ text "All code for this site is "
        , a
            [ class "grey-link"
            , href "https://github.com/dmy/elm-doc-preview"
            ]
            [ text "open source" ]
        , text " and written in Elm."
        ]



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FilesSelected files ->
            ( model
            , filesSelected files
            )

        ReadmeReceived string ->
            ( { model
                | readme = Just string
                , page = Readme
              }
            , Cmd.none
            )

        ModulesReceived value ->
            case Decode.decodeValue (Decode.list Docs.decoder) value of
                Ok modules ->
                    ( { model
                        | modules = modules
                        , page = Readme
                      }
                    , Cmd.none
                    )

                Err err ->
                    ( model, Cmd.none )

        UrlRequested request ->
            case request of
                Internal url ->
                    ( model
                    , Nav.pushUrl model.key (Url.toString url)
                    )

                External url ->
                    ( model
                    , Nav.load url
                    )

        UrlChanged url ->
            let
                modules =
                    List.map .name model.modules

                segment =
                    url.fragment
                        |> Maybe.map (String.dropLeft 1)
                        |> Maybe.withDefault ""
            in
            case List.member segment modules of
                True ->
                    ( { model | page = Module segment }
                    , Cmd.none
                    )

                False ->
                    ( { model | page = Readme }
                    , Cmd.none
                    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ readmeReceived ReadmeReceived
        , modulesReceived ModulesReceived
        ]



-- MAIN


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }
