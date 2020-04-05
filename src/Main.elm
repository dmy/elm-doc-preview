module Main exposing (main)

{-|

@docs main

-}

import Browser
import Browser.Navigation as Nav
import Elm.Project as Project exposing (Project)
import Elm.Version as Version exposing (Version)
import Json.Decode as Decode
import Json.Encode as Encode
import Page.Diff as Diff
import Page.Docs as Docs
import Page.Problem as Problem
import Page.Search as Search
import Ports
import Session
import Skeleton
import Time
import Url
import Url.Parser as Parser exposing ((</>), Parser, custom, fragment, map, oneOf, s, top)



-- MAIN


{-| -}
main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }



-- MODEL


type alias Model =
    { key : Nav.Key
    , page : Page
    }


type Page
    = NotFound Session.Data
    | Search Search.Model
    | Docs Docs.Model
    | Diff Diff.Model



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.onReadme OnReadme
        , Ports.onDocs OnDocs
        , Ports.onManifest OnManifest
        , Ports.locationHrefRequested LinkClicked
        ]



-- VIEW


view : Model -> Browser.Document Msg
view model =
    case model.page of
        NotFound _ ->
            Skeleton.view never
                { title = "Not Found"
                , header = []
                , warning = Skeleton.NoProblems
                , attrs = Problem.styles
                , kids = Problem.notFound
                }

        Search search ->
            Skeleton.view SearchMsg (Search.view search)

        Docs docs ->
            Skeleton.view DocsMsg (Docs.view docs)

        Diff diff ->
            Skeleton.view never (Diff.view diff)



-- INIT


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    stepUrl url
        { key = key
        , page = NotFound Session.empty
        }



-- UPDATE


type Msg
    = LinkClicked String
    | UrlRequested Browser.UrlRequest
    | UrlChanged Url.Url
    | SearchMsg Search.Msg
    | DiffMsg Diff.Msg
    | DocsMsg Docs.Msg
    | OnReadme Ports.Readme
    | OnDocs Ports.Docs
    | OnManifest Ports.Manifest


update : Msg -> Model -> ( Model, Cmd Msg )
update message model =
    case message of
        UrlRequested request ->
            -- Url requests are intercepted by javascript
            -- and handled by LinkClicked to work-around
            -- unhandled links in markdown blocks and fix
            -- absolute https://package.elm-lang.org/packages links.
            ( model, Cmd.none )

        LinkClicked href ->
            ( model, requestHref model.key href )

        UrlChanged url ->
            stepUrl url model

        SearchMsg msg ->
            case model.page of
                Search search ->
                    stepSearch model (Search.update msg search)

                _ ->
                    ( model, Cmd.none )

        DiffMsg msg ->
            case model.page of
                Diff diff ->
                    stepDiff model (Diff.update msg diff)

                _ ->
                    ( model, Cmd.none )

        DocsMsg msg ->
            case model.page of
                Docs docs ->
                    stepDocs model (Docs.update msg docs)

                _ ->
                    ( model, Cmd.none )

        OnReadme readme ->
            ( updateReadme readme model, Cmd.none )

        OnDocs docs ->
            ( updateDocs docs model, Cmd.none )

        OnManifest manifest ->
            ( updateManifest manifest model, Cmd.none )


requestHref : Nav.Key -> String -> Cmd msg
requestHref navKey href =
    case Url.fromString href of
        Just url ->
            -- Complete URL are expected to be external
            Nav.load href

        Nothing ->
            if String.startsWith "/source/" href then
                Nav.load href

            else
                Nav.pushUrl navKey href


stepSearch : Model -> ( Search.Model, Cmd Search.Msg ) -> ( Model, Cmd Msg )
stepSearch model ( search, cmds ) =
    ( { model | page = Search search }
    , Cmd.map SearchMsg cmds
    )


stepDocs : Model -> ( Docs.Model, Cmd Docs.Msg ) -> ( Model, Cmd Msg )
stepDocs model ( docs, cmds ) =
    ( { model | page = Docs docs }
    , Cmd.map DocsMsg cmds
    )


stepDiff : Model -> ( Diff.Model, Cmd Diff.Msg ) -> ( Model, Cmd Msg )
stepDiff model ( diff, cmds ) =
    ( { model | page = Diff diff }
    , Cmd.map DiffMsg cmds
    )



-- WEBSOCKET UPDATES


updateReadme : Ports.Readme -> Model -> Model
updateReadme { author, project, version, readme } model =
    case Version.fromString version of
        Just v ->
            updatePageReadme author project v readme model

        Nothing ->
            model


updatePageReadme : String -> String -> Version -> String -> Model -> Model
updatePageReadme author project version readme model =
    let
        newSession =
            Session.addReadme author project version readme (exit model)

        newPage =
            case model.page of
                Docs m ->
                    Docs (Docs.updateReadme author project version readme m)

                _ ->
                    setPageSession newSession model.page
    in
    { model | page = newPage }


updateDocs : Ports.Docs -> Model -> Model
updateDocs { author, project, version, docs } model =
    case ( Version.fromString version, Decode.decodeValue Session.docsDecoder docs ) of
        ( Just v, Ok docs_ ) ->
            updatePageDocs author project v docs_ model

        _ ->
            model


updatePageDocs : String -> String -> Version -> Session.Docs -> Model -> Model
updatePageDocs author project version docs model =
    let
        newSession =
            Session.addDocs author project version docs (exit model)

        newPage =
            case model.page of
                Docs m ->
                    Docs (Docs.updateDocs author project version docs m)

                _ ->
                    setPageSession newSession model.page
    in
    { model | page = newPage }


updateManifest : Ports.Manifest -> Model -> Model
updateManifest { author, project, version, timestamp, manifest } model =
    case ( Version.fromString version, Decode.decodeValue Project.decoder manifest ) of
        ( Just v, Ok manifest_ ) ->
            updatePageManifest author project v manifest_ model

        _ ->
            model


updatePageManifest : String -> String -> Version -> Project -> Model -> Model
updatePageManifest author project version manifest model =
    let
        newSession =
            Session.addManifest author project version manifest (exit model)

        newPage =
            case model.page of
                Docs m ->
                    Docs (Docs.updateManifest author project version manifest m)

                _ ->
                    setPageSession newSession model.page
    in
    { model | page = newPage }


setPageSession : Session.Data -> Page -> Page
setPageSession session page =
    case page of
        NotFound _ ->
            NotFound session

        Search m ->
            Search { m | session = session }

        Diff m ->
            Diff { m | session = session }

        Docs m ->
            Docs { m | session = session }



-- EXIT


exit : Model -> Session.Data
exit model =
    case model.page of
        NotFound session ->
            session

        Search m ->
            m.session

        Docs m ->
            m.session

        Diff m ->
            m.session



-- ROUTER


stepUrl : Url.Url -> Model -> ( Model, Cmd Msg )
stepUrl url model =
    let
        session =
            exit model

        parser =
            oneOf
                [ route top
                    (stepSearch model (Search.init session))
                , route (s "packages" </> author_ </> project_)
                    (\author project ->
                        stepDiff model (Diff.init session author project)
                    )
                , route (s "packages" </> author_ </> project_ </> version_ </> focus_)
                    (\author project version focus ->
                        stepDocs model (Docs.init session author project version focus)
                    )
                ]
    in
    case Parser.parse parser url of
        Just answer ->
            answer

        Nothing ->
            ( { model | page = NotFound session }
            , Cmd.none
            )


route : Parser a b -> a -> Parser (b -> c) c
route parser handler =
    Parser.map handler parser


author_ : Parser (String -> a) a
author_ =
    custom "AUTHOR" Just


project_ : Parser (String -> a) a
project_ =
    custom "PROJECT" Just


version_ : Parser (Maybe Version -> a) a
version_ =
    custom "VERSION" <|
        \string ->
            if string == "latest" then
                Just Nothing

            else
                Maybe.map Just (Version.fromString string)


focus_ : Parser (Docs.Focus -> a) a
focus_ =
    oneOf
        [ map Docs.Readme top
        , map Docs.Module (moduleName_ </> fragment identity)
        ]


moduleName_ : Parser (String -> a) a
moduleName_ =
    custom "MODULE" (Just << String.replace "-" ".")
