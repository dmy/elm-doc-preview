port module Main exposing (main)

import Block
import Browser exposing (UrlRequest(..))
import Browser.Dom as Dom
import Browser.Navigation as Nav
import Elm.Docs as Docs
import Elm.Error as Error
import Elm.Type as Type
import Errors exposing (viewError)
import File exposing (File)
import File.Select as Select
import Howto exposing (howto, howtoWithModules)
import Html exposing (Html, a, div, h1, input, li, span, text, ul)
import Html.Attributes exposing (class, href, id, placeholder, style, title, value)
import Html.Events exposing (on, onClick, onInput, preventDefaultOn)
import Html.Extra as Html exposing (viewIf)
import Http
import Json.Decode as Decode exposing (Decoder)
import Markdown
import Maybe.Extra as Maybe
import Regex
import Svg exposing (svg)
import Svg.Attributes exposing (d, fill, height, viewBox, width)
import Task
import Url exposing (Url)
import Url.Builder
import Url.Parser exposing (Parser)
import Url.Parser.Query as Query
import Utils.Markdown as Markdown



-- PORTS
--
-- Urls changes are intercepted by javascript to work-around
-- https://github.com/elm-explorations/markdown/issues/1
-- See https://github.com/dmy/elm-doc-preview/issues/1
--
-- Local documentation is stored in local storage to improve
-- navigation (mainly when going back from external links).


port locationHrefRequested : (String -> msg) -> Sub msg


port compilationCompleted : (String -> msg) -> Sub msg


port readmeUpdated : (String -> msg) -> Sub msg


port docsUpdated : (String -> msg) -> Sub msg


port storeReadme : String -> Cmd msg


port storeDocs : String -> Cmd msg


port clearStorage : () -> Cmd msg



-- TYPES


type Msg
    = Ignored String
    | CompilationCompleted String
    | OpenFilesClicked
    | GotFiles File (List File)
    | ClosePreviewClicked
    | DocsLoaded String
    | DocsRequestCompleted (Result Http.Error String)
    | ReadmeLoaded String
    | ReadmeRequestCompleted (Result Http.Error String)
    | FilterChanged String
    | LocationHrefRequested String
    | UrlRequested UrlRequest
    | UrlChanged Url


type alias Model =
    { readme : Maybe String
    , modules : List Docs.Module
    , navKey : Nav.Key
    , url : Url
    , page : Page
    , source : Source
    , online : Bool
    , error : Maybe Error.Error
    , filter : String
    }


type Page
    = Readme
    | Module String


type Source
    = Local
    | Remote LoadingState Repo


type LoadingState
    = Loading
    | LoadingReadme
    | LoadingDocs
    | Loaded


type alias Repo =
    { name : String
    , version : String
    }


type alias Flags =
    { readme : Maybe String
    , docs : Maybe String
    , online : Bool
    }



-- INIT


init : Flags -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url navKey =
    let
        source =
            urlToSource url

        ( readme, modules ) =
            initDoc source flags
    in
    ( { readme = readme
      , modules = modules
      , navKey = navKey
      , url = url
      , page = urlToPage url
      , source = source
      , online = flags.online
      , error = Nothing
      , filter = ""
      }
    , Cmd.batch
        [ focusOpenFilesLink
        , getDoc source
        , scrollToFragment url
        ]
    )


initDoc : Source -> Flags -> ( Maybe String, List Docs.Module )
initDoc source flags =
    case source of
        Remote _ _ ->
            ( Nothing, [] )

        Local ->
            ( flags.readme
            , flags.docs
                |> Maybe.map decodeDocs
                |> Maybe.withDefault []
            )


focusOpenFilesLink : Cmd Msg
focusOpenFilesLink =
    Task.attempt (\_ -> Ignored "focus") (Dom.focus "open-link")


urlToSource : Url -> Source
urlToSource url =
    Url.Parser.parse repoParser { url | path = "" }
        |> Maybe.join
        |> Maybe.map (Remote Loading)
        |> Maybe.withDefault Local


repoParser : Parser (Maybe Repo -> Maybe Repo) (Maybe Repo)
repoParser =
    Url.Parser.query <|
        Query.map2 repoParserHelper
            (Query.string "repo")
            (Query.string "version")


repoParserHelper : Maybe String -> Maybe String -> Maybe Repo
repoParserHelper maybeRepo maybeVersion =
    case ( maybeRepo, maybeVersion ) of
        ( Just repo, Just version ) ->
            Just (Repo repo version)

        ( Just repo, Nothing ) ->
            Just (Repo repo "master")

        _ ->
            Nothing


getDoc : Source -> Cmd Msg
getDoc source =
    case source of
        Remote _ repo ->
            Cmd.batch
                [ Http.get
                    { url = githubFileUrl repo "docs.json"
                    , expect = Http.expectString DocsRequestCompleted
                    }
                , Http.get
                    { url = githubFileUrl repo "README.md"
                    , expect = Http.expectString ReadmeRequestCompleted
                    }
                , clearStorage ()
                ]

        Local ->
            Cmd.none


githubFileUrl : Repo -> String -> String
githubFileUrl repo file =
    Url.Builder.crossOrigin "https://raw.githubusercontent.com"
        [ repo.name
        , repo.version
        , file
        ]
        []


sourceQuery : Source -> String
sourceQuery source =
    case source of
        Remote _ repo ->
            Url.Builder.toQuery
                [ Url.Builder.string "repo" repo.name
                , Url.Builder.string "version" repo.version
                ]

        Local ->
            ""



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
            , stopDragOver
            , preventDefaultOn "drop"
                (Decode.map alwaysPreventDefault dropDecoder)
            ]
            [ viewMain model
            , footer
            ]
        ]
    }


viewMain : Model -> Html Msg
viewMain model =
    div
        [ class "center"
        , style "flex" "1"
        , style "flex-wrap" "wrap-reverse"
        , style "display" "flex"
        , style "align-items" "flex-end"
        ]
        [ case ( model.error, isLoading model ) of
            ( Just error, _ ) ->
                compilationError error

            ( Nothing, True ) ->
                spinner

            _ ->
                page model
        , navigation model
        ]


dropDecoder : Decoder Msg
dropDecoder =
    Decode.at [ "dataTransfer", "files" ]
        (Decode.oneOrMore GotFiles File.decoder)


stopDragOver : Html.Attribute Msg
stopDragOver =
    preventDefaultOn "dragover"
        (Decode.map alwaysPreventDefault (Decode.succeed <| Ignored "dragover"))


alwaysPreventDefault : msg -> ( msg, Bool )
alwaysPreventDefault msg =
    ( msg, True )


isLoading : Model -> Bool
isLoading model =
    -- Offline, waiting for websocket update
    if not model.online && model.readme == Nothing then
        True

    else
        case model.source of
            Remote Loading _ ->
                True

            Remote LoadingReadme _ ->
                True

            Remote LoadingDocs _ ->
                True

            _ ->
                False


page : Model -> Html Msg
page model =
    div [ class "block-list" ] <|
        case ( model.page, model.readme, model.modules ) of
            ( Readme, Just readme, _ ) ->
                [ Markdown.block readme ]

            ( Readme, Nothing, [] ) ->
                [ Markdown.block howto ]

            ( Readme, Nothing, _ ) ->
                [ Markdown.block howtoWithModules ]

            ( Module name, _, modules ) ->
                case List.filter (\m -> m.name == name) modules of
                    currentModule :: _ ->
                        doc model.filter
                            model.modules
                            currentModule
                            (sourceQuery model.source)

                    _ ->
                        [ h1 [] [ text "Error" ]
                        , text ("Module \"" ++ name ++ "\" not found.")
                        ]


spinner : Html msg
spinner =
    div [ class "block-list" ] <|
        [ div [ class "spinner" ]
            [ div [ class "bounce1" ] []
            , div [ class "bounce2" ] []
            , div [ class "bounce3" ] []
            ]
        ]


compilationError : Error.Error -> Html msg
compilationError error =
    div
        [ class "block-list"
        , style "margin-top" "24px"
        ]
        [ viewError error ]


doc : String -> List Docs.Module -> Docs.Module -> String -> List (Html msg)
doc filter modules currentModule query =
    let
        info =
            Block.makeInfo currentModule.name modules query
    in
    h1 [ class "block-list-title" ] [ text currentModule.name ]
        :: List.map (Block.view filter info) (Docs.toBlocks currentModule)



-- Side navigation bar


navigation : Model -> Html Msg
navigation model =
    div [ class "pkg-nav" ]
        [ logo
        , viewIf (model.online && not (isLoading model)) <|
            openLink
        , viewIf model.online <|
            closeLink model
        , viewIf (model.readme /= Nothing) <|
            navLinks model.source model.page [ Readme ]
        , browseSourceLink model.source
        , filterBox model.filter model.modules
        , if String.isEmpty model.filter then
            model.modules
                |> List.map (\m -> Module m.name)
                |> navLinks model.source model.page

          else
            search model.source model.page model.filter model.modules
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


openLink : Html Msg
openLink =
    div []
        [ a
            [ id "open-link"
            , style "cursor" "pointer"
            , href ""
            , onEnterOrSpace OpenFilesClicked
            , onClick OpenFilesClicked
            ]
            [ text "Open Files" ]
        ]


closeLink : Model -> Html Msg
closeLink model =
    if model.readme == Nothing && model.modules == [] then
        Html.nothing

    else
        div [ style "margin-bottom" "10px" ]
            [ a
                [ style "cursor" "pointer"
                , href "/"
                , onClick ClosePreviewClicked
                ]
                [ text "Close Preview" ]
            ]


browseSourceLink : Source -> Html Msg
browseSourceLink source =
    case source of
        Local ->
            Html.nothing

        Remote _ repo ->
            div []
                [ a
                    [ style "margin-top" "20px"
                    , style "cursor" "pointer"
                    , href (githubSource repo)
                    ]
                    [ text "Browse Source" ]
                ]


filterBox : String -> List Docs.Module -> Html Msg
filterBox filter modules =
    input
        [ placeholder "Filter regex"
        , value filter
        , onInput FilterChanged
        ]
        []


search : Source -> Page -> String -> List Docs.Module -> Html Msg
search source currentPage filter modules =
    ul []
        (List.filterMap (searchModule source currentPage filter) modules)


searchModule : Source -> Page -> String -> Docs.Module -> Maybe (Html Msg)
searchModule source currentPage filter m =
    let
        results =
            List.concat
                [ searchFrom m.binops filter
                , searchFrom m.unions filter
                , searchFrom m.aliases filter
                , searchFrom m.values filter
                ]
    in
    if List.isEmpty results then
        Nothing

    else
        Just <|
            li [ class "pkg-nav-search-chunk" ]
                [ pageLink source currentPage (Module m.name)
                , ul [] (List.map (searchResult source m.name) results)
                ]


searchFrom : List { r | name : String } -> String -> List String
searchFrom records filter =
    List.filterMap
        (\r ->
            if contains filter r.name then
                Just r.name

            else
                Nothing
        )
        records


contains : String -> String -> Bool
contains pattern str =
    pattern
        |> Regex.fromStringWith { caseInsensitive = True, multiline = False }
        |> Maybe.map (\regex -> Regex.contains regex str)
        |> Maybe.withDefault False


searchResult : Source -> String -> String -> Html Msg
searchResult source module_ symbol =
    resultLink source module_ symbol


githubSource : Repo -> String
githubSource repo =
    Url.Builder.crossOrigin "https://github.com"
        [ repo.name
        , "tree"
        , repo.version
        ]
        []


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


navLinks : Source -> Page -> List Page -> Html msg
navLinks source currentPage pages =
    ul []
        (List.map (pageLink source currentPage) pages)


pageLink : Source -> Page -> Page -> Html msg
pageLink source currentPage targetPage =
    li []
        [ a
            [ class "pkg-nav-module"
            , href (pagePath targetPage ++ sourceQuery source)
            , styleIf (currentPage == targetPage) "font-weight" "bold"
            , styleIf (currentPage == targetPage) "text-decoration" "underline"
            ]
            [ case targetPage of
                Readme ->
                    text "README"

                Module name ->
                    text name
            ]
        ]


resultLink : Source -> String -> String -> Html Msg
resultLink source module_ symbol =
    li []
        [ a
            [ class "pkg-nav-module"
            , (href << String.concat) <|
                [ pagePath (Module module_)
                , sourceQuery source
                , "#"
                , symbol
                ]
            ]
            [ text symbol
            ]
        ]


pagePath : Page -> String
pagePath page_ =
    case page_ of
        Module name ->
            "/" ++ slugify name

        Readme ->
            "/"


styleIf : Bool -> String -> String -> Html.Attribute msg
styleIf cond property value =
    if cond then
        style property value

    else
        style "" ""


slugify : String -> String
slugify str =
    String.replace "." "-" str


unslugify : String -> String
unslugify str =
    String.replace "-" "." str



-- Footer


footer : Html msg
footer =
    div [ class "footer" ]
        [ span []
            [ text "elm-doc-preview is "
            , a
                [ class "grey-link"
                , href "https://github.com/dmy/elm-doc-preview"
                ]
                [ text "open source." ]
            ]
        , text " "
        , span [] [ text "Copyright © 2018 Rémi Lefèvre." ]
        ]



-- Files handling


selectFiles : Cmd Msg
selectFiles =
    Select.files
        -- Browsers do not agree on mime types :/
        [ "text/plain", "text/markdown", "application/json", ".md" ]
        GotFiles


readFiles : List File -> Cmd Msg
readFiles files =
    Cmd.batch (List.map readFile files)


readFile : File -> Cmd Msg
readFile file =
    case ( File.name file, File.mime file ) of
        ( "README.md", _ ) ->
            Task.perform ReadmeLoaded (File.toString file)

        ( "docs.json", "application/json" ) ->
            Task.perform DocsLoaded (File.toString file)

        _ ->
            Cmd.none


decodeDocs : String -> List Docs.Module
decodeDocs docs =
    case Decode.decodeString (Decode.list Docs.decoder) docs of
        Ok modules ->
            modules

        Err _ ->
            []



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Ignored _ ->
            ( model, Cmd.none )

        CompilationCompleted error ->
            ( setError error model, Cmd.none )

        OpenFilesClicked ->
            ( model, selectFiles )

        GotFiles file files ->
            ( { model | source = Local }, readFiles (file :: files) )

        ClosePreviewClicked ->
            ( closePreview model, clearStorage () )

        DocsLoaded docs ->
            ( setModules (decodeDocs docs) model
            , Cmd.batch
                [ scrollToFragment model.url
                , storeDocs docs
                ]
            )

        DocsRequestCompleted (Ok docs) ->
            ( setModules (decodeDocs docs) model, scrollToFragment model.url )

        DocsRequestCompleted (Err error) ->
            ( setModules [] model, Cmd.none )

        ReadmeLoaded readme ->
            ( setReadme (Just readme) model
            , Cmd.batch
                [ scrollToFragment model.url
                , storeReadme readme
                ]
            )

        ReadmeRequestCompleted (Ok readme) ->
            ( setReadme (Just readme) model, scrollToFragment model.url )

        ReadmeRequestCompleted (Err error) ->
            ( setReadme Nothing model, Cmd.none )

        FilterChanged filterValue ->
            ( { model | filter = filterValue }, Cmd.none )

        LocationHrefRequested href ->
            ( model, requestLocationHref model.navKey href )

        UrlRequested request ->
            -- Url requests are intercepted by javascript
            -- and handled by LocationHrefRequested to work-around
            -- unhandled links in markdown blocks.
            ( model, Cmd.none )

        UrlChanged url ->
            ( { model | page = urlToPage url, url = url }
            , addUrlQuery model url
            )


addUrlQuery : Model -> Url -> Cmd Msg
addUrlQuery model url =
    case ( url /= model.url, sourceQuery model.source ) of
        ( False, _ ) ->
            Cmd.none

        ( True, "" ) ->
            scrollToFragment url

        ( True, query ) ->
            Nav.replaceUrl model.navKey <|
                Url.toString <|
                    { url | query = Just (String.dropLeft 1 query) }


setError : String -> Model -> Model
setError errorJsonString model =
    case Decode.decodeString Error.decoder errorJsonString of
        Ok error ->
            { model | error = Just error }

        Err _ ->
            { model | error = Nothing }


setReadme : Maybe String -> Model -> Model
setReadme readme model =
    { model
        | readme = readme
        , source =
            case model.source of
                Remote Loading repo ->
                    Remote LoadingDocs repo

                Remote LoadingReadme repo ->
                    Remote Loaded repo

                _ ->
                    model.source
    }


setModules : List Docs.Module -> Model -> Model
setModules modules model =
    { model
        | modules = modules
        , source =
            case model.source of
                Remote Loading repo ->
                    Remote LoadingReadme repo

                Remote LoadingDocs repo ->
                    Remote Loaded repo

                _ ->
                    model.source
    }


scrollToFragment : Url -> Cmd Msg
scrollToFragment url =
    case url.fragment of
        Just id ->
            Dom.getElement id
                |> Task.andThen (\e -> Dom.setViewport 0 e.element.y)
                |> Task.attempt (\_ -> Ignored "scroll")

        Nothing ->
            Cmd.none


closePreview : Model -> Model
closePreview model =
    { model
        | readme = Nothing
        , modules = []
        , page = Readme
        , source = Local
        , error = Nothing
        , filter = ""
    }


requestLocationHref : Nav.Key -> String -> Cmd Msg
requestLocationHref navKey href =
    case Url.fromString href of
        Just url ->
            -- Complete URL are expected to be external
            Nav.load href

        Nothing ->
            Nav.pushUrl navKey href


urlToPage : Url -> Page
urlToPage url =
    case url.path of
        "/" ->
            Readme

        _ ->
            url.path
                |> String.dropLeft 1
                |> unslugify
                |> Module



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ locationHrefRequested LocationHrefRequested
        , compilationCompleted CompilationCompleted
        , readmeUpdated ReadmeLoaded
        , docsUpdated DocsLoaded
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
