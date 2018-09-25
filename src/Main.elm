port module Main exposing (main)

import Block
import Browser exposing (UrlRequest(..))
import Browser.Dom as Dom
import Browser.Navigation as Nav
import Elm.Docs as Docs
import Elm.Type as Type
import Html exposing (Html, a, code, div, h1, input, label, li, span, text, ul)
import Html.Attributes exposing (attribute, class, for, href, id, multiple, name, src, style, tabindex, title, type_)
import Html.Events exposing (on, onClick, preventDefaultOn)
import Json.Decode as Decode exposing (Decoder)
import Markdown
import Svg exposing (svg)
import Svg.Attributes exposing (d, fill, height, viewBox, width)
import Task
import Url exposing (Url)
import Utils.Markdown as Markdown



-- PORTS


port openFiles : () -> Cmd msg


port clearStorage : () -> Cmd msg


port readFiles : Decode.Value -> Cmd msg


port readItems : Decode.Value -> Cmd msg


port readmeReceived : (String -> msg) -> Sub msg


port modulesReceived : (Decode.Value -> msg) -> Sub msg



-- TYPES


type Msg
    = NoOp
    | OpenFiles
    | Close
    | FilesSelected Decode.Value
    | ItemsDropped Decode.Value
    | ModulesReceived Decode.Value
    | ReadmeReceived String
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


type alias Flags =
    { readme : Maybe String
    , docs : Maybe String
    }


init : Flags -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        modules =
            case flags.docs of
                Just docs ->
                    Decode.decodeString (Decode.list Docs.decoder) docs
                        |> Result.withDefault []

                Nothing ->
                    []

        requestedModule =
            urlToModule url

        requestedPage =
            if List.member requestedModule (List.map .name modules) then
                Module requestedModule

            else
                Readme
    in
    ( { readme = flags.readme
      , modules = modules
      , key = key
      , page = requestedPage
      }
    , Cmd.batch
        [ if not (String.isEmpty url.path) && requestedPage == Readme then
            -- Remove not found module from URL
            Nav.replaceUrl key "/"

          else
            Cmd.none
        , if url.fragment == Nothing then
            Task.attempt (always NoOp) (Dom.focus "files-input-label")

          else
            Cmd.none
        ]
    )



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "Elm Doc Preview"
    , body =
        [ div
            [ style "min-width" "100%"
            , style "min-height" "100%"
            , style "display" "flex"
            , style "flex-direction" "column"
            , preventDefaultOn "drop"
                (Decode.at [ "dataTransfer", "items" ] Decode.value
                    |> Decode.map (\items -> ( ItemsDropped items, True ))
                )
            , stopDragOver
            ]
            [ div
                [ class "center"
                , style "flex" "1"
                ]
                [ page model
                , navigation model
                ]
            , footer
            ]
        ]
    }


stopDragOver : Html.Attribute Msg
stopDragOver =
    preventDefaultOn "dragover" (Decode.map alwaysPreventDefault (Decode.succeed NoOp))


alwaysPreventDefault : msg -> ( msg, Bool )
alwaysPreventDefault msg =
    ( msg, True )


navigation : Model -> Html Msg
navigation model =
    div
        [ class "pkg-nav"
        ]
        [ logo
        , filesInput
        , closeLink model
        , case model.readme of
            Just _ ->
                navLinks model.page [ Readme ]

            Nothing ->
                text ""
        , model.modules
            |> List.map (\m -> Module m.name)
            |> navLinks model.page
        ]


closeLink : Model -> Html Msg
closeLink model =
    if model.readme == Nothing && model.modules == [] then
        text ""

    else
        div [ style "margin-top" "20px" ]
            [ a
                [ href "/"
                , onClick Close
                ]
                [ text "Close Preview" ]
            ]


logo : Html msg
logo =
    div
        [ style "display" "flex"
        , style "transform" "translateX(-8px)"
        ]
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


page : Model -> Html Msg
page model =
    div [ class "block-list" ] <|
        case model.page of
            Readme ->
                case model.readme of
                    Just readme ->
                        [ Markdown.block readme ]

                    Nothing ->
                        if List.isEmpty model.modules then
                            [ Markdown.block howto ]

                        else
                            [ Markdown.block howtoWithModules ]

            Module name ->
                case List.filter (\m -> m.name == name) model.modules of
                    [ module_ ] ->
                        doc model.modules module_

                    _ ->
                        [ h1 [] [ text "Error" ]
                        , text "Module not found."
                        ]


howto : String
howto =
    """
# Elm Documentation Previewer

Open a package `README.md`, `docs.json` (generated with `elm make --docs`) or both.

Click **Open Files** on the side or **drag & drop files** anywhere in the page.


*No data is sent to the server, so you can safely preview private packages documentation.*
"""


howtoWithModules : String
howtoWithModules =
    """
# Elm Documentation Previewer

Select a module and optionally add a `README.md` file.
"""


doc : List Docs.Module -> Docs.Module -> List (Html msg)
doc modules module_ =
    let
        info =
            Block.makeInfo module_.name modules
    in
    h1 [ class "block-list-title" ] [ text module_.name ]
        :: List.map (Block.view info) (Docs.toBlocks module_)



-- Side navigation bar


filesInput : Html Msg
filesInput =
    div
        []
        [ label
            [ for "files-input"
            , class "files-input"
            ]
            [ span
                [ id "files-input-label"
                , attribute "role" "button"
                , attribute "aria-controls" "filenames"
                , tabindex 0
                , onEnterOrSpace OpenFiles
                ]
                [ text "Open Files" ]
            ]
        , input
            [ id "files-input"
            , type_ "file"
            , style "display" "none"
            , multiple True
            , on "change"
                (Decode.at [ "target", "files" ] Decode.value
                    |> Decode.map FilesSelected
                )
            ]
            []
        ]


onEnterOrSpace : msg -> Html.Attribute msg
onEnterOrSpace msg =
    on "keyup"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    if key == "Enter" || key == " " then
                        Decode.succeed msg

                    else
                        Decode.fail ""
                )
        )


navLinks : Page -> List Page -> Html msg
navLinks currentPage pages =
    ul [ style "margin-top" "20px" ]
        (List.map (navLink currentPage) pages)


navLink : Page -> Page -> Html msg
navLink currentPage targetPage =
    li []
        [ a
            [ class "pkg-nav-module"
            , case targetPage of
                Readme ->
                    href "/"

                Module name ->
                    href ("/" ++ String.replace "." "-" name)
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
        [ text "The code for this site is "
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
        NoOp ->
            ( model, Cmd.none )

        OpenFiles ->
            ( model, openFiles () )

        Close ->
            ( { model
                | readme = Nothing
                , modules = []
                , page = Readme
              }
            , clearStorage ()
            )

        FilesSelected files ->
            ( model
            , readFiles files
            )

        ItemsDropped files ->
            ( model
            , readItems files
            )

        ReadmeReceived string ->
            ( { model
                | readme = Just string
                , page = Readme
              }
            , Nav.replaceUrl model.key "/"
            )

        ModulesReceived value ->
            case Decode.decodeValue (Decode.list Docs.decoder) value of
                Ok modules ->
                    let
                        modulesNames =
                            List.map .name modules

                        ( newPage, cmd ) =
                            case model.page of
                                Module module_ ->
                                    if List.member module_ modulesNames then
                                        ( Module module_, Cmd.none )

                                    else
                                        ( Readme, Nav.replaceUrl model.key "/" )

                                _ ->
                                    ( Readme, Cmd.none )
                    in
                    ( { model
                        | modules = modules
                        , page = newPage
                      }
                    , cmd
                    )

                Err err ->
                    ( model, Cmd.none )

        UrlRequested request ->
            case request of
                Internal url ->
                    ( model
                    , case url.fragment of
                        Just _ ->
                            -- scroll to anchor
                            Nav.load (Url.toString url)

                        Nothing ->
                            Nav.pushUrl model.key (Url.toString url)
                    )

                External url ->
                    ( model
                    , Nav.load url
                    )

        UrlChanged url ->
            let
                modules =
                    List.map .name model.modules

                module_ =
                    urlToModule url
            in
            case List.member module_ modules of
                True ->
                    ( { model | page = Module module_ }
                    , Cmd.none
                    )

                False ->
                    ( { model | page = Readme }
                    , Cmd.none
                    )


urlToModule : Url -> String
urlToModule url =
    url.path
        |> String.split "/"
        |> List.reverse
        |> List.head
        |> Maybe.withDefault url.path
        |> String.replace "-" "."


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ readmeReceived ReadmeReceived
        , modulesReceived ModulesReceived
        ]



-- MAIN


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }
